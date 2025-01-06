-- TANKERS --
local activeTankers = {}
local tankerMenus = {}
local tankerTemplates = {
  {name = "AR201 #IFF:5201FR", spawnMenuText = "Spawn Blue TANKER AR201", despawnMenuText = "Despawn Blue TANKER AR201", menuGroup = "BLUE"},
  {name = "AR202 #IFF:5202FR", spawnMenuText = "Spawn Blue TANKER AR202", despawnMenuText = "Despawn Blue TANKER AR202", menuGroup = "BLUE"},
  {name = "AR203 #IFF:5203FR", spawnMenuText = "Spawn Blue TANKER AR203", despawnMenuText = "Despawn Blue TANKER AR203", menuGroup = "BLUE"},
  {name = "AR301 #IFF:5301FR", spawnMenuText = "Spawn Blue TANKER AR301", despawnMenuText = "Despawn Blue TANKER AR301", menuGroup = "BLUE"},
  {name = "AR302 #IFF:5302FR", spawnMenuText = "Spawn Blue TANKER AR302", despawnMenuText = "Despawn Blue TANKER AR302", menuGroup = "BLUE"},
  {name = "AR303 #IFF:5303FR", spawnMenuText = "Spawn Blue TANKER AR303", despawnMenuText = "Despawn Blue TANKER AR303", menuGroup = "BLUE"},
  {name = "AR304 #IFF:5304FR", spawnMenuText = "Spawn Blue TANKER AR304", despawnMenuText = "Despawn Blue TANKER AR304", menuGroup = "BLUE"},
  {name = "AR305 #IFF:5307FR", spawnMenuText = "Spawn Blue TANKER AR305", despawnMenuText = "Despawn Blue TANKER AR305", menuGroup = "BLUE"},
  {name = "AR401 #IFF:5401FR", spawnMenuText = "Spawn Red TANKER AR401", despawnMenuText = "Despawn Red TANKER AR401", menuGroup = "RED"},
  {name = "AR402 #IFF:5402FR", spawnMenuText = "Spawn Red TANKER AR402", despawnMenuText = "Despawn Red TANKER AR402", menuGroup = "RED"},
  {name = "AR403 #IFF:5403FR", spawnMenuText = "Spawn Red TANKER AR403", despawnMenuText = "Despawn Red TANKER AR403", menuGroup = "RED"},
  {name = "AR404 #IFF:5404FR", spawnMenuText = "Spawn Red TANKER AR404", despawnMenuText = "Despawn Red TANKER AR404", menuGroup = "RED"},
  {name = "AR501 #IFF:5501FR", spawnMenuText = "Spawn Red TANKER AR501", despawnMenuText = "Despawn Red TANKER AR501", menuGroup = "RED"},
  {name = "AR502 #IFF:5502FR", spawnMenuText = "Spawn Red TANKER AR502", despawnMenuText = "Despawn Red TANKER AR502", menuGroup = "RED"},
  {name = "AR503 #IFF:5503FR", spawnMenuText = "Spawn Red TANKER AR503", despawnMenuText = "Despawn Red TANKER AR503", menuGroup = "RED"}
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
  local tanker = SPAWN:New(tankerTemplate.name)
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
