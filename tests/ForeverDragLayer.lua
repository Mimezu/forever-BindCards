-- A dragged or floating stack must draw above the docked binder pages, even
-- when the window sits at a high frame level (it is raised above other UI).
local root = ... or 'Interface/AddOns/BindCards'
local file = assert(io.open(root .. '/UI.lua', 'rb'))
local source = file:read('*a'):gsub('\r\n', '\n'); file:close()
local first = assert(source:find('function UI:ApplyFloatingGroupLayer(view, bringToFront)', 1, true))
local last = assert(source:find('function UI:RaiseFloatingGroup(view)', first, true))
local function Frame(level)
    local f = { level = level or 1, children = {} }
    function f:SetFrameStrata(value) self.strata = value end
    function f:SetFrameLevel(value) self.level = value end
    function f:GetFrameLevel() return self.level end
    function f:GetChildren() return unpack(self.children) end
    function f:IsShown() return true end
    return f
end
local UI = {}
function UI:RefreshEditorChromeLayer() end
local chunk = assert(loadstring('local UI, CardID, min, max, tsort = ...\n' .. source:sub(first, last - 1)))
chunk(UI, function(card) return card and card.id end, math.min, math.max, table.sort)

for _, contentLevel in ipairs({ 5, 120, 400 }) do
    UI.workspaceContent = Frame(contentLevel)
    UI.floatingZOrder, UI.floatingZSerial, UI.cardViews, UI.floatingSheets = nil, nil, {}, nil
    -- Docked pages sit at content+5 with tiles a few levels above.
    local dockedTop = contentLevel + 5 + 12
    local card = { id = 'general', layoutMode = 'floating' }
    local view = Frame(1)
    view.card = card
    view.children = { Frame(1) }
    UI:ApplyFloatingGroupLayer(view, true)
    assert(view.strata == 'DIALOG' and view.level > dockedTop,
        ('stack above docked pages at window level %d (stack %d, docked %d)'):format(contentLevel, view.level, dockedTop))
    assert(view.children[1].level > view.level, 'stack contents above its page')
end
print('PASS: dragged and floating stacks draw above docked pages at any window level')

local function Section(a, b)
    local s = assert(source:find(a, 1, true)); local e = assert(source:find(b, s + #a, true))
    return source:sub(s, e - 1)
end
-- While dragging, the whole stack is lifted above the (top-level) window.
local liftChunk = assert(loadstring('local UI, CardID = ...\n' ..
    Section('function UI:SetDragStrata(view, lifted)', 'function UI:RaiseFloatingGroup(view)')))
liftChunk(UI, function(card) return card and card.id end)
local rootCard = { id = 'general' }
local page = Frame(1); page.card = rootCard; page.children = { Frame(1) }
local sibling = Frame(1); sibling.card = { id = 'sub' }; sibling.groupRoot = rootCard
local tab = Frame(1); tab.groupRoot = rootCard; page.tab = tab
local sheet = Frame(1)
local other = Frame(1); other.card = { id = 'paladin' }; other.strata = 'DIALOG'
UI.cardViews = { general = page, sub = sibling, paladin = other }
UI.floatingSheets = { general = { sheet } }
UI:SetDragStrata(page, true)
for _, f in ipairs({ page, page.children[1], sibling, tab, sheet }) do
    assert(f.strata == 'FULLSCREEN', 'the dragged stack is lifted as a whole')
end
assert(other.strata == 'DIALOG', 'other stacks stay put')
UI:SetDragStrata(page, false)
for _, f in ipairs({ page, page.children[1], sibling, tab, sheet }) do
    assert(f.strata == 'DIALOG', 'restored after the drag')
end

-- Binder mode: the see-through window lets clicks reach the world.
local passChunk = assert(loadstring('local UI, InCombat = ...\n' ..
    Section('function UI:ApplyWorkspacePassThrough(mode)', 'function UI:ApplyWorkspaceMode(mode, preserveSize)')))
local combat = false
passChunk(UI, function() return combat end)
local function Mouse(range)
    local f = { clicks = true, wheel = true }
    function f:SetMouseClickEnabled(value) self.clicks = value end
    function f:EnableMouseWheel(value) self.wheel = value end
    function f:GetVerticalScrollRange() return range or 0 end
    return f
end
UI.frame, UI.workspaceScroll = Mouse(), Mouse(0)
BindCardsDB = { settings = { workspaceMode = 'binder' } }
UI:ApplyWorkspacePassThrough('binder')
assert(UI.frame.clicks == false and UI.workspaceScroll.clicks == false, 'binder mode passes clicks through')
assert(UI.workspaceScroll.wheel == false, 'nothing to scroll: the wheel zooms the camera')
UI.workspaceScroll = Mouse(120); UI.workspaceScroll.clicks = false
UI:UpdateWorkspaceWheel()
assert(UI.workspaceScroll.wheel == true, 'long binders still scroll with the wheel')
BindCardsDB.settings.workspaceMode = 'panel'
UI:ApplyWorkspacePassThrough('panel')
assert(UI.frame.clicks == true and UI.workspaceScroll.clicks == true and UI.workspaceScroll.wheel == true,
    'panel mode keeps its solid window')
combat = true
UI.frame.clicks = 'unchanged'
UI:ApplyWorkspacePassThrough('binder')
assert(UI.frame.clicks == 'unchanged', 'no changes in combat')
print('PASS: drag lifts the whole stack and restores it; binder window passes clicks and idle wheel through')
