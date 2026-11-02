-- The card a character last had open must survive a reload: the database
-- repair on load used to rebuild character records without lastCardID.
local root = ... or 'Interface/AddOns/BindCards'
local addon = {}
SlashCmdList = {}
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
UnitClass = function() return 'Druid', 'DRUID', 11 end
UnitGUID = function() return 'Player-1-Test' end
GetRealmName = function() return 'Test' end
InCombatLockdown = function() return false end
IsInInstance = function() return false, 'none' end
UnitIsPVP = function() return false end
C_Timer = { After = function() end }
for _, file in ipairs({ 'Core', 'Conditions', 'Bindings', 'Serialization' }) do
    assert(loadfile(root .. '/' .. file .. '.lua'))('BindCards', addon)
end
addon.RequestRecompile = function() end
addon:InitializeDatabase()
local profile = assert(addon:CreateProfile('Remember', nil, 'class:DRUID'))
assert(addon:SelectProfile(profile.id))
local secondary = assert(profile.cards[3] or profile.cards[2], 'expected a non-root card')
local key = addon:GetCurrentCharacterKey()
local record = addon.db.selections.characters[key]
assert(type(record) == 'table', 'selecting a profile creates the character record')
record.lastCardID = secondary.id -- what UI:SaveRememberedSelection writes on hide/logout

-- Simulate logout/login: SavedVariables round-trip through the repair.
BindCardsDB = addon.CopyTable(addon.db)
addon:InitializeDatabase()
local reloaded = addon.db.selections.characters[key]
assert(reloaded and reloaded.lastCardID == secondary.id, 'last open card lost on reload')
local found
for _, card in ipairs(addon:GetProfile(profile.id).cards) do
    if card.id == reloaded.lastCardID then found = true end
end
assert(found, 'remembered card id must still resolve after the repair')
-- A second reload keeps it too (repair is idempotent).
BindCardsDB = addon.CopyTable(addon.db)
addon:InitializeDatabase()
assert(addon.db.selections.characters[key].lastCardID == secondary.id)

-- Malformed values are dropped instead of carried forward.
for _, bad in ipairs({ 42, '', string.rep('x', 129), {} }) do
    addon.db.selections.characters[key].lastCardID = bad
    BindCardsDB = addon.CopyTable(addon.db)
    addon:InitializeDatabase()
    assert(addon.db.selections.characters[key].lastCardID == nil, 'kept malformed lastCardID')
end
print('PASS: last open card survives reload and repeated repairs; malformed values are dropped')
