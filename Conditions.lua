local _, BindCards = ...

local VALID_CONTENT = { ANY = true, PVE = true, PVP = true }
local VALID_CLASSES = BindCards.VALID_CLASSES

local FORM_DEFINITIONS = {
    druid_caster = { class = "DRUID", label = "Caster" },
    druid_bear = { class = "DRUID", label = "Bear", spellID = 5487, spellAliases = { 9634 } },
    druid_cat = { class = "DRUID", label = "Cat", spellID = 768 },
    druid_moonkin = { class = "DRUID", label = "Moonkin", spellID = 24858 },
    druid_travel = { class = "DRUID", label = "Travel", spellID = 783 },
    priest_shadowform = { class = "PRIEST", label = "Shadowform", spellID = 15473 },
    druid_aquatic = { class = "DRUID", label = "Aquatic", spellID = 1066 },
    warrior_battle = { class = "WARRIOR", label = "Battle stance", spellID = 2457 },
    warrior_defensive = { class = "WARRIOR", label = "Defensive stance", spellID = 71 },
    warrior_berserker = { class = "WARRIOR", label = "Berserker stance", spellID = 2458 },
    rogue_stealth = { class = "ROGUE", label = "Stealth", stealth = true },
}
local FORM_OPTIONS = {
    DRUID = { "druid_caster", "druid_bear", "druid_cat", "druid_moonkin", "druid_travel", "druid_aquatic" },
    WARRIOR = { "warrior_battle", "warrior_defensive", "warrior_berserker" },
    PRIEST = { "priest_shadowform" },
    ROGUE = { "rogue_stealth" },
}
BindCards.FORM_DEFINITIONS = FORM_DEFINITIONS

