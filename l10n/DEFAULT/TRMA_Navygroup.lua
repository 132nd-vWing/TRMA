------------------------------------------------------------------
-- CARRIER SCRIPT rev 3.6 (marshal beta)
------------------------------------------------------------------
env.info("[Carrier Ops] Script loading 3.6")

------------------------------------------------------------------
-- CONFIGURATION / CONSTANTS
------------------------------------------------------------------
local debug = false

local RecoveryStartMinute = 25        -- 20 Real-World Cycle Start minute
local RecoveryDuration = 32           -- 32 cycle duration minutes
local RecoveryOpenOffset = 5          -- 5  window open offset 
local RecoveryCloseOffset = 30        -- 30 window close offset
local RecoveryTurnOutOffset = 32      -- 32 ship turnout offset (marshal reset)

local HPA_TO_INHG   = 0.02953
local MMHG_TO_HPA   = 1.33322
local MPS_TO_KNOTS  = 1.94384
local MAGVAR_EAST_DEG = 4             -- Static magvar; TRMA 4, OPAC 10

------------------------------------------------------------------
-- GLOBAL TABLES / STATE
------------------------------------------------------------------
local carrier_info = { weather = {}, ship = {}, recovery= {}, marshal= { stack = {}, assigned_minutes = {} } } 

local carrier_name = "CVN-73"         -- DCS unit name (unit, not group)
local tanker_name = "CVN73_Tanker#IFF:5327FR" -- DCS tanker unit name

local carrier_unit = UNIT:FindByName(carrier_name)  -- find the ME unit
local carrier_navygroup = NAVYGROUP:New(carrier_name):SetPatrolAdInfinitum():Activate() -- spawn the carrier
local marshal_zone = ZONE_UNIT:New("MarshalZone", carrier_unit, UTILS.NMToMeters(60)) -- define the marshal zone
local clients = SET_CLIENT:New():FilterActive(true):FilterCoalitions("blue"):FilterStart() -- capture spawned clients

local recovery_tanker = nil
local carrier_root_menu = nil  
local carrier_admin_menu = nil
local cycle_extend_menu = nil
-- local carrier_lights_menu = nil

------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------

-- Broadcaster to clients within Marshal Zone
local function BroadcastMessageToZone(message)
  if not marshal_zone then return end

  clients:ForEachClientInZone(marshal_zone, function(client)
    MESSAGE:New(message, 15):ToClient(client)
  end)
end

-- Logs
local function log(message) env.info("[Carrier Ops] " .. message) end

-- Magvar for East offset
local function trueToMag(true_deg) return (true_deg - MAGVAR_EAST_DEG) % 360 end

-- QNH (mmHg -> hPa -> inHg)
local function getQNH(weather)
  local mmHg     = weather.qnh or 762.762
  local qnh_hpa  = mmHg * MMHG_TO_HPA
  local qnh_inhg = qnh_hpa * HPA_TO_INHG
  return qnh_hpa, qnh_inhg
end

-- Wind at ground
local function getWindDataAtGroundLevel(weather)
  local wind_data     = weather.wind.atGround
  local wind_speed_mps= wind_data.speed
  local wind_to_true  = wind_data.dir
  local wind_from_true= (wind_to_true + 180) % 360
  local wind_speed_kn = wind_speed_mps * MPS_TO_KNOTS
  return trueToMag(wind_from_true), wind_speed_kn
end

-- UTC time
local function getUtcEpoch()
  return os.time(os.date("!*t"))
end

-- Sun times checker DCS does wierd things for sunrise/sunset
local function IsValidClockString(t)
  return type(t) == "string" and t:match("^%d%d:%d%d:%d%d$")
end

-- Next Recovery Window
local function nextRecoveryStartup()
  local now = getUtcEpoch()
  local t = os.date("!*t", now)
  t.min, t.sec = RecoveryStartMinute, 0

  local start_utc = os.time(t)
  if start_utc <= now then start_utc = start_utc + 3600 end

  local r = carrier_info.recovery
  r.state         = "IDLE"
  r.start_utc     = start_utc
  r.end_utc       = start_utc + RecoveryDuration * 60
  r.open_utc      = start_utc + RecoveryOpenOffset * 60
  r.close_utc     = start_utc + RecoveryCloseOffset * 60
  r.turnout_utc   = start_utc + RecoveryTurnOutOffset * 60
  r.open_reported = false
  r.close_reported= false
