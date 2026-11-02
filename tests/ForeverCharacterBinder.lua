-- Character binder: one set per character (third tab), racials added once,
-- character keys win over class and General, "Copy from" another character,
-- and everything survives the load-time database repair.
local root = ... or 'Interface/AddOns/BindCards'
local addon = {}
SlashCmdList = {}
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
local guid, charName = 'Player-1-AAAA', 'Neige Blanche'
UnitClass = function() return 'Paladin', 'PALADIN', 2 end
UnitGUID = function() return guid end
UnitName = function() return charName end
UnitRace = function() return 'Undead', 'Scourge', 5 end
GetRealmName = function() return 'Test' end
InCombatLockdown = function() return false end
IsInInstance = function() return false, 'none' end
UnitIsPVP = function() return false end
C_Timer = { After = function() end }
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 } }
-- Spellbook: two active racials plus a passive racial and a class spell.
local book = {
    { name = 'Will of the Forsaken', spellID = 7744, isPassive = false, itemType = 1 },
    { name = 'Cannibalize', spellID = 20577, isPassive = false, itemType = 1 },
    { name = 'Shadow Resistance', spellID = 20579, isPassive = true, itemType = 1 },
    { name = 'Holy Light', spellID = 635, isPassive = false, itemType = 1 },
}
local bookLoaded = true
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return bookLoaded and 1 or 0 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #book } end,
    GetSpellBookItemInfo = function(slot) return book[slot] end,
}
local alliedNames = { { name = 'Will of the Forsaken' }, { name = 'Cannibalize' }, { name = 'Shadow Resistance' } }
C_AlliedRaces = { GetAllRacialAbilitiesFromID = function(raceID) return raceID == 5 and alliedNames or nil end }
IsPlayerSpell = function(id)
    if not bookLoaded then return false end -- spell data not loaded yet
    for _, item in ipairs(book) do if item.spellID == id then return true end end
    return false
end
C_Spell = { GetSpellInfo = function(id) return { name = 'Spell ' .. tostring(id), spellID = id, iconID = 1 } end }
for _, file in ipairs({ 'Core', 'Conditions', 'Bindings', 'Serialization' }) do
    assert(loadfile(root .. '/' .. file .. '.lua'))('BindCards', addon)
