do
--create an instance of the IADS
redIADS = SkynetIADS:create('R21_IADS')


--add all units with unit name beginning with 'EWR' to the IADS:
redIADS:addEarlyWarningRadarsByPrefix('R21_EWR')


--add all groups begining with group name 'IADS' to the IADS:
redIADS:addSAMSitesByPrefix('R21_IADS')



--local sa15 = redIADS:getSAMSiteByGroupName('R23_IADS_SA15_pointdefence_2')
--redIADS:getSAMSiteByGroupName('R23_IADS_SA2-2'):addPointDefence(sa15):setHARMDetectionChance(100)



--activate the IADS
redIADS:activate()

end
