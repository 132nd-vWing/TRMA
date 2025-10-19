range_13_menu_root = MENU_MISSION:New("Range 13",range_root_menu13_18)

local function range13_flag11()
  range_13_menu_ARscenario_Storjord:Remove()
  trigger.action.setUserFlag(11, true)
  MessageToAll("R13 AR scenario Storjord activated")
end



local function range13_flag32()
  range_13_menu_CAS_Scenario1:Remove()
  trigger.action.setUserFlag(32, true)
  MessageToAll("R13 Cas Scenario #1 Activated")
end

range_13_menu_CAS_Scenario1 = MENU_MISSION_COMMAND:New("Activate R13 CAS Scenario #1",range_13_menu_root,range13_flag32)
range_13_menu_ARscenario_Storjord = MENU_MISSION_COMMAND:New("Activate AR scenario Storjord",range_13_menu_root,range13_flag11)