-- ============================================================================
-- TRMA A2A RANGE ENGINE (ver 2.5)
-- ============================================================================
-- Purpose: Automated A2A Spawning with "Leash" logic.
-- ver 2.5: added ACM MODE (1v1 practice, per-client-group F10 menu) - see the
--          ACM MODE section below for its own instructions and rationale.
-- Instructions for Mission Makers:
-- 1. in ME make sure there is R31_AA_Spawn_1 and _2, and R31_AA_Engage  trigger zone. (replace R31 with the range)
-- 2. in ME make sur ethe drones exist with name format Drone_{airframe} or Drone_{airframe}_BFM
-- 3. load this lua before the range luas. 
-- 4. Add and edit the snip A2A initializer below to the range lua.  
-- ============================================================================

-- ============================================================================
-- ----------------------------
-- -- A2A initializer
-- ----------------------------
-- local range33_A2A = TRMA_A2A.Range:New("Range 33", {
--   engageZone = "R33_AA_Engage",
--   capZones = {
--     { name = "West", zoneName = "R33_AA_Spawn_1" },
--     { name = "Mid", zoneName = "R33_AA_Spawn_2" }
--   }
-- }, range_33_menu_root)
-- ===========================================================================

-- ==============================================================================
-- Start
local debug = false

TRMA_A2A = {}

-- USER SETTINGS: Air frames must be called Drone_{airframe} or Drone_{airframe}_BFM in ME
TRMA_A2A.Airframes = { 
  "MIG23",
  "MIG29A",
  "SU30",
  "JF17",
  "MIG25",
  "SU27",
  "J11A",
  "MIG31" 
}

-- ============================================================================
-- ACM MODE (1v1 Air Combat Maneuvering)
-- ============================================================================
-- Purpose: a blue player picks a weapon set, a bandit type and a bandit count
--          from their own F10 menu and presses SPAWN BANDIT. One, two or four
--          aggressors spawn 15-25 NM out on a random bearing, nose-on, at a
--          random altitude in a window from 7000 ft below the player to 7000 ft
--          above him - that window's TOP capped at 25000 ft but never below the
--          player's own altitude, so a high player gets bandits at his level or
--          below rather than every one pinned to the cap. The terrain guards run
--          afterwards and may lift a bandit above the cap. Intercepts THAT CLIENT
--          GROUP only - the whole flight, not one pilot. The figures below
--          are the SPAWN-INSTANT placement only - two are placed line abreast 1 NM
--          apart, four as a box 1 NM wide and 5 NM deep. They are not held: DCS
--          wingmen rejoin the lead, so a DCS formation option (line abreast for a
--          2-ship, combat spread for a 4-ship) is commanded to keep the flight
--          spread out. The exact NM spacing is gone the moment the AI settles.
-- Instructions for Mission Makers:
-- 1. No ME work required. ACM reuses the existing Drone_Aggressor_{airframe} and
--    Drone_Aggressor_{airframe}_BFM templates listed in TRMA_A2A.Airframes.
-- 2. The menu is per client GROUP (MENU_GROUP) under its own top-level "ACM
--    Training"
--    entry - deliberately NOT nested under range_root_menu, which is a
--    MENU_MISSION and belongs to a different menu tree.
-- 3. Blue clients only. The aggressor templates are RED; a red player would get
--    a same-coalition bandit that will never engage him.
-- 4. State is in memory only and does not survive a mission restart.
-- ============================================================================

TRMA_A2A.ACM = {}

-- Per client-group state, keyed by GROUP name. Group name is stable across a
-- player leaving and re-slotting, and is the same key MOOSE's MENU_INDEX uses.
--   State[groupName] = { weapons, airframe, size, rootMenu, menuAlive,
--                       bandit, banditFG, spawnId, spawnTime }
-- spawnId is the monotonic stamp that lets a deferred SPAWN hook tell whether it
-- has been superseded; spawnTime backs the grace window in the watchdog.
TRMA_A2A.ACM.State = {}

TRMA_A2A.ACM.Defaults = { weapons = "AA", airframe = nil, size = 1 } -- airframe nil = random

TRMA_A2A.ACM.WeaponSets = {
  AA  = { key = "AA",  label = "Full A/A",  suffix = ""     },
  BFM = { key = "BFM", label = "WVR / BFM", suffix = "_BFM" }
}
TRMA_A2A.ACM.WeaponOrder = { "AA", "BFM" } -- pairs() is unordered; menus are not

-- Tuning
TRMA_A2A.ACM.SpawnRangeMinNM   = 15
TRMA_A2A.ACM.SpawnRangeMaxNM   = 25
TRMA_A2A.ACM.SpawnSpeedKnots   = 400    -- fallback when the player's own speed is unreadable
TRMA_A2A.ACM.RearSpeedFactor   = 1.25   -- rear-sector spawn: overtake so the bandit can close
TRMA_A2A.ACM.SpeedMinKnots     = 250    -- floor; 1.25 x a slow player must not stall the bandit
TRMA_A2A.ACM.SpeedMaxKnots     = 1200    -- ceiling;
TRMA_A2A.ACM.AheadLegNM        = 60     -- length of the straight-ahead leg, see SpawnBandit
TRMA_A2A.ACM.SpawnMinAGL       = 300    -- metres, terrain guard floor
-- Spawn altitude. FEET, because that is how the requirement is written and because
-- TRMA_MISC.lua runs _SETTINGS:SetImperial(). COORDINATE.y is metres ASL, so these
-- are converted at the point of use and nothing downstream sees feet.
TRMA_A2A.ACM.AltVarianceFt     = 7000   -- half-width of the altitude roll window, see SpawnBandit
TRMA_A2A.ACM.AltMaxFt          = 25000  -- ceiling on the roll window's TOP; never below the player
TRMA_A2A.ACM.LeashNM           = 60
TRMA_A2A.ACM.WatchdogSeconds   = 30
TRMA_A2A.ACM.SpawnGraceSeconds = 5      -- ignore a fresh bandit's liveness this long
TRMA_A2A.ACM.Skill             = "Good" -- matches TRMA_A2A.Range:SpawnFlight
TRMA_A2A.ACM.SpawnCount        = 0      -- monotonic; unique alias + spawn stamp

-- Multi-ship formations. Distances are NM and are rotated onto the spawn heading in
-- FormationOffsets. Only 1, 2 and 4 ships are offered.
TRMA_A2A.ACM.FormationSpanNM   = 1      -- line abreast / box lateral spacing at spawn
TRMA_A2A.ACM.FormationDepthNM  = 5      -- box trail depth at spawn
TRMA_A2A.ACM.SizeOrder         = { 1, 2, 4 } -- menu order; pairs() is unordered

