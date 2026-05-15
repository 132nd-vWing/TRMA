-----------------------------
-- Range 31 Lua
-----------------------------

local range_31_menu_root = MENU_MISSION:New("Range 31", range_root_menu31_34)

-----------------------------
-- A2A initializer
-----------------------------
local range31_A2A = TRMA_A2A.Range:New("Range 31", {
  engageZone = "R31_AA_Engage",
  capZones = {
    { name = "West", zoneName = "R31_AA_Spawn_1" },
    { name = "Mid", zoneName = "R31_AA_Spawn_2" }
  }
}, range_31_menu_root) 

----------------------------
-- Naval Operations
----------------------------
local range31_SAG = TRMA_SAG.Range:New("Range 31", {
  spawnZone = "R31_Naval_Spawn" -- Define this zone in the ME
}, range_31_menu_root)


