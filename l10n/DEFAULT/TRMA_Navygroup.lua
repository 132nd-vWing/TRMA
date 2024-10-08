-- Carrier Control Menu
local carrier_root_menu = MENU_MISSION:New("Carrier Control")
local case3stack = {}
-- Create Admin Menu
local CV73_admin_menu = MENU_COALITION:New(coalition.side.BLUE, "CVN-73 Admin", carrier_root_menu)

-- Recovery Window Parameters
local RecoveryStartatMinute = 20 -- Minute at every hour when recovery starts
local RecoveryDuration = 35  -- Duration in Minutes for Recovery Window to stay open
local clients = SET_CLIENT:New():FilterActive(true):FilterCoalitions("blue"):FilterStart()
local timeend = nil -- Initialize timeend

local offset = 0   --this is the offset for the CASEIII Marshall radial

local CVN_73_beacon_unit = UNIT:FindByName("CVN-73")

-- Define MarshallZone
local MarshallZone = ZONE_UNIT:New("MarshallZone", CVN_73_beacon_unit, UTILS.NMToMeters(60))

-- Function to broadcast messages to players in the Marshall Zone
local function BroadcastMessageToZone(message)
  clients:ForEachClientInZone(MarshallZone, function(client)
    MESSAGE:New(message, 15):ToClient(client)
  end)
end
local function scheduleClearQueueAfterTurn() --this function will  be defined at the end of the script
end

local CVN73 = NAVYGROUP:New("CVN-73")
CVN73:SetPatrolAdInfinitum()
CVN73:Activate()