function BindCards:GetFormOptions(class)
    local result = {}
    for _, id in ipairs(FORM_OPTIONS[class] or {}) do
        local definition = FORM_DEFINITIONS[id]
        result[#result + 1] = { id = id, label = definition.label, class = definition.class }
    end
    return result
end

function BindCards:IsFormValidForClass(form, class)
    local definition = FORM_DEFINITIONS[form]
    return definition ~= nil and definition.class == class
end

function BindCards:ResolveFormIndices(class)
    if class == nil then return {} end
    self.resolvedFormIndices = self.resolvedFormIndices or {}
    if InCombatLockdown and InCombatLockdown() then return self.resolvedFormIndices[class] or {} end
    local resolved = {}
    if class ~= "DRUID" and class ~= "PRIEST" and class ~= "WARRIOR" then
        self.resolvedFormIndices[class] = resolved
        return resolved
    end
    if not GetNumShapeshiftForms or not GetShapeshiftFormInfo then return self.resolvedFormIndices[class] or resolved end
    local ok, count = pcall(GetNumShapeshiftForms)
    if not ok then return self.resolvedFormIndices[class] or resolved end
    if issecretvalue and issecretvalue(count) then return self.resolvedFormIndices[class] or resolved end
    count = tonumber(count) or 0
    local wanted = {}
    for _, id in ipairs(FORM_OPTIONS[class] or {}) do
        local spellID = FORM_DEFINITIONS[id].spellID
        if spellID then wanted[spellID] = id end
        for _, alias in ipairs(FORM_DEFINITIONS[id].spellAliases or {}) do wanted[alias] = id end
    end
    for index = 1, count do
        local infoOK, _, _, _, spellID = pcall(GetShapeshiftFormInfo, index)
        if not infoOK then spellID = nil end
        if issecretvalue and issecretvalue(spellID) then spellID = nil end
        local id = wanted[tonumber(spellID)]
        if id then
            resolved[id] = resolved[id] or {}
            resolved[id][#resolved[id] + 1] = index
        end
    end
    self.resolvedFormIndices[class] = resolved
    return resolved
end

function BindCards:GetCurrentForm(class)
    if class == "ROGUE" then
        if not IsStealthed then return nil end
        local ok, active = pcall(IsStealthed)
        if not ok then return nil end
        if issecretvalue and issecretvalue(active) then return nil end
        return active == true and "rogue_stealth" or nil
    end
    if class ~= "DRUID" and class ~= "PRIEST" and class ~= "WARRIOR" then return nil end
    if not GetShapeshiftForm then return nil end
    local ok, index = pcall(GetShapeshiftForm)
    if not ok then return nil end
    if issecretvalue and issecretvalue(index) then return nil end
    index = tonumber(index)
    if class == "DRUID" and (not index or index == 0) then return "druid_caster" end
    for id, resolvedIndices in pairs(self:ResolveFormIndices(class)) do
        for _, resolvedIndex in ipairs(resolvedIndices) do
            if resolvedIndex == index then return id end
        end
    end
    return nil
end

function BindCards:GetFormStateDriver(class)
    if class == "ROGUE" then return "[stealth] rogue_stealth; base" end
    local clauses, indices = {}, self:ResolveFormIndices(class)
    for _, id in ipairs(FORM_OPTIONS[class] or {}) do
        if id ~= "druid_caster" then
            for _, index in ipairs(indices[id] or {}) do
                clauses[#clauses + 1] = ("[form:%d] %s"):format(index, id)
            end
        end
    end
    if class == "DRUID" then clauses[#clauses + 1] = "[noform] druid_caster" end
    clauses[#clauses + 1] = "base"
    return table.concat(clauses, "; ")
end

function BindCards:GetConditionalBindingStateDriver(class)
    return self:GetFormStateDriver(class)
end

function BindCards.GetCurrentActivity() return nil end

function BindCards:RefreshSpecGroup()
    if InCombatLockdown and InCombatLockdown() then return self.activeSpecGroup end
    local getter = C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup
    local ok, group = false, nil
    if type(getter) == "function" then ok, group = pcall(getter) end
    if not ok or (issecretvalue and issecretvalue(group)) then group = nil end
    if group ~= 1 and group ~= 2 then group = nil end
    self.activeSpecGroup = group
    return group
end

function BindCards:GetPlayerContext()
    local _, class = UnitClass("player")
    if issecretvalue and issecretvalue(class) then class = nil end
    return {
        class = class,
        specGroup = self:RefreshSpecGroup(),
        content = self.GetCurrentContentType(),
        form = self:GetCurrentForm(class),
    }
end

local function SafeResult(callback, ...)
    if type(callback) ~= "function" then return nil end
    local ok, value, second = pcall(callback, ...)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    if issecretvalue and issecretvalue(second) then second = nil end
    return value, second
end

function BindCards.GetCurrentContentType()
    local inInstance, instanceType = SafeResult(IsInInstance)
    if inInstance == true then
        return (instanceType == "arena" or instanceType == "pvp") and "PVP" or "PVE"
    end

    local warModeActive = C_PvP and SafeResult(C_PvP.IsWarModeActive)
    local warModeDesired = C_PvP and SafeResult(C_PvP.IsWarModeDesired)
    if warModeActive == true or warModeDesired == true then return "PVP" end

    local zoneType = C_PvP and SafeResult(C_PvP.GetZonePVPInfo)
    if zoneType == "arena" or zoneType == "combat" then return "PVP" end
    if SafeResult(UnitIsPVP, "player") == true then return "PVP" end
    return "PVE"
end

function BindCards.StripTalentLoadoutCondition(condition)
    -- Do not broaden imported Retail conditions by deleting their restrictions.
    return condition, false
end

function BindCards:NormalizeCondition(condition, resolveCurrent)
    if condition == nil then condition = {} end
    if type(condition) ~= "table" then return {}, false, "Condition must be a table." end
    local result = {}
    for _, field in ipairs({ "role", "specID", "activity", "talentConfigID", "talentConfigOwner" }) do
        if condition[field] ~= nil then return {}, false, "Retail conditions are not supported in Forever. Choose a Primary or Secondary build." end
    end
    local class = condition.class
    if class == "Any class" then class = nil end
    if class ~= nil and not VALID_CLASSES[class] then return {}, false, "Invalid class condition." end
    result.class = class
    local group = condition.specGroup
    if group == "Any build" then group = nil end
    if group == "Current build" and resolveCurrent then
        group = self:GetPlayerContext().specGroup
        if group == nil then return {}, false, "The active build is unavailable." end
    end
    if group ~= nil and group ~= 1 and group ~= 2 then return {}, false, "Invalid build condition." end
    result.specGroup = group

    local content = condition.content
    if content == nil or content == "Any content" then content = "ANY" end
    if type(content) == "string" then content = content:upper() end
    if not VALID_CONTENT[content] then return {}, false, "Invalid content condition." end
    result.content = content

    if condition.talentConfigID ~= nil or condition.talentConfigOwner ~= nil then
        return {}, false, "Talent loadout card conditions are no longer supported."
    end
    local form = condition.form
    if form == "Any form" then form = nil end
    if form ~= nil and not FORM_DEFINITIONS[form] then return {}, false, "Invalid form condition." end
    if form ~= nil and result.class ~= nil and FORM_DEFINITIONS[form].class ~= result.class then
        return {}, false, "Form and class conditions do not match."
    end
    result.form = form

    return result, true
end

local function ConditionSpecificity(condition)
    local score = 0
    if condition.class then score = score + 2 end
    if condition.specGroup then score = score + 4 end
    if condition.content ~= "ANY" then score = score + 8 end
    if condition.form then score = score + 32 end
    return score
end

local function NormalizedConditionMatches(condition, context)
    if condition == false then return false end
    if condition.class and condition.class ~= context.class then return false end
    if condition.specGroup and condition.specGroup ~= context.specGroup then return false end
    if condition.content ~= "ANY" and condition.content ~= context.content then return false end
    if condition.form and condition.form ~= context.form then return false end
    return true
end

function BindCards:GetConditionSpecificity(condition)
    local valid
    condition, valid = self:NormalizeCondition(condition, false)
    if not valid then return 0 end
    return ConditionSpecificity(condition)
end

function BindCards:ConditionMatches(condition, context)
    local valid
    condition, valid = self:NormalizeCondition(condition, false)
    if not valid then return false end
    context = context or self:GetPlayerContext()
    return NormalizedConditionMatches(condition, context)
end

function BindCards:GetActiveCards(profile, context)
    profile = profile or self:GetSelectedProfile()
    if not profile then return {}, {} end
    context = context or self:GetPlayerContext()
    local cardsById, active, depths, specificity, binderFamilies, binderIds = {}, {}, {}, {}, {}, {}
    local normalizedConditions, conditionSpecificity = {}, {}
    for _, card in ipairs(profile.cards or {}) do
        cardsById[card.id] = card
        local normalized, valid = self:NormalizeCondition(card.condition, false)
        normalizedConditions[card.id] = valid and normalized or false
        conditionSpecificity[card.id] = valid and ConditionSpecificity(normalized) or 0
    end

    local function resolveBinder(card, trail)
        if binderIds[card.id] ~= nil then return binderIds[card.id] or nil end
        trail = trail or {}
        if trail[card.id] then binderIds[card.id] = false; return nil end
        trail[card.id] = true
        local owner = cardsById[card.parentId or card.homeParentId]
        local binderId
        if owner then
            binderId = resolveBinder(owner, trail)
        else
            binderId = self:NormalizeBinderId(card.binderId)
            if not binderId then
                local templateClass = type(card.templateKey) == "string" and
                    card.templateKey:match("^default:class:(.+)$")
                local conditionClass = card.condition and card.condition.class
                binderId = templateClass and ("class:" .. templateClass) or
                    (conditionClass and ("class:" .. conditionClass) or self.GENERAL_BINDER_ID)
            end
        end
        trail[card.id] = nil
        binderIds[card.id] = binderId or false
        binderFamilies[card.id] = type(binderId) == "string" and (binderId:match("^class:") and "class" or
            (binderId == self.CHARACTER_BINDER_ID and "character")) or "general"
        return binderId
    end
    for _, card in ipairs(profile.cards or {}) do resolveBinder(card) end

    local function evaluate(card, trail)
        if active[card.id] ~= nil then return active[card.id], depths[card.id], specificity[card.id] end
        if trail[card.id] then
            active[card.id], depths[card.id], specificity[card.id] = false, 0, 0
            return false, 0, 0
        end
        trail[card.id] = true
        local parentActive, depth, parentSpecificity = true, 0, 0
        local ownerId = card.parentId or card.homeParentId
        if ownerId then
            local parent = cardsById[ownerId]
            if not parent then
                parentActive = false
            else
                parentActive, depth, parentSpecificity = evaluate(parent, trail)
                depth = depth + 1
            end
        end
        trail[card.id] = nil
        local binderClass = binderIds[card.id] and binderIds[card.id]:match("^class:(.+)$")
        local binderMatches = not binderClass or binderClass == context.class
        active[card.id] = card.enabled ~= false and parentActive and binderMatches and
            NormalizedConditionMatches(normalizedConditions[card.id], context)
        depths[card.id] = depth
        specificity[card.id] = parentSpecificity + conditionSpecificity[card.id]
        return active[card.id], depth, specificity[card.id]
    end

    local result = {}
    for _, card in ipairs(profile.cards or {}) do
        if evaluate(card, {}) then result[#result + 1] = card end
    end
    local children, roots = {}, { general = {}, class = {}, character = {} }
    local branchSpecificity = {}
    local function BranchSpecificity(card)
        if branchSpecificity[card.id] then return branchSpecificity[card.id] end
        local score = specificity[card.id]
        for _, child in ipairs(children[card.id] or {}) do
            score = math.max(score, BranchSpecificity(child))
        end
        branchSpecificity[card.id] = score
        return score
    end
    local function SortPeers(peers)
        table.sort(peers, function(left, right)
            if (left.priority or 0) ~= (right.priority or 0) then
                return (left.priority or 0) < (right.priority or 0)
            end
            local leftSpecificity, rightSpecificity = BranchSpecificity(left), BranchSpecificity(right)
            if leftSpecificity ~= rightSpecificity then return leftSpecificity < rightSpecificity end
            if (left.order or 0) ~= (right.order or 0) then return (left.order or 0) < (right.order or 0) end
            return left.id < right.id
        end)
    end
    for _, card in ipairs(result) do
        local ownerId = card.parentId or card.homeParentId
        if ownerId and active[ownerId] then
            children[ownerId] = children[ownerId] or {}
            children[ownerId][#children[ownerId] + 1] = card
        else
            local family = roots[binderFamilies[card.id]] and binderFamilies[card.id] or "general"
            roots[family][#roots[family] + 1] = card
        end
    end
    SortPeers(roots.general)
    SortPeers(roots.class)
    SortPeers(roots.character)
    for _, peers in pairs(children) do SortPeers(peers) end
    local ordered = {}
    local function Emit(card)
        ordered[#ordered + 1] = card
        for _, child in ipairs(children[card.id] or {}) do Emit(child) end
    end
    for _, family in ipairs({ "general", "class", "character" }) do
        for _, root in ipairs(roots[family]) do Emit(root) end
    end
    return ordered, active
end
