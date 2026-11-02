local _, BindCards = ...

local Helpers = {}
BindCards.UIHelpers = Helpers

local function UTF8Length(text)
    local length = 0
    for index = 1, #text do
        local byte = text:byte(index)
        if not byte or byte < 0x80 or byte >= 0xC0 then length = length + 1 end
    end
    return length
end

function Helpers.KeyFontSize(baseSize, text)
    baseSize = tonumber(baseSize) or 12
    text = type(text) == "string" and text or ""
    local length = UTF8Length(text)
    if length <= 4 then return baseSize end
    return math.max(8, math.floor(baseSize * 4 / length))
end

function Helpers.CollapsedSelection(selectedID, parentID, isDescendant)
    if selectedID and parentID and type(isDescendant) == "function" and
        isDescendant(selectedID, parentID) then
        return parentID
    end
    return selectedID
end

function Helpers.PreferredDockedBinder(wanted, generalDetached, classDetached, generalAvailable, classAvailable)
    if wanted == "class" and classDetached and generalAvailable and not generalDetached then return "general" end
    if wanted == "general" and generalDetached and classAvailable and not classDetached then return "class" end
    return wanted
end

local function HierarchyDepth(value)
    return math.min(3, math.max(0, math.floor(tonumber(value) or 0)))
end

function Helpers.HierarchyTabMetrics(depth, mainRoot)
    depth = HierarchyDepth(depth)
    if mainRoot then
        return { width = 164, height = 34, iconSize = 16, fontSize = 12, indent = 0, gap = 4 }
    end
    if depth <= 1 then return { width = 150, height = 30, iconSize = 14, fontSize = 10, indent = 0, gap = 4 } end
    if depth == 2 then return { width = 136, height = 27, iconSize = 13, fontSize = 9, indent = 0, gap = 4 } end
    return { width = 122, height = 24, iconSize = 12, fontSize = 9, indent = 0, gap = 4 }
end

function Helpers.HierarchyEarRailWidth()
    -- The widest root ear plus its one-pixel overlap and a small breathing edge.
    return Helpers.HierarchyTabMetrics(0, true).width + 6
end

function Helpers.HierarchyEarLayer(selected, workspaceLevel)
    -- The Forever workspace also uses DIALOG. Keep its tabs above the page's
    -- interactive descendants even after the editor has been raised.
    return "DIALOG", (tonumber(workspaceLevel) or 0) + (selected and 52 or 44)
end

function Helpers.GeneralPageFootprint(columns, capacity, iconSize)
    columns = math.min(12, math.max(3, math.floor(tonumber(columns) or 6)))
    capacity = math.max(columns, math.floor(tonumber(capacity) or columns * 2))
    local rows = math.max(1, math.ceil(capacity / columns))
    iconSize = math.min(48, math.max(24, tonumber(iconSize) or 36))
    local gridWidth = columns * (iconSize + 6) - 6
    local gridHeight = rows * (iconSize + 6) - 6
    -- General utility sheets need enough header/action breathing room to read
    -- as cards, while their grid capacity—not occupied slots—drives growth.
    return math.max(380, gridWidth + 176), math.max(190, gridHeight + 110)
end

function Helpers.DockedPageWidth(binderKey, availableWidth, intrinsicWidth, columns, capacity, iconSize)
    availableWidth = math.max(1, tonumber(availableWidth) or 1)
    -- General and the character card are compact utility binders.
    if binderKey ~= "general" and binderKey ~= "character" then return availableWidth end
    local naturalWidth = columns and Helpers.GeneralPageFootprint(columns, capacity, iconSize) or
        math.max(380, (tonumber(intrinsicWidth) or 300) + 56)
    -- General is a compact utility binder. Enlarging the shared window for a
    -- spell-heavy class must not stretch General along with it.
    return math.min(availableWidth, naturalWidth, 560)
end

function Helpers.HierarchyCoverHeight(pageHeight, depth)
    pageHeight = math.max(1, tonumber(pageHeight) or 1)
    depth = HierarchyDepth(depth)
    return pageHeight + depth * 18 + 8
end

function Helpers.PanelMinimumWidth(navigationWidth, rulesWidth, minimumWorkspaceWidth)
    navigationWidth = math.max(0, tonumber(navigationWidth) or 178)
    rulesWidth = math.max(0, tonumber(rulesWidth) or 178)
    minimumWorkspaceWidth = math.max(1, tonumber(minimumWorkspaceWidth) or 300)
    -- 10 outer-left + 8 nav gap + 8 rules gap + 10 outer-right.
    return navigationWidth + rulesWidth + minimumWorkspaceWidth + 36
end

function Helpers.ShouldHideResizeGrip(binderMode, resizeActive, cursorInside)
    return binderMode == true and resizeActive ~= true and cursorInside ~= true
end

