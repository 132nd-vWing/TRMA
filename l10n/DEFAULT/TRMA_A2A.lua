-- ============================================================================
-- TRMA A2A RANGE ENGINE (ver 2.4)
-- ============================================================================
-- Purpose: Automated A2A Spawning with "Leash" logic.
-- Instructions for Mission Makers:
-- 1. engageZone is the area where combat is allowed. The range. 
-- 2. capZones are the specific areas where drones will spawn and patrol.
-- ============================================================================
local debug = false

TRMA_A2A = {}

-- USER SETTINGS: Air frames must be called Drone_{airframe} or Drone_{airframe}_BFM in ME
TRMA_A2A.Airframes = { 
  "SU27", 
  "MIG29A" 
}

-- ============================================================================
-- RANGE CLASS LOGIC (The Engine)
-- ============================================================================
TRMA_A2A.Range = {}
TRMA_A2A.Range.__index = TRMA_A2A.Range

function TRMA_A2A.Range:New(rangeName, config, parentMenu)
  local self = setmetatable({}, TRMA_A2A.Range)
  
  -- Range Identity
  self.name       = rangeName
  self.mode       = "BVR" 
  self.isRandom   = false
  self.parentMenu = parentMenu

  -- Zone Setup
  self.zoneEngage = ZONE:New(config.engageZone) 
  self.capZones = {}
  for _, zData in ipairs(config.capZones) do
    table.insert(self.capZones, {
      name = zData.name,
      zone = ZONE:New(zData.zoneName)
    })
  end

  -- Default Group Templates
  self.capGroups = {
    { airframe = TRMA_A2A.Airframes[2], size = 2, capZoneID = 1 },
    { airframe = TRMA_A2A.Airframes[1], size = 2, capZoneID = 2 },
  }

  self:BuildMenu()
  env.info("[TRMA_A2A] Loaded Range: " .. self.name)
  return self
end

function TRMA_A2A.Range:SpawnFlight(airframe, size, capZoneID)
  local range = self
  local currentCapZone = self.capZones[capZoneID]
  local zoneObj = currentCapZone.zone

  -- 1. Setup Parameters
  if self.isRandom then 
    airframe = TRMA_A2A.Airframes[math.random(#TRMA_A2A.Airframes)]
    size = math.random(1, 4)
  end
  
  local template  = string.format("Drone_Aggressor_%s", airframe)
  if self.mode == "BFM" then template = template .. "_BFM" end

  -- 2. Define the "Drone Intelligence" (The callback)
  local function OnSpawnGroup(group)
    local drones = FLIGHTGROUP:New(group)
    local alt    = math.random(20000, 30000)
    
    -- Mission: Fly a racetrack in the patrol zone
    local patrol = AUFTRAG:NewORBIT_RACETRACK(zoneObj:GetRandomCoordinate(), alt, 350, 110)    

    -- "Radar" Setup: Tell the drone which zones to monitor
    drones:SetCheckZones(SET_ZONE:New():AddZone(range.zoneEngage):AddZone(zoneObj))
    drones:AddMission(patrol)

    -- EVENT: Entering the Range (Weapons Hot)
    function drones:OnAfterEnterZone(From, Event, To, zone)
      if zone == zoneObj or zone == range.zoneEngage then
        
        if debug then 
          local msg = drones:GetName() .. ": Weapons HOT (Entering " .. zone:GetName() .. ")"
          MESSAGE:New(msg, 5):ToAll() 
          env.info(msg)
        end
        
        -- Engagement Logic: BVR = 100nm, BFM = 20nm
        local rangeDist = (range.mode == "BVR") and 185 or 40
        drones:SetEngageDetectedOn(rangeDist, {"Air"}, range.zoneEngage)
      end
    end

    -- EVENT: Leaving the Range (The Leash)
    function drones:OnAfterLeaveZone(From, Event, To, zone)
      if zone == range.zoneEngage then
        local msg = drones:GetName() .. ": Leaving Range. Disengaging."
        env.info(msg)
        if debug then 
          MESSAGE:New(msg, 10):ToAll()
        end

        drones:SetEngageDetectedOff()
        group:ClearTasks() -- Force-break the AI dogfight
        drones:StartMission(patrol)
      end
    end
  end

  -- 3. Execute Spawn
  local alias = template .. "-" .. math.random(1000)
  SPAWN:NewWithAlias(template, alias)
    :InitLimit(10, 0)
    :InitGrouping(size)
    :InitRandomizeCallsign()
    :InitSkill("Good")
    :OnSpawnGroup(OnSpawnGroup)
    :SpawnInZone(zoneObj, true, 10000, 15000)
end

-- ============================================================================
-- RADIO MENU BUILDER
-- ============================================================================
function TRMA_A2A.Range:BuildMenu()
  if self.a2aMenu then self.a2aMenu:Remove() end
  self.a2aMenu = MENU_MISSION:New(self.name .. " Adversaries", self.parentMenu)

  -- Submenu: Mode Switch
  local mMode = MENU_MISSION:New("Change Mode: " .. self.mode, self.a2aMenu)
  for _, mType in ipairs({"BVR", "BFM"}) do
    local icon = (mType == self.mode) and " [ACTIVE]" or ""
    MENU_MISSION_COMMAND:New(mType .. icon, mMode, function() self.mode = mType; self:BuildMenu() end)
  end

  -- Submenu: Quick Spawns
  for i, cfg in ipairs(self.capGroups) do
    local locName = self.capZones[cfg.capZoneID].name 
    local label = string.format("Spawn Group %d: %d-ship %s (%s)", i, cfg.size, cfg.airframe, locName)
    MENU_MISSION_COMMAND:New(label, self.a2aMenu, function() self:SpawnFlight(cfg.airframe, cfg.size, cfg.capZoneID) end)
  end

  -- Submenu: Deep Config
  local mCfg = MENU_MISSION:New("Edit Group Compositions", self.a2aMenu)
  for i, cfg in ipairs(self.capGroups) do
    local mGrp = MENU_MISSION:New("Group " .. i, mCfg)

    -- Edit Size
    local mSize = MENU_MISSION:New("Set Size", mGrp)
    for s = 1, 4 do
      MENU_MISSION_COMMAND:New(s .. "-ship", mSize, function() cfg.size = s; self:BuildMenu() end)
    end

    -- Edit Airframe
    local mAir = MENU_MISSION:New("Set Airframe", mGrp)
    for _, name in ipairs(TRMA_A2A.Airframes) do
      MENU_MISSION_COMMAND:New(name, mAir, function() cfg.airframe = name; self:BuildMenu() end)
    end
  end
end