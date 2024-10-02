-- Carrier Control Menu
local carrier_root_menu = MENU_MISSION:New("Carrier Control")
local CV73_menu = MENU_COALITION:New(coalition.side.BLUE, "CVN-73", carrier_root_menu)
trigger.action.setUserFlag(501, true) -- switch lights off on the Carrier

local timerecovery_start = nil
local timerecovery_end = nil
local global_timeend = nil
local CVN_73_beacon_unit = nil

-- Recovery Window Parameters
local RecoveryStartatMinute = 20 -- Minute at every hour when recovery starts
local RecoveryDuration = 35  -- Duration in Minutes for Recovery Window to stay open

-- Set Frequencies via Script
local CVN_73_Group = GROUP:FindByName("CVN-73")
if CVN_73_Group then
  CVN_73_beacon_unit = CVN_73_Group:GetUnit(1)
  if CVN_73_beacon_unit then
    local CVN_73_Beacon = CVN_73_beacon_unit:GetBeacon()
    -- Proceed with the beacon commands
    CVN_73_beacon_unit:CommandActivateLink4(331, nil, "A73", 5)
    CVN_73_beacon_unit:CommandActivateACLS(nil, "A73", 5)
    CVN_73_Beacon:ActivateICLS(13, "I73")
    CVN_73_Beacon:ActivateTACAN(13, "X", "T73", true)
    CVN_73_beacon_unit:SetSpeed(UTILS.KnotsToKmph(16), true)
    env.info("Carrier Group is " .. CVN_73_Group:GetName())
    env.info("Carrier Unit is " .. CVN_73_beacon_unit:GetName())
  else
    MESSAGE:New("Error: CVN-73 unit not found! Check mission setup."):ToAll()
    return
  end
else
  MESSAGE:New("Error: CVN-73 group not found! Check mission setup."):ToAll()
  return
end

local CVN73 = NAVYGROUP:New("CVN-73")
CVN73:Activate()
CVN73:SetPatrolAdInfinitum()
CVN73:SetSpeed(16)

-- Define Recovery Tanker
local ArcoWash = RECOVERYTANKER:New(CVN_73_beacon_unit, "CVN73_Tanker#IFF:5327FR")
ArcoWash:SetAltitude(10000)
ArcoWash:SetTACAN(64, 'SH1')
ArcoWash:SetRadio(142.5)
ArcoWash:SetUnlimitedFuel(true)
ArcoWash:SetTakeoffHot()

-- Global Variables for Recovery Times
local timerecovery_start = nil
local global_timeend = nil -- Global timeend to preserve recovery end time

-- Menu command variable
local extend_recovery_menu_command = nil

-- Function to Extend Recovery
local function extend_recovery73()
  env.info("Old cycle was " .. timerecovery_start .. " until " .. timerecovery_end)
  local timenow = timer.getAbsTime()
  global_timeend = global_timeend + 5 * 60 -- Use global_timeend to extend recovery window

  timerecovery_start = UTILS.SecondsToClock(timenow, true)
  timerecovery_end = UTILS.SecondsToClock(global_timeend, true)

  if CVN73:IsSteamingIntoWind() then
    env.info("New cycle is " .. timerecovery_start .. " until " .. timerecovery_end)
    CVN73:ClearTasks()
    CVN73:AddTurnIntoWind(timerecovery_start, timerecovery_end, 25, true)
    MESSAGE:New("Current cycle extended by 5 minutes, new cycle end will be " .. timerecovery_end):ToBlue()
  else
    MESSAGE:New("CVN-73 is not steaming into wind, cannot extend recovery window"):ToBlue()
  end
end

