local root, uiOverride = ...
root = root or 'Interface/AddOns/BindCards'
local file = assert(io.open(uiOverride or root .. '/UI.lua', 'r'))
local source = file:read('*a'):gsub('\r\n', '\n'); file:close()
local compile = loadstring or load
local function section(first, last)
    local start = assert(source:find(first, 1, true), first)
    local finish = assert(source:find(last, start + #first, true), last)
    return source:sub(start, finish - 1)
end

local addon, UI = {}, {}
SlashCmdList = {}
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
UnitClass = function() return 'Druid', 'DRUID', 11 end
UnitGUID = function() return 'Player-1-Test' end
GetRealmName = function() return 'Test' end
InCombatLockdown = function() return false end
IsInInstance = function() return false, 'none' end
UnitIsPVP = function() return false end
C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end }
C_ClassInfo = { GetClassInfo = function(id)
    return { className = addon.CLASS_FILES[id], classFile = addon.CLASS_FILES[id] }
end }
C_Timer = { After = function() end }
assert(loadfile(root .. '/Core.lua'))('BindCards', addon)
assert(loadfile(root .. '/Conditions.lua'))('BindCards', addon)
addon.RequestRecompile = function() end
addon:InitializeDatabase()
local profile = assert(addon:CreateProfile('Druid', nil, 'class:DRUID'))
local druid, primary, secondary = profile.cards[1], profile.cards[2], profile.cards[3]
local function CardID(card) return card and card.id end
local function ParentID(card) return card and card.parentId end
local function Call(method, ...)
    if method == 'UpdateCard' then
        local id, values = ...
        return addon:UpdateCard(id, values, profile.id)
    end
    error('unexpected API ' .. method)
end
local function Mutate(_, fn) assert(fn() ~= false, 'drop mutation failed') end
function UI:FindCard(id) return addon:GetCard(id, profile.id) end
function UI:GetBinderKeyForCard(card) return card and 'class' end
function UI:SetSelectedCardState(card) self.selectedCardID = card.id end
function UI:RefreshBinderSelectors() end
function UI:RefreshWorkspace() self.rebuilds = (self.rebuilds or 0) + 1 end
function UI:SetDragStrata(view, lifted) self.dragLifted = lifted and view or false end

local cursorX, cursorY = 0, 0
GetCursorPosition = function() return cursorX, cursorY end
local function frame(left, top, width, height, parent)
    local f = { left = left, top = top, width = width, height = height,
        parent = parent, shown = true, level = parent and parent.level + 1 or 0, children = {} }
    if parent then parent.children[#parent.children + 1] = f end
    function f:IsShown() return self.shown end
    function f:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:GetLeft() return self.left end
    function f:GetRight() return self.left + self.width end
    function f:GetTop() return self.top end
    function f:GetBottom() return self.top - self.height end
    function f:GetWidth() return self.width end
    function f:GetHeight() return self.height end
    function f:GetCenter() return self.left + self.width / 2, self.top - self.height / 2 end
    function f:GetEffectiveScale() return 1 end
    function f:StopMovingOrSizing() end
    function f:GetFrameLevel() return self.level end
    function f:SetFrameLevel(level)
        local delta = level - self.level
        self.level = level
        for _, child in ipairs(self.children) do child:SetFrameLevel(child.level + delta) end
    end
    function f:GetChildren() return (unpack or table.unpack)(self.children) end
    function f:SetFrameStrata(strata) self.strata = strata end
    return f
end
UIParent = frame(0, 1000, 1600, 1000)
UI.frame = frame(20, 900, 650, 500, UIParent)
UI.workspaceContent = frame(180, 800, 460, 400, UI.frame)
UI.header = frame(20, 900, 650, 51, UI.frame)
UI.binderBar = frame(20, 845, 650, 30, UI.frame)
local close = frame(640, 890, 20, 20, UI.header)
UI.classBinder = frame(100, 845, 100, 25, UI.binderBar)
local druidView = frame(200, 770, 350, 200, UI.workspaceContent)
druidView.card, druidView.shown = druid, false
druidView.tab = frame(25, 800, 140, 28, UI.frame)
local secondaryView = frame(220, 760, 350, 200, UI.workspaceContent)
secondaryView.card = secondary
secondaryView.tab = frame(50, 760, 120, 28, UI.frame)
local primaryView = frame(700, 700, 350, 200, UIParent)
primaryView.card = primary
primaryView.tab = frame(550, 700, 140, 28, primaryView)
UI.cardViews = { [druid.id] = druidView, [primary.id] = primaryView, [secondary.id] = secondaryView }
local sheet = frame(200, 785, 375, 225, UI.workspaceContent)
sheet.card = druid
UI.binderSheets = { sheet }

local chunk = [[local UI, Call, Mutate, CardID, ParentID = ...
local min, max, floor = math.min, math.max, math.floor
local Helpers = {}
local function IsMainBinderRoot() return false end
local function CardPageHeight() return 200 end
]] .. section('local function CursorInside(', 'local function EntryTileUnderCursor()') ..
    section('function UI:GetRootCard(', 'function UI:GetOwnershipRoot(') ..
    section('function UI:GetCardDropSurfaces(', 'function UI:UpdateHomeBinderHighlight()') ..
    section('function UI:SelectReturnedCardInStack(', 'function UI:ReturnBinderStack(') ..
    section('function UI:FinishCardDrag()', 'function UI:ScheduleDragCancel(') ..
    section('function UI:ApplyEmbeddedLayer(', 'function UI:ApplyDockedEarLayer(')
assert(compile(chunk))(UI, Call, Mutate, CardID, ParentID)

local function peel()
    assert(addon:UpdateCard(primary.id, { parentId = false, homeParentId = druid.id,
        layoutMode = 'floating' }, profile.id))
    UI.dragSession = { card = primary, view = primaryView, originMode = 'floating' }
end
local function dropOn(surface, description)
    peel()
    cursorX, cursorY = surface.left + 4, surface.top - 4
    UI.dragLifted = primaryView
    UI:FinishCardDrag()
    assert(UI.dragLifted == false, 'dropping puts the stack back on the normal layer')
    assert(primary.parentId == druid.id and primary.homeParentId == nil and
        primary.layoutMode == 'stacked', description)
    assert(UI.selectedCardID == primary.id, 'returned build must remain selected')
    assert(not UI.dragSession, 'drop must end the drag')
    assert(#profile.cards == 3, 'reattachment must not duplicate cards')
end
for cycle = 1, 4 do
    dropOn(druidView.tab, 'Primary must return when dropped on the visible Druid ear')
    dropOn(secondaryView.tab, 'the home stack sibling ear must accept the return')
    dropOn(secondaryView, 'the visible home stack page must accept the return')
    dropOn(sheet, 'the exposed ancestor sheet must accept the return')
    dropOn(UI.classBinder, 'the top Class selector must still accept the return')
end

-- Returning to a detached parent must also accept its exposed ancestor sheet.
druid.layoutMode = 'floating'
UI.binderSheets = {}
UI.classBinder:Hide()
local floatingSheet = frame(800, 900, 400, 200, UIParent)
floatingSheet.card = druid
UI.floatingSheets = { [druid.id] = { floatingSheet } }
dropOn(floatingSheet, 'exposed sheets on a detached parent must accept the return')
assert(UI.floatingSelection[druid.id] == primary.id, 'select returned build in detached stack')

-- Releasing away from the owning stack must leave the build detached.
peel(); cursorX, cursorY = 1400, 200
UI:FinishCardDrag()
assert(primary.homeParentId == druid.id and primary.parentId == nil and
    primary.layoutMode == 'floating', 'unrelated screen area must not attach a build')

assert(UI.RefreshEditorChromeLayer, 'the editor header needs an explicit layer above its cards')
primaryView.groupRoot = primary
for _, level in ipairs({ 100, 500, 4000 }) do
    primaryView:SetFrameLevel(level)
    UI:RefreshEditorChromeLayer()
    assert(UI.header.level > primaryView.level + 16, 'floating page and ear must not cover the header')
    assert(close.level > UI.header.level, 'header controls must remain clickable')
    local prior = UI.header.level
    UI:RefreshEditorChromeLayer()
    assert(UI.header.level == prior, 'refreshes must not continually increase frame levels')
end
druid.layoutMode, primary.layoutMode = 'stacked', 'stacked'
UI.frame:SetFrameLevel(500)
UI:RefreshEditorChromeLayer()
assert(UI.header.level > UI.workspaceContent.level + 58, 'header must stay above docked ears after focus changes')
assert(UI.binderBar.level > UI.workspaceContent.level + 58, 'top selectors must stay above scrolled ears')

-- A queued data refresh must not reset the page to its old saved position.
local refreshUI = { frame = UI.frame, dragSession = {} }
assert(compile('local UI = ...\n' .. section('function UI:Refresh()', 'function UI:RequestRefresh()')))(refreshUI)
refreshUI:Refresh()
assert(refreshUI.refreshPending == true, 'refresh should wait until the drag finishes')
-- Exercise the attachment reset and actual docking block, including the old
-- screen anchor left by dragging a root binder. Parenting an anchored floating
-- page into the scroll child is rejected by this model before SetPoint runs.
local dockUI = { workspaceContent = UI.workspaceContent }
assert(compile('local UI = ...\n' .. section('function UI:ResetWorkspaceViewAttachments()',
    'local function DrawPaperGrid(')))(dockUI)
local function anchored(parent)
    local f = { parent = parent, anchor = UIParent }
    function f:Hide() self.hidden = true end
    function f:ClearAllPoints() self.anchor = nil end
    function f:SetParent(p)
        assert(not self.anchor, 'release old anchor family before reparenting')
        self.parent = p
    end
    function f:SetPoint(point, relative, relativePoint, x, y)
        assert(relative == dockUI.workspaceContent and relativePoint == 'TOPLEFT',
            'docked page must explicitly anchor to its scroll child')
        self.anchor, self.x, self.y = relative, x, y
    end
    function f:SetFrameStrata() end
    function f:SetFrameLevel() end
    function f:SetScale() end
    function f:SetSize(w,h) self.width,self.height=w,h end
    return f
end
local page = anchored(UIParent)
page.tab = anchored(page)
local backing = anchored(UIParent)
dockUI.cardViews = { druid = page }
dockUI.floatingSheets = { druid = { backing } }
local docking = section('                view:SetParent(self.workspaceContent);',
    '            if mode == "panel" and not floating then')
-- The extracted block ends with the surrounding floating/docked branch's end.
local dock = assert(compile([[local self, view = ...
local viewWidth, height, pageX, frontPageOffsetY = 409, 300, 45, 0
local pageHeight = 1
local max = math.max
if true then
]] .. docking))
for cycle = 1, 4 do
    page.parent, page.anchor = UIParent, UIParent
    page.tab.parent, page.tab.anchor = page, page
    backing.anchor = page
    dockUI:ResetWorkspaceViewAttachments()
    assert(not backing.anchor and not page.tab.anchor)
    dock(dockUI, page)
    assert(page.parent == dockUI.workspaceContent and page.anchor == dockUI.workspaceContent)
    assert(page.x == 45 and page.y == -5 and page.width == 409)
end
print('PASS: repeated card returns, root docking anchor reset, stable header layers, and deferred drag refresh')
