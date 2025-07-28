-- Create a menu root for Range 23
range_23_menu_root = MENU_MISSION:New("Range 23", range_root_menu19_24)

-- Initialize variables for IADS and spawned units
local redIADS
local spawnedUnits = {}
local areSitesSpawned = false
local spawn_delay = 3 -- Delay in seconds for adding SAMs to IADS

-- Function to start spawning SAM sites
function start_sam_sites_R23()
  start_sams_r23:Remove()

  -- Create an instance of the IADS
  redIADS = SkynetIADS:create('R23_IADS')
  -- Export the IADS instance globally so that other scripts (e.g., advanced scramble logic) can access it.  Without this assignment the IADS variable remains local to this file and cannot be referenced from separate modules.  See issue #43 TRMA Github for details.
  _G.redIADS_R23 = redIADS


  -- Define the table with static SAM templates
  local staticSams = {
    "R23_EWR_1",
    "R23_EWR_2",
    "R23_EWR_3",
    "R23_IADS_SA2-1",
    "R23_IADS_SA2-2"
  }

  -- Define the table with mobile SAM templates
  local mobileSams = {
    "R23_IADS_SA6_1",
    "R23_IADS_SA11_1"
  }

  -- Define the table with spawn location template names
  local spawnLocationTemplates = {
    "R23_SAM_SPAWN_1",
    "R23_SAM_SPAWN_2",
    "R23_SAM_SPAWN_3",
    "R23_SAM_SPAWN_4",
    "R23_SAM_SPAWN_5",
    "R23_SAM_SPAWN_6",
    "R23_SAM_SPAWN_7",
    "R23_SAM_SPAWN_8",
    "R23_SAM_SPAWN_9"
  }

  local pointDefenseTemplates = {
    "R23_IADS_SA15_pointdefence_1",
    "R23_IADS_SA15_pointdefence_2"
  }


  -- Function to get a random index from a table
  local function getRandomIndex(tbl)
    return math.random(#tbl)
  end

  -- Function to spawn a static SAM template
  local function spawnStaticSam(templateName)
    local template = SPAWN:New(templateName)
    local group = template:Spawn()
    if group then
      env.info("Spawned static SAM template: " .. templateName)
      -- Track spawned units
      table.insert(spawnedUnits, group)
    else
      env.warning("Failed to spawn static SAM template: " .. templateName)
    end
  end

  -- Function to spawn a mobile SAM template at a specific location
  local function spawnMobileSam(templateName, locationTemplateName)
    -- Find the location template group in the mission
    local locationGroup = GROUP:FindByName(locationTemplateName)
    if not locationGroup then
      env.warning("Location template group not found: " .. locationTemplateName)
      return
    end

    -- Get the position of the location group
    local spawnPosition = locationGroup:GetVec3()

    -- Spawn the mobile SAM template at this location
    local mobileSamTemplate = SPAWN:New(templateName)
    local group = mobileSamTemplate:SpawnFromVec3(spawnPosition)
    if group then
      env.info("Spawned mobile SAM template: " .. templateName .. " at location: " .. locationTemplateName)
      -- Track spawned units
      table.insert(spawnedUnits, group)
    else
      env.warning("Failed to spawn mobile SAM template: " .. templateName)
    end
  end

  -- Function to spawn point defenses
  local function spawnPointDefenses()

    for _, templateName in ipairs(pointDefenseTemplates) do
      spawnStaticSam(templateName)
    end
  end

  -- Function to manually add spawned SAMs and EWRs to the IADS
  local function addSAMsToIADS()
    if redIADS then
      for _, group in ipairs(spawnedUnits) do
        if group:IsAlive() then
          local groupName = group:GetName() -- Get the group name as a string
          local firstUnit = group:GetUnit(1) -- Get the first unit
          local unitName = firstUnit:GetName() -- Get the unit name

          -- Add EWRs to the IADS using unit name
          if unitName:find("R23_EWR_") then
            redIADS:addEarlyWarningRadar(unitName) -- Pass the UNIT name string
            env.info("EWR added to IADS: " .. unitName)

            -- Add SAM sites using group name
          elseif groupName:find("R23_IADS_SA") then
            local sam = redIADS:addSAMSite(groupName) -- Pass the group name string
            env.info("SAM added to IADS: " .. groupName)
          end
        else
          env.warning("Group is not alive: " .. group:GetName())
        end
      end

    else
      env.warning("IADS object (redIADS) is nil.")
    end
    --add pointdefenses
    local point1 = redIADS:getSAMSitesByPrefix("R23_IADS_SA15_pointdefence_1")
    redIADS:getSAMSitesByPrefix("R23_IADS_SA2-1"):addPointDefence(point1):setHARMDetectionChance(100)
    local point2 = redIADS:getSAMSitesByPrefix("R23_IADS_SA15_pointdefence_2")
    redIADS:getSAMSitesByPrefix("R23_IADS_SA2-2"):addPointDefence(point2):setHARMDetectionChance(100)
  end

  -- Function to print all SAM sites added to the IADS
  local function printIADSSamSites()
    local samSites = redIADS:getSAMSites()
    if not samSites or #samSites == 0 then
      env.info("No SAM sites found in IADS.")
    else
      env.info("Total SAM sites in IADS: " .. #samSites)
      for _, samSite in ipairs(samSites) do
        local samName = samSite:getDCSName() -- Get the SAM site name
        if samName then
          env.info("SAM site in IADS: " .. samName)
        else
          env.info("SAM site has no valid name.")
        end
      end
    end
  end

  -- Function to spawn all SAMs
  local function spawn_groups()
    -- Spawn all static SAM templates
    for _, templateName in ipairs(staticSams) do
      spawnStaticSam(templateName)
    end

    -- Spawn 3 mobile SAM groups using random templates and locations
    for i = 1, 3 do
      if #mobileSams == 0 or #spawnLocationTemplates == 0 then
        env.warning("Not enough SAM templates or locations left to spawn all groups.")
        break
      end

      -- Pick a random SAM template
      local selectedSam = mobileSams[getRandomIndex(mobileSams)]
      -- Pick a random location template
      local selectedLocation = table.remove(spawnLocationTemplates, getRandomIndex(spawnLocationTemplates))

      -- Spawn the SAM at the selected location
      spawnMobileSam(selectedSam, selectedLocation)
    end

    -- Spawn point defenses
    spawnPointDefenses()

    -- Print all SAM sites in the IADS
    env.info("Mission setup complete.")
  end

  -- Function to add SAMs to IADS after a delay
  local function addSAMsWithDelay()
    addSAMsToIADS()
    printIADSSamSites()
  end

  -- Start the spawning process
  spawn_groups()

  -- Schedule the function to add SAMs to the IADS after a delay
  timer.scheduleFunction(addSAMsWithDelay, nil, timer.getTime() + spawn_delay)
  redIADS:activate()
  -- Debug settings for IADS
--  local iadsDebug = redIADS:getDebugSettings()
--  iadsDebug.addedEWRadar = true
--  iadsDebug.addedSAMSite = true
--  iadsDebug.warnings = true
--  iadsDebug.radarWentLive = true
--  iadsDebug.radarWentDark = true
--  iadsDebug.harmDefence = true
--  iadsDebug.samSiteStatusEnvOutput = true
--  iadsDebug.earlyWarningRadarStatusEnvOutput = true
--  iadsDebug.commandCenterStatusEnvOutput = true

  -- Set the menu to stop IADS and despawn units
  stop_sams_r23 = MENU_MISSION_COMMAND:New("Stop IADS and Despawn All Units at Range 23", range_23_menu_root, stop_and_despawn)
end

-- Function to stop IADS and despawn all units
function stop_and_despawn()
  start_sams_r23 = MENU_MISSION_COMMAND:New("Spawn SAM Sites at Range 23", range_23_menu_root, start_sam_sites_R23)
  stop_sams_r23:Remove()

  if redIADS then
    redIADS:deactivate()
    env.info("IADS deactivated.")
  end

  -- Despawn all tracked units
  for _, unit in ipairs(spawnedUnits) do
    if unit and unit:IsAlive() then
      unit:Destroy()
      env.info("Despawned unit: " .. unit:GetName())
    end
  end

  -- Clear the list of spawned units
  spawnedUnits = {}

  env.info("All units despawned.")
end

-- SCUD Hunt Scenario activation functions
local function flag_40()
  start_SCUD_HUNT_r23:Remove()
  trigger.action.setUserFlag(40, true)
  MessageToAll("SCUD Hunt Scenario at Range 23 activated")
end

local function flag_46()
  start_SCUD_HUNT_IADS_r23:Remove()
  trigger.action.setUserFlag(46, true)
  MessageToAll("SCUD Hunt Scenario with IADS at Range 23 activated")
end

-- SAT SME and EX GREEN SHIELD
local function flag_22()
  start_EXGS_Course_r23:Remove()
  trigger.action.setUserFlag(22, true)
  MessageToAll("Range 23 EX GREEN SHIELD activated")
end

local function flag_23()
  start_SME_SAT_Course_r23:Remove()
  trigger.action.setUserFlag(23, true)
  MessageToAll("Range 23 SME SAT Course activated")
end

-- Initialize the spawn command
start_sams_r23 = MENU_MISSION_COMMAND:New("Spawn SAM Sites at Range 23", range_23_menu_root, start_sam_sites_R23)
start_SCUD_HUNT_r23 = MENU_MISSION_COMMAND:New("Activate the SCUD Hunt Scenario at Range 23", range_23_menu_root, flag_40)
start_SCUD_HUNT_IADS_r23 = MENU_MISSION_COMMAND:New("Activate the SCUD Hunt Scenario with IADS at Range 23", range_23_menu_root, flag_46)
start_SME_SAT_Course_r23 = MENU_MISSION_COMMAND:New("Activate SME SAT course in range 23", range_23_menu_root, flag_23)
start_EXGS_Course_r23 = MENU_MISSION_COMMAND:New("Activate EX GREEN SHIELD in range 23", range_23_menu_root, flag_22)