-- The DCS controller formation commanded AFTER the spawn placement, so the flight
-- holds a spread instead of collapsing onto the lead. AI.Option.Air.id.FORMATION is a
-- DCS global, not a MOOSE one; MOOSE itself addresses it exactly this way at
-- Moose_.lua:27357, :107622 and :116009. The ENUMS values are Moose_.lua:193-231.
--   2-ship -> LineAbreast.Group (65539), the widest line-abreast variant and the
--             direct analogue of the requested line abreast.
--   4-ship -> Spread.Group (458755). Spread is the widest of the fixed-wing
--             formations, so it preserves most of the wide-and-deep box; FingerFour
--             would pull all four into a tight fighter formation, which is the
--             opposite of what was asked for.
TRMA_A2A.ACM.Formation2Ship    = ENUMS.Formation.FixedWing.LineAbreast.Group
TRMA_A2A.ACM.Formation4Ship    = ENUMS.Formation.FixedWing.Spread.Group

-- ----------------------------------------------------------------------------
-- STATE
-- ----------------------------------------------------------------------------
function TRMA_A2A.ACM:GetState(group)
  local groupName = group:GetName()
  local state = self.State[groupName]
  if not state then
    state = {
      groupName = groupName,
      weapons   = self.Defaults.weapons,
      airframe  = self.Defaults.airframe,
      size      = self.Defaults.size,
      rootMenu  = nil,
      menuAlive = false,
      bandit    = nil,
      banditFG  = nil
    }
    self.State[groupName] = state
  end
  return state
end

-- Bring one client group's menu into line with its state. Idempotent: calling it
-- twice on an unchanged live group rebuilds the menu exactly once. It must never
-- tear down a menu the player may currently have open.
function TRMA_A2A.ACM:Reconcile(group)
  if not group or not group:IsAlive() then return end

  local state = self.State[group:GetName()]
  if not state then
    self:GetState(group)   -- first sighting: create defaults
    self:RebuildMenu(group)
    return
  end

  if state.menuAlive == false then
    self:RebuildMenu(group)
  end
  -- menu already up and current: do nothing
end

-- ----------------------------------------------------------------------------
-- ACM RADIO MENU BUILDER (per player group)
-- ----------------------------------------------------------------------------
-- Precondition: group:IsAlive().
-- MENU_GROUP:New consults MENU_INDEX:HasGroupMenu first and, if an entry already
-- exists for this path, RETURNS THE CACHED OBJECT without adding anything to the
-- DCS menu. MENU_INDEX is keyed by group name, which is identical after a player
-- leaves and re-slots. So we always Remove() our own root first, and we always
-- keep the rootMenu reference so the GroupMenu==self identity check inside
-- MENU_GROUP:Remove holds. Remove() also needs the group alive - hence the guard.
-- NOTE: MENU_GROUP / MENU_GROUP_COMMAND take the GROUP as the FIRST argument.
-- That is not the case for the MENU_MISSION calls used elsewhere in this file.
function TRMA_A2A.ACM:RebuildMenu(group)
  if not group or not group:IsAlive() then return end

  local state = self:GetState(group)
  local weaponSet = self.WeaponSets[state.weapons] or self.WeaponSets[self.Defaults.weapons]

  if state.rootMenu then state.rootMenu:Remove() end
  state.rootMenu = MENU_GROUP:New(group, "ACM Training")

  -- Submenu: weapon set
  local mWeapons = MENU_GROUP:New(group, "Weapons: " .. weaponSet.label, state.rootMenu)
  for _, key in ipairs(self.WeaponOrder) do
    local wSet = self.WeaponSets[key]
    local icon = (key == state.weapons) and " [ACTIVE]" or ""
    MENU_GROUP_COMMAND:New(group, wSet.label .. icon, mWeapons, function()
      state.weapons = key
      TRMA_A2A.ACM:RebuildMenu(group)
    end)
  end

  -- Submenu: bandit airframe
  local mBandit = MENU_GROUP:New(group, "Bandit: " .. (state.airframe or "Random"), state.rootMenu)
  local randomIcon = (state.airframe == nil) and " [ACTIVE]" or ""
  MENU_GROUP_COMMAND:New(group, "Random" .. randomIcon, mBandit, function()
    state.airframe = nil
    TRMA_A2A.ACM:RebuildMenu(group)
  end)
  for _, airframe in ipairs(TRMA_A2A.Airframes) do
    local icon = (airframe == state.airframe) and " [ACTIVE]" or ""
    MENU_GROUP_COMMAND:New(group, airframe .. icon, mBandit, function()
      state.airframe = airframe
      TRMA_A2A.ACM:RebuildMenu(group)
    end)
  end

  -- Submenu: number of hostile aircraft. 1, 2 and 4 only - 2 is placed line abreast
  -- and 4 as a box, and there is no defined geometry for 3. Those are spawn-instant
  -- placements; what is held afterwards is a DCS formation, not the exact spacing.
  local size = state.size or self.Defaults.size
  local mSize = MENU_GROUP:New(group, "Bandit Count: " .. tostring(size), state.rootMenu)
  for _, n in ipairs(self.SizeOrder) do
    local icon = (n == size) and " [ACTIVE]" or ""
    MENU_GROUP_COMMAND:New(group, string.format("%d-ship", n) .. icon, mSize, function()
      state.size = n
      TRMA_A2A.ACM:RebuildMenu(group)
    end)
  end

  MENU_GROUP_COMMAND:New(group, "SPAWN BANDIT", state.rootMenu, function()
    TRMA_A2A.ACM:SpawnBandit(group)
  end)
  MENU_GROUP_COMMAND:New(group, "Despawn Bandit", state.rootMenu, function()
    TRMA_A2A.ACM:DespawnBandit(group, "ACM: bandit despawned. Knock it off.")
  end)

  state.menuAlive = true
end

-- ----------------------------------------------------------------------------
-- BANDIT SPEED AND SPAWN ASPECT
-- ----------------------------------------------------------------------------
-- Heading and speed are read from UNIT 1 - the same unit that supplies the spawn
-- anchor. GROUP:GetCoordinate (Moose_.lua:28055) -> GROUP:GetVec3 (:27998) ->
-- GetUnit(1) is unit 1 only, while GROUP:GetHeading (:28105) and
-- GROUP:GetVelocityVec3 (:27881) both average over every live unit. A mean heading
-- is meaningless across the 000/360 wrap: two aircraft on 350 and 010 average to
-- 180, which inverts the aspect and hands a head-on spawn the rear-sector overtake
-- speed. Most client groups in this mission are multi-slot, so that is the normal
-- case and not an exotic one. Both getters resolve GetUnit(1) themselves; they run
-- in the same synchronous frame, so they cannot disagree about which unit that is.
--
-- The guard chain stays. UNIT:GetHeading (POSITIONABLE:GetHeading, Moose_.lua:23414)
-- returns nil rather than NaN when the object cannot be read, and GetUnit(1) derefs
-- the DCS group, so a player who dies between the IsAlive() check in SpawnBandit and
-- this call still yields nil rather than a bogus aspect.
-- Returns degrees, or nil when it cannot be trusted.
function TRMA_A2A.ACM:GetPlayerHeading(playerGroup)
  local ok, heading = pcall(function()
    local unit = playerGroup:GetUnit(1)
    return unit and unit:GetHeading()
  end)
  if ok and type(heading) == "number" and heading == heading
     and heading >= 0 and heading <= 360 then
    return heading
  end
  return nil