if GROUP:FindByName("CVN-73") then
  trigger.action.setUserFlag(501, true) -- switch lights off on the Carrier at Mission Start

  if CVN_73_beacon_unit then
    local CVN_73_Beacon = CVN_73_beacon_unit:GetBeacon()
    CVN_73_beacon_unit:CommandActivateLink4(331, nil, "A73", 5)
    CVN_73_beacon_unit:CommandActivateACLS(nil, "A73", 5)
    CVN_73_beacon_unit:CommandSetFrequency(309.5)
    CVN_73_Beacon:ActivateICLS(13, "I73")
    CVN_73_Beacon:ActivateTACAN(13, "X", "T73", true)
    CVN_73_beacon_unit:CommandSetFrequency(309.5) -- Set Carrier Frequency
    CVN_73_beacon_unit:SetSpeed(UTILS.KnotsToMps(16), true)
    env.info("Carrier Unit is " .. CVN_73_beacon_unit:GetName())

    -- Define Recovery Tanker
    local ArcoWash = RECOVERYTANKER:New(CVN_73_beacon_unit, "CVN73_Tanker#IFF:5327FR")
    ArcoWash:SetAltitude(10000)
    ArcoWash:SetTACAN(64, 'SH1')
    ArcoWash:SetRadio(142.5)
    ArcoWash:SetUnlimitedFuel(true)
    ArcoWash:SetTakeoffHot()

    -- Initialize global variables for recovery times
    local timerecovery_start = nil
    local timerecovery_end = nil

    -- Initialize the menu command variable
    local extend_recovery_menu_command = nil

    -- Function to Extend Recovery
    local function extend_recovery73()
      env.info("Old cycle was " .. timerecovery_start .. " until " .. timerecovery_end)
      local timenow = timer.getAbsTime()

      if timeend == nil then timeend = timenow + RecoveryDuration * 60 end  -- Ensure timeend is initialized

      timeend = timeend + 5 * 60 -- Extend time by 5 minutes

      timerecovery_start = UTILS.SecondsToClock(timenow, true)
      timerecovery_end = UTILS.SecondsToClock(timeend, true)

      if CVN73:IsSteamingIntoWind() then
        env.info("New cycle is " .. timerecovery_start .. " until " .. timerecovery_end)
        CVN73:ClearTasks()
        CVN73:AddTurnIntoWind(timerecovery_start, timerecovery_end, 25, true)

        BroadcastMessageToZone("Current cycle extended by 5 minutes, new cycle end will be " .. timerecovery_end)
      else
        BroadcastMessageToZone("CVN-73 is not steaming into wind, cannot extend recovery window")
      end
    end




    -- Function to create the extend recovery menu option
    local function create_extend_recovery_menu()
      if extend_recovery_menu_command == nil then
        extend_recovery_menu_command =  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Extend current recovery window by 5 Minutes", CV73_admin_menu, extend_recovery73)

      end
    end

    -- Function to remove the extend recovery menu option
    local function remove_extend_recovery_menu()
      if extend_recovery_menu_command then
        extend_recovery_menu_command:Remove()
        extend_recovery_menu_command = nil
      end
    end

    -- Function to Start Scheduled Recovery
    local function start_recovery73()
      local timenow = timer.getAbsTime()
      timeend = timenow + RecoveryDuration * 60 -- Initialize timeend

      timerecovery_start = UTILS.SecondsToClock(timenow, true)
      timerecovery_end = UTILS.SecondsToClock(timeend, true)

      if CVN73:IsSteamingIntoWind() then
      else
        CVN73:AddTurnIntoWind(timerecovery_start, timerecovery_end, 25, true)
        BroadcastMessageToZone("CVN-73 is turning, Recovery Window open from " .. timerecovery_start .. " until " .. timerecovery_end)
        ArcoWash:Start()
        create_extend_recovery_menu()  -- Create the extend recovery menu option
      end
    end
    local function setminute()
      start_recovery73()
      trigger.action.setUserFlag(502, true)
    end


    -- Nest Debug and Extend Recovery under CVN-73 Admin
    MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Debug: Start Cycle Manually", CV73_admin_menu, setminute)

    -- Scheduler to Check Time and Start Recovery if Necessary
    SCHEDULER:New(nil, function()
      if CVN_73_beacon_unit then
        local current_minute = tonumber(os.date('%M'))
        if current_minute == RecoveryStartatMinute then
          if not CVN73:IsSteamingIntoWind() then
            env.info("Recovery opening at Minute " .. current_minute)
            start_recovery73()
            trigger.action.setUserFlag(502, true) -- lights on
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
          trigger.action.setUserFlag(501, true)
          scheduleClearQueueAfterTurn()
          function ArcoWash:OnEventEngineShutdown(EventData)
            env.info("Arcowash despawning")
            ArcoWash:Stop()
          end
        end
      end
    end, {}, 120, 240)

    local function CarrierInfo()
      local heading = math.floor(CVN_73_beacon_unit:GetHeading() + 0.5)
      local windData = CVN73:GetWind(24)
      local windDirection = math.floor(windData)
      local windSpeedMps = (windData - windDirection) * 1000000
      local windSpeedKnots = UTILS.MpsToKnots(windSpeedMps)

      if CVN73:IsSteamingIntoWind() then
        local brc = math.floor(CVN73:GetHeadingIntoWind(0, 25) + 0.5)
        local carrierSpeedKnots = CVN_73_beacon_unit:GetVelocityKNOTS()
        local windSpeedOverDeckKnots = windSpeedKnots + carrierSpeedKnots
        local fb = (brc - 9) % 360

        -- If fb becomes negative, add 360 to bring it back into the 0-360 range
        if fb < 0 then
          fb = fb + 360
        end
        BroadcastMessageToZone("CVN-73 is recovering, from " .. timerecovery_start .. " until " .. timerecovery_end)
        BroadcastMessageToZone("BRC is " .. brc)
        BroadcastMessageToZone("FB is " .. fb)
        BroadcastMessageToZone("Current Heading of the Carrier is " .. heading)
        BroadcastMessageToZone(string.format("Wind over deck is from %d degrees at %.1f knots", windDirection, windSpeedOverDeckKnots))
      else
        BroadcastMessageToZone("CVN-73 is currently not recovering. Next Cyclic Ops Window start at Minute " .. RecoveryStartatMinute)
        BroadcastMessageToZone("Current Heading of the Carrier is " .. heading)
        BroadcastMessageToZone(string.format("Wind is from %d degrees at %.1f knots", windDirection, windSpeedKnots))
      end
    end
    -- Top Level: CVN-73 Carrier Information
    MENU_COALITION_COMMAND:New(coalition.side.BLUE, "CVN-73 Carrier Information", carrier_root_menu, CarrierInfo)
  end
