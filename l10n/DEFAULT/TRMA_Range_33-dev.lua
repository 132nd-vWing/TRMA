-- A2A Script Full Version
-- rev 5.1
-- jonde + ChatGPT

-- Description
-- A2A engagement Script provides a semi dynamic configurable Enemy area encounter. 
-- Jets include SU27, MIG29 (more can be added as required)
-- Supports BFM or BVR provide enemy differetn weapons. 
-- Support 1-3 flights. 
-- Supports a 0,1,3,5 minute delay between flight spawns. 
-- Each flight can be configured with these parms. 
--- Airframe (SU27, MIG29)
--- Flight Size (1-4)
--- Flight Task (DCA (CAP), OCA (Intercept))
--- Flight Spawnlocation (NW, SW, NE) (can add more if needed)
--
-- Behaviour
-- The flights should work as a team as they are actually 1,2,3,4 ship groups in the templates. 
-- DCA enemy 
--- will execute a CAP orbit near their spawn zone. 
--- will engage when Blue threat is detected inside 50nm. 
--- will disengage and return to CAP if blue leave R33. 
--- will despawn if they leave R33 for more than 3 minutes. 
-- OCA enemy 
--- will actively hunt for blue inside R33. 
--- will disengage and loiter if blue leave R33. 
--- will despawn if they leave R33 for more that 3 minutes. 
-- 
-- Function 
--- Show Current Config will show what is currently configured. It initially shows the default. 
--- Confugure Engagement allows you to change the parameters
--- Activate will check that no engagement is active and trigger the engagement. 
--- Deactivate will clean up all active red flights and reset the logs and timers. 
--
-- Requirements
--- Trigger Zones (RANGE33, R33_NW, R33_SW, R33_NE)
--- Templates (Per airframe, 1,2,3,4 ship, BFM and BVR)
--- Moose. 

-- trigger.action.outText("r33-dev.lua loaded with menus + spawn logic!", 10)

-- ================== CONFIG ==================

local EngagementConfig = {
  type = "BVR",   -- BVR or BFM
  numFlights = 2, -- 1-3
  delay = 1,      -- minutes between spawns
  flights = {
    [1] = { airframe = "SU27", size = 2, spawnZone = "NW", stance = "DCA" },
    [2] = { airframe = "MIG29", size = 2, spawnZone = "SW", stance = "DCA" },
    [3] = { airframe = "MIG29", size = 2, spawnZone = "NW", stance = "OCA" },
  }
}

local RangeZone = ZONE:New("RANGE33")
local ActiveRedFlights = {}
local FlightSchedulers = {}
local flightMenus = {}
local configMenu = nil
local a2aMenu = nil
local ActiveAIControllers = {}

-- ================== HELPERS ==================

local function GetEngagementStatus()
  local status = string.format("Mode: %s | Flights: %d | Delay: %d",
    EngagementConfig.type, EngagementConfig.numFlights, EngagementConfig.delay)

  for i = 1, EngagementConfig.numFlights do
    local f = EngagementConfig.flights[i]
    status = status .. string.format(" | F%d: %s x%d @%s %s",
      i, f.airframe, f.size, f.spawnZone, f.stance)
  end
  return status
end

local function Highlight(label, current, candidate)
  return (current == candidate) and (label .. " *") or label
end

local function BuildTemplateName(flightCfg)
  return string.format("Red_%s_%s_%d",
    EngagementConfig.type, flightCfg.airframe, flightCfg.size)
end

local function EnsureZone(name)
  local z = ZONE:FindByName(name)
  if not z then
    -- MESSAGE:New("ERROR: Missing trigger zone: "..name, 15):ToAll()
    env.error(string.format("ERROR-R33: Missing trigger zone: %s", name))
    return nil
  end
  return z
end

local function TemplateExists(name)
  return GROUP:FindByName(name) ~= nil
end

local function RebuildConfigMenuDeferred()
  timer.scheduleFunction(function()
    BuildConfigMenu()
    return nil
  end, nil, timer.getTime() + 0.1)
