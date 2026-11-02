-- Mouseover (unit-frame) bindings: key format, assignment, compilation,
-- export/import, native Click Casting conflicts and the capture window.
local root = 'Interface/AddOns/BindCards'
local function read(path)
    local f = assert(io.open(path)); local s = f:read('*a'); f:close(); return s
end
local fixture = read('StorageInvestigation/attach-validation-20260918/tests/BindCardsSmoke.lua')
fixture = fixture:sub(1, assert(fixture:find(';(function()', 1, true)) - 1)
fixture = fixture:gsub('local playerClass = "EVOKER"', 'local playerClass = "PRIEST"')
local addon = assert(loadstring(fixture .. '\nreturn BindCards'))(root)
addon.RequestRecompile = function() end
addon:InitializeDatabase()
C_Spell.GetSpellInfo = function(id) return { name = 'Spell ' .. tostring(id), spellID = id, iconID = 1 } end

-- Key format
assert(addon:NormalizeKey('hover:help:shift-button1') == 'HOVER:HELP:SHIFT-BUTTON1')
assert(addon:NormalizeKey('HOVER:HARM:SHIFT-ALT-F') == 'HOVER:HARM:ALT-SHIFT-F')
assert(addon:NormalizeKey('HOVER:ANY:BUTTON1') == 'HOVER:ANY:BUTTON1', 'plain left click is bindable on frames')
assert(addon:NormalizeKey('HOVER:HELP:BUTTON2') == 'HOVER:HELP:BUTTON2')
assert(addon:NormalizeKey('HOVER:HELP:NUMPAD1') == 'HOVER:HELP:NUMPAD1', 'numpad keys are not gamepad keys')
assert(not addon:NormalizeKey('BUTTON1'), 'plain left click stays unbindable globally')
for _, invalid in ipairs({ 'HOVER:FOCUS:F', 'HOVER:HELP:', 'HOVER:HELP:PAD1', 'HOVER:HELP:SHIFT-PAD1',
    'HOVER:HELP:HOVER:HARM:F', 'HOVER:HELP:GAMEPAD:BAR1:RT:PAD1', 'HOVER:F' }) do
    assert(not addon:NormalizeKey(invalid), invalid)
end
assert(addon:GetHoverScope(true, false) == 'HELP' and addon:GetHoverScope(false, true) == 'HARM')
assert(addon:GetHoverScope(true, true) == 'ANY' and addon:GetHoverScope(false, false) == nil)
assert(addon:MakeHoverBinding('HELP', 'CTRL-SHIFT-BUTTON1') == 'HOVER:HELP:CTRL-SHIFT-BUTTON1')
assert(not addon:MakeHoverBinding('NOPE', 'F') and not addon:MakeHoverBinding('HELP', 'PAD1'))
assert(addon:ParseHoverBinding('HOVER:HARM:F').scope == 'HARM' and addon:ParseHoverBinding('HOVER:HARM:F').key == 'F')
assert(not addon:ParseHoverBinding('F') and not addon:IsHoverBinding('SHIFT-BUTTON1'))
assert(addon:FormatHoverScope('HELP') == 'Friendly frames' and addon:FormatHoverScope('ANY') == 'Friendly or hostile frames')

-- Assignment: one normal key plus one mouseover key per scope on each tile.
local profile = assert(addon:CreateProfile('Hover', nil, 'class:PRIEST'))
addon.GetSelectedProfileSets = function() return nil, profile end
addon.GetSelectedProfile = function() return profile end
local card = profile.cards[1]
local heal = assert(addon:CreateTile(card.id, { kind = 'spell', spellID = 2061 }, profile.id))
local smite = assert(addon:CreateTile(card.id, { kind = 'spell', spellID = 585 }, profile.id))
local function has(tile, key)
    for _, value in ipairs(tile.bindings) do if value == key then return true end end
    return false
end
assert(addon:AssignTileBinding(heal.id, 'F', profile.id))
assert(addon:AssignTileBinding(heal.id, 'HOVER:HELP:SHIFT-BUTTON1', profile.id))
assert(has(heal, 'F') and has(heal, 'HOVER:HELP:SHIFT-BUTTON1'), 'mouseover must not evict the normal key')
assert(addon:AssignTileBinding(heal.id, 'HOVER:HELP:BUTTON1', profile.id))
assert(has(heal, 'F') and has(heal, 'HOVER:HELP:BUTTON1') and not has(heal, 'HOVER:HELP:SHIFT-BUTTON1'),
    'a new key for the same scope replaces the old one')
