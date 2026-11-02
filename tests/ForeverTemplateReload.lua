local root, coreOverride = ...
root = root or 'Interface/AddOns/BindCards'
local addon = {}
SlashCmdList = {}
CreateFrame = function()
    return { RegisterEvent = function() end, SetScript = function() end }
end
UnitClass = function() return 'Druid', 'DRUID', 11 end
UnitGUID = function() return 'Player-1-Test' end
GetRealmName = function() return 'Test' end
InCombatLockdown = function() return false end
IsInInstance = function() return false, 'none' end
UnitIsPVP = function() return false end
C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end }
C_ClassInfo = { GetClassInfo = function(id)
    return { className = addon.CLASS_FILES[id], classFile = addon.CLASS_FILES[id] }
end }
C_Timer = { After = function() end }
assert(loadfile(coreOverride or root .. '/Core.lua'))('BindCards', addon)
assert(loadfile(root .. '/Conditions.lua'))('BindCards', addon)
addon.RequestRecompile = function() end
addon:InitializeDatabase()
local profile = assert(addon:CreateProfile('Druid', nil, 'class:DRUID'))
local profileId, classId = profile.id, profile.cards[1].id
local ids = { profile.cards[2].id, profile.cards[3].id }

-- Both build templates can be peeled out of their class card. The public
-- mutation API materializes the inherited class restriction in their condition.
for group, id in ipairs(ids) do
    assert(addon:UpdateCard(id, { parentId = false, homeParentId = classId,
        layoutMode = 'floating', floatX = 120 * group, floatY = 40 }, profileId))
    local card = addon:GetCard(id, profileId)
    assert(card.condition.class == 'DRUID', 'peeling should retain the class restriction')
    assert(addon:IsValidTemplateKey(card.templateKey, card.condition),
        'a peeled build template must keep its generated identity')
end

-- Keep user-created cards even when they share a build condition.
local custom = assert(addon:CreateCard({ name = 'My Primary', parentId = classId,
    condition = { class = 'DRUID', specGroup = 1 } }, profileId))
local customId = custom.id
for cycle = 1, 4 do
    BindCardsDB = addon.CopyTable(addon.db)
    addon:InitializeDatabase()
    assert(addon:EnsureProfileTemplates(profileId))
    profile = addon:GetProfile(profileId)
    assert(#profile.cards == 4, 'reload must not add another build card')
    for group, id in ipairs(ids) do
        local card = assert(addon:GetCard(id, profileId), 'original card must survive')
        assert(card.templateKey == 'default:specgroup:DRUID:' .. group)
        assert(card.homeParentId == classId and card.parentId == nil)
        assert(card.layoutMode == 'floating' and card.floatX == 120 * group)
    end
    assert(addon:GetCard(customId, profileId).templateKey == nil,
        'user cards must not be merged into generated cards')
end

-- Docking a peeled card leaves an explicit class condition as well.
for _, id in ipairs(ids) do assert(addon:MoveCard(id, classId, 2, profileId)) end
BindCardsDB = addon.CopyTable(addon.db)
addon:InitializeDatabase()
assert(addon:EnsureProfileTemplates(profileId))
assert(#addon:GetProfile(profileId).cards == 4, 'docked templates must not duplicate')

-- Build cards are editable (0.4.29): their rules may change or go away
-- without losing their identity. Only another class is still rejected.
assert(not addon:IsValidTemplateKey('default:specgroup:DRUID:1', { class = 'MAGE', specGroup = 1 }),
    'a build card cannot move to another class')
for _, condition in ipairs({ { specGroup = 2 }, {}, { class = 'DRUID', specGroup = 1, content = 'PVP' },
    { class = 'DRUID', specGroup = 1, form = 'druid_cat' } }) do
    assert(addon:IsValidTemplateKey('default:specgroup:DRUID:1', condition),
        'edited build card rules keep the card')
end
print('PASS: peeled and docked Primary/Secondary cards retain identity across repeated reloads')
