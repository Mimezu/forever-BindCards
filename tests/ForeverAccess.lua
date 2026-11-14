-- Window key setter, minimap button and Settings page (Access.lua).
local root = ... or 'Interface/AddOns/BindCards'

local function frame(name)
    local f = { scripts = {}, shown = true, points = {}, events = {} }
    setmetatable(f, { __index = function(_, k) return function() end end })
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:GetScript(event) return self.scripts[event] end
    function f:IsShown() return self.shown end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:SetShown(v) self.shown = v and true or false end
    function f:SetPoint(...) self.points = { ... } end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:CreateFontString() local t = frame(); function t:SetText(s) self.text = s end; return t end
    f.CreateTexture = f.CreateFontString
    function f:SetText(s) self.text = s end
    function f:SetChecked(v) self.checked = v end
    function f:GetChecked() return self.checked end
    function f:EnableKeyboard(v) self.keyboard = v end
    function f:SetPropagateKeyboardInput(v) self.propagate = v end
    function f:GetWidth() return 140 end
    function f:GetCenter() return 500, 400 end
    function f:GetEffectiveScale() return 1 end
    if name then _G[name] = f end
    return f
end
local created = {}
CreateFrame = function(kind, name, parent, template)
    local f = frame(name); f.kind, f.parent, f.template = kind, parent, template
    created[#created + 1] = f
    return f
end
UIParent, Minimap = frame(), frame()
GameTooltip = frame()

local combat = false
InCombatLockdown = function() return combat end
local bindings, saved = {}, 0
GetBindingKey = function(action)
    local keys = {}
    for key, a in pairs(bindings) do if a == action then keys[#keys + 1] = key end end
    table.sort(keys)
    return unpack(keys)
end
GetBindingAction = function(key) return bindings[key] or '' end
SetBinding = function(key, action) bindings[key] = action end
GetBindingText = function(key) return (key:gsub('CTRL%-', 'Ctrl-')) end
SaveBindings = function() saved = saved + 1 end
GetCurrentBindingSet = function() return 2 end
local alt, ctrl, shift = false, false, false
IsAltKeyDown = function() return alt end
IsControlKeyDown = function() return ctrl end
IsShiftKeyDown = function() return shift end
BINDING_NAME_TOGGLEBACKPACK = 'Open Backpack'

local registered = {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel, name) return { panel = panel, name = name } end,
    RegisterAddOnCategory = function(category) registered[#registered + 1] = category end,
}
SettingsPanel = frame()
HideUIPanel = function(f) f:Hide() end

local notes = {}
BindCardsDB = { settings = { minimapIcon = true, minimapAngle = 200 } }
BindCards = { toggled = 0, shown = 0 }
function BindCards:Notify(text) notes[#notes + 1] = text end
function BindCards:ToggleWindow() self.toggled = self.toggled + 1 end
function BindCards:ShowUI() self.shown = self.shown + 1 end
function BindCards:GetProfileBindingConflict(key) if key == 'F' then return 'Fireball' end end

assert(loadfile(root .. '/Access.lua'))('BindCards', BindCards)
assert(BINDING_NAME_BINDCARDS_TOGGLE and BINDING_CATEGORY_BINDCARDS == 'BindCards')
local bindingsXml = assert(io.open(root .. '/Bindings.xml')):read('*a')
assert(bindingsXml:find('name="BINDCARDS_TOGGLE"', 1, true) and bindingsXml:find('BindCards:ToggleWindow()', 1, true))
local toc = assert(io.open(root .. '/BindCards.toc')):read('*a')
assert(toc:find('\nUI.lua\r?\nAccess.lua'), 'Access.lua loads after UI.lua')

-- Login: button and Settings page appear.
local loader = created[#created]
loader.scripts.OnEvent(loader, 'PLAYER_LOGIN')
local button = assert(BindCardsMinimapButton)
assert(button.parent == Minimap and button:IsShown())
assert(#registered == 1 and registered[1].name == 'BindCards')

-- Window key: set, replace an old action, card overlap, combat refusal, clear.
assert(BindCards:GetWindowKeyText() == 'Not set')
bindings['CTRL-B'] = 'TOGGLEBACKPACK'
assert(BindCards:SetWindowKey('CTRL-B'))
assert(bindings['CTRL-B'] == 'BINDCARDS_TOGGLE' and saved == 1)
assert(notes[#notes] == 'Ctrl-B no longer does "Open Backpack".')
assert(BindCards:GetWindowKeyText() == 'Ctrl-B')
assert(BindCards:SetWindowKey('F'))
assert(bindings['CTRL-B'] == nil and bindings.F == 'BINDCARDS_TOGGLE', 'old key released')
assert(notes[#notes] == 'F is also on Fireball; the card wins.')
combat = true
assert(BindCards:SetWindowKey('G') == nil and bindings.G == nil)
assert(BindCards:StartWindowKeyCapture() == false)
combat = false

-- Capture: Esc cancels, modifiers alone wait, modifiers combine.
local doneCount = 0
assert(BindCards:StartWindowKeyCapture(function() doneCount = doneCount + 1 end))
local capture = assert(BindCardsWindowKeyCapture)
assert(capture:IsShown() and capture.keyboard and capture.propagate == false)
assert(BindCards:IsCapturingWindowKey())
capture.scripts.OnKeyDown(capture, 'ESCAPE')
assert(not capture:IsShown() and doneCount == 1 and bindings.F == 'BINDCARDS_TOGGLE')
BindCards:StartWindowKeyCapture(function() doneCount = doneCount + 1 end)
capture.scripts.OnKeyDown(capture, 'LSHIFT')
assert(capture:IsShown(), 'modifier alone keeps listening')
shift, ctrl = true, true
capture.scripts.OnKeyDown(capture, 'K')
shift, ctrl = false, false
assert(bindings['CTRL-SHIFT-K'] == 'BINDCARDS_TOGGLE' and bindings.F == nil and doneCount == 2)
-- Entering combat stops listening.
BindCards:StartWindowKeyCapture(function() doneCount = doneCount + 1 end)
capture.scripts.OnEvent(capture, 'PLAYER_REGEN_DISABLED')
assert(not capture:IsShown() and doneCount == 3)

-- Minimap: click opens, drag saves the angle, toggle hides and persists.
button.scripts.OnClick(button)
assert(BindCards.toggled == 1)
button.scripts.OnEnter(button); assert(GameTooltip.text == 'BindCards')
GetCursorPosition = function() return 500, 500 end -- straight above center
button.scripts.OnDragStart(button)
button.scripts.OnUpdate(button)
assert(math.abs(BindCardsDB.settings.minimapAngle - 90) < 0.001)
assert(button.points[2] == Minimap and math.abs(button.points[4]) < 0.001 and math.abs(button.points[5] - 80) < 0.001)
button.scripts.OnDragStop(button); assert(button.scripts.OnUpdate == nil)
BindCards:SetMinimapIconShown(false)
assert(not button:IsShown() and BindCardsDB.settings.minimapIcon == false)

-- Settings page: checkbox mirrors the setting; Open closes Settings first.
local panel = registered[1].panel
panel.scripts.OnShow(panel)
local check, open, keyButton
for _, f in ipairs(created) do
    if f.parent == panel and f.kind == 'CheckButton' then check = f end
    if f.parent == panel and f.kind == 'Button' and f.text == 'Open' then open = f end
end
for _, f in ipairs(created) do
    if f.parent == panel and f.kind == 'Button' and f ~= open then keyButton = f end
end
assert(check.checked == false and keyButton.text == 'Ctrl-SHIFT-K')
check.checked = true; check.scripts.OnClick(check)
assert(button:IsShown() and BindCardsDB.settings.minimapIcon == true)
SettingsPanel:Show(); open.scripts.OnClick(open)
assert(not SettingsPanel:IsShown() and BindCards.shown == 1)
keyButton.scripts.OnClick(keyButton, 'LeftButton')
assert(keyButton.text == 'Press a key' and BindCards:IsCapturingWindowKey())
panel.scripts.OnHide(panel)
assert(not BindCards:IsCapturingWindowKey() and keyButton.text == 'Ctrl-SHIFT-K')
keyButton.scripts.OnClick(keyButton, 'RightButton')
assert(keyButton.text == 'Not set' and bindings['CTRL-SHIFT-K'] == nil)

print('PASS: window key setter, minimap button and Settings page')
