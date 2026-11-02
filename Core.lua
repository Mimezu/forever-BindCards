local ADDON_NAME, BindCards = ...

_G.BindCards = BindCards

BindCards.ADDON_NAME = ADDON_NAME
BindCards.IS_FOREVER = true
BindCards.CLASS_IDS = { 1, 2, 3, 4, 5, 7, 8, 9, 11 }
BindCards.CLASS_FILES = { [1]="WARRIOR", [2]="PALADIN", [3]="HUNTER", [4]="ROGUE", [5]="PRIEST", [7]="SHAMAN", [8]="MAGE", [9]="WARLOCK", [11]="DRUID" }
BindCards.SCHEMA_VERSION = 3
BindCards.MAX_PROFILES = 64
BindCards.MAX_PROFILE_SETS = 1024
BindCards.MAX_CARDS = 512
BindCards.MAX_TILES = 4096
BindCards.MIN_COLUMNS = 3
BindCards.MAX_COLUMNS = 12
BindCards.GENERAL_BINDER_ID = "general"
-- One set per character (owner = character GUID); wins over class and General.
BindCards.CHARACTER_BINDER_ID = "character"
BindCards.VALID_UI_THEMES = {
    eui = true, mimezu = true, luminous = true, charcoal = true, chalk = true,
    tungsten = true, editorial = true, snes = true, famicom = true, violetmist = true, violetbloom = true,
    gamecube = true, genesis = true, ps1 = true, ps2 = true,
    xbox = true, xbox360 = true, legacy = true,
}
BindCards.VALID_CLASSES = {}
for _, class in pairs(BindCards.CLASS_FILES) do BindCards.VALID_CLASSES[class] = true end
-- Spell drops default to exact ranks; highestRank is an explicit per-tile opt-in.
BindCards.SPELL_ID_ALIASES = {}
BindCards.callbacks = BindCards.callbacks or {}

local DB_DEFAULTS = {
    schemaVersion = BindCards.SCHEMA_VERSION,
    nextId = 1,
    profiles = {},
    selections = {
        defaults = { generalProfileId = nil, classProfileIds = {} },
        characters = {},
    },
    settings = {
        uiScale = 1.0,
        iconSize = 36,
        workspaceMode = "binder",
        selectedBinderKey = "class",
        theme = "eui",
        defaultProfileId = nil,
        windowWidth = 580,
        windowHeight = 520,
        windowManualSize = false,
        windowX = nil,
        windowY = nil,
        binderWidth = 580,
        binderHeight = 300,
        binderManualSize = false,
        gatherLooseSheets = true,
        suspendBindPad = false,
        showAbilityNames = true,
        experimentalBinderStrings = true,
        experimentalColorPass = true,
        experimentalCardSizing = true,
        legacyBindingsRestored = false,
        bindingRestore = {},
    },
}

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$")
end

local function numberOr(value, fallback)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return fallback end
    return number
end

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[copy(key, seen)] = copy(child, seen)
    end
    return result
end

BindCards.CopyTable = copy

function BindCards:IsValidTemplateKey(templateKey, condition)
    local normalized, valid = self:NormalizeCondition(condition, false)
    if not valid then return false end
    if templateKey == "default:general" or templateKey == "default:character" then
        return not normalized.class and not normalized.specGroup and not normalized.form and normalized.content == "ANY"
    end
    local class = type(templateKey) == "string" and templateKey:match("^default:class:([A-Z]+)$")
    if class then
        return self.VALID_CLASSES[class] == true and normalized.class == class and
            not normalized.specGroup and not normalized.form and normalized.content == "ANY"
    end
    local groupClass = tostring(templateKey):match("^default:specgroup:([A-Z]+):[12]$")
    -- Build cards (Primary/Secondary) are created with a Build rule but the
    -- player may rename them, change or remove their rules and switch them
    -- off (e.g. after a respec). Their identity is the key; only the class
    -- must still match. Peeling/moving materializes the inherited class.
    return groupClass ~= nil and self.VALID_CLASSES[groupClass] == true and
        (normalized.class == nil or normalized.class == groupClass)
end

-- Primary/Secondary: generated, never deleted, but otherwise editable.
function BindCards:IsBuildCard(card)
    local templateKey = type(card) == "table" and card.templateKey
    return type(templateKey) == "string" and templateKey:match("^default:specgroup:[A-Z]+:[12]$") ~= nil
end

function BindCards:RefreshClassCatalog()
    -- Class IDs are sparse; the nine-class count is not a maximum class ID.
    for _, class in pairs(self.CLASS_FILES) do self.VALID_CLASSES[class] = true end
end

function BindCards:NewID(kind)
    local rawRealm = GetRealmName and GetRealmName() or "realm"
    if issecretvalue and issecretvalue(rawRealm) then rawRealm = "realm" end
    local realm = tostring(rawRealm):gsub("[^%w]", "")
    local guid = UnitGUID and UnitGUID("player") or "player"
    if issecretvalue and issecretvalue(guid) then guid = "player" end
    local tail = tostring(guid):match("([^%-]+)$") or "player"
    self.usedIds = self.usedIds or {}
    local id
    repeat
        local sequence = math.max(1, math.floor(numberOr(self.db.nextId, 1)))
        self.db.nextId = sequence + 1
        id = string.format("bc-%s-%s-%s-%x", kind or "id", realm, tail, sequence)
    until not self.usedIds[id]
    self.usedIds[id] = true
    return id
end

function BindCards:CountProfiles(binderId)
    local count = 0
    for _, profile in pairs(self.db and self.db.profiles or {}) do
        if not binderId or profile.binderId == binderId then count = count + 1 end
    end
    return count
end

function BindCards:CountTiles(profile)
    local count = 0
    for _, card in ipairs(profile and profile.cards or {}) do count = count + #(card.tiles or {}) end
    return count
end

function BindCards:UniqueProfileName(name, exceptId, binderId)
    name = trim(name)
    if name == "" then name = "New profile" end
    name = name:sub(1, 64)
    local used = {}
    for id, profile in pairs(self.db.profiles or {}) do
        if id ~= exceptId and (not binderId or profile.binderId == binderId) and
            type(profile.name) == "string" then
            used[profile.name:lower()] = true
        end
    end
    if not used[name:lower()] then return name end
    local base, suffix = name:sub(1, 57), 2
    local candidate
    repeat
        candidate = string.format("%s (%d)", base, suffix):sub(1, 64)
        suffix = suffix + 1
    until not used[candidate:lower()]
    return candidate
end