end

-- Ground speed in knots, or nil when unreadable. Unit 1 again, for the same reason.
-- UNIT:GetVelocityKNOTS returns 0 rather than nil for a missing DCS object, which is
-- indistinguishable from a parked player - the speed clamp below is what makes both
-- cases safe.
function TRMA_A2A.ACM:GetPlayerSpeedKnots(playerGroup)
  local ok, knots = pcall(function()
    local unit = playerGroup:GetUnit(1)
    return unit and unit:GetVelocityKNOTS()
  end)
  if ok and type(knots) == "number" and knots == knots then
    return knots
  end
  return nil
end

-- Returns (speedKnots, aspectLabel).
-- bearing is the true bearing FROM the player TO the spawn point, so folding the
-- player's own heading out of it gives the spawn aspect. A bandit put down behind
-- the player has to overtake before it can do anything, hence RearSpeedFactor; from
-- the front sector a matched speed gives an honest merge.
function TRMA_A2A.ACM:ChooseBanditSpeed(playerGroup, bearing)
  local heading = self:GetPlayerHeading(playerGroup)
  local knots   = self:GetPlayerSpeedKnots(playerGroup)

  if not heading or not knots then
    env.info(string.format(
      "[TRMA_A2A][ACM] Player heading/speed unreadable (hdg=%s spd=%s) - using %d kt",
      tostring(heading), tostring(knots), self.SpawnSpeedKnots))
    return self.SpawnSpeedKnots, "aspect unknown"
  end

  local relative = ((bearing - heading + 540) % 360) - 180 -- [-180, 180)
  local front    = math.abs(relative) <= 90

  local speed = front and knots or (knots * self.RearSpeedFactor)

  -- Clamp. 1.25 x a near-stationary player is a bandit that falls out of the sky,
  -- and an unclamped fast player would send a MIG31 through the merge supersonic.
  if speed < self.SpeedMinKnots then speed = self.SpeedMinKnots end
  if speed > self.SpeedMaxKnots then speed = self.SpeedMaxKnots end

  return math.floor(speed + 0.5), front and "front sector" or "rear sector"
end

-- ----------------------------------------------------------------------------
-- STRAIGHT-AHEAD LEG
-- ----------------------------------------------------------------------------
-- Why this exists: SPAWN:SpawnFromVec3 (Moose_.lua:20795) relocates route.points[1]
-- and the unit positions and nothing else, so every Drone_Aggressor_* template keeps
-- its Mission Editor waypoint 2 at a fixed map position. The bandit was therefore
-- placed and pointed correctly and then immediately turned to fly that leftover
-- point. The templates are shared with the per-range A2A engine and must not be
-- edited, so the route is replaced at spawn instead.
--
-- DelaySeconds = 0 matters: CONTROLLABLE:Route defaults to `DelaySeconds or 1`, and
-- CONTROLLABLE:SetTask only calls Controller:setTask inline when WaitTime is nil or
-- 0 (Moose_.lua:24248) - anything else is scheduled. 0 kills the turn before the AI
-- can start it. This raw controller task is deliberately short lived: FLIGHTGROUP
-- takes ownership 0.3 s later and re-tasks the group itself, with the same leg.
function TRMA_A2A.ACM:RouteStraightAhead(banditGroup, fromCoord, toCoord, speedKnots)
  local speedKmh = UTILS.KnotsToKmph(speedKnots)
  local wpFrom = fromCoord:WaypointAirTurningPoint(COORDINATE.WaypointAltType.BARO, speedKmh)
  local wpTo   = toCoord:WaypointAirTurningPoint(COORDINATE.WaypointAltType.BARO, speedKmh)
  banditGroup:Route({ wpFrom, wpTo }, 0)
end

