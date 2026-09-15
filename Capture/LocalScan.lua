-- =============================================================================
-- Capture/LocalScan.lua
--
-- Shared production capture helpers and slash-command routing.
--
-- Slash aliases: /chron, /chronicle, /clog  (all three route here)
-- =============================================================================

local Log = Chronicle.Logger
local Capture = Chronicle.Capture

-- ---------------------------------------------------------------------------
-- Guild
-- ---------------------------------------------------------------------------

--- Read guild info for a unit.
-- @param unit  string  "player", "target", "raid5", etc.
-- @return table or nil  { name, rank_name, rank_index }
function Capture.ScanGuild(unit)
    unit = unit or "player"
    local guildName, rankName, rankIndex = GetGuildInfo(unit)
    if not guildName then return nil end
    return {
        name       = guildName,
        rank_name  = rankName or "",
        rank_index = rankIndex or 0,
    }
end

-- ---------------------------------------------------------------------------
-- Pet
-- ---------------------------------------------------------------------------

--- Derive the pet unit token from a player unit token.
-- "player" -> "pet",  "raid5" -> "raid5pet",  "party2" -> "party2pet"
local function derivePetUnit(unit)
    if unit == "player" then return "pet" end
    local raidIndex = unit:match("^raid(%d+)$")
    if raidIndex then return "raidpet" .. raidIndex end
    local partyIndex = unit:match("^party(%d+)$")
    if partyIndex then return "partypet" .. partyIndex end
    return unit .. "pet"
end

--- Read pet info for a unit.
-- @param unit  string  "player", "target", "raid5", etc.
-- @return table or nil  { name, guid, family }
function Capture.ScanPet(unit)
    unit = unit or "player"
    local petUnit = derivePetUnit(unit)
    if not UnitExists(petUnit) then return nil end
    return {
        name   = UnitName(petUnit) or "Unknown",
        guid   = UnitGUID(petUnit) or "",
        family = UnitCreatureFamily(petUnit) or "",
    }
end

-- ---------------------------------------------------------------------------
-- Honor / PvP  (local player only -- can't inspect others' honor)
-- ---------------------------------------------------------------------------

--- Read PvP / honor stats for the local player.
-- @return table  { lifetime_hk, highest_rank, honor_currency, session_hk }
function Capture.ScanHonor()
    local lifetimeHK, highestRank = 0, 0
    if type(GetPVPLifetimeStats) == "function" then
        lifetimeHK, _, highestRank = GetPVPLifetimeStats()
    end

    local honorCurrency = 0
    if type(GetHonorCurrency) == "function" then
        honorCurrency = GetHonorCurrency()
    end

    local sessionHK = 0
    if type(GetPVPSessionStats) == "function" then
        sessionHK = GetPVPSessionStats()
    end

    return {
        lifetime_hk    = lifetimeHK or 0,
        highest_rank   = highestRank or 0,
        honor_currency = honorCurrency or 0,
        session_hk     = sessionHK or 0,
    }
end

-- ---------------------------------------------------------------------------
-- Instance snapshot
-- ---------------------------------------------------------------------------

local function captureInstance()
    if type(GetInstanceInfo) ~= "function" then return nil end
    local name, instType, diffIdx, diffName, maxPlayers, playerDiff, isDynamic, mapId =
        GetInstanceInfo()
    if not name or name == "" then return nil end
    return {
        name             = name,
        instance_type    = instType or "",
        difficulty_index = diffIdx or 0,
        difficulty_name  = diffName or "",
        max_players      = maxPlayers or 0,
        player_difficulty = playerDiff or 0,
        is_dynamic       = isDynamic and true or false,
        map_id           = mapId or 0,
    }
end

-- ---------------------------------------------------------------------------
-- Full CI assemblers
-- ---------------------------------------------------------------------------

