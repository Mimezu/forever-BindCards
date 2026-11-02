-- Phase 3: keys and the mouse wheel while hovering unit frames. The secure
-- snippets from HoverCast.lua run here in an emulated restricted environment
-- (header globals, newtable/pairs, SecureCmdOptionParse, frame handles with
-- per-owner override bindings), following Forever 70009 SecureHandlers.lua.
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
hooksecurefunc = function(a, b, c)
    if type(a) == 'string' then
        local original = _G[a]; _G[a] = function(...) local r = original(...); b(...); return r end
    else
        local original = a[b]; a[b] = function(...) local r = original(...); c(...); return r end
    end
end
function SecureUnitButton_OnClick() end
function CompactUnitFrame_SetUpFrame() end
GetCVarBool = function(name) return name == 'ActionButtonUseKeyDown' end

local HOSTILE = { target = true }
UnitExists = function() return true end
UnitCanAttack = function(_, unit) return HOSTILE[unit] == true end
UnitCanAssist = function(_, unit) return not HOSTILE[unit] end

-- Restricted environment shared by the header and every wrapped snippet.
local restricted = {
    newtable = function() return {} end, pairs = pairs,
    SecureCmdOptionParse = function(options)
        local unit = assert(options:match('%[@([^,]+),harm%]'))
        if HOSTILE[unit] then return 'harm' end
        if options:find(',help]', 1, true) then return 'help' end
        return 'none'
    end,
}
local function Run(code, self, extra)
    local chunk = assert(loadstring(code))
    local env = setmetatable({ self = self }, { __index = restricted, __newindex = restricted })
    for k, v in pairs(extra or {}) do rawset(env, k, v) end
    setfenv(chunk, env)
    return chunk()
end

local function Region(name)
    local frame = { attrs = {}, name = name, overrides = {}, wraps = {}, refs = {} }
    function frame:SetAttribute(k, v) self.attrs[k] = v end
    function frame:GetAttribute(k) return self.attrs[k] end
    function frame:GetName() return self.name end
    function frame:IsForbidden() return false end
    function frame:ClearBindings() self.overrides = {} end
    function frame:SetBindingClick(priority, key, button, token)
        assert(priority == true, 'hover keys must outrank normal overrides')
        self.overrides[key] = { button = button:GetName(), token = token }
    end
    function frame:SetFrameRef(label, ref) self.refs[label] = ref end
    function frame:GetFrameRef(label) return self.refs[label] end
    function frame:Execute(code) Run(code, self) end
    function frame:RegisterForClicks(...) self.clicks = { ... } end
    for _, m in ipairs({ 'SetSize', 'SetAlpha', 'EnableMouse', 'SetPoint', 'Show' }) do frame[m] = function() end end
    if name then _G[name] = frame end
    return frame
end
local baseCreateFrame = CreateFrame
CreateFrame = function(kind, name, ...)
    if name == 'BindCardsHoverHeader' or name == 'BindCardsHoverKeys' then return Region(name) end
    return baseCreateFrame(kind, name, ...)
end
local drivers = {}
RegisterAttributeDriver = function(frame, attr, value) drivers[attr] = { frame = frame, value = value } end
SecureHandlerWrapScript = function(frame, script, header, body)
    assert(not combat, 'wraps are installed out of combat')
    frame.wraps[script] = { header = header, body = body }
end

local function UnitButton(name, unit)
    local frame = Region(name)
    frame.attrs = { ['*type1'] = 'target', ['*type2'] = 'menu', unit = unit }
    function frame:GetScript(which) if which == 'OnClick' then return SecureUnitButton_OnClick end end
    return frame
end
local function Enter(frame) Run(assert(frame.wraps.OnEnter, 'frame not wrapped').body, frame) end
local function Leave(frame) Run(frame.wraps.OnLeave.body, frame) end
-- A key press follows the hovered frame's override to the key button.
local function Press(frame, key)
    local binding = frame.overrides[key]
    if not binding then return nil end
    local button = _G[binding.button]
    local token = binding.token
    local kind = button.attrs['*type-' .. token]
    local value = button.attrs['*spell-' .. token] or button.attrs['*macrotext-' .. token]
    return kind, value, button.attrs.unit