function Helpers.ClampFloatingStack(left, top, pageWidth, pageHeight, earWidth, earHeight, screenWidth, screenHeight, margin)
    left, top = tonumber(left) or 0, tonumber(top) or 0
    pageWidth, pageHeight = math.max(1, tonumber(pageWidth) or 1), math.max(1, tonumber(pageHeight) or 1)
    earWidth, earHeight = math.max(0, tonumber(earWidth) or 0), math.max(0, tonumber(earHeight) or 0)
    screenWidth, screenHeight = math.max(1, tonumber(screenWidth) or 1), math.max(1, tonumber(screenHeight) or 1)
    margin = math.max(0, tonumber(margin) or 0)
    local totalWidth = pageWidth + earWidth
    local totalHeight = math.max(pageHeight, earHeight)
    local maximumLeft = math.max(margin, screenWidth - margin - totalWidth)
    local minimumTop = math.min(screenHeight - margin, margin + totalHeight)
    return math.min(maximumLeft, math.max(margin, left)),
        math.min(screenHeight - margin, math.max(minimumTop, top))
end

function Helpers.HierarchySheetGeometry(layerDepth, selectedDepth, pageWidth, laneX)
    local layerOffset = HierarchyDepth(layerDepth) * 16
    local selectedOffset = HierarchyDepth(selectedDepth) * 16
    local width = math.max(1, tonumber(pageWidth) or 1) + math.max(0, selectedOffset - layerOffset)
    local x = (tonumber(laneX) or 0) + layerOffset
    return { x = x, width = width, right = x + width }
end

function Helpers.WorkspaceLaneX(mode, binderKey)
    if mode == "panel" then return 5 end
    -- Cascade: General 5, class 45, character 85 (class shows behind it).
    if binderKey == "character" then return 85 end
    return binderKey == "class" and 45 or 5
end

function Helpers.FloatingCenterFromTopLeft(left, top, width, rootHeight, hierarchyX,
        coordinateScale, parentCenterX, parentCenterY)
    local scale = tonumber(coordinateScale) or 1
    local x = ((tonumber(left) or 0) - (tonumber(hierarchyX) or 0) +
        (tonumber(width) or 0) / 2) * scale - (tonumber(parentCenterX) or 0)
    local y = ((tonumber(top) or 0) - (tonumber(rootHeight) or 0) / 2) * scale -
        (tonumber(parentCenterY) or 0)
    return x, y
end

function Helpers.HierarchyAncestors(selected, cardsByID, cardID, parentID, maximum)
    local result, cursor, seen = {}, selected, {}
    if type(cardsByID) ~= "table" or type(cardID) ~= "function" or type(parentID) ~= "function" then
        return result
    end
    while cursor do
        local cursorID = cardID(cursor)
        if cursorID then seen[cursorID] = true end
        local wantedParentID = parentID(cursor)
        if not wantedParentID or seen[wantedParentID] then break end
        local parent = cardsByID[wantedParentID]
        if not parent then break end
        table.insert(result, 1, parent)
        cursor = parent
    end
    maximum = math.max(0, math.floor(tonumber(maximum) or #result))
    if #result <= maximum then return result end
    if maximum == 0 then return {} end
    if maximum == 1 then return { result[#result] } end
    local trimmed = { result[1] }
    local start = #result - maximum + 2
    for index = start, #result do trimmed[#trimmed + 1] = result[index] end
    return trimmed
end

local function SortProfiles(result)
    table.sort(result, function(left, right)
        local leftName = tostring(left.name or ""):lower()
        local rightName = tostring(right.name or ""):lower()
        if leftName == rightName then return tostring(left.id or "") < tostring(right.id or "") end
        return leftName < rightName
    end)
    return result
end

function Helpers.SortedProfiles(profiles)
    local result = {}
    for _, profile in pairs(type(profiles) == "table" and profiles or {}) do
        if type(profile) == "table" then result[#result + 1] = profile end
    end
    return SortProfiles(result)
end

function Helpers.ProfileStats(profile)
    local stats = { cards = 0, tiles = 0, bindings = 0, macros = 0 }
    for _, card in ipairs(type(profile) == "table" and profile.cards or {}) do
        stats.cards = stats.cards + 1
        for _, tile in ipairs(type(card) == "table" and card.tiles or {}) do
            stats.tiles = stats.tiles + 1
            stats.bindings = stats.bindings + #(type(tile.bindings) == "table" and tile.bindings or {})
            if tile.kind == "macro" or tile.type == "macro" then stats.macros = stats.macros + 1 end
        end
    end
    return stats
end

function Helpers.ProfileLibraryList(profiles, binderId)
    local result = {}
    if type(profiles) ~= "table" or type(binderId) ~= "string" then return result end
    for _, profile in pairs(profiles) do
        if type(profile) == "table" and profile.binderId == binderId then
            result[#result + 1] = profile
        end
    end
    return SortProfiles(result)
end

local UNIT_EVENTS = {
    UNIT_PET = true,
    PLAYER_FLAGS_CHANGED = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
}

function Helpers.ShouldRefreshMacroEvent(event, unit, macroEditorOpen)
    if event == "PLAYER_STARTED_MOVING" or event == "PLAYER_STOPPED_MOVING" or
        event == "GROUP_ROSTER_UPDATE" then
        return false
    end
    if event == "MODIFIER_STATE_CHANGED" then return macroEditorOpen == true end
    if not UNIT_EVENTS[event] then return true end
    return unit == nil or unit == "player" or unit == "target" or unit == "focus"
end

return Helpers
