-- TRMA_A2A.lua (ver 2.3 - FSM Refactor)
-- Object-Oriented A2A Range Spawner

env.info("[TRMA_A2A] INFO: ver 2.3 loading...")

TRMA_A2A = {}

TRMA_A2A.Airframes = {
  "MIG23",
  "MIG29A",
  "SU30",
  "JF17",
  "MIG25",
  "SU27",
  "J11A",
  "MIG31"
}

-- ======================================================================
-- TRMA_A2A.Range Class
-- ======================================================================
TRMA_A2A.Range = {}
TRMA_A2A.Range.__index = TRMA_A2A.Range

function TRMA_A2A.Range:New(rangeName, config, parentMenu)
  env.info("[TRMA_A2A] DEBUG: Initializing New Range: " .. tostring(rangeName))

  local self = setmetatable({}, TRMA_A2A.Range)
  
  self.name = rangeName
  self.mode = "BVR" 
  self.isRandom = false
  
  -- 1. Initialize Zones
  self.zoneEngage = ZONE:New(config.engageZone) 
  self.setEngage = SET_ZONE:New():AddZone(self.zoneEngage)

  self.patrolZones = {}
  for i, pZoneData in ipairs(config.patrolZones) do
    table.insert(self.patrolZones, {
      name = pZoneData.name,
      zone = ZONE:New(pZoneData.zoneName)
    })
  end

  self.capGroups = {
    { airframe = "SU27",   size = 2, zoneIdx = 1 },
    { airframe = "MIG29A", size = 2, zoneIdx = 2 },
  }

  self.parentMenu = parentMenu
  self:BuildMenu()

  env.info("[TRMA_A2A] INFO: Initialized " .. self.name)
  return self
end

function TRMA_A2A.Range:SpawnFlight(airframe, size, zoneIdx)
  if self.isRandom then 
    airframe = TRMA_A2A.Airframes[math.random(#TRMA_A2A.Airframes)]
    size = math.random(1, 4)
  end

  local orbitData = self.patrolZones[zoneIdx]
  local zoneOrbit = orbitData.zone
  local template = string.format("Drone_Aggressor_%s", airframe)
  if self.mode == "BFM" then template = template .. "_BFM" end

  local function OnSpawnGroup(group)
    local drones = FLIGHTGROUP:New(group)
    local alt = math.random(20000, 30000)
    
    -- AUFTRAG definition
    local mission_cap = AUFTRAG:NewORBIT_RACETRACK(zoneOrbit:GetRandomCoordinate(), alt, 350, 110)    

    -- Setup Zone monitoring (The "AllZones" logic from your test)
    local checkZones = SET_ZONE:New():AddZone(self.zoneEngage):AddZone(zoneOrbit)
    drones:SetCheckZones(checkZones)

    -- Initial state: Start CAP
    drones:AddMission(mission_cap)

    -- 1. ENTRANCE LOGIC (Engage when in Spawn Zone / Return to range)
    function drones:OnAfterEnterZone(From, Event, To, zone)
      -- Check if we entered our specific patrol zone or the main range
      if zone == zoneOrbit or zone == self.zoneEngage then
        --local msg = string.format("%s: Inside %s. Weapons HOT.", drones:GetName(), zone:GetName())
        --MESSAGE:New(msg, 5):ToAll()
        
        -- Enable detection and engagement restricted to the Range Zone
        drones:SetEngageDetectedOn(self.mode == "BVR" and 185 or 40, {"Air"}, self.zoneEngage)
      end
    end

    -- 2. EXIT LOGIC (Leash trigger)
    function drones:OnAfterLeaveZone(From, Event, To, zone)
      -- Only trigger the leash if leaving the main Engage Zone
      if zone == self.zoneEngage then
        --local msg = string.format("%s: EXCEEDED RANGE. Disengaging...", drones:GetName())
        --MESSAGE:New(msg, 10):ToAll()
        
        -- Mechanics from your test.lua
        drones:SetEngageDetectedOff()
        
        -- Optional: Break DCS logic hard if AUFTRAG isn't snapping them back fast enough
        local dcsGroup = drones:GetGroup()
        if dcsGroup then dcsGroup:ClearTasks() end
        
        -- Force transition back to CAP
        drones:StartMission(mission_cap)
      end
    end
  end

  -- Spawning Execution
  local alias = template .. "-" .. tostring(math.random(100000))
  SPAWN:NewWithAlias(template, alias)
    :InitLimit(10, 0)
    :InitSkill("Good")
    :InitGrouping(size)
    :InitRandomizeCallsign()
    :OnSpawnGroup(OnSpawnGroup)
    :SpawnInZone(zoneOrbit, true, 10000, 15000)
end

function TRMA_A2A.Range:BuildMenu()
  if self.a2aMenu then self.a2aMenu:Remove() end
  self.a2aMenu = MENU_MISSION:New("A2A Adversaries", self.parentMenu)

  -- Mode Toggle
  local modeMenu = MENU_MISSION:New(string.format("Engagement Mode (%s)", self.mode), self.a2aMenu)
  for _, modeType in ipairs({"BVR", "BFM"}) do
    local display = (modeType == self.mode) and (modeType .. " ★") or modeType
    MENU_MISSION_COMMAND:New(display, modeMenu, function()
      self.mode = modeType
      self:BuildMenu()
    end)
  end

  -- Group Spawns
  for i, cfg in ipairs(self.capGroups) do
    local zoneName = self.patrolZones[cfg.zoneIdx].name
    local label = string.format("Group%d %d-ship %s %s", i, cfg.size, cfg.airframe, zoneName)
    MENU_MISSION_COMMAND:New(label, self.a2aMenu, function()
      self:SpawnFlight(cfg.airframe, cfg.size, cfg.zoneIdx)
    end)
  end

  -- Random Spawn
  MENU_MISSION_COMMAND:New(string.format("Random %s Group mid range", self.mode), self.a2aMenu, function()
    self.isRandom = true
    self:SpawnFlight(nil, nil, 2)
    self.isRandom = false 
  end)

  -- Configuration Submenu
  local configGroupsMenu = MENU_MISSION:New("Configure Groups", self.a2aMenu)
  for i, cfg in ipairs(self.capGroups) do
    local groupMenu = MENU_MISSION:New(string.format("Configure Group%d", i), configGroupsMenu)

    -- Size
    local sizeMenu = MENU_MISSION:New("Set Size", groupMenu)
    for s = 1, 4 do
      local label = (cfg.size == s) and string.format("%d-ship ★", s) or string.format("%d-ship", s)
      MENU_MISSION_COMMAND:New(label, sizeMenu, function() cfg.size = s; self:BuildMenu() end)
    end

    -- Airframe
    local airframeMenu = MENU_MISSION:New("Set Airframe", groupMenu)
    for _, name in ipairs(TRMA_A2A.Airframes) do
      local label = (cfg.airframe == name) and (name .. " ★") or name
      MENU_MISSION_COMMAND:New(label, airframeMenu, function() cfg.airframe = name; self:BuildMenu() end)
    end

    -- Patrol Zone
    local zoneMenu = MENU_MISSION:New("Set Patrol Zone", groupMenu)
    for idx, pZone in ipairs(self.patrolZones) do
      local label = (cfg.zoneIdx == idx) and (pZone.name .. " ★") or pZone.name
      MENU_MISSION_COMMAND:New(label, zoneMenu, function() cfg.zoneIdx = idx; self:BuildMenu() end)
    end
  end
end

env.info("[TRMA_A2A] INFO: Initialization complete.")