-- Schema 4 (0.4.44): the pinned experimental toggles and the BindPad blocker
-- setting leave the saved data; a card with a retail-only rule (role,
-- activity) still loads without error and never binds; the PvP recompile
-- listens to PLAYER_PVP_FLAG_CHANGED when the client has it and to
-- PLAYER_FLAGS_CHANGED otherwise.
local root = ... or 'Interface/AddOns/BindCards'
local registered = {}
SlashCmdList = {}
CreateFrame = function()
    return { RegisterEvent = function(_, event) registered[event] = true end, SetScript = function() end }
end
UnitClass = function() return 'Druid', 'DRUID', 11 end
UnitGUID = function() return 'Player-1-Test' end
GetRealmName = function() return 'Test' end
InCombatLockdown = function() return false end
IsInInstance = function() return false, 'none' end
UnitIsPVP = function() return false end
C_Timer = { After = function() end }
C_EventUtils = { IsEventValid = function(event) return event == 'PLAYER_PVP_FLAG_CHANGED' end }
local function LoadAddon()
    local addon = {}
    for _, file in ipairs({ 'Core', 'Conditions', 'Bindings', 'Serialization' }) do
        assert(loadfile(root .. '/' .. file .. '.lua'))('BindCards', addon)
    end
    addon.RequestRecompile = function() end
    return addon
end
local addon = LoadAddon()
assert(registered.PLAYER_PVP_FLAG_CHANGED and not registered.PLAYER_FLAGS_CHANGED,
    'the PvP flag event replaces PLAYER_FLAGS_CHANGED when the client has it')
assert(addon.SetBindPadSuspended == nil and addon.InstallBindPadRefreshHooks == nil and
    addon.GetCurrentActivity == nil, 'BindPad and activity code is gone')

-- A schema-3 save with the retired keys.
BindCardsDB = {
    schemaVersion = 3, nextId = 1, profiles = {},
    selections = { defaults = { classProfileIds = {} }, characters = {} },
    settings = {
        showAbilityNames = false, gatherLooseSheets = false,
        experimentalBinderStrings = true, experimentalColorPass = true, experimentalCardSizing = true,
        suspendBindPad = true,
    },
}
BindCardsDBBackup = nil
addon:InitializeDatabase()
assert(addon.SCHEMA_VERSION == 4 and addon.db.schemaVersion == 4, 'schema 4')
for _, key in ipairs({ 'experimentalBinderStrings', 'experimentalColorPass', 'experimentalCardSizing', 'suspendBindPad' }) do
    assert(addon.db.settings[key] == nil, key .. ' should be dropped')
end
assert(addon.db.settings.showAbilityNames == false and addon.db.settings.gatherLooseSheets == false,
    'other settings survive the migration')
assert(type(BindCardsDBBackup) == 'table' and BindCardsDBBackup.data.settings.suspendBindPad == true,
    'the pre-migration save is backed up')
assert(addon.db.settings.legacyBindingsRestored == false and type(addon.db.settings.bindingRestore) == 'table',
    'the one-time binding migration flag stays')

-- The migrated save reloads without another migration, repair or backup.
BindCardsDB = addon.CopyTable(addon.db)
BindCardsDBBackup = nil
addon:InitializeDatabase()
assert(BindCardsDBBackup == nil, 'a schema-4 save must not be repaired again')
assert(addon.db.schemaVersion == 4 and addon.db.settings.experimentalCardSizing == nil)

-- Retail-only rules on saved cards: rejected on creation, dropped on load
-- (NormalizeCondition refuses them), never active.
local profile = assert(addon:CreateProfile('Rules', nil, 'general'))
assert(addon:SelectProfile(profile.id))
local rootCard
for _, card in ipairs(profile.cards) do if not card.parentId then rootCard = card break end end
assert(rootCard, 'General root card')
for _, condition in ipairs({ { activity = 'SKYRIDING' }, { role = 'TANK' }, { specID = 102 } }) do
    local created, message = addon:CreateCard({ name = 'Retail', parentId = rootCard.id, condition = condition }, profile.id)
    assert(created == nil and message:find('Retail'), 'retail rules are refused: ' .. tostring(message))
end
local kept = assert(addon:CreateCard({ name = 'Kept', parentId = rootCard.id, condition = { content = 'PVP' } }, profile.id))
local stale = assert(addon:CreateCard({ name = 'Stale', parentId = rootCard.id }, profile.id))
stale.condition = { activity = 'SKYRIDING' } -- as an old save could hold it
assert(not addon:ConditionMatches(stale.condition), 'a retail rule never matches')
BindCardsDB = addon.CopyTable(addon.db)
addon:InitializeDatabase()
local reloaded = assert(addon:GetProfile(profile.id), 'the profile still loads')
local names = {}
for _, card in ipairs(reloaded.cards) do names[card.name] = card end
assert(names.Kept and names.Kept.condition.content == 'PVP', 'ordinary cards survive')
assert(names.Stale == nil, 'the card with the retail rule is dropped by the repair')
for _, card in ipairs(addon:GetActiveCards(reloaded, { class = 'DRUID', content = 'PVP' })) do
    assert(card.condition.activity == nil and card.condition.role == nil)
end

-- Without the new event the old one is registered instead.
registered = {}
C_EventUtils = nil
LoadAddon()
assert(registered.PLAYER_FLAGS_CHANGED and not registered.PLAYER_PVP_FLAG_CHANGED,
    'older clients fall back to PLAYER_FLAGS_CHANGED')
print('PASS: schema 4 drops the experimental and BindPad keys, retail rules stay refused, PvP event fallback')
