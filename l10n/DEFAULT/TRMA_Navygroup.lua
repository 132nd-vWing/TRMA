-- Carrier Control Menu
carrier_root_menu = MENU_MISSION:New("Carrier Control")
CV73_menu = MENU_COALITION:New(coalition.side.BLUE, "CVN-73", carrier_root_menu)

-- Recovery Window Parameters
RecoveryStartatMinute = 20 -- Minute at every hour when recovery starts
RecoveryDuration = 35  -- Duration in Minutes for Recovery Window to stay open

CVN73 = NAVYGROUP:New("CVN-73")
CVN_73_beacon_unit = UNIT:FindByName("CVN-73")

-- Error handling: Check if the carrier unit exists
if not CVN_73_beacon_unit then
    MESSAGE:New("Error: CVN-73 unit not found! Check mission setup."):ToAll()
    return
end

CVN73:SetPatrolAdInfinitum()
CVN73:SetDefaultICLS(13, "I73", CVN_73_beacon_unit)
CVN73:SetDefaultTACAN(13, "T73", CVN_73_beacon_unit, X)
CVN73:SetDefaultRadio(309.500)
CVN73:SetSpeed(12, TRUE,TRUE)


-- Define Recovery Tanker
ArcoWash = RECOVERYTANKER:New(CVN_73_beacon_unit, "CVN73_Tanker#IFF:5327FR")
ArcoWash:SetAltitude(10000)
ArcoWash:SetTACAN(64, 'SH1')
ArcoWash:SetRadio(142.5)
ArcoWash:SetUnlimitedFuel(true)
ArcoWash:SetTakeoffHot()

-- Initialize global variables for recovery times
timerecovery_start = nil
timerecovery_end = nil

-- Initialize the menu command variable
extend_recovery_menu_command = nil

-- Function to create the extend recovery menu option
function create_extend_recovery_menu()
    if extend_recovery_menu_command == nil then
        extend_recovery_menu_command = MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Extend current recovery window by 5 Minutes", CV73_menu, extend_recovery73)
    end
end

-- Function to remove the extend recovery menu option
function remove_extend_recovery_menu()
    if extend_recovery_menu_command then
        extend_recovery_menu_command:Remove()
        extend_recovery_menu_command = nil
    end
end

-- Scheduler to Check Time and Start Recovery if Necessary
SCHEDULER:New(nil, function()
    if CVN_73_beacon_unit then
        local current_minute = tonumber(os.date('%M'))
        if current_minute == RecoveryStartatMinute then
            if not CVN73:IsSteamingIntoWind() then
                env.info("Recovery opening at Minute " .. current_minute)
                start_recovery73()
            end
        end
    end
end, {}, 1, 30)

-- Scheduler to Manage Recovery State
SCHEDULER:New(nil, function()
    if CVN_73_beacon_unit then
        if CVN73:IsSteamingIntoWind() then
            create_extend_recovery_menu()
        else
            remove_extend_recovery_menu()
            ArcoWash:RTB()
        end
    end
end, {}, 1, 120)

-- Function to Start Scheduled Recovery
function start_recovery73()
    timenow = timer.getAbsTime()
    timeend = timenow + RecoveryDuration * 60
    timerecovery_start = UTILS.SecondsToClock(timenow, true)
    timerecovery_end = UTILS.SecondsToClock(timeend, true)

    if CVN73:IsSteamingIntoWind() then
        -- MESSAGE:New("CVN-73 is currently recovering, recovery window closes at time " .. timerecovery_end):ToAll()
    else
        CVN73:AddTurnIntoWind(timerecovery_start, timerecovery_end, 25, true)
        MESSAGE:New("CVN-73 is turning, Recovery Window open from " .. timerecovery_start .. " until " .. timerecovery_end):ToBlue()
        ArcoWash:Start()
        create_extend_recovery_menu()  -- Create the extend recovery menu option
        
    end
end

-- Function to Extend Recovery
function extend_recovery73()
    env.info("Old cycle was " .. timerecovery_start .. " until " .. timerecovery_end)
    timenow = timer.getAbsTime()
    timeend = timeend + 5 * 60

    timerecovery_start = UTILS.SecondsToClock(timenow, true)
    timerecovery_end = UTILS.SecondsToClock(timeend, true)

    if CVN73:IsSteamingIntoWind() then
        env.info("New cycle is " .. timerecovery_start .. " until " .. timerecovery_end)
        CVN73:ClearTasks()
        CVN73:AddTurnIntoWind(timerecovery_start, timerecovery_end, 25, true)

        MESSAGE:New("Current cycle extended by 5 minutes, new cycle end will be " .. timerecovery_end):ToBlue()
    else
        MESSAGE:New("CVN-73 is not steaming into wind, cannot extend recovery window"):ToBlue()
    end
end

function CarrierInfo()
    local heading = math.floor(CVN_73_beacon_unit:GetHeading() + 0.5)
    local windData = CVN73:GetWind(24) -- Get wind data
    local windDirection = math.floor(windData) -- Extract wind direction
    local windSpeedMps = (windData - windDirection) * 1000000 -- Calculate wind speed in m/s
    local windSpeedKnots = UTILS.MpsToKnots(windSpeedMps) -- Convert m/s to knots
    
    if CVN73:IsSteamingIntoWind() then
        local brc = math.floor(CVN73:GetHeadingIntoWind(0, 25) + 0.5)
        local carrierSpeedKnots = CVN_73_beacon_unit:GetVelocityKNOTS()
        local windSpeedOverDeckKnots = windSpeedKnots + carrierSpeedKnots -- Wind speed over deck
        
        MESSAGE:New("CVN-73 is recovering, from " .. timerecovery_start .. " until " .. timerecovery_end):ToBlue()
        MESSAGE:New("BRC is " .. brc):ToBlue()
        MESSAGE:New("FB is " .. brc - 9):ToBlue()
        MESSAGE:New("Current Heading of the Carrier is " .. heading):ToBlue()
        MESSAGE:New(string.format("Wind over deck is from %d degrees at %.1f knots", windDirection, windSpeedOverDeckKnots)):ToBlue()

        env.info("CVN-73 is recovering, from " .. timerecovery_start .. " until " .. timerecovery_end)
        env.info("BRC is " .. brc)
        env.info("FB is " .. brc - 9)
        env.info("Current Heading of the Carrier is " .. heading)
        env.info(string.format("Wind over deck is from %d degrees at %.1f knots", windDirection, windSpeedOverDeckKnots))
    else
        MESSAGE:New("CVN-73 is currently not recovering. Next Cyclic Ops Window start at Minute " .. RecoveryStartatMinute):ToBlue()
        MESSAGE:New("Current Heading of the Carrier is " .. heading):ToBlue()
        MESSAGE:New(string.format("Wind is from %d degrees at %.1f knots", windDirection, windSpeedKnots)):ToBlue()
        env.info("CVN-73 is currently not recovering. Next Cyclic Ops Window start at Minute " .. RecoveryStartatMinute)
        env.info("Current Heading of the Carrier is " .. heading)
        env.info(string.format("Wind is from %d degrees at %.1f knots", windDirection, windSpeedKnots))
    end
end

MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Carrier Info", CV73_menu, CarrierInfo)

---- Optional: Add debugging function to manually start the carrier's turn
--function setminute()
--  start_recovery73()
--end
--MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Debug Set Minute", CV73_menu, setminute)
