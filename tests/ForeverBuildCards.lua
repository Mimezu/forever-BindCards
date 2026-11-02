-- Build cards (Primary/Secondary) are generated but editable: rename, change
-- or remove their rules, switch them off. The respec workflow: keep the old
-- build card switched off, add a new card with the same Build rule.
local root = ... or 'Interface/AddOns/BindCards'
local addon = {}
SlashCmdList = {}
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
UnitClass = function() return 'Paladin', 'PALADIN', 2 end
UnitGUID = function() return 'Player-1-Test' end
UnitName = function() return 'Tester' end
GetRealmName = function() return 'Test' end
InCombatLockdown = function() return false end
IsInInstance = function() return false, 'none' end
UnitIsPVP = function() return false end
C_Timer = { After = function() end }
C_Spell = { GetSpellInfo = function(id) return { name = 'Spell ' .. tostring(id), spellID = id, iconID = 1 } end }
for _, file in ipairs({ 'Core', 'Conditions', 'Bindings', 'Serialization' }) do
    assert(loadfile(root .. '/' .. file .. '.lua'))('BindCards', addon)
end
addon.RequestRecompile = function() end
addon:InitializeDatabase()
assert(addon:EnsureDefaultProfile())
local _, class = addon:GetSelectedProfileSets()
local function Find(templateKey)
    for _, card in ipairs(class.cards) do if card.templateKey == templateKey then return card end end
end
local classRoot = assert(Find('default:class:PALADIN'))
local primary = assert(Find('default:specgroup:PALADIN:1'))
local secondary = assert(Find('default:specgroup:PALADIN:2'))
assert(addon:IsBuildCard(secondary) and not addon:IsBuildCard(classRoot))

-- Secondary was Holy: its keys.
local function Tile(card, spellID, key)
    local tile = assert(addon:CreateTile(card.id, { kind = 'spell', spellID = spellID }, class.id))
    assert(addon:AssignTileBinding(tile.id, key, class.id))
    return tile
end
Tile(secondary, 635, '3')        -- Holy Light on 3
Tile(primary, 25780, '1')        -- Righteous Fury on 1 (Primary: Prot)

-- Respec: rename the old card, switch it off, add Ret with Build · Secondary.
assert(addon:UpdateCard(secondary.id, { name = 'Holy' }, class.id), 'build cards can be renamed')
assert(addon:UpdateCard(secondary.id, { enabled = false }, class.id), 'build cards can be switched off')
local ret = assert(addon:CreateCard({ name = 'Retribution', parentId = classRoot.id,
    condition = { specGroup = 2 }, columns = 6 }, class.id))
Tile(ret, 20271, '3')            -- Judgement on the old Holy Light key
local context = { class = 'PALADIN', specGroup = 2, content = 'PVE' }
addon.GetPlayerContext = function() return context end
local winners = addon:CompileCurrentBindings()
assert(winners['3'] and winners['3'].spellID == 20271, 'Ret takes the key while Holy is off')
context.specGroup = 1
winners = addon:CompileCurrentBindings()
assert(winners['1'] and winners['1'].spellID == 25780 and not winners['3'], 'Primary unaffected')

-- Rules are editable too: Holy could be moved to Primary, or have no Build rule.
assert(addon:UpdateCard(secondary.id, { condition = {} }, class.id), 'rules can be removed')
assert(addon:UpdateCard(secondary.id, { condition = { specGroup = 1 } }, class.id), 'rules can change')

-- The load-time template check keeps all of it; no duplicate Secondary appears.
assert(addon:EnsureProfileTemplates(class.id))
assert(secondary.name == 'Holy' and secondary.enabled == false and secondary.condition.specGroup == 1)
local count = 0
for _, card in ipairs(class.cards) do if card.parentId == classRoot.id then count = count + 1 end end
assert(count == 3, 'Primary, Holy and Retribution; no recreated Secondary')

-- And a full reload (SavedVariables + repair).
BindCardsDB = addon.CopyTable(addon.db)
addon:InitializeDatabase()
assert(addon:EnsureDefaultProfile())
_, class = addon:GetSelectedProfileSets()
secondary = assert(Find('default:specgroup:PALADIN:2'), 'template identity survives the reload')
assert(secondary.name == 'Holy' and secondary.enabled == false and secondary.condition.specGroup == 1)
count = 0
classRoot = Find('default:class:PALADIN')
for _, card in ipairs(class.cards) do if card.parentId == classRoot.id then count = count + 1 end end
assert(count == 3)

-- Still protected: build cards cannot be deleted; binder roots stay fixed.
assert(not addon:DeleteCard(secondary.id, class.id), 'build cards are switched off, not deleted')
assert(not addon:UpdateCard(classRoot.id, { name = 'Paly' }, class.id), 'class root keeps its name')
assert(not addon:UpdateCard(classRoot.id, { enabled = false }, class.id), 'class root stays on')
print('PASS: build cards: rename, switch off, edit rules, respec card takes keys, templates and reload keep edits')
