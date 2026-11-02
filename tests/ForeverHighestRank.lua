local root = 'Interface/AddOns/BindCards'
local function read(path)
    local f = assert(io.open(path)); local s = f:read('*a'); f:close(); return s
end
local fixture = read('StorageInvestigation/attach-validation-20260918/tests/BindCardsSmoke.lua')
fixture = fixture:sub(1, assert(fixture:find(';(function()', 1, true)) - 1)
fixture = fixture:gsub('local playerClass = "EVOKER"', 'local playerClass = "DRUID"')
local addon = assert(loadstring(fixture .. '\nreturn BindCards'))(root)
addon.RequestRecompile = function() end
addon:InitializeDatabase()
local learned = 200
C_Spell.GetSpellInfo = function(id)
    return { name = 'Healing Touch', spellID = id == 'Healing Touch' and learned or id, iconID = 1 }
end
IsSpellKnown = function(id) return id == 100 or id == learned end
local profile = assert(addon:CreateProfile('Ranks', nil, 'class:DRUID'))
addon.GetSelectedProfileSets = function() return nil, profile end
addon.GetSelectedProfile = function() return profile end
local tile = assert(addon:CreateTile(profile.cards[1].id, { kind = 'spell', spellID = 100 }, profile.id))
assert(not tile.highestRank)
assert(addon:SetTileBinding(tile.id, 'F6', true, profile.id))
assert(addon:ApplyBindings('exact'))
assert(GetBindingAction('F6', true):find('CLICK ', 1, true) == 1)
assert(addon:SetTileHighestRank(tile.id, true, profile.id))
assert(addon:ApplyBindings('highest'))
assert(GetBindingAction('F6', true) == 'SPELL Healing Touch')
learned = 300
assert(addon:GetHighestLearnedSpellID(tile) == 300)
assert(tile.spellID == 100, 'automatic mode must not rewrite original ID')
local envelope
C_EncodingUtil = {
    SerializeJSON = function(value) envelope = addon.CopyTable(value); return '{}' end,
    CompressString = function(value) return value end, EncodeHex = function() return 'AA' end,
    DecodeHex = function() return '{}' end, DecompressString = function(value) return value end,
    DeserializeJSON = function() return addon.CopyTable(envelope) end,
}
assert(addon:ExportProfile(profile.id))
assert(envelope.schemaVersion == 6 and envelope.profile.cards[1].tiles[1].highestRank)
local imported = assert(addon:ImportProfile('BC01:AA', false))
assert(imported.cards[1].tiles[1].highestRank)
envelope.profile.cards[1].tiles[1].highestRank = 'yes'
assert(not addon:ImportProfile('BC01:AA', false))
envelope.profile.cards[1].tiles[1].highestRank = nil
envelope.schemaVersion = 5
assert(addon:ImportProfile('BC01:AA', false), 'old exports must remain valid')
addon:InitializeDatabase()
profile = addon.db.profiles[profile.id]
tile = profile.cards[1].tiles[1]
assert(tile.highestRank, 'reload must preserve universal mode')
assert(addon:SetTileHighestRank(tile.id, false, profile.id))
assert(not tile.highestRank and tile.spellID == 300)
assert(addon:ApplyBindings('locked'))
assert(GetBindingAction('F6', true):find('CLICK ', 1, true) == 1)
assert(addon:SetTileHighestRank(tile.id, true, profile.id))
assert(addon:ConvertTileToMacro(tile.id, '/cast Healing Touch', 'Heal', 1, profile.id))
assert(not tile.highestRank)
print('PASS: exact default, highest-rank casting, learned-rank lock, reload, export/import and macro cleanup')

-- Replay the close/show ordering used by native center panels, then Escape.
local source = read(root .. '/UI.lua')
local first = assert(source:find('function UI:RememberSpellbookClose()', 1, true))
local last = assert(source:find('function UI:ConfigureSpellbookButton(', first, true))
local UI, timers, hook, combat = {}, {}, nil, false
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
hooksecurefunc = function(name, fn) assert(name == 'ShowUIPanel'); hook = fn end
ShowUIPanel = function() end
local function frame()
    return { shown = false, IsShown = function(self) return self.shown end,
        Show = function(self) self.shown = true end }
