range_15_menu_root = MENU_MISSION:New("Range 15",range_root_menu13_18)
range_15_scenario = {}

local function range_15_clear_menu()
  for k, v in pairs(range_15_scenario) do
    v:Remove()
    range_15_scenario[k] = nil
  end
end

local function range15_flag61()
  range_15_clear_menu()
  trigger.action.setUserFlag(61, true)
  MessageToAll("R15 Basic CAS scenario activated")
end
local function range15_flag35()
  range_15_clear_menu()
  trigger.action.setUserFlag(35, true)
  MessageToAll("R15 CAS scenario-1 activated")
end

range_15_scenario["range_15_menu_flag61"] = MENU_MISSION_COMMAND:New("Activate R15 Basic CAS Scenario",range_15_menu_root,range15_flag61)
range_15_scenario["range_15_menu_flag35"] = MENU_MISSION_COMMAND:New("Activate R15 CAS Scenario-1",range_15_menu_root,range15_flag35)




range_15_menu_root = MENU_MISSION:New("Range 15",range_root_menu13_18)

local function range15_flag65()
  range_15_menu_AR:Remove()
  trigger.action.setUserFlag(65, true)
  MessageToAll("Range 15 AR scenario activated")
end

range_15_menu_AR = MENU_MISSION_COMMAND:New("Activate Range 15 AR Scenario",range_15_menu_root,range15_flag65)
