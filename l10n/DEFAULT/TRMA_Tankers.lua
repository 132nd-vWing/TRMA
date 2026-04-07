-- TANKERS --
-- Note: Ensure 'tanker_menu' is defined BEFORE this script runs
local activeTankers = {}
local tankerMenus = {}
local tankerTemplates = {
  {name = "AR201 #IFF:5201FR", spawnMenuText = "Spawn AR201", despawnMenuText = "Despawn AR201", menuGroup = "BLUE"},
  {name = "AR202 #IFF:5202FR", spawnMenuText = "Spawn AR202", despawnMenuText = "Despawn AR202", menuGroup = "BLUE"},
  {name = "AR203 #IFF:5203FR", spawnMenuText = "Spawn AR203", despawnMenuText = "Despawn AR203", menuGroup = "BLUE"},
  {name = "AR204 #IFF:5204FR", spawnMenuText = "Spawn AR204", despawnMenuText = "Despawn AR204", menuGroup = "BLUE"}, 
  {name = "AR301 #IFF:5301FR", spawnMenuText = "Spawn AR301", despawnMenuText = "Despawn AR301", menuGroup = "BLUE"},
  {name = "AR302 #IFF:5302FR", spawnMenuText = "Spawn AR302", despawnMenuText = "Despawn AR302", menuGroup = "BLUE"},
  {name = "AR303 #IFF:5303FR", spawnMenuText = "Spawn AR303", despawnMenuText = "Despawn AR303", menuGroup = "BLUE"},
  {name = "AR304 #IFF:5304FR", spawnMenuText = "Spawn AR304", despawnMenuText = "Despawn AR304", menuGroup = "BLUE"},
  {name = "AR305 #IFF:5305FR", spawnMenuText = "Spawn AR305", despawnMenuText = "Despawn AR305", menuGroup = "BLUE"},
  {name = "AR401 #IFF:5401FR", spawnMenuText = "Spawn AR401", despawnMenuText = "Despawn AR401", menuGroup = "RED"},
  {name = "AR402 #IFF:5402FR", spawnMenuText = "Spawn AR402", despawnMenuText = "Despawn AR402", menuGroup = "RED"},
  {name = "AR403 #IFF:5403FR", spawnMenuText = "Spawn AR403", despawnMenuText = "Despawn AR403", menuGroup = "RED"},
  {name = "AR404 #IFF:5404FR", spawnMenuText = "Spawn AR404", despawnMenuText = "Despawn AR404", menuGroup = "RED"},
  {name = "AR501 #IFF:5501FR", spawnMenuText = "Spawn AR501", despawnMenuText = "Despawn AR501", menuGroup = "RED"},
  {name = "AR502 #IFF:5502FR", spawnMenuText = "Spawn AR502", despawnMenuText = "Despawn AR502", menuGroup = "RED"},
  {name = "AR503 #IFF:5503FR", spawnMenuText = "Spawn AR503", despawnMenuText = "Despawn AR503", menuGroup = "RED"},
  {name = "AR504 #IFF:5504FR", spawnMenuText = "Spawn AR504", despawnMenuText = "Despawn AR504", menuGroup = "RED"}
}

-- Forward declaration of functions so the menus can see them
local tankerActivate
local tankerDeactivate

tankerActivate = function(tankerIndex)
    local template = tankerTemplates[tankerIndex]
    local tankerGroup = GROUP:FindByName(template.name)
    
    if tankerGroup then
        tankerGroup:Activate() 
        env.info("Activated Tanker: " .. template.name)

        activeTankers[tankerIndex] = template.name -- Use template name for list clarity
        
        -- Update Menus
        if tankerMenus[tankerIndex].spawnMenu then
            tankerMenus[tankerIndex].spawnMenu:Remove()
            tankerMenus[tankerIndex].spawnMenu = nil
        end
        
        local menuParent = template.menuGroup == "BLUE" and tanker_menu_blue1 or tanker_menu_red1
        tankerMenus[tankerIndex].despawnMenu = MENU_MISSION_COMMAND:New(template.despawnMenuText, menuParent, function() tankerDeactivate(tankerIndex) end)
    else
        env.error("Could not find Group in ME: " .. template.name)
        MESSAGE:New("Error: Group " .. template.name .. " not found in Mission Editor!", 10):ToAll()
    end
end

tankerDeactivate = function(tankerIndex)
    local template = tankerTemplates[tankerIndex]
    local tankerGroup = GROUP:FindByName(template.name)
    
    if tankerGroup then
        tankerGroup:Destroy() 
        env.info("Deactivated Tanker: " .. template.name)
        activeTankers[tankerIndex] = nil 
        
        -- Update Menus
        if tankerMenus[tankerIndex].despawnMenu then
            tankerMenus[tankerIndex].despawnMenu:Remove()
            tankerMenus[tankerIndex].despawnMenu = nil
        end
        
        local menuParent = template.menuGroup == "BLUE" and tanker_menu_blue1 or tanker_menu_red1
        tankerMenus[tankerIndex].spawnMenu = MENU_MISSION_COMMAND:New(template.spawnMenuText, menuParent, function() tankerActivate(tankerIndex) end)
    end
end

local function listActiveTankers()
    local msg = "Operating Tankers:\n"
    local count = 0
    
    for index, name in pairs(activeTankers) do
        msg = msg .. "- " .. name .. "\n"
        count = count + 1
    end
    
    if count > 0 then
        MESSAGE:New(msg, 10):ToAll()
    else
        MESSAGE:New("No Tankers operating, spawn via Tanker menu", 5):ToAll()
    end
end

-- Menu groups (Assumes 'tanker_menu' is already created globally)
tanker_menu_blue1 = MENU_MISSION:New("Blue Tankers", tanker_menu)
tanker_menu_red1 = MENU_MISSION:New("Red Tankers", tanker_menu)

-- Initialize menus for each tanker
for i, template in ipairs(tankerTemplates) do
    tankerMenus[i] = {}
    local menuParent = template.menuGroup == "BLUE" and tanker_menu_blue1 or tanker_menu_red1
    tankerMenus[i].spawnMenu = MENU_MISSION_COMMAND:New(template.spawnMenuText, menuParent, function() tankerActivate(i) end)
end

-- Menu command to list active tankers
MENU_MISSION_COMMAND:New("List Active Tankers", tanker_menu, listActiveTankers)
