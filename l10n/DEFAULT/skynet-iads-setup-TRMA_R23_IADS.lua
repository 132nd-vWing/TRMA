do
--create an instance of the IADS
redIADS = SkynetIADS:create('R23_IADS')


--add all units with unit name beginning with 'EWR' to the IADS:
redIADS:addEarlyWarningRadarsByPrefix('R23_EWR')


--add all groups begining with group name 'IADS' to the IADS:
redIADS:addSAMSitesByPrefix('R23_IADS')

-- Point Defence for SA-2
local sa15 = redIADS:getSAMSiteByGroupName('R23_IADS_SA15_pointdefence_1')
redIADS:getSAMSiteByGroupName('R23_IADS_SA2-1'):addPointDefence(sa15):setHARMDetectionChance(100)

local sa15 = redIADS:getSAMSiteByGroupName('R23_IADS_SA15_pointdefence_2')
redIADS:getSAMSiteByGroupName('R23_IADS_SA2-2'):addPointDefence(sa15):setHARMDetectionChance(100)



--activate the IADS
redIADS:activate()

end
