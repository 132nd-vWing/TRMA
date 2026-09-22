_SETTINGS:SetPlayerMenuOff()
_SETTINGS:SetImperial()

---important: the MessageToAll function was removed from Moose, we add it back here, else all other scripts will break.
function MessageToAll( MsgText, MsgTime, MsgName )
  -- trace.f()
  MESSAGE:New( MsgText, MsgTime, "Message" ):ToCoalition( coalition.side.RED ):ToCoalition( coalition.side.BLUE )
end





awacs_root_menu = MENU_MISSION:New("AWACS and TANKER Control")
range_root_menu = MENU_MISSION:New("RANGE Control")
--RANGE.MenuF10Root=MENU_MISSION:New("Basic Ranges",range_root_menu)
--range_root_menu1_6 = MENU_MISSION:New("RANGES 1-6",range_root_menu)
range_root_menu7_12 = MENU_MISSION:New("RANGES 7-12",range_root_menu)
range_root_menu13_18 = MENU_MISSION:New("RANGES 13-18",range_root_menu)
range_root_menu19_24 = MENU_MISSION:New("RANGES 19-24",range_root_menu)
range_root_menu31_34 = MENU_MISSION:New("RANGES 31-34",range_root_menu)
--moa_root_menu = MENU_MISSION:New("MOAs")

awacs_menu = MENU_MISSION:New("AWACS Control", awacs_root_menu )
tanker_menu = MENU_MISSION:New("TANKER Control", awacs_root_menu )
--elint_menu = MENU_MISSION:New("ELINT Control", awacs_root_menu )
--elint_menu_elint1 = MENU_MISSION:New("ELINT RANGE 2", elint_menu )
--range_root_menu_misc = MENU_MISSION:New("Miscellaneous ")

--- FOX script (replaces Missiletrainer)
fox=FOX:New()
fox:SetExplosionDistance(20)
fox:SetDisableF10Menu(true)
fox:SetDefaultLaunchAlerts(false)

-- Custom Fox handler for after missile destoryed
function fox:OnAfterMissileDestroyed(From, Event, To, missile)
  if missile.targetPlayer then
    trigger.action.outSoundForGroup(missile.targetPlayer.group:GetID(), '132nd_Sounds/missile_kill.ogg')
  end
end

fox:Start()
---/Fox


-- ============================================================================
-- DATALINK ROSTER (Link 16 STN / A-10C SADL TN) - ver 1.0
-- ============================================================================
-- Purpose: a player opens their own F10 menu, presses one command, and gets a
--          list of the Link 16 STNs (and A-10C SADL track numbers) of every
--          aircraft on their coalition that currently has a human in it.
--          Visible to the presser's flight (their DCS group), not just to
--          them: DCS radio menus and text output are per-group, so a
--          multi-seat client group shares both.
-- Instructions for Mission Makers:
-- 1. No ME work required beyond what is already there. The track numbers are
--    read out of the unit properties (AddPropAircraft.STN_L16 / .SADL_TN) that
--    the ME writes into `mission`, snapshotted ONCE at load.
-- 2. If you change an STN in the ME, the change is picked up on the next
--    mission load - there is no runtime re-read.
-- 3. The menu is per-group (MENU_GROUP) under its own top-level "Datalink"
--    entry. It is deliberately NOT nested under range_root_menu / awacs_root_menu
--    above: those are MENU_MISSION roots, shared by every client on the server.
-- 4. Both coalitions get the menu. A red client simply sees the red roster.
-- 5. State is in memory only and does not survive a mission restart.
-- ============================================================================

TRMA_L16 = {}

-- Snapshot of the ME-authored datalink properties, keyed by UNIT name:
--   DB[unitName] = { tn = "01125", kind = "STN"|"SADL", vcl = "RN", vcn = "11" }
-- tn is stored VERBATIM as the ME string. STN_L16 is 5-digit OCTAL and is what
-- the pilot types into the DED/UFC, so it must never be converted to decimal.
TRMA_L16.DB = {}

TRMA_L16.State = {}          -- per client GROUP name: { rootMenu, menuAlive }

