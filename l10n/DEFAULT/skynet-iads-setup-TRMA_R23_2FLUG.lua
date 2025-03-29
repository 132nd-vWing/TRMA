do
--create an instance of the IADS
redIADS = SkynetIADS:create('R23_IADS_2FLUG')


--add all units with unit name beginning with 'EWR' to the IADS:
redIADS:addEarlyWarningRadarsByPrefix('R23_EWR')


--add all groups begining with group name 'IADS' to the IADS:
redIADS:addSAMSitesByPrefix('R23_IADS')


--activate the IADS
redIADS:activate()

end