end

assert(loadfile(root .. '/HoverCast.lua'))('BindCards', addon)
local recompiles = {}
addon.RequestRecompile = function(_, reason) recompiles[#recompiles + 1] = reason end
addon:InitializeDatabase()
C_Spell.GetSpellInfo = function(id) return { name = 'Spell ' .. tostring(id), spellID = id, iconID = 1 } end
IsSpellKnown = function() return true end

local party = UnitButton('CompactPartyFrameMember1', 'party1')
local target = UnitButton('TargetFrame', 'target')
-- Forever's PlayerFrame: HealthBar has enableMouseMotion (hover text) and
-- would steal OnEnter/OnLeave from the unit frame. ToT is a nested unit frame.
local function Child(parent, motion, unit, kind)
    local child = Region(nil)
    child.parent, child.motion, child.attrs.unit, child.kind = parent, motion, unit, kind or 'Frame'
    function child:GetObjectType() return self.kind end
    function child:IsMouseMotionEnabled() return self.motion end
    function child:SetPropagateMouseMotion(value) self.propagate = value end
    function child:GetPropagateMouseMotion() return self.propagate end
    function child:GetParent() return self.parent end
    parent.children = parent.children or {}
    parent.children[#parent.children + 1] = child
    function parent:GetChildren() return unpack(self.children) end
    return child
end
local player = UnitButton('PlayerFrame', 'player')
local content = Child(player, false)
local healthBar = Child(content, true, nil, 'StatusBar')
local portraitHover = Child(player, true)
local tot = Child(target, true, 'targettarget')
local totBar = Child(tot, true, nil, 'StatusBar')
-- TargetFrame.Auras answers mouse-motion queries with secret booleans on
-- Forever; testing one threw "attempt to perform boolean test on a secret".
local SECRET = setmetatable({}, { __tostring = function() return '<secret boolean>' end })
issecretvalue = function(value) return value == SECRET end
local auras = Child(target, SECRET)
local auraButton = Child(auras, true, nil, 'StatusBar')
local profile = assert(addon:CreateProfile('Keys', nil, 'class:PRIEST'))
addon.GetSelectedProfileSets = function() return nil, profile end
addon.GetSelectedProfile = function() return profile end
local card = profile.cards[1]
local function Tile(spellID, ...)
    local tile = assert(addon:CreateTile(card.id, { kind = 'spell', spellID = spellID }, profile.id))
    for _, key in ipairs({ ... }) do assert(addon:AssignTileBinding(tile.id, key, profile.id)) end
    return tile
end
local heal = Tile(2061, 'HOVER:HELP:F')
local smite = Tile(585, 'HOVER:HARM:F')
local dispel = Tile(527, 'HOVER:ANY:G')
local wheel = Tile(528, 'HOVER:ANY:SHIFT-MOUSEWHEELUP')
local renew = Tile(139, 'HOVER:HELP:G', 'Q') -- specific beats both on G; Q is a normal key
assert(addon:ApplyBindings('keys'))

local keys = _G.BindCardsHoverKeys
assert(keys and keys.attrs['*type-SPELL 2061'] == 'spell' and keys.attrs['*spell-SPELL 585'] == 585)
assert(keys.attrs.useOnKeyDown == true and keys.clicks[1] == 'AnyDown', 'follows ActionButtonUseKeyDown')
assert(party.wraps.OnEnter and target.wraps.OnLeave, 'unit frames wrapped')
assert(drivers.hasunit and drivers.hasunit.value:find('@mouseover', 1, true))
assert(addon.lastAppliedHoverBindings['HOVER:HELP:F'] == heal)
assert(addon:GetHoverBindingStatus('HOVER:HELP:F'):find('Active while the cursor', 1, true))

-- Mouse-motion children pass motion to the unit frame; nested unit frames don't.
assert(healthBar.propagate == true, 'PlayerFrame health bar must not steal the hover')
assert(content.propagate == nil, 'children without mouse motion are left alone')
assert(tot.propagate == nil and totBar.propagate == nil, 'nested unit frame keeps its own hover')
assert(portraitHover.propagate == nil, 'only StatusBars are changed')
assert(auras.propagate == nil and auraButton.propagate == nil, 'a secret region and its subtree are left alone')

-- The player frame itself (the reported case: E = Judgement, friendly E = Purify).
Enter(player)
local kind, spell, unit = Press(player, 'F')
assert(kind == 'spell' and spell == 2061 and unit == 'player', 'hovering the player frame heals yourself')
Leave(player)

-- /bc hover reports without errors, with the cursor on the health bar.
local said = {}
addon.Notify = function(_, text) said[#said + 1] = text end
GetMouseFoci = function() return { healthBar } end
addon:ReportHoverState()
local report = table.concat(said, '\n')
assert(report:find('Unit frame: PlayerFrame unit=player', 1, true) and report:find('passes motion', 1, true), report)
assert(report:find('F (friendly frames)', 1, true), report)

-- Friendly frame
Enter(party)
local kind, spell, unit = Press(party, 'F')
assert(kind == 'spell' and spell == 2061 and unit == 'party1', 'F heals the hovered friend')
kind, spell = Press(party, 'SHIFT-MOUSEWHEELUP')
assert(kind == 'spell' and spell == 528, 'wheel binding for both scopes')
kind, spell = Press(party, 'G')
assert(spell == 139, 'friendly-specific G beats the both-scope G')
assert(Press(party, 'Q') == nil, 'normal keys are never claimed')
Leave(party)
assert(next(party.overrides) == nil, 'leaving releases every key')

-- Hostile frame
Enter(target)
kind, spell, unit = Press(target, 'F')
assert(kind == 'spell' and spell == 585 and unit == 'target', 'F smites the hovered enemy')
kind, spell = Press(target, 'G')
assert(spell == 527, 'no hostile G, so the both-scope G applies')
Leave(target)

-- A frame hiding under the cursor: the mouseover driver releases its keys.
Enter(party)
assert(party.overrides.F)
local header = _G.BindCardsHoverHeader
Run(header.attrs._onattributechanged, header, { name = 'hasunit', value = 'false' })
assert(next(party.overrides) == nil, 'keys released when the unit is lost')

-- Hover keys outrank the normal override: not a lost binding, no recompile loop.
addon.lastCompiledBindings = { F = heal }
addon.lastAppliedBindingActions = { F = 'CLICK BindCardsBindingProxy:SPELL 1' }
local realGetBindingAction = GetBindingAction
GetBindingAction = function(key, checkOverride)
    if key == 'F' then return checkOverride and 'CLICK BindCardsHoverKeys:SPELL 2061' or '' end
    return realGetBindingAction(key, checkOverride)
end
recompiles = {}
local conflicts = addon:RefreshBindingConflicts()
assert(conflicts.F == nil, 'hover key is not a foreign conflict')
for _, reason in ipairs(recompiles) do assert(reason ~= 'external-binding-change', 'hover key caused a recompile') end
GetBindingAction = realGetBindingAction

-- Frames that appear in combat get their wrap after combat.
local raid = UnitButton('CompactRaidFrame1', 'raid1')
combat = true
CompactUnitFrame_SetUpFrame(raid)
assert(not raid.wraps.OnEnter)
combat = false
assert(addon:ApplyBindings('combat-ended'))
Enter(raid)
kind, spell, unit = Press(raid, 'F')
assert(spell == 2061 and unit == 'raid1')
Leave(raid)

-- Removing every mouseover key empties the tables; wraps claim nothing.
for _, tile in ipairs({ heal, smite, dispel, wheel }) do assert(addon:ClearTileBindings(tile.id, profile.id)) end
assert(addon:ClearTileHoverBindings(renew.id, 'HELP', profile.id))
assert(addon:ApplyBindings('cleared'))
Enter(party)
assert(next(party.overrides) == nil, 'nothing claimed without mouseover keys')
Leave(party)
assert(keys.attrs['*type-SPELL 2061'] == nil, 'stale key actions removed')
print('PASS: hover keys and wheel: disposition, specific-over-both, release on leave and unit loss, no recompile loop, combat wrap, cleanup')

-- Test unit frames (Menu → Test unit frames): stand-ins for party frames.
local function Permissive(name, template)
    local frame = Region(name)
    frame.scripts, frame.shown, frame.template = {}, true, template
    function frame:SetScript(which, fn) self.scripts[which] = fn end
    function frame:GetScript(which)
        if which == 'OnClick' and self.template == 'SecureUnitButtonTemplate' then return SecureUnitButton_OnClick end
        return self.scripts[which]
    end
    function frame:IsShown() return self.shown end
    function frame:SetShown(value)
        self.shown = value
        local script = self.scripts[value and 'OnShow' or 'OnHide']
        if script then script(self) end
    end
    function frame:Hide() self:SetShown(false) end
    function frame:SetMouseMotionEnabled(value) self.motion = value end
    function frame:IsMouseMotionEnabled() return self.motion end
    function frame:SetPropagateMouseMotion(value) self.propagate = value end
    function frame:GetChildren() return unpack(self.children or {}) end
    function frame:CreateTexture() return Permissive() end
    function frame:CreateFontString() return Permissive() end
    return setmetatable(frame, { __index = function(_, k)
        if type(k) == 'string' and k:match('^%u') then return function() end end
    end })
end
CreateFrame = function(kind, name, parent, template)
    local frame = Permissive(name, template)
    frame.kind = kind
    function frame:GetObjectType() return self.kind end
    if parent and parent.children ~= false then
        parent.children = parent.children or {}
        parent.children[#parent.children + 1] = frame
    end
    return frame
end
SecureUnitButton_OnLoad = function(frame, unit)
    frame:SetAttribute('*type1', 'target'); frame:SetAttribute('*type2', 'menu'); frame:SetAttribute('unit', unit)
end
UnitHealth, UnitHealthMax, UnitName = function() return 50 end, function() return 100 end, function(unit) return unit end
local notices = {}
addon.Notify = function(_, text) notices[#notices + 1] = text end

assert(addon:AssignTileBinding(heal.id, 'HOVER:HELP:F', profile.id))
assert(addon:AssignTileBinding(smite.id, 'HOVER:HARM:F', profile.id))
assert(addon:AssignTileBinding(dispel.id, 'HOVER:HARM:SHIFT-BUTTON1', profile.id))
assert(addon:ApplyBindings('test-frames'))
combat = true
assert(not addon:ToggleHoverTestFrames(), 'no toggling in combat')
combat = false
assert(addon:ToggleHoverTestFrames())
local panel = _G.BindCardsHoverTest
assert(panel and panel:IsShown() and #panel.buttons == 5)
local testPlayer, testTarget = panel.buttons[1], panel.buttons[2]
assert(testPlayer:GetAttribute('unit') == 'player' and testTarget:GetAttribute('unit') == 'target')
assert(testTarget:GetAttribute('*type2') == 'togglemenu', 'right click opens the unit menu without a menu function')
assert(addon.hoverCast.frames[testTarget].blizzard, 'same click path as Blizzard party frames')
assert(addon.hoverCast.frames[testTarget].wrapped, 'key handler installed')
assert(testTarget.bar.motion and testTarget.bar.propagate, 'health bar catches motion and passes it on')
assert(testTarget:GetAttribute('shift-harmbutton1') == 'SPELL 527' and testTarget:GetAttribute('shift-type1') == '')
Enter(testTarget)
kind, spell, unit = Press(testTarget, 'F')
assert(kind == 'spell' and spell == 585 and unit == 'target', 'hostile key on the test Target frame')
Leave(testTarget)
Enter(testPlayer)
kind, spell, unit = Press(testPlayer, 'F')
assert(spell == 2061 and unit == 'player')
Leave(testPlayer)
assert(addon:ToggleHoverTestFrames())
assert(not panel:IsShown(), 'second toggle hides the panel')
print('PASS: test unit frames: Blizzard unit-button path, registration, key handler, health-bar motion, casting, combat lock')
