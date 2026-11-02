local f = assert(io.open('Interface/AddOns/BindCards/UI.lua'))
local source = f:read('*a'); f:close()
local first = assert(source:find('function UI:ShowSpellMenu(', 1, true))
local last = assert(source:find('FlattenCards = function', first, true))
local function frame()
    local obj = { scripts = {} }
    for _, method in ipairs({'SetSize', 'SetClampedToScreen', 'EnableMouse', 'RegisterEvent',
        'SetPoint', 'SetFrameStrata', 'SetFrameLevel', 'ClearAllPoints'}) do obj[method] = function() end end
    obj.label = { SetText = function(_, text) obj.text = text end }
    function obj:SetScript(event, fn) self.scripts[event] = fn end
    obj.HookScript = obj.SetScript
    function obj:Show() self.shown = true end
    function obj:Hide() self.shown = false end
    function obj:IsShown() return self.shown end
    return obj
end
CreateFrame = frame
UISpecialFrames = {}
local UI, entry = {}, { id = 'heal', kind = 'spell' }
local function call(name, id, enabled)
    if name == 'GetTileDisplay' then return 'Healing Touch', 1 end
    assert(name == 'SetTileHighestRank' and id == entry.id)
    entry.highestRank = enabled or nil
    return entry
end
UI.SetStatus = function() error('Unexpected UI error') end
UI.ShowPrompt = function(_, _, _, _, _, options) UI.macroBody = options.value end
local prelude = 'local UI, Button, Skin, C, CursorInside, tinsert, Mutate, Call, EntryID, SpellRankText = ...\n'
assert(loadstring(prelude .. source:sub(first, last - 1)))(UI, frame, function() end, {},
    function(obj) return obj.inside end, table.insert, function(_, fn) assert(fn()) end,
    call, function(obj) return obj.id end, function() return 'Rank 2' end)
local owner = frame()
UI:ShowSpellMenu(owner, {}, entry)
assert(UI.spellMenu.rows[1].text == 'Always use highest learned rank')
UI.spellMenu.rows[1].scripts.OnClick()
assert(entry.highestRank and not UI.spellMenu:IsShown())
UI:ShowSpellMenu(owner, {}, entry)
assert(UI.spellMenu.rows[1].text == 'Use current rank only')
UI.spellMenu.rows[2].scripts.OnClick()
assert(UI.macroBody == '#showtooltip\n/cast Healing Touch')
UI:ShowSpellMenu(owner, {}, entry)
UI.spellMenu.rows[1].scripts.OnClick()
assert(not entry.highestRank)
UI:ShowSpellMenu(owner, {}, entry)
UI.spellMenu.rows[2].scripts.OnClick()
assert(UI.macroBody == '#showtooltip\n/cast Healing Touch(Rank 2)')
UI:ShowSpellMenu(owner, {}, entry)
owner.scripts.OnHide(); assert(not UI.spellMenu:IsShown())
UI:ShowSpellMenu(owner, {}, entry)
UI.spellMenu.scripts.OnEvent(UI.spellMenu); assert(not UI.spellMenu:IsShown())
assert(#UISpecialFrames == 1, 'reuse must not register duplicate Escape handlers')
-- Exercise the actual workspace click handler, including its trailing refresh.
-- RefreshWorkspace hides/reuses tiles, which dismisses menus anchored to them.
local workspace = assert(source:find('function UI:CreateWorkspaceTile(', 1, true))
local clickStart = assert(source:find('tile:SetScript("OnClick", function(self, button)', workspace, true))
local clickEnd = assert(source:find('    view.tiles[index] = tile', clickStart, true))
owner.entry, owner.card = entry, { id = 'card' }
BindCardsDB = { settings = { workspaceMode = 'binder' } }
IsShiftKeyDown = function() return false end
UI.RefreshWorkspace = function() owner.scripts.OnHide() end
assert(loadstring('local UI, tile, CardID = ...\n' .. source:sub(clickStart, clickEnd - 1)))(
    UI, owner, function(card) return card.id end)
owner.scripts.OnClick(owner, 'RightButton')
assert(UI.spellMenu:IsShown(), 'right-click must not immediately refresh away the spell menu')
UI.spellMenu.rows[1].scripts.OnClick()
assert(entry.highestRank, 'menu opened through right-click must remain usable')
print('PASS: spell menu toggles, macro rank semantics, reuse, dismissal and workspace right-click')
