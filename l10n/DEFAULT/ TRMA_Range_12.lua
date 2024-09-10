range_12_menu_root = MENU_MISSION:New("Range 12",range_root_menu7_12)

local function range12_flag12()
  range_12_menu_CAS:Remove()
  trigger.action.setUserFlag(12, true)
  MessageToAll("Range 12 Scenario CAS Defensive activated")
end

range_12_menu_CAS = MENU_MISSION_COMMAND:New("Activate Range 12 CAS defensive",range_12_menu_root,range12_flag12)