end

-- ================== SPAWN / DESPAWN ==================

local function SpawnRedFlight(flightNum)
  local fCfg = EngagementConfig.flights[flightNum]
  local templateName = BuildTemplateName(fCfg)
  local spawnZone = EnsureZone("R33_" .. fCfg.spawnZone)

  if not spawnZone then
    env.error(string.format("ERROR-R33 Flight %d spawn aborted: zone %s not found.",flightNum, fCfg.spawnZone))
    return
  end
  if not TemplateExists(templateName) then
    env.error(string.format("ERROR-R33 Flight %d spawn aborted: template '%s' not found.",flightNum, templateName))
    return
  end

  MESSAGE:New(string.format("R33 Spawning Flight %d (%s) at %s",flightNum, templateName, fCfg.spawnZone), 10):ToAll()

  local spawner = SPAWN:New(templateName)
    spawner:InitLimit(999, 0)
  local group = spawner:SpawnInZone(spawnZone, true, 15000, 30000)
  
  if not group then
    env.error(string.format("ERROR-R33 Failed to spawn %s",templateName))
    return
  end
  ActiveRedFlights[flightNum] = group

  -- Function to start the AI_CAP_ZONE controller
  local function startController()
    local capZone = (fCfg.stance == "DCA")
      and (EnsureZone("R33_" .. fCfg.spawnZone) or RangeZone)
      or RangeZone

    local engageZone
    if fCfg.stance == "DCA" then
      engageZone = ZONE_RADIUS:New(
        capZone:GetName() .. "_Engage",
        capZone:GetVec2(),
        129640 -- 70nm in metres
      )
    else
      engageZone = RangeZone
    end

    local ai = AI_CAP_ZONE:New(
      capZone,
      fCfg.minSpeed or 350, fCfg.maxSpeed or 450,
      fCfg.minAlt or 20000, fCfg.maxAlt or 30000
    )
    ai:SetEngageZone(engageZone)
    ai:SetControllable(group)
    ai:Start()

    ActiveAIControllers[flightNum] = ai
  end

  -- Start CAP controller on spawn
  startController()

  -- Scheduler: cleanup and Blue presence toggle
  FlightSchedulers[flightNum] = SCHEDULER:New(nil, function()
    if not group or not group:IsAlive() then
      if ActiveAIControllers[flightNum] then
        ActiveAIControllers[flightNum]:Stop()
        ActiveAIControllers[flightNum] = nil
      end
      ActiveRedFlights[flightNum] = nil
      if FlightSchedulers[flightNum] then
        FlightSchedulers[flightNum]:Stop()
        FlightSchedulers[flightNum] = nil
      end
      return
    end

    -- Despawn if outside RangeZone > 3 min
    local inside = RangeZone:IsVec3InZone(group:GetPointVec3())
    if not inside then
      group._outTime = group._outTime or timer.getTime()
      if timer.getTime() - group._outTime > 180 then
        -- MESSAGE:New(string.format("R33 Red Flight %d left Range 33 > 3 minutes — despawning.",flightNum), 10):ToAll()
        env.error(string.format("INFO-R33 Red Flight %d left Range 33 > 3 minutes — despawning.",flightNum))
        group:Destroy()
        return
      end
    else
      group._outTime = nil
    end

    -- Blue presence check
    local blueInside = false
    local blues = SET_GROUP:New():FilterCoalitions("blue"):FilterCategories("plane"):FilterActive(true):FilterOnce()
    blues:ForEachGroup(function(bGroup)
      if RangeZone:IsVec3InZone(bGroup:GetPointVec3()) then
        blueInside = true
      end
    end)

    if not blueInside and ActiveAIControllers[flightNum] then
      ActiveAIControllers[flightNum]:Stop()
      ActiveAIControllers[flightNum] = nil
      -- Force them back into a holding orbit at their CAP zone
      local capZone = (fCfg.stance == "DCA")
          and (EnsureZone("R33_" .. fCfg.spawnZone) or RangeZone)
          or RangeZone

      local orbitTask = group:TaskOrbitCircleAtVec2(capZone:GetVec2(),
                                                    fCfg.orbitSpeed or 400,
                                                    fCfg.orbitAlt or 25000)
      group:SetTask(orbitTask)

      -- MESSAGE:New(string.format("R33 Red Flight %d holding CAP — no blue inside.",flightNum), 10):ToAll()
      env.info(string.format("INFO-R33 Red Flight %d holding CAP — no blue inside.",flightNum))
    elseif blueInside and not ActiveAIControllers[flightNum] then
      startController()
      --MESSAGE:New(string.format("R33 Red Flight %d resuming intercept — blue inside range.",flightNum), 10):ToAll()
      env.info(string.format("INFO-R33 Red Flight %d resuming intercept — blue inside range.",flightNum))

    end
  end, {}, 30, 30)