assert(addon:AssignTileBinding(heal.id, 'HOVER:ANY:BUTTON3', profile.id))
assert(has(heal, 'HOVER:HELP:BUTTON1') and has(heal, 'HOVER:ANY:BUTTON3'), 'scopes coexist')
assert(addon:AssignTileBinding(heal.id, 'G', profile.id))
assert(has(heal, 'G') and not has(heal, 'F') and has(heal, 'HOVER:HELP:BUTTON1'), 'a normal key keeps mouseover keys')
-- Same click, opposite dispositions: the classic heal-friend / nuke-enemy pair.
assert(addon:AssignTileBinding(smite.id, 'HOVER:HARM:BUTTON1', profile.id))
assert(has(heal, 'HOVER:HELP:BUTTON1') and has(smite, 'HOVER:HARM:BUTTON1'))
-- The exact same mouseover key moves between sibling tiles.
assert(addon:AssignTileBinding(smite.id, 'HOVER:ANY:BUTTON3', profile.id))
assert(not has(heal, 'HOVER:ANY:BUTTON3') and has(smite, 'HOVER:ANY:BUTTON3'))
assert(addon:ClearTileHoverBindings(smite.id, 'ANY', profile.id))
assert(has(smite, 'HOVER:HARM:BUTTON1') and not has(smite, 'HOVER:ANY:BUTTON3'), 'clear removes one scope only')

-- Compilation: mouseover keys never become global override bindings.
assert(addon:ApplyBindings('hover'))
assert(GetBindingAction('G', true):find('CLICK ', 1, true) == 1, 'normal key still installs')
assert((GetBindingAction('HOVER:HELP:BUTTON1', true) or '') == '')
assert((GetBindingAction('BUTTON1', true) or '') == '', 'plain left click must stay native')
local winners = addon:CompileCurrentBindings(profile)
for key in pairs(winners) do assert(not addon:IsHoverBinding(key), 'mouseover key went global: ' .. key) end
local hoverWinners = addon.lastCompiledHoverBindings
assert(hoverWinners['HOVER:HELP:BUTTON1'] == heal and hoverWinners['HOVER:HARM:BUTTON1'] == smite)
assert(addon:GetHoverBindingStatus('HOVER:HELP:BUTTON1'):find('Saved', 1, true))
assert(addon:GetHoverBindingStatus('G') == nil)

-- Export/import keeps mouseover keys; malformed ones are rejected.
local envelope
C_EncodingUtil = {
    SerializeJSON = function(value) envelope = addon.CopyTable(value); return '{}' end,
    CompressString = function(value) return value end, EncodeHex = function() return 'AA' end,
    DecodeHex = function() return '{}' end, DecompressString = function(value) return value end,
    DeserializeJSON = function() return addon.CopyTable(envelope) end,
}
assert(addon:ExportProfile(profile.id))
local imported = assert(addon:ImportProfile('BC01:AA', false))
local found = {}
for _, tile in ipairs(imported.cards[1].tiles) do
    for _, key in ipairs(tile.bindings) do found[key] = true end
end
assert(found['HOVER:HELP:BUTTON1'] and found['HOVER:HARM:BUTTON1'] and found.G)
envelope.profile.cards[1].tiles[1].bindings = { 'HOVER:FOCUS:BUTTON1' }
assert(not addon:ImportProfile('BC01:AA', false), 'unknown scope must be rejected')

-- Native Click Casting runs first on Blizzard frames; detect the overlap.
Enum = Enum or {}
Enum.ClickBindingType = { None = 0, Spell = 1, Macro = 2, Interaction = 3, PetAction = 4 }
local nativeProfile = {
    { type = 1, actionID = 2061, button = 'LeftButton', modifiers = 1 },
    { type = 3, actionID = 1, button = 'RightButton', modifiers = 0 },
}
C_ClickBindings = { GetProfileInfo = function() return nativeProfile end }
GetStringFromModifiers = function(mods) return mods == 1 and 'SHIFT' or '' end
assert(addon:GetNativeClickBindingConflict('HOVER:HELP:SHIFT-BUTTON1'))
assert(not addon:GetNativeClickBindingConflict('HOVER:HELP:BUTTON1'), 'modifiers must match exactly')
assert(not addon:GetNativeClickBindingConflict('HOVER:HELP:BUTTON2'), 'native Target/menu interactions are not conflicts')
assert(not addon:GetNativeClickBindingConflict('HOVER:HELP:SHIFT-F'), 'keys are not native clicks')
assert(addon:GetHoverBindingStatus('HOVER:ANY:SHIFT-BUTTON1'):find('Blizzard Click Casting', 1, true))
C_ClickBindings = nil
assert(not addon:GetNativeClickBindingConflict('HOVER:HELP:SHIFT-BUTTON1'), 'clients without native click casting')
print('PASS: mouseover key format, per-scope assignment, no global install, export/import and native click conflicts')