end


------------------------------------------------------------------
-- CARRIER ENVIRONMENT (weather, ship data)
------------------------------------------------------------------

local function updateCarrierWeather()
  if not carrier_unit or not carrier_unit:IsAlive() then return end

  local weather = env.mission.weather
  local qnh_hpa, qnh_inhg = getQNH(weather)
  local wind_dir_mag, wind_speed_knots = getWindDataAtGroundLevel(weather)
  local cloud_base = weather.clouds.base or 0
  local visibility = weather.visibility.distance or 0
  if weather.fog and weather.fog.thickness > 0 then
    local fog_vis = weather.fog.visibility or 0
    visibility = math.min(visibility, fog_vis)
  end

  -- Daylight at boat
  local coord = carrier_unit:GetCoordinate()
  local sunrise_raw = coord:GetSunrise()
  local sunset_raw = coord:GetSunset()
  local missionDate = env.mission.date
  local month = missionDate.Month
  local isNight
  local now = timer.getAbsTime() % 86400
  local sunrise_ok = IsValidClockString(sunrise_raw)
  local sunset_ok  = IsValidClockString(sunset_raw)

  if not sunrise_ok or not sunset_ok then
    -- Polar or undefined sun state
    if month == 6 or month == 7 or month == 8 then
      isNight = false
    elseif month == 11 or month == 12 or month == 1 then
      isNight = true
    else
      isNight = false
    end
  else
    local sunrise = UTILS.ClockToSeconds(sunrise_raw)
    local sunset  = UTILS.ClockToSeconds(sunset_raw)

    local night_start = sunset + 1800
    local night_end   = sunrise - 1800
    isNight = (now >= night_start) or (now <= night_end)
  end

  -- CASE logic
  local carrier_case
  if isNight then
    carrier_case = "III"
  elseif cloud_base > 914 and visibility > 9260 then  -- >3000ft >5nm
    carrier_case = "I"
  elseif cloud_base >= 305 and cloud_base <= 914 and visibility > 9260 then -- 1000-3000ft >5nm
    carrier_case = "II"
  else
    carrier_case = "III"
  end

  -- Weather info update
  carrier_info.weather = {
    cloud_base    = cloud_base,
    visibility    = visibility,
    vis_report    = visibility >= 10000 and "10+ km" or (visibility >= 1000 and string.format("%d km", math.floor(visibility / 1000)) or string.format("%d meters", visibility)),
    wind_dir      = wind_dir_mag,
    wind_speed    = wind_speed_knots,
    temperature   = weather.season.temperature or 15,
    qnh_hpa       = qnh_hpa,
    qnh_inhg      = qnh_inhg,
    case          = carrier_case,
  }

  if debug then 
    log(string.format(
      "WeatherInfo: gt=%s | sunrise=%s | sunset=%s | case=%s | cloud=%s | vis=%s | wind_dir=%s | wind_spd=%s",
      UTILS.SecondsToClock(now),
      sunrise_raw,
      sunset_raw,
      tostring(carrier_case),
      tostring(cloud_base), 
      tostring(visibility),
      tostring(wind_dir_mag), 
      tostring(wind_speed_knots)
    ))
  end
end

local function updateCarrierInfo()
  if not carrier_unit or not carrier_unit:IsAlive() then return end

  local heading_mag = trueToMag(math.floor(carrier_unit:GetHeading() + 0.5))
  local speed_knots  = carrier_unit:GetVelocityKNOTS()
  local brc_mag = trueToMag(math.floor(carrier_navygroup:GetHeadingIntoWind(0, 25) + 0.5))
  local fb_mag  = (brc_mag - 9 + 360) % 360  

  -- Ship data update
  carrier_info.ship = {
    heading_mag    = heading_mag,
    speed_knots    = speed_knots,
    brc_mag        = brc_mag,
    fb_mag         = fb_mag,
    wind_over_deck = (carrier_info.weather.wind_speed or 0) + speed_knots,
  }
 
  if debug then 
    log(string.format(
      "CarrierInfo: state=%s | start=%s | open=%s | close=%s | end=%s | turnout=%s",
      tostring(carrier_info.recovery.state),
      os.date("!%H:%M:%S", carrier_info.recovery.start_utc),
      os.date("!%H:%M:%S", carrier_info.recovery.open_utc),
      os.date("!%H:%M:%S", carrier_info.recovery.close_utc),
      os.date("!%H:%M:%S", carrier_info.recovery.end_utc), 
      os.date("!%H:%M:%S", carrier_info.recovery.turnout_utc)
    ))
  end
