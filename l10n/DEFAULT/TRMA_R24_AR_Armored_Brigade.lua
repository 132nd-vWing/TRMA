-- Lua script to activate 1 of 3 primary groups, 6 of 12 additional groups, possibly 1 of 3 optional groups, 
-- and 1 of 6 SAM groups.

-- List of the first 3 primary groups
local primaryGroups = {
    "R24_Artillery_battery_1",
    "R24_Artillery_battery_2",
    "R24_Artillery_battery_3"
}

-- List of 12 additional groups
local additionalGroups = {
    "R24_armored_company_1", "R24_armored_company_2", "R24_armored_company_3", "R24_armored_company_4", "R24_armored_company_5", "R24_armored_company_6",
    "R24_armored_company_7", "R24_armored_company_8", "R24_armored_company_9", "R24_armored_company_10", "R24_armored_company_11", "R24_armored_company_12"
}

-- List of the optional groups (one or none will be chosen)
local optionalGroups = {
    "R24_Surface_surface_BN", "R24_Rocket_artillery_BN", "R24_Heavy_Rocket_artillery_BN"
}

-- List of 6 SAM random groups
local samGroups = {
    "R24_SAM_Random1", "R24_SAM_Random2", "R24_SAM_Random3",
    "R24_SAM_Random4", "R24_SAM_Random5", "R24_SAM_Random6"
}

-- Function to activate a random group from the first 3
function activateRandomPrimaryGroup()
    local randomIndex = math.random(1, #primaryGroups)
    local selectedGroup = primaryGroups[randomIndex]
    trigger.action.activateGroup(Group.getByName(selectedGroup))
    --trigger.action.outText("Activating primary group: " .. selectedGroup, 10)
end

-- Function to activate 6 random groups from the additional 12
function activateRandomAdditionalGroups()
    local groupsPool = {unpack(additionalGroups)}
    local selectedGroups = {}
    for i = 1, 6 do
        local randomIndex = math.random(1, #groupsPool)
        local selectedGroup = groupsPool[randomIndex]
        table.insert(selectedGroups, selectedGroup)
        table.remove(groupsPool, randomIndex)
    end
    for _, groupName in ipairs(selectedGroups) do
        trigger.action.activateGroup(Group.getByName(groupName))
        --trigger.action.outText("Activating additional group: " .. groupName, 10)
    end
end

-- Function to optionally activate one group from optional groups, or none
function activateOptionalGroup()
    local shouldActivate = math.random() > 0.5
    if shouldActivate then
        local randomIndex = math.random(1, #optionalGroups)
        local selectedGroup = optionalGroups[randomIndex]
        trigger.action.activateGroup(Group.getByName(selectedGroup))
        --trigger.action.outText("Activating optional group: " .. selectedGroup, 10)
    end
end

-- Function to activate one random SAM group
function activateRandomSAMGroup()
    local randomIndex = math.random(1, #samGroups)
    local selectedGroup = samGroups[randomIndex]
    trigger.action.activateGroup(Group.getByName(selectedGroup))
    --trigger.action.outText("Activating SAM group: " .. selectedGroup, 10)
end

-- Call the functions to activate the groups
activateRandomPrimaryGroup()          -- Activates 1 of the 3 primary groups
activateRandomAdditionalGroups()      -- Activates 6 of the 12 additional groups
activateOptionalGroup()               -- 50% chance to activate 1 of 3 optional groups or none
activateRandomSAMGroup()              -- Activates 1 of 6 SAM groups