--- Build a complete Combatant Info struct for the local player.
-- @return table  The CI struct ready for serialization
function Capture.ScanLocal()
    local ci = {
        player = {
            guid   = UnitGUID("player") or "",
            name   = UnitName("player") or "Unknown",
            realm  = GetRealmName() or "",
            class  = select(2, UnitClass("player")) or "",
            race   = select(2, UnitRace("player")) or "",
            gender = UnitSex("player") or 0,
            level  = UnitLevel("player") or 0,
        },
        guild       = Capture.ScanGuild("player"),
        pet         = Capture.ScanPet("player"),
        gear        = Capture.ScanGear("player"),
        talents     = Capture.ScanTalents("player", false),
        honor       = Capture.ScanHonor(),
        instance    = captureInstance(),
        captured_at = time(),
        source      = "local",
    }
    return ci
end

--- Build a CI struct for an inspected unit.
-- Call only after INSPECT_READY has fired for this unit.
-- @param unit  string  "target", "raid5", etc.
-- @return table  The CI struct
function Capture.ScanUnit(unit, isInspect)
    unit = unit or "target"
    isInspect = (isInspect ~= false)  -- default true for non-player units

    local ci = {
        player = {
            guid   = UnitGUID(unit) or "",
            name   = UnitName(unit) or "Unknown",
            realm  = GetRealmName() or "",
            class  = select(2, UnitClass(unit)) or "",
            race   = select(2, UnitRace(unit)) or "",
            gender = UnitSex(unit) or 0,
            level  = UnitLevel(unit) or 0,
        },
        guild       = Capture.ScanGuild(unit),
        pet         = Capture.ScanPet(unit),
        gear        = Capture.ScanGear(unit),
        talents     = nil,
        -- Honor: only readable for "player"
        honor       = nil,
        instance    = captureInstance(),
        captured_at = time(),
        source      = "inspect",
    }

    -- Peer talents are intentionally unsupported.

    return ci
end

-- ---------------------------------------------------------------------------
-- Slash command handler
--
-- Routing:
--   /clog log <sub>               ->  logger settings
--   /clog relay <sub>             ->  relay status and controls
--   /chron help                    ->  print help
-- ---------------------------------------------------------------------------

