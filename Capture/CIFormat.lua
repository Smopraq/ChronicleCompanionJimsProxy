-- =============================================================================
-- Capture/CIFormat.lua
--
-- Wire format helpers for encoding player data segments.  Each function
-- takes a Capture result table and returns a compact string suitable for
-- the relay's wire protocol.
--
-- Format: P<guid>;<segmentTypeChar><data>
-- Segments are independent -- one message per segment per player.
--
-- Reserved chars avoided in output: | " [ ] \n
-- Separators used: , (field) . (sub-field) : (slot/group)
-- =============================================================================

Chronicle.CIFormat = {}
local F    = Chronicle.CIFormat
local Util = Chronicle.Util

-- ---------------------------------------------------------------------------
-- I = Identity
-- Format: I<name>,<class>,<race>,<gender>,<level>
-- ---------------------------------------------------------------------------

--- Format player identity segment.
-- @tparam table ci  player identity data
-- @treturn string segment string (without P<guid> wrapper)
function F.Identity(ci)
    if not ci or not ci.player then return nil end
    local p = ci.player
    return string.format("I%s,%s,%s,%d,%d",
        Util.Sanitize(p.name or ""),
        p.class or "",
        p.race or "",
        p.gender or 0,
        p.level or 0)
end

-- ---------------------------------------------------------------------------
-- G = Gear
-- Format: G<slot>.<itemId>.<enc>.<g1>.<g2>.<g3>.<g4>.<sfx>.<ilvl>:<next>:...
-- ---------------------------------------------------------------------------

--- Format gear segment.
-- @tparam table gear  result from Capture.ScanGear()
-- @treturn string segment string
function F.Gear(gear)
    if not gear then return nil end
    local slots = {}
    for i = 1, 19 do
        local g = gear[i]
        if g then
            local gems = g.gems or {}
            slots[#slots + 1] = string.format("%d.%d.%d.%d.%d.%d.%d.%d.%d",
                i,
                g.item_id or 0,
                g.enchant or 0,
                gems[1] or 0,
                gems[2] or 0,
                gems[3] or 0,
                gems[4] or 0,
                g.suffix or 0,
                g.item_level or 0)
        end
    end
    if #slots == 0 then return nil end
    return "G" .. table.concat(slots, ":")
end

-- ---------------------------------------------------------------------------
-- T = Talents
-- Format: T<activeGroup>,<numGroups>,<rankStr1>
-- ---------------------------------------------------------------------------

--- Format talents segment.
-- @tparam table talents  result from Capture.ScanTalents()
-- @treturn string segment string
function F.Talents(talents)
    if not talents then return nil end
    local parts = {
        string.format("T%d,%d", talents.active_group or 1, talents.num_groups or 1)
    }
    for g = 1, (talents.num_groups or 1) do
        local group = talents.groups and talents.groups[g]
        if group and group.rank_string then
            parts[#parts + 1] = group.rank_string
        else
            parts[#parts + 1] = ""
        end
    end
    -- Join: T<active>,<num>,<rankStr1>
    return parts[1] .. "," .. table.concat(parts, ",", 2)
end

-- ---------------------------------------------------------------------------
-- U = Guild  (just the name)
-- Format: U<guildName>
-- ---------------------------------------------------------------------------

--- Format guild segment.
-- @tparam table guild  result from Capture.ScanGuild()
-- @treturn string segment string
function F.Guild(guild)
    if not guild or not guild.name then return nil end
    return "U" .. Util.Sanitize(guild.name)
end

-- ---------------------------------------------------------------------------
-- E = Pet  (name + guid only)
-- Format: E<name>,<guid>
-- ---------------------------------------------------------------------------

--- Format pet segment.
-- @tparam table pet  result from Capture.ScanPet()
-- @treturn string segment string
function F.Pet(pet)
    if not pet then return nil end
    return string.format("E%s,%s",
        Util.Sanitize(pet.name or ""),
        pet.guid or "")
end

-- ---------------------------------------------------------------------------
-- H = Honor
-- Format: H<lifetimeHK>,<highestRank>,<currency>,<sessionHK>
-- ---------------------------------------------------------------------------

--- Format honor segment.
-- @tparam table honor  result from Capture.ScanHonor()
-- @treturn string segment string
function F.Honor(honor)
    if not honor then return nil end
    return string.format("H%d,%d,%d,%d",
        honor.lifetime_hk or 0,
        honor.highest_rank or 0,
        honor.honor_currency or 0,
        honor.session_hk or 0)
end

-- ---------------------------------------------------------------------------
-- Wrap: prepend P<guid>; to any segment
-- ---------------------------------------------------------------------------

--- Wrap a segment with the player GUID header.
-- @tparam string guid  player GUID
-- @tparam string segment  formatted segment string (e.g. "G1.51396...")
-- @treturn string full wire message (e.g. "P0x060...;G1.51396...")
function F.Wrap(guid, segment)
    return "P" .. (guid or "") .. ";" .. (segment or "")
end
