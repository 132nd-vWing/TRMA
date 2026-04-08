-- TANKERS --
local activeTankers = {}
local tankerMenus = {}
local tankerTemplates = {
  {name = "AR101 #IFF:5101FR", callsign = { id = "Texaco", major = 1, minor = 1 }, spawnMenuText = "Spawn AR101", despawnMenuText = "Despawn AR101", menuGroup = "BLUE"},
  {name = "AR102 #IFF:5102FR", callsign = { id = "Texaco", major = 2, minor = 1 }, spawnMenuText = "Spawn AR102", despawnMenuText = "Despawn AR102", menuGroup = "BLUE"},
  {name = "AR201 #IFF:5201FR", callsign = { id = "Arco", major = 1, minor = 1 }, spawnMenuText = "Spawn AR201", despawnMenuText = "Despawn AR201", menuGroup = "BLUE"},
  {name = "AR202 #IFF:5202FR", callsign = { id = "Arco", major = 2, minor = 1 }, spawnMenuText = "Spawn AR202", despawnMenuText = "Despawn AR202", menuGroup = "BLUE"},
  {name = "AR203 #IFF:5203FR", callsign = { id = "Arco", major = 3, minor = 1 }, spawnMenuText = "Spawn AR203", despawnMenuText = "Despawn AR203", menuGroup = "BLUE"},
  {name = "AR204 #IFF:5204FR", callsign = { id = "Arco", major = 4, minor = 1 }, spawnMenuText = "Spawn AR204", despawnMenuText = "Despawn AR204", menuGroup = "BLUE"},
  {name = "AR301 #IFF:5301FR", callsign = { id = "Shell", major = 1, minor = 1 }, spawnMenuText = "Spawn AR301", despawnMenuText = "Despawn AR301", menuGroup = "BLUE"},
  {name = "AR302 #IFF:5302FR", callsign = { id = "Shell", major = 2, minor = 1 }, spawnMenuText = "Spawn AR302", despawnMenuText = "Despawn AR302", menuGroup = "BLUE"},
  {name = "AR303 #IFF:5303FR", callsign = { id = "Shell", major = 3, minor = 1 }, spawnMenuText = "Spawn AR303", despawnMenuText = "Despawn AR303", menuGroup = "BLUE"},
  {name = "AR304 #IFF:5304FR", callsign = { id = "Shell", major = 4, minor = 1 }, spawnMenuText = "Spawn AR304", despawnMenuText = "Despawn AR304", menuGroup = "BLUE"},
  --{name = "AR305 #IFF:5307FR", callsign = { id = "Shell", major = 5, minor = 1 }, spawnMenuText = "Spawn AR305", despawnMenuText = "Despawn AR305", menuGroup = "BLUE"},
  {name = "AR401 #IFF:5401FR", callsign = { id = "Arco", major = 6, minor = 1 }, spawnMenuText = "Spawn AR401", despawnMenuText = "Despawn AR401", menuGroup = "RED"},
  {name = "AR402 #IFF:5402FR", callsign = { id = "Arco", major = 7, minor = 1 }, spawnMenuText = "Spawn AR402", despawnMenuText = "Despawn AR402", menuGroup = "RED"},
  {name = "AR403 #IFF:5403FR", callsign = { id = "Arco", major = 8, minor = 1 }, spawnMenuText = "Spawn AR403", despawnMenuText = "Despawn AR403", menuGroup = "RED"},
  {name = "AR404 #IFF:5404FR", callsign = { id = "Arco", major = 9, minor = 1 }, spawnMenuText = "Spawn AR404", despawnMenuText = "Despawn AR404", menuGroup = "RED"},
  {name = "AR501 #IFF:5501FR", callsign = { id = "Shell", major = 6, minor = 1 }, spawnMenuText = "Spawn AR501", despawnMenuText = "Despawn AR501", menuGroup = "RED"},
  {name = "AR502 #IFF:5502FR", callsign = { id = "Shell", major = 7, minor = 1 }, spawnMenuText = "Spawn AR502", despawnMenuText = "Despawn AR502", menuGroup = "RED"},
  {name = "AR503 #IFF:5503FR", callsign = { id = "Shell", major = 8, minor = 1 }, spawnMenuText = "Spawn AR503", despawnMenuText = "Despawn AR503", menuGroup = "RED"},
  {name = "AR504 #IFF:5504FR", callsign = { id = "Shell", major = 9, minor = 1 }, spawnMenuText = "Spawn AR504", despawnMenuText = "Despawn  AR504", menuGroup = "RED"},
}

