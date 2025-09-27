-- local variables
local zoneCAP = ZONE_POLYGON:New("zoneCAP",GROUP:FindByName("r23_engagezone"))
local zoneOrbit = ZONE_POLYGON:New("zoneOrbit",GROUP:FindByName("r23_patrolzone"))
local zoneRangeViolation = ZONE_POLYGON:New("zoneRangeViolation",GROUP:FindByName("r23_range_violation"))

local setCAP = SET_ZONE:New()
local setRangeviolation= SET_ZONE:New()
local setOrbit = SET_ZONE:New()

setCAP:AddZone(zoneCAP)
setRangeviolation:AddZone(zoneRangeViolation)
setRangeviolation:AddZone(zoneOrbit)

-- Defaul spawn group and config store
local aaConfig = { 
  mode = "BVR",
  airframe = "MIG29A", 
  size = 2
}
local aaRandom = 0
local airframes = {
  "MIG21",
  "MIG29A",
  "MIG29S",
  "MIG31",
  "SU27"
}

local function a2a()
  
  MESSAGE:New(string.format("R33: Spawning %s %s %d",aaConfig.mode, aaConfig.airframe, aaConfig.size))

  -- find mode, airframe, size
  local mode = aaConfig.mode
  local template
  local number

  if aaRandom == 1 then 
    template = string.format("Drone_Aggressor_%s", airframes[math.random(#airframes)])
    number = math.random(1, 4)
    aaRandom = 0
  else 
    template = string.format("Drone_Aggressor_%s", aaConfig.airframe)
    number = aaConfig.size
  end
    
  if aaConfig.mode == "BFM" then 
    template = template.."_BFM"
  end

  if template == "Drone_Aggressor_MIG31_BFM" then
    template = "Drone_Aggressor_MIG21_BFM" -- switch MIG31 BFM to MIG21
  end

  local function flightgroup(group)
    local a2a = FLIGHTGROUP:New(group)
    local mission_racetrack = AUFTRAG:NewORBIT_RACETRACK(zoneOrbit:GetRandomCoordinate(), 26000, 300, 110, 20)
    if mode == "BFM" then
      a2a:SetEngageDetectedOn(20, {"Air"}, setCAP)
    else
      a2a:SetEngageDetectedOn(60, {"Air"}, setCAP)
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
              a2a:SetEngageDetectedOn(20, {"Air"}, setCAP)
            else
              a2a:SetEngageDetectedOn(60, {"Air"}, setCAP)
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
  spawna2a:InitGrouping(number)
  spawna2a:InitSpeedKnots(500)
  spawna2a:InitRandomizeCallsign()
  spawna2a:OnSpawnGroup(flightgroup)
  spawna2a:SpawnInZone(zoneOrbit, true, 10000, 11000)
end

-- Menu references
local r33Menu

-- Show current config - not required as its in the menu item now. 
local function showConfig()
  MESSAGE:New(string.format("R33 AA set to: %s %s %s-ship.", aaConfig.mode, aaConfig.airframe, aaConfig.size),10):ToAll()
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
      if aaConfig.airframe == "MIG31" and mode == "BFM" then
        MESSAGE:New("BFM against MIG31 not supported.", 10):ToAll()
      else
        aaConfig.mode = mode
        BuildAAMenu()
        --showConfig()
      end
    end)
  end

  -- === Airframe Menu ===
  local airframeMenu = MENU_MISSION:New("Set Airframe", r33Menu)

  for _, name in ipairs(airframes) do
    MENU_MISSION_COMMAND:New(name, airframeMenu, function()
      if aaConfig.mode == "BFM" and name == "MIG31" then
        MESSAGE:New("BFM against MIG31 not supported.", 10):ToAll()
      else
        aaConfig.airframe = name
        BuildAAMenu()
        --showConfig()
      end
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

  -- === Spawn Menu Item ===
  local spawnTitle = string.format("Spawn %s %s %d-ship", aaConfig.mode, aaConfig.airframe, aaConfig.size)
  MENU_MISSION_COMMAND:New(spawnTitle, r33Menu, a2a)
  MENU_MISSION_COMMAND:New(string.format("Spawn random %s Cap flight",aaConfig.mode), r33Menu, function()
    aaRandom = 1
    a2a()  
  end)

end

-- Initial build
BuildAAMenu()


