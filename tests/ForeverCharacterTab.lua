-- Character tab UI: binder model, tab selection and the "Copy from…" menu,
-- running the real UI.lua sections with stubs.
local root = ... or 'Interface/AddOns/BindCards'
local file = assert(io.open(root .. '/UI.lua', 'rb'))
local source = file:read('*a'):gsub('\r\n', '\n'); file:close()
local function section(first, last)
    local start = assert(source:find(first, 1, true), first)
    local finish = assert(source:find(last, start + #first, true), last)
    return source:sub(start, finish - 1)
end
local helpers = {}
assert(loadfile(root .. '/UIHelpers.lua'))('BindCards', helpers)

-- Part 1: binder model and tab selection.
local cards = {
    { id = 'g', name = 'GENERAL', templateKey = 'default:general', binderId = 'general' },
    { id = 'p', name = 'PALADIN', templateKey = 'default:class:PALADIN', binderId = 'class:PALADIN' },
    { id = 'p1', name = 'Primary', parentId = 'p' },
    { id = 'c', name = 'NEIGE BLANCHE', templateKey = 'default:character', binderId = 'character' },
    { id = 'c1', name = 'Professions', parentId = 'c' },
}
local byId = {}
for _, card in ipairs(cards) do byId[card.id] = card end
local function RootOf(card)
    while card and card.parentId do card = byId[card.parentId] end
    return card
end
local refreshed = 0
local UI = { selectedCardByBinder = {} }
function UI:FindCard(id) return byId[id] end
function UI:Refresh() refreshed = refreshed + 1 end
function UI:SetSelectedCardState(card) self.selectedCardID = card and card.id; return card ~= nil end
function UI:SelectActiveSpecCard() return false end
BindCardsDB = { settings = {} }
local env = setmetatable({
    UI = UI, Helpers = helpers.UIHelpers,
    UnitClass = function() return 'Paladin', 'PALADIN' end,
    Call = function(method, card)
        if method == 'GetCardBinderId' then return RootOf(card).binderId end
        if method == 'GetBinderFamily' then
            local binderId = RootOf(card).binderId
            return binderId == 'character' and 'character' or (binderId:match('^class:') and 'class' or 'general')
        end
        if method == 'GetCurrentClassFile' then return 'PALADIN' end
        if method == 'GetPlayerContext' then return { class = 'PALADIN', specGroup = 2 } end
    end,
    IsCardActive = function(card) return card.enabled ~= false end,
    CardID = function(card) return card and card.id end,
    ParentID = function(card) return card and card.parentId end,
    GetCards = function() return cards end,
}, { __index = _G })
local chunk = assert(loadstring(section('local function CurrentClassBinder()', 'local FRIENDLY = {') ..
    section('function UI:GetBinderKeyForCard(card)', 'function UI:SetBinderForProfileSelection(binderId)')))
setfenv(chunk, env); chunk()

local model = UI:GetBinderModel()
assert(model.character and model.character.root == byId.c, 'character root found')
assert(model.character.label == 'NEIGE BLANCHE', 'tab shows the character name')
assert(#model.character.cards == 2 and #model.class.cards == 2 and #model.general.cards == 1)
assert(UI:GetBinderKeyForCard(byId.c1) == 'character' and UI:GetBinderKeyForCard(byId.p1) == 'class')
UI:SelectBinder('character')
assert(UI.selectedBinderKey == 'character' and UI.selectedCardID == 'c', 'character tab selectable')
assert(BindCardsDB.settings.selectedBinderKey == 'character', 'choice remembered')
assert(UI:GetSelectedBinderKey() == 'character')
UI.selectedCardID = 'c1'
UI:SelectBinder('class')
UI:SelectBinder('character')
assert(UI.selectedCardID == 'c1', 'returns to the last card of the character tab')
-- After a respec the class tab opens on the active build card, not the
-- switched-off default one.
local holy = { id = 'p2', name = 'Holy', parentId = 'p', templateKey = 'default:specgroup:PALADIN:2',
    condition = { specGroup = 2 }, enabled = false }
local retCard = { id = 'r', name = 'Retribution', parentId = 'p', condition = { specGroup = 2 } }
table.insert(cards, 3, holy); table.insert(cards, 4, retCard)
byId.p2, byId.r = holy, retCard
UI:SelectActiveSpecCard()
assert(UI.selectedCardID == 'r', 'opens the active Retribution card')
holy.enabled = nil
UI:SelectActiveSpecCard()
assert(UI.selectedCardID == 'p2', 'the default build card wins when it is on')
table.remove(cards, 4); table.remove(cards, 3); byId.p2, byId.r = nil, nil
-- A detached character stack falls back to a docked binder.
byId.c.layoutMode = 'floating'
assert(UI:GetSelectedBinderKey() == 'class')
byId.c.layoutMode = nil
-- No character set (e.g. unreadable GUID): the tab is empty and never selected.
table.remove(cards, 5); table.remove(cards, 4); byId.c, byId.c1 = nil, nil
UI.selectedBinderKey = 'character'
assert(UI:GetSelectedBinderKey() == 'class', 'empty character tab falls back')
UI:SelectBinder('character')
assert(UI.selectedBinderKey == 'class', 'an empty character tab cannot be selected')
assert(helpers.UIHelpers.DockedPageWidth('character', 900, 300, 6, 12, 36) <= 560,
    'character card is compact like General')
-- The workspace draws pages only for cards in its visible list; the
-- character card was missing from it (empty page in 0.4.28).
local visibleChunk = assert(loadstring('local binderModel = ...\n' ..
    section('    local visibleCards = {}', '    local flat = FlattenCards(visibleCards)') ..
    '\nreturn visibleCards'))
local visible = visibleChunk({
    general = { cards = { { id = 'g' } } }, class = { cards = { { id = 'p' } } },
    character = { cards = { { id = 'c' }, { id = 'c1' } } },
})
local ids = {}
for _, card in ipairs(visible) do ids[#ids + 1] = card.id end
assert(table.concat(ids, ',') == 'g,p,c,c1', 'workspace draws General, class and character cards: ' ..
    table.concat(ids, ','))
-- Silhouettes: every other docked binder shows behind the open one.
local coverChunk = assert(loadstring('local self, mode, binderKey, binderModel, RootIsFloating, RootCard, MAX_HIERARCHY_SHEETS = ...\n' ..
    section('    -- Every other docked binder shows as a silhouette', '    local ancestors = Helpers.HierarchyAncestors') ..
    '\nreturn binderCovers, maximumAncestors'))
local gRoot, pRoot, cRoot = { id = 'g' }, { id = 'p' }, { id = 'c' }
local pChild = { id = 'p1', parentId = 'p' }
local coverModel = {
    general = { root = gRoot, cards = { gRoot } }, class = { root = pRoot, cards = { pRoot, pChild } },
    character = { root = cRoot, cards = { cRoot } },
}
local coverUI = { selectedCardByBinder = { class = 'p1' } }
function coverUI:FindCard(id) return ({ p1 = pChild })[id] end
local function Floating(root) return root.layoutMode == 'floating' end
local function RootCardOf(card) return card.parentId == 'p' and pRoot or card end
local function Keys(covers)
    local keys = {}
    for _, cover in ipairs(covers) do keys[#keys + 1] = cover.binderKey end
    return table.concat(keys, ',')
end
local covers, maxAncestors = coverChunk(coverUI, 'binder', 'character', coverModel, Floating, RootCardOf, 6)
assert(Keys(covers) == 'general,class', 'character open: General and class behind it')
assert(maxAncestors == 4, 'two sheets used by covers')
assert(covers[2].card == pChild, 'a cover shows the binder remembered card')
covers = coverChunk(coverUI, 'binder', 'general', coverModel, Floating, RootCardOf, 6)
assert(Keys(covers) == 'class,character', 'General open: class and character behind it')
cRoot.layoutMode = 'floating'
covers = coverChunk(coverUI, 'binder', 'class', coverModel, Floating, RootCardOf, 6)
assert(Keys(covers) == 'general', 'a detached binder has no silhouette')
cRoot.layoutMode = nil
covers = coverChunk(coverUI, 'panel', 'class', coverModel, Floating, RootCardOf, 6)
assert(#covers == 0, 'panel mode has no silhouettes')

-- Silhouette geometry: each must stick out of the open page, never sit
-- inside it (pages are slightly see-through; hidden edges read as lines).
local geometryChunk = assert(loadstring(
    'local pageLayers, generalLaneX, classLaneX, characterLaneX, selectedLaneX, frontPageWidth, iconSize, ' ..
    'availablePageWidth, depthByID, CardID, NaturalPageHeight, Helpers, selectedPageY, selectedPageHeight, ' ..
    'selectedDepth, min, max = ...\nlocal activeLayerY, layerGeometry = 5, {}\n' ..
    section('    for index, layer in ipairs(pageLayers) do\n        local geometry\n        if layer.binderCover then',
        '    local childCount = {}') .. '\nreturn layerGeometry'))
local frontWidth, frontX, frontY, frontHeight = 620, 45, 5, 480
local geometry = geometryChunk({
    { binderCover = true, binderKey = 'general', card = { id = 'g', columns = 6, capacity = 12 } },
    { binderCover = true, binderKey = 'character', card = { id = 'c', columns = 6, capacity = 12 } },
}, 5, 45, 85, frontX, frontWidth, 36, 700, {}, function(card) return card.id end,
    function() return 120 end, helpers.UIHelpers, frontY, frontHeight, 0, math.min, math.max)
local general, character = geometry[1], geometry[2]
assert(general.x < frontX, 'General silhouette sticks out on the left')
assert(character.x + character.width > frontX + frontWidth,
    'character silhouette sticks out on the right of the class page')
for _, g in ipairs(geometry) do
    assert(g.y + g.height >= frontY + frontHeight, 'no silhouette ends inside the open page')
end

-- Binders cascade: General, class, then the character card to the right.
local Lane = helpers.UIHelpers.WorkspaceLaneX
assert(Lane('binder', 'general') < Lane('binder', 'class') and Lane('binder', 'class') < Lane('binder', 'character'),
    'character page continues the binder cascade')
assert(Lane('panel', 'character') == Lane('panel', 'general'), 'panel mode keeps one column')

-- The character card's icon is the character's portrait.
local portraitChunk = assert(loadstring(section('local function ApplyCardIcon(texture, card)', 'local function EntryID(entry)') ..
    '\nreturn ApplyCardIcon'))
local portraitUnit
setfenv(portraitChunk, setmetatable({
    SetPortraitTexture = function(texture, unit) portraitUnit = unit; texture.portrait = true end,
}, { __index = _G }))
local ApplyCardIcon = portraitChunk()
local texture = { shown = false }
function texture:Hide() self.shown = false end
function texture:Show() self.shown = true end
function texture:SetTexture(value) self.portrait = nil; self.value = value end
function texture:SetTexCoord() end
ApplyCardIcon(texture, { templateKey = 'default:character', condition = {} })
assert(portraitUnit == 'player' and texture.portrait and texture.shown, 'character card shows the player portrait')
print('PASS: character tab: model, name, ownership, selection memory, detach and empty fallbacks')

-- Part 2: the card menu's "Copy from…" (real ShowCardMenu).
local function frame()
    local f = { scripts = {}, shown = false }
    for _, method in ipairs({ 'SetWidth', 'SetClampedToScreen', 'EnableMouse',
        'RegisterEvent', 'SetPoint', 'ClearAllPoints', 'SetFrameStrata', 'SetFrameLevel' }) do
        f[method] = function() end
    end
    function f:SetHeight(n) self.height = n end
    function f:SetScript(event, fn) self.scripts[event] = fn end
    f.HookScript = f.SetScript
    function f:IsShown() return self.shown end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
    function f:SetEnabled(value) self.enabled = value end
    f.label = { SetText = function(_, text) f.text = text end }
    return f
end
CreateFrame = function() return frame() end
UISpecialFrames, UIParent = {}, frame()
local MenuUI = {}
local others = { { id = 'set-2', name = 'Other Char', tiles = 3 } }
local copied, confirmed
local function MenuCall(method, card)
    if method == 'GetCardBinderId' then return card.binderId end
    if method == 'GetOtherCharacterSets' then return others end
    if method == 'GetFormOptions' then return {} end
    error(method)
end
function MenuUI:CopyCharacterFrom(sourceSet) copied = sourceSet end
local menuChunk = assert(loadstring('local UI, Button, Skin, C, CursorInside, tinsert, CardName, CardID, ' ..
    'IsStandardCard, IsMainBinderRoot, Call, ParentID, Mutate, IsFixedCard = ...\n' ..
    section('function UI:ShowMenu(', 'function UI:ShowAddRuleMenu(')))
menuChunk(MenuUI, frame, function() end, {}, function(f) return f and f.inside end, table.insert,
    function(c) return c.name end, function(c) return c.id end,
    function(c) return c.templateKey ~= nil end,
    function(c) return c.templateKey ~= nil end, MenuCall,
    function(c) return c.parentId end, function(_, fn) return fn() end,
    function(c) return c.templateKey ~= nil end)
local characterRoot = { id = 'c', name = 'NEIGE BLANCHE', templateKey = 'default:character', binderId = 'character' }
local owner = frame()
local function Row(label)
    for _, row in ipairs(MenuUI.cardMenu.rows) do
        if row:IsShown() and row.text == label then return row end
    end
end
MenuUI:ShowCardMenu(owner, characterRoot)
assert(Row('Add racial abilities'), 'Add racial abilities offered on the character card')
local copyRow = assert(Row('Copy from…'), 'Copy from… offered on the character card')
assert(copyRow.enabled)
copyRow.scripts.OnClick()
local otherRow = assert(Row('Other Char (3)'), 'lists the other character with its tile count')
otherRow.scripts.OnClick()
assert(copied == others[1], 'choosing a character starts the copy')
others = {}
MenuUI:ShowCardMenu(owner, characterRoot)
assert(not Row('Copy from…').enabled, 'disabled when there is no other character')
local rename = Row('Rename')
assert(rename and not rename.enabled and not Row('Delete card'), 'character card is fixed like other roots')
MenuUI.cardMenu:Hide()

-- UI:CopyCharacterFrom asks first, then copies and opens the tab.
local flow = section('function UI:CopyCharacterFrom(source)', 'function UI:AddFormCard(parent, formID)')
local FlowUI, calls = {}, {}
function FlowUI:Confirm(title, message, callback) confirmed = { title = title, message = message }; callback() end
function FlowUI:SelectBinder(key) calls.selected = key end
function FlowUI:SetStatus(text) calls.status = text end
local flowChunk = assert(loadstring('local UI, InCombat, Mutate, Call = ...\n' .. flow))
local inCombat = false
flowChunk(FlowUI, function() return inCombat end, function(_, fn) return fn() end,
    function(method, id) calls[method] = id; return true end)
FlowUI:CopyCharacterFrom({ id = 'set-2', name = 'Other Char' })
assert(confirmed and confirmed.title == 'Copy from Other Char?' and confirmed.message:find('Undo', 1, true))
assert(calls.CopyCharacterSetFrom == 'set-2' and calls.selected == 'character')
inCombat, calls = true, {}
FlowUI:CopyCharacterFrom({ id = 'set-2', name = 'Other Char' })
assert(not calls.CopyCharacterSetFrom and calls.status, 'locked in combat')
print('PASS: character card menu: Copy from… list, disabled when alone, fixed root, confirm, combat lock')