end

-- Create CASE II/III Marshall Menu
local caseIII_menu = MENU_COALITION:New(coalition.side.BLUE, "CVN-73 CASE II/III Marshall", carrier_root_menu)

-- Create menus for Panthers and Spectres bort number ranges
local panthers_menu = MENU_COALITION:New(coalition.side.BLUE, "Panthers", caseIII_menu)
local spectres_menu = MENU_COALITION:New(coalition.side.BLUE, "Spectres", caseIII_menu)

-- Initialize case3stack table to store bort numbers as a queue

local add_commands = {}


-- Forward declaration of removeBortFromMarshall
local removeBortFromMarshall

-- Function to add bort number and replace menu with "remove" option
local function addBortToMarshall(flight_num, range_menu)
  -- Add the flight to the marshall queue
  table.insert(case3stack, flight_num)
  BroadcastMessageToZone("Flight " .. flight_num .. " added to Marshall Queue at position " .. #case3stack)

  -- Remove the "add" menu entry for this bort number (from add_commands table)
  if add_commands[flight_num] then
    add_commands[flight_num]:Remove()  -- Explicitly remove the "add" command
    add_commands[flight_num] = nil  -- Clear the reference
  end

  -- Create a "remove" option in the same place within the specific range submenu
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, flight_num .. " remove from CASE III Marshall Queue", range_menu, function()
    removeBortFromMarshall(flight_num, range_menu)
  end)
end

-- Function to create a menu for each range of bort numbers (used for both Panthers and Spectres)
local function createBortMenu(start_num, end_num, parent_menu)
  local range_menu = MENU_COALITION:New(coalition.side.BLUE, tostring(start_num) .. "-" .. tostring(end_num), parent_menu)

  for flight_num = start_num, end_num do
    -- Create the "add to queue" menu option for each bort number directly under the range menu
    local add_command = MENU_COALITION_COMMAND:New(coalition.side.BLUE, flight_num .. " add to CASE III Marshall Queue", range_menu, function()
      addBortToMarshall(flight_num, range_menu)  -- Pass the reference to the add_command
    end)
    -- Store the add command in the table for later removal
    add_commands[flight_num] = add_command
  end
end

-- Function to remove bort number and recreate the add menu
removeBortFromMarshall = function(flight_num, range_menu)
  local index_to_remove = nil
  for i, bort in ipairs(case3stack) do
    if bort == flight_num then
      index_to_remove = i
      break
    end
  end

  if index_to_remove then
    table.remove(case3stack, index_to_remove)
    BroadcastMessageToZone("Flight " .. flight_num .. " removed from Marshall")

    -- Renumber the remaining entries in the stack
    for i, bort in ipairs(case3stack) do
      BroadcastMessageToZone("Flight " .. bort .. " is now in position " .. i)
    end
  end

  -- Remove the "remove" menu entry and recreate the "add" menu option
  MENU_COALITION_COMMAND:New(coalition.side.BLUE, flight_num .. " add to CASE III Marshall Queue", range_menu, function()
    addBortToMarshall(flight_num, range_menu)
  end)
end

