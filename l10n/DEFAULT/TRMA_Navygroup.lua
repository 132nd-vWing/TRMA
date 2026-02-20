------------------------------------------------------------------
-- CARRIER SCRIPT

------------------------------------------------------------------
env.info("[Carrier Ops] Script loading 3.9")

------------------------------------------------------------------
-- CONFIGURATION / CONSTANTS
------------------------------------------------------------------
local debug = false                     -- enable debug to dcs.log           

local recovery_start_minute = 20        -- 20 Real-World Cycle Start minute
local open_buffer   = 10                -- Minutes from Start until Window Opens (Ship prep/turning)
local default_window = 25               -- Default length of the "Open" window (Case I/II/III ops)
local close_buffer  = 2                 -- Minutes from Window Close until Turnout (Cleanup/Reset)

local deckAngle = 0                     -- -9.1 for Nimitz, but results in a scaled BRC. 

local approach_buffer = 3               -- minutes to next earliest push time.
local approach_duration = 5             -- minutes from slot dme - ball

local HPA_TO_INHG   = 0.02953
local MMHG_TO_HPA   = 1.33322
local MPS_TO_KNOTS  = 1.94384
local MAGVAR = 4                        -- fallback magvar from F10 rose

------------------------------------------------------------------
-- GLOBAL TABLES / STATE
------------------------------------------------------------------
local carrier_info = { weather = {}, ship = {}, recovery= {}, marshal= { stack = {}, assigned_minutes = {} } }  -- register for all working data. 

local carrier_name = "CVN-73"         -- DCS unit name (unit, not group)
local tanker_name = "CVN73_Tanker#IFF:5327FR" -- DCS tanker unit name
local rescue_name = "CVN73_Rescue"     -- DCS rescue helo unit name 
local rescue_airbase = "Plane Guard"    -- DCS escort ship name to land helo.

local carrier_unit = UNIT:FindByName(carrier_name)  -- find the ME unit
local carrier_navygroup = NAVYGROUP:New(carrier_name):SetPatrolAdInfinitum():Activate() -- spawn and task the carrier 
local rescue_helo = RESCUEHELO:New(carrier_name, rescue_name):SetTakeoffHot():SetAltitude(70):SetHomeBase(AIRBASE:FindByName(rescue_airbase)) -- define rescue helo
local marshal_zone = ZONE_UNIT:New("MarshalZone", carrier_unit, UTILS.NMToMeters(50)) -- define the marshal zone for broadcasts
local clients = SET_CLIENT:New():FilterActive(true):FilterCoalitions("blue"):FilterStart() -- list spawned blue human clients

local recovery_tanker = nil     
local carrier_root_menu = nil  
local carrier_admin_menu = nil
local cycle_extend_menu = nil

PlayerSideRegistry = {}

-- Magvar detection
local hasMagvar, magvar = pcall(require, "magvar")
local hasTerrain, terrain = pcall(require, "terrain")


if hasMagvar and hasTerrain then 
  magvar.init(env.mission.date.Month, env.mission.date.Year) -- call map/date magvar tables once. 
else
  env.info("Magvar unavailable, using static")
end


------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------

-- Logs and Debugging
local function log(message, isDebug)
  if isDebug and not debug then return end

  local prefix = isDebug and "[Carrier Debug] " or "[Carrier Ops] "
  env.info(prefix .. message) 
end

-- Broadcaster to clients within Marshal Zone
local function BroadcastMessageToZone(message)
  if not marshal_zone then return end

  clients:ForEachClientInZone(marshal_zone, function(client)
    MESSAGE:New(message, 15):ToClient(client)
  end)
end

-- Magvar from DCS  
local function trueToMag(true_deg)
  return (true_deg - ((carrier_info and carrier_info.weather and carrier_info.weather.mag_var) or MAGVAR)) % 360
end

-- Normalise bearings. 
local function norm360(deg) return (deg % 360 + 360) % 360 end

-- QNH (mmHg -> hPa -> inHg)
local function getQNH(weather)
  local mmHg     = weather.qnh or 762.762
  local qnh_hpa  = mmHg * MMHG_TO_HPA
  local qnh_inhg = qnh_hpa * HPA_TO_INHG
  return qnh_hpa, qnh_inhg
end

