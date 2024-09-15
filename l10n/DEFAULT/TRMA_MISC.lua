_SETTINGS:SetPlayerMenuOff()

---important: the MessageToAll function was removed from Moose, we add it back here, else all other scripts will break. 
function MessageToAll( MsgText, MsgTime, MsgName )
  -- trace.f()
  MESSAGE:New( MsgText, MsgTime, "Message" ):ToCoalition( coalition.side.RED ):ToCoalition( coalition.side.BLUE )
end





awacs_root_menu = MENU_MISSION:New("AWACS and TANKER Control")
range_root_menu = MENU_MISSION:New("RANGE Control")
--RANGE.MenuF10Root=MENU_MISSION:New("Basic Ranges",range_root_menu)
--range_root_menu1_6 = MENU_MISSION:New("RANGES 1-6",range_root_menu)
range_root_menu7_12 = MENU_MISSION:New("RANGES 7-12",range_root_menu)
range_root_menu13_18 = MENU_MISSION:New("RANGES 13-18",range_root_menu)
range_root_menu19_24 = MENU_MISSION:New("RANGES 19-24",range_root_menu)
range_root_menu31_34 = MENU_MISSION:New("RANGES 31-34",range_root_menu)
--moa_root_menu = MENU_MISSION:New("MOAs")

--awacs_menu = MENU_MISSION:New("AWACS Control", awacs_root_menu )
tanker_menu = MENU_MISSION:New("TANKER Control", awacs_root_menu )
--elint_menu = MENU_MISSION:New("ELINT Control", awacs_root_menu )
--elint_menu_elint1 = MENU_MISSION:New("ELINT RANGE 2", elint_menu )
--range_root_menu_misc = MENU_MISSION:New("Miscellaneous ")

--- FOX script (replaces Missiletrainer)
fox=FOX:New()
fox:SetExplosionDistance(20)
fox:SetDisableF10Menu(true)
fox:SetDefaultLaunchAlerts(false)
fox:Start()
---/Fox