function BindCards:RegisterCallback(event, func, owner)
    if type(event) ~= "string" or type(func) ~= "function" then return false end
    self.callbacks[event] = self.callbacks[event] or {}
    self.callbacks[event][#self.callbacks[event] + 1] = { func = func, owner = owner }
    return true
end

function BindCards:UnregisterCallbacks(owner)
    for event, entries in pairs(self.callbacks) do
        for index = #entries, 1, -1 do
            if entries[index].owner == owner then table.remove(entries, index) end
        end
        if #entries == 0 then self.callbacks[event] = nil end
    end
end

function BindCards:Fire(event, ...)
    local entries = self.callbacks[event]
    if not entries then return end
    for index = 1, #entries do
        local entry = entries[index]
        local ok, message = pcall(entry.func, entry.owner, ...)
        if not ok then geterrorhandler()(message) end
    end
end

function BindCards:Notify(message)
    local text = tostring(message or "")
    if text == "" then return end
    print("|cff55b8d6BindCards:|r " .. text)
    self:Fire("NOTIFICATION", text)
end

function BindCards:GetCurrentClassFile()
    local classFile = UnitClass and select(2, UnitClass("player")) or nil
    if issecretvalue and issecretvalue(classFile) then return nil end
    return type(classFile) == "string" and self.VALID_CLASSES[classFile] and classFile or nil
end

function BindCards:GetCurrentCharacterKey()
    local guid = UnitGUID and UnitGUID("player") or nil
    if issecretvalue and issecretvalue(guid) then return nil end
    return type(guid) == "string" and guid ~= "" and guid or nil
end

function BindCards:GetProfiles(binderId)
    local profiles = self.db and self.db.profiles or {}
    if not binderId then return profiles end
    local filtered = {}
    for id, profile in pairs(profiles) do
        if profile.binderId == binderId then filtered[id] = profile end
    end
    return filtered
end

function BindCards:GetProfile(profileId)
    if not self.db then return nil end
    if profileId then return self.db.profiles[profileId] end
    return self:GetActiveProfile()
end

function BindCards:GetSelectedProfileSet(binderId)
    if not self.db or type(binderId) ~= "string" then return nil end
    local selections = self.db.selections or {}
    local defaults = selections.defaults or {}
    local characterKey = self:GetCurrentCharacterKey()
    local character = characterKey and selections.characters and selections.characters[characterKey] or nil
    local classFile = binderId:match("^class:(.+)$")
    local selectedId
    if binderId == self.CHARACTER_BINDER_ID then
        -- Never fall back to another character's set.
        if not characterKey then return nil end
        local selected = character and character.characterProfileId and self.db.profiles[character.characterProfileId]
        if selected and selected.binderId == binderId and selected.ownerKey == characterKey then return selected end
        for _, profile in pairs(self.db.profiles) do
            if profile.binderId == binderId and profile.ownerKey == characterKey then return profile end
        end
        return nil
    elseif binderId == self.GENERAL_BINDER_ID then
        selectedId = character and character.generalProfileId or defaults.generalProfileId
    elseif classFile then
        selectedId = character and character.classProfileIds and character.classProfileIds[classFile] or
            (defaults.classProfileIds and defaults.classProfileIds[classFile])
    end
    local selected = selectedId and self.db.profiles[selectedId]
    if selected and selected.binderId == binderId then return selected end

    local candidates = {}
    for _, profile in pairs(self.db.profiles) do
        if profile.binderId == binderId then candidates[#candidates + 1] = profile end
    end
    table.sort(candidates, function(left, right)
        if (left.createdAt or 0) ~= (right.createdAt or 0) then
            return (left.createdAt or 0) < (right.createdAt or 0)
        end
        return left.id < right.id
    end)
    return candidates[1]
end

function BindCards:GetSelectedProfileSets(context)
    context = context or (self.GetPlayerContext and self:GetPlayerContext()) or {}
    local classFile = context.class or self:GetCurrentClassFile()
    local general = self:GetSelectedProfileSet(self.GENERAL_BINDER_ID)
    local class = classFile and self:GetSelectedProfileSet("class:" .. classFile) or nil
    local character = self:GetSelectedProfileSet(self.CHARACTER_BINDER_ID)
    return general, class, character
end

function BindCards:GetActiveProfile()
    local general, class, character = self:GetSelectedProfileSets()
    if not general and not class then return nil end
    local cards = {}
    local function append(source)
        for _, card in ipairs(source and source.cards or {}) do cards[#cards + 1] = card end
    end
    append(general)
    append(class)
    append(character)
    return {
        id = "active-composite",
        name = general and class and (general.name .. " / " .. class.name) or
            ((general or class) and (general or class).name or "Binding sets"),
        cards = cards,
        bindingsEnabled = true,
        isComposite = true,
        sourceProfiles = { general, class, character },
    }
end

function BindCards:GetSelectedProfile()
    return self:GetActiveProfile()
end

function BindCards:GetActiveProfileName()
    local profile = self:GetActiveProfile()
    return profile and profile.name
end

function BindCards:GetProfileNames()
    local names = {}
    for _, profile in pairs(self:GetProfiles() or {}) do names[#names + 1] = profile.name end
    table.sort(names, function(left, right) return left:lower() < right:lower() end)
    return names
end

function BindCards:SetProfile(nameOrId)
    if self.db.profiles[nameOrId] then return self:SelectProfile(nameOrId) end
    local wanted = trim(nameOrId):lower()
    if wanted == "" then return false, "Enter a profile name." end
    local focused = self.db.profiles[self.db.selectedProfileId]
    local wantedBinder = focused and focused.binderId or self.GENERAL_BINDER_ID
    for id, profile in pairs(self.db.profiles) do
        if profile.binderId == wantedBinder and profile.name:lower() == wanted then
            return self:SelectProfile(id)
        end
    end
    return self:CreateProfile(nameOrId, nil, wantedBinder)
end

function BindCards:CreateOrSwitchProfile(name) return self:SetProfile(name) end

function BindCards:RenameProfile(profileId, name)
    local profile = self:GetProfile(profileId)
    name = trim(name)
    if not profile then return false, "Profile not found." end
    if name == "" then return false, "Enter a profile name." end
    name = name:sub(1, 64)
    for id, candidate in pairs(self.db.profiles) do
        if id ~= profileId and candidate.binderId == profile.binderId and
            candidate.name:lower() == name:lower() then
            return false, "That profile name is already used."
        end
    end
    profile.name = name
    self:TouchProfile(profile)
    self:Fire("PROFILES_CHANGED", profileId)
    return true
end

function BindCards:GetCards(profileId)
    local profile = self:GetProfile(profileId)
    return profile and profile.cards or {}
end

function BindCards:GetCard(cardId, profileId)
    local _, card = self:FindCardOwner(cardId, profileId)
    return card
end

function BindCards:CreateProfile(name, source, binderId)
    if source ~= nil then
        if type(source) == "table" and source.id and self.db.profiles[source.id] == source then
            return self:CopyProfile(source.id, name)
        end
        return nil, "Profile copies must use an installed source profile."
    end
    binderId = self:NormalizeBinderId(binderId) or self.GENERAL_BINDER_ID
    local classFile = binderId:match("^class:(.+)$")
    if binderId ~= self.GENERAL_BINDER_ID and binderId ~= self.CHARACTER_BINDER_ID and
        not (classFile and self.VALID_CLASSES[classFile]) then
        return nil, "Choose a valid General or class library."
    end
    if self:CountProfiles(binderId) >= self.MAX_PROFILES or self:CountProfiles() >= self.MAX_PROFILE_SETS then
        return nil, "Binding set limit reached."
    end
    local previousSelectedProfileId = self.db.selectedProfileId
    local originalNextId, originalUsedIds = self.db.nextId, copy(self.usedIds or {})
    name = trim(name)
    if name == "" then name = "New profile" end
    local id = self:NewID("profile")
    local profile = {
        id = id,
        name = self:UniqueProfileName(name, nil, binderId),
        binderId = binderId,
        cards = {},
        bindingsEnabled = true,
    }
    profile.createdAt = time and time() or 0
    profile.updatedAt = profile.createdAt
    self.db.profiles[id] = profile
    self.db.selectedProfileId = id
    if type(self.EnsureProfileTemplates) == "function" then
        local ensured, message = self:EnsureProfileTemplates(id)
        if not ensured then
            self.db.profiles[id] = nil
            self.db.selectedProfileId = previousSelectedProfileId
            self.db.nextId, self.usedIds = originalNextId, originalUsedIds
            return nil, message
        end
    end
    self:SelectProfile(id)
    self:Fire("PROFILES_CHANGED", id)
    return profile
end

function BindCards:CreateProfileSet(binderId, name, sourceId)
    if sourceId then return self:CopyProfile(sourceId, name) end
    return self:CreateProfile(name, nil, binderId)
end

function BindCards:CopyProfile(profileId, name)
    local source = self:GetProfile(profileId)
    if not source then return nil, "Profile not found." end
    if self:CountProfiles(source.binderId) >= self.MAX_PROFILES or self:CountProfiles() >= self.MAX_PROFILE_SETS then
        return nil, "Binding set limit reached."
    end
    local originalNextId, originalUsedIds = self.db.nextId, copy(self.usedIds or {})
    local clone = copy(source)
    clone.id = self:NewID("profile")
    clone.name = self:UniqueProfileName(name or (source.name .. " Copy"), nil, source.binderId)
    clone.createdAt = time and time() or 0
    clone.updatedAt = clone.createdAt
    local cardIds = {}
    for index, card in ipairs(clone.cards) do
        local oldId = card.id
        card.id = self:NewID("card")
        cardIds[oldId] = card.id
        card.order = card.order or index
        for tileIndex, tile in ipairs(card.tiles or {}) do
            tile.id = self:NewID("tile")
            tile.order = tile.order or tileIndex
        end
    end
    for _, card in ipairs(clone.cards) do
        card.parentId = card.parentId and cardIds[card.parentId] or nil
        card.homeParentId = card.homeParentId and cardIds[card.homeParentId] or nil
        local customRootId = type(card.binderId) == "string" and card.binderId:match("^custom:(.+)$")
        if not card.parentId and customRootId and cardIds[customRootId] then
            card.binderId = "custom:" .. cardIds[customRootId]
        end
    end
    self.db.profiles[clone.id] = clone
    local ensured, message = self:EnsureProfileTemplates(clone.id)
    if not ensured then
        self.db.profiles[clone.id] = nil
        self.db.nextId, self.usedIds = originalNextId, originalUsedIds
        return nil, message
    end
    self:TouchProfile(clone)
    self:SelectProfile(clone.id)
    self:Fire("PROFILES_CHANGED", clone.id)
    return clone
end

function BindCards:DeleteProfile(profileId)
    local removed = self.db.profiles[profileId]
    if not removed then return false, "Binding set not found." end
    if removed.binderId == self.CHARACTER_BINDER_ID then return false, "Character cards can't be deleted." end
    if self:CountProfiles(removed.binderId) <= 1 then return false, "Keep at least one set in this library." end
    self.db.profiles[profileId] = nil
    local fallback = self:GetSelectedProfileSet(removed.binderId)
    if not fallback then
        for _, candidate in pairs(self.db.profiles) do
            if candidate.binderId == removed.binderId then fallback = candidate; break end
        end
    end
    local selections = self.db.selections or {}
    local function Replace(record)
        if type(record) ~= "table" then return end
        if removed.binderId == self.GENERAL_BINDER_ID then
            if record.generalProfileId == profileId then record.generalProfileId = fallback and fallback.id end
        else
            local classFile = removed.binderId:match("^class:(.+)$")
            record.classProfileIds = record.classProfileIds or {}
            if record.classProfileIds[classFile] == profileId then
                record.classProfileIds[classFile] = fallback and fallback.id
            end
        end
    end
    Replace(selections.defaults)
    for _, record in pairs(selections.characters or {}) do Replace(record) end
    if self.db.selectedProfileId == profileId then self.db.selectedProfileId = fallback and fallback.id end
    if self.db.settings.defaultProfileId == profileId then self.db.settings.defaultProfileId = fallback and fallback.id end
    self:Fire("PROFILES_CHANGED", self.db.selectedProfileId)
    self:Fire("PROFILE_SELECTED", self.db.selectedProfileId, removed.binderId)
    self:Fire("ProfileChanged", self.db.selectedProfileId, removed.binderId)
    self:RequestRecompile("profile-deleted")
    return true
end

function BindCards:SelectProfile(profileId)
    local profile = self.db.profiles[profileId]
    if not profile then return false, "Binding set not found." end
    local ensured, ensureMessage = self:EnsureProfileTemplates(profileId)
    if not ensured then return false, ensureMessage end
    self.db.selections = self.db.selections or { defaults = {}, characters = {} }
    self.db.selections.defaults = self.db.selections.defaults or { classProfileIds = {} }
    self.db.selections.defaults.classProfileIds = self.db.selections.defaults.classProfileIds or {}
    self.db.selections.characters = self.db.selections.characters or {}
    local classFile = profile.binderId and profile.binderId:match("^class:(.+)$")
    local characterKey = self:GetCurrentCharacterKey()
    if profile.binderId == self.GENERAL_BINDER_ID then
        if not characterKey or not self.db.selections.defaults.generalProfileId then
            self.db.selections.defaults.generalProfileId = profileId
        end
    elseif classFile then
        if not characterKey or not self.db.selections.defaults.classProfileIds[classFile] then
            self.db.selections.defaults.classProfileIds[classFile] = profileId
        end
    else
        return false, "This binding set has no valid library."
    end
    local currentClass = self:GetCurrentClassFile()
    if characterKey and (profile.binderId == self.GENERAL_BINDER_ID or classFile == currentClass) then
        local record = self.db.selections.characters[characterKey]
        if type(record) ~= "table" then
            record = { classProfileIds = {} }
            self.db.selections.characters[characterKey] = record
        end
        record.classProfileIds = record.classProfileIds or {}
        if profile.binderId == self.GENERAL_BINDER_ID then record.generalProfileId = profileId
        else record.classProfileIds[classFile] = profileId end
    end
    self.db.selectedProfileId = profileId
    self:Fire("PROFILE_SELECTED", profileId, profile.binderId)
    self:Fire("ProfileChanged", profileId, profile.binderId)
    if profile.binderId == self.GENERAL_BINDER_ID or classFile == currentClass then
        self:RequestRecompile("profile-selected")
    end
    return true
end

function BindCards:SelectProfileSet(profileId) return self:SelectProfile(profileId) end

function BindCards:SetProfileBindingsEnabled(profileId, enabled)
    local profile = self:GetProfile(profileId)
    if not profile then return false, "Profile not found." end
    profile.bindingsEnabled = enabled == true
    self:TouchProfile(profile)
    self:RequestRecompile("profile-bindings-toggled")
    return true
end

function BindCards:CreateUndoSnapshot(profileId)
    local profile = self:GetProfile(profileId)
    if not profile then return nil, "Undo data is unavailable." end
    if profile.isComposite then
        local profiles = {}
        for _, source in pairs(profile.sourceProfiles or {}) do
            if source and source.id then profiles[source.id] = copy(source) end
        end
        return {
            profiles = profiles,
            selectedProfileId = self.db.selectedProfileId,
            defaultProfileId = self.db.settings and self.db.settings.defaultProfileId or nil,
        }
    end
    return {
        profileId = profile.id,
        profile = copy(profile),
        selectedProfileId = self.db.selectedProfileId,
        defaultProfileId = self.db.settings and self.db.settings.defaultProfileId or nil,
    }
end

function BindCards:RestoreUndoSnapshot(snapshot)
    if type(snapshot) ~= "table" then return false, "Undo data is unavailable." end
    if InCombatLockdown and InCombatLockdown() then return false, "Undo is unavailable during combat." end

    -- Profile-scoped restores must not roll back unrelated profiles or settings.
    if type(snapshot.profiles) == "table" then
        self.usedIds = self.usedIds or {}
        for profileId, savedProfile in pairs(snapshot.profiles) do
            if type(savedProfile) == "table" then
                local restored = copy(savedProfile)
                restored.id = profileId
                self.db.profiles[profileId] = restored
                self.usedIds[profileId] = true
                for _, card in ipairs(restored.cards or {}) do
                    if card.id then self.usedIds[card.id] = true end
                    for _, tile in ipairs(card.tiles or {}) do
                        if tile.id then self.usedIds[tile.id] = true end
                    end
                end
            end
        end
        if snapshot.selectedProfileId and self.db.profiles[snapshot.selectedProfileId] then
            self.db.selectedProfileId = snapshot.selectedProfileId
        end
        if self.db.settings and (snapshot.defaultProfileId == nil or
            self.db.profiles[snapshot.defaultProfileId]) then
            self.db.settings.defaultProfileId = snapshot.defaultProfileId
        end
        BindCardsDB = self.db
    elseif type(snapshot.profile) ~= "table" then
        if type(snapshot.db) ~= "table" then return false, "Undo data is unavailable." end
        self.db = copy(snapshot.db)
        self.usedIds = copy(snapshot.usedIds or {})
        BindCardsDB = self.db
    else
        local restored = copy(snapshot.profile)
        local restoredProfileId = restored.id or snapshot.profileId
        if type(restoredProfileId) ~= "string" or restoredProfileId == "" then
            return false, "Undo data is unavailable."
        end
        restored.id = restoredProfileId
        self.db.profiles[restoredProfileId] = restored

        self.usedIds = self.usedIds or {}
        self.usedIds[restoredProfileId] = true
        for _, card in ipairs(restored.cards or {}) do
            if card.id then self.usedIds[card.id] = true end
            for _, tile in ipairs(card.tiles or {}) do
                if tile.id then self.usedIds[tile.id] = true end
            end
        end

        local selectedProfileId = snapshot.selectedProfileId
        if selectedProfileId and self.db.profiles[selectedProfileId] then
            self.db.selectedProfileId = selectedProfileId
        elseif not self.db.profiles[self.db.selectedProfileId] then
            self.db.selectedProfileId = restoredProfileId
        end
        if self.db.settings then
            local defaultProfileId = snapshot.defaultProfileId
            if defaultProfileId == nil or self.db.profiles[defaultProfileId] then
                self.db.settings.defaultProfileId = defaultProfileId
            end
        end
        BindCardsDB = self.db
    end
    self:Fire("PROFILES_CHANGED", self.db.selectedProfileId)
    self:Fire("PROFILE_SELECTED", self.db.selectedProfileId)
    self:Fire("ProfileChanged", self.db.selectedProfileId)
    self:Fire("DATA_CHANGED", self.db.selectedProfileId)
    self:Fire("DataChanged", self.db.selectedProfileId)
    self:RequestRecompile("undo")
    return true
end

function BindCards:TouchProfile(profile, changeKind)
    profile = profile or self:GetSelectedProfile()
    if profile then profile.updatedAt = time and time() or 0 end
    if self.templateBatch then return end
    self:Fire("DATA_CHANGED", profile and profile.id, changeKind)
    self:Fire("DataChanged", profile and profile.id, changeKind)
end

function BindCards:FindCard(cardId, ...)
    local supplied = select("#", ...) > 0
    local profile = ...
    if not supplied then profile = self:GetSelectedProfile() end
    if not profile then return nil end
    for index, card in ipairs(profile.cards) do
        if card.id == cardId then return card, index end
    end
end

-- Resolve globally unique card IDs to a real set when callers use the active composite.
function BindCards:FindCardOwner(cardId, profileId)
    local explicit = type(profileId) == "table" and profileId or
        (type(profileId) == "string" and self.db and self.db.profiles[profileId] or nil)
    if explicit then
        local card, index = self:FindCard(cardId, explicit)
        return card and explicit or nil, card, index
    end
    if type(profileId) == "string" and profileId ~= "active-composite" then return nil end
    local visited = {}
    local general, class = self:GetSelectedProfileSets()
    local function find(profile)
        if not profile or visited[profile.id] then return nil end
        visited[profile.id] = true
        local card, index = self:FindCard(cardId, profile)
        if card then return profile, card, index end
    end
    local profile, card, index = find(general)
    if profile then return profile, card, index end
    profile, card, index = find(class)
    if profile then return profile, card, index end
    for _, candidate in pairs(self.db and self.db.profiles or {}) do
        profile, card, index = find(candidate)
        if profile then return profile, card, index end
    end
end

function BindCards:GetMutationProfile(profileId, binderId, parentId)
    local explicit = type(profileId) == "table" and profileId or
        (type(profileId) == "string" and self.db and self.db.profiles[profileId] or nil)
    if explicit then return explicit end
    if type(profileId) == "string" and profileId ~= "active-composite" then return nil end
    if parentId then return self:FindCardOwner(parentId, profileId) end
    binderId = self:NormalizeBinderId(binderId) or self.GENERAL_BINDER_ID
    local classFile = binderId:match("^class:(.+)$")
    if classFile then binderId = "class:" .. classFile
    elseif binderId ~= self.GENERAL_BINDER_ID and binderId ~= self.CHARACTER_BINDER_ID then
        binderId = self.GENERAL_BINDER_ID
    end
    return self:GetSelectedProfileSet(binderId)
end

function BindCards:NormalizeBinderId(binderId)
    if binderId == self.GENERAL_BINDER_ID or binderId == self.CHARACTER_BINDER_ID then return binderId end
    if type(binderId) ~= "string" or #binderId > 160 then return nil end
    local class = binderId:match("^class:([A-Z]+)$")
    if class and self.VALID_CLASSES[class] then return binderId end
    if binderId:match("^custom:.+$") then return binderId end
end

local function inferredRootBinderId(addon, card)
    local condition = card and card.condition or {}
    local templateKey = card and card.templateKey
    if type(templateKey) == "string" and templateKey:match("^default:class:") then
        local binderId = "class:" .. templateKey:sub(15)
        if addon:NormalizeBinderId(binderId) then return binderId end
    end
    if type(condition.class) == "string" and condition.class ~= "" then
        return "class:" .. condition.class
    end
    if templateKey == "default:general" then return addon.GENERAL_BINDER_ID end
    if templateKey == "default:character" then return addon.CHARACTER_BINDER_ID end
    return card and ("custom:" .. card.id) or addon.GENERAL_BINDER_ID
end

function BindCards:GetCardBinderId(cardOrId, profile)
    if type(profile) ~= "table" then profile = self:GetProfile(profile) end
    local card = type(cardOrId) == "table" and cardOrId or self:FindCard(cardOrId, profile)
    if not card then return nil end
    local cardsById, cursor, visited = {}, card, {}
    for _, candidate in ipairs(profile and profile.cards or {}) do cardsById[candidate.id] = candidate end
    while cursor.parentId and cardsById[cursor.parentId] and not visited[cursor.id] do
        visited[cursor.id] = true
        cursor = cardsById[cursor.parentId]
    end
    return self:NormalizeBinderId(cursor.binderId) or inferredRootBinderId(self, cursor)
end

function BindCards:GetBinderFamily(cardOrId, profile)
    local binderId = self:GetCardBinderId(cardOrId, profile)
    if not binderId then return nil end
    if binderId == self.CHARACTER_BINDER_ID then return "character" end
    return binderId:match("^class:") and "class" or "general"
end

function BindCards:CanCardUseGlobalPriority(cardOrId, profile)
    if type(profile) ~= "table" then profile = self:GetProfile(profile) end
    local card = type(cardOrId) == "table" and cardOrId or self:FindCard(cardOrId, profile)
    if not card or card.templateKey ~= nil or not (card.parentId or card.homeParentId) then return false end
    return self:GetCardBinderId(card, profile) == self.GENERAL_BINDER_ID
end

function BindCards:CreateCard(values, profileId)
    if type(values) == "string" then
        values, profileId = { name = values, parentId = profileId }, nil
    end
    values = type(values) == "table" and values or {}
    if values.templateKey ~= nil and not self.templateBatch then return nil, "Generated cards are managed by BindCards." end
    if values.homeParentId ~= nil then return nil, "Create the card in its parent before peeling it." end
    values.parentId = values.parentId or values.parentID
    local requestedBinderId = values.binderId
    if not requestedBinderId and not values.parentId and type(values.condition) == "table" and
        type(values.condition.class) == "string" then
        requestedBinderId = "class:" .. values.condition.class
    end
    local profile = self:GetMutationProfile(profileId, requestedBinderId, values.parentId)
    if not profile then return nil, "Profile not found." end
    if not values.parentId and not requestedBinderId then requestedBinderId = profile.binderId end
    if #profile.cards >= self.MAX_CARDS then return nil, "Card limit reached." end
    if values.parentId and not self:FindCard(values.parentId, profile) then
        return nil, "Parent card not found."
    end
    local columns = math.max(self.MIN_COLUMNS, math.min(self.MAX_COLUMNS, numberOr(values.columns, 6)))
    local capacity = math.max(columns, math.min(192, math.floor(numberOr(values.capacity, columns * 2))))
    local condition, conditionValid, conditionMessage = self:NormalizeCondition(values.condition or values.conditions or {}, true)
    if not conditionValid then return nil, conditionMessage end
    if condition.form and not values.parentId then return nil, "Form conditions belong on subcards." end
    if condition.activity and not values.parentId then return nil, "Activity conditions belong on General subcards." end
    if requestedBinderId ~= nil and not self:NormalizeBinderId(requestedBinderId) then
        return nil, "Invalid binder."
    end
    if requestedBinderId ~= nil and values.parentId then return nil, "Only top-level cards own a binder." end
    if profile.binderId and requestedBinderId and requestedBinderId:match("^custom:") == nil and
        profile.binderId ~= requestedBinderId then
        return nil, "Cards must stay in their General or class binding set."
    end
    local effectiveBinderId = requestedBinderId
    if values.parentId then effectiveBinderId = self:GetCardBinderId(values.parentId, profile) end
    local binderClass = effectiveBinderId and effectiveBinderId:match("^class:(.+)$")
    if binderClass then
        if condition.activity then return nil, "Activity cards must belong to the General binder." end
        if condition.class and condition.class ~= binderClass then return nil, "Class binder and condition do not match." end
        if condition.form and not self:IsFormValidForClass(condition.form, binderClass) then
            return nil, "That form is not available in this class binder."
        end
        if not values.parentId then condition.class = binderClass end
    elseif condition.form then
        return nil, "Form cards must belong to a supported class binder."
    elseif condition.activity and effectiveBinderId ~= self.GENERAL_BINDER_ID then
        return nil, "Activity cards must belong to the General binder."
    end
    local overrideAllBindingsWhenActive = values.overrideAllBindingsWhenActive == true
    if overrideAllBindingsWhenActive and
        (values.templateKey ~= nil or not values.parentId or effectiveBinderId ~= self.GENERAL_BINDER_ID) then
        return nil, "Global priority belongs on a user-created General subcard."
    end
    local cardId = self:NewID("card")
    local card = {
        id = cardId,
        name = trim(values.name) ~= "" and trim(values.name):sub(1, 64) or "New card",
        enabled = values.enabled ~= false,
        collapsed = values.collapsed == true,
        treeExpanded = values.treeExpanded == true,
        parentId = values.parentId,
        homeParentId = nil,
        binderId = values.parentId and nil or requestedBinderId,
        order = numberOr(values.order, #profile.cards + 1),
        priority = numberOr(values.priority, 0),
        columns = columns,
        capacity = capacity,
        layoutMode = values.layoutMode == "floating" and "floating" or "stacked",
        floatX = values.floatX and math.max(-10000, math.min(10000, numberOr(values.floatX, 0))) or nil,
        floatY = values.floatY and math.max(-10000, math.min(10000, numberOr(values.floatY, 0))) or nil,
        floatWidth = values.floatWidth and math.max(240, math.min(1200, numberOr(values.floatWidth, 420))) or nil,
        floatHeight = values.floatHeight and math.max(180, math.min(1000, numberOr(values.floatHeight, 360))) or nil,
        paperWidth = values.paperWidth and math.max(300, math.min(720, numberOr(values.paperWidth, 430))) or nil,
        paperHeight = values.paperHeight and math.max(120, math.min(1000, numberOr(values.paperHeight, 260))) or nil,
        templateKey = type(values.templateKey) == "string" and values.templateKey:sub(1, 64) or nil,
        condition = condition,
        overrideAllBindingsWhenActive = overrideAllBindingsWhenActive and true or nil,
        tiles = {},
    }
    if not card.parentId and not card.binderId then card.binderId = inferredRootBinderId(self, card) end
    profile.cards[#profile.cards + 1] = card
    if not self.templateBatch then
        self:TouchProfile(profile)
        self:RequestRecompile("card-created")
    end
    return card
end

local function wouldCreateCycle(addon, card, newParentId, profile)
    local cursor = newParentId
    local visited = {}
    while cursor do
        if cursor == card.id or visited[cursor] then return true end
        visited[cursor] = true
        local parent = addon:FindCard(cursor, profile)
        cursor = parent and (parent.parentId or parent.homeParentId)
    end
    return false
end

local function subtreeClassConflict(addon, cardId, binderClass, profile)
    local byId = {}
    for _, candidate in ipairs(profile.cards or {}) do byId[candidate.id] = candidate end
    for _, candidate in ipairs(profile.cards or {}) do
        local cursor, seen = candidate, {}
        while cursor and (cursor.parentId or cursor.homeParentId) and not seen[cursor.id] do
            seen[cursor.id] = true
            local ownerId = cursor.parentId or cursor.homeParentId
            if ownerId == cardId then
                local class = candidate.condition and candidate.condition.class
                if class and class ~= binderClass then return true end
                local form = candidate.condition and candidate.condition.form
                if form and (not binderClass or not addon:IsFormValidForClass(form, binderClass)) then return true end
                local activity = candidate.condition and candidate.condition.activity
                if activity and binderClass then return true end
                break
            end
            cursor = byId[ownerId]
        end
    end
    return false
end

function BindCards:UpdateCard(cardId, values, profileId)
    local profile, card = self:FindCardOwner(cardId, profileId)
    if not card then return nil, "Card not found." end
    values = type(values) == "table" and values or {}
    if self:IsValidTemplateKey(card.templateKey, card.condition) and not self:IsBuildCard(card) and
        (values.name ~= nil or values.enabled ~= nil) then
        return nil, "Default card identity cannot be changed."
    end
    local pendingCondition
    if values.condition ~= nil or values.conditions ~= nil then
        local valid, message
        pendingCondition, valid, message = self:NormalizeCondition(values.condition or values.conditions, true)
        if not valid then return nil, message end
        if card.templateKey and not self:IsValidTemplateKey(card.templateKey, pendingCondition) then
            return nil, "Default card role, class, or specialization cannot be changed."
        end
    end
    local inheritedBinderId = self:GetCardBinderId(card, profile)
    if values.binderId ~= nil and not self:NormalizeBinderId(values.binderId) then
        return nil, "Invalid binder."
    end
    local intendedParentId = card.parentId
    if values.parentId ~= nil then intendedParentId = values.parentId ~= false and values.parentId or nil end
    local intendedHomeParentId = card.homeParentId
    if values.homeParentId ~= nil then
        intendedHomeParentId = values.homeParentId ~= false and values.homeParentId or nil
        if intendedHomeParentId and not self:FindCard(intendedHomeParentId, profile) then
            return nil, "Home parent card not found."
        end
        if intendedHomeParentId and wouldCreateCycle(self, card, intendedHomeParentId, profile) then
            return nil, "Cards cannot contain themselves."
        end
    end
    if intendedParentId and intendedHomeParentId then
        return nil, "A card cannot be nested and peeled at the same time."
    end
    if values.binderId ~= nil and intendedParentId then return nil, "Only top-level cards own a binder." end
    if values.parentId ~= nil then
        if intendedParentId and not self:FindCard(intendedParentId, profile) then
            return nil, "Parent card not found."
        end
        if wouldCreateCycle(self, card, intendedParentId, profile) then return nil, "Cards cannot contain themselves." end
    end
    local intendedBinderId
    if not intendedParentId then intendedBinderId = values.binderId or card.binderId or inheritedBinderId end
    local effectiveBinderId = intendedBinderId
    if intendedParentId then effectiveBinderId = self:GetCardBinderId(intendedParentId, profile) end
    local intendedLayoutMode = values.layoutMode == nil and card.layoutMode or
        (values.layoutMode == "floating" and "floating" or "stacked")
    if intendedLayoutMode == "floating" and intendedParentId then
        return nil, "Only top-level cards can be detached."
    end
    if intendedHomeParentId then
        if intendedLayoutMode ~= "floating" then
            return nil, "A peeled card must remain floating."
        end
        local homeBinderId = self:GetCardBinderId(intendedHomeParentId, profile)
        if intendedBinderId ~= homeBinderId then
            return nil, "A peeled card must remain in its parent binder."
        end
    end
    local intendedCondition = pendingCondition or card.condition
    if intendedCondition.form and not intendedParentId and not intendedHomeParentId then
        return nil, "Form conditions belong on subcards."
    end
    if intendedCondition.activity and not intendedParentId and not intendedHomeParentId then
        return nil, "Activity conditions belong on General subcards."
    end
    local binderClass = effectiveBinderId and effectiveBinderId:match("^class:(.+)$")
    if binderClass then
        if intendedCondition.activity then return nil, "Activity cards must belong to the General binder." end
        if intendedCondition.class and intendedCondition.class ~= binderClass then
            return nil, "Class binder and condition do not match."
        end
        if not intendedParentId and intendedCondition.class ~= binderClass then
            intendedCondition = self.CopyTable(intendedCondition)
            intendedCondition.class = binderClass
        end
        if intendedCondition.form and not self:IsFormValidForClass(intendedCondition.form, binderClass) then
            return nil, "That form is not available in this class binder."
        end
    elseif intendedCondition.form then
        return nil, "Form cards must belong to a supported class binder."
    elseif intendedCondition.activity and effectiveBinderId ~= self.GENERAL_BINDER_ID then
        return nil, "Activity cards must belong to the General binder."
    end
    local intendedOverride = card.overrideAllBindingsWhenActive == true
    if values.overrideAllBindingsWhenActive ~= nil then
        intendedOverride = values.overrideAllBindingsWhenActive == true
    end
    if intendedOverride and
        (card.templateKey ~= nil or not (intendedParentId or intendedHomeParentId) or
            effectiveBinderId ~= self.GENERAL_BINDER_ID) then
        return nil, "Global priority belongs on a user-created General subcard."
    end
    if subtreeClassConflict(self, card.id, binderClass, profile) then
        return nil, "A nested class condition conflicts with the destination binder."
    end
    if values.parentId ~= nil then
        card.parentId = intendedParentId
        card.binderId = intendedBinderId
        if intendedParentId then card.homeParentId = nil end
    elseif values.binderId ~= nil then
        card.binderId = intendedBinderId
    end
    if values.homeParentId ~= nil then card.homeParentId = intendedHomeParentId end
    if values.name ~= nil then card.name = (trim(values.name) ~= "" and trim(values.name) or "Card"):sub(1, 64) end
    if values.enabled ~= nil then card.enabled = values.enabled == true end
    if values.collapsed ~= nil then card.collapsed = values.collapsed == true end
    if values.treeExpanded ~= nil then card.treeExpanded = values.treeExpanded == true end
    if values.order ~= nil then card.order = numberOr(values.order, card.order) end
    if values.priority ~= nil then card.priority = numberOr(values.priority, card.priority or 0) end
    if values.columns ~= nil then
        card.columns = math.max(self.MIN_COLUMNS, math.min(self.MAX_COLUMNS, numberOr(values.columns, card.columns)))
        card.capacity = math.max(card.columns, card.capacity or card.columns * 2)
    end
    if values.capacity ~= nil then
        card.capacity = math.max(card.columns or self.MIN_COLUMNS,
            math.min(192, math.floor(numberOr(values.capacity, card.capacity or self.MIN_COLUMNS))))
    end
    if values.layoutMode ~= nil then
        card.layoutMode = intendedLayoutMode
    end
    if values.floatX ~= nil then card.floatX = math.max(-10000, math.min(10000, numberOr(values.floatX, 0))) end
    if values.floatY ~= nil then card.floatY = math.max(-10000, math.min(10000, numberOr(values.floatY, 0))) end
    if values.floatWidth ~= nil then
        card.floatWidth = math.max(240, math.min(1200, numberOr(values.floatWidth, card.floatWidth or 420)))
    end
    if values.floatHeight ~= nil then
        card.floatHeight = math.max(180, math.min(1000, numberOr(values.floatHeight, card.floatHeight or 360)))
    end
    if values.paperWidth ~= nil then
        card.paperWidth = math.max(300, math.min(720, numberOr(values.paperWidth, card.paperWidth or 430)))
    end
    if values.paperHeight ~= nil then
        card.paperHeight = math.max(120, math.min(1000, numberOr(values.paperHeight, card.paperHeight or 260)))
    end
    if pendingCondition or intendedCondition ~= card.condition then card.condition = intendedCondition end
    if values.overrideAllBindingsWhenActive ~= nil then
        card.overrideAllBindingsWhenActive = values.overrideAllBindingsWhenActive == true and true or nil
    end
    self:TouchProfile(profile)
    if values.enabled ~= nil or values.parentId ~= nil or values.homeParentId ~= nil or
        values.binderId ~= nil or values.order ~= nil or values.priority ~= nil or
        values.condition ~= nil or values.conditions ~= nil or values.overrideAllBindingsWhenActive ~= nil then
        self:RequestRecompile("card-updated")
    end
    return card
end


local function normalizeCardOrder(profile)
    table.sort(profile.cards, function(left, right)
        if (left.order or 0) ~= (right.order or 0) then return (left.order or 0) < (right.order or 0) end
        return left.id < right.id
    end)
    for index, card in ipairs(profile.cards) do card.order = index end
end

function BindCards:MoveCard(cardId, parentId, targetIndex, profileId)
    local profile, card = self:FindCardOwner(cardId, profileId)
    if not card then return false, "Card not found." end
    if parentId then
        local parentProfile, parent = self:FindCardOwner(parentId, profileId)
        if not parent then return false, "Parent card not found." end
        if parentProfile ~= profile then return false, "Cards cannot move between binding sets." end
    end
    if wouldCreateCycle(self, card, parentId, profile) then return false, "Cards cannot contain themselves." end
    if card.condition.form and not parentId then return false, "Form conditions belong on subcards." end
    if card.condition.activity and not parentId then return false, "Activity conditions belong on General subcards." end
    local inheritedBinderId = self:GetCardBinderId(card, profile)
    local effectiveBinderId = parentId and self:GetCardBinderId(parentId, profile) or inheritedBinderId
    local binderClass = effectiveBinderId and effectiveBinderId:match("^class:(.+)$")
    if binderClass and card.condition.class and card.condition.class ~= binderClass then
        return false, "Class binder and condition do not match."
    end
    if card.condition.form and (not binderClass or not self:IsFormValidForClass(card.condition.form, binderClass)) then
        return false, "That form is not available in the destination binder."
    end
    if card.condition.activity and effectiveBinderId ~= self.GENERAL_BINDER_ID then
        return false, "Activity cards must remain in the General binder."
    end
    if subtreeClassConflict(self, card.id, binderClass, profile) then
        return false, "A nested class condition conflicts with the destination binder."
    end
    normalizeCardOrder(profile)
    card.parentId = parentId
    card.homeParentId = nil
    if parentId then card.binderId = nil else card.binderId = inheritedBinderId end
    if card.overrideAllBindingsWhenActive and
        (not parentId or effectiveBinderId ~= self.GENERAL_BINDER_ID or card.templateKey ~= nil) then
        card.overrideAllBindingsWhenActive = nil
    end
    if not parentId and binderClass and card.condition.class ~= binderClass then
        card.condition = self.CopyTable(card.condition)
        card.condition.class = binderClass
    end
    if parentId then card.layoutMode = "stacked" end
    targetIndex = math.max(1, math.min(#profile.cards, math.floor(tonumber(targetIndex) or card.order)))
    local _, oldIndex = self:FindCard(cardId, profile)
    table.remove(profile.cards, oldIndex)
    table.insert(profile.cards, targetIndex, card)
    for index, item in ipairs(profile.cards) do item.order = index end
    self:TouchProfile(profile)
    self:RequestRecompile("card-moved")
    return true
end

function BindCards:DeleteCard(cardId, profileId)
    local profile, card = self:FindCardOwner(cardId, profileId)
    if not card then return false, "Card not found." end
    if self:IsValidTemplateKey(card.templateKey, card.condition) then
        return false, "Generated profile cards cannot be deleted."
    end
    local removing, changed = { [cardId] = true }, true
    while changed do
        changed = false
        for _, candidate in ipairs(profile.cards) do
            local ownerId = candidate.parentId or candidate.homeParentId
            if ownerId and removing[ownerId] and not removing[candidate.id] then
                removing[candidate.id], changed = true, true
            end
        end
    end
    for index = #profile.cards, 1, -1 do
        if removing[profile.cards[index].id] then table.remove(profile.cards, index) end
    end
    self:TouchProfile(profile)
    self:RequestRecompile("card-deleted")
    return true
end

function BindCards:FindTile(tileId, ...)
    local supplied = select("#", ...) > 0
    local profile = ...
    if not supplied then profile = self:GetSelectedProfile() end
    if not profile then return nil end
    for _, card in ipairs(profile.cards) do
        for index, tile in ipairs(card.tiles or {}) do
            if tile.id == tileId then return tile, card, index end
        end
    end
end

function BindCards:FindTileOwner(tileId, profileId)
    local explicit = type(profileId) == "table" and profileId or
        (type(profileId) == "string" and self.db and self.db.profiles[profileId] or nil)
    if explicit then
        local tile, card, index = self:FindTile(tileId, explicit)
        return tile and explicit or nil, tile, card, index
    end
    if type(profileId) == "string" and profileId ~= "active-composite" then return nil end
    local visited = {}
    local general, class = self:GetSelectedProfileSets()
    local function find(profile)
        if not profile or visited[profile.id] then return nil end
        visited[profile.id] = true
        local tile, card, index = self:FindTile(tileId, profile)
        if tile then return profile, tile, card, index end
    end
    local profile, tile, card, index = find(general)
    if profile then return profile, tile, card, index end
    profile, tile, card, index = find(class)
    if profile then return profile, tile, card, index end
    for _, candidate in pairs(self.db and self.db.profiles or {}) do
        profile, tile, card, index = find(candidate)
        if profile then return profile, tile, card, index end
    end
end

local function tileGridPosition(tile, card, fallback)
    local columns = math.max(BindCards.MIN_COLUMNS, math.min(BindCards.MAX_COLUMNS, tonumber(card.columns) or 6))
    local oldSlot = math.max(1, math.floor(tonumber(tile.order) or fallback or 1))
    local x = math.floor(tonumber(tile.gridX) or ((oldSlot - 1) % columns + 1))
    local y = math.floor(tonumber(tile.gridY) or (math.floor((oldSlot - 1) / columns) + 1))
    return x, y
end

function BindCards:CreateTile(cardId, payload, profileId)
    local profile, card = self:FindCardOwner(cardId, profileId)
    if not card then return nil, "Card not found." end
    if #card.tiles >= 192 then return nil, "This card is full." end
    if self:CountTiles(profile) >= self.MAX_TILES then return nil, "Profile tile limit reached." end
    payload = self:NormalizeTilePayload(payload)
    if not self:IsValidTilePayload(payload) then return nil, "Unsupported spell, item, toy, mount, or macro." end
    local requestedSlot = type(payload) == "table" and tonumber(payload.slot or payload.order) or nil
    requestedSlot = requestedSlot and math.floor(requestedSlot) or nil
    if requestedSlot and (requestedSlot < 1 or requestedSlot > (card.capacity or 192)) then
        return nil, "That grid cell is outside this card."
    end
    local columns = card.columns or 6
    local requestedX = requestedSlot and ((requestedSlot - 1) % columns + 1) or nil
    local requestedY = requestedSlot and (math.floor((requestedSlot - 1) / columns) + 1) or nil
    local occupied = {}
    for fallback, existing in ipairs(card.tiles) do
        local x, y = tileGridPosition(existing, card, fallback)
        occupied[x .. ":" .. y] = true
    end
    if requestedX and occupied[requestedX .. ":" .. requestedY] then return nil, "That grid cell is occupied." end
    if not requestedX then
        for slot = 1, card.capacity or columns * 2 do
            local x = (slot - 1) % columns + 1
            local y = math.floor((slot - 1) / columns) + 1
            if not occupied[x .. ":" .. y] then requestedX, requestedY = x, y; break end
        end
    end
    if not requestedX then return nil, "The visible grid is full." end
    local tile = {
        id = self:NewID("tile"),
        kind = payload.kind,
        spellID = payload.spellID, highestRank = payload.highestRank,
        itemID = payload.itemID,
        macrotext = payload.macrotext,
        name = type(payload.name) == "string" and payload.name:sub(1, 128) or nil,
        icon = type(payload.icon) == "number" and payload.icon == payload.icon and payload.icon < math.huge and payload.icon or nil,
        manualIcon = type(payload.manualIcon) == "number" and payload.manualIcon > 0 and
            payload.manualIcon % 1 == 0 and payload.manualIcon or nil,
        gridX = requestedX,
        gridY = requestedY,
        order = (requestedY - 1) * self.MAX_COLUMNS + requestedX,
        bindings = {},
    }
    card.tiles[#card.tiles + 1] = tile
    self:TouchProfile(profile)
    return tile
end

function BindCards:NormalizeTilePayload(payload)
    if type(payload) ~= "table" then return payload end
    local normalized = copy(payload)
    normalized.kind = normalized.kind or normalized.type
    normalized.highestRank = normalized.kind == "spell" and normalized.highestRank == true or nil
    if normalized.kind == "spell" then
        normalized.spellID = tonumber(normalized.spellID or normalized.id)
        normalized.spellID = self.SPELL_ID_ALIASES[normalized.spellID] or normalized.spellID
    end
    if normalized.kind == "item" then normalized.itemID = tonumber(normalized.itemID or normalized.id) end
    if normalized.kind == "macro" then normalized.macrotext = normalized.macrotext or normalized.body end
    return normalized
end

-- Name lookup follows the client's currently learned rank instead of a saved ID.
function BindCards:GetHighestLearnedSpellID(tile)
    local getter = C_Spell and C_Spell.GetSpellInfo
    if not getter then return nil end
    local base = getter(tile.spellID)
    local info = base and getter(base.name)
    local id = info and tonumber(info.spellID)
    if id and (not IsSpellKnown or IsSpellKnown(id)) then return id end
end

-- With the spellbook hiding low ranks, a drag of the top learned rank means
-- "this spell", so it follows future ranks. Showing all ranks keeps drops exact.
function BindCards:IsGenericSpellDrop(spellID)
    local showAll = C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("ShowAllSpellRanks")
    if showAll ~= false then return false end
    local getter = C_Spell and C_Spell.GetSpellSubtext
    local ok, rank = pcall(getter, spellID)
    if not ok or (issecretvalue and issecretvalue(rank)) or type(rank) ~= "string" or not rank:match("%d") then
        return false
    end
    return self:GetHighestLearnedSpellID({ spellID = spellID }) == spellID
end

function BindCards:SetTileHighestRank(tileId, enabled, profileId)
    local profile, tile = self:FindTileOwner(tileId, profileId)
    if not tile or tile.kind ~= "spell" then return nil, "Spell tile not found." end
    if not enabled and tile.highestRank then
        local id = self:GetHighestLearnedSpellID(tile)
        if not id then return nil, "Current learned rank is unavailable. Open the spellbook and try again." end
        tile.spellID = id
    end
    tile.highestRank = enabled == true or nil
    self:TouchProfile(profile)
    self:RequestRecompile("spell-rank-mode")
    return tile
end

function BindCards:UpdateTile(tileId, values, profileId)
    local profile, tile, card = self:FindTileOwner(tileId, profileId)
    if not tile then return nil, "Tile not found." end
    values = type(values) == "table" and values or {}
    local bindingRelevant = values.bindings ~= nil or
        (tile.kind == "macro" and (values.macrotext ~= nil or values.body ~= nil))
    if values.order ~= nil or values.gridX ~= nil or values.gridY ~= nil then
        local slot = math.floor(tonumber(values.order) or 0)
        local currentX, currentY = tileGridPosition(tile, card)
        local x = math.floor(tonumber(values.gridX) or (slot > 0 and ((slot - 1) % (card.columns or 6) + 1)) or currentX)
        local y = math.floor(tonumber(values.gridY) or (slot > 0 and (math.floor((slot - 1) / (card.columns or 6)) + 1)) or currentY)
        if x < 1 or x > self.MAX_COLUMNS or y < 1 or y > 64 then return nil, "Invalid grid cell." end
        for _, other in ipairs(card.tiles) do
            local ox, oy = tileGridPosition(other, card)
            if other ~= tile and ox == x and oy == y then return nil, "That grid cell is occupied." end
        end
        tile.gridX, tile.gridY = x, y
        tile.order = (y - 1) * self.MAX_COLUMNS + x
    end
    if values.name ~= nil then tile.name = trim(values.name):sub(1, 128) end
    if values.icon ~= nil and type(values.icon) == "number" and values.icon == values.icon and values.icon < math.huge then
        tile.icon = values.icon
    end
    if values.manualIcon ~= nil then
        if values.manualIcon == false then
            tile.manualIcon = nil
        elseif type(values.manualIcon) == "number" and values.manualIcon > 0 and values.manualIcon % 1 == 0 then
            tile.manualIcon = values.manualIcon
        else
            return nil, "Invalid icon ID."
        end
    end
    if tile.kind == "macro" and (values.macrotext ~= nil or values.body ~= nil) then
        local macrotext = values.macrotext or values.body
        if type(macrotext) ~= "string" or macrotext == "" or #macrotext > 1023 then
            return nil, "Invalid macro."
        end
        tile.macrotext = macrotext
    end
    if values.bindings ~= nil then
        if type(values.bindings) ~= "table" then return nil, "Bindings must be a list." end
        tile.bindings = {}
        local seen = {}
        for _, key in ipairs(values.bindings) do
            key = self:NormalizeKey(key)
            if key and not seen[key] and #tile.bindings < 8 then
                seen[key] = true
                tile.bindings[#tile.bindings + 1] = key
            end
        end
    end
    self:TouchProfile(profile)
    if bindingRelevant then self:RequestRecompile("tile-updated") end
    return tile
end

function BindCards:ConvertTileToMacro(tileId, macrotext, name, icon, profileId)
    local profile, tile = self:FindTileOwner(tileId, profileId)
    if not tile then return nil, "Tile not found." end
    if type(macrotext) ~= "string" or macrotext == "" or #macrotext > 1023 then return nil, "Invalid macro." end
    tile.kind = "macro"
    tile.spellID = nil
    tile.highestRank = nil
    tile.itemID = nil
    tile.macrotext = macrotext
    tile.name = trim(name) ~= "" and trim(name):sub(1, 128) or tile.name or "Macro"
    if type(icon) == "number" then tile.icon = icon end
    self:TouchProfile(profile)
    self:RequestRecompile("tile-converted")
    return tile
end

function BindCards:DeleteTile(tileId, profileId)
    local profile, tile, card, index = self:FindTileOwner(tileId, profileId)
    if not index then return false, "Tile not found." end
    local hadBindings = tile.bindings and #tile.bindings > 0
    table.remove(card.tiles, index)
    self:TouchProfile(profile)
    if hadBindings then self:RequestRecompile("tile-deleted") end
    return true
end

function BindCards:MoveTile(tileId, targetCardId, targetIndex, profileId)
    local profile, tile, sourceCard, sourceIndex = self:FindTileOwner(tileId, profileId)
    local targetProfile, targetCard = self:FindCardOwner(targetCardId, profileId)
    if not tile then return false, "Tile not found." end
    if not targetCard then return false, "Target card not found." end
    if targetProfile ~= profile then return false, "Abilities cannot move between binding sets." end
    targetIndex = math.max(1, math.min(targetCard.capacity or 192,
        math.floor(tonumber(targetIndex) or 1)))
    local targetColumns = targetCard.columns or 6
    local targetX = (targetIndex - 1) % targetColumns + 1
    local targetY = math.floor((targetIndex - 1) / targetColumns) + 1
    local displaced
    for _, item in ipairs(targetCard.tiles) do
        local x, y = tileGridPosition(item, targetCard)
        if item ~= tile and x == targetX and y == targetY then displaced = item; break end
    end
    if targetCard ~= sourceCard and #targetCard.tiles >= 192 and not displaced then
        return false, "The target card is full."
    end
    local oldX, oldY = tileGridPosition(tile, sourceCard, sourceIndex)
    -- An occupied destination swaps cells instead of repacking the grid.
    tile.gridX, tile.gridY = targetX, targetY
    tile.order = (targetY - 1) * self.MAX_COLUMNS + targetX
    if displaced then
        displaced.gridX, displaced.gridY = oldX, oldY
        displaced.order = (oldY - 1) * self.MAX_COLUMNS + oldX
        if sourceCard ~= targetCard then
            table.remove(targetCard.tiles, select(3, self:FindTile(displaced.id, profile)))
            sourceCard.tiles[#sourceCard.tiles + 1] = displaced
        end
    end
    if sourceCard ~= targetCard then
        table.remove(sourceCard.tiles, sourceIndex)
        targetCard.tiles[#targetCard.tiles + 1] = tile
    end
    self:TouchProfile(profile)
    if sourceCard ~= targetCard then self:RequestRecompile("tile-moved") end
    return true
end

function BindCards:IsValidTilePayload(payload)
    if type(payload) ~= "table" then return false end
    local function positiveInteger(value)
        return type(value) == "number" and value == value and value > 0 and value < math.huge and value % 1 == 0
    end
    if payload.kind == "spell" then return positiveInteger(payload.spellID) end
    if payload.kind == "item" then return positiveInteger(payload.itemID) end
    if payload.kind == "macro" then
        return type(payload.macrotext) == "string" and payload.macrotext ~= "" and #payload.macrotext <= 1023
    end
    return false
end

function BindCards:IsCardActive(cardId, profileId)
    local profile, card = self:FindCardOwner(cardId, profileId)
    if not card then return false, "Card not found." end
    local _, states = self:GetActiveCards(profile)
    return states[cardId] == true, states[cardId] and nil or "Conditions are not active."
end

function BindCards:GetCursorPayload()
    local cursorType, id, info, extra = GetCursorInfo()
    if issecretvalue and (issecretvalue(cursorType) or issecretvalue(id) or issecretvalue(info) or issecretvalue(extra)) then
        return nil, "That cursor payload is protected."
    end
    if cursorType == "spell" then
        local spellID = tonumber(extra) or tonumber(id)
        if not spellID then return nil, "That spell is unavailable." end
        spellID = self.SPELL_ID_ALIASES[spellID] or spellID
        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        return { kind = "spell", spellID = spellID, name = spellInfo and spellInfo.name, icon = spellInfo and spellInfo.iconID,
            highestRank = self:IsGenericSpellDrop(spellID) or nil }
    elseif cursorType == "item" then
        local itemID = tonumber(id) or (type(info) == "string" and tonumber(info:match("item:(%d+)")))
        if not itemID then return nil, "That item is unavailable." end
        if C_ToyBox and C_ToyBox.GetToyInfo then
            local toyItemID, toyName, toyIcon = C_ToyBox.GetToyInfo(itemID)
            if tonumber(toyItemID) then
                return { kind = "item", itemID = itemID, name = toyName, icon = toyIcon }
            end
        end
        local itemName, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemID)
        return { kind = "item", itemID = itemID, name = itemName, icon = itemIcon }
    elseif cursorType == "toy" then
        local itemID = tonumber(id)
        if not itemID or not C_ToyBox or not C_ToyBox.GetToyInfo then
            return nil, "That toy is unavailable."
        end
        local toyItemID, toyName, toyIcon = C_ToyBox.GetToyInfo(itemID)
        if not tonumber(toyItemID) then return nil, "That toy is unavailable." end
        return { kind = "item", itemID = itemID, name = toyName, icon = toyIcon }
    elseif cursorType == "mount" or cursorType == "summonmount" then
        local mountID = tonumber(id)
        if not mountID or not C_MountJournal or not C_MountJournal.GetMountInfoByID then
            return nil, "That mount is unavailable."
        end
        local mountName, spellID, mountIcon = C_MountJournal.GetMountInfoByID(mountID)
        spellID = tonumber(spellID)
        if type(mountName) ~= "string" or mountName == "" or not spellID then
            return nil, "That mount is unavailable."
        end
        return { kind = "spell", spellID = spellID, name = mountName, icon = mountIcon }
    elseif cursorType == "macro" then
        local macroIndex = tonumber(id)
        local name, icon, body
        if macroIndex then name, icon, body = GetMacroInfo(macroIndex) end
        if not body or body == "" then return nil, "That macro is unavailable." end
        return { kind = "macro", name = name, icon = icon, macrotext = body }
    end
    return nil, "Pick up a spell, item, toy, mount, or macro first."
end

function BindCards:AddCursorToCard(cardId, profileId)
    local payload, message = self:GetCursorPayload()
    if not payload then return nil, message end
    local tile, createMessage = self:CreateTile(cardId, payload, profileId)
    if tile and ClearCursor then ClearCursor() end
    return tile, createMessage
end

local macroIconCache = setmetatable({}, { __mode = "k" })

local function readableMacroValue(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function trimMacroToken(value)
    if type(value) ~= "string" then return nil end
    value = trim(value):gsub("^!", ""):gsub('^"(.-)"$', "%1")
    if value == "" or value:lower() == "null" then return nil end
    return value
end

local function chooseMacroOption(options)
    options = trimMacroToken(options)
    if not options then return nil end
    if SecureCmdOptionParse then
        local ok, selected = pcall(SecureCmdOptionParse, options)
        selected = ok and readableMacroValue(selected) or nil
        if type(selected) == "string" and trim(selected) ~= "" then return trim(selected) end
        if options:find("%[") then return nil end
    end
    -- The secure parser is unavailable in headless tests and some early load
    -- states. This fallback provides a stable preview until the next state
    -- invalidation; the secure parser remains authoritative in game.
    for clause in options:gmatch("[^;]+") do
        local candidate = trim(clause:gsub("^%b[]%s*", ""))
        if candidate ~= "" then return candidate end
    end
end

local MACRO_COMMANDS = {
    cast = "cast", use = "use", castsequence = "castsequence",
    castrandom = "castrandom", userandom = "userandom",
}
for globalName, kind in pairs({
    SLASH_CAST1 = "cast", SLASH_USE1 = "use", SLASH_CASTSEQUENCE1 = "castsequence",
    SLASH_CASTRANDOM1 = "castrandom", SLASH_USERANDOM1 = "userandom",
}) do
    local slash = _G[globalName]
    local command = type(slash) == "string" and slash:match("^/([%a]+)$")
    if command then MACRO_COMMANDS[command:lower()] = kind end
end

local function macroActionFromLine(line)
    local command, options = line:match("^%s*/([%a]+)%s+(.+)$")
    command = command and MACRO_COMMANDS[command:lower()]
    if not command then return nil end
    local selected = chooseMacroOption(options)
    if not selected then return nil end
    if command == "castsequence" then
        selected = selected:gsub("^reset=[^%s]+%s*", "")
        selected = selected:match("^%s*([^,]+)")
    elseif command == "castrandom" or command == "userandom" then
        selected = selected:match("^%s*([^,]+)")
    end
    return trimMacroToken(selected), command
end

local function macroItemIcon(query)
    if not C_Item then return nil end
    local icon = C_Item.GetItemInfoInstant and select(5, C_Item.GetItemInfoInstant(query)) or nil
    if not icon and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(query) end
    if not icon and C_Item.GetItemInfo then icon = select(10, C_Item.GetItemInfo(query)) end
    local itemID = tonumber(query)
    if not icon and itemID and C_Item.RequestLoadItemDataByID then
        BindCards.pendingMacroItemIDs = BindCards.pendingMacroItemIDs or {}
        if not BindCards.pendingMacroItemIDs[itemID] then
            BindCards.pendingMacroItemIDs[itemID] = true
            pcall(C_Item.RequestLoadItemDataByID, itemID)
        end
    end
    return readableMacroValue(icon)
end

local function resolveMacroActionIcon(action, command)
    action = trimMacroToken(action)
    if not action then return nil end
    local lower = action:lower()
    local itemToken = lower:match("^item:(%d+)$")
    local numericAction = tonumber(action)
    local preferItem = command == "use" or command == "userandom" or itemToken ~= nil or
        (command == nil and numericAction and numericAction >= 0 and numericAction <= 19)
    if preferItem then
        local slot = tonumber(action)
        if slot and slot >= 0 and slot <= 19 then
            local icon = GetInventoryItemTexture and
                readableMacroValue(GetInventoryItemTexture("player", slot)) or nil
            local itemID = GetInventoryItemID and
                readableMacroValue(GetInventoryItemID("player", slot)) or nil
            local name = itemID and C_Item and C_Item.GetItemInfo and
                readableMacroValue((C_Item.GetItemInfo(itemID))) or nil
            if icon then return icon, name or action, "inventory", slot end
            return nil, nil, "inventory", slot
        end
        local query = itemToken and tonumber(itemToken) or action
        local icon = macroItemIcon(query)
        if icon then
            local itemID = C_Item and C_Item.GetItemInfoInstant and
                readableMacroValue((C_Item.GetItemInfoInstant(query))) or tonumber(query)
            local name = C_Item and C_Item.GetItemInfo and
                readableMacroValue((C_Item.GetItemInfo(query))) or nil
            return icon, name or action, "item", itemID
        end
    end
    local spellQuery = tonumber(action) or action
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellQuery)
    local spellIcon = info and readableMacroValue(info.iconID)
    if spellIcon then
        return spellIcon, (readableMacroValue(info.name) or action), "spell",
            readableMacroValue(info.spellID) or tonumber(action)
    end
    if not preferItem and C_Item then
        local query = itemToken and tonumber(itemToken) or action
        local itemIcon = macroItemIcon(query)
        if itemIcon then
            local itemID = C_Item.GetItemInfoInstant and
                readableMacroValue((C_Item.GetItemInfoInstant(query))) or tonumber(query)
            local name = C_Item.GetItemInfo and readableMacroValue((C_Item.GetItemInfo(query))) or nil
            return itemIcon, name or action, "item", itemID
        end
    end
end

function BindCards:InvalidateMacroIcons()
    self.macroIconRevision = (tonumber(self.macroIconRevision) or 0) + 1
end

function BindCards:ResolveMacroIcon(tileOrText)
    local tile = type(tileOrText) == "table" and tileOrText or nil
    local macrotext = tile and tile.macrotext or tileOrText
    if type(macrotext) ~= "string" or macrotext == "" then return nil end
    local revision = tonumber(self.macroIconRevision) or 0
    local cached = tile and macroIconCache[tile]
    if cached and cached.text == macrotext and cached.revision == revision then
        return cached.icon, cached.action, cached.targetKind, cached.targetValue
    end

    local lines, tooltipIndex, tooltipOptions = {}, nil, nil
    for line in macrotext:gsub("\r\n", "\n"):gsub("\r", "\n"):gmatch("[^\n]+") do
        lines[#lines + 1] = line
        if not tooltipIndex and line:lower():match("^%s*#showtooltip") then
            tooltipIndex = #lines
            tooltipOptions = line:match("^%s*#[Ss][Hh][Oo][Ww][Tt][Oo][Oo][Ll][Tt][Ii][Pp]%s*(.-)%s*$")
        end
    end

    local icon, action, targetKind, targetValue
    if tooltipIndex and tooltipOptions and tooltipOptions ~= "" then
        local selected = chooseMacroOption(tooltipOptions)
        icon, action, targetKind, targetValue = resolveMacroActionIcon(selected)
    end
    if tooltipIndex and not icon then
        for index = tooltipIndex + 1, #lines do
            local candidate, command = macroActionFromLine(lines[index])
            if candidate then
                icon, action, targetKind, targetValue = resolveMacroActionIcon(candidate, command)
                if icon then break end
            end
        end
    end
    if tile then
        macroIconCache[tile] = {
            text = macrotext, revision = revision, icon = icon, action = action,
            targetKind = targetKind, targetValue = targetValue,
        }
    end
    return icon, action, targetKind, targetValue
end

function BindCards:GetMacroTooltipTarget(tileOrText)
    local _, _, targetKind, targetValue = self:ResolveMacroIcon(tileOrText)
    return targetKind, targetValue
end

function BindCards:GetTileDisplay(tile)
    if not tile then return nil end
    if tile.kind == "spell" then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(tile.spellID)
        return info and info.name or tile.name or ("Spell " .. tile.spellID), info and info.iconID or tile.icon
    elseif tile.kind == "item" then
        local name, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(tile.itemID)
        if (not name or not icon) and C_ToyBox and C_ToyBox.GetToyInfo then
            local _, toyName, toyIcon = C_ToyBox.GetToyInfo(tile.itemID)
            name, icon = name or toyName, icon or toyIcon
        end
        return name or tile.name or ("Item " .. tile.itemID), icon or tile.icon
    elseif tile.kind == "macro" then
        local resolvedIcon = self:ResolveMacroIcon(tile)
        return tile.name or "Macro", tile.manualIcon or resolvedIcon or tile.icon or 134400
    end
end

local function backupDatabase(reason, database)
    BindCardsDBBackup = {
        reason = reason,
        savedAt = time and time() or 0,
        data = copy(database),
    }
end

local function validId(value)
    return type(value) == "string" and value ~= "" and #value <= 128
end

function BindCards:RepairDatabase(database)
    local changed = tonumber(database.schemaVersion) ~= self.SCHEMA_VERSION
    local sourceProfiles = type(database.profiles) == "table" and database.profiles or {}
    local sourceSettings = type(database.settings) == "table" and database.settings or {}
    local sourceSelections = type(database.selections) == "table" and database.selections or {}
    local sourceSelected = database.selectedProfileId
    for key in pairs(database) do
        if key ~= "schemaVersion" and key ~= "nextId" and key ~= "selectedProfileId" and
            key ~= "profiles" and key ~= "selections" and key ~= "settings" then changed = true end
    end
    self.db = {
        schemaVersion = self.SCHEMA_VERSION,
        nextId = math.max(1, math.floor(numberOr(database.nextId, 1))),
        profiles = {},
        selections = { defaults = { classProfileIds = {} }, characters = {} },
        settings = {},
    }
    self.usedIds = {}

    if sourceProfiles ~= database.profiles then changed = true end
    local selectedMap = {}
    local profileCount = 0
    for sourceKey, source in pairs(sourceProfiles) do
        if profileCount >= self.MAX_PROFILE_SETS then changed = true break end
        if type(source) == "table" then
            local oldProfileId = validId(source.id) and source.id or (validId(sourceKey) and sourceKey or nil)
            local profileId = oldProfileId
            if not profileId or self.usedIds[profileId] then profileId, changed = self:NewID("profile"), true else self.usedIds[profileId] = true end
            selectedMap[sourceKey] = profileId
            if source.id ~= nil then selectedMap[source.id] = profileId end
            local profileBinderId = self:NormalizeBinderId(source.binderId)
            local binderClass = profileBinderId and profileBinderId:match("^class:(.+)$")
            if profileBinderId ~= self.GENERAL_BINDER_ID and profileBinderId ~= self.CHARACTER_BINDER_ID and
                not (binderClass and self.VALID_CLASSES[binderClass]) then
                profileBinderId = nil
            end
            -- Character sets keep their owner; without one they cannot be shown.
            local ownerKey = profileBinderId == self.CHARACTER_BINDER_ID and type(source.ownerKey) == "string" and
                source.ownerKey ~= "" and #source.ownerKey <= 128 and source.ownerKey or nil
            local profile = {
                id = profileId,
                name = self:UniqueProfileName(type(source.name) == "string" and source.name or "Recovered profile",
                    nil, profileBinderId),
                binderId = profileBinderId,
                cards = {},
                bindingsEnabled = source.bindingsEnabled ~= false,
                createdAt = numberOr(source.createdAt, 0),
                updatedAt = numberOr(source.updatedAt, 0),
                ownerKey = ownerKey,
                seedRacials = ownerKey and source.seedRacials == true or nil,
            }
            self.db.profiles[profileId] = profile
            profileCount = profileCount + 1

            local cardMap, pending, seenTemplateKeys = {}, {}, {}
            local sourceCards = type(source.cards) == "table" and source.cards or {}
            if sourceCards ~= source.cards then changed = true end
            for cardIndex, sourceCard in ipairs(sourceCards) do
                if #pending >= self.MAX_CARDS then changed = true break end
                if type(sourceCard) == "table" then
                    local sourceCondition, retiredLoadout = self.StripTalentLoadoutCondition(sourceCard.condition or {})
                    local condition, conditionValid = self:NormalizeCondition(sourceCondition, false)
                    if retiredLoadout then changed = true end
                    if conditionValid then
                        local oldCardId = validId(sourceCard.id) and sourceCard.id or nil
                        local cardId = oldCardId
                        if not cardId or self.usedIds[cardId] then cardId, changed = self:NewID("card"), true else self.usedIds[cardId] = true end
                        if oldCardId and not cardMap[oldCardId] then cardMap[oldCardId] = cardId end
                        local columns = math.max(self.MIN_COLUMNS, math.min(self.MAX_COLUMNS, numberOr(sourceCard.columns, 6)))
                        local templateKey = type(sourceCard.templateKey) == "string" and
                            sourceCard.templateKey ~= "" and sourceCard.templateKey:sub(1, 64) or nil
                        if templateKey and (seenTemplateKeys[templateKey] or
                            not self:IsValidTemplateKey(templateKey, condition)) then
                            templateKey, changed = nil, true
                        elseif templateKey then
                            seenTemplateKeys[templateKey] = true
                        end
                        local card = {
                            id = cardId,
                            name = (trim(sourceCard.name) ~= "" and trim(sourceCard.name) or "Recovered card"):sub(1, 64),
                            enabled = not retiredLoadout and sourceCard.enabled ~= false,
                            collapsed = sourceCard.collapsed == true,
                            treeExpanded = sourceCard.treeExpanded == true or
                                (sourceCard.treeExpanded == nil and sourceCard.templateKey == "default:general"),
                            parentId = sourceCard.parentId,
                            homeParentId = sourceCard.homeParentId,
                            binderId = self:NormalizeBinderId(sourceCard.binderId),
                            order = numberOr(sourceCard.order, cardIndex),
                            priority = numberOr(sourceCard.priority, 0),
                            columns = columns,
                            capacity = math.max(columns, math.min(192, math.floor(numberOr(sourceCard.capacity, columns * 2)))),
                            layoutMode = sourceCard.layoutMode == "floating" and "floating" or "stacked",
                            floatX = sourceCard.floatX and math.max(-10000, math.min(10000, numberOr(sourceCard.floatX, 0))) or nil,
                            floatY = sourceCard.floatY and math.max(-10000, math.min(10000, numberOr(sourceCard.floatY, 0))) or nil,
                            floatWidth = sourceCard.floatWidth and math.max(240, math.min(1200, numberOr(sourceCard.floatWidth, 420))) or nil,
                            floatHeight = sourceCard.floatHeight and math.max(180, math.min(1000, numberOr(sourceCard.floatHeight, 360))) or nil,
                            paperWidth = sourceCard.paperWidth and math.max(300, math.min(720, numberOr(sourceCard.paperWidth, 430))) or nil,
                            paperHeight = sourceCard.paperHeight and math.max(120, math.min(1000, numberOr(sourceCard.paperHeight, 260))) or nil,
                            templateKey = templateKey,
                            condition = condition,
                            overrideAllBindingsWhenActive = sourceCard.overrideAllBindingsWhenActive == true and true or nil,
                            tiles = {},
                        }
                        if sourceCard.binderId ~= nil and not card.binderId then changed = true end
                        pending[#pending + 1] = card
                        local sourceTiles = type(sourceCard.tiles) == "table" and sourceCard.tiles or {}
                        local occupiedSlots = {}
                        for tileIndex, sourceTile in ipairs(sourceTiles) do
                            if self:CountTiles(profile) + #card.tiles >= self.MAX_TILES or #card.tiles >= 192 then
                                changed = true
                                break
                            end
                            local payload = self:NormalizeTilePayload(sourceTile)
                            if self:IsValidTilePayload(payload) then
                                if payload.kind == "spell" and tonumber(sourceTile.spellID or sourceTile.id) ~= payload.spellID then
                                    changed = true
                                end
                                local oldSlot = math.max(1, math.floor(numberOr(sourceTile.order, tileIndex)))
                                local requestedX = math.floor(numberOr(sourceTile.gridX, (oldSlot - 1) % columns + 1))
                                local requestedY = math.floor(numberOr(sourceTile.gridY, math.floor((oldSlot - 1) / columns) + 1))
                                local cellKey = requestedX .. ":" .. requestedY
                                if requestedX < 1 or requestedX > self.MAX_COLUMNS or requestedY < 1 or requestedY > 64 or occupiedSlots[cellKey] then
                                    requestedX, requestedY = nil, nil
                                    for y = 1, 64 do
                                        for x = 1, self.MAX_COLUMNS do
                                            if not occupiedSlots[x .. ":" .. y] then requestedX, requestedY = x, y; break end
                                        end
                                        if requestedX then break end
                                    end
                                    changed = true
                                end
                                if not requestedX then changed = true; break end
                                occupiedSlots[requestedX .. ":" .. requestedY] = true
                                local tileId = validId(sourceTile.id) and sourceTile.id or nil
                                if not tileId or self.usedIds[tileId] then tileId, changed = self:NewID("tile"), true else self.usedIds[tileId] = true end
                                local tile = {
                                    id = tileId, kind = payload.kind, spellID = payload.spellID, highestRank = payload.highestRank,
                                    itemID = payload.itemID, macrotext = payload.macrotext,
                                    name = type(payload.name) == "string" and payload.name:sub(1, 128) or nil,
                                    icon = type(payload.icon) == "number" and payload.icon == payload.icon and
                                        payload.icon < math.huge and payload.icon or nil,
                                    manualIcon = type(payload.manualIcon) == "number" and payload.manualIcon > 0 and
                                        payload.manualIcon % 1 == 0 and payload.manualIcon or nil,
                                    gridX = requestedX, gridY = requestedY,
                                    order = (requestedY - 1) * self.MAX_COLUMNS + requestedX, bindings = {},
                                }
                                local seen = {}
                                for _, rawKey in ipairs(type(sourceTile.bindings) == "table" and sourceTile.bindings or {}) do
                                    local key = self:NormalizeKey(rawKey)
                                    if key and not seen[key] and #tile.bindings < 8 then
                                        seen[key], tile.bindings[#tile.bindings + 1] = true, key
                                    else
                                        changed = true
                                    end
                                end
                                card.tiles[#card.tiles + 1] = tile
                            else
                                changed = true
                            end
                        end
                        profile.cards[#profile.cards + 1] = card
                    else
                        changed = true
                    end
                else
                    changed = true
                end
            end
            for _, card in ipairs(profile.cards) do
                if card.parentId then
                    card.parentId = cardMap[card.parentId]
                    if not card.parentId then card.enabled, changed = false, true end
                    if card.parentId and card.layoutMode == "floating" then
                        card.layoutMode, changed = "stacked", true
                    end
                end
                if card.homeParentId then
                    card.homeParentId = cardMap[card.homeParentId]
                    if not card.homeParentId then
                        -- A detached card still inherits its home parent's
                        -- restrictions. Losing that parent must not activate it.
                        card.enabled, card.layoutMode, changed = false, "stacked", true
                    end
                end
            end
            local byId = {}
            for _, card in ipairs(profile.cards) do byId[card.id] = card end
            for _, card in ipairs(profile.cards) do
                if card.parentId and card.homeParentId then
                    card.homeParentId, card.layoutMode, changed = nil, "stacked", true
                elseif card.homeParentId then
                    card.layoutMode = "floating"
                end
                local cursor, seen = card, {}
                while cursor and (cursor.parentId or cursor.homeParentId) do
                    if seen[cursor.id] then
                        if card.homeParentId then
                            card.homeParentId, card.layoutMode = nil, "stacked"
                        else
                            card.parentId = nil
                        end
                        card.enabled, changed = false, true
                        break
                    end
                    seen[cursor.id] = true
                    cursor = byId[cursor.parentId or cursor.homeParentId]
                end
            end
            for _, card in ipairs(profile.cards) do
                if card.parentId then
                    if card.binderId ~= nil then card.binderId, changed = nil, true end
                else
                    local owner, seen = card.homeParentId and byId[card.homeParentId], {}
                    while owner and (owner.parentId or owner.homeParentId) and not seen[owner.id] do
                        seen[owner.id] = true
                        owner = byId[owner.parentId or owner.homeParentId]
                    end
                    local inferred = owner and (self:NormalizeBinderId(owner.binderId) or
                        inferredRootBinderId(self, owner)) or card.binderId or inferredRootBinderId(self, card)
                    local oldCustomId = inferred:match("^custom:(.+)$")
                    if oldCustomId and cardMap[oldCustomId] then inferred = "custom:" .. cardMap[oldCustomId] end
                    if card.binderId ~= inferred then card.binderId, changed = inferred, true end
                end
            end
            for _, card in ipairs(profile.cards) do
                local cursor, seen = card, {}
                while cursor and (cursor.parentId or cursor.homeParentId) and
                    byId[cursor.parentId or cursor.homeParentId] and not seen[cursor.id] do
                    seen[cursor.id] = true
                    cursor = byId[cursor.parentId or cursor.homeParentId]
                end
                local effectiveBinderId = cursor and (self:NormalizeBinderId(cursor.binderId) or
                    inferredRootBinderId(self, cursor))
                local effectiveClass = effectiveBinderId and effectiveBinderId:match("^class:(.+)$")
                if effectiveClass and card.condition.class and card.condition.class ~= effectiveClass then
                    card.condition.class, changed = effectiveClass, true
                end
                if card.condition.form and ((not card.parentId and not card.homeParentId) or
                    not effectiveClass or not self:IsFormValidForClass(card.condition.form, effectiveClass)) then
                    card.condition.form, card.enabled, changed = nil, false, true
                end
                if card.condition.activity and ((not card.parentId and not card.homeParentId) or
                    effectiveBinderId ~= self.GENERAL_BINDER_ID) then
                    card.condition.activity, card.overrideAllBindingsWhenActive, card.enabled, changed =
                        nil, nil, false, true
                elseif card.overrideAllBindingsWhenActive and
                    (card.templateKey ~= nil or not (card.parentId or card.homeParentId) or
                        effectiveBinderId ~= self.GENERAL_BINDER_ID) then
                    card.overrideAllBindingsWhenActive, changed = nil, true
                end
            end
        else
            changed = true
        end
    end
    self.db.selectedProfileId = selectedMap[sourceSelected]
    if not self.db.profiles[self.db.selectedProfileId] then self.db.selectedProfileId = next(self.db.profiles) end
    local function MapSelectedProfile(profileId, binderId)
        local mapped = selectedMap[profileId] or profileId
        local profile = mapped and self.db.profiles[mapped]
        return profile and profile.binderId == binderId and mapped or nil
    end
    local sourceDefaults = type(sourceSelections.defaults) == "table" and sourceSelections.defaults or {}
    self.db.selections.defaults.generalProfileId = MapSelectedProfile(
        sourceDefaults.generalProfileId, self.GENERAL_BINDER_ID)
    local sourceDefaultClasses = type(sourceDefaults.classProfileIds) == "table" and
        sourceDefaults.classProfileIds or {}
    for classFile, profileId in pairs(sourceDefaultClasses) do
        if self.VALID_CLASSES[classFile] then
            self.db.selections.defaults.classProfileIds[classFile] = MapSelectedProfile(
                profileId, "class:" .. classFile)
        end
    end
    local sourceCharacters = type(sourceSelections.characters) == "table" and sourceSelections.characters or {}
    local characterCount = 0
    for characterKey, sourceRecord in pairs(sourceCharacters) do
        if characterCount >= 256 then changed = true break end
        if type(characterKey) == "string" and characterKey ~= "" and #characterKey <= 128 and
            type(sourceRecord) == "table" then
            local record = { classProfileIds = {} }
            record.generalProfileId = MapSelectedProfile(sourceRecord.generalProfileId, self.GENERAL_BINDER_ID)
            record.characterProfileId = MapSelectedProfile(sourceRecord.characterProfileId, self.CHARACTER_BINDER_ID)
            -- The card this character last had open (UI restores it; a
            -- missing card falls back to the active spec card).
            if type(sourceRecord.lastCardID) == "string" and sourceRecord.lastCardID ~= "" and
                #sourceRecord.lastCardID <= 128 then
                record.lastCardID = sourceRecord.lastCardID
            end
            for classFile, profileId in pairs(type(sourceRecord.classProfileIds) == "table" and
                sourceRecord.classProfileIds or {}) do
                if self.VALID_CLASSES[classFile] then
                    record.classProfileIds[classFile] = MapSelectedProfile(profileId, "class:" .. classFile)
                end
            end
            self.db.selections.characters[characterKey] = record
            characterCount = characterCount + 1
        else
            changed = true
        end
    end
    self.db.settings.uiScale = math.max(0.65, math.min(1.4, numberOr(sourceSettings.uiScale, 1.0)))
    self.db.settings.iconSize = math.max(24, math.min(48, numberOr(sourceSettings.iconSize, 36)))
    self.db.settings.workspaceMode = sourceSettings.workspaceMode == "panel" and "panel" or "binder"
    self.db.settings.selectedBinderKey = sourceSettings.selectedBinderKey == "general" and "general" or "class"
    self.db.settings.theme = self.VALID_UI_THEMES[sourceSettings.theme] and sourceSettings.theme or "eui"
    self.db.settings.defaultProfileId = selectedMap[sourceSettings.defaultProfileId]
    self.db.settings.windowWidth = math.max(560, math.min(1200, numberOr(sourceSettings.windowWidth, 580)))
    self.db.settings.windowHeight = math.max(280, math.min(1000, numberOr(sourceSettings.windowHeight, 520)))
    self.db.settings.windowManualSize = sourceSettings.windowManualSize == true
    local savedWindowX, savedWindowY = tonumber(sourceSettings.windowX), tonumber(sourceSettings.windowY)
    self.db.settings.windowX = savedWindowX and math.max(-10000, math.min(10000, savedWindowX)) or nil
    self.db.settings.windowY = savedWindowY and math.max(-10000, math.min(10000, savedWindowY)) or nil
    self.db.settings.binderWidth = math.max(560, math.min(1200, numberOr(sourceSettings.binderWidth, 580)))
    self.db.settings.binderHeight = math.max(150, math.min(1000, numberOr(sourceSettings.binderHeight, 300)))
    self.db.settings.binderManualSize = sourceSettings.binderManualSize == true
    self.db.settings.gatherLooseSheets = sourceSettings.gatherLooseSheets ~= false
    self.db.settings.suspendBindPad = sourceSettings.suspendBindPad == true
    self.db.settings.showAbilityNames = sourceSettings.showAbilityNames ~= false
    -- These features graduated from their experimental toggles. Keep the
    -- legacy saved keys pinned on for schema compatibility while runtime UI
    -- treats the features as unconditional.
    self.db.settings.experimentalBinderStrings = true
    self.db.settings.experimentalColorPass = true
    self.db.settings.experimentalCardSizing = true
    self.db.settings.legacyBindingsRestored = sourceSettings.legacyBindingsRestored == true
    self.db.settings.bindingRestore = {}
    if type(sourceSettings.bindingRestore) == "table" then
        local restoreCount = 0
        for key, action in pairs(sourceSettings.bindingRestore) do
            local validKey = type(key) == "string" and key ~= "" and #key <= 64
            local validAction = action == false or (type(action) == "string" and #action <= 1024)
            if validKey and validAction and restoreCount < self.MAX_TILES then
                self.db.settings.bindingRestore[key] = action
                restoreCount = restoreCount + 1
            else
                changed = true
            end
        end
    elseif sourceSettings.bindingRestore ~= nil then
        changed = true
    end
    if sourceSettings.uiScale ~= self.db.settings.uiScale or sourceSettings.iconSize ~= self.db.settings.iconSize or
        sourceSettings.workspaceMode ~= self.db.settings.workspaceMode or
        sourceSettings.selectedBinderKey ~= self.db.settings.selectedBinderKey or
        sourceSettings.theme ~= self.db.settings.theme or sourceSettings.windowWidth ~= self.db.settings.windowWidth or
        sourceSettings.windowHeight ~= self.db.settings.windowHeight or
        sourceSettings.windowManualSize ~= self.db.settings.windowManualSize or
        sourceSettings.windowX ~= self.db.settings.windowX or sourceSettings.windowY ~= self.db.settings.windowY or
        sourceSettings.binderWidth ~= self.db.settings.binderWidth or
        sourceSettings.binderHeight ~= self.db.settings.binderHeight or
        sourceSettings.binderManualSize ~= self.db.settings.binderManualSize or
        sourceSettings.gatherLooseSheets ~= self.db.settings.gatherLooseSheets or
        sourceSettings.suspendBindPad ~= self.db.settings.suspendBindPad or
        sourceSettings.showAbilityNames ~= self.db.settings.showAbilityNames or
        sourceSettings.experimentalBinderStrings ~= self.db.settings.experimentalBinderStrings or
        sourceSettings.experimentalColorPass ~= self.db.settings.experimentalColorPass or
        sourceSettings.experimentalCardSizing ~= self.db.settings.experimentalCardSizing or
        sourceSettings.legacyBindingsRestored ~= self.db.settings.legacyBindingsRestored or
        sourceSettings.defaultProfileId ~= self.db.settings.defaultProfileId then changed = true end
    for key in pairs(sourceSettings) do
        if key ~= "uiScale" and key ~= "iconSize" and key ~= "workspaceMode" and
            key ~= "selectedBinderKey" and key ~= "theme" and
            key ~= "defaultProfileId" and key ~= "windowWidth" and key ~= "windowHeight" and
            key ~= "windowManualSize" and key ~= "windowX" and key ~= "windowY" and
            key ~= "binderWidth" and key ~= "binderHeight" and
            key ~= "binderManualSize" and key ~= "gatherLooseSheets" and
            key ~= "suspendBindPad" and
            key ~= "showAbilityNames" and
            key ~= "experimentalBinderStrings" and
            key ~= "experimentalColorPass" and
            key ~= "experimentalCardSizing" and
            key ~= "legacyBindingsRestored" and
            key ~= "bindingRestore" then changed = true end
    end
    return changed
end

local DATABASE_MIGRATIONS = {
    [2] = function(database)
        if type(database.profiles) == "table" then
            for _, profile in pairs(database.profiles) do
                if type(profile) == "table" and profile.bindingsEnabled == nil then
                    profile.bindingsEnabled = true
                end
            end
        end
        database.schemaVersion = 2
    end,
    [3] = function(database)
        database.schemaVersion = 3
    end,
}

function BindCards:MigrateDatabase(database, fromVersion)
    local migrated = false
    for version = math.max(1, math.floor(tonumber(fromVersion) or 0) + 1), self.SCHEMA_VERSION do
        local migration = DATABASE_MIGRATIONS[version]
        if migration then migration(database); migrated = true end
    end
    return migrated
end

function BindCards:MigrateLegacyProfilesToSets()
    if not self.db or not self.db.profiles then return false end
    local needsSplit = false
    for _, profile in pairs(self.db.profiles) do
        if not profile.binderId then needsSplit = true; break end
    end
    if not needsSplit then return false end

    local snapshot = copy(self.db)
    local snapshotUsedIds = copy(self.usedIds or {})
    local legacyProfiles = self.db.profiles
    local legacySelectedId = self.db.selectedProfileId
    local legacyDefaultId = self.db.settings and self.db.settings.defaultProfileId
    local newProfiles, splitMap, usedNames = {}, {}, {}
    local beforeTiles, afterTiles, beforeCards, afterCards = 0, 0, 0, 0
    for _, profile in pairs(legacyProfiles) do
        beforeTiles = beforeTiles + self:CountTiles(profile)
        beforeCards = beforeCards + #(profile.cards or {})
    end

    local function UniqueInBinder(name, binderId)
        name = trim(name)
        if name == "" then name = "Recovered set" end
        local used = usedNames[binderId] or {}
        usedNames[binderId] = used
        local base, candidate, suffix = name:sub(1, 64), name:sub(1, 64), 2
        while used[candidate:lower()] do
            candidate = string.format("%s (%d)", base:sub(1, 57), suffix):sub(1, 64)
            suffix = suffix + 1
        end
        used[candidate:lower()] = true
        return candidate
    end

    local function AddSet(source, binderId, cards, preferredId)
        local profileId = preferredId or self:NewID("profile")
        local profile = {
            id = profileId,
            name = UniqueInBinder(source.name or "Recovered set", binderId),
            binderId = binderId,
            cards = cards,
            bindingsEnabled = source.bindingsEnabled ~= false,
            createdAt = numberOr(source.createdAt, 0),
            updatedAt = numberOr(source.updatedAt, 0),
        }
        newProfiles[profileId] = profile
        afterTiles = afterTiles + self:CountTiles(profile)
        afterCards = afterCards + #(profile.cards or {})
        return profile
    end

    local orderedLegacy = {}
    for _, profile in pairs(legacyProfiles) do orderedLegacy[#orderedLegacy + 1] = profile end
    table.sort(orderedLegacy, function(left, right) return left.id < right.id end)
    for _, source in ipairs(orderedLegacy) do
        if source.binderId then
            source.name = UniqueInBinder(source.name, source.binderId)
            newProfiles[source.id] = source
            afterTiles = afterTiles + self:CountTiles(source)
            afterCards = afterCards + #(source.cards or {})
        else
            local buckets = {}
            for _, card in ipairs(source.cards or {}) do
                local binderId = self:GetCardBinderId(card, source) or self.GENERAL_BINDER_ID
                local classFile = binderId:match("^class:(.+)$")
                if binderId ~= self.GENERAL_BINDER_ID and not (classFile and self.VALID_CLASSES[classFile]) then
                    binderId = self.GENERAL_BINDER_ID
                end
                buckets[binderId] = buckets[binderId] or {}
                buckets[binderId][#buckets[binderId] + 1] = card
            end
            local general = AddSet(source, self.GENERAL_BINDER_ID,
                buckets[self.GENERAL_BINDER_ID] or {}, source.id)
            splitMap[source.id] = { generalProfileId = general.id, classProfileIds = {} }
            local classBinders = {}
            for binderId in pairs(buckets) do
                if binderId:match("^class:") then classBinders[#classBinders + 1] = binderId end
            end
            table.sort(classBinders)
            for _, binderId in ipairs(classBinders) do
                local classFile = binderId:match("^class:(.+)$")
                local classSet = AddSet(source, binderId, buckets[binderId])
                splitMap[source.id].classProfileIds[classFile] = classSet.id
            end
        end
    end

    if beforeTiles ~= afterTiles or beforeCards ~= afterCards then
        self.db = snapshot
        self.usedIds = snapshotUsedIds
        return nil, "Could not split profiles without preserving every card and placed icon."
    end
    for _, profile in pairs(newProfiles) do
        local ids = {}
        for _, card in ipairs(profile.cards or {}) do ids[card.id] = true end
        for _, card in ipairs(profile.cards or {}) do
            if (card.parentId and not ids[card.parentId]) or (card.homeParentId and not ids[card.homeParentId]) then
                self.db = snapshot
                self.usedIds = snapshotUsedIds
                return nil, "Could not split a card from its parent."
            end
        end
    end

    self.db.profiles = newProfiles
    self.db.selections = { defaults = { classProfileIds = {} }, characters = {} }
    local selected = splitMap[legacySelectedId]
    if selected then
        self.db.selections.defaults.generalProfileId = selected.generalProfileId
        self.db.selections.defaults.classProfileIds = copy(selected.classProfileIds)
        self.db.selectedProfileId = selected.generalProfileId
        local characterKey = self:GetCurrentCharacterKey()
        if characterKey then
            self.db.selections.characters[characterKey] = {
                generalProfileId = selected.generalProfileId,
                classProfileIds = copy(selected.classProfileIds),
            }
        end
    end
    local defaultSplit = splitMap[legacyDefaultId]
    self.db.settings.defaultProfileId = defaultSplit and defaultSplit.generalProfileId or
        self.db.selections.defaults.generalProfileId
    return true
end

function BindCards:InitializeDatabase()
    if self.CaptureStorageStage then self.CaptureStorageStage("preInitialize") end
    self:RefreshClassCatalog()
    local original = BindCardsDB
    local schema = type(original) == "table" and tonumber(original.schemaVersion) or 0
    if schema and schema > self.SCHEMA_VERSION then
        backupDatabase("future-schema-" .. tostring(schema), original)
        original = copy(DB_DEFAULTS)
    elseif type(original) ~= "table" then
        original = copy(DB_DEFAULTS)
    end
    BindCardsDB = original
    local before = copy(original)
    local migrated = self:MigrateDatabase(original, schema)
    local repaired = self:RepairDatabase(original)
    local split, splitMessage = self:MigrateLegacyProfilesToSets()
    if split == nil then
        self:Notify(splitMessage or "Profile migration was stopped; the recovery backup is unchanged.")
    end
    BindCardsDB = self.db
    if migrated or repaired or split then backupDatabase("schema-3-split-sets", before) end
    if not next(self.db.profiles) then self:CreateProfile("Default", nil, self.GENERAL_BINDER_ID) end
    if self.CaptureStorageStage then self.CaptureStorageStage("postInitialize") end
end

local function sameCondition(left, right)
    left, right = left or {}, right or {}
    return left.role == right.role and left.class == right.class and left.specID == right.specID and left.specGroup == right.specGroup and
        (left.content or "ANY") == (right.content or "ANY") and left.form == right.form and
        left.activity == right.activity
end

local function isEmptyCondition(condition)
    return sameCondition(condition, {})
end

function BindCards:EnsureProfileTemplates(profileId)
    if not self.db or not self.db.settings then return nil, "Database is not ready." end
    local profile = self:GetProfile(profileId)
    if not profile then return nil, "Profile not found." end
    local profileBinderId = self:NormalizeBinderId(profile.binderId)
    local profileClass = profileBinderId and profileBinderId:match("^class:(.+)$")
    local ensureGeneral = profileBinderId == self.GENERAL_BINDER_ID
    local ensureCharacter = profileBinderId == self.CHARACTER_BINDER_ID
    if not ensureGeneral and not ensureCharacter and not (profileClass and self.VALID_CLASSES[profileClass]) then
        return nil, "Binding set has no valid General or class library."
    end

    local changed, templateError = false, nil
    local originalCards, originalNextId, originalUsedIds = copy(profile.cards), self.db.nextId, copy(self.usedIds or {})
    local previousBatch = self.templateBatch
    self.templateBatch = true
    local function rollback(message)
        profile.cards = originalCards
        self.db.nextId = originalNextId
        self.usedIds = originalUsedIds
        self.templateBatch = previousBatch
        return nil, message or templateError or "Could not create the required profile cards."
    end
    local function findTemplate(templateKey, fallback)
        for _, card in ipairs(profile.cards) do
            if card.templateKey == templateKey then return card end
        end
        if fallback then
            for _, card in ipairs(profile.cards) do
                if not card.templateKey and fallback(card) then return card end
            end
        end
    end
    local function ensureCard(templateKey, values, fallback)
        local card = findTemplate(templateKey, fallback)
        if not card then
            values.templateKey = templateKey
            local message
            card, message = self:CreateCard(values, profile.id)
            if card then changed = true else templateError = message or "Card limit reached." end
            return card
        end
        if card.templateKey ~= templateKey then card.templateKey, changed = templateKey, true end
        -- Editable templates keep the player's name, rules and ON/OFF state.
        if not values.editable and card.name ~= values.name then card.name, changed = values.name, true end
        if not values.editable and card.enabled ~= true then card.enabled, changed = true, true end
        if card.treeExpanded == nil and values.treeExpanded ~= nil then
            card.treeExpanded, changed = values.treeExpanded == true, true
        end
        local wantedParent = values.parentId
        local validPeeled = wantedParent and card.parentId == nil and card.homeParentId == wantedParent
        if validPeeled then
            local wantedBinderId = self:GetCardBinderId(wantedParent, profile)
            if card.binderId ~= wantedBinderId then card.binderId, changed = wantedBinderId, true end
            if card.layoutMode ~= "floating" then card.layoutMode, changed = "floating", true end
        else
            if card.parentId ~= wantedParent then card.parentId, changed = wantedParent, true end
            if card.homeParentId ~= nil then card.homeParentId, changed = nil, true end
            local wantedBinderId = wantedParent and nil or values.binderId
            if card.binderId ~= wantedBinderId then card.binderId, changed = wantedBinderId, true end
            if wantedParent and card.layoutMode ~= "stacked" then card.layoutMode, changed = "stacked", true end
        end
        if not values.editable and not sameCondition(card.condition, values.condition) then
            card.condition, changed = copy(values.condition or {}), true
        end
        return card
    end

    local general
    if ensureGeneral then
        general = ensureCard("default:general", {
            name = "GENERAL", binderId = self.GENERAL_BINDER_ID,
            order = -1000, columns = 6, capacity = 12, treeExpanded = true, condition = {},
        }, function(card)
            return card.parentId == nil and card.name == "GENERAL" and isEmptyCondition(card.condition)
        end)
        if not general then return rollback(templateError or "Could not create the General card.") end
    end

    -- A character set has one root card, named after the character.
    local characterRoot
    if ensureCharacter then
        local label = type(profile.name) == "string" and profile.name ~= "" and profile.name:upper() or "CHARACTER"
        characterRoot = ensureCard("default:character", {
            name = label, binderId = self.CHARACTER_BINDER_ID,
            order = -250, columns = 6, capacity = 12, condition = {},
        }, function(card)
            return card.parentId == nil and isEmptyCondition(card.condition)
        end)
        if not characterRoot then return rollback(templateError or "Could not create the character card.") end
    end

    local classes = {}
    for _, classID in ipairs(self.CLASS_IDS) do
        local classFile = self.CLASS_FILES[classID]
        local getter = C_ClassInfo and C_ClassInfo.GetClassInfo or
            (C_CreatureInfo and C_CreatureInfo.GetClassInfo)
        local ok, info = false, nil
        if type(getter) == "function" then ok, info = pcall(getter, classID) end
        if not ok or (issecretvalue and issecretvalue(info)) then info = nil end
        local className = type(info) == "table" and info.className or nil
        if issecretvalue and issecretvalue(className) then className = nil end
        classes[#classes + 1] = { id = classID, name = className or classFile, file = classFile }
    end

    table.sort(classes, function(left, right) return left.id < right.id end)

    for _, class in ipairs(classes) do
        local className, classFile, classID = class.name, class.file, class.id
        local classCard
        if profileClass == classFile then classCard = ensureCard("default:class:" .. classFile, {
            name = type(className) == "string" and className:upper() or classFile,
            binderId = "class:" .. classFile,
            order = -500 + (tonumber(classID) or 0), columns = 6, capacity = 12,
            condition = { class = classFile },
        }, function(card)
            return card.parentId == nil and sameCondition(card.condition, { class = classFile })
        end) end
        if classCard then
            for group = 1, 2 do
                ensureCard("default:specgroup:" .. classFile .. ":" .. group, {
                    name = group == 1 and "Primary" or "Secondary",
                    parentId = classCard.id, order = group, columns = 6, capacity = 12,
                    condition = { specGroup = group }, editable = true,
                }, function(card)
                    return card.parentId == classCard.id and sameCondition(card.condition, { specGroup = group })
                end)
            end
        end
    end

    if templateError then return rollback(templateError) end

    -- Fold extra top-level cards into their binder root so detached binders include them.
    local classRoots = {}
    for _, card in ipairs(profile.cards) do
        local rootClass = type(card.templateKey) == "string" and card.templateKey:match("^default:class:(.+)$")
        if rootClass then classRoots[rootClass] = card end
    end
    for _, card in ipairs(profile.cards) do
        if not card.parentId and not card.homeParentId and
            not (type(card.templateKey) == "string" and card.templateKey:match("^default:")) then
            local targetClass = type(card.binderId) == "string" and card.binderId:match("^class:(.+)$") or
                (card.condition and card.condition.class)
            local targetRoot = targetClass and classRoots[targetClass] or
                (not targetClass and ensureGeneral and general or nil) or
                (ensureCharacter and characterRoot or nil)
            if targetRoot and targetRoot ~= card then
                card.parentId = targetRoot.id
                card.binderId = nil
                card.layoutMode = "stacked"
                card.floatX, card.floatY = nil, nil
                changed = true
            end
        end
    end

    self.templateBatch = previousBatch
    if changed and not previousBatch then
        self:TouchProfile(profile)
        self:RequestRecompile("profile-templates-updated")
    end
    return profile
end

function BindCards:EnsureAllProfileTemplates()
    if not self.db or not self.db.profiles then return false end
    for profileId in pairs(self.db.profiles) do self:EnsureProfileTemplates(profileId) end
    return true
end

function BindCards:RepairProfileTemplatesAfterLogin()
    if not self.db or not self.db.profiles then return false end
    self:RefreshClassCatalog()

    -- Repair immediately usable sets synchronously.
    local repaired = {}
    local general, class, character = self:GetSelectedProfileSets()
    local defaultProfileId = self.db.settings and self.db.settings.defaultProfileId
    -- Explicit indices: ipairs would stop at the first missing set.
    local ids = { general and general.id, class and class.id, character and character.id, defaultProfileId }
    for index = 1, 4 do
        local profileId = ids[index]
        if profileId and not repaired[profileId] and self.db.profiles[profileId] then
            self:EnsureProfileTemplates(profileId)
            repaired[profileId] = true
        end
    end
    -- Unused libraries repair lazily when selected.
    return true
end

function BindCards:EnsureDefaultProfile()
    if not self.db or not self.db.settings then return nil, "Database is not ready." end
    local profile = self.db.profiles[self.db.settings.defaultProfileId]
    if profile and profile.binderId ~= self.GENERAL_BINDER_ID then profile = nil end
    if not profile then
        for _, candidate in pairs(self.db.profiles) do
            if candidate.binderId == self.GENERAL_BINDER_ID and
                type(candidate.name) == "string" and candidate.name:lower() == "default" then
                profile = candidate
                break
            end
        end
    end
    if not profile then
        local selectedProfileId = self.db.selectedProfileId
        profile = self:CreateProfile("Default", nil, self.GENERAL_BINDER_ID)
        if selectedProfileId and self.db.profiles[selectedProfileId] then
            self.db.selectedProfileId = selectedProfileId
        end
    end
    if not profile then return nil, "Could not create the Default profile." end
    self.db.settings.defaultProfileId = profile.id
    self:EnsureProfileTemplates(profile.id)
    self.db.selections = self.db.selections or { defaults = {}, characters = {} }
    self.db.selections.defaults = self.db.selections.defaults or { classProfileIds = {} }
    self.db.selections.defaults.classProfileIds = self.db.selections.defaults.classProfileIds or {}
    self.db.selections.characters = self.db.selections.characters or {}
    if not self:GetSelectedProfileSet(self.GENERAL_BINDER_ID) then
        self.db.selections.defaults.generalProfileId = profile.id
    end

    local classFile = self:GetCurrentClassFile()
    local classProfile = classFile and self:GetSelectedProfileSet("class:" .. classFile) or nil
    if classFile and not classProfile then
        for _, candidate in pairs(self.db.profiles) do
            if candidate.binderId == "class:" .. classFile and candidate.name:lower() == "default" then
                classProfile = candidate
                break
            end
        end
        if not classProfile then classProfile = self:CreateProfile("Default", nil, "class:" .. classFile) end
    end
    if classProfile then
        self:EnsureProfileTemplates(classProfile.id)
        self.db.selections.defaults.classProfileIds[classFile] =
            self.db.selections.defaults.classProfileIds[classFile] or classProfile.id
    end
    local characterKey = self:GetCurrentCharacterKey()
    if characterKey then
        local record = self.db.selections.characters[characterKey]
        if type(record) ~= "table" then record = { classProfileIds = {} }; self.db.selections.characters[characterKey] = record end
        record.classProfileIds = record.classProfileIds or {}
        record.generalProfileId = record.generalProfileId or self.db.selections.defaults.generalProfileId
        if classFile then record.classProfileIds[classFile] = record.classProfileIds[classFile] or
            self.db.selections.defaults.classProfileIds[classFile] end
    end
    return profile, classProfile
end

-- Character sets: one per character (ownerKey = GUID), shown as the third
-- binder tab. Anything can go in it; racial abilities are added once when the
-- set is created (seedRacials), and deleting them afterwards sticks.

-- Active racials by race file, for clients whose racial API returns nothing.
local RACIAL_FALLBACK = {
    Human = { 20600 },                 -- Perception
    Dwarf = { 20594, 2481 },           -- Stoneform, Find Treasure
    NightElf = { 20580 },              -- Shadowmeld
    Gnome = { 20589 },                 -- Escape Artist
    Orc = { 20572, 33697, 33702 },     -- Blood Fury (variants)
    Scourge = { 7744, 20577 },         -- Will of the Forsaken, Cannibalize
    Tauren = { 20549 },                -- War Stomp
    Troll = { 20554, 26296, 26297 },   -- Berserking (variants)
    BloodElf = { 28730, 25046, 50613 },-- Arcane Torrent (variants)
    Draenei = { 28880 },               -- Gift of the Naaru
}

-- Active racial names on Forever (English), including Forever-only ones.
-- Source: Wowhead "All Racials and Available Class-Race Combinations in
-- World of Warcraft: Forever" (updated 2026-09-25; pre-release, may change).
-- Matched by name against active spellbook spells, so it adds only racials
-- the character really has.
local FOREVER_RACIAL_NAMES = {
    ["will to survive"] = true, ["perception"] = true,                -- Human
    ["stoneform"] = true, ["find treasure"] = true,                   -- Dwarf
    ["shadowmeld"] = true, ["elunes light"] = true, ["elune's light"] = true, -- Night Elf
    ["escape artist"] = true, ["eureka!"] = true,                     -- Gnome
    ["blood fury"] = true, ["shatter curse"] = true,                  -- Orc
    ["will of the forsaken"] = true, ["cannibalize"] = true,          -- Undead
    ["war stomp"] = true, ["cultivation"] = true,                     -- Tauren
    ["berserking"] = true, ["rapid regeneration"] = true,             -- Troll
    ["walk on air"] = true, ["read ley line"] = true, ["skysight"] = true, -- Skyborne
}

local function Plain(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return unpack(results, 2)
end

-- Active (non-passive) spells in the player's spellbook: a list of
-- { name, spellID, subName } plus a lookup by lower-case name.
local function SpellbookActiveSpells()
    local spells, list, book = {}, {}, C_SpellBook
    if type(book) ~= "table" or type(book.GetNumSpellBookSkillLines) ~= "function" then return spells, list end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    for line = 1, tonumber(Plain(SafeCall(book.GetNumSpellBookSkillLines))) or 0 do
        local info = SafeCall(book.GetSpellBookSkillLineInfo, line)
        local offset = type(info) == "table" and tonumber(Plain(info.itemIndexOffset))
        local count = type(info) == "table" and tonumber(Plain(info.numSpellBookItems))
        for slot = (offset or 0) + 1, (offset or 0) + (count or 0) do
            local item = SafeCall(book.GetSpellBookItemInfo, slot, bank)
            local name = type(item) == "table" and Plain(item.name)
            local spellID = type(item) == "table" and tonumber(Plain(item.spellID))
            if type(name) == "string" and spellID and Plain(item.isPassive) == false and
                (spellType == nil or Plain(item.itemType) == spellType) then
                spells[name:lower()] = spells[name:lower()] or spellID
                local subName = Plain(item.subName)
                list[#list + 1] = { name = name, spellID = spellID, subName = type(subName) == "string" and subName or "" }
            end
        end
    end
    return spells, list
end

-- Spell IDs of the current character's active racial abilities, from three
-- sources that can only add, never hide one another:
--   1. the spellbook's own "Racial" label on active spells (it also shows
--      Forever-only racials such as Human Will to Survive);
--   2. the race's ability names (C_AlliedRaces) matched in the spellbook;
--   3. a table of classic racials checked with IsPlayerSpell;
--   4. Forever's active racial names (English) matched in the spellbook.
-- The label is game data and localized: besides "Racial", any label carried
-- by a racial found through 2, 3 or 4 is accepted too.
function BindCards:GetRacialSpellIDs()
    local _, raceFile, raceID = SafeCall(UnitRace, "player")
    raceFile, raceID = Plain(raceFile), tonumber(Plain(raceID))
    local result, seen = {}, {}
    local function Add(spellID)
        if spellID and not seen[spellID] then seen[spellID], result[#result + 1] = true, spellID end
    end
    local spells, list = SpellbookActiveSpells()
    local allied = C_AlliedRaces
    local abilities = raceID and type(allied) == "table" and SafeCall(allied.GetAllRacialAbilitiesFromID, raceID)
    for _, ability in ipairs(type(abilities) == "table" and abilities or {}) do
        local name = type(ability) == "table" and Plain(ability.name)
        Add(type(name) == "string" and spells[name:lower()] or nil)
    end
    for _, spellID in ipairs(type(raceFile) == "string" and RACIAL_FALLBACK[raceFile] or {}) do
        if Plain(SafeCall(IsPlayerSpell, spellID)) == true then Add(spellID) end
    end
    for _, item in ipairs(list) do
        if FOREVER_RACIAL_NAMES[item.name:lower()] then Add(item.spellID) end
    end
    local labels = { racial = true }
    for _, item in ipairs(list) do
        if seen[item.spellID] and item.subName ~= "" then labels[item.subName:lower()] = true end
    end
    for _, item in ipairs(list) do
        if labels[item.subName:lower()] then Add(item.spellID) end
    end
    return result
end

function BindCards:GetCharacterRootCard(profile)
    for _, card in ipairs(profile and profile.cards or {}) do
        if card.templateKey == "default:character" then return card end
    end
end

-- Adds the pending racials once. Returns true when the set is settled
-- (racials added, or the spellbook answered and there are none), and the
-- number of tiles added.
function BindCards:SeedCharacterRacials(profile)
    if not profile or not profile.seedRacials then return true, 0 end
    local spellbookReady = type(C_SpellBook) == "table" and
        (tonumber(Plain(SafeCall(C_SpellBook.GetNumSpellBookSkillLines))) or 0) > 0
    local racials = self:GetRacialSpellIDs()
    if #racials == 0 and not spellbookReady then return false end
    local root = self:GetCharacterRootCard(profile)
    if not root then return false end
    local added = 0
    for _, spellID in ipairs(racials) do
        -- Present anywhere on the character card or its subcards counts.
        local present = false
        for _, card in ipairs(profile.cards or {}) do
            for _, tile in ipairs(card.tiles or {}) do
                if tile.kind == "spell" and tile.spellID == spellID then present = true end
            end
        end
        if not present and self:CreateTile(root.id, { kind = "spell", spellID = spellID }, profile.id) then
            added = added + 1
        end
    end
    profile.seedRacials = nil
    self:TouchProfile(profile)
    return true, added
end

-- Card menu "Add racial abilities": adds any racial not on the card yet
-- (e.g. one detected by a newer BindCards). Returns the number added.
function BindCards:AddMissingRacials()
    local profile = self:GetSelectedProfileSet(self.CHARACTER_BINDER_ID)
    if not profile then return nil, "This character has no character card yet." end
    profile.seedRacials = true
    local settled, added = self:SeedCharacterRacials(profile)
    if not settled then return nil, "The spellbook is not loaded yet; try again in a moment." end
    if added > 0 then self:RequestRecompile("racials-added") end
    return added
end

-- Creates this character's set on first login (named after the character).
function BindCards:EnsureCharacterProfile()
    if not self.db or not self.db.profiles then return nil end
    local characterKey = self:GetCurrentCharacterKey()
    if not characterKey then return nil end
    local profile = self:GetSelectedProfileSet(self.CHARACTER_BINDER_ID)
    if not profile then
        local name = Plain(SafeCall(UnitName, "player"))
        local previousSelected = self.db.selectedProfileId
        profile = self:CreateProfile(type(name) == "string" and name ~= "" and name or "Character", nil,
            self.CHARACTER_BINDER_ID)
        self.db.selectedProfileId = previousSelected
        if not profile then return nil end
        profile.ownerKey = characterKey
        profile.seedRacials = true
    end
    self.db.selections = self.db.selections or { defaults = {}, characters = {} }
    self.db.selections.characters = self.db.selections.characters or {}
    local record = self.db.selections.characters[characterKey]
    if type(record) ~= "table" then record = { classProfileIds = {} }; self.db.selections.characters[characterKey] = record end
    record.characterProfileId = profile.id
    self:EnsureProfileTemplates(profile.id)
    self:SeedCharacterRacials(profile)
    return profile
end

-- Other characters' sets, for "Copy from…": { id, name, tiles }.
function BindCards:GetOtherCharacterSets()
    local own, list = self:GetSelectedProfileSet(self.CHARACTER_BINDER_ID), {}
    for _, profile in pairs(self.db and self.db.profiles or {}) do
        if profile.binderId == self.CHARACTER_BINDER_ID and profile ~= own then
            list[#list + 1] = { id = profile.id, name = profile.name, tiles = self:CountTiles(profile) }
        end
    end
    table.sort(list, function(left, right) return tostring(left.name):lower() < tostring(right.name):lower() end)
    return list
end

-- Replaces this character's cards with a copy of another character's cards.
function BindCards:CopyCharacterSetFrom(sourceProfileId)
    local target = self:GetSelectedProfileSet(self.CHARACTER_BINDER_ID)
    local source = self.db and self.db.profiles[sourceProfileId]
    if not target then return nil, "This character has no character card yet." end
    if not source or source.binderId ~= self.CHARACTER_BINDER_ID or source == target then
        return nil, "Choose another character."
    end
    local cards, cardIds = copy(source.cards or {}), {}
    for index, card in ipairs(cards) do
        local oldId = card.id
        card.id = self:NewID("card")
        cardIds[oldId] = card.id
        card.order = card.order or index
        for tileIndex, tile in ipairs(card.tiles or {}) do
            tile.id = self:NewID("tile")
            tile.order = tile.order or tileIndex
        end
    end
    for _, card in ipairs(cards) do
        card.parentId = card.parentId and cardIds[card.parentId] or nil
        card.homeParentId = card.homeParentId and cardIds[card.homeParentId] or nil
    end
    target.cards = cards
    target.seedRacials = nil
    self:EnsureProfileTemplates(target.id) -- renames the root to this character
    self:TouchProfile(target, "bindings")
    self:RequestRecompile("character-copied")
    return target
end

function BindCards:SetUISettings(uiScale, iconSize, workspaceMode)
    if uiScale ~= nil then
        self.db.settings.uiScale = math.max(0.65, math.min(1.4, numberOr(uiScale, self.db.settings.uiScale)))
    end
    if iconSize ~= nil then
        self.db.settings.iconSize = math.max(24, math.min(48, numberOr(iconSize, self.db.settings.iconSize)))
    end
    if workspaceMode ~= nil then
        self.db.settings.workspaceMode = workspaceMode == "panel" and "panel" or "binder"
    end
    self:Fire("SETTINGS_CHANGED", self.db.settings)
    return self.db.settings
end

function BindCards:SetUITheme(theme)
    self.db.settings.theme = self.VALID_UI_THEMES[theme] and theme or "eui"
    self:Fire("SETTINGS_CHANGED", self.db.settings)
    return self.db.settings.theme
end

-- UI compatibility aliases; SavedVariables and exports retain card/tile terminology.
function BindCards:AddCard(values, profileId) return self:CreateCard(values, profileId) end
function BindCards:AddEntry(cardId, payload, profileId)
    return self:CreateTile(cardId, self:NormalizeTilePayload(payload), profileId)
end
function BindCards:DeleteEntry(_, tileId, profileId) return self:DeleteTile(tileId, profileId) end
function BindCards:MoveEntry(_, tileId, cardId, index, profileId)
    return self:MoveTile(tileId, cardId, index, profileId)
end
function BindCards:CopyEntry(_, tileId, cardId, index, profileId)
    local profile, tile = self:FindTileOwner(tileId, profileId)
    if not tile then return nil, "Tile not found." end
    local targetProfile, target = self:FindCardOwner(cardId, profileId)
    if not target then return nil, "Target card not found." end
    if targetProfile ~= profile then return nil, "Abilities cannot copy between binding sets." end
    if #target.tiles >= 192 then return nil, "The target card is full." end
    if self:CountTiles(profile) >= self.MAX_TILES then return nil, "Profile tile limit reached." end
    index = math.max(1, math.min(target.capacity or 192,
        math.floor(tonumber(index) or 1)))
    local columns = target.columns or 6
    local x, y = (index - 1) % columns + 1, math.floor((index - 1) / columns) + 1
    for _, existing in ipairs(target.tiles) do
        local ex, ey = tileGridPosition(existing, target)
        if ex == x and ey == y then return nil, "That grid cell is occupied." end
    end
    local duplicate = copy(tile)
    duplicate.id, duplicate.bindings = self:NewID("tile"), {}
    duplicate.gridX, duplicate.gridY = x, y
    duplicate.order = (y - 1) * self.MAX_COLUMNS + x
    target.tiles[#target.tiles + 1] = duplicate
    self:TouchProfile(profile)
    return duplicate
end
function BindCards:UpdateEntry(_, tileId, values, profileId) return self:UpdateTile(tileId, values, profileId) end
function BindCards:SetEntryBinding(_, tileId, key, profileId)
    if key == nil then return self:ClearTileBindings(tileId, profileId) end
    return self:SetTileBinding(tileId, key, true, profileId)
end
function BindCards:GetProfileBindingConflict(key, tileId, profileId)
    key = self:NormalizeKey(key)
    if not key then return nil end
    local profile = self:GetProfile(profileId)
    for _, card in ipairs(profile and profile.cards or {}) do
        for _, tile in ipairs(card.tiles or {}) do
            if tile.id ~= tileId then
                for _, existing in ipairs(tile.bindings or {}) do
                    if self:NormalizeKey(existing) == key then return self:GetTileDisplay(tile) end
                end
            end
        end
    end
end

local eventFrame = CreateFrame("Frame")
BindCards.eventFrame = eventFrame
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
-- Build 70338 reports PvP flag changes with their own event.
if C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid("PLAYER_PVP_FLAG_CHANGED") then
    eventFrame:RegisterEvent("PLAYER_PVP_FLAG_CHANGED")
end
eventFrame:RegisterEvent("WAR_MODE_STATUS_UPDATE")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("CVAR_UPDATE")
eventFrame:RegisterEvent("UPDATE_BINDINGS")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:SetScript("OnEvent", function(frame, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        if frame and frame.UnregisterEvent then frame:UnregisterEvent("ADDON_LOADED") end
        BindCards:InitializeDatabase()
        BindCards:EnsureDefaultProfile()
        BindCards:InstallHouseEditorBindingHook()
        BindCards:Fire("READY")
    elseif event == "PLAYER_LOGIN" then
        -- Class/spec APIs may be unavailable at ADDON_LOADED.
        BindCards:InstallHouseEditorBindingHook()
        BindCards:EnsureDefaultProfile()
        BindCards:EnsureCharacterProfile()
        BindCards:RepairProfileTemplatesAfterLogin()
        BindCards:RequestRecompile("login")
    elseif event == "SPELLS_CHANGED" then
        -- Racials wait for the spellbook; add them once it has loaded.
        local profile = BindCards.db and BindCards:GetSelectedProfileSet(BindCards.CHARACTER_BINDER_ID)
        if profile and profile.seedRacials and BindCards:SeedCharacterRacials(profile) then
            BindCards:RequestRecompile("racials-added")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        BindCards:RefreshSpecGroup()
        BindCards:RequestRecompile("combat-ended")
        BindCards:ApplyPendingBindings()
    elseif event == "CVAR_UPDATE" then
        local cvarName = ...
        if issecretvalue and issecretvalue(cvarName) then cvarName = nil end
        if cvarName == "ActionButtonUseKeyDown" or cvarName == "ACTION_BUTTON_USE_KEY_DOWN" then
            BindCards:RequestRecompile("key-trigger")
        end
    elseif event == "UPDATE_BINDINGS" then
        BindCards:RequestBindingConflictRefresh()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if not unit or unit == "player" then BindCards:RequestRecompile("specialization") end
    elseif event == "PLAYER_FLAGS_CHANGED" then
        local unit = ...
        if unit == "player" then BindCards:RequestRecompile("pvp-status") end
    elseif event == "PLAYER_PVP_FLAG_CHANGED" then
        BindCards:RequestRecompile("pvp-status")
    else
        BindCards:RefreshSpecGroup()
        BindCards:RequestRecompile(event)
    end
    BindCards:Fire("GAME_EVENT", event, ...)
end)

SLASH_BINDCARDS1 = "/bindcards"
SLASH_BINDCARDS2 = "/bcards"
SLASH_BINDCARDS3 = "/bc"
SlashCmdList.BINDCARDS = function(input)
    input = trim(input):lower()
    if (input == "gamepad on" or input == "gamepad off") and BindCards.SetGamepadBindingsEnabled then
        BindCards:SetGamepadBindingsEnabled(input == "gamepad on")
    elseif input == "rebind" then
        BindCards:RequestRecompile("slash", true)
        BindCards:Notify(InCombatLockdown() and "Bindings queued until combat ends." or "Bindings refreshed.")
    elseif input == "hover" and BindCards.ReportHoverState then
        BindCards:ReportHoverState()
    elseif input == "testframes" and BindCards.ToggleHoverTestFrames then
        BindCards:ToggleHoverTestFrames()
    elseif input == "help" then
        BindCards:Notify("Use /bc to open BindCards, /bc rebind to refresh bindings, /bc hover while pointing at a unit frame to check mouseover keys, or /bc testframes for stand-in unit frames.")
    elseif type(BindCards.ToggleWindow) == "function" then
        BindCards:ToggleWindow()
    else
        BindCards:Fire("OPEN_REQUESTED")
    end
end