-- Wind at ground
local function getWind(weather)
  local wind_data      = weather.wind.atGround
  local wind_speed_mps = wind_data.speed
  local wind_to_true   = wind_data.dir
  local wind_from_true = (wind_to_true + 180) % 360
  local wind_speed_kn  = wind_speed_mps * MPS_TO_KNOTS
  return wind_from_true, wind_speed_kn
end

-- UTC time
local function getUtcEpoch()
  return os.time(os.date("!*t"))
end

-- Sun times checker DCS does wierd things for sunrise/sunset
local function IsValidClockString(t)
  return type(t) == "string" and t:match("^%d%d:%d%d:%d%d$")
end

------------------------------------------------------------------
-- CARRIER ENVIRONMENT (weather, ship data)
------------------------------------------------------------------

local function updateCarrierWeather()
  if not carrier_unit or not carrier_unit:IsAlive() then return end

  -- Magnetic variation at carrier
  local mvDeg = MAGVAR
  if hasMagvar and hasTerrain then 
    local pos = carrier_unit:GetPosition().p
    local lat, lon = terrain.convertMetersToLatLon(pos.x, pos.z)

    local mvRad = magvar.get_mag_decl(lat, lon)
    mvDeg = norm360(math.deg(mvRad))   -- normalised +East -West
  end

  -- Weather from mission
  local weather = env.mission.weather
  local qnh_hpa, qnh_inhg = getQNH(weather)
  
  local wind_from_true, wind_speed_knots = getWind(weather)
  local wind_from_mag = trueToMag(wind_from_true)

  local cloud_base = weather.clouds.base or 0
  local visibility = weather.visibility.distance or 0
  if weather.fog and weather.fog.thickness > 0 then
    local fog_vis = weather.fog.visibility or 0
    visibility = math.min(visibility, fog_vis)
  end

  -- Daylight at the carrier
  local coord = carrier_unit:GetCoordinate()
  local sunrise_raw = coord:GetSunrise()
  local sunset_raw = coord:GetSunset()
  local missionDate = env.mission.date
  local month = missionDate.Month
  local is_night
  local now = timer.getAbsTime() % 86400
  local sunrise_ok = IsValidClockString(sunrise_raw)
  local sunset_ok  = IsValidClockString(sunset_raw)

  if not sunrise_ok or not sunset_ok then
    -- Polar or undefined sun state
    if month == 6 or month == 7 or month == 8 then
      is_night = false
    elseif month == 11 or month == 12 or month == 1 then
      is_night = true
    else
      is_night = false
    end
  else
    local sunrise = UTILS.ClockToSeconds(sunrise_raw)
    local sunset  = UTILS.ClockToSeconds(sunset_raw)

    local night_start = sunset + 900  -- 15 minutes
    local night_end   = sunrise - 900
    is_night = (now >= night_start) or (now <= night_end)
  end

  -- CASE logic
  local carrier_case
  if is_night then
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
    wind_from_true = wind_from_true,
    wind_from_mag = wind_from_mag,
    wind_speed_knots = wind_speed_knots,
    temperature   = weather.season.temperature or 15,
    qnh_hpa       = qnh_hpa,
    qnh_inhg      = qnh_inhg,
    mag_var       = mvDeg,
    case          = carrier_case,
  }

end

local function updateCarrierInfo()
  if not carrier_unit or not carrier_unit:IsAlive() then log("No Carrier", true) return end

  local heading_true = norm360(carrier_unit:GetHeading())
  local speed_knots  = carrier_unit:GetVelocityKNOTS()
  
  local brc_true = norm360(carrier_navygroup:GetHeadingIntoWind(deckAngle, 20))
  local fb_true = norm360(brc_true - 9)

  -- Ship data update
  carrier_info.ship = {
    heading_true   = heading_true,
    heading_mag    = trueToMag(heading_true),
    brc_true       = brc_true,
    brc_mag        = trueToMag(brc_true),
    fb_true        = fb_true,
    fb_mag         = trueToMag(fb_true),
    speed_knots    = speed_knots,
    wind_over_deck = (carrier_info.weather.wind_speed_knots or 0) + speed_knots,
  }

end

------------------------------------------------------------------
-- RECOVERY CYCLE CONTROL (Wallclock UTC driven) 
------------------------------------------------------------------

