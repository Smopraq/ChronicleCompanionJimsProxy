-- =============================================================================
-- Core/CombatLogController.lua
--
-- Single owner for combat-logging state queries and mutations. The 1.14.2
-- client can return nil when a request cannot currently be confirmed, so nil
-- must remain distinct from a confirmed OFF state.
-- =============================================================================

local Log = Chronicle.Logger

Chronicle.CombatLogController = {}
local Controller = Chronicle.CombatLogController

local confirmedState = nil
local chatHookInstalled = false

local function stateLabel(state)
    if state == true then return "ON" end
    if state == false then return "OFF" end
    return "UNKNOWN"
end

--- Return the last confirmed combat-logging state without querying the client.
-- @treturn boolean|nil true for ON, false for OFF, nil when unknown
function Controller:GetState()
    return confirmedState
end

--- Query combat-logging state once and cache only a boolean result.
-- @treturn boolean|nil raw client result
-- @treturn boolean|nil last confirmed state
function Controller:RefreshState()
    local ok, result = pcall(LoggingCombat)
    if not ok then
        Log:Warn("Combat logging state query failed: %s", tostring(result))
        return nil, confirmedState
    end
    if type(result) == "boolean" then
        local changed = result ~= confirmedState
        confirmedState = result
        if changed and Chronicle.Relay then
            Chronicle.Relay:Reevaluate()
        end
    end
    return result, confirmedState
end

--- Request one combat-logging state mutation and cache a boolean result.
-- @tparam boolean desired requested logging state
-- @treturn boolean|nil raw client result
-- @treturn boolean|nil last confirmed state
function Controller:SetState(desired)
    desired = desired and true or false
    local ok, result = pcall(LoggingCombat, desired)
    if not ok then
        Log:Warn("Combat logging request failed: %s", tostring(result))
        return nil, confirmedState
    end
    if type(result) == "boolean" then
        confirmedState = result
        return result, confirmedState
    end

    Log:Warn("Combat logging request could not be confirmed; state remains %s",
        stateLabel(confirmedState))
    return nil, confirmedState
end

--- Toggle from the cached confirmed state using one mutation call at most.
-- An unknown initial state requests ON without claiming that it was OFF.
-- @treturn boolean|nil raw client result
-- @treturn boolean|nil last confirmed state
function Controller:Toggle()
    if confirmedState == nil then
        Log:Info("Combat logging state is unknown; requesting ON")
    end
    return self:SetState(confirmedState ~= true)
end

local function observeCombatLogStatus(message)
    local observedState = nil
    if type(COMBATLOGENABLED) == "string" and message == COMBATLOGENABLED then
        observedState = true
    elseif type(COMBATLOGDISABLED) == "string" and message == COMBATLOGDISABLED then
        observedState = false
    end

    if observedState == nil or observedState == confirmedState then return end
    confirmedState = observedState
    if Chronicle.Relay then
        Chronicle.Relay:Reevaluate()
    end
end

local function installChatStatusHook()
    if chatHookInstalled or not DEFAULT_CHAT_FRAME then return end
    hooksecurefunc(DEFAULT_CHAT_FRAME, "AddMessage", function(self, message)
        observeCombatLogStatus(message)
    end)
    chatHookInstalled = true
end

Chronicle.RegisterEvent("PLAYER_LOGIN", function()
    installChatStatusHook()
    Controller:RefreshState()
end)
