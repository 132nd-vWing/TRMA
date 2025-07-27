-- AWACS --
local activeAWACS = {}
local AWACSMenus = {}
local AWACSTemplates = {
  {name = "FOCUS #IFF:5602FR", spawnMenuText = "Spawn Red AWACS FOCUS", despawnMenuText = "Despawn Red AWACS FOCUS", menuGroup = "RED"},
  {name = "FOCUS2 #IFF:5604FR", spawnMenuText = "Spawn Red AWACS FOCUS2", despawnMenuText = "Despawn Red AWACS FOCUS2", menuGroup = "RED"},
  {name = "FOCUS3 #IFF:5605FR", spawnMenuText = "Spawn Red AWACS FOCUS3", despawnMenuText = "Despawn Red AWACS FOCUS3", menuGroup = "RED"},
  {name = "WIZARD #IFF:5601FR", spawnMenuText = "Spawn Red AWACS WIZARD", despawnMenuText = "Despawn Red AWACS WIZARD", menuGroup = "RED"},
  {name = "DARKSTAR #IFF:5612FR", spawnMenuText = "Spawn Blue AWACS Darkstar", despawnMenuText = "Despawn Blue AWACS Darkstar", menuGroup = "BLUE"},
  {name = "MAGIC #IFF:5611FR", spawnMenuText = "Spawn Blue AWACS MAGIC", despawnMenuText = "Despawn Blue AWACS MAGIC ", menuGroup = "BLUE"},
  {name = "OVERLORD 2 #IFF:5613FR", spawnMenuText = "Spawn Blue AWACS OVERLORD", despawnMenuText = "Despawn Blue AWACS OVERLORD", menuGroup = "BLUE"}
  }


local function AWACS_active()
  if next(activeAWACS) then
    for index, activeAWACS in pairs(activeAWACS) do
      MessageToAll("Operating AWACS: " .. activeAWACS, 5)
    end
  else
    MessageToAll("No AWACS operating, spawn via AWACS menu", 5)
  end
end

local function AWACSDespawn(AWACSIndex)
  local AWACSTemplate = AWACSTemplates[AWACSIndex]
  local menuGroup = AWACSTemplate.menuGroup == "BLUE" and AWACS_menu_blue1 or AWACS_menu_red1

  if AWACSMenus[AWACSIndex] and AWACSMenus[AWACSIndex].despawnMenu then
    AWACSMenus[AWACSIndex].despawnMenu:Remove()
    AWACSMenus[AWACSIndex].despawnMenu = nil
  end

  if not AWACSMenus[AWACSIndex].spawnMenu then
    AWACSMenus[AWACSIndex].spawnMenu = MENU_MISSION_COMMAND:New(AWACSTemplate.spawnMenuText, menuGroup, function() AWACSpawn(AWACSIndex) end)
  end

  if activeAWACS[AWACSIndex] then
    local group = GROUP:FindByName(activeAWACS[AWACSIndex])
    if group then
      group:Destroy()
      env.info("Group " .. activeAWACS[AWACSIndex] .. " despawned")
    end
    activeAWACS[AWACSIndex] = nil -- Remove the AWACS from the active list
  end
end

function AWACSpawn(AWACSIndex)
  local AWACSTemplate = AWACSTemplates[AWACSIndex]
  local AWACS = SPAWN:New(AWACSTemplate.name)
  AWACS:OnSpawnGroup(
    function(AWACSGroup)
      activeAWACS[AWACSIndex] = AWACSGroup:GetName()
      env.info("Group " .. AWACSGroup:GetName() .. " spawned")
      local menuGroup = AWACSTemplate.menuGroup == "BLUE" and AWACS_menu_blue1 or AWACS_menu_red1
      if AWACSMenus[AWACSIndex] and AWACSMenus[AWACSIndex].spawnMenu then
        AWACSMenus[AWACSIndex].spawnMenu:Remove()
        AWACSMenus[AWACSIndex].spawnMenu = nil
      end
      AWACSMenus[AWACSIndex].despawnMenu = MENU_MISSION_COMMAND:New(AWACSTemplate.despawnMenuText, menuGroup, function() AWACSDespawn(AWACSIndex) end)
    end
  ):Spawn()
end

-- Menu groups
AWACS_menu_blue1 = MENU_MISSION:New("Blue AWACS", awacs_menu )
AWACS_menu_red1 = MENU_MISSION:New("Red AWACS", awacs_menu )

-- Initialize menus for each AWACS
for i, AWACSTemplate in ipairs(AWACSTemplates) do
  AWACSMenus[i] = {}
  local menuGroup = AWACSTemplate.menuGroup == "BLUE" and AWACS_menu_blue1 or AWACS_menu_red1
  AWACSMenus[i].spawnMenu = MENU_MISSION_COMMAND:New(AWACSTemplate.spawnMenuText, menuGroup, function() AWACSpawn(i) end)
end

-- Menu command to list active AWACS
list_active_AWACS = MENU_MISSION_COMMAND:New("List Active AWACS", awacs_menu, AWACS_active)

--AWACSpawn(3)