-- Capture window: run the real handlers with lightweight frame stubs.
local source = read(root .. '/UI.lua')
local keysFrom = assert(source:find('local function FormatKey(key, tileId)', 1, true))
local keysTo = assert(source:find('local function EntryBinding(entry)', keysFrom, true))
local captureFrom = assert(source:find('function UI:CreateCapture(parent)', 1, true))
local captureTo = assert(source:find('function UI:ToggleSpellbook()', captureFrom, true))
local function frame()
    return setmetatable({ scripts = {} }, { __index = function(_, method)
        if method == 'SetScript' then return function(self, event, callback) self.scripts[event] = callback end end
        if method == 'SetText' then return function(self, text) self.text = text end end
        if method == 'Hide' then return function(self) self.hidden = true end end
        return function() end
    end })
end
local UI, assigned, cleared, scopeCleared = {}, nil, false, nil
UI.SetEntryBinding = function(_, _, _, key) if key == nil then cleared = true else assigned = key end end
UI.ClearEntryHoverBinding = function(_, _, _, scope) scopeCleared = scope end
local shift = false
local env = setmetatable({
    UI = UI, UIParent = {}, Skin = function() end, SetButtonEnabled = function() end,
    C = { muted = { 1, 1, 1 }, faint = {}, raised = {}, paperAlt = {}, amber = {},
        hoverFriendly = { 0.2, 0.576, 0.498 }, hoverHostile = { 0.769, 0.118, 0.227 } },
    Font = frame, CreateFrame = frame, InCombat = function() return false end,
    Button = function() local button = frame(); button.label = frame(); return button end,
    Call = function(method, ...) return addon[method](addon, ...) end,
    IsShiftKeyDown = function() return shift end,
    IsAltKeyDown = function() return false end, IsControlKeyDown = function() return false end,
}, { __index = _G })
local chunk = assert(loadstring(source:sub(keysFrom, keysTo - 1) .. source:sub(captureFrom, captureTo - 1) ..
    '\nreturn FormatKey, EntryHoverScope'))
setfenv(chunk, env)
local FormatKey, EntryHoverScope = chunk()
assert(FormatKey('HOVER:HELP:SHIFT-BUTTON1') == 'S-M1', 'tile label shows the key, not the scope')
assert(EntryHoverScope({ bindings = { 'F', 'HOVER:HARM:BUTTON3' } }) == 'HARM')
assert(EntryHoverScope({ bindings = { 'F' } }) == nil)
UI:CreateCapture({})
local capture = UI.capture
local function reset() assigned, cleared, scopeCleared, capture.hidden = nil, false, nil, nil end

