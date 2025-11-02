-- R33 A2A 1.4
-- engagement zone definition
local zoneCAP = ZONE_POLYGON:New("zoneCAP",GROUP:FindByName("R33_engagezone"))
local setCAP = SET_ZONE:New()
setCAP:AddZone(zoneCAP)

-- violation zone definition
local zoneRangeViolation = ZONE_POLYGON:New("zoneRangeViolation",GROUP:FindByName("R33_range_violation")) 

-- patrol/spawn zone definition
local patrolZones = {
  ZONE_POLYGON:New("R33_patrolzone", GROUP:FindByName("R33_patrolzone")),
  ZONE_POLYGON:New("R33_patrolzone_2", GROUP:FindByName("R33_patrolzone_2")),
  ZONE_POLYGON:New("R33_patrolzone_3", GROUP:FindByName("R33_patrolzone_3"))
}
local zoneOrbit = patrolZones[1]  -- default spawnzone

-- local setOrbit = SET_ZONE:New()



-- Default spawn group and config store
local aaConfig = { 
  mode = "BVR",
  airframe = "MIG29A", 
  size = 2,
  patrolzone = "RANDOM", -- options: RANDOM, 1, 2, 3
  random = false -- true = airframe and flight size
}
local aaRandom = 0
local airframes = {
  "MIG21",
  "MIG29A",
  "MIG29S",
  "MIG31",
  "SU27",
  "MIG25",
  "J11A"
}

local function a2a()

  -- select patrol zone
  local zoneIndex
  if aaConfig.random or aaConfig.patrolzone == "RANDOM" then
    zoneIndex = math.random(#patrolZones)
  else
    zoneIndex = tonumber(aaConfig.patrolzone)
  end
  local zoneOrbit = patrolZones[zoneIndex]

  -- set range violation zones. 
  local setRangeviolation = SET_ZONE:New()
  setRangeviolation:AddZone(zoneRangeViolation)
  setRangeviolation:AddZone(zoneOrbit)

  -- set airframe and flight size
  local airframe = aaConfig.random and airframes[math.random(#airframes)] or aaConfig.airframe
  local size = aaConfig.random and math.random(1, 4) or aaConfig.size
  
  -- build template
  local template = string.format("Drone_Aggressor_%s", airframe)
  if aaConfig.mode == "BFM" then 
    template = template.."_BFM"
  end

  -- send message
  local zoneLabel = string.format("Zone %d", zoneIndex)
  if aaConfig.random then 
    MESSAGE:New(string.format( "R33: Spawning random CAP flight." ), 10):ToAll()
  else
    MESSAGE:New(string.format( "R33: Spawning %s %s %d-ship in %s.", aaConfig.mode, airframe, size, zoneLabel ), 10):ToAll()
  end

  local function flightgroup(group)
    local a2a = FLIGHTGROUP:New(group)
    local mission_racetrack = AUFTRAG:NewORBIT_RACETRACK(zoneOrbit:GetRandomCoordinate(), math.random(20000, 30000), 300, 110, 20)
    
    if aaConfig.mode == "BFM" then
      a2a:SetEngageDetectedOn(40, {"Air"}, setCAP)
    else
      a2a:SetEngageDetectedOn(185, {"Air"}, setCAP)
    end
    
    a2a:SetCheckZones(setRangeviolation)
    a2a:AddMission(mission_racetrack)
    env.info(group:GetName().." entering racetrack CAP station in Range 33")

    function a2a:OnAfterDetectedGroupNew(From,Event,To,Group)
      env.info(a2a:GetName().." detected Target "..Group:GetName())
    end

    function a2a:onafterEnterZone(From,Event,To,Zone)
      if Zone == zoneRangeViolation then
        local inzoneOrbit = false
        a2a:MissionStart(mission_racetrack)
        a2a:SetEngageDetectedOff()
        env.info(a2a:GetName().." violated Range 33 Boundary, returning to CAP Station")
        function a2a:onafterEnterZone(From,Event,To,Zone)
          if Zone == zoneOrbit and inzoneOrbit == false then
            inzoneOrbit = true
            env.info(a2a:GetName().." resumed CAP station in Range 33, scanning for Targets")
            if aaConfig.mode == "BFM" then 
              a2a:SetEngageDetectedOn(40, {"Air"}, setCAP)
            else
              a2a:SetEngageDetectedOn(185, {"Air"}, setCAP)
            end
            env.info("reset, fight's on")
          end
        end
      end
    end
  end
  -- Spawn the flight group using the selected template
  local alias = template .. "-" .. tostring(math.random(100000))
  local spawna2a = SPAWN:NewWithAlias(template, alias)
  spawna2a:InitLimit(3, 0)
  spawna2a:InitSkill("Average")
  spawna2a:InitGrouping(size)
  spawna2a:InitSpeedKnots(500)
  spawna2a:InitRandomizeCallsign()
  spawna2a:OnSpawnGroup(flightgroup)
  spawna2a:SpawnInZone(zoneOrbit, true, 10000, 11000)
end

-- Menu references
local r33Menu

-- Show current config - not required as its in the menu item now. 
local function showConfig()
  MESSAGE:New(string.format("R33 AA set to: %s %s %s-ship .", aaConfig.mode, aaConfig.airframe, aaConfig.size),10):ToAll()
end

-- Build the whole menu system
local function BuildAAMenu()
  if r33Menu then r33Menu:Remove() end
  r33Menu = MENU_MISSION:New("Range 33", range_root_menu31_34)

  -- Show Config
  MENU_MISSION_COMMAND:New("Show Config", r33Menu, showConfig)

  -- === Mode Menu ===
  local modeMenu = MENU_MISSION:New("Set Engagement Mode", r33Menu)

  for _, mode in ipairs({"BVR", "BFM"}) do
    MENU_MISSION_COMMAND:New(mode, modeMenu, function()
      aaConfig.mode = mode
      BuildAAMenu()
    end)
  end

  -- === Airframe Menu ===
  local airframeMenu = MENU_MISSION:New("Set Airframe", r33Menu)

  for _, name in ipairs(airframes) do
    MENU_MISSION_COMMAND:New(name, airframeMenu, function()
      aaConfig.airframe = name
      BuildAAMenu()
    end)
  end

  -- === Size Menu ===
  local sizeMenu = MENU_MISSION:New("Set Flight Size", r33Menu)
  for i = 1, 4 do
    MENU_MISSION_COMMAND:New(i.."-ship", sizeMenu, function()
      aaConfig.size = i
      BuildAAMenu()
      --showConfig()
    end)
  end

  -- === Patrol Zone Menu ===
  local patrolMenu = MENU_MISSION:New("Set Patrol Zone", r33Menu)
  for i, label in ipairs({"RANDOM", "1", "2", "3"}) do
    local display = (label == "RANDOM") and "Random" or ("Zone " .. label)
    MENU_MISSION_COMMAND:New(display, patrolMenu, function()
      aaConfig.patrolzone = label
      BuildAAMenu()
    end)
  end

  -- === Spawn Menu Item ===
  local spawnTitle = string.format("Spawn %s %s %d-ship", aaConfig.mode, aaConfig.airframe, aaConfig.size)
  MENU_MISSION_COMMAND:New(spawnTitle, r33Menu, a2a)
  MENU_MISSION_COMMAND:New(string.format("Spawn random %s Cap flight",aaConfig.mode), r33Menu, function()
    aaConfig.random = true
    a2a()
    aaConfig.random = false 
  end)

end

-- Initial build
BuildAAMenu()


