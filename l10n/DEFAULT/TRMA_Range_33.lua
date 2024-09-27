range_33_menu_root = MENU_MISSION:New("Range 33", range_root_menu31_34)
zoneCAP = ZONE_POLYGON:NewFromGroupName("r23_engagezone")

local zoneOrbit = ZONE_POLYGON:NewFromGroupName("r23_patrolzone")

local r34_BVR_Templates = {
  "Drone_Aggressor_MIG21",
  "Drone_Aggressor_MIG29A",
  "Drone_Aggressor_MIG29S",
  "Drone_Aggressor_MIG31",
  "Drone_Aggressor_SU27"
}

-- Function to spawn a random 2-ship BVR flight inside zoneCAP
local function bvr(number)
  -- Randomly select an aircraft type from the BVR templates
  local random_template = r34_BVR_Templates[math.random(#r34_BVR_Templates)]

  -- Flightgroup function, handles mission assignment and actions
  local function flightgroup(group)
    local bvr = FLIGHTGROUP:New(group)
    local mission_racetrack = AUFTRAG:NewORBIT_RACETRACK(zoneOrbit:GetRandomCoordinate(), 26000, 300, 110, 20)

    bvr:SetEngageDetectedOn(60, {"Air"}, zoneCAP)


    bvr:AddMission(mission_racetrack)
    env.info(group:GetName().." entering racetrack CAP station in Range 33")
    
    -- Setup zone leave event to destroy the group
    function bvr:OnAfterDetectedGroupNew(From,Event,To,Group)
      env.info(bvr:GetName().." detected Target "..Group:GetName())
    end

    function zoneCAP:OnAfterLeftZone(From,Event,To,Controllable)
      if Controllable == bvr  then
      bvr:ClearTasks()
      bvr:SetEngageDetectedOn(60, {"Air"}, zoneCAP)
      bvr:AddMission(mission_racetrack)
      env.info(bvr:GetName().." leaving Range 23 Engagement Zone and destroyed.")
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

-- Add the command to the menu, ensure bvr is called when the command is selected
r23_bvr_2 = MENU_MISSION_COMMAND:New("Spawn Hostile 2-ship BVR-Capflight in Range33", range_33_menu_root, function() bvr(2) end)
r23_bvr_4 = MENU_MISSION_COMMAND:New("Spawn Hostile 4-ship BVR-Capflight in Range33", range_33_menu_root, function() bvr(4) end)
