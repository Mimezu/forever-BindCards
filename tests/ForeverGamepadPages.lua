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
local profile = assert(addon:CreateProfile('Controller', nil, 'class:DRUID'))
local card = profile.cards[1]
local spell = assert(addon:CreateTile(card.id, { kind = 'spell', spellID = 774 }, profile.id))
local macro = assert(addon:CreateTile(card.id, { kind = 'macro', macrotext = '/cast Rejuvenation' }, profile.id))
local function has(tile, key)
    for _, value in ipairs(tile.bindings) do if value == key then return true end end
    return false
end
local keys = {}
for page = 1, 3 do
    keys[page] = assert(addon:MakeGamepadShortcut('PAD1', false, true, page))
    assert(addon:ParseGamepadShortcut(keys[page]).page == page)
    assert(addon:NormalizeKey(keys[page]:lower()) == keys[page])
    assert(addon:FormatGamepadShortcut(keys[page]):find('Bar ' .. page, 1, true))
end
for _, invalid in ipairs({ 'GAMEPAD:BAR0:RT:PAD1', 'GAMEPAD:BAR4:RT:PAD1',
    'GAMEPAD:BAR01:RT:PAD1', 'GAMEPAD:BAR1:INVALID:PAD1', 'GAMEPAD:BAR2:RT:PADMENU' }) do
    assert(not addon:NormalizeKey(invalid))
end
assert(not addon:MakeGamepadShortcut('PAD1', false, true, 4))
local legacy = 'GAMEPAD:ALL:RT:PAD1'
assert(addon:NormalizeKey(legacy) == legacy)
assert(addon:FormatGamepadShortcut(legacy):find('All bars', 1, true))
assert(addon:AssignTileBinding(spell.id, 'F', profile.id))
assert(addon:AssignTileBinding(spell.id, legacy, profile.id))
for page = 1, 3 do assert(addon:AssignTileBinding(spell.id, keys[page], profile.id)) end
assert(has(spell, 'F') and not has(spell, legacy) and #spell.bindings == 4)
-- Same chord on a different page must not evict the other pages.
assert(addon:AssignTileBinding(macro.id, keys[2], profile.id))
assert(has(spell, keys[1]) and not has(spell, keys[2]) and has(spell, keys[3]))
assert(has(macro, keys[2]))
assert(addon:AssignTileBinding(spell.id, 'G', profile.id))
assert(not has(spell, 'F') and has(spell, keys[1]) and has(spell, keys[3]))
-- Identical keys on conditional child cards must remain independent.
local child = profile.cards[2]
local conditional = assert(addon:CreateTile(child.id, { kind = 'spell', spellID = 5185 }, profile.id))
assert(addon:AssignTileBinding(conditional.id, keys[1], profile.id))
assert(has(spell, keys[1]))
local profileId, spellId, macroId = profile.id, spell.id, macro.id
BindCardsDB = addon.CopyTable(addon.db)
addon:InitializeDatabase()
profile = addon:GetProfile(profileId)
local _, restoredSpell = addon:FindTileOwner(spellId, profileId)
local _, restoredMacro = addon:FindTileOwner(macroId, profileId)
assert(has(restoredSpell, keys[1]) and has(restoredSpell, keys[3]) and has(restoredMacro, keys[2]))
-- Exercise real export/import validation; codec is a deep-copy transport stub.
local envelope
C_EncodingUtil = {
    SerializeJSON = function(value) envelope = addon.CopyTable(value); return '00' end,
    DeserializeJSON = function() return addon.CopyTable(envelope) end,
    CompressString = function(value) return value end,
    DecompressString = function(value) return value end,
    EncodeHex = function(value) return value end,
    DecodeHex = function(value) return value end,
}
local exported = assert(addon:ExportProfile(profileId))
assert(addon:GetImportSummary(exported))
assert(addon:ImportProfile(exported, false))
addon.GetPlayerContext = function() return { class = 'DRUID', specGroup = 1, content = 'PVE' } end
local winners = addon:CompileCurrentBindings(profile)
assert(winners.G, 'keyboard binding must still compile')
for key in pairs(winners) do assert(not addon:IsGamepadShortcut(key), 'saved controller key went live') end
assert(addon:GetGamepadBindingCapabilities().overrides == false)

-- Execute the real capture handlers with lightweight frame stubs.
local file = assert(io.open(root .. '/UI.lua', 'r'))
local source = file:read('*a'); file:close()
local first = assert(source:find('function UI:CreateCapture(parent)', 1, true))
local last = assert(source:find('function UI:ToggleSpellbook()', first, true))
local function frame()
    return setmetatable({ scripts = {} }, { __index = function(_, method)
        if method == 'SetScript' then return function(self, event, callback) self.scripts[event] = callback end end
        if method == 'SetText' then return function(self, text) self.text = text end end
        return function() end
    end })
end
local UI = {}
local assigned
UI.SetEntryBinding = function(_, _, _, key) assigned = key end
local env = setmetatable({
    UI = UI, UIParent = {}, C = {}, Skin = function() end,
    Font = frame, CreateFrame = frame, InCombat = function() return false end,
    Button = function() local button = frame(); button.label = frame(); return button end,
    Call = function(method, ...) return addon[method](addon, ...) end,
}, { __index = _G })
local chunk = assert(loadstring(source:sub(first, last - 1)))
setfenv(chunk, env); chunk()
UI:CreateCapture({})
local capture = UI.capture
capture.gamepadHeld = {}
for page = 1, 3 do
    assigned = nil
    capture.pageButtons[page].scripts.OnClick()
    assert(not assigned and capture.gamepadPage == page)
    capture.scripts.OnGamePadButtonDown(capture, 'PADRTRIGGER')
    capture.scripts.OnGamePadButtonDown(capture, 'PAD1')
    assert(assigned == keys[page], 'capture ignored bar selection')
    capture.scripts.OnGamePadButtonUp(capture, 'PADRTRIGGER')
end
print('PASS: gamepad pages, conflicts, reload, import validation, inactive compilation and capture handlers')