local function create_extend_recovery_menu()
  if extend_recovery_menu_command == nil then
    extend_recovery_menu_command = MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Extend current recovery window by 5 Minutes", CV73_menu, extend_recovery73)
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
  global_timeend = timenow + RecoveryDuration * 60 -- Update global_timeend
  timerecovery_start = UTILS.SecondsToClock(timenow, true)
  timerecovery_end = UTILS.SecondsToClock(global_timeend, true)

  if CVN73:IsSteamingIntoWind() then
  else
    CVN73:AddTurnIntoWind(timerecovery_start, timerecovery_end, 25, true)
    MESSAGE:New("CVN-73 is turning, Recovery Window open from " .. timerecovery_start .. " until " .. timerecovery_end):ToBlue()
    ArcoWash:Start()
    create_extend_recovery_menu()  -- Create the extend recovery menu option
  end
end

-- Marshall Stack System
-- Create MarshallZone around the carrier
local MarshallZone = ZONE_UNIT:New("MarshallZone", CVN_73_beacon_unit, UTILS.NMToMeters(60))

-- Create a set of active blue coalition clients (initialize this early to avoid nil errors)
local clients = SET_CLIENT:New():FilterActive(true):FilterCoalitions("blue"):FilterStart()

-- Forward declare PlayerActionFunction to prevent circular dependencies
local PlayerActionFunction

-- Variables for queue message formatting
local stackdistance = 21
local stackangels = 6
local pushtime = RecoveryStartatMinute + 10

-- Table to store player names in the case 3 stack
local case3_stack = {}
-- New table to store player names in the queue
local case3_queue = {}
-- Table to track if "Leave Queue" menu and "Join Queue" menu were created for each player
local leaveQueueMenus = {}
local joinQueueMenus = {}
local displayQueueMenus = {}

-- Function to broadcast a message to players in the Marshall Zone only
local function BroadcastMessageToZone(message)
  clients:ForEachClientInZone(MarshallZone, function(client)
    MESSAGE:New(message, 10):ToClient(client)
  end)
end

-- Function to display the current queue positions and names
local function DisplayQueueFunction()
  if #case3_queue == 0 then
    BroadcastMessageToZone("The CASE II/III Marshall Stack is currently empty.")
  else
    local queue_message = "CASE II/III Marshall Stack:\n"
    local windData = CVN73:GetWind(24) -- Refresh wind data
    local windDirection = math.floor(windData) -- Current wind direction
    local reciprocalWindDirection = windDirection + 180

    -- Ensure the result stays within 0-360 degrees
    if reciprocalWindDirection > 360 then
      reciprocalWindDirection = reciprocalWindDirection - 360
    end

    local base_stackdistance = stackdistance
    local base_stackangels = stackangels
    local base_pushtime = pushtime

    for i, entry in ipairs(case3_queue) do
      local playername = entry:match("position %d+ (.+)")
      local pushtime = base_pushtime + i
      local adjusted_stackdistance = base_stackdistance + i - 1
      local adjusted_stackangels = base_stackangels + i - 1
      queue_message = queue_message .. playername .. ", Marshall from Mother at " .. windDirection .. "/" .. adjusted_stackdistance .. " , at Angels " .. adjusted_stackangels .. ". Pushtime Minute " .. pushtime .. "\n"
    end
    BroadcastMessageToZone(queue_message)
  end
end

-- Function to update queue positions after a player is removed
local function UpdateQueuePositions()
  for i, playerEntry in ipairs(case3_queue) do
    local playername = playerEntry:match("position %d+ (.+)")
    case3_queue[i] = "position " .. i .. " " .. playername
  end
end

