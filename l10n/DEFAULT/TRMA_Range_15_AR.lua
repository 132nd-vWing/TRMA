-- Lua script to activate 1 of 3 primary groups, 6 of 12 additional groups, and possibly 1 of 3 optional groups with a 50% chance of no activation

-- List of the first 3 primary groups
local primaryGroups = {
    "R15_AR_MBT_COY_1",
    "R15_AR_MBT_COY_2",
    "R15_AR_MBT_COY_3"
}

-- List of 12 additional groups
local additionalGroups = {
    "R15_AR_IFV_PLT_1", "R15_AR_IFV_PLT_2", "R15_AR_IFV_PLT_3", "R15_AR_IFV_PLT_4", "R15_AR_IFV_PLT_5", "R15_AR_IFV_PLT_6",
    "R15_AR_IFV_PLT_7", "R15_AR_IFV_PLT_8", "R15_AR_IFV_PLT_9", "R15_AR_IFV_PLT_10", "R15_AR_IFV_PLT_11", "R15_AR_IFV_PLT_12"
}

-- List of the optional groups (one or none will be chosen)
local optionalGroups = {
    "R15_AR_Arty_1", "R15_AR_Arty_2", "R15_AR_Arty_3"
}

-- Function to activate a random group from the first 3
function activateRandomPrimaryGroup()
    -- Select a random index between 1 and the number of primary groups
    local randomIndex = math.random(1, #primaryGroups)
    
    -- Get the group name for the selected index
    local selectedGroup = primaryGroups[randomIndex]
    
    -- Activate the group
    trigger.action.activateGroup(Group.getByName(selectedGroup))

    -- Print a message to confirm which group was activated (optional, for debug)
    --trigger.action.outText("Activating primary group: " .. selectedGroup, 10)
end

-- Function to activate 6 random groups from the additional 12
function activateRandomAdditionalGroups()
    -- Create a copy of the additional groups table to work with
    local groupsPool = {unpack(additionalGroups)}
    
    -- Table to store the 6 selected groups
    local selectedGroups = {}
    
    -- Select 6 unique groups
    for i = 1, 6 do
        -- Select a random index from the remaining groups
        local randomIndex = math.random(1, #groupsPool)
        
        -- Get the group name for the selected index
        local selectedGroup = groupsPool[randomIndex]
        
        -- Add selected group to the table
        table.insert(selectedGroups, selectedGroup)
        
        -- Remove the selected group from the pool to prevent duplicates
        table.remove(groupsPool, randomIndex)
    end
    
    -- Activate the selected groups
    for _, groupName in ipairs(selectedGroups) do
        trigger.action.activateGroup(Group.getByName(groupName))
        -- Print a message to confirm which groups were activated (optional, for debug)
        --trigger.action.outText("Activating additional group: " .. groupName, 10)
    end
end

-- Function to optionally activate one group from optional groups, or none
function activateOptionalGroup()
    -- 50% chance to skip activation
    local shouldActivate = math.random() > 0.5
    
    if shouldActivate then
        -- Select a random group from the optional list
        local randomIndex = math.random(1, #optionalGroups)
        
        -- Get the group name for the selected index
        local selectedGroup = optionalGroups[randomIndex]
        
        -- Activate the group
        trigger.action.activateGroup(Group.getByName(selectedGroup))
        
        -- Print a message to confirm which optional group was activated (optional, for debug)
        --trigger.action.outText("Activating optional group: " .. selectedGroup, 10)
    --else
        -- Print a message to confirm no optional group was activated (optional, for debug)
        --trigger.action.outText("No optional group activated", 10)
    end
end

-- Call the functions to activate the groups
activateRandomPrimaryGroup()          -- Activates 1 of the 3 primary groups
activateRandomAdditionalGroups()      -- Activates 6 of the 12 additional groups
activateOptionalGroup()               -- 50% chance to activate 1 of 3 optional groups or none
