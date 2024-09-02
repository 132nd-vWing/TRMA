-- Create a menu root for Range 23
range_23_menu_root = MENU_MISSION:New("Range 23", range_root_menu19_24)

-- Initialize variables for IADS and spawned units
local redIADS
local spawnedUnits = {}
local areSitesSpawned = false

-- Function to start spawning SAM sites
function start_sam_sites_R23()
start_sams_r23:Remove()
    -- Create an instance of the IADS
    redIADS = SkynetIADS:create('R23_IADS')

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

    -- Define the table with spawn location templates
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
            -- Add to IADS if it's an EWR or SAM site
            if templateName:find("EWR") then
                redIADS:addEarlyWarningRadarsByPrefix(templateName)
            elseif templateName:find("IADS") then
                redIADS:addSAMSitesByPrefix(templateName)
            end
        else
            env.warning("Failed to spawn static SAM template: " .. templateName)
        end
    end

    -- Function to spawn a mobile SAM template at a random location
    local function spawnMobileSam(templateName)
        if #spawnLocationTemplates == 0 then
            env.warning("No spawn location templates available.")
            return
        end

        -- Pick a random location template
        local index = getRandomIndex(spawnLocationTemplates)
        local locationTemplateName = table.remove(spawnLocationTemplates, index)  -- Remove the location template from the list after use

        -- Spawn the location template to get the actual spawn location
        local locationTemplate = SPAWN:New(locationTemplateName)
        local locationGroup = locationTemplate:Spawn()

        -- Check if the location group was successfully spawned
        if not locationGroup then
            env.warning("Failed to spawn location template: " .. locationTemplateName)
            return
        end

        -- Get the position of the first unit in the location group
        local spawnPosition = locationGroup:GetUnits()[1]:GetVec3()

        -- Spawn the mobile SAM template at this location
        local mobileSamTemplate = SPAWN:New(templateName)
        local group = mobileSamTemplate:Spawn(spawnPosition)
        if group then
            env.info("Spawned mobile SAM template: " .. templateName .. " at location template: " .. locationTemplateName)
            -- Track spawned units
            table.insert(spawnedUnits, group)
            -- Add to IADS
            redIADS:addSAMSitesByPrefix(templateName)
        else
            env.warning("Failed to spawn mobile SAM template: " .. templateName)
        end
    end

    -- Function to spawn point defenses
    local function spawnPointDefenses()
        local pointDefenseTemplates = {
            "R23_IADS_SA15_pointdefence_1",
            "R23_IADS_SA15_pointdefence_2",
            "R23_IADS_SA15_pointdefence_3",
            "R23_IADS_SA15_pointdefence_4"
        }

        for _, templateName in ipairs(pointDefenseTemplates) do
            spawnStaticSam(templateName)
        end
    end

    -- Define a function to spawn all groups
    local function spawn_groups()
        -- Spawn all static SAM templates
        for _, templateName in ipairs(staticSams) do
            spawnStaticSam(templateName)
        end

        -- Spawn each mobile SAM template at a random location
        for _, templateName in ipairs(mobileSams) do
            spawnMobileSam(templateName)
        end

        -- Spawn point defenses
        spawnPointDefenses()

        -- Activate the IADS
        if redIADS then
            redIADS:activate()
        end


        env.info("Mission setup complete.")
    end

    -- Start the spawning process
    spawn_groups()
    stop_sams_r23 = MENU_MISSION_COMMAND:New("Stop IADS and Despawn All Units at Range 23", range_23_menu_root,stop_and_despawn)
end

-- Function to stop IADS and despawn all units
function stop_and_despawn()
start_sams_r23 = MENU_MISSION_COMMAND:New("Spawn SAM Sites at Range 23", range_23_menu_root,start_sam_sites_R23)
stop_sams_r23:Remove()
    
    -- Despawn all tracked units
    for _, unit in ipairs(spawnedUnits) do
        if unit then
            unit:Destroy()
            env.info("Despawned unit: " .. unit:GetName())
        end
    end

    -- Clear the list of spawned units
    spawnedUnits = {}


    env.info("All units despawned.")
end
start_sams_r23 = MENU_MISSION_COMMAND:New("Spawn SAM Sites at Range 23", range_23_menu_root,start_sam_sites_R23)
