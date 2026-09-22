-- TANKERS --
local activeTankers = {}
local tankerMenus = {}
local tankerAltitudes = {}
local tankerSpeeds = {}

-- Altitude is commanded in barometric feet. DCS has no climb-rate control, so
-- the AI picks its own vertical speed to get there.
local ALT_STEP_FT = 1000
local ALT_MIN_FT = 3000
local ALT_MAX_FT = 45000
local ALT_FALLBACK_FT = 20000

-- Speed is held and shown as indicated airspeed, which is what a receiver flies
-- to. DCS commands true airspeed, so every altitude change has to re-issue the
-- speed or the indicated figure on the label quietly drifts.
local SPD_STEP_KT = 10
local SPD_MIN_KT = 150
local SPD_MAX_KT = 350
local SPD_FALLBACK_KT = 300

local tankerTemplates = {
  {name = "AR101 #IFF:5101FR", callsign = { id = "Texaco", major = 1, minor = 1 }, spawnMenuText = "Spawn AR101", despawnMenuText = "Despawn AR101", menuGroup = "BLUE_BOOM"},
  {name = "AR102 #IFF:5102FR", callsign = { id = "Texaco", major = 2, minor = 1 }, spawnMenuText = "Spawn AR102", despawnMenuText = "Despawn AR102", menuGroup = "BLUE_BOOM"},
  {name = "AR201 #IFF:5201FR", callsign = { id = "Arco", major = 1, minor = 1 },   spawnMenuText = "Spawn AR201", despawnMenuText = "Despawn AR201", menuGroup = "BLUE_BOOM"},
  {name = "AR202 #IFF:5202FR", callsign = { id = "Arco", major = 2, minor = 1 },   spawnMenuText = "Spawn AR202", despawnMenuText = "Despawn AR202", menuGroup = "BLUE_BOOM"},
  {name = "AR203 #IFF:5203FR", callsign = { id = "Arco", major = 3, minor = 1 },   spawnMenuText = "Spawn AR203", despawnMenuText = "Despawn AR203", menuGroup = "BLUE_BOOM"},
  {name = "AR204 #IFF:5204FR", callsign = { id = "Arco", major = 4, minor = 1 },   spawnMenuText = "Spawn AR204", despawnMenuText = "Despawn AR204", menuGroup = "BLUE_BOOM"},
  {name = "AR301 #IFF:5301FR", callsign = { id = "Shell", major = 1, minor = 1 },  spawnMenuText = "Spawn AR301", despawnMenuText = "Despawn AR301", menuGroup = "BLUE_DROGUE"},
  {name = "AR302 #IFF:5302FR", callsign = { id = "Shell", major = 2, minor = 1 },  spawnMenuText = "Spawn AR302", despawnMenuText = "Despawn AR302", menuGroup = "BLUE_DROGUE"},
  {name = "AR303 #IFF:5303FR", callsign = { id = "Shell", major = 3, minor = 1 },  spawnMenuText = "Spawn AR303", despawnMenuText = "Despawn AR303", menuGroup = "BLUE_DROGUE"},
  {name = "AR304 #IFF:5304FR", callsign = { id = "Shell", major = 4, minor = 1 },  spawnMenuText = "Spawn AR304", despawnMenuText = "Despawn AR304", menuGroup = "BLUE_DROGUE"},
  {name = "AR305 #IFF:5305FR", callsign = { id = "Shell", major = 5, minor = 1 },  spawnMenuText = "Spawn AR305", despawnMenuText = "Despawn AR305", menuGroup = "BLUE_DROGUE"},
  {name = "AR401 #IFF:5401FR", callsign = { id = "Arco", major = 6, minor = 1 },   spawnMenuText = "Spawn AR401", despawnMenuText = "Despawn AR401", menuGroup = "RED"},
  {name = "AR402 #IFF:5402FR", callsign = { id = "Arco", major = 7, minor = 1 },   spawnMenuText = "Spawn AR402", despawnMenuText = "Despawn AR402", menuGroup = "RED"},
  {name = "AR403 #IFF:5403FR", callsign = { id = "Arco", major = 8, minor = 1 },   spawnMenuText = "Spawn AR403", despawnMenuText = "Despawn AR403", menuGroup = "RED"},
  {name = "AR404 #IFF:5404FR", callsign = { id = "Arco", major = 9, minor = 1 },   spawnMenuText = "Spawn AR404", despawnMenuText = "Despawn AR404", menuGroup = "RED"},
  {name = "AR501 #IFF:5501FR", callsign = { id = "Shell", major = 6, minor = 1 },  spawnMenuText = "Spawn AR501", despawnMenuText = "Despawn AR501", menuGroup = "RED"},
  {name = "AR502 #IFF:5502FR", callsign = { id = "Shell", major = 7, minor = 1 },  spawnMenuText = "Spawn AR502", despawnMenuText = "Despawn AR502", menuGroup = "RED"},
  {name = "AR503 #IFF:5503FR", callsign = { id = "Shell", major = 8, minor = 1 },  spawnMenuText = "Spawn AR503", despawnMenuText = "Despawn AR503", menuGroup = "RED"},
  {name = "AR504 #IFF:5504FR", callsign = { id = "Shell", major = 9, minor = 1 },  spawnMenuText = "Spawn AR504", despawnMenuText = "Despawn AR504", menuGroup = "RED"},
}

