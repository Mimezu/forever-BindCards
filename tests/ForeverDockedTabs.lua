local root = ... or 'Interface/AddOns/BindCards'
local addon = {}
assert(loadfile(root .. '/UIHelpers.lua'))('BindCards', addon)
local file = assert(io.open(root .. '/UI.lua', 'r'))
local source = file:read('*a'):gsub('\r\n', '\n'); file:close()
local function section(first, last)
    local start = assert(source:find(first, 1, true))
    local finish = assert(source:find(last, start + #first, true))
    return source:sub(start, finish - 1)
end
local UI = {}
assert(loadstring('local UI, Helpers, min = ...\n' ..
    section('function UI:ApplyEmbeddedLayer(', 'function UI:UpdateBinderStrings()')))(
    UI, addon.UIHelpers, math.min)

-- Model normal frame ancestry: raising a parent also raises its children.
local function frame(parent, level)
    local f = { parent = parent, level = level, children = {}, scale = 1 }
    function f:GetChildren() return unpack(self.children) end
    function f:GetFrameLevel() return self.level end
    function f:SetFrameLevel(value)
        local delta = value - self.level
        self.level = value
        for _, child in ipairs(self.children) do child:SetFrameLevel(child.level + delta) end
    end
    function f:SetFrameStrata(value) self.strata = value end
    function f:SetScale(value) self.scale = value end
    function f:EnableMouse(value) self.mouseEnabled = value end
    function f:SetParent(value)
        if self.parent then
            for i, child in ipairs(self.parent.children) do
                if child == self then table.remove(self.parent.children, i); break end
            end
        end
        self.parent = value
        value.children[#value.children + 1] = self
    end
    if parent then parent.children[#parent.children + 1] = f end
    return f
end
UIParent = frame(nil, 0)
UI.frame = frame(UIParent, 120)
local scroll = frame(UI.frame, 122)
UI.workspaceContent = frame(scroll, 123)
local page = frame(UI.workspaceContent, 124)
local tile = frame(page, 125)
UI:ApplyEmbeddedLayer(page, UI.workspaceContent:GetFrameLevel() + 30)

local tabs = {}
for _, id in ipairs({'DRUID', 'Primary', 'Secondary'}) do
    local tab = frame(UIParent, 0)
    local expand = frame(tab, 1)
    UI:ApplyDockedEarLayer(tab, id == 'Primary')
    assert(tab.level > tile.level, 'docked tabs must receive clicks above a raised DIALOG page')
    assert(expand.level > tab.level, 'expand control must receive its own clicks')
    assert(tab.parent == UI.frame, 'tabs must follow editor focus without scroll clipping')
    assert(tab.scale == 1 and tab.mouseEnabled, 'tabs inherit editor scale and accept clicks')
    tabs[#tabs + 1] = tab
end
UI.frame:SetFrameLevel(400)
for _, tab in ipairs(tabs) do
    assert(tab.level > tile.level, 'raising the editor must not strand its tabs underneath')
end

-- Exercise the actual tab selection callback after hit-testing its layer.
local clickSource = section('    view.tab:SetScript("OnClick", function()',
    '    view.tab:SetScript("OnEnter", function(self)')
local selected
function UI:SelectCard(card) selected = card.id end
for i, id in ipairs({'DRUID', 'Primary', 'Secondary'}) do
    local view = { card = { id = id }, tab = tabs[i] }
    function view.tab:SetScript(event, fn) assert(event == 'OnClick'); self.click = fn end
    assert(loadstring('local UI, view, CardID = ...\n' .. clickSource))(
        UI, view, function(card) return card.id end)
    assert(view.tab.level > tile.level)
    view.tab.click()
    assert(selected == id, 'attached class/build tabs must select their cards')
end
print('PASS: attached class/build tabs remain clickable when the DIALOG editor is raised')
