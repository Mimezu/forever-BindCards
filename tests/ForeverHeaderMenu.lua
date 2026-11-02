local root = ... or 'Interface/AddOns/BindCards'
local file = assert(io.open(root .. '/UI.lua', 'r'))
local source = file:read('*a'); file:close()
local first = assert(source:find('function UI:ToggleHeaderMenu(', 1, true))
local last = assert(source:find('function UI:ConfigureSpellbookButton(', first, true))
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
    function f:Hide() self.shown = false end
    function f:SetShown(value) self.shown = value end
    f.label = { SetText = function(_, text) f.text = text end }
    return f
end
CreateFrame = function(_, _, _, template)
    assert(template == 'BackdropTemplate', 'menu must not inherit native menu templates')
    return frame()
end
MenuUtil = { CreateContextMenu = function() error('native context menu called') end }
UISpecialFrames = {}
BindCardsDB = { settings = {} }
local UI = { refreshed = 0 }
function UI:RefreshGrid() self.refreshed = self.refreshed + 1 end
function UI:RefreshWorkspace() self.refreshed = self.refreshed + 1 end
function UI:ShowProfiles(owner) self.profileOwner = owner end
function UI:UndoLastChange() self.undone = true end
assert(loadstring('local UI, Button, Skin, C, CursorInside, tinsert = ...\n' ..
    source:sub(first, last - 1)))(UI, frame, function() end, {},
    function(f) return f.inside end, table.insert)
local owner, display = frame(), frame()
local function open()
    UI:ToggleHeaderMenu(owner, display)
    assert(UI.headerMenu:IsShown())
end
local function click(index)
    UI.headerMenu.rows[index].scripts.OnClick()
    assert(not UI.headerMenu:IsShown())
end
open()
assert(#UI.headerMenu.rows == 5)
assert(UI.headerMenu.rows[2].text == '[x] Show ability names')
click(2)
assert(BindCardsDB.settings.showAbilityNames == false and UI.refreshed == 2)
open()
assert(UI.headerMenu.rows[2].text == '[ ] Show ability names')
click(2)
assert(BindCardsDB.settings.showAbilityNames == true)
open(); click(3)
assert(BindCardsDB.settings.gatherLooseSheets == false)
open(); click(1); assert(display:IsShown())
open(); click(4); assert(UI.profileOwner == owner)
local testFramesToggled
Call = function(method) if method == 'ToggleHoverTestFrames' then testFramesToggled = true end end
open(); assert(UI.headerMenu.rows[5].text == 'Test unit frames'); click(5); assert(testFramesToggled)
UI.lastUndo = { label = 'edit' }
open(); assert(UI.headerMenu.rows[1].text == 'Undo edit'); click(1)
assert(UI.undone)
UI.lastUndo = nil
open(); assert(not UI.headerMenu.rows[6]:IsShown())
UI:ToggleHeaderMenu(owner, display); assert(not UI.headerMenu:IsShown())
open(); owner.inside = true
UI.headerMenu.scripts.OnEvent(UI.headerMenu); assert(UI.headerMenu:IsShown())
owner.inside = false
UI.headerMenu.scripts.OnEvent(UI.headerMenu); assert(not UI.headerMenu:IsShown())
open(); owner.scripts.OnHide(); assert(not UI.headerMenu:IsShown())
assert(#UISpecialFrames == 1 and UISpecialFrames[1] == 'BindCardsHeaderMenu')
print('PASS: header menu actions, state, reuse and dismissal without native menus')