-- Menu groups
local tanker_menu_blue = MENU_MISSION:New("Blue Tankers", tanker_menu)
local tanker_menu_blue_boom = MENU_MISSION:New("Boom", tanker_menu_blue)
local tanker_menu_blue_drogue = MENU_MISSION:New("Drogue", tanker_menu_blue)
local tanker_menu_red1 = MENU_MISSION:New("Red Tankers", tanker_menu)


local function getMenuGroup(template) 
  if template.menuGroup == "BLUE_BOOM" then
    return tanker_menu_blue_boom
  elseif template.menuGroup == "BLUE_DROGUE" then
    return tanker_menu_blue_drogue
  else
    return tanker_menu_red1
  end
end

-- "AR101 #IFF:5101FR" -> "AR101"
local function tankerShortName(template)
  return template.name:match("^(%S+)") or template.name
end

local function roundTo(value, step)
  return math.floor(value / step + 0.5) * step
end

local function tankerList()
  if next(activeTankers) == nil then
    MESSAGE:New("No Tankers operating, spawn via Tanker menu", 5):ToAll()
    return
  end

  local lines = { "Operating Tankers:" }
  for i, template in ipairs(tankerTemplates) do
    if activeTankers[i] then
      table.insert(lines, string.format("- %s: %d ft, %d kt IAS", template.name,
        tankerAltitudes[i] or ALT_FALLBACK_FT, tankerSpeeds[i] or SPD_FALLBACK_KT))
    end
  end

  MESSAGE:New(table.concat(lines, "\n"), 5):ToAll()
end

local tankerSpawn
local tankerDespawn
local tankerControlMenu

-- The live GROUP for an active tanker, or nil if it never spawned or is gone.
local function tankerGroupOf(tankerIndex)
  local groupName = activeTankers[tankerIndex]
  local group = groupName and GROUP:FindByName(groupName)
  if group and group:IsAlive() then
    return group
  end
  return nil
end

-- Converts the held indicated airspeed to the true figure DCS wants and issues
-- it. UTILS.IasToTas and UTILS.TasToIas are a matched pair, so a tanker seeded
-- from its own template and commanded straight back gets its briefed speed.
-- Keep = true so the setting survives the next leg of the race-track orbit.
local function tankerApplySpeed(tankerIndex, group)
  local speed = tankerSpeeds[tankerIndex]
  local altitude = tankerAltitudes[tankerIndex]
  if not speed or not altitude then
    return
  end
  local trueSpeed = UTILS.IasToTas(speed, UTILS.FeetToMeters(altitude))
  group:SetSpeed(UTILS.KnotsToMps(trueSpeed), true)
end

local function tankerAltitudeRequest(tankerIndex, deltaFeet)
  local shortName = tankerShortName(tankerTemplates[tankerIndex])
  local group = tankerGroupOf(tankerIndex)
  if not group then
    MESSAGE:New(shortName .. " is not airborne.", 5):ToAll()
    return
  end

  local altitude = (tankerAltitudes[tankerIndex] or ALT_FALLBACK_FT) + deltaFeet
  if altitude < ALT_MIN_FT or altitude > ALT_MAX_FT then
    MESSAGE:New(string.format("%s is limited to %d - %d ft.",
      shortName, ALT_MIN_FT, ALT_MAX_FT), 5):ToAll()
    return
  end

  group:SetAltitude(UTILS.FeetToMeters(altitude), true, "BARO")
  tankerAltitudes[tankerIndex] = altitude
  tankerApplySpeed(tankerIndex, group)
  tankerControlMenu(tankerIndex)

  MESSAGE:New(string.format("%s %s to %d ft.", shortName,
    deltaFeet > 0 and "climbing" or "descending", altitude), 10):ToAll()
end

local function tankerSpeedRequest(tankerIndex, deltaKnots)
  local shortName = tankerShortName(tankerTemplates[tankerIndex])
  local group = tankerGroupOf(tankerIndex)
  if not group then
    MESSAGE:New(shortName .. " is not airborne.", 5):ToAll()
    return
  end

  local speed = (tankerSpeeds[tankerIndex] or SPD_FALLBACK_KT) + deltaKnots
  if speed < SPD_MIN_KT or speed > SPD_MAX_KT then
    MESSAGE:New(string.format("%s is limited to %d - %d kt IAS.",
      shortName, SPD_MIN_KT, SPD_MAX_KT), 5):ToAll()
    return
  end

  tankerSpeeds[tankerIndex] = speed
  tankerApplySpeed(tankerIndex, group)
  tankerControlMenu(tankerIndex)

  MESSAGE:New(string.format("%s speed set to %d kt IAS.", shortName, speed), 10):ToAll()
