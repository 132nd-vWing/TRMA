range_17_menu_root = MENU_MISSION:New("Range 17",range_root_menu13_18)

local function range17_flag101()
  range_17_menu_ARscenario_ArmoredBrigade:Remove()
  trigger.action.setUserFlag(101, true)
  MessageToAll("R17 AR scenario Armored Brigade activated")
end

range_17_menu_ARscenario_ArmoredBrigade = MENU_MISSION_COMMAND:New("Activate AR scenario Armored Brigade",range_17_menu_root,range17_flag101)







