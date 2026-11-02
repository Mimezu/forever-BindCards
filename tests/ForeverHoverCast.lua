-- Phase 2: mouseover clicks cast on unit frames. The secure click path is
-- emulated from Forever 1.60.1 (70009) SecureTemplates.lua:
-- SecureUnitButton_OnClick (native Click Casting first, then the Target/menu
-- drop rule) and GetConvertedButtonUnitAndActionType (help/harm remap).
local root = 'Interface/AddOns/BindCards'
local function read(path)
    local f = assert(io.open(path)); local s = f:read('*a'); f:close(); return s
end
local fixture = read('StorageInvestigation/attach-validation-20260918/tests/BindCardsSmoke.lua')
fixture = fixture:sub(1, assert(fixture:find(';(function()', 1, true)) - 1)
fixture = fixture:gsub('local playerClass = "EVOKER"', 'local playerClass = "PRIEST"')
local addon = assert(loadstring(fixture .. '\nreturn BindCards'))(root)
local combat = false
InCombatLockdown = function() return combat end
ATTRIBUTE_NOOP = ''
local hooks = {}
hooksecurefunc = function(a, b, c)
    if type(a) == 'string' then
        local original = _G[a]
        _G[a] = function(...) local r = original(...); b(...); return r end
    else
        local original = a[b]
        a[b] = function(...) local r = original(...); c(...); return r end
    end
    hooks[#hooks + 1] = a
end
function SecureUnitButton_OnClick() end -- identity only; the flow is emulated below
function CompactUnitFrame_SetUpFrame(frame) end
assert(loadfile(root .. '/HoverCast.lua'))('BindCards', addon)
addon.RequestRecompile = function() end
addon:InitializeDatabase()
C_Spell.GetSpellInfo = function(id) return { name = 'Spell ' .. tostring(id), spellID = id, iconID = 1 } end
IsSpellKnown = function() return true end

-- Units: party1 friendly, target hostile.
local HOSTILE = { target = true }
UnitExists = function() return true end
UnitCanAttack = function(_, unit) return HOSTILE[unit] == true end
UnitCanAssist = function(_, unit) return not HOSTILE[unit] end

local function UnitButton(name, unit, blizzard)
    local frame = { attrs = { ['*type1'] = 'target', ['*type2'] = 'menu', unit = unit }, name = name }
    function frame:SetAttribute(k, v) self.attrs[k] = v end
    function frame:GetAttribute(k) return self.attrs[k] end
    function frame:GetScript(which) if which == 'OnClick' and blizzard then return SecureUnitButton_OnClick end end
    function frame:IsForbidden() return false end
    if name then _G[name] = frame end
    return frame
end

-- Emulation of the Forever secure click path.
local modifiers = ''
local SUFFIX = { LeftButton = '1', RightButton = '2', MiddleButton = '3', Button4 = '4', Button5 = '5' }
local function Get(frame, name, button)
    local suffix = SUFFIX[button] or ('-' .. button)
    for _, attr in ipairs({ modifiers .. name .. suffix, '*' .. name .. suffix, modifiers .. name .. '*', '*' .. name .. '*', name }) do
        local value = frame.attrs[attr]
        if value ~= nil then
            if value == '' then return nil end
            return value
        end
    end
end
-- Native profile: only the default Target / menu interactions (user removed spells).
local function NativeBindingType(button)
    if modifiers == '' and (button == 'LeftButton' or button == 'RightButton') then return 'Interaction' end
    return 'None'
end
local function Click(frame, button)
    local bindingType = frame:GetScript('OnClick') and NativeBindingType(button) or nil
    if frame:GetScript('OnClick') then
        local t = Get(frame, 'type', button)
        if (t == 'target' or t == 'menu' or t == 'togglemenu') and bindingType == 'None' then return 'dropped' end
    end
    local unit = Get(frame, 'unit', button)
    local original = button
    if UnitCanAttack('player', unit) then button = Get(frame, 'harmbutton', button) or button
    elseif UnitCanAssist('player', unit) then button = Get(frame, 'helpbutton', button) or button end
    if button ~= original then unit = Get(frame, 'unit', button) end
    local t = Get(frame, 'type', button)
    if t == 'spell' then return 'spell', Get(frame, 'spell', button), unit end
    if t == 'macro' then return 'macro', Get(frame, 'macrotext', button), unit end
    return t, nil, unit
end
local function Copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
local function Same(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

local party = UnitButton('CompactPartyFrameMember1', 'party1', true)
local target = UnitButton('TargetFrame', 'target', true)
local partyOriginal, targetOriginal = Copy(party.attrs), Copy(target.attrs)

-- Control: Blizzard drops an unbound Shift-Left before any addon remap.
modifiers = 'shift-'
party.attrs['shift-helpbutton1'] = 'X'
assert(Click(party, 'LeftButton') == 'dropped', 'emulation must reproduce the native drop')
party.attrs['shift-helpbutton1'] = nil
modifiers = ''

local profile = assert(addon:CreateProfile('Clicks', nil, 'class:PRIEST'))
addon.GetSelectedProfileSets = function() return nil, profile end
addon.GetSelectedProfile = function() return profile end
local card = profile.cards[1]
local function Tile(spellID, key)
    local tile = assert(addon:CreateTile(card.id, { kind = 'spell', spellID = spellID }, profile.id))
    assert(addon:AssignTileBinding(tile.id, key, profile.id))
    return tile
end
local heal = Tile(2061, 'HOVER:HELP:SHIFT-BUTTON1')
local renew = Tile(139, 'HOVER:HELP:BUTTON1')
local smite = Tile(585, 'HOVER:HARM:SHIFT-BUTTON1')
local dispel = Tile(527, 'HOVER:ANY:BUTTON3')
local keyed = Tile(17, 'HOVER:HELP:F')
local macro = assert(addon:CreateTile(card.id, { kind = 'macro', macrotext = '/cast [@mouseover] Spell 8092' }, profile.id))
assert(addon:AssignTileBinding(macro.id, 'HOVER:HARM:CTRL-BUTTON2', profile.id))
assert(addon:ApplyBindings('hover-cast'))

-- Friendly frame
modifiers = 'shift-'
local kind, spell, unit = Click(party, 'LeftButton')
assert(kind == 'spell' and spell == 2061 and unit == 'party1', 'Shift-Left heals the hovered friend')
modifiers = ''
kind, spell, unit = Click(party, 'LeftButton')
assert(kind == 'spell' and spell == 139 and unit == 'party1', 'plain Left bound to friendly frames casts')
assert(Click(party, 'RightButton') == 'menu', 'unbound Right keeps the unit menu')
kind, spell = Click(party, 'MiddleButton')
assert(kind == 'spell' and spell == 527, 'both-scope Middle click on a friend')
modifiers = 'ctrl-'
assert(Click(party, 'RightButton') == nil, 'hostile-only Ctrl-Right does nothing on a friend (as natively)')

-- Hostile frame
modifiers = 'shift-'
kind, spell, unit = Click(target, 'LeftButton')
assert(kind == 'spell' and spell == 585 and unit == 'target', 'Shift-Left smites the hovered enemy')
modifiers = ''
assert(Click(target, 'LeftButton') == 'target', 'friendly-only plain Left keeps Target on enemies')
kind, spell = Click(target, 'MiddleButton')
assert(kind == 'spell' and spell == 527, 'both-scope Middle click on an enemy')
modifiers = 'ctrl-'
kind, spell = Click(target, 'RightButton')
assert(kind == 'macro' and spell:find('@mouseover', 1, true), 'macro tiles run on hostile Ctrl-Right')
modifiers = ''

-- Status and UI state
assert(addon.lastAppliedHoverBindings['HOVER:HELP:SHIFT-BUTTON1'] == heal)
assert(not addon.lastAppliedHoverBindings['HOVER:HELP:F'], 'keys need secure hover handlers (not mocked here)')
assert(addon:GetHoverBindingStatus('HOVER:HELP:SHIFT-BUTTON1'):find('Active on unit frames', 1, true))
assert(addon:GetHoverBindingStatus('HOVER:HELP:F'):find('unavailable', 1, true))
assert(addon:GetHoverBindingStatus('HOVER:HARM:CTRL-BUTTON2'):find('@mouseover', 1, true))
for key in pairs(addon:CompileCurrentBindings(profile)) do assert(not addon:IsHoverBinding(key)) end

-- Frames set up in combat wait; the post-combat recompile stamps them.
local raid = UnitButton('CompactRaidFrame1', 'raid1', true)
combat = true
CompactUnitFrame_SetUpFrame(raid)
assert(raid.attrs['shift-helpbutton1'] == nil, 'no attribute writes in combat')
assert(not addon:ApplyBindings('combat'))
combat = false
assert(addon:ApplyBindings('combat-ended'))
modifiers = 'shift-'
kind, spell, unit = Click(raid, 'LeftButton')
assert(kind == 'spell' and spell == 2061 and unit == 'raid1', 'queued frame stamped after combat')
modifiers = ''

-- Third-party frames through the ClickCastFrames registry: no NOOP needed.
local custom = UnitButton(nil, 'party2', false)
ClickCastFrames[custom] = true
assert(ClickCastFrames[custom] == true)
modifiers = 'shift-'
kind, spell = Click(custom, 'LeftButton')
assert(kind == 'spell' and spell == 2061 and custom.attrs['shift-type1'] == nil)
modifiers = ''

-- Rebinding moves the action; removing every binding restores all frames.
assert(addon:AssignTileBinding(heal.id, 'HOVER:HELP:ALT-BUTTON1', profile.id))
assert(addon:ApplyBindings('rebind'))
assert(party.attrs['shift-type1'] == '' and party.attrs['alt-type1'] == '', 'smite still owns Shift-Left')
modifiers = 'alt-'
kind, spell = Click(party, 'LeftButton')
assert(kind == 'spell' and spell == 2061)
modifiers = ''
for _, tile in ipairs({ heal, renew, smite, dispel, keyed, macro }) do assert(addon:ClearTileBindings(tile.id, profile.id)) end
assert(addon:ApplyBindings('cleared'))
assert(Same(party.attrs, partyOriginal) and Same(target.attrs, targetOriginal), 'every attribute restored')
assert(next(addon.lastAppliedHoverBindings) == nil)

-- Clique owns unit frames when loaded: BindCards restores and steps aside.
assert(addon:AssignTileBinding(heal.id, 'HOVER:HELP:SHIFT-BUTTON1', profile.id))
assert(addon:ApplyBindings('again'))
assert(party.attrs['shift-helpbutton1'] ~= nil)
ClickCastHeader = {}
assert(addon:ApplyBindings('clique'))
assert(Same(party.attrs, partyOriginal), 'restored for Clique')
assert(addon:GetHoverBindingStatus('HOVER:HELP:SHIFT-BUTTON1'):find('Clique', 1, true))
ClickCastHeader = nil
print('PASS: unit-frame click casting: friendly/hostile/both, native drop avoided, Target/menu fallthrough, combat queue, registry, restore, Clique')