end




local function ActivateEngagement()
  -- Prevent duplicate activation
  local anyAlive = false
  for _, g in pairs(ActiveRedFlights) do
    if g and g:IsAlive() then
      anyAlive = true
      break
    end
  end
  if anyAlive then
    MESSAGE:New("R33 Engagement already active! Deactivate first.", 5):ToAll()
    return
  end


  MESSAGE:New("R33 Engagement Activated", 5):ToAll()

  -- convert 0 delay into 0.1 to avoid collisions
  local delayMin = EngagementConfig.delay
  if delayMin == 0 then delayMin = 0.1 -- 6 seconds
  end
  
  -- Spawn Flight 1 immediately
  SpawnRedFlight(1)

  -- Chain remaining flights
  if EngagementConfig.numFlights > 1 then
    for i = 2, EngagementConfig.numFlights do
      local delaySec = (i-1) * (delayMin * 60)
      -- MESSAGE:New(string.format("R33 Scheduling Flight %d in %d seconds", i, delaySec), 5):ToAll()
      env.info(string.format("Scheduling Flight %d in %d seconds", i, delaySec))
      timer.scheduleFunction(
        function(arg, time)
          local flightNum = arg
          SpawnRedFlight(flightNum)
          return nil -- one-shot
        end,
        i, -- arg
        timer.getTime() + delaySec
      )
    end
  end
end




local function DeactivateEngagement()
  MESSAGE:New("Engagement Deactivated. Cleaning up red air.", 5):ToAll()

  for i, g in pairs(ActiveRedFlights) do
    if g and g:IsAlive() then g:Destroy() end
    ActiveRedFlights[i] = nil
    if ActiveAIControllers[i] then
      ActiveAIControllers[i]:Stop()
      ActiveAIControllers[i] = nil
    end
  end

  for i, s in pairs(FlightSchedulers) do
    if s then s:Stop() end
    FlightSchedulers[i] = nil
  end
end

-- ================== MENUS ==================

