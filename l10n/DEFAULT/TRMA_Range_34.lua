range_34_menu_root = MENU_MISSION:New("Range 34",range_root_menu31_34)

-- Grisha
local function range34_flag102()
  range_34_menu_Grisha:Remove()
  trigger.action.setUserFlag(102, true)
  MessageToAll("R34 Ship Grisha activated")
end

range_34_menu_Grisha = MENU_MISSION_COMMAND:New("Activate Ship Grisha",range_34_menu_root,range34_flag102)

-- Type 052B
local function range34_flag103()
  range_34_menu_Type052B:Remove()
  trigger.action.setUserFlag(103, true)
  MessageToAll("R34 Ship Type 052B activated")
end

range_34_menu_Type052B = MENU_MISSION_COMMAND:New("Activate Ship Type 052B",range_34_menu_root,range34_flag103)

-- Type 052C
local function range34_flag104()
  range_34_menu_Type052C:Remove()
  trigger.action.setUserFlag(104, true)
  MessageToAll("R34 Ship Type 052C activated")
end

range_34_menu_Type052C = MENU_MISSION_COMMAND:New("Activate Ship Type 052C",range_34_menu_root,range34_flag104)

-- Type CG Moskva
local function range34_flag105()
  range_34_menu_CGMoskva:Remove()
  trigger.action.setUserFlag(105, true)
  MessageToAll("R34 Ship Type Cruiser Moskva activated")
end

range_34_menu_CGMoskva = MENU_MISSION_COMMAND:New("Activate Ship Cruiser Moskva",range_34_menu_root,range34_flag105)

-- Type SAG
local function range34_flag106()
  range_34_menu_SAG:Remove()
  trigger.action.setUserFlag(106, true)
  MessageToAll("R34 SAG activated")
end

range_34_menu_SAG = MENU_MISSION_COMMAND:New("Activate SAG",range_34_menu_root,range34_flag106)




