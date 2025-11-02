-- R33 A2A 1.5
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

local aaMode = "BVR" -- or "BFM"

-- Airframes in mission
local airframes = {
  "MIG23",
  "MIG29A",
  "SU30",
  "JF17",
  "MIG25",
  "SU27",
  "J11A",
  "MIG31"
}

-- Default spawn group and config store
local aaConfig = { 
  airframe = "JF17", 
  size = 2,
  patrolzone = "RANDOM", -- options: RANDOM, 1, 2, 3
  random = false -- true = airframe and flight size
}
-- === Preset A2A group definitions ===
local presets = {
  {
    airframe = "MIG23",
    size = 2, 
    zone = 3
  },
  {
    airframe = "MIG29A",
    size = 2, 
    zone = 1
  },
  {
    airframe = "SU30",
    size = 2, 
    zone = 2
  } 
}

local function a2a(airframe, size, zone)
  local mode = aaMode

  -- select airframe and size
  if aaConfig.random then 
    airframe = airframes[math.random(#airframes)]
    size = math.random(1,4)
  else
    airframe = airframe or aaConfig.airframe
    size = size or aaConfig.size
  end

  -- select patrol zone
  if zone then 
    zoneIndex = tonumber(zone)
  elseif aaConfig.random or aaConfig.patrolzone == "RANDOM" then
    zoneIndex = math.random(#patrolZones)
  else 
    zoneIndex = tonumber(aaConfig.patrolzone)
  end
  
  local zoneOrbit = patrolZones[zoneIndex]

  -- set range violation zones. 
  local setRangeviolation = SET_ZONE:New()
  setRangeviolation:AddZone(zoneRangeViolation)
  setRangeviolation:AddZone(zoneOrbit)
 
  -- build template
  local template = string.format("Drone_Aggressor_%s", airframe)
  if mode == "BFM" then 
    template = template.."_BFM"
  end

  -- send message
  local zoneLabel = string.format("Zone %d", zoneIndex)
  if aaConfig.random then 
    MESSAGE:New(string.format( "R33: Spawning random CAP flight." ), 10):ToAll()
  else
    MESSAGE:New(string.format( "R33: Spawning %s %s %d-ship in %s.", mode, airframe, size, zoneLabel ), 10):ToAll()
  end

  local function flightgroup(group)
    local a2a = FLIGHTGROUP:New(group)
    local mission_racetrack = AUFTRAG:NewORBIT_RACETRACK(zoneOrbit:GetRandomCoordinate(), math.random(20000, 30000), 300, 110, 20)
    
    if mode == "BFM" then
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
            if mode == "BFM" then 
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

-- Build the whole menu system
local function BuildAAMenu()
  if r33Menu then r33Menu:Remove() end
  r33Menu = MENU_MISSION:New("Range 33", range_root_menu31_34)


  -- Mode Menu
  local modeMenu = MENU_MISSION:New(string.format("Engagement Mode (%s)", aaMode), r33Menu)
  for _, mode in ipairs({"BVR", "BFM"}) do
    local display = (mode == aaMode) and (mode .. " ★") or mode
    MENU_MISSION_COMMAND:New(display, modeMenu, function()
      aaMode = mode
      BuildAAMenu()
    end)
  end

  -- Preset Spawns
  for _, preset in ipairs(presets) do
    local display = string.format("Preset %d-ship %s", preset.size, preset.airframe)
    MENU_MISSION_COMMAND:New(display, r33Menu, function()
      a2a(preset.airframe, preset.size, preset.zone)
    end)
  end

  -- custom Spawn
  local customLabel = string.format("Custom %d-ship %s", aaConfig.size, aaConfig.airframe)
  MENU_MISSION_COMMAND:New(customLabel, r33Menu, function()
    a2a()
  end)
  
  -- custom config menu
  local configMenu = MENU_MISSION:New("Configure Custom Group", r33Menu)

  -- Group Size
  local sizeMenu = MENU_MISSION:New("Set Flight Size", configMenu)
  for i = 1, 4 do
    local display = (i == aaConfig.size) and (i .. "-ship ★") or (i .. "-ship")
    MENU_MISSION_COMMAND:New(display, sizeMenu, function()
      aaConfig.size = i
      BuildAAMenu()
    end)
  end

  -- Airframe Menu
  local airframeMenu = MENU_MISSION:New("Set Airframe", configMenu)
  for _, name in ipairs(airframes) do
    local display = (name == aaConfig.airframe) and (name .. " ★") or name
    MENU_MISSION_COMMAND:New(display, airframeMenu, function()
      aaConfig.airframe = name
      BuildAAMenu()
    end)
  end

  -- Patrol Zone Menu
  local patrolMenu = MENU_MISSION:New("Set Patrol Zone", configMenu)
  for _, label in ipairs({"RANDOM", "1", "2", "3"}) do
    local display = (label == aaConfig.patrolzone) and
                    ((label == "RANDOM") and "Random ★" or ("Zone " .. label .. " ★")) or
                    ((label == "RANDOM") and "Random" or ("Zone " .. label))
    MENU_MISSION_COMMAND:New(display, patrolMenu, function()
      aaConfig.patrolzone = label
      BuildAAMenu()
    end)

    -- Random Spawn
    MENU_MISSION_COMMAND:New(string.format("Spawn random %s Cap flight", aaMode), r33Menu, function()
      aaConfig.random = true
      a2a()
      aaConfig.random = false 
    end)
  end
end

-- Initial build
BuildAAMenu()


