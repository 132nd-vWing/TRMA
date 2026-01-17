-- Carrier Control Menu
local carrier_root_menu = MENU_MISSION:New("Carrier Control")
local case3stack = {}
local extensions = 0
-- Create Admin Menu
local CV73_admin_menu = MENU_COALITION:New(coalition.side.BLUE, "CVN-73 Admin", carrier_root_menu)

-- Recovery Window Parameters
RecoveryStartatMinute = 20 -- Minute at every hour when recovery starts 20 default
RecoveryDuration = 35  -- Duration in Minutes for Recovery Window to stay open  35 default
local clients = SET_CLIENT:New():FilterActive(true):FilterCoalitions("blue"):FilterStart()
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


-- ================================= Carrier ATIS ===================================

-- atis_weather --
local atis_weather = {}

-- Constants
local HPA_TO_INHG = 0.02953
local MMHG_TO_HPA = 1.33322
local MPS_TO_KNOTS = 1.94384

-- Function to log messages to DCS log
local function log(message)
  env.info("[ATIS Weather] " .. message)
end

-- Function to get QNH (hPa and inHg)
local function getQNH(weather)
  local mmHg = weather.qnh or 762.762  -- Use provided QNH or default to 762.762 mmHg

  -- Convert mmHg to hPa
  local qnh_hpa = mmHg * MMHG_TO_HPA
  log("RAW QNH: " .. mmHg .. " mmHg (" .. qnh_hpa .. " hPa)")

  -- Convert hPa to inHg
  local qnh_inhg = qnh_hpa * HPA_TO_INHG  -- Convert hPa to inHg
  log("Converted QNH: " .. qnh_hpa .. " hPa (" .. qnh_inhg .. " inHg)")

  return qnh_hpa, qnh_inhg
end

-- Function to get wind data at ground level from DCS weather
local function getWindDataAtGroundLevel(weather)
  local wind_data = weather.wind.atGround  -- Get ground-level wind data

  local wind_speed_mps = wind_data.speed  -- Wind speed in meters per second
  local wind_direction = wind_data.dir  -- Wind direction in degrees

  log("Ground-level Wind Direction: " .. wind_direction .. " degrees")
  log("Ground-level Wind Speed: " .. wind_speed_mps .. " m/s")

  -- Convert wind speed from meters per second to knots
  local wind_speed_knots = wind_speed_mps * MPS_TO_KNOTS

  return wind_direction, wind_speed_knots
end

-- Function to calculate temperature at a specific altitude
local function getTemperatureAtAltitude(weather, altitude)
  local sea_level_temperature = weather.season.temperature or 15  -- Default to 15°C if not provided
  local lapse_rate = 6.5  -- Standard lapse rate in °C per 1000 meters
  local temperature_at_altitude = sea_level_temperature - (lapse_rate * (altitude / 1000))
  return temperature_at_altitude
end


