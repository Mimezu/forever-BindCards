local root = ... or 'Interface/AddOns/BindCards'
local file = assert(io.open(root .. '/UI.lua', 'r'))
local source = file:read('*a'); file:close()
local first = assert(source:find('function UI:ShowCardMenu(', 1, true))
local last = assert(source:find('function UI:ShowAddRuleMenu(', first, true))
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
local UI = {}
function UI:AddCard(id) assert(not self.cardMenu:IsShown()); self.added = id end
function UI:AddFormCard(card, id) self.form = {card, id} end
function UI:RenameCard(card) self.renamed = card end
function UI:DeleteCard(card) self.deleted = card end
function UI:CanPeelCard() return true end
function UI:ReturnPeeledCard(card) self.returned = card; return true end
function UI:ReturnBinderStack(card) self.returned = card; return true end
local function Call(method, card, values)
    if method == 'GetCardBinderId' then return card.binderId end
    if method == 'GetFormOptions' then return {{id=1,label='Bear'}, {id=3,label='Cat'}} end
    if method == 'UpdateCard' then UI.updated = {card, values}; return true end
    error(method)
end
assert((loadstring or load)('local UI, Button, Skin, C, CursorInside, tinsert, CardName, CardID, IsStandardCard, IsMainBinderRoot, Call, ParentID, Mutate, IsFixedCard = ...\n' .. source:sub(first, last-1)))(
    UI, frame, function() end, {}, function(f) return f and f.inside end, table.insert,
    function(c) return c.name end, function(c) return c.id end,
    function(c) return c.standard end, function(c) return c.main end, Call,
    function(c) return c.parentId end, function(_, fn) return fn() end,
    function(c) return c.standard and not c.build end)
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
print('PASS: GENERAL/DRUID card menus, form choices, actions, reuse and dismissal without native menus')