local function displayQueue()
  if #case3stack == 0 then
    BroadcastMessageToZone("No flights currently in Marshall queue")
    return
  end

  -- Define the base values
  local adjusted_stackdistance = 21
  local adjusted_stackangels = 6
  local base_pushtime = RecoveryStartatMinute + 10

  -- Calculate reciprocalFB based on wind direction
  CVN73:GetCoordinate()
  local windData = CVN73:GetWind(24)
  local carierpos = CVN73:GetCoordinate()
  local pressure = carierpos:GetPressureText(0)
  local windDirection = math.floor(windData)
  local reciprocalWindDirection = (windDirection + 180) % 360

  -- Calculate reciprocalFB as reciprocalWindDirection - 9 degrees + offset
  local reciprocalFB = reciprocalWindDirection - 9 + offset
  if reciprocalFB < 0 then
    reciprocalFB = reciprocalFB + 360
  end

  local FB = windDirection - 9
  if FB < 0 then
    FB = reciprocalFB + 360
  end

  -- Initialize the queue message with the header
  local queue_message = "Current Marshall Queue:\n"
  queue_message = queue_message .. "Expect Final Bearing " .. FB .. ", QNH " .. pressure .. ".\n"

  -- Iterate over the stack and display the information for each bort number
  for i, bort in ipairs(case3stack) do
    -- Determine the aircraft type based on the bort number
    local aircraft_type = ""
    if bort >= 300 and bort <= 399 then
      aircraft_type = "Hornet"
    elseif bort >= 200 and bort <= 299 then
      aircraft_type = "Tomcat"
    else
      aircraft_type = "Unknown"
    end

    -- Calculate adjusted values for each position in the stack
    local stack_distance = adjusted_stackdistance + i - 1  -- Increment distance for each position
    local stack_angels = adjusted_stackangels + i - 1      -- Increment angels for each position
    local pushtime = base_pushtime + i - 1                  -- Increment pushtime for each position

    -- Create the message for each bort number
    queue_message = queue_message .. aircraft_type .. " " .. bort .. ", Marshall from Mother at "
      .. reciprocalFB .. "/" .. stack_distance
      .. ", at Angels " .. stack_angels
      .. ". Pushtime Minute " .. pushtime .. "\n"
  end

  -- Broadcast the constructed message
  BroadcastMessageToZone(queue_message)
end


-- Create a menu to display the current queue directly under CVN-73 CASE II/III Marshall
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Display the Marshall Stack", caseIII_menu, displayQueue)

-- Create menus for Panthers (300-326) and Spectres (200-226)
createBortMenu(300, 306, panthers_menu)
createBortMenu(307, 313, panthers_menu)
createBortMenu(314, 319, panthers_menu)
createBortMenu(320, 326, panthers_menu)

createBortMenu(200, 206, spectres_menu)
createBortMenu(207, 213, spectres_menu)
createBortMenu(214, 219, spectres_menu)
createBortMenu(220, 226, spectres_menu)

-- Function to clear the entire marshall queue and reset everything
local function clearMarshallQueue()
  -- Create a copy of the case3stack to avoid modifying the table while iterating
  local stack_copy = {}
  for i = 1, #case3stack do
    stack_copy[i] = case3stack[i]
  end

  for _, flight_num in ipairs(stack_copy) do
    -- Find the correct range menu for the flight number and remove it
    if flight_num >= 300 and flight_num <= 326 then
      removeBortFromMarshall(flight_num, panthers_menu)
    elseif flight_num >= 200 and flight_num <= 226 then
      removeBortFromMarshall(flight_num, spectres_menu)
    end
  end

  -- Clear the stack after removing all entries
  case3stack = {}

  -- Optionally, you could broadcast a message to notify users that the queue has been cleared
  BroadcastMessageToZone("The Marshall Queue has been cleared.")
end



local function scheduleClearQueueAfterTurn()
  -- Check if there are entries in the queue
  if #case3stack > 0 then
    -- Schedule the clearMarshallQueue function to run in 5 minutes (300 seconds)
    SCHEDULER:New(nil, function()
      -- Double-check if there are still entries in the queue after 5 minutes
      if #case3stack > 0 then
        clearMarshallQueue()
      else
        env.info("Marshall queue is already empty, no need to clear.")
      end
    end, {}, 300) -- 300 seconds = 5 minutes
  else
    env.info("No entries in the Marshall queue, nothing to clear.")
  end
end


-- Add a menu option to clear the entire marshall queue
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Clear Marshall Queue", CV73_admin_menu, clearMarshallQueue)


