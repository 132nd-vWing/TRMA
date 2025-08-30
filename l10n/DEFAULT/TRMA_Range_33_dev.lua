range_33_menu_root = MENU_MISSION:New("Range 33", range_root_menu31_34)
local zoneCAP = ZONE_POLYGON:New("zoneCAP",GROUP:FindByName("r23_engagezone"))
local zoneOrbit = ZONE_POLYGON:New("zoneOrbit",GROUP:FindByName("r23_patrolzone"))

local zoneRangeViolation = ZONE_POLYGON:New("zoneRangeViolation",GROUP:FindByName("r23_range_violation"))

local setCAP = SET_ZONE:New()
local setRangeviolation= SET_ZONE:New()
local setOrbit = SET_ZONE:New()

setCAP:AddZone(zoneCAP)
setRangeviolation:AddZone(zoneRangeViolation)
setRangeviolation:AddZone(zoneOrbit)

-- new locals
local trigger = 0

local aaConfig = { 
  mode = "BVR",
  airframe = "MIG21", 
  size = 2
}

local airframes = {
  "MIG21",
  "MIG29A",
  "MIG29S",
  "MIG31",
  "SU27"
}

local r33_BVR_Templates = {
  "Drone_Aggressor_MIG21",
  "Drone_Aggressor_MIG29A",
  "Drone_Aggressor_MIG29S",
  "Drone_Aggressor_MIG31",
  "Drone_Aggressor_SU27"
}

local r33_BFM_Templates = {
  "Drone_Aggressor_MIG29A_BFM",
  "Drone_Aggressor_MIG21_BFM",
  "Drone_Aggressor_MIG29S_BFM",
  "Drone_Aggressor_SU27_BFM"
}


