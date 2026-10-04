-- =============================================================================
-- Core/AutoLog.lua
--
-- Automatically enables combat logging and activates the relay when the
-- player enters a raid or dungeon instance.  After leaving, logging stays on
-- for LEAVE_TIMEOUT_MIN minutes (ghost release, repair, bank run, summon) and
-- is turned off only if the player has not entered a raid or dungeon again.
--
-- Config toggles:
--   auto_combatlog_raid    (default true) -- auto-enable LoggingCombat() in raids
--   auto_combatlog_dungeon (default true) -- auto-enable LoggingCombat() in dungeons
-- The relay is unconditionally tied to LoggingCombat() -- no separate toggle.
-- =============================================================================

local Log    = Chronicle.Logger
local Config = Chronicle.Config
local Relay  = Chronicle.Relay
local CombatLog = Chronicle.CombatLogController

--- Instance types that trigger auto-activation.
local INSTANCE_TYPES = {
    party = true,   -- 5-man dungeons
    raid  = true,   -- raids
}

--- Minutes combat logging stays on after leaving an instance.
local LEAVE_TIMEOUT_MIN = 30

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local wasInInstance = false   -- track transitions, not just current state
local leaveTimerId  = 0       -- bumped to cancel a pending leave timeout

-- ---------------------------------------------------------------------------
-- Evaluate current zone and act
-- ---------------------------------------------------------------------------

--- Check the current zone and auto-enable combat logging / relay.
-- Called on zone change events and login.
local function evaluate()
    if not Config:IsReady() then return end

    local inInstance = false
    local instanceType = "none"
    local instanceName = ""

    if type(GetInstanceInfo) == "function" then
        instanceName, instanceType = GetInstanceInfo()
    else
        local _, iType = IsInInstance()
        instanceType = iType or "none"
        instanceName = GetRealZoneText() or ""
    end

    inInstance = INSTANCE_TYPES[instanceType] or false

    -- Entering an instance
    if inInstance and not wasInInstance then
        wasInInstance = true
        leaveTimerId = leaveTimerId + 1   -- cancel any pending leave timeout

        -- Auto combat logging (separate toggles for raid vs dungeon)
        local autoLog = false
        if instanceType == "raid" then
            autoLog = Config:Get("auto_combatlog_raid")
        elseif instanceType == "party" then
            autoLog = Config:Get("auto_combatlog_dungeon")
        end
        if autoLog then
            if CombatLog:GetState() ~= true then
                local result = CombatLog:SetState(true)
                if result == true then
                    Log:Info("Auto-enabled combat logging (%s - %s)", instanceName, instanceType)
                end
            else
                Log:Debug("Entered %s (%s) - combat logging already on", instanceName, instanceType)
            end
        end

        -- Relay follows combat logging state
        Relay:Reevaluate()

    -- Leaving an instance
    elseif not inInstance and wasInInstance then
        wasInInstance = false
        leaveTimerId = leaveTimerId + 1
        local timerId = leaveTimerId

        -- Keep combat logging on for a while; turn it off only if the
        -- player has not entered a raid or dungeon again by then
        if CombatLog:GetState() == true then
            Log:Info("Left instance - combat logging stays ON for %d min", LEAVE_TIMEOUT_MIN)
            C_Timer.After(LEAVE_TIMEOUT_MIN * 60, function()
                if timerId ~= leaveTimerId then return end
                if CombatLog:GetState() == true then
                    local result = CombatLog:SetState(false)
                    if result == false then
                        Log:Info("No instance for %d min - combat logging OFF", LEAVE_TIMEOUT_MIN)
                    end
                end
                -- Relay follows combat logging state
                Relay:Reevaluate()
            end)
        else
            Log:Info("Left instance")
        end
        -- Relay follows combat logging state
        Relay:Reevaluate()
    end
end

-- ---------------------------------------------------------------------------
-- Event wiring
-- ---------------------------------------------------------------------------

Chronicle.RegisterEvent("ZONE_CHANGED_NEW_AREA", evaluate)
Chronicle.RegisterEvent("PLAYER_ENTERING_WORLD", evaluate)

-- Also check on login in case we logged out inside an instance
Chronicle.RegisterEvent("PLAYER_LOGIN", function()
    -- Small delay to let Config hydrate and other modules init
    local f = CreateFrame("Frame")
    local elapsed = 0
    f:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 1 then
            self:SetScript("OnUpdate", nil)
            evaluate()
        end
    end)
end)
