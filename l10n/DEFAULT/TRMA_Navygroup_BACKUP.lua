-- Carrier Control Menu
local carrier_root_menu = MENU_MISSION:New("Carrier Control")
local CV73_menu = MENU_COALITION:New(coalition.side.BLUE, "CVN-73", carrier_root_menu)
trigger.action.setUserFlag(501, true) -- switch lights off on the Carrier

local timerecovery_start = nil
local timerecovery_end = nil
local global_timeend = nil
local CVN_73_beacon_unit = nil

-- Initialize Menu Tracking Tables
local leaveQueueMenus = {}
local joinQueueMenus = {}
local displayQueueMenus = {}
local players_in_zone = {}

-- CASE III Queue
local case3_queue = {}

-- Recovery Window Parameters
local RecoveryStartatMinute = 20 -- Minute at every hour when recovery starts
local RecoveryDuration = 35  -- Duration in Minutes for Recovery Window to stay open

-- Marshall Zone and Clients tracking (declare at the top to ensure they are globally accessible)
local MarshallZone = nil
local clients = nil

-- Function to broadcast messages to players in the Marshall Zone
local function BroadcastMessageToZone(message)
  clients:ForEachClientInZone(MarshallZone, function(client)
    MESSAGE:New(message, 10):ToClient(client)
  end)
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
      CVN_73_Beacon:CommandSetFrequency(309.5) -- Set Carrier Frequency
      CVN_73_beacon_unit:SetSpeed(UTILS.KnotsToKmph(16), true)
      env.info("Carrier Group is " .. CVN_73_Group:GetName())
      env.info("Carrier Unit is " .. CVN_73_beacon_unit:GetName())

      -- Initialize the Marshall Zone and Client Set
      MarshallZone = ZONE_UNIT:New("MarshallZone", CVN_73_beacon_unit, UTILS.NMToMeters(60))
      clients = SET_CLIENT:New():FilterActive(true):FilterCoalitions("blue"):FilterStart()

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
    create_extend_recovery_menu()  -- Create the extend recovery menu option
  end
end

-- Function to update queue positions after a player is removed
local function UpdateQueuePositions()
  for i, playerEntry in ipairs(case3_queue) do
    local playername = playerEntry:match("position %d+ (.+)")
    case3_queue[i] = "position " .. i .. " " .. playername
  end
end

-- Function to display the current queue
local function DisplayQueueFunction()
  if #case3_queue == 0 then
    BroadcastMessageToZone("The CASE II/III Marshall Stack is currently empty.")
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
    local base_pushtime = RecoveryStartatMinute + 10

    for i, entry in ipairs(case3_queue) do
      local playername = entry:match("position %d+ (.+)")
      local pushtime = base_pushtime + i
      local adjusted_stackdistance = base_stackdistance + i - 1
      local adjusted_stackangels = base_stackangels + i - 1
      queue_message = queue_message .. playername .. ", Marshall from Mother at " .. reciprocalFB .. "/" .. adjusted_stackdistance .. " , at Angels " .. adjusted_stackangels .. ". Pushtime Minute " .. pushtime .. "\n"
    end
    BroadcastMessageToZone(queue_message)
  end
end

-- Function to remove a player from the queue
local function RemovePlayerFromQueue(playername)
  for i, entry in ipairs(case3_queue) do
    if entry:find(playername) then
      table.remove(case3_queue, i)
      env.info(playername .. " removed from the CASE II/III Marshall Stack due to landing.")
      UpdateQueuePositions()
      BroadcastMessageToZone(playername .. " has landed and was removed from the CASE II/III Marshall Stack.")
      DisplayQueueFunction()

      -- Remove associated menus
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

-- Event handler for when a player lands
local LandHandler = EVENTHANDLER:New()

function LandHandler:OnEventLand(EventData)
  local unit = EventData.IniUnit
  if unit and unit:IsPlayer() then
    local playername = unit:GetPlayerName()
    env.info("Player '" .. playername .. "' has landed.")

    -- Remove the player from the queue if they are in it
    RemovePlayerFromQueue(playername)
  end
end

