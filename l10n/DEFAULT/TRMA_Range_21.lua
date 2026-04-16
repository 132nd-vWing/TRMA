range_21_menu_root = MENU_MISSION:New("Range 21",range_root_menu19_24)

local function range21_flag71()
  range_21_menu_R21_scenario_IADS:Remove()
  trigger.action.setUserFlag(71, true)
  MessageToAll("R21 IADS activated")
end

range_21_menu_R21_scenario_IADS = MENU_MISSION_COMMAND:New("Activate R21 IADS",range_21_menu_root,range21_flag71)

-- A2A initializer
local range21_A2A = TRMA_A2A.Range:New("Range 21", {
  engageZone = "R21_AA_Engage",
  patrolZones = {
    { name = "East", zoneName = "R21_AA_Spawn_1" },
    { name = "West", zoneName = "R21_AA_Spawn_2" }
  }
}, range_21_menu_root) 