-- Function to allow players to remove themselves from the queue
local function PlayerRemoveFunction(playername)
  for i, entry in ipairs(case3_queue) do
    if entry:find(playername) then
      table.remove(case3_queue, i)
      env.info(playername .. " removed themselves from the CASE II/III Marshall Stack.")
      UpdateQueuePositions()
      BroadcastMessageToZone(playername .. " was removed from the CASE II/III Marshall Stack, Positions updated.")
      -- Automatically broadcast the updated stack to everyone in the zone
      DisplayQueueFunction()

      if leaveQueueMenus[playername] then
        leaveQueueMenus[playername]:Remove()
        leaveQueueMenus[playername] = nil
      end
      if not joinQueueMenus[playername] then
        joinQueueMenus[playername] = MENU_COALITION_COMMAND:New(coalition.side.BLUE, playername .. " - Join the CASE II/III Marshall Stack", CV73_menu, PlayerActionFunction, playername)
      end
      if displayQueueMenus[playername] then
        displayQueueMenus[playername]:Remove()
        displayQueueMenus[playername] = nil
      end
      break
    end
  end
end

-- Function to handle player action and add them to the case3_queue
PlayerActionFunction = function(playername)
  for _, entry in ipairs(case3_queue) do
    if entry:find(playername) then
      MESSAGE:New("You are already in the queue.", 10):ToCoalition(coalition.side.BLUE)
      return
    end
  end
  local queue_position = #case3_queue + 1
  local queue_entry = "position " .. queue_position .. " " .. playername
  table.insert(case3_queue, queue_entry)
  env.info("Player added to case 3 queue: " .. queue_entry)

  -- Automatically broadcast the updated stack to everyone in the zone
  BroadcastMessageToZone(playername .. " has joined the CASE II/III Marshall Stack.")
  DisplayQueueFunction() -- Auto display the updated stack

  -- Create the menu for displaying the Marshall Stack for this player
  if not displayQueueMenus[playername] then
    displayQueueMenus[playername] = MENU_COALITION_COMMAND:New(coalition.side.BLUE, playername .. " - Display the CASE II/III Marshall Stack", CV73_menu, DisplayQueueFunction)
  end

  if not leaveQueueMenus[playername] then
    leaveQueueMenus[playername] = MENU_COALITION_COMMAND:New(coalition.side.BLUE, playername .. " - Remove Yourself from the CASE II/III Marshall Stack", CV73_menu, PlayerRemoveFunction, playername)
  end
  if joinQueueMenus[playername] then
    joinQueueMenus[playername]:Remove()
    joinQueueMenus[playername] = nil
  end
end

-- Function to handle clients inside the MarshallZone
local function ClientFunctionIn(client)
  local clientunit = client:GetClientGroupUnit()
  local playername = clientunit:GetPlayerName()
  if not case3_stack[playername] then
    case3_stack[playername] = true
    table.insert(case3_stack, playername)
    env.info("Player " .. playername .. " entered Marshall Zone.")

    -- Provide option to display Marshall Stack before joining
    if not displayQueueMenus[playername] then
      displayQueueMenus[playername] = MENU_COALITION_COMMAND:New(coalition.side.BLUE, playername .. " - Display the CASE II/III Marshall Stack", CV73_menu, DisplayQueueFunction)
    end

    if not joinQueueMenus[playername] then
      joinQueueMenus[playername] = MENU_COALITION_COMMAND:New(coalition.side.BLUE, playername .. " - Add Yourself to the CASE II/III Marshall Stack", CV73_menu, PlayerActionFunction, playername)
    end
  end
end

-- Function to check when clients leave the MarshallZone or disconnect (disconnect handling)
local function CleanUpDisconnectedPlayers()
  clients:ForEachClient(function(client)
    local playername = client:GetClientGroupUnit():GetPlayerName()
    if not client:IsAlive() then
      for i, entry in ipairs(case3_queue) do
        if entry:find(playername) then
          table.remove(case3_queue, i)
          env.info(playername .. " was disconnected and removed from the Case II/III Marshall Stack.")
          UpdateQueuePositions()
          BroadcastMessageToZone(playername .. " disconnected, Positions of the Case II/III Marshall Stack updated.")
          if leaveQueueMenus[playername] then
            leaveQueueMenus[playername]:Remove()
            leaveQueueMenus[playername] = nil
          end
          if joinQueueMenus[playername] then
            joinQueueMenus[playername]:Remove()
            joinQueueMenus[playername] = nil
          end
          if displayQueueMenus[playername] then
            displayQueueMenus[playername]:Remove()
            displayQueueMenus[playername] = nil
          end
          break
        end
      end
    end
  end)
