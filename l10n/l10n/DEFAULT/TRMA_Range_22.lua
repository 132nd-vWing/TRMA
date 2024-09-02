-- Define the root menu for Range 22
range_22_menu_root = MENU_MISSION:New("Range 22", range_root_menu19_24)

-- Function to activate the AR scenario WEST
local function range22_AR_scenario_WEST()

  -- Define the groups of units
  local heavy_rocket_arty = {
    "R22_Heavy_rocket_arty_BN_1",
    "R22_Heavy_rocket_arty_BN_2",
    "R22_Heavy_rocket_arty_BN_3",
    "R22_Heavy_rocket_arty_BN_4",
  }

  local AR_Sams = {
    "R22_AR_SAM_SA_8_1",
    "R22_AR_SAM_SA_8_2",
    "R22_AR_SAM_SA_13_1",
    "R22_AR_SAM_SA_13_2",
  }

  local arty_battery = {
    "R22_AR_Arty_battery_1",
    "R22_AR_Arty_battery_2",
  }

  local additional_spawns = {
    "R22_AR_SSM_BN", 
    "R22_AR_Manpad_1",
    "R22_AR_Manpad_2",
  }

  local AR_Mech_coy = {
    "R22_AR_Mech_coy_1",
    "R22_AR_Mech_coy_2",
    "R22_AR_Mech_coy_3",
  }

  -- Randomly select one group from the heavy_rocket_arty list
  local selected_heavy_rocket_arty = heavy_rocket_arty[math.random(#heavy_rocket_arty)]
  local group_heavy_rocket = GROUP:FindByName(selected_heavy_rocket_arty)
  
  if group_heavy_rocket then
    group_heavy_rocket:Activate()
    group_heavy_rocket:SetAIOff()
  else
    env.warning("Group " .. selected_heavy_rocket_arty .. " not found.")
  end

  -- Randomly select one group from the AR_Sams list
  local selected_AR_Sams = AR_Sams[math.random(#AR_Sams)]
  local group_AR_Sams = GROUP:FindByName(selected_AR_Sams)
  
  if group_AR_Sams then
    group_AR_Sams:Activate()
    group_AR_Sams:SetAIOn()
  else
    env.warning("Group " .. selected_AR_Sams .. " not found.")
  end

  -- 67% chance to spawn one of the arty_battery groups
  local roll_arty_battery = math.random()
  if roll_arty_battery > 0.33 then
    local selected_arty_battery = arty_battery[math.random(#arty_battery)]
    local group_arty_battery = GROUP:FindByName(selected_arty_battery)
    
    if group_arty_battery then
      group_arty_battery:Activate()
      group_arty_battery:SetAIOff()
      env.info("R22 AR Scenario West: Artillery battery activated - " .. selected_arty_battery)
    else
      env.warning("Group " .. selected_arty_battery .. " not found.")
    end
  else
    env.info("R22 AR Scenario West: No artillery batteries activated.")
  end

  -- 20% chance to spawn all of the additional_spawns groups
  local roll_additional_spawns = math.random()
  if roll_additional_spawns <= 0.20 then
    env.info("R22 AR Scenario West: All additional spawns activated.")
    for _, spawn in ipairs(additional_spawns) do
      local group_additional = GROUP:FindByName(spawn)
      if group_additional then
        group_additional:Activate()
        if spawn == "R22_AR_SSM_BN" then
          group_additional:SetAIOff()  -- Set AI OFF if it's the specific SSM group
        end
      else
        env.warning("Group " .. spawn .. " not found.")
      end
    end  
  end

  -- Randomly select one group from AR_Mech_coy and activate it
  local selected_AR_Mech_coy = AR_Mech_coy[math.random(#AR_Mech_coy)]
  local group_AR_Mech_coy = GROUP:FindByName(selected_AR_Mech_coy)
  
  if group_AR_Mech_coy then
    group_AR_Mech_coy:Activate()
    group_AR_Mech_coy:SetAIOff()
  else
    env.warning("Group " .. selected_AR_Mech_coy .. " not found.")
  end

  -- Notify all players about the scenario activation
  env.info("R22 AR Scenario West activated. Spawned " .. selected_heavy_rocket_arty .. ", " .. selected_AR_Sams .. ", and " .. selected_AR_Mech_coy)
  MessageToAll("R22 AR Scenario West activated")
end

-- Create a mission command to trigger the scenario
MENU_MISSION_COMMAND:New("Activate AR scenario WEST", range_22_menu_root, range22_AR_scenario_WEST)
