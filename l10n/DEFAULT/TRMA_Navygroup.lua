-- Carrier Control Menu Initialization
env.info("Carrier Control Script Starting")
--local carrier_root_menu = MENU_MISSION:New("Carrier Control")
local CV73_menu = nil

trigger.action.setUserFlag(501, true) -- switch lights off on the Carrier

local timerecovery_start = nil
local timerecovery_end = nil
local global_timeend = nil
local CVN_73_beacon_unit = nil
local MarshallZone = nil
local clients = SET_CLIENT:New():FilterActive(true):FilterCoalitions("blue"):FilterStart()

-- Store player menus to prevent duplicates
local player_menus = {}

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

-- Function to get the player's unit dynamically from the group
local function GetPlayerUnitFromGroup(group)
  local playerUnit = nil

  -- Check if group is nil
  if not group then
    env.info("GetPlayerUnitFromGroup: group is nil, cannot find player unit")
    return nil
  end

  -- Refresh clients before searching to ensure we're using the latest data
  RefreshClients()
  clients:ForEachClient(function(client)
    local unit = client:GetClientGroupUnit()
    if unit and unit:GetGroup() == group then
      playerUnit = unit
    end
  end)

  if playerUnit then
    env.info("GetPlayerUnitFromGroup: Found player unit for group: " .. group:GetName())
  else
    env.info("GetPlayerUnitFromGroup: No player unit found for group: " .. group:GetName())
  end

  return playerUnit
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
    end
  end
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

-- Handle queue actions (joining, leaving, displaying)
local function HandlePlayerQueueAction(action, playerUnit, playerName)
  if not playerName then
    env.info("Player name is missing!")
    return
  end

  -- Log the action being taken
  env.info("Handling action '" .. action .. "' for player: " .. playerName)

  if action == "join" then
    if not playerUnit then
      env.info("Player unit not found for join action!")
      return
    end

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
    -- Check if the player is already removed
    local playerInQueue = false
    for i, entry in ipairs(case3_queue) do
      if entry:find(playerName) then
        playerInQueue = true
        table.remove(case3_queue, i)
        if playerUnit then
          SendMessageToGroup(playerUnit, playerName .. " has been removed from the CASE II/III Marshall Stack.")
        end
        env.info("Player " .. playerName .. " removed from CASE II/III Marshall Stack.")
        break
      end
    end

    if not playerInQueue then
      env.info("Player " .. playerName .. " was not in the CASE II/III Marshall Stack.")
    end

  elseif action == "display" then
    if not playerUnit then
      env.info("Player unit not found for display action!")
      return
    end

    -- Display the current Marshall Stack
    if #case3_queue == 0 then
      SendMessageToGroup(playerUnit, "The CASE II/III Marshall Stack is currently empty.")
    else
      local queue_message = "CASE II/III Marshall Stack:\n"
      for i, entry in ipairs(case3_queue) do
        queue_message = queue_message .. i .. ": " .. entry .. "\n"
      end
      SendMessageToGroup(playerUnit, queue_message)
    end
  end
end



-- Carrier Information function
local function CarrierInfo(playerUnit)
  if not playerUnit then
    env.info("CarrierInfo called but playerUnit is nil")
    return
  end

  if not CVN_73_beacon_unit then
    env.info("CVN-73 beacon unit is nil, cannot provide carrier info")
    return
  end

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
    SendMessageToGroup(playerUnit, "CVN-73 is currently not recovering. Next Cyclic Ops Window starts at Minute " .. RecoveryStartatMinute)
    SendMessageToGroup(playerUnit, "Current Heading of the Carrier is " .. heading)
    SendMessageToGroup(playerUnit, string.format("Wind is from %d degrees at %.1f knots", windDirection, windSpeedKnots))
  end
end

