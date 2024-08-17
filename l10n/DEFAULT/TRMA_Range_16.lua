range_16_menu_root = MENU_MISSION:New("Range 16",range_root_menu13_18)
range_16_scenario = {}

local function range_16_clear_menu()
  for k, v in pairs(range_16_scenario) do
    v:Remove()
    range_16_scenario[k] = nil
  end
end

local function range16_AR_Mech_Division()
  range_16_clear_menu()


-- List of template groups for Regular mechanized units
local regularMechanizedUnits = {
  "R16_Mech_Coy-0", "R16_Mech_Coy-1", "R16_Mech_Coy-2", "R16_Mech_Coy-3", "R16_Mech_Coy-4",
  "R16_Mech_Coy-5", "R16_Mech_Coy-6", "R16_Mech_Coy-7", "R16_Mech_Coy-8", "R16_Mech_Coy-9",
  "R16_Mech_Coy-10", "R16_Mech_Coy-11", "R16_Mech_Coy-12", "R16_Mech_Coy-13", "R16_Mech_Coy-14",
  "R16_Mech_Coy-15", "R16_Mech_Coy-16", "R16_Mech_Coy-17", "R16_Mech_Coy-18", "R16_Mech_Coy-19",
  "R16_Mech_Coy-20", "R16_Mech_Coy-21", "R16_Mech_Coy-22", "R16_Mech_Coy-23", "R16_Mech_Coy-24",
  "R16_Mech_Coy-25", "R16_Mech_Coy-26", "R16_Mech_Coy-27", "R16_Mech_Coy-28", "R16_Mech_Coy-29",
  "R16_Mech_Coy-30"
}

-- List of template groups for Artillery
local artillery = {
  "R16_Artillery battery-1", "R16_Artillery battery-2", "R16_Artillery battery-3", 
  "R16_Artillery battery-4", "R16_Artillery battery-5", "R16_Artillery battery-6", 
  "R16_Artillery battery-7", "R16_Artillery battery-8"
}

-- List of template groups for SAMs
local sams = {
  "R16_Air_defense_battery-1", "R16_Air_defense_battery-2", "R16_Air_defense_battery-3", 
  "R16_Air_defense_battery-4", "R16_Air_defense_battery-5"
}

-- List of template groups for Rocket Artillery
local rocketArtillery = {
  "R16_Rocket_Arty_BN-1", "R16_Rocket_Arty_BN-2", "R16_Rocket_Arty_BN-3"
}

-- List of template groups for Time sensitive targets
local timeSensitiveTargets = {
  -- Replace with the actual names of the groups in the fifth table
  "R16_Fifth_Group-1", "R16_Fifth_Group-2", "R16_Fifth_Group-3", 
  "R16_Fifth_Group-4", "R16_Fifth_Group-5"
}

-- Function to shuffle the templateGroups array
local function shuffle(tbl)
  for i = #tbl, 2, -1 do
    local j = math.random(1, i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
end

-- Shuffle all template groups
shuffle(regularMechanizedUnits)
shuffle(artillery)
shuffle(sams)
shuffle(rocketArtillery)
shuffle(timeSensitiveTargets)


-- Function to spawn a group and disable its AI
local function spawnAndDisableAI(groupName)
  local spawnedGroup = SPAWN:New(groupName)
  spawnedGroup:InitAIOn():Spawn()
end

-- Randomly choose the number of groups to activate from all tables
local numGroupsToActivate1 = math.random(5, 19)  -- Regular mechanized units
local numGroupsToActivate2 = math.random(1, 4)   -- Artillery
local numGroupsToActivate3 = math.random(0, 3)   -- SAMs

-- Select the desired number of groups from the shuffled lists
local selectedGroups1 = { unpack(regularMechanizedUnits, 1, numGroupsToActivate1) }
local selectedGroups2 = { unpack(artillery, 1, numGroupsToActivate2) }
local selectedGroups3 = { unpack(sams, 1, numGroupsToActivate3) }

-- Spawn the selected groups from the Regular mechanized units
for _, groupName in ipairs(selectedGroups1) do
  spawnAndDisableAI(groupName)
end

-- Spawn the selected groups from the Artillery
for _, groupName in ipairs(selectedGroups2) do
  spawnAndDisableAI(groupName)
end

-- Spawn the selected groups from the SAMs
for _, groupName in ipairs(selectedGroups3) do
  spawnAndDisableAI(groupName)
end

-- 50% chance to spawn a group from the Rocket Artillery
if math.random() <= 0.5 then
  local selectedGroup4 = rocketArtillery[math.random(#rocketArtillery)]
  spawnAndDisableAI(selectedGroup4)
  env.info(string.format("Rocket Artillery %s activated.", selectedGroup4))
else
  env.info("No Rocket Artillery activated.")
end

-- 25% chance to spawn 1 or 2 groups from the Time sensitive targets
if math.random() <= 0.25 then
  local numGroupsToActivate5 = math.random(1, 2)
  local selectedGroups5 = { unpack(timeSensitiveTargets, 1, numGroupsToActivate5) }
  
  for _, groupName in ipairs(selectedGroups5) do
    spawnAndDisableAI(groupName)
  end
  
  env.info(string.format("%d groups activated from the Time sensitive targets.", numGroupsToActivate5))
else
  env.info("No groups activated from the Time sensitive targets.")
end

env.info(string.format("%d random groups activated from the Regular mechanized units.", numGroupsToActivate1))
env.info(string.format("%d random groups activated from the Artillery.", numGroupsToActivate2))
env.info(string.format("%d random groups activated from the SAMs.", numGroupsToActivate3))
   
  MessageToAll("R16 AR scenario: Mechanized Division activated")
end







MENU_MISSION_COMMAND:New("Activate R16 AR scenario: Mechanized Division",range_16_menu_root,range16_AR_Mech_Division)