end

-- Function to check which clients are in the MarshallZone
local function CheckZones()
  clients:ForEachClientInZone(MarshallZone, ClientFunctionIn)
end

-- Scheduler to Check Clients in the Marshall Zone every 10 seconds
SCHEDULER:New(nil, CheckZones, {}, 5, 30)

-- Scheduler to clean up disconnected players every 60 seconds
SCHEDULER:New(nil, CleanUpDisconnectedPlayers, {}, 5, 60)

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
      ArcoWash.OnEventEngineShutdown = function(EventData)
        env.info("ArcoWash despawning")
        ArcoWash:Stop()
        trigger.action.setUserFlag(501, true) -- carrier lights off
      end
    end
  end
end, {}, 120, 240)

-- Carrier Info Function
local function CarrierInfo()
  local heading = math.floor(CVN_73_beacon_unit:GetHeading() + 0.5)
  local windData = CVN73:GetWind(24) -- Refresh wind data
  local windDirection = math.floor(windData)
  local windSpeedMps = (windData - windDirection) * 1000000
  local windSpeedKnots = UTILS.MpsToKnots(windSpeedMps)

  if CVN73:IsSteamingIntoWind() then
    local brc = math.floor(CVN73:GetHeadingIntoWind(0, 25) + 0.5)
    local carrierSpeedKnots = CVN_73_beacon_unit:GetVelocityKNOTS()
    local windSpeedOverDeckKnots = windSpeedKnots + carrierSpeedKnots

    MESSAGE:New("CVN-73 is recovering, from " .. timerecovery_start .. " until " .. timerecovery_end):ToBlue()
    MESSAGE:New("BRC is " .. brc):ToBlue()
    MESSAGE:New("FB is " .. brc - 9):ToBlue()
    MESSAGE:New("Current Heading of the Carrier is " .. heading):ToBlue()
    MESSAGE:New(string.format("Wind over deck is from %d degrees at %.1f knots", windDirection, windSpeedOverDeckKnots)):ToBlue()
  else
    MESSAGE:New("CVN-73 is currently not recovering. Next Cyclic Ops Window starts at Minute " .. RecoveryStartatMinute):ToBlue()
    MESSAGE:New("Current Heading of the Carrier is " .. heading):ToBlue()
    MESSAGE:New(string.format("Wind is from %d degrees at %.1f knots", windDirection, windSpeedKnots)):ToBlue()
  end
end

MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Carrier Info", CV73_menu, CarrierInfo)

-- Debugging function to manually start the carrier's turn
local function setminute()
  start_recovery73()
  trigger.action.setUserFlag(502, true) -- lights on
end
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Debugging only: Manually start Recovery, do not use in Missions", CV73_menu, setminute)



-- Function to handle clients inside the MarshallZone
local function ClientFunctionIn(client)
  local clientunit = client:GetClientGroupUnit()
  local playername = clientunit:GetPlayerName()
  if not case3_stack[playername] then
    case3_stack[playername] = true
    table.insert(case3_stack, playername)
    env.info("Player " .. playername .. " entered Marshall Zone.")

    -- Provide option to display Marshall Stack before joining
    if not displayQueueMenus[playername] then
      displayQueueMenus[playername] = MENU_COALITION_COMMAND:New(coalition.side.BLUE, playername .. " - Display the CASE II/III Marshall Stack", CV73_menu, DisplayQueueFunction)
    end

    if not joinQueueMenus[playername] then
      joinQueueMenus[playername] = MENU_COALITION_COMMAND:New(coalition.side.BLUE, playername .. " - Add Yourself to the CASE II/III Marshall Stack", CV73_menu, PlayerActionFunction, playername)
    end
  end
end

 