-- Function to initialize menus for a specific client (player)
local function InitializeMenusForClient(client)
  local playerUnit = client:GetClientGroupUnit()
  if playerUnit then
    local playerName = playerUnit:GetPlayerName()
    if playerName then
      env.info("Creating menu for player: " .. playerName)

      -- Prevent creating duplicate menus
      if player_menus[playerName] then
        env.info("Menu for player " .. playerName .. " already exists. Skipping creation.")
        return
      end

      -- Create player-specific carrier control menu
      local playerMenu = MENU_GROUP:New(playerUnit:GetGroup(), "Carrier Control")
      player_menus[playerName] = playerMenu  -- Store player menu to prevent duplicates

      -- Join CASE II/III Marshall Stack
      MENU_GROUP_COMMAND:New(playerUnit:GetGroup(), "Join CASE II/III Marshall Stack", playerMenu, function()
        -- Use the client directly to get the player's unit
        local invokingUnit = client:GetClientGroupUnit()
        if invokingUnit then
          local invokingPlayerName = invokingUnit:GetPlayerName()
          if invokingPlayerName then
            env.info("Player " .. invokingPlayerName .. " joining CASE II/III Stack")
            HandlePlayerQueueAction("join", invokingUnit, invokingPlayerName)
          end
        else
          env.info("invokingUnit not found for Join CASE II/III command")
        end
      end)

      -- Remove Yourself from CASE II/III Marshall Stack
      MENU_GROUP_COMMAND:New(playerUnit:GetGroup(), "Remove Yourself from CASE II/III Marshall Stack", playerMenu, function()
        -- Use the client directly to get the player's unit
        local invokingUnit = client:GetClientGroupUnit()
        if invokingUnit then
          local invokingPlayerName = invokingUnit:GetPlayerName()
          if invokingPlayerName then
            HandlePlayerQueueAction("leave", invokingUnit, invokingPlayerName)
          end
        else
          env.info("invokingUnit not found for Remove CASE II/III command")
        end
      end)

      -- Display CASE II/III Marshall Stack
      MENU_GROUP_COMMAND:New(playerUnit:GetGroup(), "Display CASE II/III Marshall Stack", playerMenu, function()
        -- Use the client directly to get the player's unit
        local invokingUnit = client:GetClientGroupUnit()
        if invokingUnit then
          local invokingPlayerName = invokingUnit:GetPlayerName()
          if invokingPlayerName then
            HandlePlayerQueueAction("display", invokingUnit, invokingPlayerName)
          end
        else
          env.info("invokingUnit not found for Display CASE II/III command")
        end
      end)

      -- Carrier Info Menu Option
      MENU_GROUP_COMMAND:New(playerUnit:GetGroup(), "Carrier Info", playerMenu, function()
        -- Use the client directly to get the player's unit
        local invokingUnit = client:GetClientGroupUnit()
        if invokingUnit then
          CarrierInfo(invokingUnit)
        else
          env.info("Carrier Info: invokingUnit not found")
        end
      end)
    end
  end
end


-- Function to find a client dynamically based on the player name
local function FindClientByName(playerName)
  local foundClient = nil
  clients:ForEachClient(function(client)
    local playerUnit = client:GetClientGroupUnit()
    if playerUnit and playerUnit:GetPlayerName() == playerName then
      foundClient = client
    end
  end)
  return foundClient
end

-- Event handler for when a player enters a unit or a relevant event occurs
local PlayerJoinHandler = EVENTHANDLER:New()

function PlayerJoinHandler:OnEventBirth(EventData)
  local playerName = EventData.IniPlayerName
  local playerUnit = EventData.IniUnit

  if playerName and playerUnit then
    env.info("Player '" .. playerName .. "' has spawned or joined a unit")

    -- Find the client dynamically using playerName
    local client = FindClientByName(playerName)
    if client then
      -- Always clear any existing menus for the player
      env.info("Clearing and reinitializing menus for player: " .. playerName)
      player_menus[playerName] = nil  -- Clear old menus
      InitializeMenusForClient(client)  -- Recreate menus for new unit
    else
      env.info("Client not found for player: " .. playerName)
    end
  else
    env.info("PlayerJoinHandler event: playerName or playerUnit is nil")
  end
end

-- Also handle the PlayerEnterUnit event directly (if it triggers)
function PlayerJoinHandler:OnEventPlayerEnterUnit(EventData)
  local playerName = EventData.IniPlayerName
  local playerUnit = EventData.IniUnit

  if playerName and playerUnit then
    env.info("Player '" .. playerName .. "' has entered a unit")

    -- Find the client dynamically using playerName
    local client = FindClientByName(playerName)
    if client then
      -- Always clear any existing menus for the player
      env.info("Clearing and reinitializing menus for player: " .. playerName)
      player_menus[playerName] = nil  -- Clear old menus
      InitializeMenusForClient(client)  -- Recreate menus for new unit
    else
      env.info("Client not found for player: " .. playerName)
    end
  else
    env.info("PlayerEnterUnit event: playerName or playerUnit is nil")
  end
end

-- Event handler for when a player leaves a unit
local PlayerLeaveHandler = EVENTHANDLER:New()

function PlayerLeaveHandler:OnEventPlayerLeaveUnit(EventData)
  -- Try to retrieve the player's name from the event data
  local playerName = EventData.IniPlayerName
  local unitName = EventData.IniUnit and EventData.IniUnit:GetName() or "Unknown Unit"

  -- Log more details to understand what's happening
  if not playerName then
    env.info("PlayerLeaveHandler: playerName is nil for unit " .. unitName)
  else
    env.info("Player '" .. playerName .. "' has left the unit '" .. unitName .. "'")
  end

  -- Proceed only if playerName is valid
  if playerName then
    -- Remove player from CASE II/III stack
    HandlePlayerQueueAction("leave", nil, playerName)

    -- Clear menus for the player to allow them to be recreated when joining a new unit
    player_menus[playerName] = nil
  else
    env.info("PlayerLeaveHandler: Unable to handle leaving unit for player (no player name)")
  end
end



-- Register event handlers for joining and leaving units
PlayerJoinHandler:HandleEvent(EVENTS.PlayerEnterUnit)
PlayerLeaveHandler:HandleEvent(EVENTS.PlayerLeaveUnit)
PlayerJoinHandler:HandleEvent(EVENTS.Birth)

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

-- SCHEDULER to handle carrier recovery and extend menu logic
SCHEDULER:New(nil, function()
  if CVN_73_beacon_unit then
    local current_minute = tonumber(os.date('%M'))

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

    -- Handle carrier heading and extend menu
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
end, {}, 60, 240)