-- Mouseover mode names the clicks Blizzard Click Casting still runs.
capture:SetHoverScope(true, false)
assert(not capture.help.text:find('Blizzard Click Casting', 1, true), 'no native profile, no hint')
C_ClickBindings = { GetProfileInfo = function() return nativeProfile end }
nativeProfile[#nativeProfile + 1] = { type = 2, actionID = 1, button = 'MiddleButton', modifiers = 3 }
GetStringFromModifiers = function(mods) return ({ [1] = 'SHIFT', [3] = 'ALT-CTRL' })[mods] or '' end
capture:SetHoverScope(true, false)
assert(capture.help.text:find('Blizzard Click Casting still uses: Alt-Ctrl-Middle click, Shift-Left click', 1, true),
    capture.help.text)
capture:SetHoverScope(false, false)
assert(not capture.help.text:find('Blizzard Click Casting', 1, true), 'hint only in mouseover mode')
C_ClickBindings = nil
capture:SetHoverScope(true, false)
reset(); capture.scripts.OnMouseDown(capture, 'LeftButton')
assert(assigned == 'HOVER:HELP:BUTTON1' and capture.hidden, 'plain left click binds on friendly frames')
reset(); capture.scripts.OnMouseDown(capture, 'RightButton')
assert(assigned == 'HOVER:HELP:BUTTON2' and not cleared, 'right click is captured in mouseover mode')
shift = true
reset(); capture.scripts.OnMouseDown(capture, 'LeftButton')
assert(assigned == 'HOVER:HELP:SHIFT-BUTTON1')
shift = false
capture:SetHoverScope(true, true)
reset(); capture.scripts.OnKeyDown(capture, 'F')
assert(assigned == 'HOVER:ANY:F')
reset(); capture.scripts.OnMouseWheel(capture, 1)
assert(assigned == 'HOVER:ANY:MOUSEWHEELUP')
reset(); capture.scripts.OnKeyDown(capture, 'BACKSPACE')
assert(scopeCleared == 'ANY' and not assigned, 'backspace clears only the selected scope')
capture:SetHoverScope(false, true)
reset(); capture.clearButton.scripts.OnClick()
assert(scopeCleared == 'HARM' and not cleared)
capture.gamepadHeld = {}
reset(); capture.scripts.OnGamePadButtonDown(capture, 'PAD1')
assert(not assigned, 'controller gestures are ignored in mouseover mode')
-- Toggles: clicking Friendly adds it; neither toggle returns to normal keys.
capture.hoverButtons[1].scripts.OnClick()
assert(capture:GetHoverScope() == 'ANY')
capture.hoverButtons[1].scripts.OnClick(); capture.hoverButtons[2].scripts.OnClick()
assert(capture:GetHoverScope() == nil)
reset(); capture.scripts.OnMouseDown(capture, 'LeftButton')
assert(not assigned, 'plain left click stays unbindable as a normal key')
reset(); capture.scripts.OnMouseDown(capture, 'RightButton')
assert(cleared, 'right click still clears in normal mode')
reset(); capture.clearButton.scripts.OnClick()
assert(cleared and not scopeCleared)
print('PASS: capture toggles, plain clicks on frames, scoped clear, controller lockout and normal-mode behaviour')

-- Tile marker: bottom-left corner, colors per scope, name inset and restored.
local badgeFrom = assert(source:find('-- The ability name spans the tile bottom', 1, true))
local badgeTo = assert(source:find('function UI:RefreshGrid()', badgeFrom, true))
local function region()
    local r = { points = {}, shown = true }
    -- Store the long form, as the client's GetPoint returns it.
    function r:SetPoint(point, a, b, c, d)
        if type(a) == 'number' or a == nil then a, b, c, d = 'parent', point, a, b end
        self.points[#self.points + 1] = { point, a, b, c, d }
    end
    function r:ClearAllPoints() self.points = {} end
    function r:GetNumPoints() return #self.points end
    function r:GetPoint(i) return unpack(self.points[i]) end
    function r:IsShown() return self.shown end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:SetVertexColor(...) self.color = { ... } end
    function r:CreateTexture() return region() end
    -- Unknown methods are no-ops; unknown fields (hoverBadge, ...) stay nil.
    return setmetatable(r, { __index = function(_, k)
        if type(k) == 'string' and k:match('^%u') then return function() end end
    end })
end
local badgeEnv = setmetatable({
    UI = UI, EntryHoverScope = EntryHoverScope, HOVER_TEXTURE = 'x',
    C = { hoverFriendly = { 0.2, 0.576, 0.498 }, hoverHostile = { 0.769, 0.118, 0.227 } },
    CreateFrame = function() return region() end,
}, { __index = _G })
local badgeChunk = assert(loadstring(source:sub(badgeFrom, badgeTo - 1)))
setfenv(badgeChunk, badgeEnv); badgeChunk()
local tile = region()
tile.GetFrameLevel = function() return 1 end
tile.name = region()
tile.name:SetPoint('BOTTOMLEFT', 6, 5); tile.name:SetPoint('BOTTOMRIGHT', -5, 5)
tile.entry = { bindings = { 'F', 'HOVER:HARM:SHIFT-BUTTON1' } }
UI:StyleHoverBadge(tile)
local badge = assert(tile.hoverBadge)
assert(badge.shown and badge.points[1][1] == 'BOTTOMLEFT', 'marker sits bottom-left')
assert(badge.left.color[1] == 0.769 and badge.right.color[1] == 0.769, 'hostile uses Death Knight red on both halves')
local left, right = tile.name.points[1], tile.name.points[2]
assert(left[1] == 'BOTTOMLEFT' and left[4] == 19 and right[1] == 'BOTTOMRIGHT' and right[4] == -18,
    'name inset symmetrically past the marker')
tile.entry = { bindings = { 'HOVER:ANY:BUTTON3' } }
UI:StyleHoverBadge(tile)
assert(badge.left.color[1] == 0.2 and badge.right.color[1] == 0.769, 'both splits green and red')
assert(tile.name.points[1][4] == 19, 'restyling does not inset twice')
tile.entry = { bindings = { 'F' } }
UI:StyleHoverBadge(tile)
assert(not badge.shown and tile.name.points[1][4] == 6 and tile.name.points[2][4] == -5, 'name restored without marker')
print('PASS: bottom-left mouseover marker, scope colors, and ability-name inset/restore')
