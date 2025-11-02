----------------------------------------------------------------
-- Assumes MIST and MOOSE are already loaded!
-- This script integrates the requested functionality into
-- the "Range 24" submenu under "RANGES 19-24".
----------------------------------------------------------------

-- Create the Range 24 menu under RANGES 19-24 (assuming it exists)
-- Example:
-- range_root_menu = MENU_MISSION:New("Ranges")
-- range_root_menu19_24 = MENU_MISSION:New("RANGES 19-24", range_root_menu)
-- This script should run after the above is set.

local range_24_menu_root = MENU_MISSION:New("Range 24", range_root_menu19_24)

----------------------------------------------------------------
-- Utility Functions
----------------------------------------------------------------

local function activateGroup(groupName)
    local grp = Group.getByName(groupName)
    if not grp or not grp:isExist() then
        mist.respawnGroup(groupName, true)
    else
        mist.respawnGroup(groupName, true)
    end
end

local function deactivateGroup(groupName)
    local grp = Group.getByName(groupName)
    if grp and grp:isExist() then
        grp:destroy()
    end
end

local function sendMessage(msg, duration)
    MESSAGE:New(msg, duration):ToAll()
end

-- Function to activate/deactivate mobile SAMs and their artillery.
-- samName: string - the name of the SAM group
-- artyName: string - the name of the associated artillery group
-- zonesTable: table - a list of one or more zone names for random placement
local function activateMobileSAM(samName, artyName, zonesTable)
    local zoneName
    if #zonesTable > 1 then
        zoneName = zonesTable[math.random(#zonesTable)]
    else
        zoneName = zonesTable[1]
    end

    mist.respawnGroup(samName, true)

    local zData = trigger.misc.getZone(zoneName)
    if zData then
        local point = mist.getRandPointInCircle(zData.point, zData.radius)
        mist.teleportToPoint({
            groupName = samName,
            point = point,
            action = "teleport"
        })
    end

    mist.respawnGroup(artyName, true)
    sendMessage(samName .. " (and associated artillery) Activated!", 5)
end

local function deactivateMobileSAM(samName, artyName)
    deactivateGroup(samName)
    deactivateGroup(artyName)
    sendMessage(samName .. " and associated artillery Deactivated!", 5)
end

local function activateStaticSAM(samName)
    activateGroup(samName)
    sendMessage(samName .. " Activated!", 5)
end

local function deactivateStaticSAM(samName)
    deactivateGroup(samName)
    sendMessage(samName .. " Deactivated!", 5)
end

----------------------------------------------------------------
-- Part 1: Static SAM Activation/Deactivation
----------------------------------------------------------------
local staticSAMs = {
    "R24_SA-10 site_static",
    "R24_SA-2_site_static",
    "R24_SA-6_site_static"
}

local range_24_static_sam_menu = MENU_MISSION:New("Static SAM Control", range_24_menu_root)

for _, samName in ipairs(staticSAMs) do
    local samMenu = MENU_MISSION:New(samName, range_24_static_sam_menu)
    MENU_MISSION_COMMAND:New("Activate " .. samName, samMenu, activateStaticSAM, samName)
    MENU_MISSION_COMMAND:New("Deactivate " .. samName, samMenu, deactivateStaticSAM, samName)
end

----------------------------------------------------------------
-- Part 2 & 3: Mobile SAMs and associated artillery
----------------------------------------------------------------
local mobileSAMs = {
    { 
      samName = "R24_SA-8_mobile", 
      artyName = "R24_rocket_arty_BN_SA8", 
      zones = {"R24_SA-8_mobile_random_zone"} 
    },
    { 
      samName = "R24_SA-19_mobile", 
      artyName = "R24_rocket_arty_BN_SA19", 
      zones = {"R24_SA-19_mobile_random_zone"} 
    },
    { 
      samName = "R24_SA-15_mobile", 
      artyName = "R24_rocket_arty_BN_SA15", 
      zones = {"R24_SA-15_mobile_random_zone"} 
    },
    { 
      samName = "R24_SA-11_mobile", 
      artyName = "R24_rocket_arty_BN_SA11", 
      zones = {
        "R24_SA-11_mobile_random_zone_1",
        "R24_SA-11_mobile_random_zone_2",
        "R24_SA-11_mobile_random_zone_3",
        "R24_SA-11_mobile_random_zone_4"
      } 
    }
}

local range_24_mobile_sam_menu = MENU_MISSION:New("Mobile SAM Control", range_24_menu_root)

for _, samData in ipairs(mobileSAMs) do
    local samMenu = MENU_MISSION:New(samData.samName, range_24_mobile_sam_menu)
    MENU_MISSION_COMMAND:New("Activate " .. samData.samName, samMenu, activateMobileSAM, samData.samName, samData.artyName, samData.zones)
    MENU_MISSION_COMMAND:New("Deactivate " .. samData.samName, samMenu, deactivateMobileSAM, samData.samName, samData.artyName)
end

----------------------------------------------------------------
-- Part 4: IADS
----------------------------------------------------------------
local iadsGroups = {
    "R24_IADS_Army_SBORKA",
    "R24_IADS_Army_SA_15_BN",
    "R24_IADS_Army_SA_8_BN",
    "R24_rocket_arty_BN_IADS"
}

local function activateIADS()
    for _, gName in ipairs(iadsGroups) do
        activateGroup(gName)
    end
    trigger.action.setUserFlag("21", 1)
    sendMessage("IADS Activated", 5)
end

local function deactivateIADS()
    for _, gName in ipairs(iadsGroups) do
        deactivateGroup(gName)
    end
    trigger.action.setUserFlag("21", 0)
    sendMessage("IADS Deactivated", 5)
end

local range_24_iads_menu = MENU_MISSION:New("IADS Control", range_24_menu_root)
MENU_MISSION_COMMAND:New("Activate IADS", range_24_iads_menu, activateIADS)
MENU_MISSION_COMMAND:New("Deactivate IADS", range_24_iads_menu, deactivateIADS)

----------------------------------------------------------------
-- The entire functionality is now integrated under "Range 24" 
-- within the "RANGES 19-24" menu.
----------------------------------------------------------------

----------------------------------------------------------------
-- Range 24: Scenarios (Armored Brigade via flag120)
----------------------------------------------------------------
-- Assumes that 'range_24_menu_root' is already defined earlier in this file.

local function activateArmoredBrigade()
  -- Set flag120 = 1 to trigger DO SCRIPT FILE (TRMA_R24_AR_Armored_Brigade.lua) in the .miz
  trigger.action.setUserFlag("120", 1)
  MESSAGE:New("Range 24: Armored Brigade — activation requested (Flag 120 set).", 10):ToAll()

  -- Reset the flag after 1 second so the same menu option can be used again
  timer.scheduleFunction(function()
    trigger.action.setUserFlag("120", 0)
  end, {}, timer.getTime() + 1)
end

-- Add menu
local range_24_scenarios_menu = MENU_MISSION:New("Scenarios", range_24_menu_root)
MENU_MISSION_COMMAND:New("Activate Armored Brigade (Flag 120)", range_24_scenarios_menu, activateArmoredBrigade)
MENU_MISSION_COMMAND:New("Deactivate Armored Brigade (Flag 120)", range_24_scenarios_menu, deactivateArmoredBrigade)

