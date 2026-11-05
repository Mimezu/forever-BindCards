local _, BindCards = ...

local PREFIX = "BC01:"
local EXPORT_SCHEMA_VERSION = 6
local MAX_ENCODED = 256 * 1024
local MAX_EXPANDED = 2 * 1024 * 1024
local VALID_CLASSES = BindCards.VALID_CLASSES

local function isArray(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        count = count + 1
    end
    return count == #value
end

local function boundedString(value, maximum, optional)
    if optional and value == nil then return true end
    return type(value) == "string" and #value <= maximum
end

local function onlyKeys(value, allowed)
    for key in pairs(value) do if not allowed[key] then return false end end
    return true
end

local CONDITION_KEYS = {
    class = true, specGroup = true, content = true,
    form = true,
}
local PROFILE_KEYS = {
    id = true, name = true, binderId = true, cards = true,
    createdAt = true, updatedAt = true, bindingsEnabled = true,
}
local CARD_KEYS = {
    id = true, name = true, enabled = true, collapsed = true, treeExpanded = true,
    parentId = true, homeParentId = true,
    order = true, priority = true, columns = true, capacity = true, condition = true, tiles = true,
    layoutMode = true, floatX = true, floatY = true, floatWidth = true, floatHeight = true,
    paperWidth = true, paperHeight = true,
    templateKey = true, binderId = true, overrideAllBindingsWhenActive = true,
}
local TILE_KEYS = {
    id = true, kind = true, spellID = true, highestRank = true, itemID = true, macrotext = true,
    name = true, icon = true, manualIcon = true, order = true, gridX = true, gridY = true, bindings = true,
}

local function validateCondition(condition)
    if condition == nil then return true end
    if type(condition) ~= "table" or not onlyKeys(condition, CONDITION_KEYS) then return false end
    if condition.specGroup ~= nil and condition.specGroup ~= 1 and condition.specGroup ~= 2 then return false end
    if condition.class ~= nil and not VALID_CLASSES[condition.class] then return false end
    if condition.content ~= nil and condition.content ~= "ANY" and condition.content ~= "PVE" and condition.content ~= "PVP" then return false end
    if condition.form ~= nil and not BindCards.FORM_DEFINITIONS[condition.form] then return false end
    if condition.form ~= nil and condition.class ~= nil and
        BindCards.FORM_DEFINITIONS[condition.form].class ~= condition.class then return false end
    return true
end

local function validateProfile(profile, allowLegacyScope)
    if type(profile) ~= "table" or not onlyKeys(profile, PROFILE_KEYS) or
        not boundedString(profile.id, 128, true) or not boundedString(profile.name, 64) or profile.name == "" or
        not boundedString(profile.binderId, 32, allowLegacyScope) or
        (profile.binderId ~= nil and profile.binderId ~= BindCards.GENERAL_BINDER_ID and
            not (profile.binderId:match("^class:([A-Z]+)$") and
                VALID_CLASSES[profile.binderId:match("^class:([A-Z]+)$")])) or
        (profile.createdAt ~= nil and type(profile.createdAt) ~= "number") or
        (profile.updatedAt ~= nil and type(profile.updatedAt) ~= "number") or
        (profile.bindingsEnabled ~= nil and type(profile.bindingsEnabled) ~= "boolean") or
        not isArray(profile.cards) or #profile.cards > BindCards.MAX_CARDS then
        return false, "Invalid profile."
    end
    local cardIds, tileIds, templateKeys, tileCount = {}, {}, {}, 0
    for _, card in ipairs(profile.cards) do
        local binderClass = type(card) == "table" and type(card.binderId) == "string" and
            card.binderId:match("^class:(.+)$")
        if type(card) ~= "table" or not onlyKeys(card, CARD_KEYS) or
            not boundedString(card.id, 128) or cardIds[card.id] or
            not boundedString(card.name, 64) or card.name == "" or
            not boundedString(card.parentId, 128, true) or not boundedString(card.homeParentId, 128, true) or
            not boundedString(card.templateKey, 64, true) or
            not boundedString(card.binderId, 160, true) or
            (card.binderId ~= nil and BindCards:NormalizeBinderId(card.binderId) ~= card.binderId) or
            (card.parentId ~= nil and card.binderId ~= nil) or
            (card.homeParentId ~= nil and
                (card.parentId ~= nil or card.binderId == nil or card.layoutMode ~= "floating")) or
            (type(card.condition) == "table" and card.condition.form ~= nil and
                card.parentId == nil and card.homeParentId == nil) or
            (binderClass and not card.parentId and not card.homeParentId and
                (type(card.condition) ~= "table" or card.condition.class ~= binderClass)) or
            (card.enabled ~= nil and type(card.enabled) ~= "boolean") or
            (card.collapsed ~= nil and type(card.collapsed) ~= "boolean") or
            (card.treeExpanded ~= nil and type(card.treeExpanded) ~= "boolean") or
            (card.overrideAllBindingsWhenActive ~= nil and
                type(card.overrideAllBindingsWhenActive) ~= "boolean") or
            (card.order ~= nil and (type(card.order) ~= "number" or card.order % 1 ~= 0)) or
            (card.priority ~= nil and type(card.priority) ~= "number") or
            (card.columns ~= nil and (type(card.columns) ~= "number" or card.columns < BindCards.MIN_COLUMNS or card.columns > BindCards.MAX_COLUMNS or card.columns % 1 ~= 0)) or
            (card.capacity ~= nil and (type(card.capacity) ~= "number" or card.capacity < (card.columns or BindCards.MIN_COLUMNS) or card.capacity > 192 or card.capacity % 1 ~= 0)) or
            (card.layoutMode ~= nil and card.layoutMode ~= "stacked" and card.layoutMode ~= "floating") or
            (card.floatX ~= nil and (type(card.floatX) ~= "number" or math.abs(card.floatX) > 10000)) or
            (card.floatY ~= nil and (type(card.floatY) ~= "number" or math.abs(card.floatY) > 10000)) or
            (card.floatWidth ~= nil and (type(card.floatWidth) ~= "number" or card.floatWidth < 240 or card.floatWidth > 1200)) or
            (card.floatHeight ~= nil and (type(card.floatHeight) ~= "number" or card.floatHeight < 180 or card.floatHeight > 1000)) or
            (card.paperWidth ~= nil and (type(card.paperWidth) ~= "number" or card.paperWidth < 300 or card.paperWidth > 720)) or
            (card.paperHeight ~= nil and (type(card.paperHeight) ~= "number" or card.paperHeight < 120 or card.paperHeight > 1000)) or
            not validateCondition(card.condition) or not isArray(card.tiles) then
            return false, "Invalid card data: " .. tostring(type(card) == "table" and card.name or "unknown") .. "."
        end
        if card.templateKey then
            if templateKeys[card.templateKey] or not BindCards:IsValidTemplateKey(card.templateKey, card.condition) then
                return false, "Invalid generated card identity."
            end
            templateKeys[card.templateKey] = true
        end
        cardIds[card.id] = true
        if #card.tiles > 192 then return false, "A card has too many abilities." end
        tileCount = tileCount + #card.tiles
        if tileCount > BindCards.MAX_TILES then return false, "The profile has too many tiles." end
        local occupiedSlots = {}
        for tileIndex, tile in ipairs(card.tiles) do
            local oldSlot = type(tile) == "table" and type(tile.order) == "number" and tile.order or tileIndex
            local gridX = type(tile) == "table" and tile.gridX or nil
            local gridY = type(tile) == "table" and tile.gridY or nil
            gridX = gridX or ((oldSlot - 1) % (card.columns or 6) + 1)
            gridY = gridY or (math.floor((oldSlot - 1) / (card.columns or 6)) + 1)
            local cellKey = tostring(gridX) .. ":" .. tostring(gridY)
            if type(tile) ~= "table" or not onlyKeys(tile, TILE_KEYS) or
                not boundedString(tile.id, 128) or tileIds[tile.id] or
                not boundedString(tile.kind, 8) or not boundedString(tile.name, 128, true) or
                (tile.icon ~= nil and type(tile.icon) ~= "number") or
                (tile.manualIcon ~= nil and (type(tile.manualIcon) ~= "number" or tile.manualIcon <= 0 or tile.manualIcon % 1 ~= 0)) or
                (type(tile.order) ~= "number" or tile.order % 1 ~= 0 or tile.order < 1) or
                type(gridX) ~= "number" or gridX % 1 ~= 0 or gridX < 1 or gridX > BindCards.MAX_COLUMNS or
                type(gridY) ~= "number" or gridY % 1 ~= 0 or gridY < 1 or gridY > 64 or occupiedSlots[cellKey] or
                not isArray(tile.bindings) or #tile.bindings > 8 then
                return false, "Invalid tile data."
            end
            occupiedSlots[cellKey] = true
            tileIds[tile.id] = true
            if tile.highestRank ~= nil and (tile.kind ~= "spell" or tile.highestRank ~= true) then return false, "Invalid spell rank mode." end
            if tile.kind == "spell" and (type(tile.spellID) ~= "number" or tile.spellID <= 0 or tile.spellID % 1 ~= 0) then return false, "Invalid spell." end
            if tile.kind == "item" and (type(tile.itemID) ~= "number" or tile.itemID <= 0 or tile.itemID % 1 ~= 0) then return false, "Invalid item." end
            if tile.kind == "macro" and (not boundedString(tile.macrotext, 1023) or tile.macrotext == "") then return false, "Invalid macro." end
            if tile.kind ~= "spell" and tile.kind ~= "item" and tile.kind ~= "macro" then return false, "Unsupported tile." end
            if tile.kind ~= "spell" and tile.spellID ~= nil then return false, "Non-canonical tile." end
            if tile.kind ~= "item" and tile.itemID ~= nil then return false, "Non-canonical tile." end
            if tile.kind ~= "macro" and tile.macrotext ~= nil then return false, "Non-canonical tile." end
            for _, key in ipairs(tile.bindings) do
                if not boundedString(key, 64) or BindCards:NormalizeKey(key) ~= key then return false, "Invalid binding." end
            end
        end
    end
    for _, card in ipairs(profile.cards) do
        if card.parentId and not cardIds[card.parentId] then return false, "A parent card is missing." end
        if card.homeParentId and not cardIds[card.homeParentId] then return false, "A home card is missing." end
        if card.homeParentId and BindCards:GetCardBinderId(card.homeParentId, profile) ~= card.binderId then
            return false, "A peeled card does not match its parent binder."
        end
    end
    local parents = {}
    for _, card in ipairs(profile.cards) do parents[card.id] = card.parentId or card.homeParentId end
    for id in pairs(parents) do
        local cursor, seen = id, {}
        while cursor do
            if seen[cursor] then return false, "The profile contains a card cycle." end
            seen[cursor] = true
            cursor = parents[cursor]
        end
    end
    for _, card in ipairs(profile.cards) do
        local effectiveBinderId = BindCards:GetCardBinderId(card, profile)
        local binderClass = effectiveBinderId and effectiveBinderId:match("^class:(.+)$")
        if binderClass and card.condition and card.condition.class and card.condition.class ~= binderClass then
            return false, "A nested class condition conflicts with its binder."
        end
        if card.condition and card.condition.form and
            (not binderClass or not BindCards:IsFormValidForClass(card.condition.form, binderClass)) then
            return false, "A form condition conflicts with its class binder."
        end
        if card.overrideAllBindingsWhenActive and not BindCards:CanCardUseGlobalPriority(card, profile) then
            return false, "Global priority belongs on a user-created General subcard."
        end
        if profile.binderId then
            local effectiveScope = effectiveBinderId and effectiveBinderId:match("^class:([A-Z]+)$") and
                effectiveBinderId or BindCards.GENERAL_BINDER_ID
            if effectiveScope ~= profile.binderId then return false, "A card is outside this binding set." end
        end
    end
    return true
end

local function encode(data)
    if not C_EncodingUtil then return nil, "Encoding is unavailable." end
    local ok, result = pcall(function()
        local json = C_EncodingUtil.SerializeJSON(data)
        local compressed = C_EncodingUtil.CompressString(json)
        return PREFIX .. C_EncodingUtil.EncodeHex(compressed)
    end)
    if not ok or type(result) ~= "string" then return nil, "Could not export this profile." end
    if #result > MAX_ENCODED then return nil, "The export is too large." end
    return result
end

local function decode(text)
    if type(text) ~= "string" or #text > MAX_ENCODED or text:sub(1, #PREFIX) ~= PREFIX then
        return nil, "This is not a BindCards BC01 export."
    end
    local payload = text:sub(#PREFIX + 1)
    if payload == "" or payload:find("[^0-9A-Fa-f]") or #payload % 2 ~= 0 then return nil, "The export is damaged." end
    local ok, result = pcall(function()
        local compressed = C_EncodingUtil.DecodeHex(payload)
        local json = C_EncodingUtil.DecompressString(compressed)
        if type(json) ~= "string" or #json > MAX_EXPANDED then error("expanded data too large") end
        return C_EncodingUtil.DeserializeJSON(json)
    end)
    if not ok or type(result) ~= "table" then return nil, "The export could not be read." end
    return result
end

local function decodeEnvelope(text)
    local envelope, message = decode(text)
    if not envelope then return nil, message end
    if envelope.client ~= "forever" then return nil, "Import a BindCards Forever export." end
    if not onlyKeys(envelope, { format = true, schemaVersion = true, profile = true, client = true }) or
        envelope.format ~= "BC01" or
        (envelope.schemaVersion ~= 1 and envelope.schemaVersion ~= 2 and envelope.schemaVersion ~= 3 and
            envelope.schemaVersion ~= 4 and envelope.schemaVersion ~= 5 and envelope.schemaVersion ~= EXPORT_SCHEMA_VERSION) then
        return nil, "This BindCards version is not supported."
    end
    return envelope
end

function BindCards:ExportProfile(profileId)
    local profile = profileId and self.db and self.db.profiles[profileId] or nil
    if not profile then return nil, "Choose a General or class binding set to export." end
    local valid, message = validateProfile(profile)
    if not valid then return nil, message end
    return encode({ format = "BC01", client = "forever", schemaVersion = EXPORT_SCHEMA_VERSION, profile = self.CopyTable(profile) })
end

function BindCards:GetImportSummary(text)
    local envelope, message = decodeEnvelope(text)
    if not envelope then return nil, message end
    local valid
    valid, message = validateProfile(envelope.profile, envelope.schemaVersion < 3)
    if not valid then return nil, message end
    local summary = { name = envelope.profile.name, cards = #envelope.profile.cards, tiles = 0, bindings = 0, macros = 0 }
    for _, card in ipairs(envelope.profile.cards) do
        summary.tiles = summary.tiles + #card.tiles
        for _, tile in ipairs(card.tiles) do
            summary.bindings = summary.bindings + #tile.bindings
            if tile.kind == "macro" then summary.macros = summary.macros + 1 end
        end
    end
    return summary
end

function BindCards:ImportProfile(text, selectImported)
    if self:CountProfiles() >= self.MAX_PROFILE_SETS then return nil, "Binding set limit reached." end
    local envelope, message = decodeEnvelope(text)
    if not envelope then return nil, message end
    local valid
    valid, message = validateProfile(envelope.profile, envelope.schemaVersion < 3)
    if not valid then return nil, message end

    -- Fully remap a detached copy before touching SavedVariables.
    local imported = self.CopyTable(envelope.profile)
    for _, card in ipairs(imported.cards) do
        for _, tile in ipairs(card.tiles) do
            for index, key in ipairs(tile.bindings) do
                key = self:NormalizeKey(key)
                if not key then return nil, "The export contains an invalid key." end
                tile.bindings[index] = key
            end
        end
    end
    local originalNextId, originalUsedIds = self.db.nextId, self.CopyTable(self.usedIds or {})
    local originalProfiles = self.CopyTable(self.db.profiles)
    local originalSelections = self.CopyTable(self.db.selections)
    local originalSelectedProfileId = self.db.selectedProfileId
    local profileId = self:NewID("profile")
    local cardIds = {}
    for _, card in ipairs(imported.cards) do
        local oldId = card.id
        card.id = self:NewID("card")
        cardIds[oldId] = card.id
        local condition, retiredLoadout = self.StripTalentLoadoutCondition(card.condition)
        local normalized, conditionValid = self:NormalizeCondition(condition, false)
        if not conditionValid then return nil, "The export contains an invalid card condition." end
        card.condition = normalized
        if retiredLoadout then card.enabled = false end
        for tileIndex, tile in ipairs(card.tiles) do
            tile.id = self:NewID("tile")
            local oldSlot = tile.order or tileIndex
            tile.gridX = tile.gridX or ((oldSlot - 1) % (card.columns or 6) + 1)
            tile.gridY = tile.gridY or (math.floor((oldSlot - 1) / (card.columns or 6)) + 1)
            tile.order = (tile.gridY - 1) * self.MAX_COLUMNS + tile.gridX
        end
    end
    for _, card in ipairs(imported.cards) do
        card.parentId = card.parentId and cardIds[card.parentId] or nil
        card.homeParentId = card.homeParentId and cardIds[card.homeParentId] or nil
        if card.parentId then
            card.binderId = nil
        else
            local customRootId = type(card.binderId) == "string" and card.binderId:match("^custom:(.+)$")
            if customRootId and cardIds[customRootId] then card.binderId = "custom:" .. cardIds[customRootId] end
        end
    end
    for _, card in ipairs(imported.cards) do
        if not card.parentId and not card.binderId then card.binderId = self:GetCardBinderId(card, imported) end
    end
    local buckets = {}
    local preferredBinderId = imported.binderId
    if imported.binderId then
        buckets[imported.binderId] = imported.cards
    else
        local meaningful = {}
        for _, card in ipairs(imported.cards) do
            local binderId = self:GetCardBinderId(card, imported) or self.GENERAL_BINDER_ID
            local classFile = binderId:match("^class:([A-Z]+)$")
            local scope = classFile and VALID_CLASSES[classFile] and binderId or self.GENERAL_BINDER_ID
            buckets[scope] = buckets[scope] or {}
            buckets[scope][#buckets[scope] + 1] = card
            if #(card.tiles or {}) > 0 or not (type(card.templateKey) == "string" and
                card.templateKey:match("^default:")) then meaningful[scope] = true end
        end
        local currentClass = self:GetCurrentClassFile()
        for binderId in pairs(buckets) do
            if binderId ~= self.GENERAL_BINDER_ID and not meaningful[binderId] and
                binderId ~= "class:" .. tostring(currentClass or "") then
                buckets[binderId] = nil
            end
        end
        local currentBinderId = "class:" .. tostring(self:GetCurrentClassFile() or "")
        if buckets[self.GENERAL_BINDER_ID] and #buckets[self.GENERAL_BINDER_ID] > 0 then
            preferredBinderId = self.GENERAL_BINDER_ID
        elseif buckets[currentBinderId] then
            preferredBinderId = currentBinderId
        end
        buckets[self.GENERAL_BINDER_ID] = buckets[self.GENERAL_BINDER_ID] or {}
    end

    local binderIds = {}
    for binderId in pairs(buckets) do binderIds[#binderIds + 1] = binderId end
    table.sort(binderIds, function(left, right)
        if left == self.GENERAL_BINDER_ID then return true end
        if right == self.GENERAL_BINDER_ID then return false end
        return left < right
    end)
    if self:CountProfiles() + #binderIds > self.MAX_PROFILE_SETS then
        self.db.nextId, self.usedIds = originalNextId, originalUsedIds
        return nil, "Binding set limit reached."
    end
    for _, binderId in ipairs(binderIds) do
        if self:CountProfiles(binderId) >= self.MAX_PROFILES then
            self.db.nextId, self.usedIds = originalNextId, originalUsedIds
            return nil, "That General or class library is full."
        end
    end

    local installed = {}
    local function rollback(reason)
        self.db.profiles = originalProfiles
        self.db.selections = originalSelections
        self.db.selectedProfileId = originalSelectedProfileId
        self.db.nextId, self.usedIds = originalNextId, originalUsedIds
        return nil, reason
    end
    for index, binderId in ipairs(binderIds) do
        local set = {
            id = index == 1 and profileId or self:NewID("profile"),
            name = self:UniqueProfileName(imported.name .. " (Imported)", nil, binderId),
            binderId = binderId,
            cards = buckets[binderId],
            createdAt = time and time() or 0,
            updatedAt = time and time() or 0,
            bindingsEnabled = false,
        }
        self.db.profiles[set.id] = set
        local ensured, ensureMessage = self:EnsureProfileTemplates(set.id)
        if not ensured then return rollback(ensureMessage) end
        installed[#installed + 1] = set
    end
    if selectImported ~= false then
        local currentClass = self:GetCurrentClassFile()
        for _, set in ipairs(installed) do
            if set.binderId == self.GENERAL_BINDER_ID or set.binderId == "class:" .. tostring(currentClass or "") then
                self:SelectProfile(set.id)
            end
        end
    end
    local primary = installed[1]
    for _, set in ipairs(installed) do
        if set.binderId == preferredBinderId then primary = set break end
    end
    self:Fire("PROFILES_CHANGED", primary and primary.id)
    self:RequestRecompile("profile-imported")
    return primary, installed
end

BindCards.EXPORT_PREFIX = PREFIX
BindCards.EXPORT_SCHEMA_VERSION = EXPORT_SCHEMA_VERSION
