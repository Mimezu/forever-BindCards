local root = ... or 'Interface/AddOns/BindCards'
local file = assert(io.open(root .. '/UI.lua', 'r'))
local source = file:read('*a'); file:close()
-- The shared popup (ShowMenu), the card menu and the "Add condition" menu.
local first = assert(source:find('function UI:ShowMenu(', 1, true))
local last = assert(source:find('function UI:ApplyTabHierarchy(', first, true))
-- The rule value menu and the condition setter it calls.
local ruleFirst = assert(source:find('function UI:SetConditionValue(', 1, true))
local ruleLast = assert(source:find('function UI:DropDraggedEntry(', ruleFirst, true))
local function frame()
    local f = { scripts = {}, shown = false }
    for _, method in ipairs({'SetWidth', 'SetClampedToScreen', 'EnableMouse',
        'RegisterEvent', 'SetPoint', 'ClearAllPoints', 'SetFrameStrata', 'SetFrameLevel'}) do
        f[method] = function() end
    end
    function f:SetHeight(n) self.height = n end
    function f:SetScript(event, fn) self.scripts[event] = fn end
    f.HookScript = f.SetScript
    function f:IsShown() return self.shown end
    function f:Show() self.shown = true end
    function f:Hide()
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function f:SetEnabled(value) self.enabled = value end
    f.label = { SetText = function(_, text) f.text = text end }
    return f
end
CreateFrame = function(_, _, _, template)
    assert(template == 'BackdropTemplate')
    return frame()
end
MenuUtil = { CreateContextMenu = function() error('native menu must not run in gamepad mode') end }
UISpecialFrames, UIParent = {}, frame()
local UI = { status = {} }
function UI:AddCard(id) assert(not self.cardMenu:IsShown()); self.added = id end
function UI:AddFormCard(card, id) self.form = {card, id} end
function UI:RenameCard(card) self.renamed = card end
function UI:DeleteCard(card) self.deleted = card end
function UI:CanPeelCard() return true end
function UI:ReturnPeeledCard(card) self.returned = card; return true end
function UI:ReturnBinderStack(card) self.returned = card; return true end
function UI:SetStatus(text, kind) self.status = { text, kind } end
UI.conditionOptions = {
    class = { 'Any class', 'DRUID', 'HUNTER' },
    spec = { 'Any build', 'Primary', 'Secondary' },
    content = { 'Any content', 'PVE', 'PVP' },
    form = { 'Any form' },
}
local function Call(method, card, values)
    if method == 'GetCardBinderId' then return card.binderId end
    if method == 'GetFormOptions' then
        if card ~= 'DRUID' then return {} end -- the class file, not a card
        return {{id=1,label='Bear'}, {id=3,label='Cat'}}
    end
    if method == 'UpdateCard' then UI.updated = {card, values}; return true end
    error(method)
end
local function IsFixedCard(c) return c.standard and not c.build end
local function CardID(c) return c.id end
local function Mutate(_, fn) return fn() end
assert((loadstring or load)('local UI, Button, Skin, C, CursorInside, tinsert, CardName, CardID, IsStandardCard, IsMainBinderRoot, Call, ParentID, Mutate, IsFixedCard = ...\n' .. source:sub(first, last-1)))(
    UI, frame, function() end, {}, function(f) return f and f.inside end, table.insert,
    function(c) return c.name end, CardID,
    function(c) return c.standard end, function(c) return c.main end, Call,
    function(c) return c.parentId end, Mutate, IsFixedCard)
local BindCards = {
    FORM_DEFINITIONS = { [1] = { label = 'Bear' }, [3] = { label = 'Cat' } },
    CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end,
}
local function Friendly(value, fallback) return ({ PVE = 'PvE', PVP = 'PvP' })[value] or fallback end
assert((loadstring or load)('local UI, IsFixedCard, BindCards, Mutate, Call, CardID, Friendly = ...\n' ..
    source:sub(ruleFirst, ruleLast - 1)))(UI, IsFixedCard, BindCards, Mutate, Call, CardID, Friendly)
local general = {id='general',name='GENERAL',standard=true,main=true,binderId='general'}
local druid = {id='druid',name='DRUID',standard=true,main=true,binderId='class:DRUID'}
local custom = {id='custom',name='Custom',parentId='druid',binderId='class:DRUID'}
local owner, other = frame(), frame()
local function click(label)
    for _, row in ipairs(UI.cardMenu.rows) do
        if row:IsShown() and row.text == label then
            assert(row.enabled, label .. ' disabled'); row.scripts.OnClick(); return
        end
    end
    error('missing row: ' .. label)
