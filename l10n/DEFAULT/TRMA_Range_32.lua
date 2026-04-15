-- Range 31 Lua

local range_32_menu_root = MENU_MISSION:New("Range 32", range_root_menu31_34)

-- A2A initializer
local range32_A2A = TRMA_A2A.Range:New("Range 32", {
  engageZone = "R32_AA_Engage",
  patrolZones = {
    { name = "West", zoneName = "R32_AA_Spawn_1" },
    { name = "Mid", zoneName = "R32_AA_Spawn_2" }
  }
}, range_32_menu_root) -- <--- Passed directly here


