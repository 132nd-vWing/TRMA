-- Carrier Control Menu
local carrier_root_menu = MENU_MISSION:New("Carrier Control")
local CV73_menu = MENU_COALITION:New(coalition.side.BLUE, "CVN-73", carrier_root_menu)

trigger.action.setUserFlag(501, true) -- switch lights off on the Carrier

local timerecovery_start = nil
local timerecovery_end = nil
local global_timeend = nil
local CVN_73_beacon_unit = nil
local MarshallZone = nil
local clients = nil -- Declare clients to store player clients dynamically

-- Initialize SET_CLIENT for dynamically tracking active clients
clients = SET_CLIENT:New():FilterActive(true):FilterCoalitions("blue"):FilterStart()

-- CASE III Queue
local case3_queue = {}

-- Recovery Window Parameters
local RecoveryStartatMinute = 20 -- Minute at every hour when recovery starts
local RecoveryDuration = 35  -- Duration in Minutes for Recovery Window to stay open

-- Function to check if player is in the Marshall Zone
local function IsPlayerInMarshallZone(playerUnit)
  return MarshallZone and playerUnit and MarshallZone:IsCoordinateInZone(playerUnit:GetCoordinate())
end

-- Function to send a message to the player's group
local function SendMessageToGroup(playerUnit, message)
  if playerUnit and playerUnit:GetGroup() then
    MESSAGE:New(message, 10):ToGroup(playerUnit:GetGroup())
  end
end

-- Function to broadcast messages to all groups in the Marshall Zone
local function BroadcastMessageToZone(message)
  if MarshallZone then
    clients:ForEachClientInZone(MarshallZone, function(client)
      local playerUnit = client:GetClientGroupUnit()
      if playerUnit then
        SendMessageToGroup(playerUnit, message)
      end
    end)
  end
end

-- Set Frequencies via Script
local CVN_73_Group = GROUP:FindByName("CVN-73")
if CVN_73_Group then
  CVN_73_beacon_unit = CVN_73_Group:GetUnit(1)
  if CVN_73_beacon_unit then
    local CVN_73_Beacon = CVN_73_beacon_unit:GetBeacon()
    if CVN_73_Beacon then
      -- Proceed with the beacon commands
      CVN_73_beacon_unit:CommandActivateLink4(331, nil, "A73", 5)
      CVN_73_beacon_unit:CommandActivateACLS(nil, "A73", 5)
      CVN_73_Beacon:ActivateICLS(13, "I73")
      CVN_73_Beacon:ActivateTACAN(13, "X", "T73", true)
      CVN_73_beacon_unit:CommandSetFrequency(309.5) -- Set Carrier Frequency
      CVN_73_beacon_unit:SetSpeed(UTILS.KnotsToKmph(16), true)
      env.info("Carrier Group is " .. CVN_73_Group:GetName())
      env.info("Carrier Unit is " .. CVN_73_beacon_unit:GetName())

      -- Initialize the Marshall Zone
      MarshallZone = ZONE_UNIT:New("MarshallZone", CVN_73_beacon_unit, UTILS.NMToMeters(60))
    else
      BroadcastMessageToZone("Error: CVN-73 beacon not found! Check mission setup.")
      return
    end
  else
    BroadcastMessageToZone("Error: CVN-73 unit not found! Check mission setup.")
    return
  end
else
  BroadcastMessageToZone("Error: CVN-73 group not found! Check mission setup.")
  return
end

-- Carrier Activation and Behavior
local CVN73 = NAVYGROUP:New("CVN-73")
CVN73:Activate()
CVN73:SetPatrolAdInfinitum()  -- Infinite patrol mode
CVN73:SetSpeed(16)  -- Carrier speed in knots

-- Define Recovery Tanker
local ArcoWash = RECOVERYTANKER:New(CVN_73_beacon_unit, "CVN73_Tanker#IFF:5327FR")
ArcoWash:SetAltitude(10000)
ArcoWash:SetTACAN(64, 'SH1')
ArcoWash:SetRadio(142.5)
ArcoWash:SetUnlimitedFuel(true)
ArcoWash:SetTakeoffHot()

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
    BroadcastMessageToZone("Current cycle extended by 5 minutes, new cycle end will be " .. timerecovery_end)
  else
    BroadcastMessageToZone("CVN-73 is not steaming into wind, cannot extend recovery window")
  end
end

-- Function to Start Scheduled Recovery
local function start_recovery73()
  local timenow = timer.getAbsTime()
  global_timeend = timenow + RecoveryDuration * 60 -- Update global_timeend
  timerecovery_start = UTILS.SecondsToClock(timenow, true)
  timerecovery_end = UTILS.SecondsToClock(global_timeend, true)

  if not CVN73:IsSteamingIntoWind() then
    CVN73:AddTurnIntoWind(timerecovery_start, timerecovery_end, 25, true)
    BroadcastMessageToZone("CVN-73 is turning, Recovery Window open from " .. timerecovery_start .. " until " .. timerecovery_end)
    ArcoWash:Start()
  end
end

