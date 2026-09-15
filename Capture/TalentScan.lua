-- =============================================================================
-- Capture/TalentScan.lua
--
-- Reads single-spec talent data for the local player on Classic Era.
--
-- Also provides a rank_string per group in Chronicle's upstream format:
--   "ranks_tab1}ranks_tab2}ranks_tab3"
-- where each tab's portion is the concatenation of every talent's current
-- rank digit in talent-index order (including 0 for unspent).
--
-- =============================================================================

local Capture = Chronicle.Capture

-- ---------------------------------------------------------------------------
-- Internal: read a single talent group
-- ---------------------------------------------------------------------------

--- Read local Classic Era talent data.
-- @return table { tabs = { [1..3] = { name, icon, points, talents } }, rank_string }
local function readGroup()
    local numTabs = GetNumTalentTabs() or 3
    local tabs = {}
    local rankParts = {}

    for tab = 1, numTabs do
        local tabName, tabIcon, tabPoints = GetTalentTabInfo(tab)

        local numTalents = GetNumTalents(tab) or 0
        local talents = {}
        local rankDigits = {}

        for idx = 1, numTalents do
            local name, icon, tier, column, rank, maxRank = GetTalentInfo(tab, idx)

            rank = rank or 0
            maxRank = maxRank or 0
            rankDigits[#rankDigits + 1] = tostring(rank)

            -- Sparse: only store talents with at least 1 point
            if rank > 0 then
                talents[idx] = {
                    name = name,
                    rank = rank,
                    max  = maxRank,
                }
            end
        end

        tabs[tab] = {
            name    = tabName or ("Tab" .. tab),
            icon    = tabIcon or "",
            points  = tabPoints or 0,
            talents = talents,
        }
        rankParts[tab] = table.concat(rankDigits, "")
    end

    return {
        tabs        = tabs,
        rank_string = table.concat(rankParts, "}"),
    }
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Scan talents for the local player. Peer talents are intentionally unsupported.
-- @param unit       string   must resolve to "player"
-- @param isInspect  boolean  true requests are rejected
-- @return table or nil
function Capture.ScanTalents(unit, isInspect)
    unit = unit or "player"
    isInspect = isInspect or false
    if isInspect or unit ~= "player" then return nil end

    local result = {
        active_group = 1,
        num_groups   = 1,
        groups       = {},
    }
    result.groups[1] = readGroup()

    return result
end
