-- =============================================================================
-- Core/Logger.lua
--
-- Chat-window logger with configurable log levels and pretty-print support.
--
-- Log levels (ascending verbosity):
--     error < warn < info < debug
--
-- Set via Chronicle.Logger:SetLevel("debug") or /clog loglvl debug.
-- Output goes to a configurable chat frame (default: DEFAULT_CHAT_FRAME).
-- =============================================================================

local Logger = {}
Chronicle.Logger = Logger

-- ---------------------------------------------------------------------------
-- Level definitions
-- ---------------------------------------------------------------------------

local LEVELS = { error = 1, warn = 2, info = 3, debug = 4 }
local DEFAULT_LEVEL = "info"

local COLORS = {
    error = "|cffff0000",   -- red
    warn  = "|cffffff00",   -- yellow
    info  = "|cff4ec3ff",   -- Chronicle blue
    debug = "|cff888888",   -- grey
}

-- State
local currentLevel = LEVELS[DEFAULT_LEVEL]
local currentLevelName = DEFAULT_LEVEL
local chatFrame = nil  -- resolved lazily (DEFAULT_CHAT_FRAME may not exist at load time)

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function getChatFrame()
    if chatFrame then return chatFrame end
    return DEFAULT_CHAT_FRAME
end

--- Format a message with optional string.format args.
-- If the first vararg is nil or there are no varargs, msg is used as-is.
local function fmt(msg, ...)
    if select("#", ...) > 0 then
        local ok, result = pcall(string.format, msg, ...)
        if ok then return result end
    end
    return tostring(msg)
end

local function emit(level, msg, ...)
    if LEVELS[level] > currentLevel then return end
    local text = fmt(msg, ...)
    local prefix = COLORS[level] .. "[Chronicle]|r "
    local frame = getChatFrame()
    if frame and frame.AddMessage then
        frame:AddMessage(prefix .. text)
    end
    -- Errors also go through the global error handler so BugSack picks them up
    if level == "error" then
        local handler = geterrorhandler()
        if handler then
            handler("[Chronicle] " .. text)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Log an error.  Always prints.  Also feeds geterrorhandler().
-- @tparam string msg format string (or plain message)
-- @param ... format arguments
function Logger:Error(msg, ...) emit("error", msg, ...) end

--- Log a warning.  Prints at warn level or above.
-- @tparam string msg format string
-- @param ... format arguments
function Logger:Warn(msg, ...)  emit("warn",  msg, ...) end

--- Log an informational message.  Prints at info level or above.
-- @tparam string msg format string
-- @param ... format arguments
function Logger:Info(msg, ...)  emit("info",  msg, ...) end

--- Log a debug message.  Only prints when log level is "debug".
-- @tparam string msg format string
-- @param ... format arguments
function Logger:Debug(msg, ...) emit("debug", msg, ...) end

--- Set the active log level.
-- @tparam string name one of "error", "warn", "info", "debug"
function Logger:SetLevel(name)
    name = (name or ""):lower()
    if not LEVELS[name] then
        self:Warn("Unknown log level '%s'. Use: error, warn, info, debug", tostring(name))
        return
    end
    currentLevel = LEVELS[name]
    currentLevelName = name
    self:Info("Log level set to %s", name)
end

--- Return the current log level name.
-- @treturn string current level ("error", "warn", "info", or "debug")
function Logger:GetLevel()
    return currentLevelName
end

--- Set the chat frame all output goes to.
-- @tparam Frame frame any object with :AddMessage (e.g. ChatFrame2)
function Logger:SetChatFrame(frame)
    if frame and frame.AddMessage then
        chatFrame = frame
        self:Info("Logger output redirected to %s", frame:GetName() or "custom frame")
    else
        self:Warn("Invalid chat frame -- must have :AddMessage()")
    end
end

--- Return the currently active chat frame.
-- @treturn Frame the frame receiving log output
function Logger:GetChatFrame()
    return getChatFrame()
end
