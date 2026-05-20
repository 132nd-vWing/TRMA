-- ============================================================================
-- TRMA SAG ENGINE (ver 2.0) - NAVYGROUP STANDARD
-- ============================================================================
-- Offers some flotilla options for ASuW training. ME groups are honoured. 
-- 1. Red_SAG patrols at random
-- 2. Reg_CSG patrols at random
-- 3. Red_ATG moves west is separated landing formation
-- 4. Red_Convoy moves west
-- 5. Pirate scenario small craft attack a freighter. 
-- 6. Clear all navy units. 
-- 
-- Mission Designer: 
-- 1. in ME add "R31_Naval_Spawn" trigger zone for each range you want ships in. 
-- 2. create Naval groups with the names above. Red_SAG etc. 
-- 3. load this before the range scripts. 
-- 4. add and edit the snip below to the range script. 

-- ==== RANGE LUA EMBED =============================================
-- add the following to the range lua where units are required 
-- ---------------------------------------------------------------------
-- -- Naval Initializer.
-- ---------------------------------------------------------------------
-- local range31_SAG = TRMA_SAG.Range:New("Range 31", {
--   spawnZone = "R31_Naval_Spawn" -- Define this zone in the ME
-- }, range_31_menu_root)
-- ==================================================================

TRMA_SAG = {}
TRMA_SAG.Range = {}
TRMA_SAG.Range.__index = TRMA_SAG.Range

-- ============================================================================
-- INIT
-- ============================================================================
function TRMA_SAG.Range:New(rangeName, config, parentMenu)
  local self = setmetatable({}, TRMA_SAG.Range)
  
  self.name       = rangeName
  self.parentMenu = parentMenu
  self.zone       = ZONE:New(config.spawnZone)
  self.spawnedGroups  = {}

  self:BuildMenu()

  env.info("[TRMA_SAG] Loaded Range: " .. self.name)
  return self
end

-- ============================================================================
-- NAVYGROUP RANDOM PATROL
-- ============================================================================

function TRMA_SAG.Range:StartPatrol(group, speed)
  if not group or not group:IsAlive() then return end

  local navy = NAVYGROUP:New(group)
  navy:SetSpeed(speed or 15)

  -- internal state
  local waypointCount = 4
  local function BuildRoute()
    if not group:IsAlive() then return end
    navy:ClearWaypoints()

    for i = 1, waypointCount do
      local coord = self.zone:GetRandomCoordinate()
      navy:AddWaypoint(coord, speed, i - 1, 0, true)
    end

    env.info("[TRMA_SAG] New patrol route built for " .. group:GetName())
  end

  -- initial route
  BuildRoute()

  -- monitor + rebuild route when near completion
  timer.scheduleFunction(function()

    if not group:IsAlive() then return end

    local wp = navy:GetWaypointCurrent()
    local idx = wp and wp.Index or 0

    if idx >= (waypointCount - 1) then
        BuildRoute()
    end

    return timer.getTime() + 60

  end, {}, timer.getTime() + 60)

end

-- ==============================================================================
-- PATROL SPAWNER
-- ==============================================================================
function TRMA_SAG.Range:SpawnPatrolGroup(templateName, speed)
  local alias = string.format("%s-%s", templateName, self.name:gsub("%s+","_"))
  local coord = self.zone:GetRandomCoordinate()
  
  SPAWN:NewWithAlias(templateName, alias)
    :OnSpawnGroup(function(group)
      table.insert(self.spawnedGroups, group)
      self:StartPatrol(group, speed)
    end)
    :SpawnFromCoordinate(coord)
    
  MessageToAll(self.name .. ": " .. templateName .. " is now patrolling.")
end

-- ============================================================================
-- CONVOY SPAWNER
-- ============================================================================
function TRMA_SAG.Range:SpawnConvoy(templateName, speed)
  local alias = string.format("%s-%s", templateName, self.name:gsub("%s+","_"))
  local coord = self.zone:GetRandomCoordinate()

  SPAWN:NewWithAlias(templateName, alias)
    :OnSpawnGroup(function(group)
        table.insert(self.spawnedGroups, group)
        local now = group:GetCoordinate()
        local destination = now:Translate(200000, math.random(80, 100))
        group:RouteToVec3(destination:GetVec3(), speed)
    end)
    :SpawnFromCoordinate(coord)

  MessageToAll(self.name .. ": " .. templateName .. " heading East.")
end

-- ============================================================================
-- PIRACY SPAWNER
-- ============================================================================
function TRMA_SAG.Range:SpawnPiracy()
  local blueAlias = "Blue_Freighter_" .. self.name:gsub("%s+", "_")
  local spawnCoord = self.zone:GetRandomCoordinate()

  SPAWN:NewWithAlias("Blue_Freighter", blueAlias)
    :OnSpawnGroup(function(blueGroup)
      table.insert(self.spawnedGroups, group)
     
      local now = blueGroup:GetCoordinate()
      local destination = now:Translate(200000, 270)
      blueGroup:RouteToVec3(destination:GetVec3(), 10)

      timer.scheduleFunction(function()
        if not blueGroup:IsAlive() then return end

        local pirateCoord = blueGroup:GetCoordinate():Translate(10000, math.random(360))
        local redAlias = "Red_Pirate_" .. self.name:gsub("%s+", "_")

        SPAWN:NewWithAlias("Red_Pirate", redAlias)
          :OnSpawnGroup(function(redGroup)
            table.insert(self.spawnedGroups, group)
            
            local function ChaseLoop()
              if redGroup:IsAlive() and blueGroup:IsAlive() then
                -- Get blue's live position and head there
                local target = blueGroup:GetCoordinate():GetVec3()
                redGroup:RouteToVec3(target, 35) 
                timer.scheduleFunction(ChaseLoop, {}, timer.getTime() + 20)
              end
            end

            ChaseLoop()
            redGroup:OptionROEWeaponFree()
          end)
          :SpawnFromCoordinate(pirateCoord)
      end, {}, timer.getTime() + 20)
    end)
    :SpawnFromCoordinate(spawnCoord) 
end

-- ============================================================================
-- CLEAN UP
-- ============================================================================

function TRMA_SAG.Range:ClearAll()
  for i, group in ipairs(self.spawnedGroups) do
    if group and group:IsAlive() then
      group:Destroy()
    end
  end
  -- Reset the table
  self.spawnedGroups = {}
  MessageToAll(self.name .. ": All naval units cleared.")
end

-- ============================================================================
-- MENU
-- ============================================================================
function TRMA_SAG.Range:BuildMenu()

  if self.menu then self.menu:Remove() end

  self.menu = MENU_MISSION:New(self.name .. " Naval Ops", self.parentMenu)

  MENU_MISSION_COMMAND:New("Activate SAG", self.menu, function() self:SpawnPatrolGroup("Red_SAG", 20) end)
  MENU_MISSION_COMMAND:New("Activate CSG", self.menu, function() self:SpawnPatrolGroup("Red_CSG", 20) end)
  MENU_MISSION_COMMAND:New("Activate ATG", self.menu, function() self:SpawnConvoy("Red_ATG", 10) end)
  MENU_MISSION_COMMAND:New("Activate Convoy", self.menu, function() self:SpawnConvoy("Red_Convoy", 12) end)
  MENU_MISSION_COMMAND:New("Activate Piracy Scenario", self.menu, function() self:SpawnPiracy() end)
  MENU_MISSION_COMMAND:New("Deactivate ALL NAVAL UNITS", self.menu, function() self:ClearAll() end)
end