end

------------------------------------------------------------------
-- RECOVERY CYCLE CONTROL (UTC driven) 
------------------------------------------------------------------

-- Trigger MOOSE turnintowind mission.
local function startRecoveryCycle()
  local timenow = timer.getAbsTime()
  local duration = RecoveryDuration * 60
  local timeend  = timenow + duration

  -- Turn into wind 
  carrier_navygroup:AddTurnIntoWind(
    UTILS.SecondsToClock(timenow, false),
    UTILS.SecondsToClock(timeend, false),
    25, true
  )

end

-- Add extension to existing MOOSE mission
local function extendRecoveryCycle(minutes)
  if not carrier_info.recovery.end_utc then
    if debug then log("No active recovery cycle to extend.") end
    return
  end

  local extension_seconds = minutes * 60

  if carrier_navygroup:IsSteamingIntoWind() then 
    carrier_info.recovery.end_utc = carrier_info.recovery.end_utc + extension_seconds
    carrier_info.recovery.close_utc = carrier_info.recovery.close_utc + extension_seconds
    carrier_info.recovery.turnout_utc = carrier_info.recovery.turnout_utc + extension_seconds
    carrier_navygroup:ExtendTurnIntoWind(extension_seconds)
  
    if debug then log("Recovery cycle extended to " .. UTILS.SecondsToClock(carrier_info.recovery.end_utc, true)) end
  
    BroadcastMessageToZone("99, recovery window extended to " .. UTILS.SecondsToClock(carrier_info.recovery.close_utc,true))
  else
    BroadcastMessageToZone("No active recovery cycle to extend.")
  end
end

-- Cycle Controller
local function recoveryHeartbeat()
  if not carrier_unit or not carrier_unit:IsAlive() then return end
  updateCarrierInfo()

  local r = carrier_info.recovery
  local now_utc = getUtcEpoch()

  -- IDLE → TURNING_IN
  if r.state == "IDLE" and now_utc >= r.start_utc and not r.open_reported then
    startRecoveryCycle()
    trigger.action.setUserFlag("502", 2) -- lights to launch AC

    BroadcastMessageToZone(string.format(
      "99, %s Recovering from %s to %s zulu. Case %s. BRC %d, FB %d.",
      carrier_unit:GetName(),
      os.date("!%H:%M", r.open_utc),
      os.date("!%H:%M", r.close_utc),
      carrier_info.weather.case,
      carrier_info.ship.brc_mag,
      carrier_info.ship.fb_mag
    ))  

    r.open_reported = true
    r.state = "TURNING_IN"
    -- create extend menu
    cycle_extend_menu = MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Extend recovery cycle (5m)", carrier_admin_menu, function() extendRecoveryCycle(5) end )
    log("Recovery cycle started TURNING IN")

    -- Launch the tanker
    if recovery_tanker then
      recovery_tanker:Start()
      if debug then log("Recovery tanker launched") end
    end
  end

  -- TURNING_IN → OPEN
  if r.state == "TURNING_IN" and now_utc >= r.open_utc and carrier_navygroup:IsSteamingIntoWind() then
    trigger.action.setUserFlag("502", 3) -- lights to recover AC
    r.state = "OPEN"
    if debug then log("Recovery state → OPEN") end
  end

  -- OPEN → CLOSED
  if r.state == "OPEN" and now_utc >= r.close_utc and not r.close_reported then

    BroadcastMessageToZone(string.format(
      "99, %s Recovery CLOSED at %s.",
      carrier_unit:GetName(),
      os.date("!%H:%M", now_utc)
    ))

    r.close_reported = true
    r.state = "CLOSED"
    -- remove extend menu
    if cycle_extend_menu then
      cycle_extend_menu:Remove()
      cycle_extend_menu = nil
    end
    if debug then log("Recovery state → CLOSED") end
  end

  -- CLOSED → IDLE (turn downwind)
  if r.state == "CLOSED" and now_utc >= r.turnout_utc then
    carrier_unit:SetSpeed(UTILS.KnotsToMps(20), true)
    -- DCS bug, Recovery > anything needs OFF first
    trigger.action.setUserFlag("502", 0) 
    SCHEDULER:New(nil, function()
      trigger.action.setUserFlag("502", 1) 
    end, {}, 3)

    -- ClearMarshalAssignments()
    nextRecoveryStartup()
    log("Recovery cycle complete, scheduling next window")
  end