-- defines next cycle timing depending on how its triggered
local function setRecoveryCycle(window_duration, start_time)
  local now = getUtcEpoch()
  local r = carrier_info.recovery

  -- No override 
  if window_duration then 
    if r.state ~= "IDLE" and r.state ~= nil then BroadcastMessageToZone("Unable, cycle in progress.") return false end
  end

  -- 1. Determine Start Time: If start_time is nil, calculate next 20m wall-clock
  local start_utc = start_time
  if not start_utc then
    local t = os.date("!*t", now)
    t.min, t.sec = recovery_start_minute, 0
    start_utc = os.time(t)
    -- if start_utc <= now then start_utc = start_utc + 3600 end
    while start_utc <= now do start_utc = start_utc + 3600 end 
  end

  -- 2. Apply deration (nil = standard, 85 = CQ)
  local duration = window_duration or default_window
  
  r.state         = "IDLE"
  r.start_utc     = start_utc
  r.open_utc      = start_utc + (open_buffer * 60)
  r.close_utc     = r.open_utc + (duration * 60)
  r.end_utc       = r.close_utc + (close_buffer * 60)
  r.total_cycle_seconds = r.end_utc - r.start_utc
  
  r.open_reported  = false
  r.close_reported = false

  if window_duration then 
    if start_time then
      BroadcastMessageToZone("Recovery Cycle Override, cycle start imminent.")
    else
      BroadcastMessageToZone("Carrier Qualification Scheduled for next recovery cycle.")
    end
  end
  return true
end

-- MOOSE TIW trigger
local function startRecoveryCycle()
  local r = carrier_info.recovery
  carrier_navygroup:AddTurnIntoWind(nil, r.total_cycle_seconds, 25, true, nil)   -- update to simplify cycle startup
end

local function extendRecoveryCycle(minutes)
  local r = carrier_info.recovery
  local extension_seconds = minutes * 60

  if carrier_navygroup:IsSteamingIntoWind() then 
    r.close_utc = r.close_utc + extension_seconds
    r.end_utc = r.end_utc + extension_seconds
    carrier_navygroup:ExtendTurnIntoWind(extension_seconds)
  
    BroadcastMessageToZone("99, Recovery window extended to " .. os.date("!%H:%M", r.close_utc))
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
    if rescue_helo then rescue_helo:Start() end
    startRecoveryCycle()
    trigger.action.setUserFlag("502", 2) -- lights to launch AC


    BroadcastMessageToZone(string.format(
      "99, %s Recovering from %s to %s Zulu. Case %s. BRC %d, FB %d.",
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
    cycle_extend_menu = MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Extend Recovery Window (5m)", carrier_admin_menu, function() extendRecoveryCycle(5) end )
    log("Recovery cycle started TURNING IN")

    -- Launch the tanker
    if recovery_tanker then
      recovery_tanker:Start()
    end
  end

  -- TURNING_IN → OPEN
  if r.state == "TURNING_IN" and now_utc >= r.open_utc and carrier_navygroup:IsSteamingIntoWind() then
    trigger.action.setUserFlag("502", 3) -- lights to recover AC
    r.state = "OPEN"
    log("Recovery state → OPEN", true) 
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
    if rescue_helo then rescue_helo:RTB() end
    log("Recovery state → CLOSED", true)
  end

  -- CLOSED → IDLE (turn downwind)
  if r.state == "CLOSED" and now_utc >= r.end_utc then
    --carrier_navygroup:SetSpeed(30, true, nil)
    -- DCS bug, lights OFF, then to NAV. 
    trigger.action.setUserFlag("502", 0) 
    SCHEDULER:New(nil, function()
      trigger.action.setUserFlag("502", 1) 
    end, {}, 30)

    setRecoveryCycle()
    log("Recovery cycle complete, scheduling next window", true)
  end
end

------------------------------------------------------------------
-- CARRIER SYSTEM CONFIGURATION (ICLS/TACAN/Link-4/ACLS)
------------------------------------------------------------------

-- Carrier Emitters / lights to NAV at start
local function configureCarrierSystems()
  if not carrier_unit then return end

  carrier_unit:CommandSetFrequency(309.5)
  --carrier_navygroup:SetSpeed(30, true, nil)
  trigger.action.setUserFlag("502", 1) -- lights to NAV

  local function pulseSystems(count)
    if not carrier_unit:IsAlive() then return end

    carrier_unit:CommandActivateLink4(331, nil, "A73", 5)
    carrier_unit:CommandActivateACLS(nil, "A73", 5)
    
    local beacon = carrier_unit:GetBeacon()
    if beacon then 
      beacon:ActivateICLS(13, "I73")
      beacon:ActivateTACAN(13, "X", "T73", true)
    end

    log(string.format("%s System Pulse %d executed", carrier_unit:GetName(), count), true)
  end

  pulseSystems(1)

  SCHEDULER:New(nil, pulseSystems, {2}, 30)
  SCHEDULER:New(nil, pulseSystems, {3}, 60)

      log(string.format("%s systems initilized", carrier_unit:GetName(), count), true)
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

-- Helo landing tracker
function rescue_helo:OnAfterReturned(From, Event, To, airbase)
  self:Stop()
end

-- Tanker start stop menu function
local function controlRecoveryTanker()
  if not recovery_tanker then
    log("Recovery tanker not define.", true)
    return
  end
  if recovery_tanker:IsRunning() then
    recovery_tanker:Stop()
    BroadcastMessageToZone("99, Recovery Tanker off station")
    log("Recovery tanker stopped", true) 
  else 
    recovery_tanker:Start()
    BroadcastMessageToZone("99, Recovery Tanker on station")
    log("Recovery tanker started", true) 
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
    "Wind %.0f° @ %.1f kts | Visibility %s | QNH %.2f inHg | Temp %d°C",
    w.wind_from_mag,
    w.wind_speed_knots,
    w.vis_report,
    w.qnh_inhg,
    w.temperature
  ))

  table.insert(lines, string.format(
    "Ship: Hdg %d° | Spd %.1f kts | BRC %d | FB %d",
    s.heading_mag,
    s.speed_knots,
    s.brc_mag,
    s.fb_mag
  ))

  if r.state ~= "IDLE" then
    table.insert(lines, string.format(
      "Recovering from %s to %s Zulu Case %s in effect",
      UTILS.SecondsToClock(r.open_utc, true):sub(1,5),
      UTILS.SecondsToClock(r.close_utc, true):sub(1,5), 
      w.case
    ))
  else
    table.insert(lines, string.format(
      "Next Recovery window: %s to %s Zulu expect Case %s",
      UTILS.SecondsToClock(r.open_utc, true):sub(1,5), 
      UTILS.SecondsToClock(r.close_utc, true):sub(1,5),
      w.case
    ))
  end

  BroadcastMessageToZone(table.concat(lines, "\n"))