end

-- Rebuilt whenever a player changes a setting, because the label carries the
-- current altitude and speed and MOOSE menu text cannot be edited in place.
function tankerControlMenu(tankerIndex)
  local tankerTemplate = tankerTemplates[tankerIndex]
  local menus = tankerMenus[tankerIndex]

  if menus.tankerMenu then
    menus.tankerMenu:Remove()
    menus.tankerMenu = nil
  end

  menus.tankerMenu = MENU_MISSION:New(
    string.format("%s (%d ft, %d kt IAS)", tankerShortName(tankerTemplate),
      tankerAltitudes[tankerIndex] or ALT_FALLBACK_FT,
      tankerSpeeds[tankerIndex] or SPD_FALLBACK_KT),
    getMenuGroup(tankerTemplate)
  )
  MENU_MISSION_COMMAND:New(string.format("Climb %d ft", ALT_STEP_FT), menus.tankerMenu, function() tankerAltitudeRequest(tankerIndex, ALT_STEP_FT) end)
  MENU_MISSION_COMMAND:New(string.format("Descend %d ft", ALT_STEP_FT), menus.tankerMenu, function() tankerAltitudeRequest(tankerIndex, -ALT_STEP_FT) end)
  MENU_MISSION_COMMAND:New(string.format("IAS +%d kt", SPD_STEP_KT), menus.tankerMenu, function() tankerSpeedRequest(tankerIndex, SPD_STEP_KT) end)
  MENU_MISSION_COMMAND:New(string.format("IAS -%d kt", SPD_STEP_KT), menus.tankerMenu, function() tankerSpeedRequest(tankerIndex, -SPD_STEP_KT) end)
  MENU_MISSION_COMMAND:New(tankerTemplate.despawnMenuText, menus.tankerMenu, function() tankerDespawn(tankerIndex) end)
end

function tankerDespawn(tankerIndex)
  local tankerTemplate = tankerTemplates[tankerIndex]
  local menuGroup = getMenuGroup(tankerTemplate)

  if tankerMenus[tankerIndex] and tankerMenus[tankerIndex].tankerMenu then
    tankerMenus[tankerIndex].tankerMenu:Remove()
    tankerMenus[tankerIndex].tankerMenu = nil
  end
  tankerMenus[tankerIndex].spawnMenu = MENU_MISSION_COMMAND:New(tankerTemplate.spawnMenuText, menuGroup, function() tankerSpawn(tankerIndex) end)


  if activeTankers[tankerIndex] then
    local group = GROUP:FindByName(activeTankers[tankerIndex])
    if group then group:Destroy() end
    activeTankers[tankerIndex] = nil
  end
  tankerAltitudes[tankerIndex] = nil
  tankerSpeeds[tankerIndex] = nil
end

function tankerSpawn(tankerIndex)
  local tankerTemplate = tankerTemplates[tankerIndex]
  local cs = tankerTemplate.callsign

  local tanker = SPAWN:New(tankerTemplate.name)
  tanker:InitCallSign(CALLSIGN.Tanker[cs.id], cs.id, cs.major, cs.minor) 

  tanker:OnSpawnGroup( function(tankerGroup)
    activeTankers[tankerIndex] = tankerGroup:GetName()
    
    if tankerMenus[tankerIndex] and tankerMenus[tankerIndex].spawnMenu then
      tankerMenus[tankerIndex].spawnMenu:Remove()
      tankerMenus[tankerIndex].spawnMenu = nil
    end

    -- Seed from the briefed orbit rather than from the instantaneous state, so
    -- the first player change is relative to what the ME actually commanded.
    -- The stored waypoint speed is true, so convert it to indicated first.
    local route = tankerGroup:CopyRoute()
    local waypoint = route and route[1]
    local altitude = ALT_FALLBACK_FT
    local speed = SPD_FALLBACK_KT
    if waypoint and waypoint.alt then
      altitude = roundTo(UTILS.MetersToFeet(waypoint.alt), ALT_STEP_FT)
      if waypoint.speed then
        speed = roundTo(UTILS.TasToIas(UTILS.MpsToKnots(waypoint.speed), waypoint.alt), SPD_STEP_KT)
      end
    end

    tankerAltitudes[tankerIndex] = altitude
    tankerSpeeds[tankerIndex] = speed

    tankerControlMenu(tankerIndex)
  end):Spawn()
end

-- Initialize menus for each tanker
for i, tankerTemplate in ipairs(tankerTemplates) do
  tankerMenus[i] = {}
  local menuGroup = getMenuGroup(tankerTemplate)
  
  tankerMenus[i].spawnMenu = MENU_MISSION_COMMAND:New(
    tankerTemplate.spawnMenuText,
    menuGroup,
    function() tankerSpawn(i) end
  )
end

-- Menu command to list active tankers
list_active_tankers = MENU_MISSION_COMMAND:New("List Active Tankers", tanker_menu, tankerList)

