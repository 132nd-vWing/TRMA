range_12_menu_root = MENU_MISSION:New("Range 12",range_root_menu7_12)

local function range12_flag12()
  range_12_menu_CAS:Remove()
  trigger.action.setUserFlag(12, true)
  MessageToAll("Range 12 Scenario CAS Defensive activated")
end





local function range12_flag33()
  range_12_menu_CAS_Scenario2:Remove()
  trigger.action.setUserFlag(33, true)
  MessageToAll("R12 Cas Scenario #2 Activated")
end

range_12_menu_CAS = MENU_MISSION_COMMAND:New("Activate Range 12 CAS defensive",range_12_menu_root,range12_flag12)
range_12_menu_CAS_Scenario2 = MENU_MISSION_COMMAND:New("Activate R12 CAS Scenario #2",range_12_menu_root,range12_flag33)
