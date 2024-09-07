do
--create an instance of the IADS
redIADS = SkynetIADS:create('R23_Army')


--add all units with unit name beginning with 'EWR' to the IADS:
redIADS:addEarlyWarningRadarsByPrefix('R23_IADS_Army_SBORKA')


--add all groups begining with group name 'IADS' to the IADS:
redIADS:addSAMSitesByPrefix('R23_IADS_Army_SA')



--activate the IADS
redIADS:activate()

end
