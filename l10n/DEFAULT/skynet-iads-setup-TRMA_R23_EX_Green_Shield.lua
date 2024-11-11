do
--create an instance of the IADS
redIADS = SkynetIADS:create('Exercise Green Shield')


--add all units with unit name beginning with 'EWR' to the IADS:
redIADS:addEarlyWarningRadarsByPrefix('EX_GS_IADS_SBORKA')


--add all groups begining with group name 'IADS' to the IADS:
redIADS:addSAMSitesByPrefix('EX_GS_IADS_Army_SA')



--activate the IADS
redIADS:activate()

end
