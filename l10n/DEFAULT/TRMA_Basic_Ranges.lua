local root_range=MENU_MISSION:New("Basic Ranges", range_root_menu)


-- Create a range object.
Range11=RANGE:New("Range 11")
Range11:SetMenuRoot(root_range)

-- Strafe pits. Each pit can consist of multiple targets. Here we have two pits and each of the pits has two targets. These are names of the corresponding units defined in the ME.
Range11_Strafepit_Table1={"Range11_Strafepit_1", "Range11_Strafepit_1_2"}
Range11_Strafepit_Table2={"Range11_Strafepit_2", "Range11_Strafepit_2_2"}


-- Table of bombing target names.
bombtargets_Range11={"Range_11_Circle_North", "Range_11_Circle_South" }


Range11:DebugOFF()
Range11:SetMaxStrafeAlt(3000)

Range11_fouldist=140
--default is 610 meters

-- Add strafe pits. Each pit (left and right) consists of two targets.
Range11:AddStrafePit(Range11_Strafepit_Table1, 5000, 800, nil, true, 20, Range11_fouldist)
Range11:AddStrafePit(Range11_Strafepit_Table2, 5000, 800, nil, true, 20, Range11_fouldist)

-- Add bombing targets. A good hit is if the bomb falls less then 50 m from the target.
Range11:AddBombingTargets(bombtargets_Range11, 50)
Range11:SetRangeControl(120.25)
Range11:SetInstructorRadio(120.25)
Range11:Start()


-- Create a range object.
Range17=RANGE:New("Range 17")
Range17:SetMenuRoot(root_range)

-- Strafe pits. Each pit can consist of multiple targets. Here we have two pits and each of the pits has two targets. These are names of the corresponding units defined in the ME.
Range17_Strafepit_Table1={"Range_17_Strafepit_WEST_1", "Range_17_Strafepit_WEST_2"}
Range17_Strafepit_Table2={"Range_17_Strafepit_EAST_1", "Range_17_Strafepit_EAST_2"}


-- Table of bombing target names.
bombtargets_Range17={"Range_17_Circle_NORTH","Range_17_Circle_CENTRE", "Range_17_Circle_SOUTH"}


Range17:DebugOFF()
Range17:SetMaxStrafeAlt(3000)

Range17_fouldist=140
--default is 610 meters

-- Add strafe pits. Each pit (left and right) consists of two targets.
Range17:AddStrafePit(Range17_Strafepit_Table1, 5000, 800, nil, true, 20, Range17_fouldist)
Range17:AddStrafePit(Range17_Strafepit_Table2, 5000, 800, nil, true, 20, Range17_fouldist)

-- Add bombing targets. A good hit is if the bomb falls less then 50 m from the target.
Range17:AddBombingTargets(bombtargets_Range17, 50)
Range17:SetRangeControl(120.25)
Range17:SetInstructorRadio(120.25)
Range17:Start()