local function BuildFlightMenu(flightNum, parentMenu)
  if flightMenus[flightNum] then
    flightMenus[flightNum]:Remove()
    flightMenus[flightNum] = nil
  end

  local flightMenu = MENU_MISSION:New("Flight " .. flightNum, parentMenu)
  flightMenus[flightNum] = flightMenu

  -- Airframe
  local airframeMenu = MENU_MISSION:New("Airframe", flightMenu)
  for _, type in ipairs({"SU27", "MIG29"}) do
    MENU_MISSION_COMMAND:New(
      Highlight(type, EngagementConfig.flights[flightNum].airframe, type),
      airframeMenu,
      function()
        EngagementConfig.flights[flightNum].airframe = type
        MESSAGE:New(GetEngagementStatus(), 5):ToAll()
        RebuildConfigMenuDeferred()
      end
    )
  end

  -- Size
  local sizeMenu = MENU_MISSION:New("Size", flightMenu)
  for i = 1, 4 do
    MENU_MISSION_COMMAND:New(
      Highlight(tostring(i), EngagementConfig.flights[flightNum].size, i),
      sizeMenu,
      function()
        EngagementConfig.flights[flightNum].size = i
        MESSAGE:New(GetEngagementStatus(), 5):ToAll()
        RebuildConfigMenuDeferred()
      end
    )
  end

  -- Spawn Zone
  local zoneMenu = MENU_MISSION:New("Spawn Zone", flightMenu)
  for _, zone in ipairs({"NW", "SW", "NE"}) do
    MENU_MISSION_COMMAND:New(
      Highlight(zone, EngagementConfig.flights[flightNum].spawnZone, zone),
      zoneMenu,
      function()
        EngagementConfig.flights[flightNum].spawnZone = zone
        MESSAGE:New(GetEngagementStatus(), 5):ToAll()
        RebuildConfigMenuDeferred()
      end
    )
  end

  -- Stance
  local stanceMenu = MENU_MISSION:New("Stance", flightMenu)
  for _, stance in ipairs({"DCA","OCA"}) do
    MENU_MISSION_COMMAND:New(
      Highlight(stance, EngagementConfig.flights[flightNum].stance, stance),
      stanceMenu,
      function()
        EngagementConfig.flights[flightNum].stance = stance
        MESSAGE:New(GetEngagementStatus(), 5):ToAll()
        RebuildConfigMenuDeferred()
      end
    )
  end
end

function BuildConfigMenu()
  if configMenu then configMenu:Remove() end
  configMenu = MENU_MISSION:New("Configure Engagement", a2aMenu)

  -- Mode
  local typeMenu = MENU_MISSION:New("Type", configMenu)
  for _, t in ipairs({"BVR","BFM"}) do
    MENU_MISSION_COMMAND:New(
      Highlight(t, EngagementConfig.type, t),
      typeMenu,
      function()
        EngagementConfig.type = t
        MESSAGE:New(GetEngagementStatus(), 5):ToAll()
        RebuildConfigMenuDeferred()
      end
    )
  end

  -- Flights
  local flightsMenu = MENU_MISSION:New("Flights", configMenu)
  for i = 1, 3 do
    MENU_MISSION_COMMAND:New(
      Highlight(tostring(i), EngagementConfig.numFlights, i),
      flightsMenu,
      function()
        EngagementConfig.numFlights = i
        MESSAGE:New(GetEngagementStatus(), 5):ToAll()
        RebuildConfigMenuDeferred()
      end
    )
  end

  -- Delay
  local delayMenu = MENU_MISSION:New("Spawn Delay", configMenu)
  for _, d in ipairs({0,1,2,3,5}) do
    MENU_MISSION_COMMAND:New(
      Highlight(tostring(d).." min", EngagementConfig.delay, d),
      delayMenu,
      function()
        EngagementConfig.delay = d
        MESSAGE:New(GetEngagementStatus(), 5):ToAll()
        RebuildConfigMenuDeferred()
      end
    )
  end

  -- Flight submenus
  for i = 1, EngagementConfig.numFlights do
    BuildFlightMenu(i, configMenu)
  end

  -- Clean old menus
  for i = EngagementConfig.numFlights+1, #flightMenus do
    if flightMenus[i] then
      flightMenus[i]:Remove()
      flightMenus[i] = nil
    end
  end
end

-- ================== TOP-LEVEL MENU ==================

range_33test_menu_root = MENU_MISSION:New("Range 33 Test", range_root_menu31_34)
a2aMenu = MENU_MISSION:New("A2A Engagement", range_33test_menu_root)

MENU_MISSION_COMMAND:New("Show Current Config", a2aMenu, function()
  MESSAGE:New(GetEngagementStatus(), 10):ToAll()
end)

BuildConfigMenu()

MENU_MISSION_COMMAND:New("Activate Engagement", a2aMenu, ActivateEngagement)
MENU_MISSION_COMMAND:New("Deactivate Engagement", a2aMenu, DeactivateEngagement)