local function Tankers_active()
  if next(activeTankers) then
    for index, activeTanker in pairs(activeTankers) do
      MessageToAll("Operating Tankers: " .. activeTanker, 5)
    end
  else
    MessageToAll("No Tankers operating, spawn via Tanker menu", 5)
  end
end

local function tankerDespawn(tankerIndex)
  local tankerTemplate = tankerTemplates[tankerIndex]
  local menuGroup = tankerTemplate.menuGroup == "BLUE" and tanker_menu_blue1 or tanker_menu_red1

  if tankerMenus[tankerIndex] and tankerMenus[tankerIndex].despawnMenu then
    tankerMenus[tankerIndex].despawnMenu:Remove()
    tankerMenus[tankerIndex].despawnMenu = nil
  end

  if not tankerMenus[tankerIndex].spawnMenu then
    tankerMenus[tankerIndex].spawnMenu = MENU_MISSION_COMMAND:New(tankerTemplate.spawnMenuText, menuGroup, function() tankerSpawn(tankerIndex) end)
  end

  if activeTankers[tankerIndex] then
    local group = GROUP:FindByName(activeTankers[tankerIndex])
    if group then
      group:Destroy()
      env.info("Group " .. activeTankers[tankerIndex] .. " despawned")
    end
    activeTankers[tankerIndex] = nil -- Remove the tanker from the active list
  end
end

function tankerSpawn(tankerIndex)
  local tankerTemplate = tankerTemplates[tankerIndex]
  local cs = tankerTemplate.callsign
  local tanker = SPAWN:New(tankerTemplate.name)
  tanker:InitCallSign(CALLSIGN.Tanker[cs.id], cs.id, cs.major, cs.minor) 
  tanker:OnSpawnGroup(
    function(tankerGroup)
      activeTankers[tankerIndex] = tankerGroup:GetName()
      env.info("Group " .. tankerGroup:GetName() .. " spawned")
      local menuGroup = tankerTemplate.menuGroup == "BLUE" and tanker_menu_blue1 or tanker_menu_red1
      if tankerMenus[tankerIndex] and tankerMenus[tankerIndex].spawnMenu then
        tankerMenus[tankerIndex].spawnMenu:Remove()
        tankerMenus[tankerIndex].spawnMenu = nil
      end
      tankerMenus[tankerIndex].despawnMenu = MENU_MISSION_COMMAND:New(tankerTemplate.despawnMenuText, menuGroup, function() tankerDespawn(tankerIndex) end)
    end
  ):Spawn()
end

-- Menu groups
tanker_menu_blue1 = MENU_MISSION:New("Blue Tankers", tanker_menu )
tanker_menu_red1 = MENU_MISSION:New("Red Tankers", tanker_menu )

-- Initialize menus for each tanker
for i, tankerTemplate in ipairs(tankerTemplates) do
  tankerMenus[i] = {}
  local menuGroup = tankerTemplate.menuGroup == "BLUE" and tanker_menu_blue1 or tanker_menu_red1
  tankerMenus[i].spawnMenu = MENU_MISSION_COMMAND:New(tankerTemplate.spawnMenuText, menuGroup, function() tankerSpawn(i) end)
end

-- Menu command to list active tankers
list_active_tankers = MENU_MISSION_COMMAND:New("List Active Tankers", tanker_menu, Tankers_active)