end

local function debugReport()

  local w = carrier_info.weather
  local s = carrier_info.ship
  local r = carrier_info.recovery

  local lines = {}

  table.insert(lines, string.format(
    "Weather: Cloud %d | Vis %d | VisRep %s | Wind %d (%dM) | WindSpd %d | Temp %d | QNH %d (%d) | Magvar %.2f | Case %s", 
    w.cloud_base,    
    w.visibility, 
    w.vis_report,   
    w.wind_from_true,
    w.wind_from_mag,
    w.wind_speed_knots,
    w.temperature,
    w.qnh_hpa,  
    w.qnh_inhg,      
    w.mag_var,     
    w.case
    )
  )          

  table.insert(lines, string.format(
    "Ship: HDG %d (%dM) | BRC %d (%dM) | FB %d (%dM) | Spd %d | WoD %d", 
    s.heading_true,
    s.heading_mag,
    s.brc_true,   
    s.brc_mag,      
    s.fb_true,       
    s.fb_mag,        
    s.speed_knots,    
    s.wind_over_deck
    )
  )

  table.insert(lines, string.format(
    "Recovery: State %s | Start %s | Open %s | Close %s | End %s | Cycle %dm",
    r.state,
    os.date("!%H:%M", r.start_utc),
    os.date("!%H:%M", r.open_utc),
    os.date("!%H:%M", r.close_utc),
    os.date("!%H:%M",r.end_utc), 
    r.total_cycle_seconds / 60
    )
  )

  BroadcastMessageToZone(table.concat(lines, "\n"))
end

----------------------------------------------------------------
-- MARSHAL QUEUE
----------------------------------------------------------------

local function buildMarshalStack()
  local radialOffsets = { 0, 30, -30 }
  local angelsList    = { 6, 7, 8, 9, 10, 11 }

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

---MARSHAL TEST-----------------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------------------------