end
addon.RequestRecompile = function() end
addon:InitializeDatabase()
assert(addon:EnsureDefaultProfile())
local mine = assert(addon:EnsureCharacterProfile())
local function Root(profile) return assert(addon:GetCharacterRootCard(profile)) end
local function SpellIDs(card)
    local ids = {}
    for _, tile in ipairs(card.tiles or {}) do ids[#ids + 1] = tile.spellID end
    table.sort(ids)
    return table.concat(ids, ',')
end

-- Created once, named after the character, racials in it.
assert(mine.binderId == 'character' and mine.ownerKey == guid)
assert(Root(mine).name == 'NEIGE BLANCHE', 'root card named after the character')
assert(SpellIDs(Root(mine)) == '7744,20577', 'active racials only (no passive, no class spell)')
assert(not mine.seedRacials)
assert(addon:EnsureCharacterProfile() == mine, 'second login reuses the set')
assert(#Root(mine).tiles == 2, 'racials are not added twice')

-- Deleting a racial sticks across reloads; the set and its owner survive repair.
local cannibalize
for _, tile in ipairs(Root(mine).tiles) do if tile.spellID == 20577 then cannibalize = tile end end
assert(addon:DeleteTile(cannibalize.id, mine.id))
BindCardsDB = addon.CopyTable(addon.db)
addon:InitializeDatabase()
mine = assert(addon:EnsureCharacterProfile())
assert(mine.ownerKey == guid and mine.binderId == 'character', 'repair keeps the character set')
assert(SpellIDs(Root(mine)) == '7744', 'deleted racial does not come back')
assert(addon.db.selections.characters[guid].characterProfileId == mine.id)
assert(not addon:DeleteProfile(mine.id), 'character cards cannot be deleted as sets')

-- Character keys win over class and General.
local general, class = addon:GetSelectedProfileSets()
local function Tile(profile, card, spellID, key)
    local tile = assert(addon:CreateTile(card.id, { kind = 'spell', spellID = spellID }, profile.id))
    assert(addon:AssignTileBinding(tile.id, key, profile.id))
    return tile
end
local generalRoot, classRoot
for _, card in ipairs(general.cards) do if card.templateKey == 'default:general' then generalRoot = card end end
for _, card in ipairs(class.cards) do if card.templateKey == 'default:class:PALADIN' then classRoot = card end end
Tile(general, generalRoot, 8690, 'F')
Tile(class, classRoot, 635, 'F')
Tile(class, classRoot, 19740, 'G')
local wotf = Root(mine).tiles[1]
assert(addon:AssignTileBinding(wotf.id, 'F', mine.id))
addon.GetPlayerContext = function() return { class = 'PALADIN', specGroup = 1, content = 'PVE' } end
local winners = addon:CompileCurrentBindings()
assert(winners.F and winners.F.spellID == 7744, 'character key beats class and General')
assert(winners.G and winners.G.spellID == 19740, 'other class keys stay')
local composite = addon:GetActiveProfile()
local found
for _, card in ipairs(composite.cards) do if card == Root(mine) then found = true end end
assert(found, 'the character card is part of the active composite')
assert(addon:GetCardBinderId(Root(mine), mine) == 'character' and addon:GetBinderFamily(Root(mine), mine) == 'character')
local mutation = addon:GetMutationProfile('active-composite', 'character')
assert(mutation == mine, 'new cards for the character binder go to this character')

-- A second character: own set, own racials (fallback table), copy from the first.
guid, charName = 'Player-1-BBBB', 'Other Char'
C_AlliedRaces = nil -- API answers nothing: use the fallback table
local theirs = assert(addon:EnsureCharacterProfile())
assert(theirs ~= mine and theirs.ownerKey == guid)
assert(Root(theirs).name == 'OTHER CHAR' and SpellIDs(Root(theirs)) == '7744,20577', 'fallback racials')
local others = addon:GetOtherCharacterSets()
assert(#others == 1 and others[1].id == mine.id)
local mineRootId = Root(mine).id
assert(addon:CopyCharacterSetFrom(mine.id))
theirs = addon:GetSelectedProfileSet('character')
assert(Root(theirs).name == 'OTHER CHAR', 'copied root takes this character name')
assert(Root(theirs).id ~= mineRootId, 'copies get new IDs')
assert(SpellIDs(Root(theirs)) == '7744' and Root(theirs).tiles[1].bindings[1] == 'F', 'copies tiles and keys')
assert(SpellIDs(Root(mine)) == '7744', 'source left untouched')
assert(not addon:CopyCharacterSetFrom(theirs.id), 'cannot copy from itself')

-- A character whose spellbook is not loaded yet waits, then gets racials.
guid, charName = 'Player-1-CCCC', 'Late Book'
bookLoaded = false
local late = assert(addon:EnsureCharacterProfile())
assert(late.seedRacials and #Root(late).tiles == 0, 'waits for the spellbook')
bookLoaded = true
assert(addon:SeedCharacterRacials(late) and not late.seedRacials)
assert(SpellIDs(Root(late)) == '7744,20577')

-- Human (Neige): Forever gives Humans "Will to Survive", which neither the
-- race API nor the classic table knows. The spellbook labels it "Racial".
guid, charName = 'Player-1-DDDD', 'Neige'
UnitRace = function() return 'Human', 'Human', 1 end
C_AlliedRaces = nil
book = {
    { name = 'Perception', spellID = 20600, isPassive = false, itemType = 1, subName = 'Racial' },
    { name = 'Will to Survive', spellID = 59752, isPassive = false, itemType = 1, subName = 'Racial' },
    { name = 'The Human Spirit', spellID = 20598, isPassive = true, itemType = 1, subName = 'Racial Passive' },
    { name = 'Holy Light', spellID = 635, isPassive = false, itemType = 1, subName = 'Rank 1' },
}
local neige = assert(addon:EnsureCharacterProfile())
assert(SpellIDs(Root(neige)) == '20600,59752', 'both active Human racials, found by the spellbook label: ' ..
    SpellIDs(Root(neige)))
-- Localized label: learned from Perception (known through the classic table).
book[1].subName, book[2].subName = 'Raciale', 'Raciale'
local ids = addon:GetRacialSpellIDs()
table.sort(ids)
assert(table.concat(ids, ',') == '20600,59752', 'a translated "Racial" label is learned from a known racial')
-- A rank label on a known racial is never learned: Holy Light (Rank 1) stays out.
book[1].subName = 'Rank 1'
ids = addon:GetRacialSpellIDs()
table.sort(ids)
assert(table.concat(ids, ',') == '20600,59752', 'a rank label is not learned as a racial label: ' .. table.concat(ids, ','))
book[1].subName, book[2].subName = 'Racial', 'Racial'
-- Existing card missing one (seeded by an older version): the menu action adds it.
for index, tile in ipairs(Root(neige).tiles) do
    if tile.spellID == 59752 then table.remove(Root(neige).tiles, index) end
end
assert(SpellIDs(Root(neige)) == '20600')
assert(addon:AddMissingRacials() == 1 and SpellIDs(Root(neige)) == '20600,59752', 'adds the missing racial')
assert(addon:AddMissingRacials() == 0, 'nothing to add the second time')
-- Forever-only races: known racial names count even without the label
-- (Skyborne "Walk on Air"); ordinary spells with no label do not.
book[#book + 1] = { name = 'Walk on Air', spellID = 1400001, isPassive = false, itemType = 1, subName = '' }
book[#book + 1] = { name = 'Flash of Light', spellID = 19750, isPassive = false, itemType = 1, subName = '' }
ids = addon:GetRacialSpellIDs()
local found = {}
for _, id in ipairs(ids) do found[id] = true end
assert(found[1400001] and not found[19750] and not found[635], 'racial names from the Forever list; class spells ignored')
table.remove(book); table.remove(book)
-- Skyborne differ by faction: only what this character's spellbook holds is
-- added (Alliance: Read Ley Line; the Horde-only Skysight never appears).
local savedBook = book
book = {
    { name = 'Walk on Air', spellID = 1400001, isPassive = false, itemType = 1, subName = '' },
    { name = 'Read Ley Line', spellID = 1400002, isPassive = false, itemType = 1, subName = '' },
    { name = 'Wind Blessed', spellID = 1400003, isPassive = true, itemType = 1, subName = '' },
}
UnitRace = function() return 'Skyborne', 'Skyborne', 99 end
ids = addon:GetRacialSpellIDs()
table.sort(ids)
assert(table.concat(ids, ',') == '1400001,1400002', 'Alliance Skyborne: Walk on Air and Read Ley Line only')
-- The launch client spells it "Read Leyline" in some data; both spellings count.
book[2] = { name = 'Read Leyline', spellID = 1400005, isPassive = false, itemType = 1, subName = '' }
ids = addon:GetRacialSpellIDs()
table.sort(ids)
assert(table.concat(ids, ',') == '1400001,1400005', 'Alliance Skyborne: "Read Leyline" spelling')
book[2] = { name = 'Skysight', spellID = 1400004, isPassive = false, itemType = 1, subName = '' }
ids = addon:GetRacialSpellIDs()
table.sort(ids)
assert(table.concat(ids, ',') == '1400001,1400004', 'Horde Skyborne: Walk on Air and Skysight only')
book = savedBook
UnitRace = function() return 'Human', 'Human', 1 end
-- A racial moved to a subcard counts as present.
local sub = assert(addon:CreateCard({ name = 'Utility', parentId = Root(neige).id, columns = 6 }, neige.id))
local moved = Root(neige).tiles[1]
table.remove(Root(neige).tiles, 1)
sub.tiles = sub.tiles or {}
sub.tiles[#sub.tiles + 1] = moved
assert(addon:AddMissingRacials() == 0, 'a racial on a subcard is not added again')

-- No character key (e.g. secret GUID): no set, and nobody else's is shown.
guid = nil
assert(addon:GetSelectedProfileSet('character') == nil)
print('PASS: character binder: per-character sets, racials once, priority, repair, copy from, late spellbook')