-- ----------------------------------------------------------------------------
-- FORMATION GEOMETRY
-- ----------------------------------------------------------------------------
-- Returns the table SPAWN:InitSetUnitRelativePositions wants for a 2- or 4-ship, or
-- nil for a single ship (nothing to place, and the caller must then not call it).
--
-- Read out of the vendored build rather than the docs:
--   * SPAWN:_Prepare replicates units[1] up to the grouping
--     (Moose_.lua:21042-21055), which is the only reason a 2- or 4-ship is possible
--     at all: every Drone_Aggressor_* template is 1-ship (mission:100205-100270) and
--     the templates are shared with the range engine, so they are not edited.
--   * Ordering, verified by reading: SpawnFromVec3 (:20795) calls _GetSpawnIndex ->
--     _InitializeSpawnGroups -> _Prepare FIRST, then relocates units[1..#units], and
--     only then calls SpawnWithIndex. So by the time the relative-position block at
--     :20247 runs, #units already equals the grouping AND units[1].x/.y are already
--     the spawn position, not the template's editor position. The offsets below are
--     therefore relative to the real spawn point.
--   * That block does units[i].x = BaseX + Positions[i].x and
--     units[i].y = BaseY + Positions[i].y and does NOT rotate by the spawn heading,
--     so the rotation has to happen here. In this template convention units[].x is
--     NORTH and units[].y is EAST (SpawnFromVec3 writes units[].x = Vec3.x and
--     units[].y = Vec3.z; the altitude goes in units[].alt).
--   * No .heading is supplied per unit: InitHeading has already given every unit the
--     same absolute heading (Moose_.lua:20241-20245) and the whole formation must
--     point one way. No .z either - these 2D unit templates have no z field.
--   * Positions[UnitID] is indexed for every unit with NO nil check, so the table
--     must hold exactly as many entries as InitGrouping.
--
-- along is + ahead, across is + right wing, both metres:
--   north = along*cos(H) - across*sin(H)
--   east  = along*sin(H) + across*cos(H)
function TRMA_A2A.ACM:FormationOffsets(size, headingDeg)
  local span  = UTILS.NMToMeters(self.FormationSpanNM)
  local depth = UTILS.NMToMeters(self.FormationDepthNM)

  local layout
  if size == 2 then
    -- Placed line abreast, 1 NM: wingman on the leader's right.
    layout = { { 0, 0 }, { 0, span } }
  elseif size == 4 then
    -- Placed as a box, 1 NM wide and 5 NM deep: second element trailing the first.
    -- Spacing this exact survives only the spawn instant - see FormationOption.
    layout = { { 0, 0 }, { 0, span }, { -depth, 0 }, { -depth, span } }
  else
    return nil
  end

  local h    = math.rad(headingDeg)
  local cosH = math.cos(h)
  local sinH = math.sin(h)

  local positions = {}
  for i = 1, #layout do
    local along, across = layout[i][1], layout[i][2]
    positions[i] = {
      x = (along * cosH) - (across * sinH), -- north
      y = (along * sinH) + (across * cosH)  -- east
    }
  end
  return positions
end

-- The DCS formation to command for a given size, or nil for a single ship. The offsets
-- above are the spawn INSTANT only; DCS wingmen rejoin the lead under whatever
-- formation the controller holds, so without this the spread collapses within seconds.
function TRMA_A2A.ACM:FormationOption(size)
  if size == 2 then return self.Formation2Ship end
  if size == 4 then return self.Formation4Ship end
  return nil
end

-- ----------------------------------------------------------------------------
-- BANDIT SPAWN
-- ----------------------------------------------------------------------------
-- Runs from SPAWN:OnSpawnGroup, which is NOT synchronous: SPAWN defers the hook by
-- 0.3 s through its SpawnHookScheduler. So SpawnFromCoordinate has long returned by
-- the time we get here, and a player who presses SPAWN BANDIT twice inside 0.3 s
-- gets two callbacks, potentially out of order. Each spawn is therefore stamped with
-- the monotonic SpawnCount, and a callback whose stamp no longer matches the state is
-- superseded: it cleans up its own group and touches nothing else. Without this a
-- superseded callback would overwrite state.bandit/banditFG and leave either a
-- FLIGHTGROUP whose 3 timers are never stopped or a live bandit owned by nobody.
-- playerGroup is captured as an upvalue at spawn time and is never re-resolved.
-- leg = { coord = <far end of the straight-ahead leg>, speedKnots = <cruise> }, as
-- computed in SpawnBandit; see the STRAIGHT-AHEAD LEG section above.
-- formationOption is the DCS formation id for this flight size, or nil for a 1-ship.
function TRMA_A2A.ACM:OnBanditSpawned(banditGroup, playerGroup, template, bearing, distNM, spawnId, leg, formationOption)
  if not banditGroup then return end

  local state = self.State[playerGroup:GetName()]

  if (not state) or state.spawnId ~= spawnId then
    env.info(string.format(
      "[TRMA_A2A][ACM] Discarding superseded spawn %s (stamp %s, current %s) for %s",
      banditGroup:GetName(), tostring(spawnId), tostring(state and state.spawnId), playerGroup:GetName()))
    -- Whole group, not GROUP:IsAlive(): IsAlive() reports unit 1 only, so with a
    -- multi-ship it would let a superseded spawn's surviving wingmen escape the
    -- disposal. Destroy(false) as everywhere else - FOX listens for DEAD/CRASH.
    if banditGroup:CountAliveUnits() > 0 then banditGroup:Destroy(false) end
    return
  end

  local flight    = FLIGHTGROUP:New(banditGroup)

  -- Make the formation stick across the FLIGHTGROUP takeover. FLIGHTGROUP:onafterSpawned
  -- (Moose_.lua:95727) calls SwitchFormation(self.option.Formation) for every AI group;
  -- option.Formation is nil on a fresh OPSGROUP (the class default at :101632, deep-copied
  -- per instance by BASE:Inherit at :5270), so OPSGROUP:SwitchFormation (:107618) falls
  -- back to optionDefault.Formation - which FLIGHTGROUP:_InitGroup has just set to
  -- EchelonLeft.Group (:96552). Left alone that overwrites the SetOption made at spawn.
  -- Setting the DEFAULT is what makes onafterSpawned re-apply OURS instead of MOOSE's, and
  -- _InitGroup runs synchronously inside FLIGHTGROUP:New (:94963), so it cannot undo this.
  -- The INTERCEPT auftrag does NOT clobber it: OPSGROUP:_SetMissionOptions (:104538) only
  -- switches formation when the mission carries optionFormation, which only
  -- AUFTRAG:SetFormation (:83184) sets and we never call.
  if formationOption then
    flight:SetDefaultFormation(formationOption)
  end

  -- The raw route set in SpawnBandit is a controller task only. FLIGHTGROUP keeps
  -- its own waypoint list, rebuilt in OPSGROUP:_InitWaypoints (Moose_.lua:106999)
  -- from the spawned group's DATABASE template - which still carries the stale
  -- Mission Editor waypoint 2. Left in place, the first RouteToMission rebuild
  -- would route the bandit through that leftover point and the turn would come
  -- back a few seconds after the merge started. Drop everything from index 2 and
  -- re-add our own leg. Waypoint 1 is the spawn point and is the CURRENT waypoint:
  -- keep it, or onafterUpdateRoute (which starts at self.currentwp + 1) would find
  -- nothing to fly to and call _CheckGroupDone instead.
  if leg and leg.coord then
    flight:ClearWaypoints(2)
    -- Speed is KNOTS here (FLIGHTGROUP:AddWaypoint, Moose_.lua:96718), unlike the
    -- km/h that COORDINATE:WaypointAir wants and the m/s a raw route point holds.
    -- Altitude nil = keep the coordinate's own altitude.
    flight:AddWaypoint(leg.coord, leg.speedKnots, nil, nil, true)
  end

  local intercept = AUFTRAG:NewINTERCEPT(playerGroup)

  -- AddMission queues AND schedules the mission. That is the whole start path -
  -- the OPSGROUP "start this mission now" method does not exist in the vendored
  -- MOOSE build, so do not go looking for one.
  -- INTERCEPT targets the player by identity. SetEngageDetectedOn is deliberately
  -- NOT used here - it selects by type and geography, so the bandit would abandon
  -- its student for any contact that wandered past.
  flight:AddMission(intercept)

  state.bandit   = banditGroup
  state.banditFG = flight

  local msg = string.format(
    "[TRMA_A2A][ACM] Spawned %s (template %s) for %s at brg %03d / %d NM, %d kt",
    banditGroup:GetName(), template, playerGroup:GetName(), bearing, distNM,
    (leg and leg.speedKnots) or -1)
  env.info(msg)
  if debug then
    MESSAGE:New(msg, 10):ToGroup(playerGroup)
  end
end

function TRMA_A2A.ACM:SpawnBandit(playerGroup)
  if not playerGroup or not playerGroup:IsAlive() then return end

  local state = self:GetState(playerGroup)

  -- One bandit per client group: replace, never stack.
  self:DespawnBandit(playerGroup, nil)

  local playerCoord = playerGroup:GetCoordinate()
  if not playerCoord then
    MESSAGE:New("ACM: could not read your position. Try again in a moment.", 10):ToGroup(playerGroup)
    return
  end

  local bearing = math.random(0, 359)
  local distNM  = math.random(self.SpawnRangeMinNM, self.SpawnRangeMaxNM)

  -- Aspect drives the bandit's speed: from behind it needs an overtake, from the
  -- front it matches. Both are read from the player as he is right now, once.
  local speedKnots, aspect = self:ChooseBanditSpeed(playerGroup, bearing)

  -- Translate takes degrees and returns a true compass offset. Keepalt = true
  -- copies the player's altitude verbatim; that is the STARTING point for the
  -- altitude roll below, not the final spawn altitude.
  local spawnCoord = playerCoord:Translate(UTILS.NMToMeters(distNM), bearing, true)

  -- ALTITUDE: rolled inside a WINDOW around the player's own altitude. ONE altitude
  -- for the whole spawn, never per unit: SpawnFromVec3 writes Vec3.y into
  -- units[i].alt for every unit, so a 2- or 4-ship is a single altitude block and
  -- the formation terrain loop further down stays valid. There is deliberately no
  -- low floor here - the terrain guards below are the floor, and they are the right
  -- one because they follow the ground.
  --
  -- The WINDOW is clamped, not the result. Clamping the result collapsed the upper
  -- half of the band onto AltMaxFt for a high player: at 20000 ft about one roll
  -- in seven landed on exactly 25000 ft, and above 32000 ft every single one did.
  -- Instead:
  --   low  = player - AltVarianceFt   (always the full spread below him)
  --   high = player + AltVarianceFt, capped at AltMaxFt, but NEVER below the player
  --          himself - so once he is at or above AltMaxFt the bandit comes in at his
  --          own altitude or below, and the roll stays genuinely random all the way
  --          up instead of pinning to the ceiling.
  --
  -- Order matters and is: Translate -> windowed roll -> terrain guards. The terrain
  -- guards run LAST and can therefore push the bandit back ABOVE AltMaxFt. That is
  -- intended, not a bug to be tidied away: airborne beats embedded in a hill. On
  -- Kola it cannot happen anyway - 25000 ft is 7620 m and no terrain on this map
  -- comes near it.
  local playerAltFt = UTILS.MetersToFeet(spawnCoord.y)
  local lowFt       = playerAltFt - self.AltVarianceFt
  local highFt      = math.min(playerAltFt + self.AltVarianceFt,
                               math.max(self.AltMaxFt, playerAltFt))
  if highFt < lowFt then highFt = lowFt end -- defensive; unreachable while AltVarianceFt >= 0

  local spawnAltFt = math.random(math.floor(lowFt + 0.5), math.floor(highFt + 0.5))
  local varianceFt = math.floor(spawnAltFt - playerAltFt + 0.5) -- actual offset, for the log
  spawnCoord.y     = UTILS.FeetToMeters(spawnAltFt)

  -- TERRAIN GUARD (required): neither Keepalt nor the roll above clamps to the
  -- ground under the new point. Put a bandit down at the player's altitude minus
  -- 7000 ft over rising terrain and it appears inside a mountain. Raise it to a
  -- minimum AGL and note that we did.
  local raised   = false
  local floorAlt = spawnCoord:GetLandHeight() + self.SpawnMinAGL
  if spawnCoord.y < floorAlt then
    spawnCoord.y = floorAlt
    raised = true
  end

  local airframe  = state.airframe or TRMA_A2A.Airframes[math.random(#TRMA_A2A.Airframes)]
  local weaponSet = self.WeaponSets[state.weapons] or self.WeaponSets[self.Defaults.weapons]
  local size      = state.size or self.Defaults.size
  local template  = string.format("Drone_Aggressor_%s", airframe) .. weaponSet.suffix

  -- Nose-on: the bandit faces back down the bearing we placed it on.
  local heading = (bearing + 180) % 360

  -- Formation offsets, rotated onto that heading, and the DCS formation that holds the
  -- shape afterwards. Both nil for a 1-ship.
  local formation       = self:FormationOffsets(size, heading)
  local formationOption = self:FormationOption(size)

  -- TERRAIN GUARD, part 2 (multi-ship). Every unit in the group shares ONE altitude
  -- - SpawnFromVec3 writes Vec3.y into units[i].alt for all of them - and the box is
  -- 5 NM deep, so the ground under the trailing element can be far higher than the
  -- ground under the leader. Apply the same floor over every occupied point, or the
  -- wingmen spawn inside a hill that the leader cleared. The offsets are north/east
  -- metres, i.e. COORDINATE x and z.
  if formation then
    for i = 1, #formation do
      local unitCoord = COORDINATE:New(spawnCoord.x + formation[i].x, spawnCoord.y,
                                       spawnCoord.z + formation[i].y)
      local unitFloor = unitCoord:GetLandHeight() + self.SpawnMinAGL
      if spawnCoord.y < unitFloor then
        spawnCoord.y = unitFloor
        raised = true
      end
    end
  end

  -- Far end of the straight-ahead leg, down that same heading. The leg only has to
  -- outlast the ~5 s until the INTERCEPT auftrag takes over, so its length is not
  -- load bearing: nothing checks that the bandit reaches the end, and because the
  -- leg starts 15-25 NM from the player and may run back toward him, its far end is
  -- NOT guaranteed to lie outside the leash. Same terrain guard as the spawn point:
  -- Translate keeps the source altitude verbatim and does not clamp to the ground
  -- under the new point.
  local aheadCoord = spawnCoord:Translate(UTILS.NMToMeters(self.AheadLegNM), heading, true)
  local aheadFloor = aheadCoord:GetLandHeight() + self.SpawnMinAGL
  if aheadCoord.y < aheadFloor then aheadCoord.y = aheadFloor end

  local leg = { coord = aheadCoord, speedKnots = speedKnots }

  -- The counter guarantees the alias is unique for the whole mission. A repeated
  -- group name would make FLIGHTGROUP:New hand back the stale OPSGROUP of an
  -- already-destroyed bandit, and the new one would silently never fly.
  -- It doubles as the stamp that lets the deferred OnSpawnGroup hook recognise
  -- that it has been superseded - see OnBanditSpawned.
  self.SpawnCount = self.SpawnCount + 1
  local mySpawn = self.SpawnCount
  state.spawnId   = mySpawn
  state.spawnTime = timer.getTime()

  local alias = string.format("%s-ACM-%d-%d", template, mySpawn, math.random(1000))

  local function OnSpawnGroup(banditGroup)
    TRMA_A2A.ACM:OnBanditSpawned(banditGroup, playerGroup, template, bearing, distNM, mySpawn,
      leg, formationOption)
  end

  -- InitHeading, NOT InitGroupHeading. InitGroupHeading is a rotation DELTA applied
  -- on top of whatever heading the ME template already carries (Moose_.lua:20236,
  -- unitHeading = template.heading + headingRad), and every Drone_Aggressor template
  -- carries a non-zero one. InitHeading sets the absolute heading in degrees, and it
  -- assigns it to EVERY unit (Moose_.lua:20241-20245), which is what keeps a 2- or
  -- 4-ship pointing one way.
  local spawner = SPAWN:NewWithAlias(template, alias)
    :InitGrouping(size)
    :InitHeading(heading, heading)
    -- InitSpeedKnots sets units[i].speed, i.e. the velocity the bandit is born
    -- with. It does NOT govern the cruise - that is the route waypoint speed,
    -- carried by RouteStraightAhead and by the FLIGHTGROUP waypoint in the hook.
    -- All three are given the same number on purpose.
    :InitSpeedKnots(speedKnots)
    :InitRandomizeCallsign()
    :InitSkill(self.Skill)
    :OnSpawnGroup(OnSpawnGroup)

  -- Only for a 2- or 4-ship: InitSetUnitRelativePositions indexes Positions[UnitID]
  -- for every unit with no nil check, so it is called only when FormationOffsets has
  -- produced exactly as many entries as the grouping.
  if formation then
    spawner:InitSetUnitRelativePositions(formation)
  end

  local banditGroup = spawner:SpawnFromCoordinate(spawnCoord)

  -- SpawnFromCoordinate hands back the GROUP straight away even though the hook is
  -- deferred, so record it now: that way a despawn inside the 0.3 s window can still
  -- reach the aircraft instead of waiting for the callback to clean up after itself.
  --
  -- It returns nil when SpawnFromVec3's _GetSpawnIndex fails (Moose_.lua:20834), and
  -- OnSpawnGroup only fires on success - so on failure OnBanditSpawned never runs and
  -- the player gets nothing at all. That is the one case worth breaking the silence
  -- for, on the same grounds as the "could not read your position" message above: it
  -- gives away nothing about a fight that is not happening.
  if banditGroup then
    state.bandit = banditGroup
    -- Synchronously, before the deferred hook: this is what actually stops the
    -- turn toward the template's leftover waypoint 2.
    self:RouteStraightAhead(banditGroup, spawnCoord, aheadCoord, speedKnots)

    -- Command the formation at birth, so the flight starts holding the spread rather
    -- than closing up during the ~1 s before FLIGHTGROUP reaches its Spawned state.
    -- CONTROLLABLE:SetOption (Moose_.lua:25749) is a thin wrapper on
    -- Controller:setOption and needs only a live group, exactly like the Route above.
    -- OnBanditSpawned sets the same value as the FLIGHTGROUP default, so the two
    -- cannot disagree.
    if formationOption then
      banditGroup:SetOption(AI.Option.Air.id.FORMATION, formationOption)
    end

    -- The spawn is deliberately SILENT - no message to the player. An F10
    -- confirmation would telegraph bearing, range and aspect before the fight has
    -- started, which is the opposite of what an ACM setup wants. Only the despawn
    -- talks. Nothing is lost: OnBanditSpawned already logs the spawn to dcs.log, and
    -- the aspect and the terrain raise go there too so a sortie can still be
    -- reconstructed afterwards.
    env.info(string.format(
      "[TRMA_A2A][ACM] Spawn (silent) for %s - %d x %s (%s), %s, %d kt, %d ft (roll %+d ft)%s",
      state.groupName, size, airframe, weaponSet.label, aspect, speedKnots,
      math.floor(UTILS.MetersToFeet(spawnCoord.y) + 0.5), varianceFt,
      raised and " - altitude raised to clear terrain" or ""))
  else
    -- Leave the state exactly as a despawn would: no bandit, no stamp. The deferred
    -- hook cannot arrive, so nothing is left to supersede.
    state.spawnId   = nil
    state.spawnTime = nil
    env.info(string.format(
      "[TRMA_A2A][ACM] SPAWN FAILED for %s - %d x %s (%s), template %s",
      state.groupName, size, airframe, weaponSet.label, template))
    MESSAGE:New("ACM: the bandit failed to spawn. Try again in a moment.", 10)
      :ToGroup(playerGroup)
  end
end

-- ----------------------------------------------------------------------------
-- BANDIT DESPAWN
-- ----------------------------------------------------------------------------
-- reason: optional message shown to the player. Pass nil for silent cleanup.
function TRMA_A2A.ACM:DespawnBandit(group, reason)
  if not group then return end

  local state = self.State[group:GetName()]
  if not state then return end

  local removed = false
  if state.bandit then
    -- CountAliveUnits, not GROUP:IsAlive(). IsAlive() (Moose_.lua:27602) resolves
    -- DCSGroup:getUnit(1) and returns THAT unit's isActive(), so for a 2- or 4-ship
    -- whose leader is already dead it is false while the rest of the formation is
    -- still airborne - and this despawn would skip them, orphaning live aggressors
    -- that ACM is about to forget. CountAliveUnits (Moose_.lua:27845) counts every
    -- surviving unit and returns 0 when the DCS group is gone.
    if state.bandit:CountAliveUnits() > 0 then
      -- GenerateEvent = false, always. A DEAD/CRASH event here would reach the
      -- FOX OnAfterMissileDestroyed handler registered in TRMA_MISC.lua.
      state.bandit:Destroy(false)
      removed = true
      env.info("[TRMA_A2A][ACM] Despawned bandit for " .. state.groupName)
    end
    -- The FLIGHTGROUP FSM owns three repeating timers (status, queue, checkzone)
    -- and is not told about a Destroy(false). Stop it or they run for the rest of
    -- the session. Delayed, because onbeforeStop refuses while the group is alive.
    if state.banditFG then state.banditFG:__Stop(2) end
  end

  -- Clearing the stamp is what makes an OnSpawnGroup hook that is still in flight
  -- (it is deferred 0.3 s) recognise itself as superseded and dispose of its own
  -- group, instead of writing a bandit back into state we have just emptied.
  state.spawnId   = nil
  state.spawnTime = nil
  state.bandit    = nil
  state.banditFG  = nil

  if removed and reason and group:IsAlive() then
    MESSAGE:New(reason, 10):ToGroup(group)
  end
end

-- ----------------------------------------------------------------------------
-- WATCHDOG
-- ----------------------------------------------------------------------------
-- Blue client slots only.
TRMA_A2A.ACM.ClientSet = SET_CLIENT:New():FilterCoalitions("blue"):FilterActive():FilterStart()

-- ONE scheduler for the whole mission, never one per client group. Four jobs:
--   1. reconcile the menu for every alive blue client (backstop for missed events)
--   2. client gone -> mark its menu dead and clean up its bandit
--   3. bandit outside the leash -> despawn it
--   4. bandit no longer alive -> clear the slot and tell the player
--
-- EVERY fallible step is wrapped in its own pcall. SCHEDULEDISPATCHER stops a
-- schedule permanently the moment its xpcall reports failure (Moose_.lua:6777-6779),
-- and this is the only cleanup path ACM has - one raised error and menus, orphan
-- removal, the leash and kill detection all stop for the rest of the mission, with
-- nothing but a single dcs.log line to show for it. The pcalls are per group, not one
-- around the whole function, so one bad group cannot skip all the others. Reconcile
-- can genuinely raise: MENU_INDEX:ParentPath (Moose_.lua:8458-8470) calls error() and
-- indexes self.Group[GroupName].Menus unguarded, so a group dying between our
-- IsAlive() check and addSubMenuForGroup is enough.
function TRMA_A2A.ACM:Watchdog()
  -- 1. Menu backstop.
  -- CountAliveUnits, not group:IsAlive(): IsAlive() (Moose_.lua:27602) probes the
  -- fixed slot DCSGroup:getUnit(1), so in a multi-slot flight whose lead has died it
  -- is false while the rest of the flight is still airborne - and this backstop would
  -- then never call Reconcile again, leaving the ACM menu gone for that group for the
  -- rest of the mission with nothing in the log. Most blue client groups here are
  -- multi-slot. The swap is strictly safer in one direction: IsAlive() == true implies
  -- CountAliveUnits() > 0, so it can only keep a group serviced for longer, never drop
  -- one earlier. client:IsAlive() above stays as it is - that is the player's own unit
  -- and unit-level liveness is the right question for it.
  self.ClientSet:ForEachClient(function(client)
    if client and client:IsAlive() then
      local group = client:GetGroup()
      if group and group:CountAliveUnits() > 0 and group:GetCoalition() == coalition.side.BLUE then
        local ok, err = pcall(function() TRMA_A2A.ACM:Reconcile(group) end)
        if not ok then
          env.info("[TRMA_A2A][ACM] Reconcile failed for " .. tostring(group:GetName()) ..
            ": " .. tostring(err))
        end
      end
    end
  end)

  local leashMeters = UTILS.NMToMeters(self.LeashNM)

  for groupName, state in pairs(self.State) do
    local ok, err = pcall(self.SweepOne, self, groupName, state, leashMeters)
    if not ok then
      env.info("[TRMA_A2A][ACM] State sweep failed for " .. tostring(groupName) ..
        ": " .. tostring(err))
    end
  end
end

-- One state entry's worth of watchdog work (jobs 2-4). Split out so it can be pcall'd
-- per group without a closure allocation per entry per tick.
function TRMA_A2A.ACM:SweepOne(groupName, state, leashMeters)
  -- Whole-flight liveness, for the same reason as job 1 above: with group:IsAlive()
  -- the death of the slot-1 pilot alone would take the "client left" branch, destroy
  -- the bandit out from under the surviving players mid-fight and mark their menu
  -- dead. A flight whose lead is dead is still flying and still owns its ACM state.
  local playerGroup  = GROUP:FindByName(groupName)
  local playerIsLive = (playerGroup ~= nil) and (playerGroup:CountAliveUnits() > 0)

  if not playerIsLive then
    -- 2. Client left or died. DCS has already dropped its F10 menu, so force a
    -- rebuild next time this group name comes alive, and take its bandit with it.
    state.menuAlive = false
    if state.bandit then
      -- Whole group, for the reason given in DespawnBandit: a formation whose leader
      -- is already dead must still be removed in full.
      if state.bandit:CountAliveUnits() > 0 then
        state.bandit:Destroy(false)
        env.info("[TRMA_A2A][ACM] Client " .. groupName .. " gone - bandit removed")
      end
      if state.banditFG then state.banditFG:__Stop(2) end
      state.spawnId   = nil
      state.spawnTime = nil
      state.bandit    = nil
      state.banditFG  = nil
    end

  elseif state.bandit then
    -- Grace window. A just-spawned group is not reliably IsAlive() yet, and the
    -- OnSpawnGroup hook has not even run for the first 0.3 s, so without this a
    -- player could be told "bandit is down" seconds after asking for one.
    local settled = (state.spawnTime == nil) or
                    ((timer.getTime() - state.spawnTime) > self.SpawnGraceSeconds)

    -- Whole-group liveness drives BOTH the kill call and the leash. GROUP:IsAlive()
    -- is unit 1 only, so with a 2- or 4-ship it goes false the moment the leader
    -- dies: job 4 would call "bandit is down", clear the state, and leave three live
    -- aggressors on the player with no despawn path and no leash. CountAliveUnits
    -- reaches 0 only when every unit has gone. The leash still works for a decimated
    -- formation, because GROUP:GetCoordinate resolves GetUnit(1) ->
    -- DCSGroup:getUnits()[1], which is the first SURVIVING unit rather than a fixed
    -- slot.
    local aliveUnits = state.bandit:CountAliveUnits()

    if settled and aliveUnits == 0 then
      -- 4. Player (or the ground) got it.
      if state.banditFG then state.banditFG:__Stop(2) end
      state.spawnId   = nil
      state.spawnTime = nil
      state.bandit    = nil
      state.banditFG  = nil
      MESSAGE:New("ACM: bandit is down. Knock it off.", 10):ToGroup(playerGroup)

    elseif aliveUnits > 0 then
      -- 3. Leash.
      local playerCoord = playerGroup:GetCoordinate()
      local banditCoord = state.bandit:GetCoordinate()
      if playerCoord and banditCoord and playerCoord:Get2DDistance(banditCoord) > leashMeters then
        self:DespawnBandit(playerGroup, string.format(
          "ACM: bandit is more than %d NM out and has been despawned.", self.LeashNM))
      end
    end
  end
end

TRMA_A2A.ACM.Scheduler = SCHEDULER:New(nil, function() TRMA_A2A.ACM:Watchdog() end, {},
  TRMA_A2A.ACM.WatchdogSeconds, TRMA_A2A.ACM.WatchdogSeconds)

-- ----------------------------------------------------------------------------
-- PLAYER ENTER AIRCRAFT
-- ----------------------------------------------------------------------------
-- A player who slots in gets a fresh, empty DCS F10 menu, so whatever MENU_INDEX
-- still believes about that group name is stale. Mark the menu dead and let
-- Reconcile rebuild it. The watchdog is the backstop if this event is missed.
TRMA_A2A.ACM.EventHandler = EVENTHANDLER:New()

function TRMA_A2A.ACM.EventHandler:OnEventPlayerEnterAircraft(EventData)
  if not EventData then return end

  -- This event also fires for units that are not player aircraft, so guard hard.
  local group = EventData.IniGroup
  if not group and EventData.IniUnit then
    group = EventData.IniUnit:GetGroup()
  end
  if not group then return end
  if group:GetCoalition() ~= coalition.side.BLUE then return end

  -- INVALIDATE FIRST, then check liveness. Invalidation needs only the group name,
  -- and it must happen even when the group is not alive yet at event time: DCS has
  -- already dropped this slot's radio menu, so if we returned early and left
  -- menuAlive true, Reconcile would no-op here AND in the watchdog backstop, and
  -- ACM would be silently unreachable for that slot for the rest of the mission.
  -- The build below is what genuinely needs a live group.
  local state = TRMA_A2A.ACM.State[group:GetName()]
  if state then state.menuAlive = false end

  if not group:IsAlive() then return end

  TRMA_A2A.ACM:Reconcile(group)
end

TRMA_A2A.ACM.EventHandler:HandleEvent(EVENTS.PlayerEnterAircraft)

env.info("[TRMA_A2A][ACM] ACM mode loaded")

-- ============================================================================
-- RANGE CLASS LOGIC (The Engine)
-- ============================================================================
TRMA_A2A.Range = {}
TRMA_A2A.Range.__index = TRMA_A2A.Range

function TRMA_A2A.Range:New(rangeName, config, parentMenu)
  local self = setmetatable({}, TRMA_A2A.Range)
  
  -- Range Identity
  self.name       = rangeName
  self.mode       = "BVR" 
  self.isRandom   = false
  self.parentMenu = parentMenu

  -- Zone Setup
  self.zoneEngage = ZONE:New(config.engageZone) 
  self.capZones = {}
  for _, zData in ipairs(config.capZones) do
    table.insert(self.capZones, {
      name = zData.name,
      zone = ZONE:New(zData.zoneName)
    })
  end

  -- Default Group Templates
  self.capGroups = {
    { airframe = TRMA_A2A.Airframes[3], size = 2, capZoneID = 1 }, -- 2x SU30
    { airframe = TRMA_A2A.Airframes[1], size = 2, capZoneID = 2 }, -- 2x MIG23
    { airframe = TRMA_A2A.Airframes[2], size = 2, capZoneID = 1 }  -- 2x MIG29A
  }

  self:BuildMenu()
  env.info("[TRMA_A2A] Loaded Range: " .. self.name)
  return self
end

function TRMA_A2A.Range:SpawnFlight(airframe, size, capZoneID)
  local range = self
  local currentCapZone = self.capZones[capZoneID]
  local zoneObj = currentCapZone.zone

  -- 1. Setup Parameters
  if self.isRandom then 
    airframe = TRMA_A2A.Airframes[math.random(#TRMA_A2A.Airframes)]
    size = math.random(1, 4)
  end
  
  local template  = string.format("Drone_Aggressor_%s", airframe)
  if self.mode == "BFM" then template = template .. "_BFM" end

  -- 2. Define the "Drone Intelligence" (The callback)
  local function OnSpawnGroup(group)
    local drones = FLIGHTGROUP:New(group)
    local alt    = math.random(20000, 30000)
    
    -- Mission: Fly a racetrack in the patrol zone
    local patrol = AUFTRAG:NewORBIT_RACETRACK(zoneObj:GetRandomCoordinate(), alt, 350, 110)    

    -- "Radar" Setup: Tell the drone which zones to monitor
    drones:SetCheckZones(SET_ZONE:New():AddZone(range.zoneEngage):AddZone(zoneObj))
    drones:AddMission(patrol)

    -- EVENT: Entering the Range (Weapons Hot)
    function drones:OnAfterEnterZone(From, Event, To, zone)
      if zone == zoneObj or zone == range.zoneEngage then
        
        if debug then 
          local msg = drones:GetName() .. ": Weapons HOT (Entering " .. zone:GetName() .. ")"
          MESSAGE:New(msg, 5):ToAll() 
          env.info(msg)
        end
        
        -- Engagement Logic: BVR = 100nm, BFM = 20nm
        local rangeDist = (range.mode == "BVR") and 185 or 40
        drones:SetEngageDetectedOn(rangeDist, {"Air"}, range.zoneEngage)
      end
    end

    -- EVENT: Leaving the Range (The Leash)
    function drones:OnAfterLeaveZone(From, Event, To, zone)
      if zone == range.zoneEngage then
        local msg = drones:GetName() .. ": Leaving Range. Disengaging."
        env.info(msg)
        if debug then 
          MESSAGE:New(msg, 10):ToAll()
        end

        drones:SetEngageDetectedOff()
        group:ClearTasks() -- Force-break the AI dogfight
        drones:StartMission(patrol)
      end
    end
  end

  -- 3. Execute Spawn
  local alias = template .. "-" .. math.random(1000)
  SPAWN:NewWithAlias(template, alias)
    :InitLimit(10, 0)
    :InitGrouping(size)
    :InitRandomizeCallsign()
    :InitSkill("Good")
    :OnSpawnGroup(OnSpawnGroup)
    :SpawnInZone(zoneObj, true, 10000, 15000)
end

-- ============================================================================
-- RADIO MENU BUILDER
-- ============================================================================
function TRMA_A2A.Range:BuildMenu()
  if self.a2aMenu then self.a2aMenu:Remove() end
  self.a2aMenu = MENU_MISSION:New(self.name .. " Adversaries", self.parentMenu)

  -- Submenu: Mode Switch
  local mMode = MENU_MISSION:New("Change Mode: " .. self.mode, self.a2aMenu)
  for _, mType in ipairs({"BVR", "BFM"}) do
    local icon = (mType == self.mode) and " [ACTIVE]" or ""
    MENU_MISSION_COMMAND:New(mType .. icon, mMode, function() self.mode = mType; self:BuildMenu() end)
  end

  -- Submenu: Quick Spawns
  for i, cfg in ipairs(self.capGroups) do
    local locName = self.capZones[cfg.capZoneID].name 
    local label = string.format("Spawn Group %d: %d-ship %s (%s)", i, cfg.size, cfg.airframe, locName)
    MENU_MISSION_COMMAND:New(label, self.a2aMenu, function() self:SpawnFlight(cfg.airframe, cfg.size, cfg.capZoneID) end)
  end

  -- Submenu: Deep Config
  local mCfg = MENU_MISSION:New("Edit Group Compositions", self.a2aMenu)
  for i, cfg in ipairs(self.capGroups) do
    local mGrp = MENU_MISSION:New("Group " .. i, mCfg)

    -- Edit Size
    local mSize = MENU_MISSION:New("Set Size", mGrp)
    for s = 1, 4 do
      MENU_MISSION_COMMAND:New(s .. "-ship", mSize, function() cfg.size = s; self:BuildMenu() end)
    end

    -- Edit Airframe
    local mAir = MENU_MISSION:New("Set Airframe", mGrp)
    for _, name in ipairs(TRMA_A2A.Airframes) do
      MENU_MISSION_COMMAND:New(name, mAir, function() cfg.airframe = name; self:BuildMenu() end)
    end
  end
end