-- Function to get weather data and determine carrier case (Case 1, 2, or 3)
function atis_weather.getWeatherAndCarrierCaseAtPosition(carrier_unit, altitude)
  log("Getting weather data at altitude: " .. altitude .. " meters")

  local weather = env.mission.weather  -- Access mission weather data
  log("Weather data retrieved from mission")

  -- Get cloud base (in meters)
  local cloud_base = weather.clouds.base or 0  -- Cloud base altitude in meters
  log("Cloud Base: " .. cloud_base .. " meters")

  -- Initialize visibility (in meters)
  local visibility = weather.visibility.distance or 0  -- Base visibility in meters
  log("Base Visibility: " .. visibility .. " meters")

  -- Check for fog conditions
  if weather.fog and weather.fog.thickness > 0 then
    local fog_visibility = weather.fog.visibility or 0  -- Fog visibility
    visibility = math.min(visibility, fog_visibility)  -- Adjust visibility based on fog
    log("Fog detected. Fog Visibility: " .. fog_visibility .. " meters. Adjusted visibility: " .. visibility .. " meters")
  else
    log("No fog detected.")
  end

  -- Check for precipitation (rain) conditions
  local rain = ""
  if weather.precipitation then
    log("Precipitation data found: " .. tostring(weather.precipitation))
    if type(weather.precipitation) == "number" and weather.precipitation > 0 then
      rain = "Rain Detected"
      log("Rain detected with intensity (as number): " .. weather.precipitation)
    elseif type(weather.precipitation) == "table" and weather.precipitation.value and weather.precipitation.value > 0 then
      rain = "Rain Detected"
      visibility = math.min(visibility, weather.precipitation.value * 1000)  -- Adjust visibility based on precipitation intensity
      log("Rain detected with intensity (as table): " .. weather.precipitation.value .. ". Adjusted visibility: " .. visibility .. " meters")
    else
      rain = "No Rain"
      log("No precipitation detected or intensity is 0.")
    end
  else
    rain = "No Rain"
    log("No precipitation field in weather data.")
  end

  -- Get wind data at ground level
  local wind_direction, wind_speed_knots = getWindDataAtGroundLevel(weather)

  -- Calculate temperature at the given altitude
  local temperature = getTemperatureAtAltitude(weather, altitude)
  log("Temperature: " .. temperature .. "°C")

  -- Get QNH and correct for temperature
  local qnh_hpa, qnh_inhg = getQNH(weather, altitude)
  log(string.format("Corrected QNH: %.2f hPa (%.2f inHg)", qnh_hpa, qnh_inhg))

  -- Determine the carrier case based on cloud base, visibility, and fog
  local carrier_case
  local carrierpos = carrier_unit:GetCoordinate()
  if cloud_base > 914 and visibility > 9260 then
    carrier_case = "I"  -- Clear conditions for visual landings
    if carrierpos:IsDay() then
    else carrier_case = "III"  -- override CASE I with CASE III at nighttime
    end
  elseif cloud_base >= 305 and cloud_base <= 914 and visibility > 9260 then
    carrier_case = "II"  -- Cloud base is lower, but visibility is sufficient
    if carrierpos:IsDay() then
    else carrier_case = "III"  -- override CASE II with CASE III at nighttime
    end

  else
    carrier_case = "III"  -- Poor visibility or low cloud base requires IFR
  end
  log("Carrier Case: " .. carrier_case)

  return {
    cloud_base = cloud_base,      -- Cloud base in meters
    visibility = visibility,      -- Adjusted visibility in meters
    wind_speed = wind_speed_knots,      -- Wind speed in knots
    wind_direction = wind_direction,  -- Wind direction in degrees
    temperature = temperature,    -- Temperature in Celsius
    qnh_hpa = qnh_hpa,            -- QNH in hPa
    qnh_inhg = qnh_inhg,          -- QNH in inHg
    carrier_case = carrier_case,   -- Carrier case (Case 1, 2, or 3)
    rain = rain                   -- Rain information
  }
end

-- Function to return the formatted ATIS message as a string
function atis_weather.getATISMessage(weatherInfo)
  -- Determine visibility display
  local qnh_hpa_rounded = math.floor(weatherInfo.qnh_hpa + 0.5)
  local visibility_display
  if weatherInfo.visibility >= 10000 then
    visibility_display = "10+ km"
  elseif weatherInfo.visibility >= 1000 then
    visibility_display = string.format("%d km", math.floor(weatherInfo.visibility / 1000))
  else
    visibility_display = string.format("%d meters", weatherInfo.visibility)
  end

  return string.format(
    "ATIS Info:\nCloud Base: %d meters\nVisibility: %s\nWind: %.1f knots from %.0f°\nTemperature: %.1f°C\nQNH: %.2f inHg (%d hPa)\nCarrier Case: %s",
    weatherInfo.cloud_base,
    visibility_display,
    weatherInfo.wind_speed,
    weatherInfo.wind_direction,
    weatherInfo.temperature,
    weatherInfo.qnh_inhg,
    qnh_hpa_rounded,
    weatherInfo.carrier_case
  )
end

-- ================================= Carrier ATIS ===================================



-- Assuming CVN73 is your carrier unit in MOOSE
local carrier_name = "CVN-73"
local carrier_unit = UNIT:FindByName(carrier_name)  -- MOOSE unit object

if carrier_unit then
  weatherInfo = atis_weather.getWeatherAndCarrierCaseAtPosition(carrier_unit, 0)  -- Get weather at ground level (0 meters)
end


local CVN73 = NAVYGROUP:New("CVN-73")
CVN73:SetPatrolAdInfinitum()
CVN73:Activate()

function CVN73:OnAfterTurnIntoWindStop(From,Event,To)
  env.info("Cylce Stopped")
end

function CVN73:OnAfterTurnIntoWindStop(Eventdata)
  env.info("Cylce Stopped")
end