local function bvr(number)

  local random_template = r33_BVR_Templates[math.random(#r33_BVR_Templates)]
  if trigger == 1 then 
    random_template = string.format("Drone_Aggressor_%s", aaConfig.airframe)
  end


  local function flightgroup(group)
    local bvr = FLIGHTGROUP:New(group)
    local mission_racetrack = AUFTRAG:NewORBIT_RACETRACK(zoneOrbit:GetRandomCoordinate(), 26000, 300, 110, 20)
    bvr:SetEngageDetectedOn(60, {"Air"}, setCAP)
    bvr:SetCheckZones(setRangeviolation)
    bvr:AddMission(mission_racetrack)
    env.info(group:GetName().." entering racetrack CAP station in Range 33")


    function bvr:OnAfterDetectedGroupNew(From,Event,To,Group)
      env.info(bvr:GetName().." detected Target "..Group:GetName())
    end

    function bvr:onafterEnterZone(From,Event,To,Zone)
      if Zone == zoneRangeViolation then
        local inzoneOrbit = false
        bvr:MissionStart(mission_racetrack)
        bvr:SetEngageDetectedOff()
        env.info(bvr:GetName().." violated Range 33 Boundary, returning to CAP Station")
        function bvr:onafterEnterZone(From,Event,To,Zone)
          if Zone == zoneOrbit and inzoneOrbit == false then
            inzoneOrbit = true
            env.info(bvr:GetName().." resumed CAP station in Range 33, scanning for Targets")
            bvr:SetEngageDetectedOn(60, {"Air"}, setCAP)
            env.info("reset, fight's on")
          end
        end
      end
    end
  end
  -- Spawn the flight group using the selected template
  local spawnbvr = SPAWN:New(random_template)
  spawnbvr:InitSkill("Average")
  spawnbvr:InitGrouping(number)
  spawnbvr:InitSpeedKnots(500)
  spawnbvr:OnSpawnGroup(flightgroup)
  spawnbvr:SpawnInZone(zoneOrbit, true, 10000, 11000)
end

local function bfm(number)

  local random_template = r33_BFM_Templates[math.random(#r33_BFM_Templates)]
  if trigger == 1 then 
    random_template = string.format("Drone_Aggressor_%s_BFM", aaConfig.airframe)
  end

  local function flightgroup(group)
    local bfm = FLIGHTGROUP:New(group)
    local mission_racetrack = AUFTRAG:NewORBIT_RACETRACK(zoneOrbit:GetRandomCoordinate(), 26000, 300, 110, 20)
    bfm:SetEngageDetectedOn(20, {"Air"}, setCAP)
    bfm:SetCheckZones(setRangeviolation)
    bfm:AddMission(mission_racetrack)
    env.info(group:GetName().." entering racetrack CAP station in Range 33")


    function bfm:OnAfterDetectedGroupNew(From,Event,To,Group)
      env.info(bfm:GetName().." detected Target "..Group:GetName())
    end

    function bfm:onafterEnterZone(From,Event,To,Zone)
      if Zone == zoneRangeViolation then
        local inzoneOrbit = false
        bfm:MissionStart(mission_racetrack)
        bfm:SetEngageDetectedOff()
        env.info(bvr:GetName().." violated Range 33 Boundary, returning to CAP Station")
        function bvr:onafterEnterZone(From,Event,To,Zone)
          if Zone == zoneOrbit and inzoneOrbit == false then
            inzoneOrbit = true
            env.info(bvr:GetName().." resumed CAP station in Range 33, scanning for Targets")
            bfm:SetEngageDetectedOn(60, {"Air"}, setCAP)
            env.info("reset, fight's on")
          end
        end
      end
    end
  end
  -- Spawn the flight group using the selected template
  local spawnbfm = SPAWN:New(random_template)
  spawnbfm:InitSkill("Average")
  spawnbfm:InitGrouping(number)
  spawnbfm:InitSpeedKnots(500)
  spawnbfm:OnSpawnGroup(flightgroup)
  spawnbfm:SpawnInZone(zoneOrbit, true, 10000, 11000)
end

-- New spawner just uses existing model. 
local function aaSpawn()
  trigger = 1
  MESSAGE:New(string.format("Spawning %s %s %d",aaConfig.mode, aaConfig.airframe, aaConfig.size))
  if aaConfig.mode == "BVR" then 
    bvr(aaConfig.size)
  else 
    bfm(aaConfig.size)
  end
end

-- Add the command to the menu, ensure bvr is called when the command is selected
r23_bvr_2 = MENU_MISSION_COMMAND:New("Spawn Hostile 2-ship BVR-Capflight in Range33", range_33_menu_root, function() bvr(2) end)
r23_bvr_4 = MENU_MISSION_COMMAND:New("Spawn Hostile 4-ship BVR-Capflight in Range33", range_33_menu_root, function() bvr(4) end)
r23_bfm_2 = MENU_MISSION_COMMAND:New("Spawn Hostile 2-ship BFM-Capflight in Range33", range_33_menu_root, function() bfm(2) end)
r23_bfm_4 = MENU_MISSION_COMMAND:New("Spawn Hostile 4-ship BFM-Capflight in Range33", range_33_menu_root, function() bfm(4) end)

-- Selectable engagement Menu
local aaMenu = MENU_MISSION:New("AA Engagement",range_33_menu_root)

-- Show current config
local function showConfig() 
    MESSAGE:New(string.format("AA set to: %s against %s %s ship.", aaConfig.mode, aaConfig.airframe, aaConfig.size),10):ToAll()
  end 
MENU_MISSION_COMMAND:New("Show Config", aaMenu, showConfig) 

-- Select Engagement Mode
local function setMode(mode)
  aaConfig.mode = mode
  showConfig()
end
local modeMenu = MENU_MISSION:New("Set Engagement Mode", aaMenu)
for _, mode in ipairs({"BVR", "BFM"}) do
  MENU_MISSION_COMMAND:New(mode, modeMenu, setMode, mode)
end

-- Select airframe
local function setAirframe(name)
  aaConfig.airframe = name
  showConfig()
end
local airframeMenu = MENU_MISSION:New("Set Airframe", aaMenu)
for _, name in ipairs(airframes) do
  MENU_MISSION_COMMAND:New(name, airframeMenu, setAirframe, name)
end
MENU_MISSION_COMMAND:New("Random", airframeMenu, setAirframe,   
  function()
    local rnd = airframes[math.random(#airframes)]
    setAirframe(rnd)
  end
)

-- Select Flight Size
local function setSize(size)
  aaConfig.size = size
  showConfig()
end
local sizeMenu = MENU_MISSION:New("Set Flight Size", aaMenu)
for i = 1, 4 do
  MENU_MISSION_COMMAND:New(i .."-ship", sizeMenu, setSize, i)
end
MENU_MISSION_COMMAND:New("Random", sizeMenu,   
  function()
    local rnd = math.random(1, 4)
    setSize(rnd)
  end
)

-- Spawn Menu Item
MENU_MISSION_COMMAND:New("Spawn Selection", aaMenu, aaSpawn)
