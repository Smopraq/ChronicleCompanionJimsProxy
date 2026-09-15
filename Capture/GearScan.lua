-- =============================================================================
-- Capture/GearScan.lua
--
-- Reads equipment for any valid unit token (19 inventory slots).
-- Returns a table keyed by slot index with parsed itemstring fields:
-- item_id, enchant, gems, suffix, unique, item_level, raw link, and
-- optional vanity_item_id when GetInventoryItemID diverges from the link.
--
-- Works for "player" immediately, and for inspected units (e.g. "target",
-- "raid5") only after INSPECT_READY has fired and the gear buffer
-- is populated.
-- =============================================================================

local Capture = Chronicle.Capture

-- ---------------------------------------------------------------------------
-- Slot map: index -> API slot name.
-- WoW inventory slots 1-19 in canonical order.
-- ---------------------------------------------------------------------------

local SLOT_NAMES = {
    "HeadSlot",              -- 1
    "NeckSlot",              -- 2
    "ShoulderSlot",          -- 3
    "ShirtSlot",             -- 4
    "ChestSlot",             -- 5
    "WaistSlot",             -- 6
    "LegsSlot",              -- 7
    "FeetSlot",              -- 8
    "WristSlot",             -- 9
    "HandsSlot",             -- 10
    "Finger0Slot",           -- 11
    "Finger1Slot",           -- 12
    "Trinket0Slot",          -- 13
    "Trinket1Slot",          -- 14
    "BackSlot",              -- 15
    "MainHandSlot",          -- 16
    "SecondaryHandSlot",     -- 17
    "RangedSlot",            -- 18
    "TabardSlot",            -- 19
}
local NUM_SLOTS = #SLOT_NAMES



-- Resolve the engine slot ID for each name once at load time.
-- GetInventorySlotInfo returns (slotId, textureName, checkRelic).
local SLOT_IDS = {}
for i = 1, NUM_SLOTS do
    local id = GetInventorySlotInfo(SLOT_NAMES[i])
    SLOT_IDS[i] = id
end

-- Feature-test GetInventoryItemID so the capture remains tolerant of proxy
-- environments that expose a reduced Classic Era API surface.
local hasGetItemID = type(GetInventoryItemID) == "function"

-- ---------------------------------------------------------------------------
-- Itemstring parser
--
-- Classic Era item links look like:
--   |cff...|Hitem:ID:ENCHANT:GEM1:GEM2:GEM3:GEM4:SUFFIX:UNIQUE:LEVEL|h[Name]|h|r
--
-- We extract the numeric fields from the Hitem portion.
-- ---------------------------------------------------------------------------

--- Parse a WoW item link and return a table of numeric fields.
-- @param link  string  Full item link (colored, with |H...|h wrappers)
-- @return table or nil
local function parseLink(link)
    if not link then return nil end

    -- Pull the colon-delimited field string out of |Hitem:...|h
    local itemString = link:match("|Hitem:([^|]+)|h")
    if not itemString then return nil end

    -- Split on colons into an array of strings
    local parts = {}
    for field in itemString:gmatch("([^:]*):?") do
        parts[#parts + 1] = field
    end

    -- Classic Era itemstring field positions (1-based after split):
    --  1=itemId  2=enchant  3=gem1  4=gem2  5=gem3  6=gem4
    --  7=suffixId  8=uniqueId  9=level
    local itemId  = tonumber(parts[1]) or 0
    local enchant = tonumber(parts[2]) or 0
    local gem1    = tonumber(parts[3]) or 0
    local gem2    = tonumber(parts[4]) or 0
    local gem3    = tonumber(parts[5]) or 0
    local gem4    = tonumber(parts[6]) or 0
    local suffix  = tonumber(parts[7]) or 0
    local unique  = tonumber(parts[8]) or 0
    -- Item-link field 9 is the link owner's level, not the item's level.
    -- GetItemInfo return 4 is the actual base item level on Classic Era.
    local iLvl = select(4, GetItemInfo(link)) or 0

    return {
        item_id    = itemId,
        enchant    = enchant,
        gems       = { gem1, gem2, gem3, gem4 },
        suffix     = suffix,
        unique     = unique,
        item_level = iLvl,
    }
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Scan all 19 equipment slots for a unit.
-- @param unit  string  Unit token -- "player", "target", "raid5", etc.
-- @return table  gear  { [slotIndex] = { slot, item_id, enchant, gems, ... } }
--                      Empty slots are absent (nil key).
function Capture.ScanGear(unit)
    unit = unit or "player"
    local gear = {}

    for i = 1, NUM_SLOTS do
        local slotId = SLOT_IDS[i]
        local link = GetInventoryItemLink(unit, slotId)

        if link then
            local parsed = parseLink(link)
            if parsed then
                parsed.slot = i
                parsed.raw  = link

                -- Vanity / transmog detection: if GetInventoryItemID returns a
                -- different item than the link's item_id, the visual is overridden.
                if hasGetItemID then
                    local visualId = GetInventoryItemID(unit, slotId)
                    if visualId and visualId ~= parsed.item_id then
                        parsed.vanity_item_id = visualId
                    end
                end

                gear[i] = parsed
            end
        end
    end

    return gear
end