end
local function rows()
    local list = {}
    for _, row in ipairs(UI.cardMenu.rows) do
        if row:IsShown() then list[#list + 1] = row.text end
    end
    return table.concat(list, '|')
end
UI:ShowCardMenu(owner, general)
assert(not UI.cardMenu.rows[2].enabled)
click('New subcard'); assert(UI.added == 'general')
UI:ShowCardMenu(owner, druid)
click('New subcard'); assert(UI.added == 'druid')
UI:ShowCardMenu(owner, druid)
click('New form subcard'); click('< Back'); click('New form subcard'); click('Cat')
assert(UI.form[1] == druid and UI.form[2] == 3 and not UI.cardMenu:IsShown())
UI:ShowCardMenu(owner, general); click('Detach stack')
assert(UI.updated[1] == 'general' and UI.updated[2].layoutMode == 'floating')
UI:ShowCardMenu(owner, custom); click('Rename'); assert(UI.renamed == custom)
UI:ShowCardMenu(owner, custom); click('Take sheet out')
assert(UI.updated[2].homeParentId == 'druid' and UI.updated[2].parentId == false)
UI:ShowCardMenu(owner, custom); click('Delete card'); assert(UI.deleted == custom)
UI:ShowCardMenu(owner, general); UI:ShowCardMenu(other, druid)
owner.scripts.OnHide(); assert(UI.cardMenu:IsShown())
other.scripts.OnHide(); assert(not UI.cardMenu:IsShown())
UI:ShowCardMenu(owner, general); owner.inside = true
UI.cardMenu.scripts.OnEvent(UI.cardMenu); assert(UI.cardMenu:IsShown())
owner.inside = false
UI.cardMenu.scripts.OnEvent(UI.cardMenu); assert(not UI.cardMenu:IsShown())
UI:ShowCardMenu(owner, general); UI:ShowCardMenu(owner, general)
assert(not UI.cardMenu:IsShown())
assert(#UISpecialFrames == 1 and UISpecialFrames[1] == 'BindCardsCardMenu')
-- Build cards (Primary/Secondary) can be renamed but not deleted.
local primary = {id='primary',name='Holy',standard=true,build=true,parentId='druid',binderId='class:DRUID'}
UI:ShowCardMenu(owner, primary)
local renameRow, deleteRow
for _, row in ipairs(UI.cardMenu.rows) do
    if row:IsShown() and row.text == 'Rename' then renameRow = row end
    if row:IsShown() and row.text == 'Delete card' then deleteRow = row end
end
assert(renameRow and renameRow.enabled and not deleteRow, 'build card: rename yes, delete no')
UI.cardMenu:Hide()

-- Rule menus: "+" lists the rule kinds, a kind opens its values in the same
-- popup, a value updates the card. No native menu is involved.
UI.updated = nil
UI:ShowAddRuleMenu(owner, custom)
assert(UI.cardMenu:IsShown() and rows() == 'Add condition|Content|Form|Build', rows())
assert(not UI.cardMenu.rows[1].enabled, 'the title row is not clickable')
click('Content')
assert(UI.cardMenu:IsShown() and UI.cardMenu.owner == owner, 'the value menu opens from the same owner')
assert(rows() == 'Content|PvE|PvP', rows())
click('PvP')
assert(not UI.cardMenu:IsShown() and UI.updated[1] == 'custom' and UI.updated[2].condition.content == 'PVP')
-- A rule that is set offers "Remove condition" first; it clears the rule.
custom.condition = { content = 'PVP' }
UI:ShowConditionMenu(owner, custom, 'content')
assert(rows() == 'Content|Remove condition|PvE|PvP', rows())
click('Remove condition')
assert(UI.updated[2].condition.content == nil)
-- Forms show their names and store the form id; builds store the spec group.
custom.condition = {}
UI:ShowConditionMenu(owner, custom, 'form')
assert(rows() == 'Form|Bear|Cat', rows())
click('Cat'); assert(UI.updated[2].condition.form == 3)
UI:ShowConditionMenu(owner, custom, 'spec'); click('Secondary')
assert(UI.updated[2].condition.specGroup == 2)
UI:ShowConditionMenu(owner, custom, 'class'); click('HUNTER')
assert(UI.updated[2].condition.class == 'HUNTER')
-- A General subcard only gets Content (no class binder, no forms).
local generalSub = {id='gsub', name='Sub', parentId='general', binderId='general'}
UI:ShowAddRuleMenu(owner, generalSub)
assert(rows() == 'Add condition|Content', rows())
UI.cardMenu:Hide()
-- Fixed cards: a status line, no menu, no update.
UI.updated = nil
UI:ShowAddRuleMenu(owner, general)
assert(not UI.cardMenu:IsShown() and UI.status[1] == 'Default card rules are fixed.')
UI:ShowConditionMenu(owner, druid, 'content')
assert(not UI.cardMenu:IsShown() and UI.updated == nil)
-- The same owner again closes; another owner takes the popup over; a click
-- outside closes it. The one special frame handles Escape.
UI:ShowConditionMenu(owner, custom, 'class'); UI:ShowConditionMenu(owner, custom, 'class')
assert(not UI.cardMenu:IsShown())
UI:ShowConditionMenu(owner, custom, 'class'); UI:ShowConditionMenu(other, custom, 'content')
assert(UI.cardMenu:IsShown() and UI.cardMenu.owner == other and rows() == 'Content|PvE|PvP')
owner.inside, other.inside = false, false
UI.cardMenu.scripts.OnEvent(UI.cardMenu); assert(not UI.cardMenu:IsShown())
assert(#UISpecialFrames == 1, 'rule menus reuse the card menu frame')
print('PASS: GENERAL/DRUID card menus, form choices, actions, rule menus, reuse and dismissal without native menus')