LandHandler:HandleEvent(EVENTS.Land)

-- Function to handle player removal manually (e.g., disconnection)
local function PlayerRemoveFunction(playername)
  RemovePlayerFromQueue(playername)
end

-- Function to handle player actions (add to queue)
local PlayerActionFunction = function(playername)
  for _, entry in ipairs(case3_queue) do
    if entry:find(playername) then
      BroadcastMessageToZone("You are already in the queue.")
      return
    end
  end
  local queue_position = #case3_queue + 1
  local queue_entry = "position " .. queue_position .. " " .. playername
  table.insert(case3_queue, queue_entry)
  env.info("Player added to case 3 queue: " .. queue_entry)

  BroadcastMessageToZone(playername .. " has joined the CASE II/III Marshall Stack.")
  DisplayQueueFunction()

  -- Use MENU_GROUP_COMMAND to add group-specific menu items
  local group = GROUP:FindByName(clientunit:GetGroup():GetName())
  if not displayQueueMenus[playername] then
    displayQueueMenus[playername] = MENU_GROUP_COMMAND:New(group, "Display the CASE II/III Marshall Stack", CV73_menu, DisplayQueueFunction, playername)
  end

  if not leaveQueueMenus[playername] then
    leaveQueueMenus[playername] = MENU_GROUP_COMMAND:New(group, "Remove Yourself from the CASE II/III Marshall Stack", CV73_menu, PlayerRemoveFunction, playername)
  end
  if joinQueueMenus[playername] then
    joinQueueMenus[playername]:Remove()
    joinQueueMenus[playername] = nil
  end
end

-- Function to track players entering the Marshall Zone
local function PlayerEnterZone(client)
  if client == nil then
    env.info("ERROR: Client is nil in PlayerEnterZone!")
    return
  end
  
  local clientunit = client:GetClientGroupUnit()
  if clientunit == nil then
    env.info("ERROR: Client unit is nil for client " .. tostring(client))
    return
  end
  
  local playername = clientunit:GetPlayerName()
  if playername == nil then
    env.info("ERROR: Player name is nil for client " .. tostring(client))
    return
  end

  -- Proceed with your logic if no errors
  env.info("Player " .. playername .. " entered the Marshall Zone.")
  
  -- Rest of the logic
  if not players_in_zone[playername] then
    players_in_zone[playername] = true

    local group = GROUP:FindByName(clientunit:GetGroup():GetName())
    if not displayQueueMenus[playername] then
      displayQueueMenus[playername] = MENU_GROUP_COMMAND:New(group, "Display the CASE II/III Marshall Stack", CV73_menu, DisplayQueueFunction, playername)
    end

    if not joinQueueMenus[playername] then
      joinQueueMenus[playername] = MENU_GROUP_COMMAND:New(group, "Add Yourself to the CASE II/III Marshall Stack", CV73_menu, PlayerActionFunction, playername)
    end
  end
end

-- Monitor Marshall Zone for players
local function MonitorMarshallZone()
  clients:ForEachClient(function(client)
    local status, err = pcall(function()
      PlayerEnterZone(client)
    end)
  
    if not status then
      env.info("ERROR: Failed to process client in ForEachClient: " .. tostring(err))
    end
  end)
end

-- Scheduler to Monitor Marshall Zone
SCHEDULER:New(nil, MonitorMarshallZone, {}, 5, 10)

-- Event handler for when a player leaves a unit (disconnects, logs out, etc.)
local LeaveUnitHandler = EVENTHANDLER:New()

function LeaveUnitHandler:OnEventPlayerLeaveUnit(EventData)
  local unit = EventData.IniUnit
  local playername = unit:GetPlayerName()

  if playername and unit then
    env.info("Player '" .. playername .. "' left unit '" .. unit:GetName() .. "'.")

    -- Only remove the player from the queue when they disconnect or log out
    RemovePlayerFromQueue(playername)

    players_in_zone[playername] = nil  -- Clean up from zone tracking
  end
end

LeaveUnitHandler:HandleEvent(EVENTS.PlayerLeaveUnit)

-- Recovery and Carrier Info schedulers (unchanged)
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