end

-- Forced Recovery Cycle
local function ForceRecoveryCycle(duration_minutes)
  local now = getUtcEpoch()
  local duration = duration_minutes * 60

  carrier_info.recovery = {
    state = "IDLE",
    start_utc   = now,
    end_utc     = now + duration,
    open_utc    = now + (RecoveryOpenOffset * 60),
    close_utc   = now + duration - (RecoveryDuration - RecoveryCloseOffset) * 60,
    turnout_utc = now + duration,

    open_reported  = false,
    close_reported = false,
  }

  BroadcastMessageToZone(string.format(
    "99, Recovery override. New cycle starts NOW and runs for %d minutes.",
    duration_minutes
  ))

  if debug then 
    log(string.format(
      "Manual recovery override: start=%s end=%s",
      os.date("!%H:%M:%S", carrier_info.recovery.start_utc),
      os.date("!%H:%M:%S", carrier_info.recovery.end_utc)
    )) 
  end
end

------------------------------------------------------------------
-- CARRIER SYSTEM CONFIGURATION (ICLS/TACAN/Link-4/ACLS)
------------------------------------------------------------------

-- Carrier Emitters / lights to NAV at start
local function configureCarrierSystems()
  if not carrier_unit then return end

  local beacon = carrier_unit:GetBeacon()
  carrier_unit:CommandActivateLink4(331, nil, "A73", 5)
  carrier_unit:CommandActivateACLS(nil, "A73", 5)
  carrier_unit:CommandSetFrequency(309.5)
  carrier_unit:SetSpeed(UTILS.KnotsToMps(16), true)
  trigger.action.setUserFlag("502", 1) -- lights to NAV

  beacon:ActivateICLS(13, "I73")
  beacon:ActivateTACAN(13, "X", "T73", true)

  -- This is a restart to harden an MP consistency issue. 
  SCHEDULER:New(nil, function()
    if carrier_unit and carrier_unit:IsAlive() then
      carrier_unit:CommandActivateLink4(331, nil, "A73", 5)
      carrier_unit:CommandActivateACLS(nil, "A73", 5)
      if debug then log(carrier_unit:GetName() .. " datalinks refreshed") end
    end
  end, {}, 60)

  if debug then log(carrier_unit:GetName() .. " systems configured") end
end