if GROUP:FindByName("CVN-73") then
  trigger.action.setUserFlag("501", false) -- switch lights off on the Carrier at Mission Start

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
    ArcoWash:SetRadio(282.5)
    ArcoWash:SetUnlimitedFuel(true)
    ArcoWash:SetTakeoffAir()

    -- Initialize the menu command variable
    local extend_recovery_menu_command = nil

    -- Function to Extend Recovery
    function extend_recovery73()
      extensions = extensions +1
      extendduration = 5 * 60
      env.info("Old cycle was " .. timerecovery_start .. " until " .. timerecovery_end)
      timeend = timeend + extendduration
      timerecovery_start = UTILS.SecondsToClock(timenow,false)
      timerecovery_end = UTILS.SecondsToClock(timeend, false)
      
      if CVN73:IsSteamingIntoWind() then
        env.info("New cycle is " .. timerecovery_start .. " until " .. timerecovery_end)
        CVN73:ExtendTurnIntoWind(extendduration)
        BroadcastMessageToZone("Current cycle extended by 5 minutes, new cycle end will be " .. timerecovery_end)
      else
        BroadcastMessageToZone("CVN-73 is not steaming into wind, cannot extend recovery window")
      end
    end

    -- Function to create the extend recovery menu option
    function create_extend_recovery_menu()
      if extend_recovery_menu_command == nil then
        extend_recovery_menu_command =  MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Extend current recovery window by 5 Minutes", CV73_admin_menu, extend_recovery73)

      end
    end

    -- Function to remove the extend recovery menu option
    function remove_extend_recovery_menu()
      if extend_recovery_menu_command then
        extend_recovery_menu_command:Remove()
        extend_recovery_menu_command = nil
      end
    end

    -- Function to Start Scheduled Recovery
    function start_recovery73()
      timenow = timer.getAbsTime()
      duration_seconds = RecoveryDuration * 60
      timeend = timenow + duration_seconds -- Initialize timeend

      -- Calculate the recovery start and end times as clock strings
      timerecovery_start = UTILS.SecondsToClock(timenow,false)
      timerecovery_end = UTILS.SecondsToClock(timeend,false)

      if CVN73:IsSteamingIntoWind() then
        return
        -- Do nothing if already steaming into the wind
      else
        -- Turn into the wind for recovery
        CVN73:AddTurnIntoWind(timerecovery_start, timerecovery_end, 25, true)
        BroadcastMessageToZone("CVN-73 is turning, Recovery Window open from " .. timerecovery_start .. " until " .. timerecovery_end .. ". Expect CASE " .. weatherInfo.carrier_case)
        ArcoWash:Start()
        create_extend_recovery_menu() -- Create the extend recovery menu option
      end
    end


    function QualDay()
      timenow = timer.getAbsTime()
      duration_seconds = 95 * 60
      timeend = timenow + duration_seconds -- Initialize timeend

      -- Calculate the recovery start and end times as clock strings
      timerecovery_start = UTILS.SecondsToClock(timenow,false)
      timerecovery_end = UTILS.SecondsToClock(timeend,false)

      if CVN73:IsSteamingIntoWind() then
        CVN73:ExtendTurnIntoWind(duration_seconds)
        BroadcastMessageToZone("Qual Day, current cycle extended by 95 Minutes. Recovery Window open from " .. timerecovery_start .. " until " .. timerecovery_end .. ". Expect CASE " .. weatherInfo.carrier_case)
        create_extend_recovery_menu() -- Create the extend recovery menu option

      else
        -- Turn into the wind for recovery
        CVN73:AddTurnIntoWind(timerecovery_start, timerecovery_end, 25, true)
        BroadcastMessageToZone("Qual Day, CVN-73 is turning, Recovery Window open from " .. timerecovery_start .. " until " .. timerecovery_end .. ". Expect CASE " .. weatherInfo.carrier_case)
        ArcoWash:Start()
        create_extend_recovery_menu() -- Create the extend recovery menu option
      end
      trigger.action.setUserFlag("501", true)
    end


    -- Nest Debug and Extend Recovery under CVN-73 Admin
    MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Qualification Day (Start 90-Min Cycle now)", CV73_admin_menu, QualDay)

    -- Scheduler to Check Time and Start Recovery if Necessary
    SCHEDULER:New(nil, function()
      if CVN_73_beacon_unit then
        local current_minute = tonumber(os.date('%M'))

        if current_minute == 0 + (extensions*5) then
          clearMarshallQueue()
          extensions = 0
        end

        if current_minute == RecoveryStartatMinute then
          if not CVN73:IsSteamingIntoWind() then
            env.info("Recovery opening at Minute " .. current_minute)
            start_recovery73()
            trigger.action.setUserFlag("501", true) -- lights on
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
          if ArcoWash:IsRunning() then
            ArcoWash:Stop()
          end
          if trigger.misc.getUserFlag("501") == true then
            trigger.action.setUserFlag("501", false)
          end
        end
      end
    end, {}, 120, 240)

    local function CarrierInfo()
      local heading = math.floor(CVN_73_beacon_unit:GetHeading() + 0.5)
      local windDirection, windSpeedMps = CVN73:GetWind(24)  -- Correct usage
      local windSpeedKnots = UTILS.MpsToKnots(windSpeedMps)

      if CVN73:IsSteamingIntoWind() then
        local brc = math.floor(CVN73:GetHeadingIntoWind(0, 25) + 0.5)
        local carrierSpeedKnots = CVN_73_beacon_unit:GetVelocityKNOTS()
        local windSpeedOverDeckKnots = windSpeedKnots + carrierSpeedKnots
        local fb = (brc - 9) % 360

        if fb < 0 then
          fb = fb + 360
        end

        BroadcastMessageToZone("CVN-73 is recovering, from " .. timerecovery_start .. " until " .. timerecovery_end .. ". CASE " .. weatherInfo.carrier_case .. " in Effect")
        BroadcastMessageToZone("BRC is " .. brc)
        BroadcastMessageToZone("FB is " .. fb)
        BroadcastMessageToZone("Current Heading of the Carrier is " .. heading)
        BroadcastMessageToZone(string.format("Wind over deck is from %d degrees at %.1f knots", windDirection, windSpeedOverDeckKnots))
      else
        BroadcastMessageToZone("CVN-73 is currently not recovering. Next Cyclic Ops Window start at Minute " .. RecoveryStartatMinute .. ". Expect CASE " .. weatherInfo.carrier_case)
        BroadcastMessageToZone("Current Heading of the Carrier is " .. heading)
        BroadcastMessageToZone(string.format("Wind is from %d degrees at %.1f knots", windDirection, windSpeedKnots))
      end

      -- removed the atis message until fixed
      -- BroadcastMessageToZone(atis_weather.getATISMessage(weatherInfo))
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

