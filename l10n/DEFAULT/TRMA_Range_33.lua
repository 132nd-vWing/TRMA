----------------------------
-- RANGE 33
----------------------------

local range_33_menu_root = MENU_MISSION:New("Range 33", range_root_menu31_34)

----------------------------
-- A2A initializer
----------------------------
local range33_A2A = TRMA_A2A.Range:New("Range 33", {
  engageZone = "R33_AA_Engage",
  capZones = {
    { name = "West", zoneName = "R33_AA_Spawn_1" },
    { name = "Mid", zoneName = "R33_AA_Spawn_2" }
  }
}, range_33_menu_root)