end
UI.frame = frame(); UI.RequestRefresh = function() end
PlayerSpellsFrame = frame()
assert(loadstring('local UI, InCombat = ...\n' .. source:sub(first, last - 1)))(UI, function() return combat end)
UI:InstallSpellbookKeepOpen()
local function expire() for _, fn in ipairs(timers) do fn() end; timers = {} end
UI:RememberSpellbookClose(); PlayerSpellsFrame:Show(); hook(PlayerSpellsFrame)
assert(UI.frame:IsShown(), 'P should restore binder')
UI.frame.shown = false; UI:RememberSpellbookClose(); expire()
hook(PlayerSpellsFrame); assert(not UI.frame:IsShown(), 'Escape must stay closed')
UI:RememberSpellbookClose(); hook(frame()); expire()
assert(not UI.frame:IsShown(), 'unrelated panels must not reopen binder')
UI:RememberSpellbookClose(); combat = true; hook(PlayerSpellsFrame)
assert(not UI.frame:IsShown(), 'no restore in combat')
print('PASS: spellbook keeps binder open; Escape, other panels and combat do not reopen it')

-- Drops from the rank-collapsed spellbook follow future ranks; all-ranks drops stay exact.
local showAll = false
C_CVar = { GetCVarBool = function(name) assert(name == 'ShowAllSpellRanks'); return showAll end }
C_Spell.GetSpellSubtext = function(id) return 'Rank ' .. tostring(id / 100) end
learned = 200
IsSpellKnown = function(id) return id == 100 or id == 200 end
GetCursorInfo = function() return 'spell', 1, 'spell', 200 end
assert(addon:GetCursorPayload().highestRank, 'collapsed spellbook drop must follow ranks')
GetCursorInfo = function() return 'spell', 1, 'spell', 100 end
assert(not addon:GetCursorPayload().highestRank, 'lower rank (search results) stays exact')
showAll = true
GetCursorInfo = function() return 'spell', 1, 'spell', 200 end
assert(not addon:GetCursorPayload().highestRank, 'all-ranks spellbook drop stays exact')
showAll = false
C_Spell.GetSpellSubtext = function() return '' end
assert(not addon:GetCursorPayload().highestRank, 'unranked spells stay exact')
local dropped = assert(addon:CreateTile(profile.cards[1].id, { kind = 'spell', spellID = 200, highestRank = true }, profile.id))
assert(dropped.highestRank)
print('PASS: collapsed-spellbook drops follow ranks; all-ranks, low-rank and unranked drops stay exact')

-- Dimming on a new character: a shared class profile holds another
-- character's higher ranks. A highest-rank tile is usable when any rank is
-- known; an exact tile of an unlearned rank stays dim.
local uiSource = read(root .. '/UI.lua')
local dimFrom = assert(uiSource:find('local function EntrySpellUnavailable(entry)', 1, true))
local dimTo = assert(uiSource:find('local ROLE_ATLASES', dimFrom, true))
local known = { [20154] = true } -- Seal of Righteousness Rank 1 only
IsPlayerSpell = function(id) return known[id] == true end
IsSpellKnown = IsPlayerSpell
C_MountJournal = nil
C_Spell.GetOverrideSpell = function(id) return id end
C_Spell.GetSpellInfo = function(id)
    if id == 20287 or id == 20154 then return { name = 'Seal of Righteousness', spellID = id } end
    if id == 'Seal of Righteousness' then return { name = id, spellID = 20154 } end -- best known rank
end
local dimChunk = assert(loadstring(uiSource:sub(dimFrom, dimTo - 1) .. '\nreturn EntrySpellUnavailable'))
setfenv(dimChunk, setmetatable({ Call = function(method, ...) return addon[method](addon, ...) end }, { __index = _G }))
local EntrySpellUnavailable = dimChunk()
assert(not EntrySpellUnavailable({ kind = 'spell', spellID = 20287, highestRank = true }),
    'highest-rank tile with a stored Rank 2 is usable when Rank 1 is known')
assert(EntrySpellUnavailable({ kind = 'spell', spellID = 20287 }), 'exact Rank 2 stays dim at Rank 1')
assert(not EntrySpellUnavailable({ kind = 'spell', spellID = 20154 }))
known = {}
assert(EntrySpellUnavailable({ kind = 'spell', spellID = 20287, highestRank = true }), 'no rank known: dim')
print('PASS: tile dimming follows the highest learned rank for highest-rank tiles')