--- Parse a slash message into tokens.
-- "/chron inspect gear target" -> {"inspect", "gear", "target"}
local function tokenize(msg)
    local tokens = {}
    for token in (msg or ""):gmatch("%S+") do
        tokens[#tokens + 1] = token:lower()
    end
    return tokens
end

-- ---------------------------------------------------------------------------
-- Main slash handler
-- ---------------------------------------------------------------------------

local function slashHandler(msg)
    local tokens = tokenize(msg)
    local cmd = tokens[1]

    if cmd == "help" then
        Log:Info("%s commands:", Chronicle.DISPLAY_NAME or "Chronicle Companion")
        Log:Info("  /clog             -- open settings")
        Log:Info("  /clog relay       -- relay status and controls")
        Log:Info("  /clog log         -- logger settings")
        Log:Info("Type a command alone for its sub-help.")
        return
    end

    if not cmd or cmd == "" then
        Chronicle.ToggleSettingsUI()
        return
    end


    -- ---- /clog log [set-lvl|set-window] ----
    if cmd == "log" then
        local sub = tokens[2]

        -- No sub-command: dump current state + sub-help
        if not sub then
            local frame = Log:GetChatFrame()
            local frameName = (frame and frame:GetName()) or "DEFAULT_CHAT_FRAME"
            Log:Info("Log level: %s  |  Output window: %s", Log:GetLevel(), frameName)
            Log:Info("  /clog log set-lvl <error|warn|info|debug>")
            Log:Info("  /clog log set-window <1-10|name>")
            return
        end

        if sub == "set-lvl" then
            local level = tokens[3]
            if level then
                Log:SetLevel(level)
                -- Persist to SavedVariables
                if Chronicle.Config then
                    Chronicle.Config:Set("log_level", level:lower())
                end
            else
                Log:Info("Current log level: %s", Log:GetLevel())
                Log:Info("Usage: /clog log set-lvl <error|warn|info|debug>")
            end
            return
        end

        if sub == "set-window" then
            local target = tokens[3]
            if not target then
                Log:Info("Usage: /clog log set-window <1-10|name>")
                Log:Info("  e.g. /clog log set-window 2       -- ChatFrame2")
                Log:Info("  e.g. /clog log set-window combat  -- first window whose name contains 'combat'")
                return
            end

            -- Try numeric index first (ChatFrame1 .. ChatFrame10)
            local idx = tonumber(target)
            if idx and idx >= 1 and idx <= 10 then
                local frame = _G["ChatFrame" .. idx]
                if frame then
                    Log:SetChatFrame(frame)
                    if Chronicle.Config then
                        Chronicle.Config:Set("log_window", idx)
                    end
                else
                    Log:Warn("ChatFrame%d does not exist", idx)
                end
                return
            end

            -- Try matching by tab name (case-insensitive substring)
            local needle = target:lower()
            for i = 1, 10 do
                local frame = _G["ChatFrame" .. i]
                if frame then
                    local name = (frame.name or frame:GetName() or ""):lower()
                    if name:find(needle, 1, true) then
                        Log:SetChatFrame(frame)
                        if Chronicle.Config then
                            Chronicle.Config:Set("log_window", i)
                        end
                        return
                    end
                end
            end
            Log:Warn("No chat window matching '%s' found (tried ChatFrame1-10)", target)
            return
        end

        -- Unknown log sub-command
        Log:Info("Usage: /clog log [set-lvl <level> | set-window <window>]")
        return
    end

    -- ---- /clog relay [status|activate|deactivate|clear|ui] ----
    if cmd == "relay" then
        local sub = tokens[2]
        local Relay = Chronicle.Relay

        if not sub then
            -- Status summary
            if not Relay then
                Log:Warn("Relay module not loaded")
                return
            end
            local m = Relay:GetMetrics()
            local state = Relay:IsActive() and "ACTIVE"
                or (Relay:IsActivationPending() and "WAITING" or "inactive")

            local landed, total = Relay:GetActiveProgress()
            local label = Relay:GetActiveLabel()
            Log:Info("Relay: %s", state)
            if label and label ~= "" then
                Log:Info("  Message: '%s'  chunk %d/%d", label, landed, total)
            else
                Log:Info("  Message: idle")
            end
            Log:Info("  Landed: %d  |  Missed: %d  |  Sent: %d  |  Polls: %d",
                m.chunks_landed, m.chunks_missed, m.messages_sent, m.provider_polls)
            Log:Info("  /clog relay <activate|deactivate|clear|ui>")
            return
        end

        if sub == "activate" then
            Relay:Activate()
            if Relay:IsActivationPending() then
                Log:Info("Relay activation requested -- waiting %ds for combat-log writer",
                    Chronicle.C.RELAY_ACTIVATION_DELAY_SEC)
            elseif Relay:IsActive() then
                Log:Info("Relay already active")
            else
                Log:Warn("Relay requires combat logging to be enabled")
            end
            return
        end

        if sub == "deactivate" then
            Relay:Deactivate()
            Log:Info("Relay force-deactivated")
            return
        end

        if sub == "clear" then
            Relay:Deactivate()
            Relay:Activate()
            Log:Info("Relay: queue cleared (deactivated + reactivated)")
            return
        end

        if sub == "ui" then
            if Chronicle.ToggleRelayUI then
                Chronicle.ToggleRelayUI()
            else
                Log:Warn("Relay UI not loaded")
            end
            return
        end

        Log:Info("Usage: /clog relay [status|activate|deactivate|clear|ui]")
        return
    end

    Log:Warn("Unknown command: '%s'. Try /chron help", cmd)
end

-- Expose handler so Init.lua can wire the slash commands after all files load.
Chronicle._slashHandler = slashHandler
