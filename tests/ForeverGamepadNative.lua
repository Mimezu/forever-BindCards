local root = ... or 'Interface/AddOns/BindCards'
local addon, frames, timers = {}, {}, {}
local combat, cursor, failPickup, failPlace = false, nil, false, false
local storage, macros, writes = {}, {}, 0
SlashCmdList = {}
CreateFrame = function()
    local frame = { RegisterEvent = function() end, SetScript = function(self, _, fn) self.onEvent = fn end }
    frames[#frames + 1] = frame
    return frame
end
UnitClass = function() return 'Druid', 'DRUID', 11 end
UnitGUID = function() return 'Player-Test' end
GetRealmName = function() return 'Test' end
InCombatLockdown = function() return combat end
IsInInstance = function() return false, 'none' end
UnitIsPVP = function() return false end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
geterrorhandler = function() return function(message) error(message) end end
for _, file in ipairs({ 'Core', 'Conditions', 'Bindings' }) do
    assert(loadfile(root .. '/' .. file .. '.lua'))('BindCards', addon)
end
addon.RequestRecompile = function() end
addon:InitializeDatabase()
local profile = assert(addon:CreateProfile('Controller', nil, 'class:DRUID'))
addon.GetSelectedProfileSets = function() return nil, profile end
addon.GetPlayerContext = function() return { class = 'DRUID', specGroup = 1, content = 'PVE' } end
local spell = assert(addon:CreateTile(profile.cards[1].id, { kind = 'spell', spellID = 774 }, profile.id))
local macro = assert(addon:CreateTile(profile.cards[1].id, { kind = 'macro', macrotext = '#showtooltip\n/cast Rejuvenation' }, profile.id))
local key = addon:MakeGamepadShortcut('PAD2', false, true, 1)
local key2 = addon:MakeGamepadShortcut('PAD2', false, true, 2)
assert(addon:AssignTileBinding(spell.id, key, profile.id))
C_GamepadUI = {
    GetFirstGamepadActionStorageSlotIndex = function() return 500 end,
    IsValidGamepadActionStorageSlotIndex = function(slot) return slot >= 500 and slot <= 583 end,
}
GetCursorInfo = function() return cursor and cursor.kind, cursor and cursor.id end
ClearCursor = function() cursor = nil end
GetActionInfo = function(slot) local a = storage[slot]; return a and a.kind, a and a.id end
PickupSpell = function(id)
    assert(not combat)
    if failPickup then error('rejected pickup') end
    cursor = { kind = 'spell', id = id }
end
PickupItem = function(id) assert(not combat); cursor = { kind = 'item', id = id } end
PickupAction = function(slot) assert(not combat); writes = writes + 1; cursor, storage[slot] = storage[slot], nil end
PlaceAction = function(slot)
    assert(not combat)
    writes = writes + 1
    -- Native editor removes occupied actions before placement; reject swaps.
    if storage[slot] then return end
    if failPlace and cursor and cursor.id == 774 then return end
    storage[slot], cursor = cursor, storage[slot]
end
GetNumMacros = function() return 0, #macros end
GetMacroInfo = function(index)
    local m = macros[index - 120]
    if m then return m.name, m.icon or 134400, m.body end
end
GetMacroIndexByName = function(name)
    for index, m in ipairs(macros) do if m.name == name then return 120 + index end end
    return 0
end
CreateMacro = function(name, icon, body)
    assert(not combat)
    macros[#macros + 1] = { name = name, icon = icon, body = body }
    return 120 + #macros
end
PickupMacro = function(index) assert(not combat); cursor = { kind = 'macro', id = index } end
local function drain()
    local count = 0
    while #timers > 0 do
        count = count + 1; assert(count < 50, 'timer loop')
        local batch = timers; timers = {}
        for _, fn in ipairs(batch) do fn() end
    end
    assert(not addon.gamepadLastError, addon.gamepadLastError)
end
local eventFrame
local function loadBridge()
    assert(loadfile(root .. '/GamepadBindings.lua'))('BindCards', addon)
    eventFrame = frames[#frames]
    eventFrame.onEvent(eventFrame, 'PLAYER_LOGIN')
    drain()
end
storage[518] = { kind = 'spell', id = 900 }
loadBridge()
assert(storage[518].id == 774, 'RT + right-face must populate native Bar 1')
assert(addon:GetGamepadBindingLabel(key) == 'active')
assert(addon:GetGamepadStorageSlot(key2) == 546)
assert(addon:GetGamepadStorageSlot('GAMEPAD:BAR3:BOTH:PAD1') == 583)
assert(addon:GetGamepadStorageSlot('GAMEPAD:BAR1:RT:PADDRIGHT') == 514)
assert(not addon:GetGamepadStorageSlot('GAMEPAD:BAR1:BASE:PAD2'))
assert(addon:AssignTileBinding(macro.id, key2, profile.id)); drain()
assert(storage[546].kind == 'macro' and #macros == 1 and storage[518].id == 774)
addon:ApplyGamepadBindings(); assert(#macros == 1, 'must reuse native macro')
-- Reload preserves the original underneath the override.
addon.callbacks = {}; loadBridge()
assert(addon:ClearTileBindings(spell.id, profile.id)); drain()
assert(storage[518].id == 900, 'original lost across reload')
assert(addon:ClearTileBindings(macro.id, profile.id)); drain()
assert(not storage[546], 'empty native slot was not restored')
-- A native edit must win even across unrelated BindCards edits and reload.
assert(addon:AssignTileBinding(spell.id, key, profile.id)); drain()
storage[518] = { kind = 'spell', id = 901 }
eventFrame.onEvent(eventFrame, 'ACTIONBAR_SLOT_CHANGED'); drain()
assert(storage[518].id == 901)
assert(addon:AssignTileBinding(macro.id, key2, profile.id)); drain()
assert(storage[518].id == 901)
addon.callbacks = {}; loadBridge(); assert(storage[518].id == 901)
assert(addon:AssignTileBinding(spell.id, key, profile.id)); drain()
assert(storage[518].id == 774)
-- No combat writes; restoration is queued until combat ends.
combat = true
local beforeWrites = writes
assert(addon:ClearTileBindings(spell.id, profile.id)); drain()
assert(writes == beforeWrites and storage[518].id == 774 and addon.gamepadPending)
combat = false; eventFrame.onEvent(eventFrame, 'PLAYER_REGEN_ENABLED'); drain()
assert(storage[518].id == 901, 'latest native assignment must be restored')
-- Never discard a cursor payload to perform an assignment.
cursor = { kind = 'item', id = 42 }
assert(addon:AssignTileBinding(spell.id, key, profile.id)); drain()
assert(cursor.id == 42 and storage[518].id == 901)
cursor = nil; eventFrame.onEvent(eventFrame, 'CURSOR_CHANGED'); drain()
assert(storage[518].id == 774)
-- Rejected pickups/placements retain the baseline and report failure.
assert(addon:ClearTileBindings(spell.id, profile.id)); drain()
failPickup = true
assert(addon:AssignTileBinding(spell.id, key, profile.id)); drain()
assert(storage[518].id == 901 and addon:GetGamepadBindingLabel(key) == 'saved')
failPickup = false; failPlace = true
addon:ApplyGamepadBindings()
assert(storage[518].id == 901 and not cursor)
failPlace = false; addon:ApplyGamepadBindings(); assert(storage[518].id == 774)
-- Unsupported macro replacement restores the prior native action, not the old override.
macro.macrotext = string.rep('x', 256)
assert(addon:AssignTileBinding(macro.id, key, profile.id)); drain()
assert(storage[518].id == 901)
assert(addon:GetGamepadBindingStatus(key):find('255', 1, true))
-- Do not replace native actions whose restoration is unsupported.
storage[518] = { kind = 'flyout', id = 10 }
assert(addon:AssignTileBinding(spell.id, key, profile.id)); drain()
assert(storage[518].kind == 'flyout')
-- Inherited condition priority uses the same card compiler as keyboard bindings.
storage[518] = nil
assert(addon:AssignTileBinding(spell.id, key, profile.id)); drain()
local child = assert(addon:CreateTile(profile.cards[2].id, { kind = 'spell', spellID = 5185 }, profile.id))
assert(addon:AssignTileBinding(child.id, key, profile.id)); drain()
assert(storage[518].id == 5185)
assert(addon:GetGamepadBindingLabel(key, spell.id) == 'saved')
addon.GetPlayerContext = function() return { class = 'DRUID', specGroup = 2, content = 'PVE' } end
addon:ApplyGamepadBindings(); assert(storage[518].id == 774)
profile.bindingsEnabled = false
addon:ApplyGamepadBindings(); assert(not storage[518])
profile.bindingsEnabled = true
-- Native macro restoration resolves its identity after macro indices move.
macro.macrotext = '#showtooltip\n/cast Rejuvenation'
macros[#macros + 1] = { name = 'Original', body = '/dance' }
storage[518] = { kind = 'macro', id = 120 + #macros }
addon:ApplyGamepadBindings(); assert(storage[518].id == 774)
table.insert(macros, 1, { name = 'Inserted', body = '/wave' })
assert(addon:ClearTileBindings(spell.id, profile.id)); drain()
assert(storage[518].kind == 'macro' and GetMacroInfo(storage[518].id) == 'Original')
-- Reserved controls never touch the native action store.
local reserved = addon:MakeGamepadShortcut('PAD2', false, false, 1)
assert(addon:AssignTileBinding(spell.id, reserved, profile.id)); drain()
assert(addon:GetGamepadBindingStatus(reserved) == 'Reserved native control.')
-- Explicit bridge disable restores native actions and survives a reload.
addon.Notify = function() end
storage[518] = { kind = 'spell', id = 910 }
assert(addon:AssignTileBinding(spell.id, key, profile.id)); drain()
assert(storage[518].id == 774)
assert(addon:SetGamepadBindingsEnabled(false)); drain()
assert(storage[518].id == 910)
addon.callbacks = {}; loadBridge(); assert(storage[518].id == 910)
assert(addon:SetGamepadBindingsEnabled(true)); drain()
assert(storage[518].id == 774)
-- Tooltip icons must reach the native macro, including already-saved macros
-- from the old bridge. Preserve those macros rather than editing shared data.
macro.macrotext = '#showtooltip 6196\n/fg cinematic'
C_Spell = { GetSpellInfo = function(id)
    if id == 6196 then return { name = 'Far Sight', spellID = 6196, iconID = 135934 } end
end }
macros[#macros + 1] = { name = 'BCPadOld', body = macro.macrotext, icon = 134400 }
local oldIndex, oldCount = #macros, #macros
assert(addon:AssignTileBinding(macro.id, key2, profile.id)); drain()
local _, nativeIcon, nativeBody = GetMacroInfo(storage[546].id)
assert(nativeIcon == 135934 and nativeBody == macro.macrotext, 'resolved icon missing on native bar')
assert(#macros == oldCount + 1 and macros[oldIndex].icon == 134400, 'must preserve existing macros')
addon:ApplyGamepadBindings(); assert(#macros == oldCount + 1, 'matching icon/body must be reused')
addon.callbacks = {}; loadBridge()
assert(#macros == oldCount + 1, 'reload must reuse resolved macro')
macro.manualIcon = 132222
combat = true
addon:ApplyGamepadBindings(); assert(#macros == oldCount + 1, 'no macro creation in combat')
combat = false; eventFrame.onEvent(eventFrame, 'PLAYER_REGEN_ENABLED'); drain()
local _, manualIcon = GetMacroInfo(storage[546].id)
assert(manualIcon == 132222, 'manual icon must take precedence on native bar')
-- Reported case: Bear Form macro replaces an item on Bar 1 D-pad Left.
local left = addon:MakeGamepadShortcut('PADDLEFT', false, false, 1)
local bear = assert(addon:CreateTile(profile.cards[1].id, {
    kind = 'macro', macrotext = '#showtooltip Bear Form\n/cast Bear Form',
}, profile.id))
storage[500] = { kind = 'item', id = 5350 }
assert(addon:AssignTileBinding(bear.id, left, profile.id)); drain()
assert(storage[500].kind == 'macro' and addon:GetGamepadBindingLabel(left) == 'active')
local _, _, bearBody = GetMacroInfo(storage[500].id)
assert(bearBody == bear.macrotext, 'Bear Form macro text must remain exact')
addon.callbacks = {}; loadBridge()
assert(addon:GetGamepadBindingLabel(left) == 'active', 'replacement must survive reload')
assert(addon:ClearTileBindings(bear.id, profile.id)); drain()
assert(storage[500].kind == 'item' and storage[500].id == 5350, 'original item must restore')
-- Universal controller spells use an unranked native macro and revert to IDs.
C_Spell.GetSpellInfo = function(id)
    return { name = 'Rejuvenation', spellID = id == 'Rejuvenation' and 1058 or id, iconID = 1 }
end
assert(addon:SetTileHighestRank(spell.id, true, profile.id))
addon:ApplyGamepadBindings(); drain()
assert(storage[518].kind == 'macro')
local _, _, universalBody = GetMacroInfo(storage[518].id)
assert(universalBody == '#showtooltip\n/cast Rejuvenation')
assert(addon:SetTileHighestRank(spell.id, false, profile.id))
addon:ApplyGamepadBindings(); drain()
assert(storage[518].kind == 'spell' and storage[518].id == 1058)
print('PASS: native pages, spells/macros, restoration, reload, native edits, combat, cursor, failures and reserved controls')
