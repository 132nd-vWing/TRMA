range_17_menu_root = MENU_MISSION:New("Range 17",range_root_menu13_18)

local function range17_flag101()
  range_17_menu_ARscenario_ArmoredBrigade:Remove()
  trigger.action.setUserFlag(101, true)
  MessageToAll("R17 AR scenario Armored Brigade activated")
end

local function range17_flag102()
  range_17_menu_StrikeDefenses:Remove()
  trigger.action.setUserFlag(102, true)
  MessageToAll("R17 Air Defenses at Strike Target activated")
end

local function range17_flag_494MQT()
  range_17_menu_494MQT:Remove()
  trigger.action.setUserFlag("494MQT", true)
  MessageToAll("R17 494 MQT activated")
end

range_17_menu_ARscenario_ArmoredBrigade = MENU_MISSION_COMMAND:New("Activate AR scenario Armored Brigade",range_17_menu_root,range17_flag101)
range_17_menu_StrikeDefenses = MENU_MISSION_COMMAND:New("Activate Airdefenses at Range 17 Strike Targets",range_17_menu_root,range17_flag102)
range_17_menu_494MQT = MENU_MISSION_COMMAND:New("Activate 494th MQT Scenario",range_17_menu_root,range17_flag_494MQT)