-- Initialize tables to store submenu references for Panthers and Spectres
local panthers_submenus = {}
local spectres_submenus = {}

-- Initialize case3stack table to store bort numbers as a queue
add_commands = {}

function removeBortFromMarshall(flight_num, range_menu)
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
      displayQueue()
    end
  end

  -- Remove the "remove" menu entry and recreate the "add" menu option
  if add_commands[flight_num] then
    add_commands[flight_num]:Remove()  -- Explicitly remove the "remove" command
    add_commands[flight_num] = nil  -- Clear the reference
  end

  if range_menu then
    local add_command = MENU_COALITION_COMMAND:New(coalition.side.BLUE, flight_num .. " add to CASE III Marshall Queue", range_menu, function()
      addBortToMarshall(flight_num, range_menu)
    end)
    add_commands[flight_num] = add_command  -- Store the add command for later reference
  end
end


function addBortToMarshall(flight_num, range_menu)
  -- Add the flight to the marshall queue
  table.insert(case3stack, flight_num)
  displayQueue()

  -- Remove the "add" menu entry for this bort number (from add_commands table)
  if add_commands[flight_num] then
    add_commands[flight_num]:Remove()  -- Explicitly remove the "add" command
    add_commands[flight_num] = nil  -- Clear the reference
  end

  -- Create a "remove" option in the same place within the specific range submenu
  local remove_command = MENU_COALITION_COMMAND:New(coalition.side.BLUE, flight_num .. " remove from CASE III Marshall Queue", range_menu, function()
    removeBortFromMarshall(flight_num, range_menu)
  end)

  -- Store the remove command in a table if needed (optional)
  add_commands[flight_num] = remove_command
end


-- Function to create bort number menu
local function createBortMenu(start_num, end_num, parent_menu, submenu_table)
  -- Create a range menu under the parent menu
  local range_menu = MENU_COALITION:New(coalition.side.BLUE, tostring(start_num) .. "-" .. tostring(end_num), parent_menu)

  -- Store the reference to the range menu in the submenu table
  submenu_table[start_num .. "-" .. end_num] = range_menu

  for flight_num = start_num, end_num do
    -- Create the "add to queue" menu option for each bort number directly under the range menu
    local add_command = MENU_COALITION_COMMAND:New(coalition.side.BLUE, flight_num .. " add to CASE III Marshall Queue", range_menu, function()
      addBortToMarshall(flight_num, range_menu)
    end)
    -- Store the add command in the table for later removal
    add_commands[flight_num] = add_command
  end
end

