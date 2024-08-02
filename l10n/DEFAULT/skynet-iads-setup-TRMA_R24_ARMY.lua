do
--create an instance of the IADS
redIADS = SkynetIADS:create('R24_Army')


--add all units with unit name beginning with 'EWR' to the IADS:
redIADS:addEarlyWarningRadarsByPrefix('R24_IADS_Army_SBORKA-1')


--add all groups begining with group name 'IADS' to the IADS:
redIADS:addSAMSitesByPrefix('R24_IADS_Army_SA')



--activate the IADS
redIADS:activate()

end
