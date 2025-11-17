range_14_menu_root = MENU_MISSION:New("Range 14",range_root_menu13_18)
range_14_scenario = {}

local function range_14_clear_menu()
    for k, v in pairs(range_14_scenario) do
        v:Remove()
        range_14_scenario[k] = nil
    end
end

local function range14_flag31()
    range_14_clear_menu()
    trigger.action.setUserFlag(31, true)
    MessageToAll("R14 Rognan scenario activated")
end

local function range14_flag34()
    range_14_clear_menu()
    trigger.action.setUserFlag(34, true)
    MessageToAll("R14 Cas Scenario-1 activated")
end

range_14_scenario["range_14_menu_flag31"] = MENU_MISSION_COMMAND:New("Activate R14 Rognan Scenario",range_14_menu_root,range14_flag31)
range_14_scenario["range_14_menu_flag34"] = MENU_MISSION_COMMAND:New("Activate R14 CAS Scenario-1",range_14_menu_root,range14_flag34)