local function recreateAddMenuForRange(flight_num, submenu_table)
  for _, submenu in ipairs(submenu_table) do
    if flight_num >= submenu.start_num and flight_num <= submenu.end_num then
      local range_menu = submenu.menu

      -- Check if the range_menu exists and directly use it, no need for GetSubMenuByName
      if range_menu then
        -- Create the "add to queue" menu option
        local add_command = MENU_COALITION_COMMAND:New(coalition.side.BLUE, flight_num .. " add to CASE III Marshall Queue", range_menu, function()
          addBortToMarshall(flight_num, range_menu)
        end)

        -- Store the add command in the table for later removal
        add_commands[flight_num] = add_command
      else
        env.warning("Range menu not found for flight range " .. submenu.start_num .. "-" .. submenu.end_num)
      end
    end
  end
end


function displayQueue()
  if #case3stack == 0 then
    BroadcastMessageToZone("No flights currently in Marshall queue")
    return
  end

  -- Define the base values
  local adjusted_stackdistance = 21
  local adjusted_stackangels = 6
  local base_pushtime = RecoveryStartatMinute + 5

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


-- Create menus for Panthers and Spectres
createBortMenu(300, 306, panthers_menu, panthers_submenus)
createBortMenu(307, 313, panthers_menu, panthers_submenus)
createBortMenu(314, 320, panthers_menu, panthers_submenus)
createBortMenu(321, 327, panthers_menu, panthers_submenus)
createBortMenu(328, 334, panthers_menu, panthers_submenus)
createBortMenu(335, 341, panthers_menu, panthers_submenus)

createBortMenu(200, 206, spectres_menu, spectres_submenus)
createBortMenu(207, 213, spectres_menu, spectres_submenus)
createBortMenu(214, 220, spectres_menu, spectres_submenus)
createBortMenu(221, 227, spectres_menu, spectres_submenus)



function clearMarshallQueue()
  -- Clear the stack after removing all entries
  for flight_num, command in pairs(add_commands) do
    if command then
      command:Remove()  -- Remove all current "add" commands
    end
  end

  case3stack = {}
  add_commands = {}

  -- Recreate the "add to queue" menu options for all bort numbers in both ranges
  for flight_num = 300, 341 do
    local range_menu

    -- Find the correct range menu based on flight number
    if flight_num >= 300 and flight_num <= 306 then
      range_menu = panthers_submenus["300-306"]
    elseif flight_num >= 307 and flight_num <= 313 then
      range_menu = panthers_submenus["307-313"]
    elseif flight_num >= 314 and flight_num <= 320 then
      range_menu = panthers_submenus["314-320"]
    elseif flight_num >= 321 and flight_num <= 327 then
      range_menu = panthers_submenus["321-327"]
    elseif flight_num >= 328 and flight_num <= 334 then
      range_menu = panthers_submenus["328-334"]
    elseif flight_num >= 335 and flight_num <= 341 then
      range_menu = panthers_submenus["335-341"]
    end


    if range_menu then
      local add_command = MENU_COALITION_COMMAND:New(coalition.side.BLUE, flight_num .. " add to CASE III Marshall Queue", range_menu, function()
        addBortToMarshall(flight_num, range_menu)
      end)
      add_commands[flight_num] = add_command
    end
  end

  for flight_num = 200, 227 do
    local range_menu

    if flight_num >= 200 and flight_num <= 206 then
      range_menu = spectres_submenus["200-206"]
    elseif flight_num >= 207 and flight_num <= 213 then
      range_menu = spectres_submenus["207-213"]
    elseif flight_num >= 214 and flight_num <= 220 then
      range_menu = spectres_submenus["214-220"]
    elseif flight_num >= 221 and flight_num <= 227 then
      range_menu = spectres_submenus["221-227"]
    end


    if range_menu then
      local add_command = MENU_COALITION_COMMAND:New(coalition.side.BLUE, flight_num .. " add to CASE III Marshall Queue", range_menu, function()
        addBortToMarshall(flight_num, range_menu)
      end)
      add_commands[flight_num] = add_command
    end
  end

  BroadcastMessageToZone("The Marshall Queue has been cleared and menu options have been refreshed.")

end


-- Add a menu option to clear the entire marshall queue
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Clear Marshall Queue", CV73_admin_menu, clearMarshallQueue)



local function setCaseI()
  weatherInfo.carrier_case = "I"
end

local function setCaseII()
  weatherInfo.carrier_case = "II"
end

local function setCaseIII()
  weatherInfo.carrier_case = "III"
end

local function autoSetCarrierAtis()
  weatherInfo = atis_weather.getWeatherAndCarrierCaseAtPosition(carrier_unit, 0)  -- Get weather at ground level (0 meters)
end

MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Set CASE I", CV73_admin_menu, setCaseI)
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Set CASE II", CV73_admin_menu, setCaseII)
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Set CASE III", CV73_admin_menu, setCaseIII)
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Auto-set Carrier ATIS", CV73_admin_menu, autoSetCarrierAtis)