-- Function to get the player's unit dynamically and extract the player (client) name
local function GetPlayerUnitAndName()
  local playerUnit, playerName

  clients:ForEachClient(function(client)
    local unit = client:GetClientGroupUnit()
    if unit and unit:IsClient() then
      playerUnit = unit
      playerName = unit:GetPlayerName()
    end
  end)

  return playerUnit, playerName
end

-- Handle queue actions
local function HandlePlayerQueueAction(playerUnit, playerName, action)
  if IsPlayerInMarshallZone(playerUnit) then
    if action == "join" then
      -- Check if the player is already in the queue
      for _, entry in ipairs(case3_queue) do
        if entry:find(playerName) then
          SendMessageToGroup(playerUnit, "You are already in the CASE II/III Marshall Stack.")
          return
        end
      end

      -- Add the player to the queue
      local queue_position = #case3_queue + 1
      table.insert(case3_queue, "position " .. queue_position .. " " .. playerName)
      SendMessageToGroup(playerUnit, playerName .. " has joined the CASE II/III Marshall Stack.")

    elseif action == "leave" then
      -- Remove the player from the queue
      for i, entry in ipairs(case3_queue) do
        if entry:find(playerName) then
          table.remove(case3_queue, i)
          SendMessageToGroup(playerUnit, playerName .. " has been removed from the CASE II/III Marshall Stack.")
          return
        end
      end
      SendMessageToGroup(playerUnit, "You are not currently in the CASE II/III Marshall Stack.")

    elseif action == "display" then
      -- Display the current Marshall Stack
      if #case3_queue == 0 then
        SendMessageToGroup(playerUnit, "The CASE II/III Marshall Stack is currently empty.")
      else
        local queue_message = "CASE II/III Marshall Stack:\n"
        local windData = CVN73:GetWind(24)
        local windDirection = math.floor(windData)
        local reciprocalWindDirection = (windDirection + 180) % 360

        -- Calculate reciprocalFB as reciprocalWindDirection - 9 degrees
        local reciprocalFB = reciprocalWindDirection - 9
        if reciprocalFB < 0 then
          reciprocalFB = reciprocalFB + 360
        end

        local base_stackdistance = 21
        local base_stackangels = 6
        local base_pushtime = RecoveryStartatMinute + 6

        for i, entry in ipairs(case3_queue) do
          local playername = entry:match("position %d+ (.+)")
          local pushtime = base_pushtime + i
          local adjusted_stackdistance = base_stackdistance + i - 1
          local adjusted_stackangels = base_stackangels + i - 1
          queue_message = queue_message .. playername .. ", Marshall from Mother at " .. reciprocalFB .. "/" .. adjusted_stackdistance .. " , at Angels " .. adjusted_stackangels .. ". Pushtime Minute " .. pushtime .. "\n"
        end

        -- Send the detailed queue message to the player's group
        SendMessageToGroup(playerUnit, queue_message)
      end
    end
  else
    SendMessageToGroup(playerUnit, "You are not in the Marshall Zone.")
  end
end

-- Menu Options
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Join CASE II/III Marshall Stack", CV73_menu, function()
  local playerUnit, playerName = GetPlayerUnitAndName()
  if playerUnit and playerName then
    HandlePlayerQueueAction(playerUnit, playerName, "join")
  end
end)

MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Remove Yourself from CASE II/III Marshall Stack", CV73_menu, function()
  local playerUnit, playerName = GetPlayerUnitAndName()
  if playerUnit and playerName then
    HandlePlayerQueueAction(playerUnit, playerName, "leave")
  end
end)

MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Display CASE II/III Marshall Stack", CV73_menu, function()
  local playerUnit, playerName = GetPlayerUnitAndName()
  if playerUnit and playerName then
    HandlePlayerQueueAction(playerUnit, playerName, "display")
  end
end)

MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Carrier Info", CV73_menu, function()
  local playerUnit, playerName = GetPlayerUnitAndName()
  if playerUnit and IsPlayerInMarshallZone(playerUnit) then
    -- Fetch and send carrier info
    local heading = math.floor(CVN_73_beacon_unit:GetHeading() + 0.5)
    local windData = CVN73:GetWind(24)
    local windDirection = math.floor(windData)
    local windSpeedMps = (windData - windDirection) * 1000000
    local windSpeedKnots = UTILS.MpsToKnots(windSpeedMps)

    if CVN73:IsSteamingIntoWind() then
      local brc = math.floor(CVN73:GetHeadingIntoWind(0, 25) + 0.5)
      local carrierSpeedKnots = CVN_73_beacon_unit:GetVelocityKNOTS()
      local windSpeedOverDeckKnots = windSpeedKnots + carrierSpeedKnots

      -- Send detailed carrier info to the player's group
      SendMessageToGroup(playerUnit, "CVN-73 is recovering, from " .. timerecovery_start .. " until " .. timerecovery_end)
      SendMessageToGroup(playerUnit, "BRC is " .. brc)
      SendMessageToGroup(playerUnit, "FB is " .. brc - 9)
      SendMessageToGroup(playerUnit, "Current Heading of the Carrier is " .. heading)
      SendMessageToGroup(playerUnit, string.format("Wind over deck is from %d degrees at %.1f knots", windDirection, windSpeedOverDeckKnots))
    else
      -- Send info when the carrier is not in recovery
      SendMessageToGroup(playerUnit, "CVN-73 is currently not recovering. Next Cyclic Ops Window starts at Minute " .. RecoveryStartatMinute)
      SendMessageToGroup(playerUnit, "Current Heading of the Carrier is " .. heading)
      SendMessageToGroup(playerUnit, string.format("Wind is from %d degrees at %.1f knots", windDirection, windSpeedKnots))
    end
  else
    -- Notify player if they are not in the Marshall Zone
    SendMessageToGroup(playerUnit, "You are not in the Marshall Zone.")
  end