local function FindApproachTime(carrier_info, AssignedMinutes, pushBuffer)

  -- work in minutes
  local now_min = math.floor(getUtcEpoch() / 60)
  local open_min = math.floor(carrier_info.recovery.open_utc / 60)
  local close_min = math.floor(carrier_info.recovery.close_utc / 60)

  -- Rules for allocation
  local earliest_min = math.max(
    now_min + pushBuffer, 
    open_min - approach_duration
  )
  local latest_min   = close_min - approach_duration

  -- Window no longer viable
  if earliest_min > latest_min then
      return nil
  end

  -- Find a viable minute
  for m = earliest_min, latest_min do
      local t = m * 60
      if not AssignedMinutes[t] then
          return t
      end
  end

  return nil

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
      return tonumber(a.approach_time) < tonumber(b.approach_time)
  end)

  
  for _, slot in ipairs(occupied) do
    local radial_mag = norm360(carrier_info.ship.fb_mag + 180 + slot.offset) 
    local appr = slot.approach_time and os.date("!%M", slot.approach_time) or "N/A"

    table.insert(lines, string.format(
      "%s mothers %03d / %02d angels %d approach %s",
      slot.occupant,
      radial_mag,
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
          local radial_mag = norm360(carrier_info.ship.fb_mag + 180 + slot.offset)
          local appr = slot.approach_time and os.date("!%M", slot.approach_time) or "N/A"

          local text = string.format(
              "%s marshal on mothers %03d dme %02d angels %d approach time %s",
              sideNumber,
              radial_mag,
              slot.dme,
              slot.angles,
              appr
          )

          return text
        end
    end
    -- If no slot found
    return sideNumber .. " not in queue."
end

local function JoinMarshal(sideNumber)

  -- First: check if this sideNumber is already in the stack
    for _, slot in ipairs(carrier_info.marshal.stack) do
        if slot.occupant == sideNumber then
            return sideNumber .. " already in queue."
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
        return sideNumber .. " queue full hold current position."
    end

    -- Find next valid approach time
    local t = FindApproachTime(carrier_info, carrier_info.marshal.assigned_minutes, 15)
    if not t then
        return sideNumber .. " approach not possible this cycle."
    end

    -- Assign
    freeSlot.occupant = sideNumber
    freeSlot.approach_time = t
    freeSlot.last_update = getUtcEpoch()
    carrier_info.marshal.assigned_minutes[t] = sideNumber

    -- Report assignment
    return ShowMarshalInfo(sideNumber)
end

local function LeaveMarshal(sideNumber)
    for _, slot in ipairs(carrier_info.marshal.stack) do
        if slot.occupant == sideNumber then
            if slot.approach_time then
                carrier_info.marshal.assigned_minutes[slot.approach_time] = nil
            end
            slot.occupant = nil
            slot.approach_time = nil
            slot.last_update = nil
            return sideNumber .. " vacated marshal queue."
        end
    end

    return sideNumber .. " not found in stack."
end

local function UpdateMarshalTime(sideNumber)
    local slot = nil
    for _, s in ipairs(carrier_info.marshal.stack) do
        if s.occupant == sideNumber then slot = s; break end
    end

    if not slot then return sideNumber .. " not found in stack." end
    
    local newTime = FindApproachTime(carrier_info, carrier_info.marshal.assigned_minutes, 3) 
    if not newTime then return sideNumber .. " unable cycle ending." end

    if slot.approach_time then carrier_info.marshal.assigned_minutes[slot.approach_time] = nil end

    slot.approach_time = newTime
    slot.last_update = getUtcEpoch()
    carrier_info.marshal.assigned_minutes[newTime] = sideNumber

    return ShowMarshalInfo(sideNumber)
end

local function ExecuteAutoAction(actionType, sn)
  if not sn then return
  end

  local response = ""

  if actionType == "JOIN" then
    response = JoinMarshal(sn)
  elseif actionType == "LEAVE" then
    response = LeaveMarshal(sn)
  elseif actionType == "UPDATE" then
    response = UpdateMarshalTime(sn)
  elseif actionType == "SHOW" then
    response = ShowMarshalInfo(sn)
  end

  if response ~= "" then
    BroadcastMessageToZone(response)
  end
end

local function ResetMarshalStack()
    for _, slot in ipairs(carrier_info.marshal.stack) do
        slot.occupant = nil
        slot.approach_time = nil
    end

    carrier_info.marshal.assigned_minutes = {}

    log("Marshal stack reset", true)
end

-- Marshal cleanup 
local function marshalHeartbeat() 

    -- if not IsMarshalRequired() then
    --     return
    -- end
    
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
  carrier_root_menu = MENU_COALITION:New(coalition.side.BLUE, "Carrier Control")  -- global because extend is dynamic
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Carrier Information", carrier_root_menu, reportCarrierInformation)
  local marshal_root_menu = MENU_COALITION:New(coalition.side.BLUE, "Marshal Options", carrier_root_menu)
  carrier_admin_menu = MENU_COALITION:New(coalition.side.BLUE, "Carrier Admin", carrier_root_menu)  -- global because extend is dynamic
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "---", carrier_root_menu, function() end)  -- spacer
  carrier_debug_menu = MENU_COALITION:New(coalition.side.BLUE, "Carrier Debug", carrier_root_menu)

  -- ADMIN MENU
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Schedule CQ Recovery", carrier_admin_menu, function() setRecoveryCycle(85) end)  
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Start/Stop Recovery Tanker", carrier_admin_menu, controlRecoveryTanker)
  local carrier_lights_menu = MENU_COALITION:New(coalition.side.BLUE, "Configure Carrier Lights", carrier_admin_menu)

  -- DEBUG MENU
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Start Recovery Cycle Now", carrier_debug_menu, function() setRecoveryCycle(25, getUtcEpoch()) end)
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Debug Report", carrier_debug_menu, debugReport)
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Clear Marshal Stack", carrier_debug_menu, ResetMarshalStack)

  -- LIGHTS MENU
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Lights OFF", carrier_lights_menu, function() trigger.action.setUserFlag("502", 0) end)
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Lights NAV", carrier_lights_menu, function() trigger.action.setUserFlag("502", 1) end)
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Lights LAUNCH", carrier_lights_menu, function() trigger.action.setUserFlag("502", 2) end)
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Lights RECOVER", carrier_lights_menu, function() trigger.action.setUserFlag("502", 3) end)  

  -- MARSHAL MENUS
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Show Marshal Stack", marshal_root_menu, ShowMarshalStack) 

  local menu_sets = { { name = "Panthers", blocks = { 300, 310, 320, 330 } }, { name = "Spectres", blocks = { 200, 210, 220 } } }

  -- LOOP THROUGH GROUPS
  for _, group in ipairs(menu_sets) do
    local group_root = MENU_COALITION:New(coalition.side.BLUE, group.name, marshal_root_menu)

    for _, blockStart in ipairs(group.blocks) do
      local blockMenu = MENU_COALITION:New(coalition.side.BLUE, blockStart .. " Series", group_root)

      for i = 0, 9 do
        local sn = blockStart + i

        -- Create the sidenumber root menu
        local sn_root = MENU_COALITION:New(coalition.side.BLUE, sn .. " actions", blockMenu )

        -- Marshal actions now live INSIDE the sidenumber menu
        MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Join Marshal Queue", sn_root, function() ExecuteAutoAction("JOIN", sn) end)
        MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Leave Marshal Queue", sn_root, function() ExecuteAutoAction("LEAVE", sn) end)
        MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Update Approach Time", sn_root, function() ExecuteAutoAction("UPDATE", sn) end)
        MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Show My Marshal Info", sn_root, function() ExecuteAutoAction("SHOW", sn) end)
      end
    end
  end

  log("Static Menu Created", true)
end

------------------------------------------------------------------
-- MP SAFE STARTUP
------------------------------------------------------------------

-- INITIALISATION
local carrier_initialised = false
local function InitCarrierSystems()
  if carrier_initialised then 
    log("InitCarrierSystems - already initialised", true)
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
  setRecoveryCycle()
  createMenus()
  buildMarshalStack()
  updateCarrierWeather()
  updateCarrierInfo()


  -- Schedulers
  SCHEDULER:New(nil, updateCarrierWeather, {}, 1, 600) -- 10 minute weather update
  SCHEDULER:New(nil, recoveryHeartbeat, {}, 1, 30) -- 30 second recovery cycle
  SCHEDULER:New(nil, marshalHeartbeat, {}, 30, 30 ) -- 30 marshal auto clean

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