TRMA_L16.MaxLines       = 40 -- cap on the flight listing, in lines
TRMA_L16.MaxNoDatalink  = 12 -- cap on the trailing "No datalink:" line, in names
TRMA_L16.ReportSeconds  = 30 -- how long the report stays on the player's screen
TRMA_L16.SweepSeconds   = 30 -- menu backstop period
TRMA_L16.SweepOffset    = 15 -- first tick offset, to stay off ACM's frame
TRMA_L16.Debug          = false -- verbose env.info() logging

TRMA_L16.CoalitionNames = {
  [coalition.side.RED]     = "RED",
  [coalition.side.BLUE]    = "BLUE",
  [coalition.side.NEUTRAL] = "NEUTRAL"
}

-- ----------------------------------------------------------------------------
-- LOAD-TIME SNAPSHOT
-- ----------------------------------------------------------------------------
-- _DATABASE:_RegisterTemplates() runs eagerly inside DATABASE:New() at slot [1],
-- with env.getValueDictByKey already applied to the names, so by the time this
-- file runs at slot [4] every unit template - client slots included - is present.
-- This mission has no dynamic spawning of client aircraft, so a single pass is
-- a complete answer for the whole mission.
--
-- Only the two scalar strings are kept. A reference into the template table would
-- alias data MOOSE mutates when it spawns from that template.
local function buildDatalinkSnapshot()
  local db, nSTN, nSADL = {}, 0, 0

  local templates = _DATABASE and _DATABASE.Templates and _DATABASE.Templates.Units
  if not templates then
    return db, nSTN, nSADL
  end

  for unitName, entry in pairs(templates) do
    local template = entry and entry.Template
    local props    = template and template.AddPropAircraft
    -- Many client slots (F-14BU, OH58D, ...) carry no AddPropAircraft at all.
    -- That is normal, not an error: they simply have no datalink to report.
    if props then
      local stn  = props.STN_L16
      local sadl = props.SADL_TN
      local tn, kind

      if stn ~= nil and stn ~= "" then
        tn, kind = tostring(stn), "STN"
        if sadl ~= nil and sadl ~= "" then
          env.info(string.format(
            "[TRMA_L16] %s carries both STN_L16 (%s) and SADL_TN (%s) - reporting STN_L16",
            tostring(unitName), tostring(stn), tostring(sadl)))
        end
      elseif sadl ~= nil and sadl ~= "" then
        tn, kind = tostring(sadl), "SADL"
      end

      if tn then
        db[tostring(unitName)] = {
          tn   = tn,
          kind = kind,
          vcl  = props.VoiceCallsignLabel  and tostring(props.VoiceCallsignLabel)  or nil,
          vcn  = props.VoiceCallsignNumber and tostring(props.VoiceCallsignNumber) or nil
        }
        if kind == "STN" then nSTN = nSTN + 1 else nSADL = nSADL + 1 end
      end
    end
  end

  return db, nSTN, nSADL
end

-- One pcall around the WHOLE walk. An uncaught error at this point in the file
-- kills the rest of slot [4], which would take MessageToAll, every MENU_MISSION
-- root and the FOX setup above down with it. An empty DB degrades to "no
-- datalink" for everyone, which is survivable; a dead slot [4] is not.
do
  local ok, db, nSTN, nSADL = pcall(buildDatalinkSnapshot)
  if ok and type(db) == "table" then
    TRMA_L16.DB = db
    env.info(string.format("[TRMA_L16] Datalink snapshot: %d units (%d STN, %d SADL)",
      nSTN + nSADL, nSTN, nSADL))
  else
    TRMA_L16.DB = {}
    env.info("[TRMA_L16] Datalink snapshot FAILED, reporting no datalink for all units: "
      .. tostring(db))
  end
end

-- ----------------------------------------------------------------------------
-- REPORT FORMATTER (pure)
-- ----------------------------------------------------------------------------
-- No DCS or MOOSE API below this line until BuildRows, so this is testable under
-- plain lua5.1. Ordering is ALWAYS established by an explicit table.sort with a
-- total order; pairs() is never used for output, so the same rows in a different
-- array order produce a byte-identical string.
local function rowLess(a, b)
  local af, bf = tostring(a.flight or ""), tostring(b.flight or "")
  if af ~= bf then return af < bf end
  local au, bu = tostring(a.unit or ""), tostring(b.unit or "")
  if au ~= bu then return au < bu end
  local ap, bp = tostring(a.player or ""), tostring(b.player or "")
  if ap ~= bp then return ap < bp end
  return tostring(a.tn or "") < tostring(b.tn or "")