end)

-- Event handler for when a player lands
local LandHandler = EVENTHANDLER:New()

function LandHandler:OnEventLand(EventData)
  local unit = EventData.IniUnit
  
    local playername = unit:GetPlayerName()
    env.info("Player '" .. playername .. "' has landed.")

    -- Remove the player from the queue if they are in it
    HandlePlayerQueueAction(unit, playername, "leave")
  end


LandHandler:HandleEvent(EVENTS.Land)
-- Function to set up the event handlers
local function SetupEventHandlers()
  -- Event handler for when a player leaves a unit (disconnects or goes to spectators)
  local LeaveUnitHandler = EVENTHANDLER:New()

  function LeaveUnitHandler:OnEventPlayerLeaveUnit(EventData)
    env.info("PlayerLeaveUnit event triggered.")
    local unit = EventData.IniUnit
    local playerName = unit:GetPlayerName()
    env.info("Player '" .. playerName .. "' has left the unit '" .. unit:GetName() .. "'.")

    -- Remove the player from the queue if they are in it
    HandlePlayerQueueAction(unit, playerName, "leave")
  end

  LeaveUnitHandler:HandleEvent(EVENTS.PlayerLeaveUnit)

  -- Event handler for when a player enters a unit
  local EnterUnitHandler = EVENTHANDLER:New()

  function EnterUnitHandler:OnEventPlayerEnterUnit(EventData)
    env.info("PlayerEnterUnit event triggered.")
    local unit = EventData.IniUnit
    if unit and unit:IsClient() then
      local playerName = unit:GetPlayerName()
      env.info("Player '" .. playerName .. "' has entered the unit '" .. unit:GetName() .. "'.")

      -- Logic for handling players entering a new unit can be added here
    else
      env.info("No valid client unit detected.")
    end
  end

  EnterUnitHandler:HandleEvent(EVENTS.PlayerEnterUnit)
end

-- Call to setup event handlers when the script runs
env.info("Initializing event handlers.")
SetupEventHandlers()




-- Recovery and Carrier Info schedulers (unchanged)
SCHEDULER:New(nil, function()
  if CVN_73_beacon_unit then
    local current_minute = tonumber(os.date('%M'))
    local current_hour = tonumber(os.date('%H'))

    -- Check if we are at or before the recovery minute
    if current_minute == RecoveryStartatMinute then
      if not CVN73:IsSteamingIntoWind() then
        env.info("Recovery opening at Minute " .. current_minute)
        start_recovery73()
        trigger.action.setUserFlag(502, true) -- lights on
      end
    else
      -- If the current time is past the recovery window, do nothing and wait for the next hour's recovery window
      env.info("Current time is outside recovery window. Next recovery at " .. RecoveryStartatMinute .. " minutes.")
    end
  end
end, {}, 60, 30) -- Delay the first check by 60 seconds, then check every 30 seconds

-- Function to create the extend recovery menu
local function create_extend_recovery_menu()
  if extend_recovery_menu_command == nil then
    extend_recovery_menu_command = MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Extend current recovery window by 5 Minutes", CV73_menu, extend_recovery73)
  end
end

-- Function to remove the extend recovery menu
local function remove_extend_recovery_menu()
  if extend_recovery_menu_command then
    extend_recovery_menu_command:Remove()
    extend_recovery_menu_command = nil
  end
end

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

-- Carrier Information function
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

    BroadcastMessageToZone("CVN-73 is recovering, from " .. timerecovery_start .. " until " .. timerecovery_end)
    BroadcastMessageToZone("BRC is " .. brc)
    BroadcastMessageToZone("FB is " .. brc - 9)
    BroadcastMessageToZone("Current Heading of the Carrier is " .. heading)
    BroadcastMessageToZone(string.format("Wind over deck is from %d degrees at %.1f knots", windDirection, windSpeedOverDeckKnots))
  else
    BroadcastMessageToZone("CVN-73 is currently not recovering. Next Cyclic Ops Window starts at Minute " .. RecoveryStartatMinute)
    BroadcastMessageToZone("Current Heading of the Carrier is " .. heading)
    BroadcastMessageToZone(string.format("Wind is from %d degrees at %.1f knots", windDirection, windSpeedKnots))
  end
end

MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Carrier Info", CV73_menu, CarrierInfo)

local function setminute()
  start_recovery73()
  trigger.action.setUserFlag(502, true) -- lights on
end

MENU_COALITION_COMMAND:New(coalition.side.BLUE, "debug: start a cycle", CV73_menu, setminute)
