-- Phase 4: mouseover bindings on form cards (Druid). Reuses the restricted
-- environment harness from ForeverHoverKeys.lua (its setup section, before
-- HoverCast.lua loads) with the class switched to DRUID.
local root = 'Interface/AddOns/BindCards'
local function read(path)
    local f = assert(io.open(path)); local s = f:read('*a'); f:close(); return s
end
local harness = read(root .. '/tests/ForeverHoverKeys.lua')
harness = harness:sub(1, assert(harness:find("assert(loadfile(root .. '/HoverCast.lua'))", 1, true)) - 1)
harness = harness:gsub("'local playerClass = \"PRIEST\"'", "'local playerClass = \"DRUID\"'")
local addon, Region, Run, UnitButton, Enter, Leave, Press, drivers = assert(loadstring(harness ..
    '\nreturn addon, Region, Run, UnitButton, Enter, Leave, Press, drivers'))()

-- Shapeshift mocks as in ForeverFormAttributeDrivers.lua: 1 = Bear, 2 = Cat.
local combat, form = false, 0
InCombatLockdown = function() return combat end
GetNumShapeshiftForms = function() return 2 end
GetShapeshiftFormInfo = function(index) return 1, form == index, true, index == 1 and 5487 or 768 end
GetShapeshiftForm = function() return form end

assert(loadfile(root .. '/HoverCast.lua'))('BindCards', addon)
addon.RequestRecompile = function() end
addon:InitializeDatabase()
C_Spell.GetSpellInfo = function(id) return { name = 'Spell ' .. tostring(id), spellID = id, iconID = 1 } end
IsSpellKnown = function() return true end

local party = UnitButton('CompactPartyFrameMember1', 'party1')
local target = UnitButton('TargetFrame', 'target')
local profile = assert(addon:CreateProfile('Forms', nil, 'class:DRUID'))
addon.GetSelectedProfileSets = function() return nil, profile end
addon.GetSelectedProfile = function() return profile end
local base = profile.cards[1]
local bear = assert(addon:CreateCard({ name = 'BEAR', parentId = base.id, condition = { form = 'druid_bear' } }, profile.id))
local function Tile(card, spellID, key)
    local tile = assert(addon:CreateTile(card.id, { kind = 'spell', spellID = spellID }, profile.id))
    assert(addon:AssignTileBinding(tile.id, key, profile.id))
    return tile
end
Tile(base, 5185, 'HOVER:HELP:F')                -- Healing Touch on friends, any form
Tile(base, 774, 'HOVER:HELP:SHIFT-BUTTON1')     -- Rejuvenation on Shift-Left
Tile(bear, 6795, 'HOVER:HARM:F')                -- Growl on enemies, Bear only
Tile(bear, 22842, 'HOVER:HELP:SHIFT-BUTTON1')   -- Bear overrides Shift-Left on friends
assert(addon:ApplyBindings('forms'))

local header = _G.BindCardsHoverHeader
local plan = addon.hoverCast.plan
assert(plan.hasFormClicks, 'Shift-Left differs in Bear, so clicks follow the form')
assert(drivers.bcform and drivers.bcform.value:find('[form:1] druid_bear', 1, true),
    'hover header follows the same form driver as normal keys')
assert(addon.hoverCast.frames[party].wrapped)
assert(party.attrs['shift-helpbutton1'] == 'SPELL 774', 'out-of-combat stamp uses the current (caster) form')
local function SetForm(state)
    header.attrs.bcform = state
    Run(header.attrs._onattributechanged, header, { name = 'bcform', value = state })
end
function header:RunFor(frame, body) Run(body, frame) end

-- Caster form
SetForm('druid_caster')
Enter(party)
local kind, spell, unit = Press(party, 'F')
assert(spell == 5185 and unit == 'party1')
Leave(party)
Enter(target)
assert(Press(target, 'F') == nil, 'no hostile F outside Bear: F keeps its normal binding')
Leave(target)

-- Shift to Bear in combat while hovering the party frame.
combat = true
Enter(party)
SetForm('druid_bear')
assert(party.attrs['shift-helpbutton1'] == 'SPELL 22842', 'hovered frame re-stamped by the form change in combat')
kind, spell = Press(party, 'F')
assert(spell == 5185, 'base-card friendly F still applies in Bear')
Leave(party)
Enter(target)
kind, spell, unit = Press(target, 'F')
assert(kind == 'spell' and spell == 6795 and unit == 'target', 'Bear card hostile F')
Leave(target)
-- Entering another frame picks up the Bear remaps too.
local raidless = UnitButton('CompactPartyFrameMember2', 'party2')
combat = false
assert(addon:ApplyBindings('member-2'))
combat = true
SetForm('druid_bear')
Enter(raidless)
assert(raidless.attrs['shift-helpbutton1'] == 'SPELL 22842')
Leave(raidless)
-- Back to caster, still in combat.
Enter(party)
SetForm('druid_caster')
assert(party.attrs['shift-helpbutton1'] == 'SPELL 774')
Leave(party)
combat = false

-- Tooltip names the form for a binding that lives on a form card.
assert(addon:GetHoverBindingStatus('HOVER:HARM:F'):find('Active in Bear', 1, true))

-- Bindings only on a form card are still installed while in caster form.
for _, tile in ipairs(base.tiles) do assert(addon:ClearTileBindings(tile.id, profile.id)) end
assert(addon:ApplyBindings('bear-only'))
assert(addon.hoverCast.plan and addon.hoverCast.plan.hasAny, 'form-only bindings keep the secure plan')
SetForm('druid_bear')
Enter(target)
assert(select(2, Press(target, 'F')) == 6795, 'Bear-only binding works after shifting')
Leave(target)

-- Removing everything restores the frames and clears the tables.
for _, tile in ipairs(bear.tiles) do assert(addon:ClearTileBindings(tile.id, profile.id)) end
assert(addon:ApplyBindings('cleared'))
assert(party.attrs['shift-helpbutton1'] == nil and party.attrs['shift-type1'] == nil, 'attributes restored')
SetForm('druid_bear')
Enter(party)
assert(next(party.overrides) == nil)
Leave(party)
print('PASS: form cards: per-form keys and clicks, in-combat shift while hovering, form-only bindings, tooltip, restore')