end

local function noLinkLess(a, b)
  local ap, bp = tostring(a.player or ""), tostring(b.player or "")
  if ap ~= bp then return ap < bp end
  return tostring(a.unit or "") < tostring(b.unit or "")
end

-- rows = { { flight, unit, player, type, tn, kind, vcl, vcn }, ... }; tn may be nil.
function TRMA_L16:FormatReport(coalitionName, rows)
  rows = rows or {}

  local out = {
    string.format("LINK 16 / SADL - PLAYERS AIRBORNE (%s)", tostring(coalitionName)),
    ""
  }

  if #rows == 0 then
    out[#out + 1] = "No players airborne on your coalition."
    return table.concat(out, "\n")
  end

  -- Split: a row without a track number is not an error, it is a slot with no
  -- datalink (or one the ME never gave an STN). It is reported, just not listed
  -- among the flights.
  local linked, unlinked = {}, {}
  for i = 1, #rows do
    local r = rows[i]
    if r then
      if r.tn ~= nil and r.tn ~= "" then
        linked[#linked + 1] = r
      else
        unlinked[#unlinked + 1] = r
      end
    end
  end

  table.sort(linked, rowLess)
  table.sort(unlinked, noLinkLess)

  -- Build the flight listing as tagged entries first, so the line cap can be
  -- applied without losing track of how many aircraft were actually shown.
  local listing = {}
  local i = 1
  while i <= #linked do
    local fkey = tostring(linked[i].flight or "")
    listing[#listing + 1] = {
      text = string.format("%s (%s)", fkey, tostring(linked[i].type or "?"))
    }
    while i <= #linked and tostring(linked[i].flight or "") == fkey do
      local r  = linked[i]
      local tn = tostring(r.tn)
      local isSadl = (r.kind == "SADL")
      if isSadl then tn = tn .. "*" end

      local callsign = tostring(r.vcl or "") .. tostring(r.vcn or "")
      local parts = { tn }
      if callsign ~= "" then parts[#parts + 1] = callsign end
      parts[#parts + 1] = tostring(r.player or "?")

      listing[#listing + 1] = {
        text  = "  " .. table.concat(parts, "  "),
        isRow = true,
        sadl  = isSadl
      }
      i = i + 1
    end
    listing[#listing + 1] = { text = "" }   -- blank line between flights
  end

  local kept, truncated = listing, false
  if #listing > self.MaxLines then
    truncated = true
    kept = {}
    for k = 1, self.MaxLines do kept[k] = listing[k] end
    while #kept > 0 and kept[#kept].text == "" do table.remove(kept) end
  end

  local shownRows, sadlShown = 0, false
  for k = 1, #kept do
    if kept[k].isRow then shownRows = shownRows + 1 end
    if kept[k].sadl  then sadlShown = true end
    out[#out + 1] = kept[k].text
  end

  if truncated and (#linked - shownRows) > 0 then
    out[#out + 1] = string.format("... +%d more", #linked - shownRows)
  end

  -- The legend only earns its line if a "*" is actually visible above it.
  if sadlShown then
    if out[#out] ~= "" then out[#out + 1] = "" end
    out[#out + 1] = "* = SADL"
  end

  if #unlinked > 0 then
    local shown = #unlinked
    if shown > self.MaxNoDatalink then shown = self.MaxNoDatalink end
    local names = {}
    for k = 1, shown do
      names[#names + 1] = string.format("%s (%s)",
        tostring(unlinked[k].player or "?"), tostring(unlinked[k].type or "?"))
    end
    local line = "No datalink: " .. table.concat(names, ", ")
    if #unlinked > shown then
      line = line .. string.format(", ... +%d more", #unlinked - shown)
    end
    out[#out + 1] = line
  end

  while #out > 0 and out[#out] == "" do table.remove(out) end

  return table.concat(out, "\n")
end

-- ----------------------------------------------------------------------------
-- ROSTER COLLECTOR
-- ----------------------------------------------------------------------------
-- coalition.getPlayers(side) returns the DCS Unit objects that currently have a
-- human in them - exactly the set we want, and it needs no MOOSE bookkeeping.
-- Every per-unit read is pcall'd on its own: a player disconnecting mid-loop can
-- make isExist()/getName() raise, and that must cost one row, not the roster.
function TRMA_L16:BuildRows(side)
  local rows = {}

  local ok, players = pcall(coalition.getPlayers, side)
  if not ok or type(players) ~= "table" then
    env.info("[TRMA_L16] coalition.getPlayers failed for side " .. tostring(side)
      .. ": " .. tostring(players))
    return rows
  end

  for i = 1, #players do
    local u = players[i]
    local okUnit, err = pcall(function()
      if not (u and u:isExist()) then return end

      local playerName = u:getPlayerName()
      if not playerName then return end       -- AI in a client slot: not a player

      local unitName = u:getName()
      local typeName = u:getTypeName()

      local grp    = u:getGroup()
      local flight = (grp and grp:getName()) or unitName

      -- A miss here is a legitimate "no datalink" row, not a failure: plenty of
      -- client slots in this mission carry no AddPropAircraft at all.
      local rec = self.DB[tostring(unitName)]

      rows[#rows + 1] = {
        flight = tostring(flight or "?"),
        unit   = tostring(unitName or "?"),
        player = tostring(playerName),
        type   = tostring(typeName or "?"),
        tn     = rec and rec.tn   or nil,
        kind   = rec and rec.kind or nil,
        vcl    = rec and rec.vcl  or nil,
        vcn    = rec and rec.vcn  or nil
      }
    end)
    if not okUnit then
      env.info("[TRMA_L16] Skipped a player unit while building the roster: " .. tostring(err))
    end
  end

  return rows
end

-- Own coalition, own group. MessageToAll, redefined at the top of this very
-- file, goes to RED *and* BLUE; using it here would put every player's
-- callsign and STN on the other coalition's screen. MESSAGE:ToGroup is the
-- only correct sink, though a multi-seat client group shares the report
-- with itself (never with another group or coalition).
function TRMA_L16:ShowReport(group)
  if not group or not group:IsAlive() then return end

  local side = group:GetCoalition()
  local rows = self:BuildRows(side)
  local text = self:FormatReport(self.CoalitionNames[side] or "UNKNOWN", rows)

  if TRMA_L16.Debug then
    env.info(string.format("[TRMA_L16] Report for %s: %d row(s)",
      tostring(group:GetName()), #rows))
  end

  MESSAGE:New(text, self.ReportSeconds):ToGroup(group)
end

-- ----------------------------------------------------------------------------
-- PER-GROUP MENU LIFECYCLE
-- ----------------------------------------------------------------------------
function TRMA_L16:GetState(group)
  local groupName = group:GetName()
  local state = self.State[groupName]
  if not state then
    state = { groupName = groupName, rootMenu = nil, menuAlive = false }
    self.State[groupName] = state
  end
  return state
end

-- Precondition: group:IsAlive().
-- MENU_GROUP:New consults MENU_INDEX:HasGroupMenu first and, if an entry already
-- exists for this path, RETURNS THE CACHED OBJECT without adding anything to the
-- DCS menu. MENU_INDEX is keyed by group name, which is identical after a player
-- leaves and re-slots - so a naive rebuild would produce no F10 entry at all.
-- Removing our own root first, while the group is still alive, is the whole
-- reason this survives a re-slot; keeping the rootMenu reference is what makes
-- the GroupMenu==self identity check inside MENU_GROUP:Remove hold.
-- NOTE: MENU_GROUP / MENU_GROUP_COMMAND take the GROUP as the FIRST argument.
-- That is not the case for the MENU_MISSION calls at the top of this file.
function TRMA_L16:RebuildMenu(group)
  if not group or not group:IsAlive() then return end

  local state = self:GetState(group)

  if state.rootMenu then state.rootMenu:Remove() end
  state.rootMenu = MENU_GROUP:New(group, "Datalink")

  MENU_GROUP_COMMAND:New(group, "Show Link 16 / SADL STNs", state.rootMenu, function()
    TRMA_L16:ShowReport(group)
  end)

  state.menuAlive = true
end

-- The menu is stateless - one command, no selections - so there is nothing to
-- refresh. Rebuild only when it is known to be gone.
function TRMA_L16:Reconcile(group)
  if not group or not group:IsAlive() then return end

  local state = self.State[group:GetName()]
  if not state then
    self:GetState(group)
    self:RebuildMenu(group)
    return
  end

  if state.menuAlive == false then
    self:RebuildMenu(group)
  end
end

-- A player who slots in gets a fresh, empty DCS F10 menu, so whatever MENU_INDEX
-- still believes about that group name is stale. No coalition filter: a red
-- client gets the menu and an honest red roster.
TRMA_L16.EventHandler = EVENTHANDLER:New()

function TRMA_L16.EventHandler:OnEventPlayerEnterAircraft(EventData)
  if not EventData then return end

  local group = EventData.IniGroup
  if not group and EventData.IniUnit then
    group = EventData.IniUnit:GetGroup()
  end
  if not group then return end

  -- INVALIDATE FIRST, then check liveness. Invalidation needs only the group
  -- name, and it must happen even when the group is not alive yet at event time:
  -- DCS has already dropped this slot's radio menu, so leaving menuAlive true
  -- would make both Reconcile and the sweep below no-op, and the Datalink menu
  -- would be silently unreachable for that slot for the rest of the mission.
  local state = TRMA_L16.State[group:GetName()]
  if state then state.menuAlive = false end

  if not group:IsAlive() then return end

  TRMA_L16:Reconcile(group)
end

TRMA_L16.EventHandler:HandleEvent(EVENTS.PlayerEnterAircraft)

-- ----------------------------------------------------------------------------
-- MENU BACKSTOP
-- ----------------------------------------------------------------------------
-- All active clients, both coalitions - no FilterCoalitions.
TRMA_L16.ClientSet = SET_CLIENT:New():FilterActive():FilterStart()

-- ONE scheduler for the whole mission, never one per player. Two jobs:
--   1. reconcile the menu for every alive client (backstop for a missed event)
--   2. mark the menu dead for any state entry whose group is no longer alive
--
-- EVERY fallible step gets its OWN pcall, per group, not one around the tick:
-- SCHEDULEDISPATCHER stops a schedule permanently the moment its xpcall reports
-- failure (Moose_.lua:6777-6779), and this is the only recovery path the menu
-- has. Reconcile can genuinely raise - MENU_INDEX:ParentPath (Moose_.lua:8464)
-- calls error() and indexes self.Group[GroupName].Menus unguarded, so a group
-- dying between the IsAlive() check and the menu build is enough. SET_BASE:ForEach
-- is itself unprotected, hence the outer pcall as well; the state sweep still
-- runs if the set iteration blows up.
function TRMA_L16:Sweep()
  local okSet, errSet = pcall(function()
    TRMA_L16.ClientSet:ForEachClient(function(client)
      if client and client:IsAlive() then
        local group = client:GetGroup()
        if group and group:IsAlive() then
          local ok, err = pcall(TRMA_L16.Reconcile, TRMA_L16, group)
          if not ok then
            env.info("[TRMA_L16] Reconcile failed for " .. tostring(group:GetName())
              .. ": " .. tostring(err))
          end
        end
      end
    end)
  end)
  if not okSet then
    env.info("[TRMA_L16] Client set iteration failed: " .. tostring(errSet))
  end

  for groupName, state in pairs(self.State) do
    local ok, err = pcall(function()
      local group = GROUP:FindByName(groupName)
      if not group or not group:IsAlive() then
        -- Client left or died: DCS has already dropped its F10 menu, so force a
        -- rebuild the next time this group name comes alive.
        state.menuAlive = false
      end
    end)
    if not ok then
      env.info("[TRMA_L16] State sweep failed for " .. tostring(groupName)
        .. ": " .. tostring(err))
    end
  end
end

TRMA_L16.Scheduler = SCHEDULER:New(nil, function() TRMA_L16:Sweep() end, {},
  TRMA_L16.SweepOffset, TRMA_L16.SweepSeconds)

env.info("[TRMA_L16] Datalink roster loaded")