-- Tanker setup (It's launched from carrier cycle or menu)
local function setupRecoveryTanker()
  if not carrier_unit then return end
  local tanker = RECOVERYTANKER:New(carrier_unit, tanker_name)
  tanker:SetAltitude(10000)
  tanker:SetTACAN(64, 'SH7')
  tanker:SetRadio(282.5)
  tanker:SetUnlimitedFuel(true)
  tanker:SetTakeoffAir()
  tanker:SetCallsign(2,1)
  recovery_tanker = tanker
end

-- Tanker start stop menu function
local function controlRecoveryTanker()
  if not recovery_tanker then
    if debug then log("Recovery tanker not define.") end
    return
  end
  if recovery_tanker:IsRunning() then
    recovery_tanker:Stop()
    -- BroadcastMessageToZone("99, Recovery tanker off station.") 
  else 
    recovery_tanker:Start()
    -- BroadcastMessageToZone("99, Recovery tanker on station.") 
  end
end

-- Status report
local function reportCarrierInformation()
  local w = carrier_info.weather
  local s = carrier_info.ship
  local r = carrier_info.recovery

  local lines = {}

  table.insert(lines, string.format(
    "99, %s INFORMATION",
    carrier_unit:GetName() 
  ))

  table.insert(lines, string.format(
    "Case %s Wind %.0f° @ %.1f kts | Visibility %s | QNH %.2f inHg",
    w.case,
    w.wind_dir,
    w.wind_speed,
    w.vis_report,
    w.qnh_inhg
  ))

  table.insert(lines, string.format(
    "Ship: Hdg %d°M | Spd %.1f kts | BRC %d | FB %d",
    s.heading_mag,
    s.speed_knots,
    s.brc_mag,
    s.fb_mag
  ))

  if r.state ~= "IDLE" then
    table.insert(lines, string.format(
      "Recovering from %s to %s zulu",
      UTILS.SecondsToClock(r.open_utc, true):sub(1,5),
      UTILS.SecondsToClock(r.close_utc, true):sub(1,5)
    ))
  else
    table.insert(lines, string.format(
      "Next Recovery window: %s – %s zulu",
      UTILS.SecondsToClock(r.open_utc, true):sub(1,5),
      UTILS.SecondsToClock(r.close_utc, true):sub(1,5)
    ))
  end

  BroadcastMessageToZone(table.concat(lines, "\n"))
end







----------------------------------------------------------------
-- MARSHAL QUEUE
----------------------------------------------------------------

local function buildMarshalStack()
  local radialOffsets = { 0, 15, -15, 30, -30 }
  local angelsList    = { 6, 7, 8, 9 }

  local idCounter = 1

  for _, offset in ipairs(radialOffsets) do
      for _, angels in ipairs(angelsList) do
          
          local slot = {
              id            = idCounter,
              offset        = offset,               -- radial offset
              angles        = angels,               -- angels
              dme           = angels + 15,          -- DME rule
              occupant      = nil,                  -- modex/sidenumber
              approach_time = nil                   -- assigned later
          }

          table.insert(carrier_info.marshal.stack, slot)
          idCounter = idCounter + 1
      end
  end
end

local function IsMarshalRequired()
  local c = carrier_info.weather.case
  return c == "II" or c == "III"
end

local function FindApproachTime(carrier_info, AssignedMinutes)
    local now = getUtcEpoch()

    -- Rules
    local min_from_now     = now + (3 * 60)
    local min_before_open  = carrier_info.recovery.open_utc - (5 * 60)
    local max_before_close = carrier_info.recovery.close_utc - (7 * 60)

    local earliest = math.max(min_from_now, min_before_open)
    local latest   = max_before_close

    if earliest > latest then
        return nil -- no valid times
    end

    -- Round earliest up to the next full minute
    local t = earliest - (earliest % 60)

    -- Search minute-by-minute until we hit the limit
    while t <= latest do
        if not AssignedMinutes[t] then
            return t -- found a free minute
        end
        t = t + 60
    end

    return nil -- no free minute found
end

local function ShowMarshalStack()
  local lines = {}
  table.insert(lines, "MARSHAL STACK QUEUE:")

    -- Collect occupied slots
  local occupied = {}
  for _, slot in ipairs(carrier_info.marshal.stack) do
      if slot.occupant then
          table.insert(occupied, slot)
      end
  end

  -- Sort by occupant number (numeric ascending)
  table.sort(occupied, function(a, b)
      return tonumber(a.occupant) < tonumber(b.occupant)
  end)

  
  for _, slot in ipairs(occupied) do
    local actual_radial = (carrier_info.ship.fb_mag + 180 + slot.offset) % 360
    local appr = slot.approach_time and os.date("!%M", slot.approach_time) or "N/A"

    table.insert(lines, string.format(
      "%s mothers %d DME%d Angels %d approach minute %s",
      slot.occupant,
      actual_radial,
      slot.dme,
      slot.angles,
      appr
    ))
  end

  BroadcastMessageToZone(table.concat(lines, "\n"))
end

local function ShowMarshalInfo(sideNumber)
    for _, slot in ipairs(carrier_info.marshal.stack) do
        if slot.occupant == sideNumber then
          local actual_radial = (carrier_info.ship.fb_mag + 180 + slot.offset) % 360
          local appr = slot.approach_time and os.date("!%M", slot.approach_time) or "N/A"

          local text = string.format(
              "%s marshal on mothers %03d dme %02d angels %02d approach time %s",
              sideNumber,
              actual_radial,
              slot.dme,
              slot.angles,
              appr
          )

          BroadcastMessageToZone(text)
          return
        end
    end
    -- If no slot found
    BroadcastMessageToZone(sideNumber .. " not in queue, join first")
end

local function JoinMarshal(sideNumber)

    -- First: check if this sideNumber is already in the stack
    for _, slot in ipairs(carrier_info.marshal.stack) do
        if slot.occupant == sideNumber then
            -- Already assigned → just repeat their marshal info
            ShowMarshalInfo(sideNumber)
            return
        end
    end

    -- Find first empty slot
    local freeSlot = nil
    for _, slot in ipairs(carrier_info.marshal.stack) do
        if slot.occupant == nil then
            freeSlot = slot
            break
        end
    end

    if not freeSlot then
        BroadcastMessageToZone(sideNumber .. " stack full hold current position.")
        return
    end

    -- Find next valid approach time
    local t = FindApproachTime(carrier_info, carrier_info.marshal.assigned_minutes)
    if not t then
        BroadcastMessageToZone(sideNumber .. " approach not possible this cycle.")
        return
    end

    -- Assign
    freeSlot.occupant = sideNumber
    freeSlot.approach_time = t
    freeSlot.last_update = getUtcEpoch()
    carrier_info.marshal.assigned_minutes[t] = sideNumber

    -- Report assignment
    ShowMarshalInfo(sideNumber)
end

local function LeaveMarshal(sideNumber)
    for _, slot in ipairs(carrier_info.marshal.stack) do
        if slot.occupant == sideNumber then
            -- Free the minute
            if slot.approach_time then
                carrier_info.marshal.assigned_minutes[slot.approach_time] = nil
            end

            -- Clear slot
            slot.occupant = nil
            slot.approach_time = nil
            slot.last_update = nil

            BroadcastMessageToZone(sideNumber .. " vacated marshal queue.")
            return true
        end
    end

    return false -- modex not found in stack
end

local function UpdateMarshalTime(sideNumber)

    -- Step 1: find their slot
    local slot = nil
    for _, s in ipairs(carrier_info.marshal.stack) do
        if s.occupant == sideNumber then
            slot = s
            break
        end
    end

    if not slot then
        BroadcastMessageToZone(sideNumber .. " you are not in the marshal stack.")
        return
    end

    -- Step 2: find a new valid approach time
    local newTime = FindApproachTime(carrier_info, carrier_info.marshal.assigned_minutes)
    if not newTime then
        BroadcastMessageToZone(sideNumber .. " no new approach time available this cycle.")
        return
    end

    -- Step 3: free their old approach minute
    if slot.approach_time then
        carrier_info.marshal.assigned_minutes[slot.approach_time] = nil
    end


    -- Step 4: assign new time
    slot.approach_time = newTime
    slot.last_update = getUtcEpoch()
    carrier_info.marshal.assigned_minutes[newTime] = sideNumber

    -- Step 5: report updated marshal info
    ShowMarshalInfo(sideNumber)
end

local function ResetMarshalStack()
    -- Clear all slot occupants + approach times
    for _, slot in ipairs(carrier_info.marshal.stack) do
        slot.occupant = nil
        slot.approach_time = nil
    end

    -- Clear assigned minute lookup
    carrier_info.marshal.assigned_minutes = {}

    -- Optional: log/debug
    if debug then env.info("Marshal stack reset") end
end

local function MarshalHeartbeat() -- auto cleanup

    if not IsMarshalRequired() then
        return
    end
    
    local now = getUtcEpoch()

    for _, slot in ipairs(carrier_info.marshal.stack) do
        if slot.occupant and slot.approach_time then

            -- Grace window: 3 minutes after approach time
            local expiry = slot.approach_time + (3 * 60)

            if now > expiry then
                -- Auto-clear this slot
                carrier_info.marshal.assigned_minutes[slot.approach_time] = nil
                if debug then 
                  BroadcastMessageToZone(slot.occupant .. " removed from marshal.")
                end

                slot.occupant = nil
                slot.approach_time = nil
                slot.last_update = nil
            end
        end
    end
end

------------------------------------------------------------------
-- MENUS 
------------------------------------------------------------------

local function createMenus()
  carrier_root_menu = MENU_COALITION:New(coalition.side.BLUE, "Carrier Control")
  carrier_admin_menu = MENU_COALITION:New(coalition.side.BLUE, "Carrier Admin", carrier_root_menu)
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Carrier Information", carrier_root_menu, reportCarrierInformation)
  local marshal_root = MENU_COALITION:New(coalition.side.BLUE, "Marshal Options", carrier_root_menu)
  
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Start Recovery NOW (DEBUG)", carrier_admin_menu, function() ForceRecoveryCycle(30) end)
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Start CQ 90m Recovery", carrier_admin_menu, function() ForceRecoveryCycle(90) end)
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Start/Stop Recovery Tanker", carrier_admin_menu, controlRecoveryTanker)
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Show Marshal Stack", carrier_admin_menu, ShowMarshalStack)
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Clear Marshal Stack (DEBUG)", carrier_admin_menu, ResetMarshalStack)
  local carrier_lights_menu = MENU_COALITION:New(coalition.side.BLUE, "Set Carrier Lights", carrier_admin_menu)

  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Lights OFF", carrier_lights_menu, function() trigger.action.setUserFlag("502", 0) end)
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Lights NAV", carrier_lights_menu, function() trigger.action.setUserFlag("502", 1) end)
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Lights LAUNCH", carrier_lights_menu, function() trigger.action.setUserFlag("502", 2) end)
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Lights RECOVER", carrier_lights_menu, function() trigger.action.setUserFlag("502", 3) end)  

  -- MARHSAL MENUS
  local panthers_menu = MENU_COALITION:New(coalition.side.BLUE, "Panthers", marshal_root)
  local spectres_menu = MENU_COALITION:New(coalition.side.BLUE, "Spectres", marshal_root)

  -- SIDENUMBER LISTS
  local panthers = { 300, 310, 320, 330 }   -- 30x / 31x / 32x / 33x
  local spectres = { 200, 210, 220 }             -- 20x / 21x

  local function BuildMarshalLeafMenu(parentMenu, block)
      -- First level: the block (e.g. "300")
      local blockLabel = tostring(block)
      local blockMenu = MENU_COALITION:New(coalition.side.BLUE, blockLabel, parentMenu)

      -- Now expand the block into individual aircraft
      for i = 0, 9 do
          local sn = block + i
          local label = tostring(sn)

          local leaf = MENU_COALITION:New(coalition.side.BLUE, label, blockMenu)

          MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Join Queue", leaf, function() JoinMarshal(sn) end )
          MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Leave Queue", leaf, function() LeaveMarshal(sn) end )
          MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Show Info", leaf, function() ShowMarshalInfo(sn) end )
          MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Update Approach Time", leaf, function() UpdateMarshalTime(sn) end )
      end
  end

  -- BUILD PANTHERS
  for _, block in ipairs(panthers) do
  BuildMarshalLeafMenu(panthers_menu, block)
  end

  -- BUILD SPECTRES
  for _, block in ipairs(spectres) do
  BuildMarshalLeafMenu(spectres_menu, block)
  end

  if debug then log("Static Menu Created") end
end

------------------------------------------------------------------
-- MP SAFE STARTUP
------------------------------------------------------------------

-- INITIALISATION
local carrier_initialised = false
local function InitCarrierSystems()
  if carrier_initialised then 
    if debug then log("InitCarrierSystems - already initialised") end
    return true
  end

  carrier_unit = UNIT:FindByName(carrier_name)
  if not carrier_unit or not carrier_unit:IsAlive() then return false end
  log("Carrier initialising")

  carrier_navygroup = NAVYGROUP:New(carrier_name):SetPatrolAdInfinitum():Activate()
  marshal_zone = ZONE_UNIT:New("MarshalZone", carrier_unit, UTILS.NMToMeters(60))

  -- Core systems
  configureCarrierSystems()
  setupRecoveryTanker()
  nextRecoveryStartup()
  createMenus()
  buildMarshalStack()

  -- Schedulers
  SCHEDULER:New(nil, updateCarrierWeather, {}, 1, 600) -- 10 minute weather update
  SCHEDULER:New(nil, recoveryHeartbeat, {}, 1, 30) -- 30 second recovery cycle
  SCHEDULER:New(nil, MarshalHeartbeat, {}, 30, 30 ) -- 30 marshal auto clean

  carrier_initialised = true
  return true
end

-- CARRIER STARTUP SCHEDULER
SCHEDULER:New(nil, function()
  if InitCarrierSystems() then
    log("Carrier initialization complete")
    return false  -- stops once successful
  end
end, {}, 5, 5)







