-- TANKERS --
local activeTankers = {}
local tankerMenus = {}
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

local function tankerList()
  if next(activeTankers) == nil then
    MESSAGE:New("No Tankers operating, spawn via Tanker menu", 5):ToAll()
    return
  end

  local lines = { "Operating Tankers:" }
  for i, template in ipairs(tankerTemplates) do
    if activeTankers[i] then
      table.insert(lines, "- " .. template.name)
    end
  end

  MESSAGE:New(table.concat(lines, "\n"), 5):ToAll()
end

local tankerSpawn

local function tankerDespawn(tankerIndex)
  local tankerTemplate = tankerTemplates[tankerIndex]
  local menuGroup = getMenuGroup(tankerTemplate)
  
  if tankerMenus[tankerIndex] and tankerMenus[tankerIndex].despawnMenu then
    tankerMenus[tankerIndex].despawnMenu:Remove()
    tankerMenus[tankerIndex].despawnMenu = nil
  end
  tankerMenus[tankerIndex].spawnMenu = MENU_MISSION_COMMAND:New(tankerTemplate.spawnMenuText, menuGroup, function() tankerSpawn(tankerIndex) end)


  if activeTankers[tankerIndex] then
    local group = GROUP:FindByName(activeTankers[tankerIndex])
    if group then group:Destroy() end
    activeTankers[tankerIndex] = nil
  end
end

function tankerSpawn(tankerIndex)
  local tankerTemplate = tankerTemplates[tankerIndex]
  local menuGroup = getMenuGroup(tankerTemplate)
  local cs = tankerTemplate.callsign

  local tanker = SPAWN:New(tankerTemplate.name)
  tanker:InitCallSign(CALLSIGN.Tanker[cs.id], cs.id, cs.major, cs.minor) 

  tanker:OnSpawnGroup( function(tankerGroup)
    activeTankers[tankerIndex] = tankerGroup:GetName()
    
    if tankerMenus[tankerIndex] and tankerMenus[tankerIndex].spawnMenu then
      tankerMenus[tankerIndex].spawnMenu:Remove()
      tankerMenus[tankerIndex].spawnMenu = nil
    end

    tankerMenus[tankerIndex].despawnMenu = MENU_MISSION_COMMAND:New(tankerTemplate.despawnMenuText, menuGroup, function() tankerDespawn(tankerIndex) end)
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

