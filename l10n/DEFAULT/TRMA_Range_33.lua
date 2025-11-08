-- R33 A2A 1.6
-- change spawn groups to all configable.
-- mapped zones to north/centre/south 

-- engagement zone definition
local zoneCAP = ZONE_POLYGON:New("zoneCAP",GROUP:FindByName("R33_engagezone"))
local setCAP = SET_ZONE:New()
setCAP:AddZone(zoneCAP)

-- violation zone definition
local zoneRangeViolation = ZONE_POLYGON:New("zoneRangeViolation",GROUP:FindByName("R33_range_violation")) 

-- patrol/spawn zone definition
local patrolZones = {
  { name = "North", zone = ZONE_POLYGON:New("R33_patrolzone_3", GROUP:FindByName("R33_patrolzone_3")) },
  { name = "Centre", zone = ZONE_POLYGON:New("R33_patrolzone", GROUP:FindByName("R33_patrolzone")) },
  { name = "South", zone = ZONE_POLYGON:New("R33_patrolzone_2", GROUP:FindByName("R33_patrolzone_2")) },
}
local zoneOrbit = patrolZones[1].zone  -- default spawnzone

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

-- Configurable CAP Group Definitions 
local capGroups = {
  {
    airframe = "MIG23",
    size = 2,
    zone = 1, -- North
  },
  {
    airframe = "MIG29A",
    size = 2,
    zone = 2, -- Centre
  },
  {
    airframe = "SU30",
    size = 2,
    zone = 3, -- South
  },
  {
    airframe = "JF17",
    size = 2,
    zone = 2, -- Centre
  },
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
  
  local zoneOrbit = patrolZones[zoneIndex].zone
  local zoneLabel = patrolZones[zoneIndex].name

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

-- Spawn one of the configured CAP groups
local function SpawnCapGroup(groupIndex)
  local cfg = capGroups[groupIndex]
  if not cfg then
    env.error("Invalid CAP group index: " .. tostring(groupIndex))
    return
  end

  a2a(cfg.airframe, cfg.size, cfg.zone)
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

  -- Group Spawns
  for i = 1, 4 do
    local cfg = capGroups[i]
    local zoneName = patrolZones[cfg.zone].name
    local label = string.format("Group %d: %d-ship %s %s", i, cfg.size, cfg.airframe, zoneName)
    MENU_MISSION_COMMAND:New(label, r33Menu, function()
      SpawnCapGroup(i)
    end)
  end

    -- Random Spawn
  MENU_MISSION_COMMAND:New(string.format("Spawn random %s Group", aaMode), r33Menu, function()
    aaConfig.random = true
    a2a()
    aaConfig.random = false 
  end)

  -- Configure Groups
  local configGroupsMenu = MENU_MISSION:New("Configure Groups", r33Menu)

  for i = 1, 4 do
    local cfg = capGroups[i]
    local zoneName = patrolZones[cfg.zone].name
    local groupMenu = MENU_MISSION:New(string.format("Configure Group %d", i), configGroupsMenu)

    -- Set Size
    local sizeMenu = MENU_MISSION:New("Set Size", groupMenu)
    for s = 1, 4 do
      local label = (cfg.size == s) and string.format("%d-ship ★", s) or string.format("%d-ship", s)
      MENU_MISSION_COMMAND:New(label, sizeMenu, function()
        cfg.size = s
        BuildAAMenu()
      end)
    end

    -- Set Airframe
    local airframeMenu = MENU_MISSION:New("Set Airframe", groupMenu)
    for _, name in ipairs(airframes) do
      local label = (cfg.airframe == name) and (name .. " ★") or name
      MENU_MISSION_COMMAND:New(label, airframeMenu, function()
        cfg.airframe = name
        BuildAAMenu()
      end)
    end

    -- Set Patrol Zone
    local zoneMenu = MENU_MISSION:New("Set Patrol Zone", groupMenu)
    for index, entry in ipairs(patrolZones) do
      local label = (cfg.zone == index) and (entry.name .. " ★") or entry.name
      MENU_MISSION_COMMAND:New(label, zoneMenu, function()
        cfg.zone = index
        BuildAAMenu()
      end)
    end
  end

end

-- Initial build
BuildAAMenu()


