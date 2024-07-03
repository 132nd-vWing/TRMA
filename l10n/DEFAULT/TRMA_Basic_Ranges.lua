-- Strafe pits. Each pit can consist of multiple targets. Here we have two pits and each of the pits has two targets. These are names of the corresponding units defined in the ME.
Range11_Strafepit_Table={"Range11_Strafepit_1", "Range11_Strafepit_2","Range11_Strafepit_3","Range11_Strafepit_4"}

-- Table of bombing target names.
bombtargets_Range11={"Range_11_Circle_North", "Range_11_Circle_South" }

-- Create a range object.
Range11=RANGE:New("Range 11")


Range11:DebugOFF()
Range11:SetMaxStrafeAlt(3000)

Range11_fouldist=610
--default is 610 meters

-- Add strafe pits. Each pit (left and right) consists of two targets.
Range11:AddStrafePit(Range11_Strafepit_Table, 5000, 800, nil, true, 20, Range11_fouldist)



-- Add bombing targets. A good hit is if the bomb falls less then 50 m from the target.
Range11:AddBombingTargets(bombtargets_Range11, 50)
Range11:SetRangeControl(120.25)
Range11:SetInstructorRadio(120.25)
Range11:Start()


