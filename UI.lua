local _, private = ...

local BindCards = _G.BindCards or private or {}
_G.BindCards = BindCards

local UI = {}
BindCards.UI = UI
local Helpers = BindCards.UIHelpers or {}
UI.themeButtons, UI.themeFonts, UI.themeIcons = {}, {}, {}
UI.themeSurfaces = setmetatable({}, { __mode = "k" })
UI.themeFontColors = setmetatable({}, { __mode = "k" })
UI.themeTextures = setmetatable({}, { __mode = "k" })
UI.euiSkin = BindCards.EUIFacade

local floor, max, min = math.floor, math.max, math.min
local tinsert, tsort = table.insert, table.sort
local unpack = unpack or table.unpack
local FlattenCards, EntryIcon
local MAX_HIERARCHY_SHEETS = 6

local C = {
    window = { 0.035, 0.041, 0.052, 0.985 },
    panel = { 0.055, 0.063, 0.078, 1 },
    paper = { 0.073, 0.082, 0.098, 1 },
    paperAlt = { 0.060, 0.069, 0.084, 1 },
    slot = { 0.060, 0.069, 0.084, 1 },
    raised = { 0.095, 0.108, 0.129, 1 },
    hover = { 0.12, 0.14, 0.17, 1 },
    border = { 0.20, 0.235, 0.28, 0.72 },
    faint = { 0.18, 0.21, 0.25, 0.25 },
    blue = { 0.27, 0.58, 0.82, 1 },
    blueSoft = { 0.18, 0.36, 0.52, 1 },
    teal = { 0.18, 0.76, 0.70, 1 },
    drop = { 0.25, 0.90, 0.55, 1 },
    amber = { 0.93, 0.66, 0.25, 1 },
    amberMuted = { 0.58, 0.45, 0.25, 0.82 },
    amberFaint = { 0.55, 0.40, 0.20, 0.34 },
    red = { 0.88, 0.31, 0.34, 1 },
    text = { 0.91, 0.93, 0.96, 1 },
    muted = { 0.59, 0.64, 0.71, 1 },
    shortcutInactive = { 0.70, 0.74, 0.81, 1 },
    topText = { 0.91, 0.93, 0.96, 1 },
    -- Mouseover scopes use the Evoker (#33937F) and Death Knight (#C41E3A) class colors.
    hoverFriendly = { 0.20, 0.576, 0.498, 1 },
    hoverHostile = { 0.769, 0.118, 0.227, 1 },
}
local HOVER_TEXTURE = "Interface\\AddOns\\BindCards\\Assets\\HoverReticle"

local EDGE = "Interface\\Buttons\\WHITE8X8"
local BG = "Interface\\Buttons\\WHITE8X8"
local WHITE_ICON = 134400
local RESIZE_GRIP_UP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local RESIZE_GRIP_HIGHLIGHT = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight"
local RESIZE_GRIP_DOWN = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down"
local MODAL_OVERLAY_LEVEL = 1400
local MODAL_FRAME_LEVEL = 1401

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function PlayerClassColor()
    local classFile = UnitClass and select(2, UnitClass("player"))
    if issecretvalue and issecretvalue(classFile) then classFile = nil end
    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color then return color.r or 1, color.g or 1, color.b or 1 end
    return C.text[1], C.text[2], C.text[3]
end

local function CursorInside(frame)
    if not frame or not frame:IsShown() or not GetCursorPosition then return false end
    local x, y = GetCursorPosition()
    local left, right, bottom, top = frame:GetLeft(), frame:GetRight(), frame:GetBottom(), frame:GetTop()
    if issecretvalue and (issecretvalue(x) or issecretvalue(y) or issecretvalue(left) or
        issecretvalue(right) or issecretvalue(bottom) or issecretvalue(top)) then
        return false
    end
    if not (x and y and left and right and bottom and top) then return false end
    local scale = frame:GetEffectiveScale()
    return x >= left * scale and x <= right * scale and y >= bottom * scale and y <= top * scale
end

local function CursorOverSurface(frame, capturedDragTarget)
    if not frame or not frame:IsShown() then return false end
    -- Card dragging retains mouse capture on its source in Retail. Binder
    -- return surfaces cannot rely on GetMouseFoci at release time. The target
    -- has already been constrained to the card's owning binder, so its full
    -- page rectangle is intentionally valid even beneath the active stack.
    if capturedDragTarget or frame.bindCardsBinderKey or frame.bindCardsBinderCoverKey then
        return CursorInside(frame)
    end
    if GetMouseFoci then
        for _, focus in ipairs(GetMouseFoci() or {}) do
            local region = focus
            while region do
                if region == frame then return CursorInside(frame) end
                region = region.GetParent and region:GetParent() or nil
            end
        end
        return false
    end
    return CursorInside(frame)
end

local function EntryTileUnderCursor()
    if not GetMouseFoci then return nil end
    for _, focus in ipairs(GetMouseFoci() or {}) do
        local region = focus
        while region do
            if region.bindCardsEntryTile then
                if region:IsShown() and CursorInside(region) then return region, true end
                break
            end
            if region.bindCardsCardSurface and region:IsShown() and CursorInside(region) then
                return nil, true
            end
            region = region.GetParent and region:GetParent() or nil
        end
    end
    return nil, false
end

local function CardTabUnderCursor()
    -- Retail's hit-test result respects ScrollFrame clipping and occlusion.
    -- Raw frame rectangles do not: a clipped docked tab can still report that
    -- the cursor is inside it, causing its screen-level drop glow to appear as
    -- an unexplained empty rectangle over the card grid.
    if GetMouseFoci then
        for _, focus in ipairs(GetMouseFoci() or {}) do
            local region = focus
            while region do
                if region.bindCardsCard and region:IsShown() and CursorInside(region) then
                    return region
                end
                region = region.GetParent and region:GetParent() or nil
            end
        end
        return nil
    end

    -- Compatibility fallback for clients/test harnesses without GetMouseFoci.
    local strataRank = {
        BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
        FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
    }
    local best, bestRank, bestLevel
    for _, view in pairs(UI.cardViews or {}) do
        local tab = view.tab
        if tab and tab:IsShown() and tab.bindCardsCard and CursorInside(tab) then
            local rank = strataRank[tab:GetFrameStrata()] or 0
            local level = tab:GetFrameLevel() or 0
            if not best or rank > bestRank or (rank == bestRank and level > bestLevel) then
                best, bestRank, bestLevel = tab, rank, level
            end
        end
    end
    -- Panel mode represents cards with navigator rows instead of physical
    -- binder tabs.  Treat those rows as equivalent drop targets so an icon
    -- can be moved directly to another card without first opening it.
    for _, row in ipairs(UI.navRows or {}) do
        if row and row:IsShown() and row.bindCardsCard and CursorInside(row) then
            local rank = strataRank[row:GetFrameStrata()] or 0
            local level = row:GetFrameLevel() or 0
            if not best or rank > bestRank or (rank == bestRank and level > bestLevel) then
                best, bestRank, bestLevel = row, rank, level
            end
        end
    end
    return best
end

local function Call(method, ...)
    local fn = BindCards[method]
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, BindCards, ...)
    if ok then
        if a == nil and type(b) == "string" then UI.lastCallError = b; return false, b end
        UI.lastCallError = nil
        return a, b, c
    end
    UI.lastCallError = tostring(a)
    if UI.SetStatus then UI:SetStatus("Could not complete that action.", "error") end
    return false
end

local EUI_BUTTON_KEEP_KEYS = { "Icon", "Dot", "ThemeMark" }
local function ButtonKeepKeys(button)
    local keepKeys = {}
    for _, key in ipairs(EUI_BUTTON_KEEP_KEYS) do
        if button[key] then keepKeys[#keepKeys + 1] = key end
    end
    return #keepKeys > 0 and keepKeys or nil
end

local function ThemeSolid(dst, c, alpha)
    dst:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
    UI.themeTextures[dst] = { color = c, alpha = alpha, mode = "solid" }
end

local function Color(dst, c, alpha)
    -- A texture painted as a solid color must be repainted, not tinted: a
    -- vertex tint multiplies with the paint (accent x accent = darker, redder
    -- marks than the same accent elsewhere).
    local prior = UI.themeTextures[dst]
    if prior and prior.mode == "solid" then return ThemeSolid(dst, c, alpha) end
    dst:SetVertexColor(c[1], c[2], c[3], alpha or c[4] or 1)
    UI.themeTextures[dst] = { color = c, alpha = alpha, mode = "vertex" }
end

local function Skin(frame, color, border)
    frame:SetBackdrop({ bgFile = BG, edgeFile = EDGE, edgeSize = 1 })
    local b = border or C.border
    local skin = UI.euiSkin
    local topColor = frame.bindCardsTopSurface and skin and skin.GetNativeTopColor and
        skin.GetNativeTopColor(frame.bindCardsTopSurface)
    frame:SetBackdropColor(unpack(topColor or color or C.panel))
    frame:SetBackdropBorderColor(unpack(b))
    UI.themeSurfaces[frame] = { color = color or C.panel, border = b }
    if BindCards.LegacySkin then BindCards.LegacySkin:Surface(frame, color or C.panel, b) end
end

function UI:StyleEditableText(edit)
    if not edit then return end
    -- Compound Blizzard editors do not always enable their inner EditBox.
    if edit.EnableMouse then edit:EnableMouse(true) end
    local skin = self.euiSkin
    if edit.SetTextColor then
        if skin and skin.GetInputTextColor then
            edit:SetTextColor(skin.GetInputTextColor())
        else
            edit:SetTextColor(1, 1, 1, 1)
        end
    end
    if edit.SetHighlightColor then edit:SetHighlightColor(0.10, 0.70, 0.76, 1) end
    if edit.SetBlinkSpeed then edit:SetBlinkSpeed(0.32) end

    if not edit.bindCardsTextInputHooks and edit.HookScript then
        edit.bindCardsTextInputHooks = true
        edit:HookScript("OnEditFocusGained", function(self)
            UI:StyleEditableText(self)
            -- Consume modified shortcuts so Ctrl+C/Ctrl+V do not reach gameplay bindings.
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        end)
        edit:HookScript("OnEditFocusLost", function(self)
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
        end)
    end
end

local function Font(parent, size, color, flags)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local font = text:GetFont()
    text:SetFont(font, size or 12, flags or "")
    text:SetTextColor(unpack(color or C.text))
    text:SetJustifyH("LEFT")
    UI.themeFonts[#UI.themeFonts + 1] = text
    UI.themeFontColors[text] = color or C.text
    if UI.euiApplied and UI.euiSkin and UI.euiSkin.Font then pcall(UI.euiSkin.Font, text) end
    return text
end

local function ShortcutLabel(parent, size)
    local text = Font(parent, size, C.text, "OUTLINE")
    text:SetShadowColor(0, 0, 0, 0.95)
    text:SetShadowOffset(1, -1)
    return text
end

local function Divider(parent, vertical)
    local line = parent:CreateTexture(nil, "BORDER")
    ThemeSolid(line, C.faint)
    if vertical then line:SetWidth(1) else line:SetHeight(1) end
    return line
end

local function Button(parent, label, width, height, kind, actionTemplate)
    local b = CreateFrame("Button", nil, parent, actionTemplate and ("BackdropTemplate," .. actionTemplate) or "BackdropTemplate")
    b.bindCardsButtonKind = kind
    b:SetSize(width or 88, height or 24)
    Skin(b, kind == "primary" and C.blueSoft or C.raised, kind == "danger" and C.red or nil)
    b.label = Font(b, 11, C.text, "")
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetText(label or "")
    local function PrimaryInk(hovered)
        local skin = UI.euiSkin
        local background, ink
        if kind == "primary" and skin and skin.GetPrimaryButtonStyle then
            background, ink = skin.GetPrimaryButtonStyle(hovered)
        end
        if ink then b.label:SetTextColor(unpack(ink)) end
        return background
    end
    PrimaryInk(false)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(kind == "danger" and C.red or C.blue))
        self:SetBackdropColor(unpack(PrimaryInk(true) or C.hover))
    end)
    b:SetScript("OnLeave", function(self)
        Skin(self, kind == "primary" and C.blueSoft or C.raised, kind == "danger" and C.red or nil)
        PrimaryInk(false)
    end)
    UI.themeButtons[#UI.themeButtons + 1] = b
    if UI.euiApplied and UI.euiSkin and UI.euiSkin.Button then pcall(UI.euiSkin.Button, b) end
    return b
end

local function SetButtonEnabled(button, enabled)
    if not button then return end
    enabled = enabled == true
    if button.SetEnabled then button:SetEnabled(enabled) else button:EnableMouse(enabled) end
    button:SetAlpha(enabled and 1 or 0.38)
end

local function UpdateSlimScroll(scroll)
    local bar = scroll and scroll.bindCardsScrollBar
    if not bar then return end
    local range = max(0, scroll:GetVerticalScrollRange() or 0)
    bar:SetMinMaxValues(0, range)
    bar:SetValue(min(range, max(0, scroll:GetVerticalScroll() or 0)))
    bar:SetShown(range > 0.5)
end

local function SkinScrollFrame(scroll)
    if not scroll or scroll.bindCardsScrollBar then return end
    local stock = scroll.ScrollBar or scroll.scrollBar
    if not stock and scroll.GetName and scroll:GetName() then stock = _G[scroll:GetName() .. "ScrollBar"] end
    if stock then
        stock:SetAlpha(0)
        stock:EnableMouse(false)
        stock:Hide()
    end
    if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
    scroll:EnableMouseWheel(true)
    local bar = CreateFrame("Slider", nil, scroll:GetParent(), "BackdropTemplate")
    bar:SetOrientation("VERTICAL")
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
    bar:SetWidth(8)
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(false)
    Skin(bar, C.paperAlt, C.faint)
    bar:SetThumbTexture(EDGE)
    local thumb = bar:GetThumbTexture()
    ThemeSolid(thumb, C.teal)
    thumb:SetSize(6, 28)
    bar:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(min(self:GetVerticalScrollRange(), max(0,
            self:GetVerticalScroll() - delta * 42)))
        UpdateSlimScroll(self)
    end)
    scroll.bindCardsScrollBar = bar
    bar:Hide()
end

local function IconButton(parent, text, size)
    local b = Button(parent, text, size or 24, size or 24)
    b.label:SetFont(b.label:GetFont(), 14, "")
    return b
end

local function Chevron(parent, size)
    local chevron = CreateFrame("Frame", nil, parent)
    chevron:SetSize(size or 12, size or 12)
    chevron.lines = {}
    for index = 1, 2 do
        local line = chevron:CreateTexture(nil, "OVERLAY")
        line:SetSize(7, 2)
        ThemeSolid(line, C.muted)
        chevron.lines[index] = line
    end
    function chevron:SetExpanded(expanded)
        local first, second = self.lines[1], self.lines[2]
        first:ClearAllPoints()
        second:ClearAllPoints()
        if expanded then
            first:SetPoint("CENTER", -2, 1)
            second:SetPoint("CENTER", 2, 1)
            if first.SetRotation then first:SetRotation(-math.pi / 4) end
            if second.SetRotation then second:SetRotation(math.pi / 4) end
        else
            first:SetPoint("CENTER", 0, 2)
            second:SetPoint("CENTER", 0, -2)
            if first.SetRotation then first:SetRotation(-math.pi / 4) end
            if second.SetRotation then second:SetRotation(math.pi / 4) end
        end
    end
    return chevron
end

local function RaiseSharedModal(modal)
    if not modal or not modal.overlay then return end
    modal.overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    modal.overlay:SetFrameLevel(MODAL_OVERLAY_LEVEL)
    modal:SetFrameStrata("FULLSCREEN_DIALOG")
    modal:SetFrameLevel(MODAL_FRAME_LEVEL)
    modal.overlay:Raise()
    modal:Raise()
end

local function AddResizeGripArt(button)
    local texture = button:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(button)
    texture:SetTexture(RESIZE_GRIP_UP)
    button.resizeArt = texture
    button:SetHighlightTexture(RESIZE_GRIP_HIGHLIGHT)
    button:SetPushedTexture(RESIZE_GRIP_DOWN)
    return texture
end

local function CardID(card)
    return card and (card.id or card.cardID or card.uid)
end

local function ParentID(card)
    return card and (card.parentID or card.parentId or card.parent)
end

local function CardName(card)
    return (card and (card.name or card.title)) or "Untitled card"
end

local function IsMainBinderRoot(card)
    local templateKey = card and card.templateKey
    return templateKey == "default:general" or templateKey == "default:character" or
        (type(templateKey) == "string" and templateKey:match("^default:class:") ~= nil)
end

local function IsStandardCard(card)
    local templateKey = card and card.templateKey
    return type(templateKey) == "string" and templateKey:match("^default:") ~= nil
end

-- Binder roots stay fixed. Build cards (Primary/Secondary) are generated but
-- editable: rename, rules and ON/OFF. No default card can be deleted.
local function IsFixedCard(card)
    local templateKey = card and card.templateKey
    return IsStandardCard(card) and not (type(templateKey) == "string" and
        templateKey:match("^default:specgroup:") ~= nil)
end

local function IsAmberNestedCard(card)
    return (ParentID(card) ~= nil or card and card.homeParentId ~= nil) and
        not IsStandardCard(card)
end

local function CardSurface(base, card, amount)
    local red, green, blue
    if IsAmberNestedCard(card) then
        red, green, blue = C.amber[1], C.amber[2], C.amber[3]
    else
        red, green, blue = PlayerClassColor()
    end
    amount = tonumber(amount) or 0.02
    return {
        base[1] + (red - base[1]) * amount,
        base[2] + (green - base[2]) * amount,
        base[3] + (blue - base[3]) * amount,
        base[4] or 1,
    }
end

local function CardSelectionBorder(card, selected)
    if IsAmberNestedCard(card) then return C.amber end
    return selected and C.blue or C.faint
end

local function IsMutuallyExclusiveSheet(card)
    local templateKey = card and card.templateKey
    return type(templateKey) == "string" and
        (templateKey:match("^default:role:") ~= nil or
            templateKey:match("^default:specgroup:") ~= nil)
end

local function CardPageHeight(card, pageWidth, iconSize, binderKey)
    local columns = min(12, max(3, tonumber(card and card.columns) or 6))
    local capacity = max(columns, tonumber(card and card.capacity) or columns * 2)
    local rows = math.ceil(capacity / columns)
    local cardIconSize = min(iconSize or 36, max(18,
        floor((pageWidth - 16 - (columns - 1) * 6) / columns)))
    local gridHeight = rows * (cardIconSize + 6) - 6
    if card and card.collapsed then return 35 end
    if (binderKey == "general" or binderKey == "character") and Helpers.GeneralPageFootprint then
        local _, naturalHeight = Helpers.GeneralPageFootprint(columns, capacity, iconSize)
        return naturalHeight
    end
    return 78 + gridHeight
end

local function CurrentClassBinder()
    local className, classFile
    if UnitClass then className, classFile = UnitClass("player") end
    if issecretvalue then
        if issecretvalue(className) then className = nil end
        if issecretvalue(classFile) then classFile = nil end
    end
    classFile = type(classFile) == "string" and classFile ~= "" and classFile or nil
    className = type(className) == "string" and className ~= "" and className:upper() or classFile
    return classFile and ("class:" .. classFile) or nil, className or "CLASS"
end

local function BinderFamily(card)
    local family = Call("GetBinderFamily", card)
    if family == "class" then return "class" end
    if family == "character" then return "character" end
    if family == "general" then return "general" end
    local binderId = card and card.binderId
    if type(binderId) == "string" and binderId:match("^class:") then return "class" end
    local condition = card and card.condition or {}
    local templateKey = card and card.templateKey
    if (type(templateKey) == "string" and templateKey:match("^default:class:")) or condition.class then
        return "class"
    end
    return "general"
end

local FRIENDLY = {
    DEATHKNIGHT = "Death Knight", DEMONHUNTER = "Demon Hunter",
    PVE = "PvE", PVP = "PvP", ANY = "Any",
}

local function Friendly(value, fallback)
    if value == nil or value == "" then return fallback end
    local text = tostring(value)
    return FRIENDLY[text] or text:sub(1, 1) .. text:sub(2):lower()
end

local function Entries(card)
    return (card and (card.tiles or card.entries or card.slots or card.abilities or card.actions)) or {}
end

local function EntryGridPosition(card, entry, fallback)
    local oldColumns = min(12, max(3, tonumber(card and card.columns) or 6))
    local oldSlot = max(1, math.floor(tonumber(entry.order) or fallback or 1))
    local x = math.floor(tonumber(entry.gridX) or ((oldSlot - 1) % oldColumns + 1))
    local y = math.floor(tonumber(entry.gridY) or (math.floor((oldSlot - 1) / oldColumns) + 1))
    return x, y
end

local function EntriesBySlot(card, columns, rows)
    local slots, croppedRight, croppedDown = {}, 0, 0
    for fallback, entry in ipairs(Entries(card)) do
        local x, y = EntryGridPosition(card, entry, fallback)
        if x <= columns and y <= rows then
            slots[(y - 1) * columns + x] = entry
        else
            if x > columns then croppedRight = croppedRight + 1 end
            if y > rows then croppedDown = croppedDown + 1 end
        end
    end
    return slots, croppedRight, croppedDown
end

local function GetCards()
    local cards = Call("GetCards")
    if type(cards) ~= "table" then
        local profile = Call("GetActiveProfile") or BindCards.activeProfile
        cards = profile and profile.cards or BindCards.cards or {}
    end
    return cards
end

local function IsCardActive(card)
    if UI.activeSnapshotReady then
        return UI.activeCardStates and UI.activeCardStates[CardID(card)] == true
    end
    local active, reason = Call("IsCardActive", CardID(card))
    if active == nil and BindCards.GetActiveCards then
        local profile = Call("GetSelectedProfile")
        local activeCards = Call("GetActiveCards", profile)
        if type(activeCards) == "table" then
            active = false
            for _, candidate in ipairs(activeCards) do
                if CardID(candidate) == CardID(card) then active = true break end
            end
        end
    end
    if active == nil then active = card and card.active ~= false end
    return active, reason
end

local function Mutate(label, fn)
    if InCombat() then
        UI:SetStatus("Editing is unavailable during combat.", "warning")
        return false
    end
    local ok, result, message = pcall(fn)
    if not ok or result == false then
        local detail = not ok and result or message or UI.lastCallError
        UI.lastCallError = nil
        UI:SetStatus(type(detail) == "string" and detail or ("Could not " .. label:lower() .. "."), "error")
        return false, detail
    end
    UI:SetStatus(label .. ".", "success")
    UI:RequestRefresh()
    return true
end

function UI:CaptureUndo(label, profileId)
    local snapshot = Call("CreateUndoSnapshot", profileId)
    if snapshot then
        self.lastUndo = { label = label or "change", profileId = profileId, snapshot = snapshot }
    end
end

function UI:UndoLastChange()
    local undo = self.lastUndo
    if not undo then self:SetStatus("Nothing to undo.", "info"); return false end
    local restored, message = Call("RestoreUndoSnapshot", undo.snapshot)
    if restored == false then self:SetStatus(message or "Undo failed.", "error"); return false end
    self.lastUndo = nil
    self:SetStatus("Undid " .. undo.label .. ".", "success")
    self:RequestRefresh()
    return true
end

function UI:CancelDrag(suppressClick)
    local hadCardSession = self.dragSession ~= nil
    if self.dragSession and self.dragSession.view then self:SetDragStrata(self.dragSession.view, false) end
    if self.windowResizing and self.FinishWindowResize then
        self:FinishWindowResize(true)
    elseif self.frame and self.frame.StopMovingOrSizing then
        self.frame:StopMovingOrSizing()
    end
    for _, view in pairs(self.cardViews or {}) do
        if view.StopMovingOrSizing then view:StopMovingOrSizing() end
    end
    if self.dragSourceTile then
        self.dragSourceTile.icon:SetAlpha(self.dragSourceTile.entry and 1 or 0.035)
    end
    self.dragCard, self.dragEntry, self.dragSession, self.pendingCardDrag = nil, nil, nil, nil
    self.pendingEntryDrag, self.dragSourceTile = nil, nil
    if self.cardDragWatcher then self.cardDragWatcher:Hide() end
    if self.entryDragWatcher then self.entryDragWatcher:Hide() end
    if self.dragGhost then self.dragGhost:Hide() end
    if self.entryTabGlow then self.entryTabGlow:Hide() end
    if self.entryDropCardView then
        local view = self.entryDropCardView
        local selected = view.card and self.selectedCardID == CardID(view.card)
        view:SetBackdropBorderColor(unpack(CardSelectionBorder(view.card, selected)))
        self.entryDropCardView = nil
    end
    if self.homeBinderGlow then self.homeBinderGlow:Hide() end
    if self.homeBinderTabGlow then self.homeBinderTabGlow:Hide() end
    self.peelingCardID = nil
    if self.workspaceDrop then self.workspaceDrop:Hide() end
    ResetCursor()
    if suppressClick then
        self.suppressClick = true
        if C_Timer and C_Timer.After then C_Timer.After(0, function() UI.suppressClick = false end) end
    else
        self.suppressClick = false
    end
    if hadCardSession and self.workspaceContent then
        self:RefreshBinderSelectors()
        self:RefreshWorkspace()
    end
end

function UI:UpdateEntryCardHighlight()
    local target, targetRank, targetLevel
    local strataRank = {
        BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
        FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
    }
    if self.dragEntry and not CardTabUnderCursor() then
        for _, view in pairs(self.cardViews or {}) do
            if view:IsShown() and CursorInside(view) then
                local rank = strataRank[view:GetFrameStrata()] or 0
                local level = view:GetFrameLevel()
                if not target or rank > targetRank or (rank == targetRank and level > targetLevel) then
                    target, targetRank, targetLevel = view, rank, level
                end
            end
        end
    end
    if self.entryDropCardView ~= target then
        local previous = self.entryDropCardView
        if previous then
            local selected = previous.card and self.selectedCardID == CardID(previous.card)
            previous:SetBackdropBorderColor(unpack(CardSelectionBorder(previous.card, selected)))
        end
        self.entryDropCardView = target
    end
    if target then target:SetBackdropBorderColor(unpack(C.drop)) end
end

function UI:ShowEntryDragGhost(entry, copying)
    if not entry then return end
    if not self.dragGhost then
        local ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        ghost:SetSize(40, 40); ghost:SetFrameStrata("FULLSCREEN_DIALOG"); ghost:SetFrameLevel(500)
        ghost:EnableMouse(false); Skin(ghost, C.paper, C.blue)
        ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
        ghost.icon:SetPoint("TOPLEFT", 3, -3); ghost.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        ghost.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        ghost.copy = Font(ghost, 13, C.teal, "OUTLINE")
        ghost.copy:SetPoint("BOTTOMRIGHT", -2, 1); ghost.copy:SetText("+")
        ghost:SetScript("OnUpdate", function(self)
            local x, y = GetCursorPosition()
            if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return end
            local scale = UIParent:GetEffectiveScale()
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale + 12, y / scale - 12)
        end)
        self.dragGhost = ghost
    end
    local size = min(44, max(32, tonumber(BindCardsDB and BindCardsDB.settings and BindCardsDB.settings.iconSize) or 36))
    self.dragGhost:SetSize(size, size)
    self.dragGhost.icon:SetTexture(EntryIcon(entry))
    self.dragGhost.copy:SetShown(copying == true)
    self.dragGhost:Show()
end

function UI:UpdateEntryTabHighlight()
    local tab = self.dragEntry and CardTabUnderCursor()
    if not tab then
        if self.entryTabGlow then self.entryTabGlow:Hide() end
        return
    end
    if not self.entryTabGlow then
        local glow = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        glow:EnableMouse(false)
        glow:SetFrameStrata("TOOLTIP")
        -- Skinned once: this runs every frame of a drag, and theme switches
        -- re-skin registered surfaces themselves.
        Skin(glow, { 0.04, 0.16, 0.13, 0.20 }, C.drop)
        self.entryTabGlow = glow
    end
    local glow = self.entryTabGlow
    if glow.anchoredTo ~= tab then
        glow:ClearAllPoints(); glow:SetAllPoints(tab)
        glow.anchoredTo = tab
    end
    glow:SetFrameLevel(tab:GetFrameLevel() + 20)
    glow:Show()
end

function UI:StartEntryDrag(tile)
    if self.dragEntry or not tile or not tile.entry or InCombat() then return false end
    self.pendingEntryDrag = nil
    self.dragEntry = {
        card = tile.card, entry = tile.entry,
        copy = IsShiftKeyDown and IsShiftKeyDown(),
    }
    self.dragSourceTile = tile
    tile.icon:SetAlpha(0.30)
    self.suppressClick = true
    SetCursor("CAST_CURSOR")
    self:ShowEntryDragGhost(tile.entry, self.dragEntry.copy)
    return true
end

function UI:ArmEntryDrag(tile)
    if self.quickBind or InCombat() or not tile or not tile.entry then return end
    local x, y = GetCursorPosition()
    if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return end
    self.pendingEntryDrag = { tile = tile, startX = x, startY = y }
    if not self.entryDragWatcher then
        local watcher = CreateFrame("Frame", nil, UIParent)
        watcher:Hide()
        watcher:SetScript("OnUpdate", function()
            if UI.dragEntry then
                UI:UpdateEntryTabHighlight()
                UI:UpdateEntryCardHighlight()
                if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then UI:FinishEntryDrag() end
                return
            end
            local pending = UI.pendingEntryDrag
            if not pending then watcher:Hide(); return end
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                UI.pendingEntryDrag = nil; watcher:Hide(); return
            end
            local cursorX, cursorY = GetCursorPosition()
            if issecretvalue and (issecretvalue(cursorX) or issecretvalue(cursorY)) then return end
            local dx, dy = cursorX - pending.startX, cursorY - pending.startY
            if dx * dx + dy * dy >= 9 then UI:StartEntryDrag(pending.tile) end
        end)
        self.entryDragWatcher = watcher
    end
    self.entryDragWatcher:Show()
end

function UI:ReleaseEntryDrag()
    local pending = self.pendingEntryDrag
    if not self.dragEntry and pending then
        local x, y = GetCursorPosition()
        if not (issecretvalue and (issecretvalue(x) or issecretvalue(y))) then
            local dx, dy = x - pending.startX, y - pending.startY
            if dx * dx + dy * dy >= 9 then self:StartEntryDrag(pending.tile) end
        end
    end
    if self.dragEntry then self:FinishEntryDrag() end
    self.pendingEntryDrag = nil
    if self.entryDragWatcher and not self.dragEntry then self.entryDragWatcher:Hide() end
end

function UI:ArmCardDrag(view, rootCard, sourceTab, peelFromBinder)
    if BindCardsDB and BindCardsDB.settings and BindCardsDB.settings.workspaceMode == "panel" then return end
    -- A card cannot own resize and move gestures at the same time.
    local viewCardID = view and view.card and CardID(view.card)
    if self.cardResize then self:FinishCardResize(false) end
    if self.gridResize then self:FinishGridResize(false) end
    if viewCardID and self.cardViews and self.cardViews[viewCardID] then
        view = self.cardViews[viewCardID]
    end
    if InCombat() or not view or not rootCard or
        (ParentID(rootCard) and not self:CanPeelCard(rootCard)) then return end
    local x, y = GetCursorPosition()
    if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return end
    self.pendingCardDrag = {
        view = view, root = rootCard, sourceTab = sourceTab,
        peel = peelFromBinder, startX = x, startY = y,
    }
    if not self.cardDragWatcher then
        local watcher = CreateFrame("Frame", nil, UIParent)
        watcher:Hide()
        watcher:SetScript("OnUpdate", function()
            if UI.dragSession then
                UI:UpdateCardDragPosition()
                if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then UI:FinishCardDrag() end
                return
            end
            local pending = UI.pendingCardDrag
            if not pending then watcher:Hide(); return end
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                UI.pendingCardDrag = nil; watcher:Hide(); return
            end
            local cursorX, cursorY = GetCursorPosition()
            if issecretvalue and (issecretvalue(cursorX) or issecretvalue(cursorY)) then return end
            local dx, dy = cursorX - pending.startX, cursorY - pending.startY
            if dx * dx + dy * dy >= 36 then
                UI.pendingCardDrag = nil
                UI:BeginCardDrag(pending.view, pending.peel, pending.root, pending.sourceTab)
            end
        end)
        self.cardDragWatcher = watcher
    end
    self.cardDragWatcher:Show()
end

function UI:ReleaseCardDrag()
    local pending = self.pendingCardDrag
    if not self.dragSession and pending then
        local x, y = GetCursorPosition()
        if not (issecretvalue and (issecretvalue(x) or issecretvalue(y))) then
            local dx, dy = x - pending.startX, y - pending.startY
            if dx * dx + dy * dy >= 36 then
                self.pendingCardDrag = nil
                self:BeginCardDrag(pending.view, pending.peel, pending.root, pending.sourceTab)
            end
        end
    end
    if self.dragSession then self:FinishCardDrag() end
    self.pendingCardDrag = nil
    if self.cardDragWatcher and not self.dragSession then self.cardDragWatcher:Hide() end
end

function UI:ArmCardExpandPress(expand)
    if not expand then return end
    expand.bindCardsPressSerial = self.cardDragSerial or 0
end

function UI:ConsumeCardExpandPress(expand)
    if not expand then return false end
    local pressedSerial = expand.bindCardsPressSerial
    expand.bindCardsPressSerial = nil
    return pressedSerial ~= nil and pressedSerial == (self.cardDragSerial or 0)
end

function UI:IsEUITheme()
    return true
end

function UI:GetAppearanceTheme()
    local database = self and BindCardsDB
    local theme = database and database.settings and database.settings.theme
    return BindCards.VALID_UI_THEMES and BindCards.VALID_UI_THEMES[theme] and theme or "eui"
end

local function CopyThemeColor(target, source)
    if not (target and source) then return end
    target[1], target[2], target[3], target[4] = source[1], source[2], source[3], source[4]
end

function UI:RefreshAppearanceSelector()
    local selected = self:GetAppearanceTheme()
    for theme, button in pairs(self.appearanceButtons or {}) do
        if button.ThemeMark then button.ThemeMark:SetShown(theme == selected) end
        if button.label then button.label:SetTextColor(unpack(theme == selected and C.text or C.muted)) end
    end
end

function UI:ApplyAppearanceTheme(theme, refresh)
    theme = BindCards.VALID_UI_THEMES and BindCards.VALID_UI_THEMES[theme] and theme or "eui"
    local skin = self.euiSkin
    if not skin then return theme end
    self.applyingAppearance = true
    if theme ~= "eui" and skin.SetTheme then pcall(skin.SetTheme, theme) end
    local ok, palette = false, nil
    if skin.GetPalette then ok, palette = pcall(skin.GetPalette, theme) end
    if ok and type(palette) == "table" then
        for key, color in pairs(palette) do CopyThemeColor(C[key], color) end
        CopyThemeColor(C.topText, palette.topText or palette.text)
        self.useTopSurfaceText = palette.topText ~= nil
    end
    for frame, info in pairs(self.themeSurfaces) do
        local topColor = frame.bindCardsTopSurface and skin.GetNativeTopColor and
            skin.GetNativeTopColor(frame.bindCardsTopSurface)
        if frame.SetBackdropColor then frame:SetBackdropColor(unpack(topColor or info.color)) end
        if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(unpack(info.border)) end
    end
    for fontString, color in pairs(self.themeFontColors) do
        if fontString.SetTextColor then fontString:SetTextColor(unpack(color)) end
    end
    for texture, info in pairs(self.themeTextures) do
        local color, alpha = info.color, info.alpha or info.color[4] or 1
        if info.mode == "solid" and texture.SetColorTexture then
            texture:SetColorTexture(color[1], color[2], color[3], alpha)
        elseif texture.SetVertexColor then
            texture:SetVertexColor(color[1], color[2], color[3], alpha)
        end
    end
    -- Preserve the historical EUI layer order: BindCards' native backdrop
    -- palette is painted first, then the facade reasserts its translucent
    -- panels and atlas shell above it. Repainting native backdrops after the
    -- facade flattens the gaps and shell depth into a nearly uniform plate.
    if theme == "eui" and skin.SetTheme then pcall(skin.SetTheme, theme) end
    for _, button in ipairs(self.themeButtons) do
        if button.bindCardsButtonKind == "primary" and skin.GetPrimaryButtonStyle then
            local _, ink = skin.GetPrimaryButtonStyle(false)
            if ink and button.label then button.label:SetTextColor(unpack(ink)) end
        end
    end
    if self.modal then
        self:StyleEditableText(self.modal.edit)
        self:StyleEditableText(self.modal.multi)
    end
    if self.profileTransfer then self:StyleEditableText(self.profileTransfer.edit) end
    self.applyingAppearance = nil
    self.appliedAppearanceTheme = theme
    self:RefreshAppearanceSelector()
    if self.frame then
        local binderMode = not (BindCardsDB and BindCardsDB.settings and
            BindCardsDB.settings.workspaceMode == "panel")
        if binderMode then
            self.frame:SetBackdropColor(0, 0, 0, 0)
            self.frame:SetBackdropBorderColor(0, 0, 0, 0)
            if self.centerPanel and self.centerPanel.SetBackdrop then self.centerPanel:SetBackdrop(nil) end
            if self.centerBackdrop then self.centerBackdrop:Hide() end
        end
        if refresh then
            self:RefreshBinderSelectors()
            self:RefreshNavigator()
            self:RefreshWorkspace()
            self:RefreshGrid()
            self:RefreshProfiles()
            self:RefreshProfileManager()
            self:RefreshBindingChrome()
            self:RefreshVisualLabels()
        end
    end
    if BindCards.LegacySkin then BindCards.LegacySkin:Refresh() end
    return theme
end

function UI:SetAppearanceTheme(theme)
    local applied = Call("SetUITheme", theme)
    if type(applied) ~= "string" then return end
    if self.appliedAppearanceTheme ~= applied then self:ApplyAppearanceTheme(applied, true) end
    local labels = {
        eui = "Ellesmere", mimezu = "Mimezu", luminous = "Luminous",
        charcoal = "Charcoal", chalk = "Chalk", tungsten = "Tungsten",
        editorial = "Editorial", snes = "Super Nintendo", famicom = "Famicom", violetmist = "Violet Mist",
        violetbloom = "Violet Bloom", legacy = "Blizzard Legacy",
        gamecube = "GameCube", genesis = "Genesis", ps1 = "PS1", ps2 = "PS2",
        xbox = "Xbox", xbox360 = "Xbox 360",
    }
    self:SetStatus((labels[applied] or "Ellesmere") .. " appearance applied.", "success")
end

function UI:UpdateEUIAccent()
    if self.applyingAppearance then return end
    self:ApplyAppearanceTheme(self:GetAppearanceTheme(), true)
end

function UI:ApplyEUITheme(skin)
    if self.euiApplied then return end
    self.euiSkin = skin or self.euiSkin
    skin = self.euiSkin
    if not skin or not self:IsEUITheme() or not self.frame or self.euiApplied then return end
    self.euiApplied = true
    local appearanceTheme = self:GetAppearanceTheme()
    if appearanceTheme == "eui" then self:ApplyAppearanceTheme(appearanceTheme, false) end
    local binderMode = not (BindCardsDB and BindCardsDB.settings and BindCardsDB.settings.workspaceMode == "panel")
    if skin.Shell and self.panelShell then pcall(skin.Shell, self.panelShell, { bottomBar = 24 }) end
    if skin.Panel then
        if self.header then
            pcall(skin.Panel, self.header)
            if skin.TopSurface then pcall(skin.TopSurface, self.header, "header") end
        end
        if self.centerBackdrop and not binderMode then pcall(skin.Panel, self.centerBackdrop, { inset = true }) end
        if self.navPanel then pcall(skin.Panel, self.navPanel, { inset = true }) end
        if self.rightPanel then pcall(skin.Panel, self.rightPanel, { inset = true }) end
        if self.entryPanel then pcall(skin.Panel, self.entryPanel, { inset = true }) end
        if self.displayPopover then pcall(skin.Panel, self.displayPopover, { inset = true }) end
        if self.modal then pcall(skin.Panel, self.modal, { inset = true }) end
        if self.capture then pcall(skin.Panel, self.capture, { inset = true }) end
    end
    for _, fontString in ipairs(self.themeFonts) do
        if skin.Font then pcall(skin.Font, fontString) end
    end
    for _, button in ipairs(self.themeButtons) do
        if skin.Button then
            pcall(skin.Button, button, ButtonKeepKeys(button))
            if button.bindCardsTopSurface and skin.TopSurface then
                pcall(skin.TopSurface, button)
            end
        end
    end
    for _, iconInfo in ipairs(self.themeIcons) do
        if skin.SquareIcon then pcall(skin.SquareIcon, iconInfo.texture, iconInfo.parent) end
    end
    if self.closeButton and skin.CloseButton then
        -- EUI supplies its own close glyph; do not leave our text glyph under it.
        if self.closeButton.label then self.closeButton.label:SetText("") end
        pcall(skin.CloseButton, self.closeButton)
    end
    if skin.EditBox then
        if self.modal and self.modal.edit then pcall(skin.EditBox, self.modal.edit) end
        if self.modal and self.modal.multi then pcall(skin.EditBox, self.modal.multi) end
        if self.profileTransfer and self.profileTransfer.edit then
            pcall(skin.EditBox, self.profileTransfer.edit)
        end
    end
    -- External skins may replace EditBox colours. Restore the accessibility
    -- treatment after they have finished.
    if self.modal then
        self:StyleEditableText(self.modal.edit)
        self:StyleEditableText(self.modal.multi)
    end
    if self.profileTransfer then self:StyleEditableText(self.profileTransfer.edit) end
    if appearanceTheme ~= "eui" then self:ApplyAppearanceTheme(appearanceTheme, false) end
    if binderMode then
        self.frame:SetBackdropColor(0, 0, 0, 0)
        self.frame:SetBackdropBorderColor(0, 0, 0, 0)
        if self.centerPanel.SetBackdrop then self.centerPanel:SetBackdrop(nil) end
        if self.centerBackdrop then self.centerBackdrop:Hide() end
    end
    if skin.OnLooksChanged then pcall(skin.OnLooksChanged, function() UI:UpdateEUIAccent() end) end
end

function UI:ApplyFloatingGroupLayer(view, bringToFront)
    if not view then return end
    local root = view.groupRoot or view.card
    local rootID = CardID(root)
    if not rootID then return end

    self.floatingZOrder = self.floatingZOrder or {}
    self.floatingZSerial = tonumber(self.floatingZSerial) or 0
    if bringToFront and self.floatingZSerial >= 240 then
        local ordered, seen = {}, {}
        for _, candidate in pairs(self.cardViews or {}) do
            local candidateRoot = candidate.groupRoot or candidate.card
            local candidateID = CardID(candidateRoot)
            if candidate:IsShown() and candidateRoot and candidateRoot.layoutMode == "floating" and not seen[candidateID] then
                seen[candidateID] = true
                ordered[#ordered + 1] = { id = candidateID, rank = self.floatingZOrder[candidateID] or 0 }
            end
        end
        tsort(ordered, function(a, b) return a.rank < b.rank end)
        self.floatingZOrder, self.floatingZSerial = {}, 0
        for _, item in ipairs(ordered) do
            self.floatingZSerial = self.floatingZSerial + 1
            self.floatingZOrder[item.id] = self.floatingZSerial
        end
    end
    if bringToFront or not self.floatingZOrder[rootID] then
        self.floatingZSerial = self.floatingZSerial + 1
        self.floatingZOrder[rootID] = self.floatingZSerial
    end

    -- Give every floating stack a wide, private level band. Its paper sheets,
    -- card, buttons, and cells cannot interleave with another floating stack.
    -- Always above the docked binder pages, whatever level the window is at.
    local contentLevel = self.workspaceContent and self.workspaceContent:GetFrameLevel() or 0
    local baseLevel = max(60, contentLevel + 40) + self.floatingZOrder[rootID] * 32
    local function Layer(frame, depth)
        if not frame then return end
        frame:SetFrameStrata("DIALOG")
        frame:SetFrameLevel(baseLevel + min(depth, 12))
        frame.bindCardsFloatingOwner = view
        if frame.IsObjectType and frame:IsObjectType("Button") and not frame.bindCardsFloatingClickRaiseHook then
            frame.bindCardsFloatingClickRaiseHook = true
            frame:HookScript("OnClick", function(self)
                local owner = self.bindCardsFloatingOwner
                local ownerRoot = owner and (owner.groupRoot or owner.card)
                if owner and owner:IsShown() and ownerRoot and ownerRoot.layoutMode == "floating" then
                    UI:RaiseFloatingGroup(owner)
                end
            end)
        end
        for _, child in ipairs({ frame:GetChildren() }) do Layer(child, depth + 1) end
    end
    for index, sheet in ipairs((self.floatingSheets and self.floatingSheets[rootID]) or {}) do
        if sheet:IsShown() then
            sheet:SetFrameStrata("DIALOG")
            sheet:SetFrameLevel(baseLevel + index)
            sheet.bindCardsFloatingOwner = view
        end
    end
    Layer(view, 8)

    -- A stack reads correctly only when the selected page and its own tab are
    -- one front layer.  Keep every sibling tab immediately below the page so
    -- it can protrude at the edge without painting over the selected sheet.
    local selectedID = CardID(view.card)
    local function LayerTab(frame, depth)
        if not frame then return end
        frame:SetFrameStrata("DIALOG")
        frame:SetFrameLevel(baseLevel + depth)
        frame.bindCardsFloatingOwner = view
        -- Match embedded-tab layering: interactive children must sit above the
        -- parent button. Flattening them onto the parent's level makes the tab
        -- capture the click as a drag before the expand button can receive it.
        for _, child in ipairs({ frame:GetChildren() }) do LayerTab(child, depth + 1) end
    end
    for _, candidate in pairs(self.cardViews or {}) do
        local tab = candidate.tab
        if tab and tab:IsShown() and tab.groupRoot == root then
            LayerTab(tab, CardID(candidate.card) == selectedID and 24 or 7)
        end
    end
    self:RefreshEditorChromeLayer()
end

-- While dragging, lift the whole stack (page, sheets and tabs) above the
-- DIALOG layer. The window is top-level: a click on one of its ear tabs
-- raises it above any level a floating stack could hold in DIALOG.
function UI:SetDragStrata(view, lifted)
    if not view then return end
    local strata = lifted and "FULLSCREEN" or "DIALOG"
    local root = view.groupRoot or view.card
    local rootID = CardID(root)
    local function Apply(frame)
        if not frame or not frame.SetFrameStrata then return end
        frame:SetFrameStrata(strata)
        for _, child in ipairs({ frame:GetChildren() }) do Apply(child) end
    end
    Apply(view)
    for _, sheet in ipairs((self.floatingSheets and rootID and self.floatingSheets[rootID]) or {}) do Apply(sheet) end
    for _, candidate in pairs(self.cardViews or {}) do
        if candidate ~= view and (candidate.groupRoot or candidate.card) == root then Apply(candidate) end
        if candidate.tab and candidate.tab.groupRoot == root then Apply(candidate.tab) end
    end
    view.bindCardsDragLifted = lifted or nil
end

function UI:RaiseFloatingGroup(view)
    if not view then return end
    local root = view.groupRoot or view.card
    if not root or root.layoutMode ~= "floating" then return end
    self:ApplyFloatingGroupLayer(view, true)
end

function UI:ApplyEmbeddedLayer(frame, baseLevel)
    if not frame then return end
    local function Layer(childFrame, depth)
        childFrame:SetFrameStrata("DIALOG")
        childFrame:SetFrameLevel(baseLevel + min(depth, 12))
        childFrame.bindCardsFloatingOwner = nil
        for _, child in ipairs({ childFrame:GetChildren() }) do Layer(child, depth + 1) end
    end
    Layer(frame, 0)
end

function UI:RefreshEditorChromeLayer()
    if not self.frame or not self.header or not self.workspaceContent then return end
    -- Ears live outside the scroll clip, and floating stacks have independent
    -- level bands. Keep the title and its controls above both after every
    -- detach, return, and focus change, without raising the entire workspace.
    local workspaceLevel = self.workspaceContent:GetFrameLevel()
    local headerLevel = workspaceLevel + 64
    for _, view in pairs(self.cardViews or {}) do
        local root = view.groupRoot or view.card
        if view:IsShown() and root and
            (root.layoutMode == "floating" or self.peelingCardID == CardID(root)) then
            headerLevel = max(headerLevel, view:GetFrameLevel() + 32)
        end
    end
    self:ApplyEmbeddedLayer(self.header, headerLevel)
    if self.binderBar then self:ApplyEmbeddedLayer(self.binderBar, workspaceLevel + 60) end
end

function UI:ApplyDockedEarLayer(frame, selected)
    if not frame then return end
    -- These tabs live outside the ScrollFrame, but must share the editor's
    -- ancestry so native focus/raise operations move the whole surface together.
    frame:SetParent(self.frame)
    frame:SetScale(1)
    local workspaceLevel = self.workspaceContent:GetFrameLevel()
    local strata, baseLevel = "DIALOG", workspaceLevel + (selected and 52 or 44)
    if Helpers.HierarchyEarLayer then strata, baseLevel = Helpers.HierarchyEarLayer(selected, workspaceLevel) end
    local function Layer(childFrame, depth)
        childFrame:SetFrameStrata(strata)
        childFrame:SetFrameLevel(baseLevel + min(depth, 6))
        childFrame.bindCardsFloatingOwner = nil
        for _, child in ipairs({ childFrame:GetChildren() }) do Layer(child, depth + 1) end
    end
    frame:EnableMouse(true)
    Layer(frame, 0)
end

function UI:UpdateBinderStrings()
    for _, cord in ipairs(self.binderStrings or {}) do
        cord.shadow:Hide(); cord.accent:Hide(); cord.startDot:Hide(); cord.endDot:Hide()
    end
    if not self.frame or not self.frame:IsShown() then
        if self.binderStringLayer then self.binderStringLayer:Hide() end
        return
    end

    if not self.binderStringLayer then
        local layer = CreateFrame("Frame", nil, UIParent)
        layer:SetAllPoints(UIParent)
        layer:SetFrameStrata("DIALOG")
        layer:SetFrameLevel(18)
        layer:EnableMouse(false)
        self.binderStringLayer, self.binderStrings = layer, {}
    end
    self.binderStringLayer:Show()

    local cardsByID = {}
    for _, card in ipairs(GetCards()) do cardsByID[CardID(card)] = card end
    local function VisibleGroupView(root)
        local rootID = CardID(root)
        for _, view in pairs(self.cardViews or {}) do
            if view:IsShown() and CardID(view.groupRoot or view.card) == rootID then return view end
        end
    end
    local function OwningRoot(card)
        local owner, seen = cardsByID[card.homeParentId], {}
        while owner and ParentID(owner) and not seen[CardID(owner)] do
            seen[CardID(owner)] = true
            owner = cardsByID[ParentID(owner)] or owner
            if not cardsByID[ParentID(owner)] then break end
        end
        return owner
    end
    local function Cord(index)
        local cord = self.binderStrings[index]
        if cord then return cord end
        local layer = self.binderStringLayer
        cord = {
            shadow = layer:CreateLine(nil, "BACKGROUND"),
            accent = layer:CreateLine(nil, "ARTWORK"),
            startDot = layer:CreateTexture(nil, "ARTWORK"),
            endDot = layer:CreateTexture(nil, "ARTWORK"),
        }
        cord.shadow:SetThickness(4)
        cord.shadow:SetColorTexture(0, 0, 0, 0.55)
        cord.accent:SetThickness(1.6)
        cord.accent:SetColorTexture(C.teal[1], C.teal[2], C.teal[3], 0.78)
        for _, dot in ipairs({ cord.startDot, cord.endDot }) do
            dot:SetSize(5, 5)
            dot:SetColorTexture(C.teal[1], C.teal[2], C.teal[3], 0.88)
        end
        self.binderStrings[index] = cord
        return cord
    end

    local connections = {}
    for _, child in ipairs(GetCards()) do
        if child.layoutMode == "floating" and child.homeParentId then
            local owner = OwningRoot(child)
            local ownerView = owner and owner.layoutMode == "floating" and VisibleGroupView(owner)
            local childView = VisibleGroupView(child)
            if ownerView and childView and ownerView ~= childView then
                local ownerX, ownerY = ownerView:GetCenter()
                local childX, childY = childView:GetCenter()
                if ownerX and ownerY and childX and childY then
                    local startPoint, endPoint
                    if math.abs(childX - ownerX) >= math.abs(childY - ownerY) then
                        startPoint = childX >= ownerX and "RIGHT" or "LEFT"
                        endPoint = childX >= ownerX and "LEFT" or "RIGHT"
                    else
                        startPoint = childY >= ownerY and "TOP" or "BOTTOM"
                        endPoint = childY >= ownerY and "BOTTOM" or "TOP"
                    end
                    connections[#connections + 1] = {
                        ownerView = ownerView, childView = childView, childCard = child,
                        startPoint = startPoint, endPoint = endPoint,
                        sortValue = (startPoint == "LEFT" or startPoint == "RIGHT") and childY or childX,
                    }
                end
            end
        end
    end

    -- Build one attachment rail per binder edge. Cords sharing an edge receive
    -- separate, ordered knots instead of converging on its center point.
    local groups = {}
    for _, connection in ipairs(connections) do
        groups[connection.ownerView] = groups[connection.ownerView] or {}
        local ownerGroups = groups[connection.ownerView]
        ownerGroups[connection.startPoint] = ownerGroups[connection.startPoint] or {}
        ownerGroups[connection.startPoint][#ownerGroups[connection.startPoint] + 1] = connection
    end
    local stringIndex = 0
    for ownerView, ownerGroups in pairs(groups) do
        for startPoint, group in pairs(ownerGroups) do
            tsort(group, function(a, b) return a.sortValue < b.sortValue end)
            local vertical = startPoint == "LEFT" or startPoint == "RIGHT"
            local edgeLength = vertical and ownerView:GetHeight() or ownerView:GetWidth()
            local usableLength = max(0, edgeLength - 28)
            local desiredSpan = #group > 1 and max(28 * (#group - 1), edgeLength * 0.52) or 0
            local railSpan = min(usableLength, desiredSpan)
            local spacing = #group > 1 and railSpan / (#group - 1) or 0
            local firstOffset = -spacing * (#group - 1) / 2
            for index, connection in ipairs(group) do
                stringIndex = stringIndex + 1
                local cord = Cord(stringIndex)
                local cordColor = IsAmberNestedCard(connection.childCard) and C.amber or C.teal
                cord.accent:SetColorTexture(cordColor[1], cordColor[2], cordColor[3], 0.78)
                cord.startDot:SetColorTexture(cordColor[1], cordColor[2], cordColor[3], 0.88)
                cord.endDot:SetColorTexture(cordColor[1], cordColor[2], cordColor[3], 0.88)
                local offset = firstOffset + (index - 1) * spacing
                local startX, startY = vertical and 0 or offset, vertical and offset or 0
                for _, line in ipairs({ cord.shadow, cord.accent }) do
                    line:ClearAllPoints()
                    line:SetStartPoint(startPoint, ownerView, startX, startY)
                    line:SetEndPoint(connection.endPoint, connection.childView, 0, 0)
                    line:Show()
                end
                cord.startDot:ClearAllPoints()
                cord.startDot:SetPoint("CENTER", ownerView, startPoint, startX, startY)
                cord.endDot:ClearAllPoints()
                cord.endDot:SetPoint("CENTER", connection.childView, connection.endPoint, 0, 0)
                cord.startDot:Show(); cord.endDot:Show()
            end
        end
    end
end

function UI:UpdateCardDragPosition()
    local session = self.dragSession
    local view = session and session.view
    if not session or not view or not session.startCursorX then return end
    local cursorX, cursorY = GetCursorPosition()
    if issecretvalue and (issecretvalue(cursorX) or issecretvalue(cursorY)) then return end
    local uiScale = UIParent:GetEffectiveScale()
    local x = session.startLeft + cursorX / uiScale - session.startCursorX
    local y = session.startTop + cursorY / uiScale - session.startCursorY
    view:ClearAllPoints()
    view:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    self:UpdateHomeBinderHighlight()
    self:UpdateBinderStrings()
end

function UI:GetCardDropSurfaces(card)
    if not card then return nil, nil end
    local pages, tabs = {}, {}
    local ownerRoot = self:GetRootCard(card)
    local draggedRoot = self.dragSession and self.dragSession.card
    local function Add(list, surface)
        if surface and surface:IsShown() and
            (not surface.IsVisible or surface:IsVisible()) then
            list[#list + 1] = surface
        end
    end
    local ownerView = self.cardViews and self.cardViews[CardID(card)]
    if ownerView then Add(tabs, ownerView.tab) end
    -- Every ear and exposed sheet in the home stack is a return target,
    -- including the parent's ear while a different child is the front page.
    for _, candidate in pairs(self.cardViews or {}) do
        local root = candidate.card and self:GetRootCard(candidate.card)
        if root == ownerRoot and root ~= draggedRoot then
            Add(pages, candidate)
            if candidate ~= ownerView then Add(tabs, candidate.tab) end
        end
    end
    for _, sheet in ipairs((self.floatingSheets and self.floatingSheets[CardID(ownerRoot)]) or {}) do
        Add(pages, sheet)
    end
    local binderKey = self:GetBinderKeyForCard(card)
    for _, sheet in ipairs(self.binderSheets or {}) do
        if (sheet.card and self:GetRootCard(sheet.card) == ownerRoot) or
            (binderKey and sheet.bindCardsBinderCoverKey == binderKey and
                ownerRoot.layoutMode ~= "floating") then
            Add(pages, sheet)
        end
    end
    if ownerRoot.layoutMode ~= "floating" then
        if binderKey == "general" then Add(tabs, self.generalBinder)
        elseif binderKey == "class" then Add(tabs, self.classBinder)
        elseif binderKey == "character" and self.characterBinder then Add(tabs, self.characterBinder) end
    end
    -- Keep both the parent's ear and the top selector usable. Previously the
    -- selector replaced the ear, so dropping Primary on Druid could fail.
    local function Pick(surfaces)
        for _, surface in ipairs(surfaces) do
            if CursorInside(surface) then return surface end
        end
        return surfaces[1]
    end
    local page, tab = Pick(pages), Pick(tabs)
    return page or tab, page and tab or nil
end

function UI:UpdateHomeBinderHighlight()
    local card = self.dragSession and self.dragSession.card
    local homeParent = card and card.homeParentId and self:FindCard(card.homeParentId)
    local surface, tabSurface = self:GetCardDropSurfaces(homeParent)
    if not surface then
        if self.homeBinderGlow then self.homeBinderGlow:Hide() end
        if self.homeBinderTabGlow then self.homeBinderTabGlow:Hide() end
        return
    end
    if not self.homeBinderGlow then
        local glow = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        glow:EnableMouse(false)
        glow:SetFrameStrata("DIALOG")
        -- Skinned once; this refresh runs for every frame of a card drag.
        Skin(glow, { 0.10, 0.34, 0.22, 0.16 }, C.drop)
        self.homeBinderGlow = glow
    end
    local glow = self.homeBinderGlow
    -- Keep the visual outside the embedded workspace hierarchy. Reparenting a
    -- drag-time glow into backing sheets can invalidate their anchor family.
    glow:SetParent(UIParent)
    glow:SetFrameStrata("DIALOG")
    glow:ClearAllPoints()
    glow:SetAllPoints(surface)
    glow:SetFrameLevel(surface:GetFrameLevel() + 30)
    glow:SetAlpha(1)
    glow:Show()
    if tabSurface then
        if not self.homeBinderTabGlow then
            local tabGlow = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            tabGlow:EnableMouse(false)
            tabGlow:SetFrameStrata("DIALOG")
            Skin(tabGlow, { 0.10, 0.34, 0.22, 0.22 }, C.drop)
            self.homeBinderTabGlow = tabGlow
        end
        local tabGlow = self.homeBinderTabGlow
        tabGlow:ClearAllPoints()
        tabGlow:SetAllPoints(tabSurface)
        tabGlow:SetFrameLevel(tabSurface:GetFrameLevel() + 30)
        tabGlow:SetAlpha(1)
        tabGlow:Show()
    elseif self.homeBinderTabGlow then
        self.homeBinderTabGlow:Hide()
    end
end

function UI:BeginCardDrag(view, peelFromBinder, rootCard, sourceTab)
    if self.dragSession then return true end
    if BindCardsDB and BindCardsDB.settings and BindCardsDB.settings.workspaceMode == "panel" then return false end
    self.pendingCardDrag = nil
    if not view or not view.card or InCombat() then return false end
    -- A drag invalidates any expand-button press that may have started on the
    -- same ear.  The serial lets the chevron reject a mouse-up that lands on
    -- a newly reflowed ear after the stack is returned to the binder.
    self.cardDragSerial = (self.cardDragSerial or 0) + 1
    local card = rootCard or view.card
    local uiScale = UIParent:GetEffectiveScale()
    local peelAnchorWasTab = sourceTab and sourceTab:IsShown() or false
    local peelAnchor = peelAnchorWasTab and sourceTab or view
    local prePeelLeft, prePeelTop = peelAnchor:GetLeft(), peelAnchor:GetTop()
    local peeledChild = false
    if prePeelLeft and prePeelTop then
        local prePeelScale = peelAnchor:GetEffectiveScale()
        prePeelLeft = prePeelLeft * prePeelScale / uiScale
        prePeelTop = prePeelTop * prePeelScale / uiScale
    end
    if ParentID(card) then
        if not self:CanPeelCard(card) then
            self:SetStatus("Cards cannot detach in Panel mode.", "info")
            return false
        end
        local homeParentId = ParentID(card)
        local binderId = Call("GetCardBinderId", card)
        local peeled = Call("UpdateCard", CardID(card), {
            parentId = false,
            homeParentId = homeParentId,
            binderId = binderId,
            layoutMode = "floating",
        })
        if peeled == false or peeled == nil then
            self:SetStatus("Could not peel this card from its binder.", "error")
            return false
        end
        peelFromBinder = false
        peeledChild = true
        self.floatingSelection = self.floatingSelection or {}
        self.floatingSelection[CardID(card)] = CardID(card)
        self:RefreshWorkspace()
        view = self.cardViews[CardID(card)] or view
        sourceTab = view.tab
        if prePeelLeft and prePeelTop then
            local postAnchor = peelAnchorWasTab and sourceTab or view
            local postTabLeft, postTabTop = postAnchor:GetLeft(), postAnchor:GetTop()
            local postViewLeft, postViewTop = view:GetLeft(), view:GetTop()
            if postTabLeft and postTabTop and postViewLeft and postViewTop then
                local tabScale = postAnchor:GetEffectiveScale() / uiScale
                local viewScale = view:GetEffectiveScale() / uiScale
                postTabLeft, postTabTop = postTabLeft * tabScale, postTabTop * tabScale
                postViewLeft, postViewTop = postViewLeft * viewScale, postViewTop * viewScale
                view:ClearAllPoints()
                view:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
                    postViewLeft + prePeelLeft - postTabLeft,
                    postViewTop + prePeelTop - postTabTop)
            end
        end
    end
    sourceTab = sourceTab or view.tab
    local originalViewScale = view:GetEffectiveScale()
    local originalViewLeft, originalViewTop = view:GetLeft(), view:GetTop()
    if originalViewLeft and originalViewTop then
        originalViewLeft = originalViewLeft * originalViewScale / uiScale
        originalViewTop = originalViewTop * originalViewScale / uiScale
    end
    local tabScale = sourceTab:GetEffectiveScale()
    local sourceTabLeft, sourceTabTop = sourceTab:GetLeft(), sourceTab:GetTop()
    if sourceTabLeft and sourceTabTop then
        sourceTabLeft = sourceTabLeft * tabScale / uiScale
        sourceTabTop = sourceTabTop * tabScale / uiScale
    end
    self.suppressClick = true
    local activePageID = view.groupRoot == card and CardID(view.card) or CardID(card)
    self.dragSession = {
        card = card,
        view = view,
        pageID = activePageID,
        originMode = peeledChild and "stacked" or (card.layoutMode or "stacked"),
    }
    local session = self.dragSession
    if peelFromBinder then
        if self.selectedCardID == CardID(card) or self:IsDescendant(self.selectedCardID, CardID(card)) then
            local fallback
            for _, info in ipairs(FlattenCards(GetCards())) do
                local candidate = info.card
                if CardID(candidate) ~= CardID(card) and candidate.layoutMode ~= "floating" and
                    ParentID(candidate) == ParentID(card) then
                    fallback = candidate
                    break
                end
            end
            if not fallback and ParentID(card) then
                for _, candidate in ipairs(GetCards()) do
                    if CardID(candidate) == ParentID(card) and candidate.layoutMode ~= "floating" then
                        fallback = candidate
                        break
                    end
                end
            end
            if not fallback then
                for _, info in ipairs(FlattenCards(GetCards())) do
                    if CardID(info.card) ~= CardID(card) and info.card.layoutMode ~= "floating" then
                        fallback = info.card
                        break
                    end
                end
            end
            self.selectedCardID = fallback and CardID(fallback) or self.selectedCardID
        end
        self.peelingCardID = CardID(card)
        self.floatingSelection = self.floatingSelection or {}
        self.floatingSelection[CardID(card)] = activePageID
        self:RefreshBinderSelectors()
        self:RefreshWorkspace()
        -- Refresh may run hide callbacks that cancel the drag. Do not revive
        -- that session or dereference it after cancellation (BugGrabber).
        if self.dragSession ~= session then return false end
        view = self.cardViews[activePageID] or self.cardViews[CardID(card)] or view
        self.dragSession.view = view
        local left, top = self.workspaceScroll:GetLeft(), self.workspaceScroll:GetTop()
        if left and top then
            local workspaceScale = self.workspaceScroll:GetEffectiveScale()
            view:ClearAllPoints()
            view:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
                originalViewLeft or (left * workspaceScale / uiScale + 5),
                originalViewTop or (top * workspaceScale / uiScale - 5))
            if sourceTabLeft and sourceTabTop then
                local viewLeft, viewTop = view:GetLeft(), view:GetTop()
                if viewLeft and viewTop then
                    local viewScale = view:GetEffectiveScale() / uiScale
                    local viewLeftUI, viewTopUI = viewLeft * viewScale, viewTop * viewScale
                    sourceTab:ClearAllPoints()
                    sourceTab:SetPoint("TOPLEFT", view, "TOPLEFT",
                        (sourceTabLeft - viewLeftUI) / viewScale,
                        -(viewTopUI - sourceTabTop) / viewScale)
                end
            end
        end
    end
    if card.layoutMode == "floating" then
        self:RaiseFloatingGroup(view)
    else
        self:ApplyFloatingGroupLayer(view, true)
    end
    self:SetDragStrata(view, true)
    local cursorX, cursorY = GetCursorPosition()
    local viewLeft, viewTop = view:GetLeft(), view:GetTop()
    if not (issecretvalue and (issecretvalue(cursorX) or issecretvalue(cursorY) or
        issecretvalue(viewLeft) or issecretvalue(viewTop))) and viewLeft and viewTop then
        local parentScale = UIParent:GetEffectiveScale()
        local coordinateScale = view:GetEffectiveScale() / parentScale
        self.dragSession.startCursorX = cursorX / parentScale
        self.dragSession.startCursorY = cursorY / parentScale
        self.dragSession.startLeft = viewLeft * coordinateScale
        self.dragSession.startTop = viewTop * coordinateScale
        view:ClearAllPoints()
        view:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", self.dragSession.startLeft, self.dragSession.startTop)
    end
    if self.workspaceDrop and IsMainBinderRoot(card) then
        if self.binderBar then self.binderBar:Show() end
        self:PositionWorkspaceDrop(card)
        if self.frame and self.frame:GetHeight() < 125 then
            local left, top = self.frame:GetLeft(), self.frame:GetTop()
            self.frame:SetHeight(125)
            if left and top then
                self.frame:ClearAllPoints()
                self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
        end
        self.workspaceDrop.wasOver = nil
        -- The drop target sits above the docked pages but under the dragged stack.
        local dropLevel = (self.workspaceContent and self.workspaceContent:GetFrameLevel() or 0) + 36
        local dragLevel = view:GetFrameLevel()
        if dragLevel and dropLevel >= dragLevel then dropLevel = max(1, dragLevel - 1) end
        self.workspaceDrop:SetFrameLevel(dropLevel)
        self.workspaceDrop:Show()
    elseif self.workspaceDrop then
        self.workspaceDrop:Hide()
    end
    self:UpdateHomeBinderHighlight()
    return true
end

function UI:FinishCardDrag()
    local session = self.dragSession
    local view = session and session.view
    if not session or not view then return end
    self:SetDragStrata(view, false)
    view:StopMovingOrSizing()
    local docked = IsMainBinderRoot(session.card) and CursorInside(self.workspaceDrop)
    if self.workspaceDrop then self.workspaceDrop:Hide() end
    local card = session.card
    local homeParent = card.homeParentId and self:FindCard(card.homeParentId)
    local homeSurface, homeTabSurface = self:GetCardDropSurfaces(homeParent)
    local nested = homeParent and
        ((homeSurface and CursorOverSurface(homeSurface, true)) or
            (homeTabSurface and CursorOverSurface(homeTabSurface, true)))
    self.dragSession, self.peelingCardID = nil, nil
    if self.homeBinderGlow then self.homeBinderGlow:Hide() end
    if self.homeBinderTabGlow then self.homeBinderTabGlow:Hide() end
    if self.cardDragWatcher then self.cardDragWatcher:Hide() end
    self.suppressClick = true
    if C_Timer and C_Timer.After then C_Timer.After(0, function() UI.suppressClick = false end) end
    if card.homeParentId and nested then
        Mutate("Card nested", function()
            return UI:ReturnPeeledCard(card)
        end)
        return
    end
    if docked then
        if card.layoutMode == "floating" then
            Mutate("Card returned to binder", function()
                if IsMainBinderRoot(card) then return UI:ReturnBinderStack(card) end
                local returned = Call("UpdateCard", CardID(card), { layoutMode = "stacked" })
                if returned == false or returned == nil then return false end
                UI:SetSelectedCardState(card)
                UI:RefreshBinderSelectors()
                UI:RefreshWorkspace()
                return true
            end)
        else
            self:SetSelectedCardState(card)
            self:RefreshBinderSelectors()
            self:RefreshWorkspace()
            self:SetStatus("Card returned to binder.", "success")
        end
        return
    end
    local left, top = view:GetLeft(), view:GetTop()
    local fx, fy = UIParent:GetCenter()
    local coordinateScale = view:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local settings = BindCardsDB and BindCardsDB.settings or {}
    -- Persist the exact paper geometry beneath the cursor.
    local rootWidth = view:GetWidth()
    local rootHeight = CardPageHeight(card, rootWidth,
        min(48, max(24, tonumber(settings.iconSize) or 36)))
    local pageIndent = min(3, tonumber(view.depth) or 0) * 16
    local floatX, floatY
    if left and top then
        if Helpers.FloatingCenterFromTopLeft then
            floatX, floatY = Helpers.FloatingCenterFromTopLeft(left, top, rootWidth,
                rootHeight, pageIndent, coordinateScale, fx, fy)
        else
            floatX = (left - pageIndent + rootWidth / 2) * coordinateScale - fx
            floatY = (top - rootHeight / 2) * coordinateScale - fy
        end
    end
    Mutate(session.originMode == "floating" and "Card moved" or "Card detached", function()
        return Call("UpdateCard", CardID(card), {
            layoutMode = "floating",
            floatX = floatX and floor(floatX + 0.5) or card.floatX,
            floatY = floatY and floor(floatY + 0.5) or card.floatY,
        }) ~= false
    end)
end

function UI:ScheduleDragCancel(token, kind)
    if not C_Timer or not C_Timer.After then return end
    C_Timer.After(0, function()
        local current = kind == "card" and UI.dragCard or UI.dragEntry
        if current == token then UI:CancelDrag(true) end
    end)
end

function UI:ScrollWorkspace(delta)
    local scroll = self.workspaceScroll
    if not scroll then return end
    scroll:SetVerticalScroll(min(scroll:GetVerticalScrollRange(), max(0, scroll:GetVerticalScroll() - delta * 52)))
end

function UI:UpdateWorkspaceScrollbars()
    local scroll = self.workspaceScroll
    if not scroll then return end
    scroll:SetHorizontalScroll(0)
    if self.hasDockedBinderCard == false then
        scroll:SetVerticalScroll(0)
        if self.workspaceVBar then self.workspaceVBar:Hide() end
        if self.workspaceHBar then self.workspaceHBar:Hide() end
        return
    end
    local vertical = max(0, scroll:GetVerticalScrollRange() or 0)
    if self.workspaceVBar then
        self.workspaceVBar:SetMinMaxValues(0, max(1, vertical))
        self.workspaceVBar:SetValue(min(vertical, scroll:GetVerticalScroll()))
        self.workspaceVBar:SetShown(vertical > 1)
    end
    if self.workspaceHBar then
        self.workspaceHBar:SetValue(0)
        self.workspaceHBar:Hide()
    end
end

function UI:SetBinderResizeHover(inside)
    if not self.windowResizeGrip then return end
    local binder = BindCardsDB and BindCardsDB.settings and BindCardsDB.settings.workspaceMode ~= "panel"
    if not binder then self.windowResizeGrip:Show(); return end
    self.resizeHoverToken = (self.resizeHoverToken or 0) + 1
    local token = self.resizeHoverToken
    if inside or self.windowResizing then self.windowResizeGrip:Show(); return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.10, function()
            local cursorInside = CursorInside(UI.frame)
            local shouldHide = Helpers.ShouldHideResizeGrip and
                Helpers.ShouldHideResizeGrip(true, UI.windowResizing ~= nil, cursorInside) or
                (UI.windowResizing == nil and not cursorInside)
            if UI.resizeHoverToken == token and shouldHide then UI.windowResizeGrip:Hide() end
        end)
    elseif not self.windowResizing and not CursorInside(self.frame) then
        self.windowResizeGrip:Hide()
    end
end

local function FormatKey(key, tileId)
    if not key or key == "" then return nil end
    local gamepad = Call("FormatGamepadShortcut", key)
    if gamepad then return gamepad .. " (" .. (Call("GetGamepadBindingLabel", key, tileId) or "saved") .. ")" end
    -- The tile badge carries the mouseover scope; the label stays the key.
    local hover = Call("ParseHoverBinding", key)
    if hover then key = hover.key end
    return (key:gsub("CTRL%-", "C-"):gsub("SHIFT%-", "S-"):gsub("ALT%-", "A-"):gsub("BUTTON", "M"))
end

-- Scope of the first mouseover binding on an entry: HELP, HARM, ANY or nil.
local function EntryHoverScope(entry)
    for _, key in ipairs(entry and entry.bindings or {}) do
        local hover = Call("ParseHoverBinding", key)
        if hover then return hover.scope end
    end
end

local function CapturedKey(raw)
    if not raw or raw == "" then return nil end
    raw = raw:upper()
    if raw == "LSHIFT" or raw == "RSHIFT" or raw == "LCTRL" or raw == "RCTRL" or raw == "LALT" or raw == "RALT" or raw == "UNKNOWN" or raw == "PRINTSCREEN" then
        return nil
    end
    local prefix = ""
    if IsAltKeyDown and IsAltKeyDown() then prefix = prefix .. "ALT-" end
    if IsControlKeyDown and IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsShiftKeyDown and IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    return prefix .. raw
end

-- "ALT-SHIFT-BUTTON1" -> "Alt-Shift-Left click", for sentences.
local READABLE_BUTTONS = {
    BUTTON1 = "Left click", BUTTON2 = "Right click", BUTTON3 = "Middle click",
    BUTTON4 = "Button 4", BUTTON5 = "Button 5",
}
local function ReadableClick(key)
    local base = key:match("([^-]+)$") or key
    local prefix = key:sub(1, #key - #base):gsub("(%u)(%u*)%-", function(first, rest)
        return first .. rest:lower() .. "-"
    end)
    return prefix .. (READABLE_BUTTONS[base] or base)
end

-- allowPlain: plain left/right click are only bindable on unit frames.
local function MouseKey(button, allowPlain)
    local map = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
    local key = CapturedKey(map[button] or tostring(button):upper())
    if (key == "BUTTON1" or key == "BUTTON2") and not allowPlain then return nil end
    return key
end

local function EntryBinding(entry)
    return entry and ((entry.bindings and entry.bindings[1]) or entry.binding or entry.key or entry.hotkey)
end

local function SpellRankText(entry)
    if not entry or entry.kind ~= "spell" then return nil end
    local getter = C_Spell and C_Spell.GetSpellSubtext
    if type(getter) ~= "function" then return nil end
    local ok, rank = pcall(getter, entry.spellID)
    if not ok or (issecretvalue and issecretvalue(rank)) or type(rank) ~= "string" then return nil end
    return rank
end

local function EntryLabel(entry)
    if not entry then return "Empty" end
    local name = Call("GetTileDisplay", entry)
    name = name or entry.name or entry.label or entry.spellName or entry.itemName or entry.macroName or "Unknown"
    if entry.highestRank then return name .. " (Highest learned rank)" end
    local rank = SpellRankText(entry)
    return rank and rank ~= "" and (name .. " (" .. rank .. ")") or name
end

EntryIcon = function(entry)
    local _, displayIcon = Call("GetTileDisplay", entry)
    if displayIcon then return displayIcon end
    local icon = entry and (entry.icon or entry.iconID or entry.texture)
    if icon then return icon end
    if entry and (entry.kind == "spell" or entry.type == "spell") and (entry.spellID or entry.id) then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(entry.spellID or entry.id)
        return info and info.iconID or WHITE_ICON
    end
    if entry and (entry.kind == "item" or entry.type == "item") and (entry.itemID or entry.id) then
        return select(5, C_Item.GetItemInfoInstant(entry.itemID or entry.id)) or WHITE_ICON
    end
    return WHITE_ICON
end

local function EntrySpellUnavailable(entry)
    if not entry or (entry.kind ~= "spell" and entry.type ~= "spell") then return false end
    local spellID = tonumber(entry.spellID or entry.id)
    if not spellID then return false end
    if C_MountJournal and C_MountJournal.GetMountFromSpell then
        local ok, mountID = pcall(C_MountJournal.GetMountFromSpell, spellID)
        if ok and mountID then return false end
    end

    local checked, known = false, false
    local function Check(candidateID)
        if not candidateID or known then return end
        if IsPlayerSpell then
            checked = true
            local ok, result = pcall(IsPlayerSpell, candidateID)
            if ok and result == true then known = true end
        elseif C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
            checked = true
            local ok, result = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, candidateID)
            if ok and result == true then known = true end
        end
    end

    Check(spellID)
    -- Highest-rank tiles cast by name: any learned rank makes them usable
    -- (a shared class profile can hold another character's higher ranks).
    if not known and entry.highestRank then Check(Call("GetHighestLearnedSpellID", entry)) end
    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, overrideID = pcall(C_Spell.GetOverrideSpell, spellID)
        if ok and tonumber(overrideID) ~= spellID then Check(tonumber(overrideID)) end
    end
    return checked and not known
end

local function ApplyCardIcon(texture, card)
    texture:Hide()
    texture:SetTexture(nil)
    local condition = card and card.condition or {}
    local atlas = type(condition.class) == "string" and ("classicon-" .. condition.class:lower()) or nil
    if atlas and texture.SetAtlas and pcall(texture.SetAtlas, texture, atlas, false) then
        texture:SetTexCoord(0, 1, 0, 1)
        texture:Show()
    elseif card and card.templateKey == "default:general" then
        texture:SetTexture("Interface\\Icons\\INV_Misc_Note_05")
        texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        texture:Show()
    elseif card and card.templateKey == "default:character" and SetPortraitTexture then
        -- The character's own portrait, as on the player frame (round art on
        -- a square texture; a slight crop fills small icons).
        if pcall(SetPortraitTexture, texture, "player") then
            texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            texture:Show()
        end
    end
end

local function EntryID(entry)
    return entry and (entry.id or entry.entryID or entry.slotID or entry.uid)
end

local function TooltipEntry(owner, entry)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if (entry.kind == "spell" or entry.type == "spell") and (entry.spellID or entry.id) then
        GameTooltip:SetSpellByID((entry.highestRank and Call("GetHighestLearnedSpellID", entry)) or entry.spellID or entry.id)
    elseif (entry.kind == "item" or entry.type == "item") and (entry.itemID or entry.id) then
        GameTooltip:SetItemByID(entry.itemID or entry.id)
    elseif entry.kind == "macro" or entry.type == "macro" then
        local targetKind, targetValue = Call("GetMacroTooltipTarget", entry)
        local resolved = false
        if targetKind == "inventory" and targetValue and GameTooltip.SetInventoryItem then
            local ok, hasItem = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", targetValue)
            resolved = ok and hasItem ~= false
        elseif targetKind == "item" and targetValue and GameTooltip.SetItemByID then
            resolved = pcall(GameTooltip.SetItemByID, GameTooltip, targetValue)
        elseif targetKind == "spell" and targetValue and GameTooltip.SetSpellByID then
            resolved = pcall(GameTooltip.SetSpellByID, GameTooltip, targetValue)
        end
        if not resolved then
            GameTooltip:AddLine(EntryLabel(entry), 1, 1, 1)
            local macrotext = entry.macrotext or entry.body
            if macrotext then GameTooltip:AddLine(macrotext, 0.72, 0.75, 0.8, true) end
        end
    else
        GameTooltip:AddLine(EntryLabel(entry), 1, 1, 1)
        GameTooltip:Show()
    end
    local bindings = entry.bindings or {}
    if #bindings == 0 and EntryBinding(entry) then bindings = { EntryBinding(entry) } end
    for index, key in ipairs(bindings) do
        local hover = Call("ParseHoverBinding", key)
        if hover then
            local color = hover.scope == "HARM" and C.hoverHostile or (hover.scope == "HELP" and C.hoverFriendly or C.amber)
            GameTooltip:AddLine((index == 1 and "Mouseover: " or "Also mouseover: ") .. (FormatKey(key) or key) ..
                " · " .. (Call("FormatHoverScope", hover.scope) or ""), color[1], color[2], color[3])
            local status = Call("GetHoverBindingStatus", key)
            if status then GameTooltip:AddLine(status, C.muted[1], C.muted[2], C.muted[3], true) end
        else
            GameTooltip:AddLine((index == 1 and "Binding: " or "Also: ") .. (FormatKey(key, EntryID(entry)) or key), C.blue[1], C.blue[2], C.blue[3])
        end
        local gamepadStatus = Call("GetGamepadBindingStatus", key, EntryID(entry))
        if gamepadStatus then
            GameTooltip:AddLine(gamepadStatus, C.amber[1], C.amber[2], C.amber[3], true)
            local gesture = Call("ParseGamepadShortcut", key)
            if gesture then
                local scope = gesture.page and ("Bar " .. gesture.page .. " only") or "all gameplay bars (legacy)"
                GameTooltip:AddLine("Scope: " .. scope .. ". Triggers describe the held combination.", C.muted[1], C.muted[2], C.muted[3], true)
            end
        end
        local conflict = Call("GetBindingConflict", key)
        if conflict then
            local owner = conflict:match("^CLICK Clique") and "Clique Global/Hovercast" or "Another active override"
            GameTooltip:AddLine(owner .. " currently owns this key.", C.amber[1], C.amber[2], C.amber[3], true)
        end
    end
    if entry.kind == "spell" or entry.type == "spell" then
        GameTooltip:AddLine(entry.highestRank and "Always casts the highest learned rank." or "Casts the selected spell rank.", C.muted[1], C.muted[2], C.muted[3], true)
        -- Exact rank not learned by this character, but a lower one is.
        if not entry.highestRank and EntrySpellUnavailable(entry) and Call("GetHighestLearnedSpellID", entry) then
            GameTooltip:AddLine("This character hasn't learned this rank. Right-click → Always use highest learned rank to use the rank you know.",
                C.amber[1], C.amber[2], C.amber[3], true)
        end
        GameTooltip:AddLine("Right-click: spell options", C.muted[1], C.muted[2], C.muted[3])
    elseif entry.kind == "macro" or entry.type == "macro" then
        GameTooltip:AddLine("Right-click: edit macro", C.muted[1], C.muted[2], C.muted[3])
    end
    GameTooltip:AddLine("Shift-right-click: remove", C.muted[1], C.muted[2], C.muted[3])
    GameTooltip:Show()
end

local function CursorPayload()
    local backendPayload = Call("GetCursorPayload")
    if backendPayload then return backendPayload end
    local kind, a, _, c = GetCursorInfo()
    if kind == "spell" then
        local spellID = c or a
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        if not info then return nil end
        return { kind = "spell", spellID = spellID, name = info.name, icon = info.iconID }
    elseif kind == "item" then
        local itemID = a
        local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
        local icon = C_Item and select(5, C_Item.GetItemInfoInstant(itemID))
        return { kind = "item", itemID = itemID, name = name or ("Item " .. itemID), icon = icon }
    elseif kind == "toy" then
        local itemID = tonumber(a)
        if not itemID or not C_ToyBox or not C_ToyBox.GetToyInfo then return nil end
        local toyItemID, name, icon = C_ToyBox.GetToyInfo(itemID)
        if not tonumber(toyItemID) then return nil end
        return { kind = "item", itemID = itemID, name = name, icon = icon }
    elseif kind == "mount" or kind == "summonmount" then
        local mountID = tonumber(a)
        if not mountID or not C_MountJournal or not C_MountJournal.GetMountInfoByID then return nil end
        local name, spellID, icon = C_MountJournal.GetMountInfoByID(mountID)
        if not name or not tonumber(spellID) then return nil end
        return { kind = "spell", spellID = tonumber(spellID), name = name, icon = icon }
    elseif kind == "macro" then
        local macroIndex = a
        local name, icon, body = GetMacroInfo(macroIndex)
        return { kind = "macro", name = name or "Macro", icon = icon, macrotext = body }
    end
end

function UI:SetStatus(message, tone)
    if not self.statusText then return end
    local color = tone == "error" and C.red or tone == "warning" and C.amber or tone == "success" and C.teal or C.muted
    self.statusText:SetTextColor(unpack(color))
    self.statusText:SetText(message or "")
    if self.profileManager and self.profileManager:IsShown() and self.SetProfileManagerStatus then
        self:SetProfileManagerStatus(message, tone)
    end
end

function UI:FindCard(id)
    for _, card in ipairs(GetCards()) do
        if CardID(card) == id then return card end
    end
end

function UI:GetBinderKeyForCard(card)
    if not card then return nil end
    local binderId = Call("GetCardBinderId", card)
    local currentClassId = CurrentClassBinder()
    if binderId == currentClassId then return "class" end
    if binderId == "character" then return "character" end
    if type(binderId) == "string" and binderId:match("^class:") then return nil end
    return BinderFamily(card) == "class" and nil or "general"
end

function UI:GetBinderModel()
    local model = { general = { cards = {} }, class = { cards = {} }, character = { cards = {} } }
    local classId, classLabel = CurrentClassBinder()
    model.general.id, model.general.label = "general", "GENERAL"
    model.class.id, model.class.label = classId, classLabel
    model.character.id, model.character.label = "character", "CHARACTER"
    for _, card in ipairs(GetCards()) do
        local key = self:GetBinderKeyForCard(card)
        if key then
            model[key].cards[#model[key].cards + 1] = card
            if not ParentID(card) then
                local templateKey = card.templateKey
                if not model[key].root or templateKey == "default:general" or templateKey == "default:character" or
                    (key == "class" and type(templateKey) == "string" and templateKey:match("^default:class:")) then
                    model[key].root = card
                end
            end
        end
    end
    -- The character tab is labelled with the character's card name.
    if model.character.root and type(model.character.root.name) == "string" then
        model.character.label = model.character.root.name
    end
    return model
end

function UI:GetSelectedBinderKey(model)
    model = model or self:GetBinderModel()
    BindCardsDB = type(BindCardsDB) == "table" and BindCardsDB or {}
    BindCardsDB.settings = type(BindCardsDB.settings) == "table" and BindCardsDB.settings or {}
    local wanted = self.selectedBinderKey or BindCardsDB.settings.selectedBinderKey
    if wanted ~= "general" and wanted ~= "class" and wanted ~= "character" then
        wanted = #model.class.cards > 0 and "class" or "general"
    end
    if wanted == "class" and #model.class.cards == 0 then wanted = "general" end
    if wanted == "character" then
        local root = model.character.root
        if #model.character.cards == 0 or (root and root.layoutMode == "floating") then
            wanted = #model.class.cards > 0 and "class" or "general"
        end
    end
    local panelMode = BindCardsDB.settings.workspaceMode == "panel"
    if not panelMode then
        local function Detached(key)
            local root = model[key].root
            return root and (root.layoutMode == "floating" or self.peelingCardID == CardID(root)) or false
        end
        local generalDetached, classDetached = Detached("general"), Detached("class")
        if Helpers.PreferredDockedBinder then
            wanted = Helpers.PreferredDockedBinder(wanted, generalDetached, classDetached,
                model.general.root ~= nil and #model.general.cards > 0,
                model.class.root ~= nil and #model.class.cards > 0)
        elseif wanted == "class" and classDetached and model.general.root and not generalDetached then
            wanted = "general"
        elseif wanted == "general" and generalDetached and model.class.root and not classDetached then
            wanted = "class"
        end
    end
    self.selectedBinderKey = wanted
    BindCardsDB.settings.selectedBinderKey = wanted
    return wanted
end

function UI:EnsureBinderSelection(model)
    model = model or self:GetBinderModel()
    local binderKey = self:GetSelectedBinderKey(model)
    local selected = self:FindCard(self.selectedCardID)
    if selected and self:GetBinderKeyForCard(selected) == binderKey then return selected, binderKey, model end
    self.selectedCardByBinder = self.selectedCardByBinder or {}
    selected = self:FindCard(self.selectedCardByBinder[binderKey])
    if not selected or self:GetBinderKeyForCard(selected) ~= binderKey then
        selected = model[binderKey].root or model[binderKey].cards[1]
    end
    self.selectedCardID = CardID(selected)
    self.selectedCardByBinder[binderKey] = self.selectedCardID
    self.focusedEntry = nil
    self.focusedCardID = nil
    return selected, binderKey, model
end

function UI:SetSelectedCardState(cardOrId)
    local card = type(cardOrId) == "table" and cardOrId or self:FindCard(cardOrId)
    if not card then return false end
    local binderKey = self:GetBinderKeyForCard(card)
    if not binderKey then return false end
    self.selectedCardByBinder = self.selectedCardByBinder or {}
    self.selectedBinderKey = binderKey
    self.selectedCardID = CardID(card)
    self.selectedCardByBinder[binderKey] = self.selectedCardID
    self.focusedEntry = nil
    self.focusedCardID = nil
    BindCardsDB = type(BindCardsDB) == "table" and BindCardsDB or {}
    BindCardsDB.settings = type(BindCardsDB.settings) == "table" and BindCardsDB.settings or {}
    BindCardsDB.settings.selectedBinderKey = binderKey
    return true
end

function UI:SelectActiveSpecCard()
    local context = Call("GetPlayerContext") or {}
    if not context.class or not context.specGroup then return false end
    local templateKey = "default:specgroup:" .. context.class .. ":" .. context.specGroup
    -- Build cards are editable: after a respec the player may switch the
    -- default card off and use their own card with this Build rule.
    local template, ruled
    for _, card in ipairs(GetCards()) do
        if card.templateKey == templateKey then template = card end
        local condition = card.condition or {}
        if not ruled and card.enabled ~= false and tonumber(condition.specGroup) == context.specGroup and
            self:GetBinderKeyForCard(card) == "class" and IsCardActive(card) then
            ruled = card
        end
    end
    if template and template.enabled ~= false and IsCardActive(template) then ruled = template end
    local card = ruled or template
    return card and self:SetSelectedCardState(card) or false
end

-- Per-character memory of the open card; written only on window hide/logout.
local function CharacterSelectionRecord(create)
    local db = BindCards.db
    local characterKey = Call("GetCurrentCharacterKey")
    local characters = db and type(db.selections) == "table" and db.selections.characters
    if type(characterKey) ~= "string" or type(characters) ~= "table" then return nil end
    local record = characters[characterKey]
    if type(record) ~= "table" and create then
        record = { classProfileIds = {} }
        characters[characterKey] = record
    end
    return type(record) == "table" and record or nil
end

function UI:SaveRememberedSelection()
    if not self.hasOpened or type(self.selectedCardID) ~= "string" then return end
    local record = CharacterSelectionRecord(true)
    if record then record.lastCardID = self.selectedCardID end
end

function UI:RestoreRememberedSelection()
    local record = CharacterSelectionRecord(false)
    local card = record and type(record.lastCardID) == "string" and self:FindCard(record.lastCardID)
    return card and self:SetSelectedCardState(card) or false
end

function UI:SelectInitialCard()
    if not self:RestoreRememberedSelection() then self:SelectActiveSpecCard() end
end

function UI:SelectCard(cardOrId, refreshAll)
    if not self:SetSelectedCardState(cardOrId) then return false end
    if refreshAll == false then self:RefreshWorkspace() else self:Refresh() end
    return true
end

function UI:SelectBinder(binderKey)
    local model = self:GetBinderModel()
    if binderKey ~= "general" and binderKey ~= "class" and binderKey ~= "character" then return end
    if binderKey ~= "general" and #model[binderKey].cards == 0 then return end
    self.selectedCardByBinder = self.selectedCardByBinder or {}
    local current = self:FindCard(self.selectedCardID)
    local currentKey = self:GetBinderKeyForCard(current)
    if current and currentKey then self.selectedCardByBinder[currentKey] = CardID(current) end
    self.selectedBinderKey = binderKey
    BindCardsDB = type(BindCardsDB) == "table" and BindCardsDB or {}
    BindCardsDB.settings = type(BindCardsDB.settings) == "table" and BindCardsDB.settings or {}
    BindCardsDB.settings.selectedBinderKey = binderKey
    local remembered = self:FindCard(self.selectedCardByBinder[binderKey])
    if not remembered or self:GetBinderKeyForCard(remembered) ~= binderKey then
        remembered = model[binderKey].root or model[binderKey].cards[1]
    end
    self.selectedCardID = CardID(remembered)
    self.selectedCardByBinder[binderKey] = self.selectedCardID
    self.focusedEntry = nil
    self.focusedCardID = nil
    self:Refresh()
end

function UI:SetBinderForProfileSelection(binderId)
    local currentClass = Call("GetCurrentClassFile")
    local binderKey = binderId == "general" and "general" or
        (currentClass and binderId == "class:" .. currentClass and "class" or nil)
    if not binderKey then return false end
    if binderKey == "class" and self:SelectActiveSpecCard() then return true end
    local model = self:GetBinderModel()
    local binder = model and model[binderKey]
    if not binder then return false end
    self.selectedCardByBinder = self.selectedCardByBinder or {}
    local remembered = self:FindCard(self.selectedCardByBinder[binderKey])
    if not remembered or self:GetBinderKeyForCard(remembered) ~= binderKey then
        remembered = binder.root or binder.cards[1]
    end
    if remembered then return self:SetSelectedCardState(remembered) end
    self.selectedBinderKey = binderKey
    self.selectedCardID = nil
    BindCardsDB = type(BindCardsDB) == "table" and BindCardsDB or {}
    BindCardsDB.settings = type(BindCardsDB.settings) == "table" and BindCardsDB.settings or {}
    BindCardsDB.settings.selectedBinderKey = binderKey
    return true
end

function UI:HandleProfileSetSelected(profileId, binderId)
    if type(binderId) ~= "string" then
        local profile = profileId and Call("GetProfile", profileId) or nil
        binderId = profile and profile.binderId or nil
    end
    if self.profileManager and type(binderId) == "string" then
        self.profileManager.focusedBinderId = binderId
        self.profileManager.profileId = profileId
    end
    local frame = self.frame
    local point, relativeTo, relativePoint, x, y
    local width, height
    if frame then
        point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
        width, height = frame:GetWidth(), frame:GetHeight()
    end
    local token = {}
    self.profileSwitchGeometry = {
        token = token, point = point, relativeTo = relativeTo, relativePoint = relativePoint,
        x = x, y = y, width = width, height = height,
    }
    self:SetBinderForProfileSelection(binderId)
    self.hasOpened = true
    self:RequestRefresh()
    local function RestoreGeometry()
        local state = UI.profileSwitchGeometry
        if not state or state.token ~= token then return end
        UI.profileSwitchGeometry = nil
        if UI.frame and state.width and state.height then
            UI.frame:SetSize(state.width, state.height)
            if state.point then
                UI.frame:ClearAllPoints()
                UI.frame:SetPoint(state.point, state.relativeTo or UIParent,
                    state.relativePoint or state.point, state.x or 0, state.y or 0)
            end
            UI:UpdateWorkspaceScrollbars()
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, RestoreGeometry) else RestoreGeometry() end
end

function UI:IsDescendant(cardID, ancestorID)
    local card, seen = self:FindCard(cardID), {}
    while card and ParentID(card) and not seen[CardID(card)] do
        seen[CardID(card)] = true
        if ParentID(card) == ancestorID then return true end
        card = self:FindCard(ParentID(card))
    end
    return false
end

function UI:GetRootCard(card)
    local cursor, seen = card, {}
    while cursor and ParentID(cursor) and not seen[CardID(cursor)] do
        seen[CardID(cursor)] = true
        cursor = self:FindCard(ParentID(cursor)) or cursor
        if cursor == card then break end
    end
    return cursor or card
end

function UI:GetOwnershipRoot(card)
    local cursor, seen = card, {}
    while cursor and not seen[CardID(cursor)] do
        seen[CardID(cursor)] = true
        local ownerId = ParentID(cursor) or cursor.homeParentId
        if not ownerId then return cursor end
        cursor = self:FindCard(ownerId)
    end
end

function UI:CanPeelCard(card)
    if not card or not ParentID(card) then return false end
    return not (BindCardsDB and BindCardsDB.settings and
        BindCardsDB.settings.workspaceMode == "panel")
end

function UI:RestorePeeledCards(root)
    if not root then return false end
    local rootID = CardID(root)
    local restored = false
    local function BelongsToRoot(parentID)
        local cursor, seen = self:FindCard(parentID), {}
        while cursor and not seen[CardID(cursor)] do
            if CardID(cursor) == rootID then return true end
            seen[CardID(cursor)] = true
            cursor = self:FindCard(ParentID(cursor) or cursor.homeParentId)
        end
        return false
    end
    for _, card in ipairs(GetCards()) do
        local homeParentID = card.homeParentId
        if homeParentID and BelongsToRoot(homeParentID) then
            local ok = Call("UpdateCard", CardID(card), {
                parentId = homeParentID,
                homeParentId = false,
                layoutMode = "stacked",
            })
            if ok ~= false then restored = true end
        end
    end
    return restored
end

function UI:SelectReturnedCardInStack(card)
    if not card then return end
    self.floatingSelection = self.floatingSelection or {}
    self.floatingSelection[CardID(card)] = nil

    local cursor, seen = card, {}
    while cursor and ParentID(cursor) and not seen[CardID(cursor)] do
        seen[CardID(cursor)] = true
        local parent = self:FindCard(ParentID(cursor))
        if not parent then break end
        if parent.treeExpanded ~= true then
            Call("UpdateCard", CardID(parent), { treeExpanded = true })
        end
        cursor = parent
    end

    local root = self:GetRootCard(card)
    if root and root.layoutMode == "floating" then
        self.floatingSelection[CardID(root)] = CardID(card)
    end
    self:SetSelectedCardState(card)
end

function UI:ReturnPeeledCard(card)
    if not card or not card.homeParentId then return false end
    local cardID = CardID(card)
    local homeParentID = card.homeParentId
    local returned = Call("UpdateCard", cardID, {
        parentId = homeParentID,
        homeParentId = false,
        layoutMode = "stacked",
    })
    if returned == false or returned == nil then return false end

    -- Rebuild because a normal data refresh leaves paper geometry intact.
    self.floatingSelection = self.floatingSelection or {}
    self.floatingSelection[cardID] = nil
    if self.floatingZOrder then self.floatingZOrder[cardID] = nil end
    self:SelectReturnedCardInStack(card)
    self:RefreshBinderSelectors()
    self:RefreshWorkspace()
    return true
end

function UI:ReturnBinderStack(root)
    if not root then return false end
    local rootID = CardID(root)
    local selectedID = self.floatingSelection and self.floatingSelection[rootID]
    local settings = BindCardsDB and BindCardsDB.settings or {}
    if settings.gatherLooseSheets ~= false then self:RestorePeeledCards(root) end
    local returned = Call("UpdateCard", rootID, { layoutMode = "stacked" })
    if returned == false or returned == nil then return false end

    -- Reselect and rebuild after moving the UIParent-hosted view back into the stack.
    local selected = selectedID and self:FindCard(selectedID)
    if not selected or self:GetRootCard(selected) ~= root then selected = root end
    self.floatingSelection = self.floatingSelection or {}
    self.floatingSelection[rootID] = nil
    if self.floatingZOrder then self.floatingZOrder[rootID] = nil end
    self:SetSelectedCardState(selected)
    self:RefreshBinderSelectors()
    self:RefreshWorkspace()
    return true
end

function UI:GetSelectedCard()
    local selected = self:EnsureBinderSelection()
    return selected
end

function UI:UpdateMacroPreview(prompt, macrotext)
    if not prompt or not prompt.macroPreview then return end
    local icon, action = Call("ResolveMacroIcon", macrotext)
    prompt.previewIcon:SetTexture(icon or prompt.previewFallback or WHITE_ICON)
    prompt.previewIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    prompt.previewLabel:SetText(action and ("AUTO · " .. action) or "AUTO · no tooltip match")
    prompt.previewLabel:SetTextColor(unpack(icon and C.teal or C.muted))
end

function UI:RefreshVisibleMacroIcons()
    local seen = {}
    local function RefreshTile(tile)
        if not tile or seen[tile] or not tile:IsShown() then return end
        seen[tile] = true
        local entry = tile.entry
        if entry and (entry.kind == "macro" or entry.type == "macro") then
            tile.icon:SetTexture(EntryIcon(entry) or WHITE_ICON)
        end
    end
    for _, tile in ipairs(self.tiles or {}) do RefreshTile(tile) end
    for _, view in pairs(self.cardViews or {}) do
        for _, tile in ipairs(view.tiles or {}) do RefreshTile(tile) end
    end
    if self.modal and self.modal:IsShown() and self.modal.macroPreview and self.modal.activeEdit then
        self:UpdateMacroPreview(self.modal, self.modal.activeEdit:GetText())
    end
end

function UI:RequestMacroIconRefresh()
    if not self.frame or not self.frame:IsShown() or self.macroIconRefreshQueued then return end
    self.macroIconRefreshQueued = true
    local function Run()
        UI.macroIconRefreshQueued = nil
        UI:RefreshVisibleMacroIcons()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.05, Run) else Run() end
end

function UI:ShowPrompt(title, message, acceptText, callback, editConfig)
    local m = self.modal
    if not self.frame or not self.frame:IsShown() then return false end
    if self.displayPopover then self.displayPopover:Hide() end
    self:SetQuickBind(false)
    self:CancelDrag(true)
    m.title:SetText(title)
    m.message:SetText(message or "")
    m.accept.label:SetText(acceptText or "Save")
    m.callback = callback
    m.edit:Hide()
    m.multi:Hide()
    m.multiScroll:Hide()
    m.macroPreview = editConfig and editConfig.macroPreview == true or false
    m.previewFallback = editConfig and editConfig.previewFallback or nil
    m.previewIcon:SetShown(m.macroPreview)
    m.previewLabel:SetShown(m.macroPreview)
    m.counter:SetShown(editConfig and editConfig.maxLetters ~= nil)
    local promptWidth = editConfig and tonumber(editConfig.width) or 480
    local promptHeight = editConfig and tonumber(editConfig.height) or 330
    promptWidth = min(480, max(360, promptWidth))
    promptHeight = min(330, max(240, promptHeight))
    m:SetSize(promptWidth, promptHeight)
    m.edit:SetWidth(promptWidth - 40)
    m.multiScroll:SetSize(promptWidth - 40, promptHeight - 150)
    m:ClearAllPoints()
    local anchor = editConfig and editConfig.anchor
    if anchor and anchor.IsShown and anchor:IsShown() then
        local anchorX = anchor:GetCenter()
        local screenX = UIParent:GetCenter()
        local readable = not issecretvalue or
            not (issecretvalue(anchorX) or issecretvalue(screenX))
        if readable and anchorX and screenX and anchorX > screenX then
            m:SetPoint("RIGHT", anchor, "LEFT", -10, 0)
        elseif readable and anchorX and screenX then
            m:SetPoint("LEFT", anchor, "RIGHT", 10, 0)
        else
            m:SetPoint("CENTER", UIParent, "CENTER")
        end
    else
        m:SetPoint("CENTER", UIParent, "CENTER")
    end
    if editConfig then
        local edit = editConfig.multiline and m.multi or m.edit
        edit:SetMaxLetters(tonumber(editConfig.maxLetters) or (editConfig.multiline and 2097152 or 256))
        edit:Show()
        m.multiScroll:SetShown(editConfig.multiline == true)
        edit:SetText(editConfig.value or "")
        m.activeEdit = edit
        if m.macroPreview then self:UpdateMacroPreview(m, edit:GetText()) end
    else
        m.activeEdit = nil
    end
    m.overlay:Show()
    m:Show()
    RaiseSharedModal(m)
    -- A top-level window clicked to open this prompt may auto-raise after its
    -- OnClick handler returns. Reassert the modal on the next frame as well.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if m:IsShown() then RaiseSharedModal(m) end
        end)
    end
    m:EnableKeyboard(true)
    m:SetPropagateKeyboardInput(true)
    if m.activeEdit then
        -- Focus and selection visuals are only reliable after every ancestor is
        -- visible. Reassert them because an external EditBox skin may also have
        -- replaced the colors configured when the modal was constructed.
        self:StyleEditableText(m.activeEdit)
        m.activeEdit:SetFocus()
        if m.activeEdit.SetPropagateKeyboardInput then
            m.activeEdit:SetPropagateKeyboardInput(false)
        end
        m.activeEdit:HighlightText()
    end
end

function UI:Confirm(title, message, callback)
    self:ShowPrompt(title, message, "Continue", callback)
end

function UI:AddCard(parentID)
    self:ShowPrompt(parentID and "New subcard" or "New card", "Name", "Create", function(value)
        if not value or value:gsub("%s", "") == "" then return end
        Mutate("Card created", function()
            local binderId, condition
            if not parentID then
                local key = UI:GetSelectedBinderKey()
                local model = UI:GetBinderModel()
                parentID = CardID(model[key] and model[key].root)
                if not parentID then
                    if key == "class" then
                        binderId = CurrentClassBinder()
                        local classFile = binderId and binderId:match("^class:(.+)$")
                        condition = classFile and { class = classFile } or nil
                    else
                        binderId = "general"
                    end
                end
            end
            local values = { name = value, parentId = parentID, binderId = binderId, condition = condition, columns = 6 }
            local card = Call("CreateCard", values)
            if not card then card = Call("AddCard", values) end
            if card then UI:SetSelectedCardState(card) end
            return card ~= false
        end)
    end, { value = parentID and "New subcard" or "New card" })
end

function UI:AddMissingRacials()
    if InCombat() then return self:SetStatus("Cards are locked during combat.", "warning") end
    local added, message
    Mutate("Racial abilities added", function()
        added, message = Call("AddMissingRacials")
        return type(added) == "number" and added > 0
    end)
    if type(added) ~= "number" then
        self:SetStatus(message or "Racial abilities are not available yet.", "warning")
    elseif added == 0 then
        self:SetStatus("All racial abilities are already on this card.", "info")
    else
        self:SetStatus(added == 1 and "Added 1 racial ability." or ("Added " .. added .. " racial abilities."), "success")
    end
end

function UI:CopyCharacterFrom(source)
    if InCombat() then return self:SetStatus("Cards are locked during combat.", "warning") end
    self:Confirm("Copy from " .. tostring(source.name) .. "?",
        "This character's cards are replaced by a copy of " .. tostring(source.name) ..
        "'s cards and keys. Undo is available.", function()
            Mutate("Copied from " .. tostring(source.name), function()
                return Call("CopyCharacterSetFrom", source.id) ~= false
            end)
            UI:SelectBinder("character")
        end)
end

function UI:AddFormCard(parent, formID)
    local parentID = CardID(parent)
    local definition = BindCards.FORM_DEFINITIONS and BindCards.FORM_DEFINITIONS[formID]
    local binderId = parentID and Call("GetCardBinderId", parentID)
    local binderClass = type(binderId) == "string" and binderId:match("^class:(.+)$") or nil
    if not parentID or not definition or definition.class ~= binderClass then
        self:SetStatus("That form is not available in this class stack.", "warning")
        return false
    end
    return Mutate("Form subcard created", function()
        local card, message = Call("CreateCard", {
            name = definition.label,
            parentId = parentID,
            condition = { form = formID },
            columns = 6,
        })
        if not card then return false, message end
        self:SetSelectedCardState(card)
        return true
    end)
end

function UI:RenameCard(card)
    if IsFixedCard(card) then
        self:SetStatus("Default cards keep their names.", "warning")
        return
    end
    self:ShowPrompt("Rename card", "Name", "Rename", function(value)
        if not value or value == "" then return end
        Mutate("Card renamed", function()
            return Call("UpdateCard", CardID(card), { name = value }) ~= false
        end)
    end, { value = CardName(card) })
end

function UI:DeleteCard(card)
    if IsStandardCard(card) then
        self:SetStatus("Default cards cannot be deleted.", "warning")
        return
    end
    self:Confirm("Delete " .. CardName(card) .. "?", "Its abilities and nested subcards will also be removed.", function()
        local profile = Call("GetSelectedProfile")
        UI:CaptureUndo("card deletion", profile and profile.id)
        Mutate("Card deleted", function()
            local parent = UI:FindCard(ParentID(card))
            local ok = Call("DeleteCard", CardID(card))
            if ok ~= false and parent then UI:SetSelectedCardState(parent) end
            return ok ~= false
        end)
    end)
end

function UI:AddEntry(card, payload, slot)
    if not payload then
        self:SetStatus("Pick up a spell, item, toy, mount, or macro first.", "warning")
        return
    end
    Mutate("Ability added", function()
        payload = BindCards.CopyTable and BindCards.CopyTable(payload) or payload
        payload.slot = slot
        local result = Call("CreateTile", CardID(card), payload)
        if result == nil then result = Call("AddEntry", CardID(card), payload) end
        if result == false or result == nil then return false, UI.lastCallError end
        ClearCursor()
        return true
    end)
end

function UI:DeleteEntry(card, entry)
    local profile = Call("GetSelectedProfile")
    self:CaptureUndo("ability removal", profile and profile.id)
    Mutate("Ability removed", function()
        local result = Call("DeleteTile", EntryID(entry))
        if result == nil then result = Call("DeleteEntry", CardID(card), EntryID(entry)) end
        return result ~= false
    end)
end

function UI:SetEntryBinding(card, entry, key, confirmed)
    if InCombat() then return self:SetStatus("Bindings are locked during combat.", "warning") end
    if key == "ESCAPE" then return end
    if key == "BACKSPACE" or key == "DELETE" then key = nil end
    if key and not confirmed then
        local hover = Call("ParseHoverBinding", key)
        local systemAction = not hover and not Call("IsGamepadShortcut", key) and GetBindingAction and GetBindingAction(key)
        if type(systemAction) == "string" and (
            systemAction:match("^CLICK BindCardsBindingProxy:") or
            systemAction:match("^CLICK BindCardsBindingButton%d+:")
        ) then
            systemAction = ""
        end
        local conflict
        for _, otherEntry in ipairs(Entries(card)) do
            if EntryID(otherEntry) ~= EntryID(entry) then
                for _, otherKey in ipairs(otherEntry.bindings or {}) do
                    if otherKey == key then conflict = EntryLabel(otherEntry); break end
                end
            end
            if conflict then break end
        end
        if systemAction and systemAction ~= "" then conflict = systemAction end
        if conflict then
            self:Confirm("Replace binding?", (FormatKey(key) or key) .. " is used by " .. tostring(conflict) .. ".", function()
                UI:SetEntryBinding(card, entry, key, true)
            end)
            return
        end
        if hover then
            local notes = {}
            if hover.key == "BUTTON1" then notes[#notes + 1] = "Left click on matching unit frames will cast instead of targeting." end
            if hover.key == "BUTTON2" then notes[#notes + 1] = "Right click on matching unit frames will cast instead of opening the unit menu." end
            if Call("GetNativeClickBindingConflict", key) then
                notes[#notes + 1] = "Blizzard Click Casting already uses this click on Blizzard frames and will run first."
            end
            if #notes > 0 then
                self:Confirm("Bind " .. (FormatKey(key) or key) .. "?", table.concat(notes, "\n"), function()
                    UI:SetEntryBinding(card, entry, key, true)
                end)
                return
            end
        end
    end
    local changed = Mutate(key and "Binding assigned" or "Binding cleared", function()
        local result
        if key then
            result = Call("AssignTileBinding", EntryID(entry), key)
            if result == nil then result = Call("SetTileBinding", EntryID(entry), key, true) end
            if result == nil then result = Call("SetEntryBinding", EntryID(entry), key, confirmed == true) end
        else
            result = Call("ClearTileBindings", EntryID(entry))
        end
        return result ~= false
    end)
    if changed ~= false and key then
        C_Timer.After(0, function()
            local hover = Call("ParseHoverBinding", key)
            if hover then
                -- The recompile has not run yet; the tooltip shows live status.
                UI:SetStatus((FormatKey(key) or key) .. " assigned · mouseover on " ..
                    ((Call("FormatHoverScope", hover.scope) or ""):lower()), "success")
                return
            end
            local gamepadStatus = Call("GetGamepadBindingStatus", key)
            if gamepadStatus then
                UI:SetStatus(gamepadStatus, Call("GetGamepadBindingLabel", key, EntryID(entry)) == "active" and "success" or "warning")
                return
            end
            local conflict = Call("GetBindingConflict", key)
            if conflict then
                local owner = conflict:match("^CLICK Clique") and "Clique Global/Hovercast" or "Another active override"
                UI:SetStatus(key .. " assigned · " .. owner .. " still owns it", "warning")
            elseif UI.quickBind then
                UI:SetStatus(key .. " assigned · click Done to test", "success")
            end
        end)
    end
end

function UI:ClearEntryHoverBinding(card, entry, scope)
    if InCombat() then return self:SetStatus("Bindings are locked during combat.", "warning") end
    Mutate("Mouseover binding cleared", function()
        return Call("ClearTileHoverBindings", EntryID(entry), scope) ~= false
    end)
end

function UI:BeginBindCapture(card, entry)
    if InCombat() then return self:SetStatus("Bindings are locked during combat.", "warning") end
    if not self.frame or not self.frame:IsShown() then return end
    if self.displayPopover then self.displayPopover:Hide() end
    self:SetQuickBind(false)
    self:CancelDrag(true)
    local capture = self.capture
    capture.card, capture.entry = card, entry
    capture.title:SetText("Bind " .. EntryLabel(entry))
    capture.gamepadHeld = {}
    local page = capture.gamepadPage or 1
    for _, key in ipairs(entry.bindings or {}) do
        local gesture = Call("ParseGamepadShortcut", key)
        if gesture and gesture.page then page = gesture.page; break end
    end
    capture:SelectGamepadPage(page)
    -- Reopen on the ability's existing mouseover scope; otherwise a normal key.
    local scope = EntryHoverScope(entry)
    capture:SetHoverScope(scope == "HELP" or scope == "ANY", scope == "HARM" or scope == "ANY")
    capture:ClearAllPoints()
    capture:SetPoint("CENTER", UIParent, "CENTER")
    capture:Show()
    capture:Raise()
    capture:EnableKeyboard(true)
    if capture.EnableGamePadButton then capture:EnableGamePadButton(true) end
    capture:SetPropagateKeyboardInput(false)
end

function UI:SetQuickBind(enabled)
    if InCombat() then
        if not enabled then return self:EndTransientInteraction() end
        return self:SetStatus("Quick Bind is locked during combat.", "warning")
    end
    if enabled and (not self.frame or not self.frame:IsShown()) then return end
    local wasQuick = self.quickBind
    self.quickBind = enabled and true or false
    if self.quickBanner then self.quickBanner:Hide() end
    if self.quickEscape then
        -- Never keep a full-window keyboard listener alive. In Quick Bind,
        -- only the ability currently under the cursor captures a key.
        self.quickEscape:Hide()
        self.quickEscape:EnableKeyboard(false)
    end
    if self.hoveredTile then
        self.hoveredTile:EnableKeyboard(self.quickBind)
        pcall(self.hoveredTile.SetPropagateKeyboardInput, self.hoveredTile, not self.quickBind)
    end
    self.quickButton.label:SetText(self.quickBind and "Done" or "Quick Bind")
    if self.quickBind then
        self:SetStatus("Quick Bind · Hover an ability and press a key · Escape ends", "warning")
    else
        local function ReleaseTileKeyboard(tile)
            if not tile then return end
            tile:EnableKeyboard(false)
            pcall(tile.SetPropagateKeyboardInput, tile, true)
        end
        for _, tile in ipairs(self.tiles or {}) do ReleaseTileKeyboard(tile) end
        for _, view in pairs(self.cardViews or {}) do
            for _, tile in ipairs(view.tiles or {}) do ReleaseTileKeyboard(tile) end
        end
        self.hoveredTile, self.keyboardTile = nil, nil
        if wasQuick then self:SetStatus("Quick Bind ended.", "info") end
    end
    self:RefreshGrid()
end

function UI:EndTransientInteraction(reason)
    self.quickBind = false
    -- Keyboard propagation remains protected even through pcall. Combat
    -- cleanup must wait until lockdown ends, including OnShow/OnHide callers.
    if InCombat() then
        self.transientCleanupPending = true
        if reason then self:SetStatus(reason, "warning") end
        return
    end
    self.transientCleanupPending = nil
    if self.quickEscape then self.quickEscape:Hide(); self.quickEscape:EnableKeyboard(false) end
    if self.quickBanner then self.quickBanner:Hide() end
    if self.capture then
        self.capture:Hide(); self.capture:EnableKeyboard(false)
        pcall(self.capture.SetPropagateKeyboardInput, self.capture, true)
        self.capture.card, self.capture.entry = nil, nil
    end
    if self.modal then
        if self.modal.edit then self.modal.edit:ClearFocus() end
        if self.modal.multi then self.modal.multi:ClearFocus() end
        self.modal.activeEdit = nil
        self.modal:Hide()
    end
    if self.displayPopover then self.displayPopover:Hide() end
    if self.windowResizing then self:FinishWindowResize(true) end
    if self.cardResize then self:FinishCardResize(false) end
    if self.gridResize then self:FinishGridResize(false) end
    if self.resizeCapture then
        self.resizeCapture:Hide()
        self.resizeCapture:EnableKeyboard(false)
        pcall(self.resizeCapture.SetPropagateKeyboardInput, self.resizeCapture, true)
    end
    local function ReleaseKeyboard(frame)
        if not frame then return end
        pcall(frame.EnableKeyboard, frame, false)
        pcall(frame.SetPropagateKeyboardInput, frame, true)
    end
    ReleaseKeyboard(self.frame)
    ReleaseKeyboard(self.hoveredTile)
    for _, tile in ipairs(self.tiles or {}) do ReleaseKeyboard(tile) end
    for _, view in pairs(self.cardViews or {}) do
        ReleaseKeyboard(view)
        ReleaseKeyboard(view.tab)
        for _, tile in ipairs(view.tiles or {}) do ReleaseKeyboard(tile) end
    end
    self.hoveredTile, self.keyboardTile = nil, nil
    self:CancelDrag(true)
    if self.quickButton then self.quickButton.label:SetText("Quick Bind") end
    if reason then self:SetStatus(reason, "warning") end
end

function UI:GuardKeyboardFocus()
    -- Keyboard enablement becomes protected when a secure ability tile is in
    -- the ancestry.  The guard is only cleanup for editing state, so it must
    -- never touch those frames after combat lockdown begins.
    if InCombat() then return end
    if not self.frame or not self.frame:IsShown() then return end
    local chatActive = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    local tile = self.keyboardTile or self.hoveredTile
    if tile and (not self.quickBind or chatActive or not tile:IsShown() or not CursorInside(tile)) then
        tile:EnableKeyboard(false)
        pcall(tile.SetPropagateKeyboardInput, tile, true)
        if self.keyboardTile == tile then self.keyboardTile = nil end
        if self.hoveredTile == tile and not CursorInside(tile) then self.hoveredTile = nil end
    end
    if not self.quickBind then
        if self.quickEscape then self.quickEscape:EnableKeyboard(false) end
        self.frame:EnableKeyboard(false)
    end
    if self.modal and not self.modal:IsShown() then
        self.modal:EnableKeyboard(false)
        pcall(self.modal.SetPropagateKeyboardInput, self.modal, true)
        if self.modal.edit then self.modal.edit:ClearFocus() end
        if self.modal.multi then self.modal.multi:ClearFocus() end
    end
    if self.capture and not self.capture:IsShown() then
        self.capture:EnableKeyboard(false)
        pcall(self.capture.SetPropagateKeyboardInput, self.capture, true)
    end
    if self.resizeCapture then
        self.resizeCapture:EnableKeyboard(false)
        pcall(self.resizeCapture.SetPropagateKeyboardInput, self.resizeCapture, true)
        if not self.gridResize and not self.cardResize and not self.windowResizing then
            self.resizeCapture:Hide()
        end
    end
end

function UI:HandleQuickKey(raw, source)
    if InCombat() then return self:EndTransientInteraction() end
    if not self.quickBind then
        if source then source:SetPropagateKeyboardInput(true) end
        return
    end
    if raw == "ESCAPE" then
        if source then source:SetPropagateKeyboardInput(false) end
        self:SetQuickBind(false)
        return
    end
    if raw == "ENTER" or raw == "/" or raw == "SLASH" then
        if source then
            source:EnableKeyboard(false)
            source:SetPropagateKeyboardInput(true)
        end
        if self.keyboardTile == source then self.keyboardTile = nil end
        return
    end
    if not self.hoveredTile then
        if source then source:SetPropagateKeyboardInput(true) end
        return
    end
    local key = CapturedKey(raw)
    if key then
        if source then source:SetPropagateKeyboardInput(false) end
        self:SetEntryBinding(self.hoveredTile.card, self.hoveredTile.entry, key)
    elseif source then
        source:SetPropagateKeyboardInput(true)
    end
end

function UI:ShowEntryActions(card, entry, reopen)
    self.focusedEntry = entry
    self.focusedCardID = CardID(card)
    if reopen then self.entryInspectorDismissed = false end
    self.entryTitle:SetText(EntryLabel(entry))
    local bindingCount = #(entry.bindings or {})
    local primaryKey = EntryBinding(entry)
    local savedGamepad = Call("IsGamepadShortcut", primaryKey)
    local extraGamepad = false
    for _, binding in ipairs(entry.bindings or {}) do
        if binding ~= primaryKey and Call("IsGamepadShortcut", binding) then extraGamepad = true end
    end
    local primaryHover = Call("ParseHoverBinding", primaryKey)
    local prefix = savedGamepad and "Gamepad: " or
        (primaryHover and ("Mouseover (" .. (Call("FormatHoverScope", primaryHover.scope) or ""):lower() .. "): ")) or "Bound to  "
    self.entryBinding:SetText(primaryKey and (prefix .. (FormatKey(primaryKey, EntryID(entry)) or primaryKey) ..
        (bindingCount > 1 and ("  +" .. (bindingCount - 1)) or "") ..
        (extraGamepad and " · Gamepad shortcut (see tooltip)" or "")) or "Not bound")
    if self.entryMacroButton then
        self.entryMacroButton.label:SetText((entry.kind == "spell" or entry.type == "spell") and "Make macro" or ((entry.kind == "macro" or entry.type == "macro") and "Edit macro" or "New macro"))
    end
    if self.entryIconButton then self.entryIconButton.label:SetText(entry.manualIcon and "Auto icon" or "Icon ID") end
    if not self.entryInspectorDismissed then
        local settings = BindCardsDB and BindCardsDB.settings or {}
        if settings.workspaceMode == "panel" then
            self.entryPanel:SetScale(tonumber(settings.uiScale) or 1)
            self.entryPanel:Show()
            if self.entryPanel.Raise then self.entryPanel:Raise() end
            self.emptyRight:Hide()
        else
            self.entryPanel:Hide()
        end
    else
        self.entryPanel:Hide()
        self.emptyRight:Show()
    end
end

function UI:EditEntryIcon(entry)
    if not entry then return end
    if entry.manualIcon then
        Mutate("Automatic icon restored", function()
            return Call("UpdateTile", EntryID(entry), { manualIcon = false }) ~= false
        end)
        return
    end
    self:ShowPrompt("Manual icon", "Texture file ID", "Apply", function(value)
        local iconID = tonumber(value)
        if not iconID or iconID <= 0 or iconID % 1 ~= 0 then
            UI:SetStatus("Enter a valid numeric texture ID.", "warning")
            return false
        end
        return Mutate("Manual icon applied", function()
            return Call("UpdateTile", EntryID(entry), { manualIcon = iconID }) ~= false
        end)
    end, { value = tostring(entry.icon or "") })
end

function UI:ShowMacroDialog(card, entry, slot, anchor)
    local value = entry and (entry.macrotext or entry.body or "") or "#showtooltip\n"
    self:ShowPrompt(
        entry and "Edit macro" or "New macro",
        "Macro text  •  #showtooltip supported  •  Ctrl+Enter saves",
        entry and "Save" or "Create",
        function(body)
        if not body or body == "" then UI:SetStatus("Macro is empty.", "warning"); return false end
        if #body > 1023 then UI:SetStatus("Macro is too long.", "warning"); return false end
        if entry then
            Mutate("Macro updated", function()
                local _, action = Call("ResolveMacroIcon", body)
                local result = Call("UpdateTile", EntryID(entry), { macrotext = body, name = action or entry.name or "Macro" })
                return result ~= false
            end)
        else
            local _, action = Call("ResolveMacroIcon", body)
            UI:AddEntry(card, { kind = "macro", name = action or "Macro", macrotext = body }, slot)
        end
        end,
        {
            multiline = true, value = value, width = 400, height = 270, anchor = anchor,
            macroPreview = true, previewFallback = entry and entry.icon, maxLetters = 1023,
        }
    )
end

function UI:ShowSpellMenu(owner, card, entry)
    local menu = self.spellMenu
    if not menu then
        menu = CreateFrame("Frame", "BindCardsSpellMenu", UIParent, "BackdropTemplate")
        self.spellMenu = menu
        menu:SetSize(290, 76)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        Skin(menu, C.panel, C.border)
        menu.rows = {}
        menu:RegisterEvent("GLOBAL_MOUSE_DOWN")
        menu:SetScript("OnEvent", function(self)
            if self:IsShown() and not CursorInside(self) and not CursorInside(self.owner) then self:Hide() end
        end)
        if UISpecialFrames then tinsert(UISpecialFrames, "BindCardsSpellMenu") end
    end
    menu.owner = owner
    if not owner.bindCardsSpellMenuHook then
        owner.bindCardsSpellMenuHook = true
        owner:HookScript("OnHide", function() if menu.owner == owner then menu:Hide() end end)
    end
    local labels = { entry.highestRank and "Use current rank only" or "Always use highest learned rank", "Make macro" }
    local callbacks = {
        function()
            Mutate("Spell rank mode updated", function()
                local result, message = Call("SetTileHighestRank", EntryID(entry), not entry.highestRank)
                return result ~= nil and result ~= false, message
            end)
        end,
        function() UI:ShowSpellMacroDialog(card, entry, owner) end,
    }
    for index, label in ipairs(labels) do
        local row = menu.rows[index]
        if not row then row = Button(menu, "", 274, 26); menu.rows[index] = row end
        row:SetPoint("TOPLEFT", 8, -8 - (index - 1) * 30)
        row.label:SetText(label)
        local callback = callbacks[index]
        row:SetScript("OnClick", function() menu:Hide(); callback() end)
        row:Show()
    end
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(800)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
    menu:Show()
end

function UI:ShowSpellMacroDialog(_, entry, anchor)
    local name, icon = Call("GetTileDisplay", entry)
    local rank = entry.highestRank and "" or SpellRankText(entry)
    if type(name) ~= "string" or rank == nil then
        self:SetStatus("Spell rank information is unavailable. Try again after opening the spellbook.", "warning")
        return
    end
    -- Match the ranked spell token inserted by Blizzard's Camelot spellbook.
    local castName = rank ~= "" and (name .. "(" .. rank .. ")") or name
    local body = "#showtooltip\n" .. (SLASH_CAST1 or "/cast") .. " " .. castName
    self:ShowPrompt("Make macro", "Macro text", "Convert", function(value)
        if not value or value == "" then UI:SetStatus("Macro is empty.", "warning"); return false end
        if #value > 1023 then UI:SetStatus("Macro is too long.", "warning"); return false end
        Mutate("Macro created", function()
            return Call("ConvertTileToMacro", EntryID(entry), value, name, icon) ~= false
        end)
    end, {
        multiline = true, value = body, width = 400, height = 270, anchor = anchor,
        maxLetters = 1023,
        macroPreview = true, previewFallback = icon,
    })
end

FlattenCards = function(cards, includeHomeParent)
    local roots, children, known = {}, {}, {}
    for _, card in ipairs(cards) do known[CardID(card)] = true end
    for _, card in ipairs(cards) do
        local parent = ParentID(card) or (includeHomeParent and card.homeParentId)
        if parent and known[parent] then
            children[parent] = children[parent] or {}
            tinsert(children[parent], card)
        else
            tinsert(roots, card)
        end
    end
    local function Sort(list)
        tsort(list, function(a, b)
            local ao, bo = a.order or 9999, b.order or 9999
            if ao == bo then return CardName(a) < CardName(b) end
            return ao < bo
        end)
    end
    Sort(roots)
    for _, list in pairs(children) do Sort(list) end
    local result = {}
    local function Add(card, depth, last)
        tinsert(result, { card = card, depth = depth, last = last })
        local list = children[CardID(card)] or {}
        for i, child in ipairs(list) do Add(child, depth + 1, i == #list) end
    end
    for i, card in ipairs(roots) do Add(card, 0, i == #roots) end
    return result
end

function UI:RefreshNavigator()
    local _, binderKey, model = self:EnsureBinderSelection()
    local panelMode = BindCardsDB and BindCardsDB.settings and BindCardsDB.settings.workspaceMode == "panel"
    local flat = FlattenCards(model[binderKey].cards, panelMode)
    local navHeight = 4
    for _, row in ipairs(self.navRows) do row:Hide() end
    for index, info in ipairs(flat) do
        local row = self.navRows[index]
        if not row then
            row = CreateFrame("Button", nil, self.navContent, "BackdropTemplate")
            row:SetHeight(31)
            row.dot = row:CreateTexture(nil, "ARTWORK")
            row.dot:SetSize(7, 7)
            row.dot:SetTexture(EDGE)
            row.name = Font(row, 11, C.text)
            row.count = Font(row, 10, C.muted)
            row.count:SetJustifyH("RIGHT")
            row.connector = row:CreateTexture(nil, "BACKGROUND")
            ThemeSolid(row.connector, C.faint)
            row.tab = row:CreateTexture(nil, "BACKGROUND")
            row.tab:SetColorTexture(C.paper[1], C.paper[2], C.paper[3], 0.75)
            row:SetScript("OnClick", function(self)
                UI:SelectCard(self.card)
            end)
            row:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(C.raised)) end)
            row:SetScript("OnLeave", function(self) UI:StyleNavRow(self) end)
            self.navRows[index] = row
        end
        local mainRoot = IsMainBinderRoot(info.card)
        local rowHeight = mainRoot and 31 or (info.depth <= 1 and 27 or 24)
        local fontSize = mainRoot and 11 or (info.depth <= 1 and 10 or 9)
        row.card, row.bindCardsCard, row.depth = info.card, info.card, info.depth
        row:SetHeight(rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 3, -navHeight)
        row:SetPoint("RIGHT", -3, 0)
        local fontPath, _, fontFlags = row.name:GetFont()
        row.name:SetFont(fontPath, fontSize, fontFlags or "")
        row.dot:ClearAllPoints()
        local dotSize = mainRoot and 7 or (info.depth <= 1 and 6 or 5)
        row.dot:SetSize(dotSize, dotSize)
        row.dot:SetPoint("LEFT", 10 + info.depth * 15, 0)
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row.dot, "RIGHT", 8, 0)
        row.name:SetPoint("RIGHT", -37, 0)
        row.name:SetText(CardName(info.card))
        row.count:ClearAllPoints()
        row.count:SetPoint("RIGHT", -8, 0)
        row.count:SetText(#Entries(info.card))
        row.connector:ClearAllPoints()
        row.connector:SetPoint("TOPLEFT", 13 + (info.depth - 1) * 15, 4)
        row.connector:SetSize(info.depth > 0 and 12 or 0, 1)
        row.tab:ClearAllPoints()
        row.tab:SetPoint("LEFT", 3 + info.depth * 15, 0)
        row.tab:SetSize(info.depth > 0 and 3 or 0, 21)
        row:Show()
        self:StyleNavRow(row)
        navHeight = navHeight + rowHeight + (mainRoot and 4 or 2)
    end
    self.navContent:SetHeight(max(1, navHeight))
    self.emptyNav:SetShown(#flat == 0)
end

function UI:StyleNavRow(row)
    -- Legacy list rows already have a complete native rim. The old paper-tab
    -- rail and connector sit above/outside it and look like broken borders.
    local legacy = self.euiSkin and self.euiSkin.GetStyle and self.euiSkin.GetStyle() == "legacy"
    local showHierarchy = not legacy and (row.depth or 0) > 0
    row.connector:SetShown(showHierarchy)
    row.tab:SetShown(showHierarchy)
    local selected = self.selectedCardID == CardID(row.card)
    local active = IsCardActive(row.card)
    local amberNested = IsAmberNestedCard(row.card)
    local accent = amberNested and (selected and C.amber or C.amberMuted) or
        (selected and C.blue or C.teal)
    Skin(row, selected and C.raised or C.panel,
        amberNested and (selected and C.amber or C.amberFaint) or
        (selected and C.blue or C.faint))
    Color(row.dot, (active or amberNested) and accent or C.muted,
        selected and 1 or (active and 0.82 or (amberNested and 0.58 or 0.45)))
    row.name:SetTextColor(unpack(amberNested and accent or
        (selected and C.text or (active and C.text or C.muted))))
end

function UI:RefreshConditions(card)
    local conditions = card.condition or card.conditions or {}
    local canEditRules = not IsFixedCard(card)
    local parent = ParentID(card) and self:FindCard(ParentID(card))
    self.inherited:SetShown(parent ~= nil)
    if parent then self.inherited:SetText("Inherits  " .. CardName(parent)) end
    local values = {
        class = conditions.class or "Any class",
        spec = conditions.specGroup == 1 and "Primary" or conditions.specGroup == 2 and "Secondary" or "Any build",
        content = conditions.content or "Any content",
        form = conditions.form or "Any form",
    }
    local binderId = Call("GetCardBinderId", card)
    local binderClass = type(binderId) == "string" and binderId:match("^class:(.+)$") or nil
    local formOptions = Call("GetFormOptions", binderClass) or {}
    local supportsFormCondition = (ParentID(card) ~= nil or card.homeParentId ~= nil) and #formOptions > 0
    local visibleControls = {}
    for _, key in ipairs(self.conditionControlOrder or {}) do
        if key ~= "form" or supportsFormCondition then visibleControls[#visibleControls + 1] = key end
    end
    local spacing, height = #visibleControls >= 6 and 36 or 43, #visibleControls >= 6 and 31 or 36
    for index, key in ipairs(visibleControls) do
        local control = self.conditionControls[key]
        control:ClearAllPoints(); control:SetPoint("TOPLEFT", 9, -35 - (index - 1) * spacing)
        control:SetPoint("RIGHT", -9, 0); control:SetHeight(height); control:Show()
    end
    if self.conditionControls.form and not supportsFormCondition then self.conditionControls.form:Hide() end
    for key, control in pairs(self.conditionControls) do
        local display = Friendly(values[key], tostring(values[key]))
        if key == "form" and conditions.form and BindCards.FORM_DEFINITIONS then
            display = BindCards.FORM_DEFINITIONS[conditions.form] and BindCards.FORM_DEFINITIONS[conditions.form].label or display
        end
        control.value:SetText(display)
        control.current = values[key]
        control:SetEnabled(canEditRules)
        control:SetAlpha(canEditRules and 1 or 0.48)
    end
    if self.deleteCardButton then self.deleteCardButton:SetShown(not IsStandardCard(card)) end
end

function UI:SetConditionValue(card, key, value)
    if IsFixedCard(card) then
        self:SetStatus("Default card rules are fixed.", "warning")
        return false
    end
    local condition = BindCards.CopyTable and BindCards.CopyTable(card.condition or {}) or {}
    if key == "class" then condition.class = value ~= "Any class" and value or nil
    elseif key == "content" then condition.content = value ~= "Any content" and value or nil
    elseif key == "spec" then
        condition.specGroup = value == "Primary" and 1 or value == "Secondary" and 2 or nil
    elseif key == "form" then condition.form = value ~= "Any form" and value or nil
    end
    return Mutate("Condition updated", function()
        return Call("UpdateCard", CardID(card), { condition = condition }) ~= false
    end)
end

function UI:ShowConditionMenu(owner, card, key)
    if IsFixedCard(card) then
        self:SetStatus("Default card rules are fixed.", "warning")
        return
    end
    local options = self.conditionOptions[key]
    if key == "form" then
        options = { "Any form" }
        local binderId = Call("GetCardBinderId", card)
        local binderClass = type(binderId) == "string" and binderId:match("^class:(.+)$") or nil
        for _, option in ipairs(Call("GetFormOptions", binderClass) or {}) do options[#options + 1] = option.id end
    end
    if not options then return end
    self:ShowMenu(owner, function(root)
        root:CreateTitle(({ class = "Class", spec = "Build", content = "Content", form = "Form" })[key])
        local condition = card.condition or {}
        local hasCondition = (key == "class" and condition.class ~= nil) or
            (key == "spec" and condition.specGroup ~= nil) or
            (key == "content" and condition.content ~= nil and condition.content ~= "ANY") or
            (key == "form" and condition.form ~= nil)
        if hasCondition then
            -- options[1] is the "Any ..." value that clears the rule.
            root:CreateButton("Remove condition", function() UI:SetConditionValue(card, key, options[1]) end)
            root:CreateDivider()
        end
        for index, value in ipairs(options) do
            if index > 1 then
                local selected = value
                local label = key == "form" and BindCards.FORM_DEFINITIONS and
                    BindCards.FORM_DEFINITIONS[value] and BindCards.FORM_DEFINITIONS[value].label or
                    Friendly(value, value)
                root:CreateButton(label, function() UI:SetConditionValue(card, key, selected) end)
            end
        end
    end)
end

function UI:DropDraggedEntry(target)
    local drag = self.dragEntry
    if not drag or not drag.entry or not target or not target.card then return false end
    self:CancelDrag(true)
    Mutate(drag.copy and "Ability copied" or "Ability moved", function()
        if drag.copy then
            local payload = BindCards.CopyTable and BindCards.CopyTable(drag.entry) or drag.entry
            payload.id, payload.bindings = nil, {}
            payload.slot = target.index
            return Call("CreateTile", CardID(target.card), payload) ~= false
        end
        return Call("MoveTile", EntryID(drag.entry), CardID(target.card), target.index) ~= false
    end)
    return true
end

local function FirstAvailableSlot(card)
    local columns = min(12, max(3, tonumber(card and card.columns) or 6))
    local capacity = max(columns, tonumber(card and card.capacity) or columns * 2)
    local occupied = {}
    for fallback, entry in ipairs(Entries(card)) do
        local x, y = EntryGridPosition(card, entry, fallback)
        local slot = (y - 1) * columns + x
        if x >= 1 and x <= columns and slot >= 1 and slot <= capacity then occupied[slot] = true end
    end
    for slot = 1, capacity do
        if not occupied[slot] then return slot end
    end
end

function UI:DropDraggedEntryOnCard(card)
    local drag = self.dragEntry
    if not drag or not drag.entry or not card then return false end
    if card == drag.card then self:CancelDrag(true); return true end
    local slot = FirstAvailableSlot(card)
    if not slot then
        self:CancelDrag(true)
        self:SetStatus("That card has no empty cells.", "warning")
        return true
    end
    self:CancelDrag(true)
    Mutate(drag.copy and "Ability copied" or "Ability moved", function()
        if drag.copy then
            local payload = BindCards.CopyTable and BindCards.CopyTable(drag.entry) or drag.entry
            payload.id, payload.bindings, payload.slot = nil, {}, slot
            return Call("CreateTile", CardID(card), payload) ~= false
        end
        return Call("MoveTile", EntryID(drag.entry), CardID(card), slot) ~= false
    end)
    return true
end

function UI:FinishEntryDrag()
    if not self.dragEntry then return end
    local drag = self.dragEntry
    -- WoW keeps mouse capture on the source, so the target may miss OnMouseUp.
    -- GetMouseFoci is ordered topmost-first and avoids dropping through an
    -- overlapping detached card into a lower one.
    local focusedTile, blockedByCard = EntryTileUnderCursor()
    if focusedTile then
        self:DropDraggedEntry(focusedTile)
        return
    end
    local focusedTab = CardTabUnderCursor()
    if focusedTab and focusedTab.bindCardsCard then
        self:DropDraggedEntryOnCard(focusedTab.bindCardsCard)
        return
    elseif blockedByCard and self.entryDropCardView and self.entryDropCardView.card then
        self:DropDraggedEntryOnCard(self.entryDropCardView.card)
        return
    elseif not GetMouseFoci then
        for _, view in pairs(self.cardViews or {}) do
            if view:IsShown() then
                for _, tile in ipairs(view.tiles or {}) do
                    if tile:IsShown() and CursorInside(tile) then
                        self:DropDraggedEntry(tile)
                        return
                    end
                end
            end
        end
        for _, tile in ipairs(self.tiles or {}) do
            if tile:IsShown() and CursorInside(tile) then
                self:DropDraggedEntry(tile)
                return
            end
        end
    end
    -- Releasing between cells but still over a card cancels the move.
    -- Releasing beyond every card removes the original tile. Copy drags never
    -- remove their source.
    for _, view in pairs(self.cardViews or {}) do
        if view:IsShown() and (CursorInside(view) or (view.tab and view.tab:IsShown() and CursorInside(view.tab))) then
            self:CancelDrag(true)
            return
        end
    end
    if self.cardArea and self.cardArea:IsShown() and CursorInside(self.cardArea) then
        self:CancelDrag(true)
        return
    end
    self:CancelDrag(true)
    if not drag.copy and drag.entry then self:DeleteEntry(drag.card, drag.entry) end
end

local function ConfigureEntryTileCommon(tile)
    tile:SetScript("OnEnter", function(self)
        UI.hoveredTile = self.entry and self or nil
        if UI.keyboardTile and UI.keyboardTile ~= self then
            UI.keyboardTile:EnableKeyboard(false)
            pcall(UI.keyboardTile.SetPropagateKeyboardInput, UI.keyboardTile, true)
        end
        local chatActive = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
        local captureKey = UI.quickBind and self.entry ~= nil and not chatActive
        self:EnableKeyboard(captureKey)
        UI.keyboardTile = captureKey and self or nil
        pcall(self.SetPropagateKeyboardInput, self, not captureKey)
        self:SetBackdropBorderColor(unpack(UI.dragEntry and C.drop or (UI.quickBind and C.amber or C.blue)))
        if self.entry then
            TooltipEntry(self, self.entry)
            if self.unavailable then GameTooltip:AddLine("Unavailable in the current spec or talent setup", C.muted[1], C.muted[2], C.muted[3]); GameTooltip:Show() end
            if self.overridden then GameTooltip:AddLine("Overridden by active card", C.muted[1], C.muted[2], C.muted[3]); GameTooltip:Show() end
        end
    end)
    tile:SetScript("OnLeave", function(self)
        if UI.hoveredTile == self then UI.hoveredTile = nil end
        self:EnableKeyboard(false)
        if UI.keyboardTile == self then UI.keyboardTile = nil end
        pcall(self.SetPropagateKeyboardInput, self, true)
        GameTooltip:Hide()
        UI:StyleTile(self)
    end)
    tile:SetScript("OnKeyDown", function(self, key) UI:HandleQuickKey(key, self) end)
    tile:SetScript("OnReceiveDrag", function(self)
        if not UI:DropDraggedEntry(self) then
            local payload = CursorPayload()
            if payload then
                UI.suppressClick = true
                if C_Timer and C_Timer.After then C_Timer.After(0, function() UI.suppressClick = false end) end
                UI:AddEntry(self.card, payload, self.index)
            end
        end
    end)
    tile:SetScript("OnMouseDown", function(self, button)
        if UI.quickBind and button ~= "LeftButton" and button ~= "RightButton" then
            local key = MouseKey(button)
            if key and self.entry then UI:SetEntryBinding(self.card, self.entry, key) end
        elseif button == "LeftButton" then
            UI:ArmEntryDrag(self)
        end
    end)
    tile:SetScript("OnDragStart", function(self) UI:StartEntryDrag(self) end)
    tile:SetScript("OnDragStop", function() UI:ReleaseEntryDrag() end)
    tile:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then UI:ReleaseEntryDrag() end
    end)
    tile:SetScript("OnMouseWheel", function(self, delta)
        if UI.quickBind and self.entry then
            UI:SetEntryBinding(self.card, self.entry, CapturedKey(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
        else
            UI:ScrollWorkspace(delta)
        end
    end)
end

function UI:CreateTile(index)
    local tile = CreateFrame("Button", nil, self.gridContent, "BackdropTemplate")
    tile.bindCardsEntryTile = true
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tile:RegisterForDrag("LeftButton")
    tile:EnableMouseWheel(true)
    tile:EnableKeyboard(false)
    tile.icon = tile:CreateTexture(nil, "ARTWORK")
    tile.icon:SetPoint("TOPLEFT", 5, -5)
    tile.icon:SetPoint("BOTTOMRIGHT", -5, 5)
    tile.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tile.wash = tile:CreateTexture(nil, "OVERLAY")
    tile.wash:SetAllPoints(tile.icon)
    tile.wash:SetColorTexture(0.03, 0.04, 0.05, 0.32)
    tile.key = ShortcutLabel(tile, 22)
    tile.keySize = 22
    tile.activeKeySize = tile.keySize * 0.75
    tile.inactiveKeySize = tile.keySize * 0.75
    tile.key:SetPoint("TOPRIGHT", -5, -4)
    tile.name = Font(tile, 9, C.text, "OUTLINE")
    tile.name:SetPoint("BOTTOMLEFT", 6, 5)
    tile.name:SetPoint("BOTTOMRIGHT", -5, 5)
    tile.name:SetJustifyH("CENTER")
    tile.number = Font(tile, 8, C.muted)
    tile.number:SetPoint("TOPLEFT", 5, -4)
    ConfigureEntryTileCommon(tile)
    tile:SetScript("OnClick", function(self, button)
        if UI.suppressClick then return end
        if not self.entry then
            local payload = CursorPayload()
            if payload then UI:AddEntry(self.card, payload, self.index) else UI:ShowMacroDialog(self.card, nil, self.index, self) end
            return
        end
        if UI.quickBind then
            local key = MouseKey(button)
            if key then UI:SetEntryBinding(self.card, self.entry, key) end
            return
        end
        UI:ShowEntryActions(self.card, self.entry, true)
        if button == "RightButton" then
            if IsShiftKeyDown and IsShiftKeyDown() then
                UI:Confirm("Remove " .. EntryLabel(self.entry) .. "?", "This removes the tile and its bindings.", function() UI:DeleteEntry(self.card, self.entry) end)
            elseif self.entry.kind == "spell" or self.entry.type == "spell" then
                UI:ShowSpellMenu(self, self.card, self.entry)
            elseif self.entry.kind == "macro" or self.entry.type == "macro" then
                UI:ShowMacroDialog(self.card, self.entry, nil, self)
            end
        end
    end)
    self.tiles[index] = tile
    return tile
end

function UI:StyleTile(tile)
    local occupied = tile.entry ~= nil
    local skin = self.euiSkin
    local iconInk = skin and skin.GetAbilityLabelColor and skin.GetAbilityLabelColor()
    if tile.name then
        tile.name:SetTextColor(unpack(occupied and (iconInk or C.text) or C.muted))
        tile.name:SetShadowColor(0, 0, 0, 1)
        tile.name:SetShadowOffset(1, -1)
    end
    local focused = occupied and self.focusedEntry == tile.entry
    Skin(tile, occupied and C.paper or C.slot, focused and C.blue or C.faint)
    tile.wash:SetAlpha(tile.unavailable and 0.42 or (occupied and 0 or 0.45))
    tile:SetAlpha(tile.unavailable and 0.55 or 1)
    local keyFont, currentSize, keyFlags = tile.key:GetFont()
    keyFont = keyFont or (_G and _G.STANDARD_TEXT_FONT) or "Fonts\\FRIZQT__.TTF"
    local preferredSize = tile.bindingActive and tile.activeKeySize or tile.inactiveKeySize
    local keySize = tonumber(preferredSize) or tonumber(tile.keySize) or tonumber(currentSize) or 12
    local keyText = tile.key:GetText() or ""
    if Helpers.KeyFontSize then keySize = Helpers.KeyFontSize(keySize, keyText)
    elseif #keyText > 4 then keySize = max(8, floor(keySize * 4 / #keyText)) end
    keyFlags = keyFlags and keyFlags ~= "" and keyFlags or "OUTLINE"
    tile.key:SetFont(keyFont, keySize, keyFlags)
    -- Character counts misjudge wide glyphs (S-M2 is 4 characters but wider
    -- than a small tile). Measure and shrink to fit beside the slot number.
    local available = (tile.GetWidth and tile:GetWidth() or 0) - 9
    if tile.number and tile.number:IsShown() and (tile.number:GetText() or "") ~= "" then
        available = available - (tile.number:GetStringWidth() or 0) - 3
    end
    local measured = keyText ~= "" and tile.key.GetStringWidth and tile.key:GetStringWidth() or 0
    if available > 0 and measured > available then
        keySize = max(7, floor(keySize * available / measured))
        tile.key:SetFont(keyFont, keySize, keyFlags)
    end
    if tile.bindingActive then
        tile.key:SetTextColor(PlayerClassColor())
    else
        tile.key:SetTextColor(unpack(C.shortcutInactive))
    end
    self:StyleHoverBadge(tile)
end

-- The ability name spans the tile bottom; while the marker is shown, inset
-- it on both sides so it stays centred and clear of the marker.
local HOVER_BADGE_SIZE = 12
local function InsetTileName(tile, inset)
    local name = tile.name
    if not name or not name.GetNumPoints then return end
    if not tile.hoverNameAnchors then
        tile.hoverNameAnchors = {}
        for index = 1, name:GetNumPoints() do tile.hoverNameAnchors[index] = { name:GetPoint(index) } end
    end
    if (tile.hoverNameInset or false) == inset then return end
    tile.hoverNameInset = inset
    name:ClearAllPoints()
    for _, anchor in ipairs(tile.hoverNameAnchors) do
        local point, relativeTo, relativePoint, x, y = unpack(anchor)
        local shift = 0
        if inset and point:find("LEFT", 1, true) then shift = HOVER_BADGE_SIZE + 1 end
        if inset and point:find("RIGHT", 1, true) then shift = -(HOVER_BADGE_SIZE + 1) end
        name:SetPoint(point, relativeTo, relativePoint, (x or 0) + shift, y or 0)
    end
end

-- Mouseover marker: a small bullseye in the bottom-left corner. Friendly and
-- hostile tint the whole mark; "both" splits it down the middle.
function UI:StyleHoverBadge(tile)
    local scope = tile.entry and EntryHoverScope(tile.entry)
    local badge = tile.hoverBadge
    if not scope then
        if badge then badge:Hide() end
        if tile.hoverNameInset then InsetTileName(tile, false) end
        return
    end
    if not badge then
        badge = CreateFrame("Frame", nil, tile)
        badge:SetSize(HOVER_BADGE_SIZE, HOVER_BADGE_SIZE)
        badge:SetPoint("BOTTOMLEFT", 4, 4)
        badge.left = badge:CreateTexture(nil, "OVERLAY", nil, 7)
        badge.left:SetTexture(HOVER_TEXTURE)
        badge.left:SetPoint("TOPLEFT")
        badge.left:SetPoint("BOTTOMRIGHT", badge, "BOTTOM")
        badge.left:SetTexCoord(0, 0.5, 0, 1)
        badge.right = badge:CreateTexture(nil, "OVERLAY", nil, 7)
        badge.right:SetTexture(HOVER_TEXTURE)
        badge.right:SetPoint("TOPLEFT", badge, "TOP")
        badge.right:SetPoint("BOTTOMRIGHT")
        badge.right:SetTexCoord(0.5, 1, 0, 1)
        tile.hoverBadge = badge
    end
    badge:SetFrameLevel(tile:GetFrameLevel() + 3)
    local left = scope == "HARM" and C.hoverHostile or C.hoverFriendly
    local right = scope == "HELP" and C.hoverFriendly or C.hoverHostile
    badge.left:SetVertexColor(left[1], left[2], left[3])
    badge.right:SetVertexColor(right[1], right[2], right[3])
    badge:SetAlpha(tile.bindingActive and 1 or 0.9)
    badge:Show()
    InsetTileName(tile, tile.name and tile.name:IsShown() or false)
end

function UI:RefreshGrid()
    local card = self:GetSelectedCard()
    if self.workspaceContent then
        if card then
            self:RefreshConditions(card)
            if self.focusedEntry then self:ShowEntryActions(card, self.focusedEntry) else self.entryPanel:Hide(); self.emptyRight:Show() end
        end
        self:RefreshWorkspace()
        return
    end
    if not card then
        self.cardArea:Hide()
        self.welcome:Show()
        return
    end
    self.welcome:Hide()
    self.cardArea:Show()
    local active, reason = IsCardActive(card)
    self.cardTitle:SetText(CardName(card))
    local canRename = not IsFixedCard(card)
    self.renameButton:SetEnabled(canRename)
    self.renameButton:SetAlpha(canRename and 1 or 0.32)
    self.cardStatus:SetText(active and "ACTIVE" or "INACTIVE")
    self.cardStatus:SetTextColor(unpack(active and C.teal or C.muted))
    self.cardReason:SetText(reason or (active and "Matches" or "Does not match"))
    self:RefreshConditions(card)
    local columns = min(12, max(3, tonumber(card.columns or card.gridColumns or 6) or 6))
    self.columnValue:SetText(columns .. " columns")
    local width = self.gridScroll:GetWidth() - 15
    local gap = 7
    local size = floor((width - gap * (columns - 1)) / columns)
    size = min(64, max(42, size))
    local capacity = max(columns, tonumber(card.capacity) or columns * 2)
    local slots = capacity
    local rows = math.ceil(slots / columns)
    local entries = EntriesBySlot(card, columns, rows)
    local winners = BindCards.lastCompiledBindings or Call("CompileBindings") or {}
    self.gridContent:SetHeight(rows * (size + gap) + 12)
    for _, tile in ipairs(self.tiles) do tile:Hide() end
    for index = 1, slots do
        local tile = self.tiles[index] or self:CreateTile(index)
        local col = (index - 1) % columns
        local row = floor((index - 1) / columns)
        tile:SetSize(size, size)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", 4 + col * (size + gap), -4 - row * (size + gap))
        tile.index, tile.card, tile.entry = index, card, entries[index]
        tile.number:SetText(index)
        tile.icon:SetTexture(tile.entry and EntryIcon(tile.entry) or WHITE_ICON)
        tile.icon:SetDesaturated(not tile.entry)
        tile.icon:SetAlpha(tile.entry and 1 or 0.035)
        tile.name:SetText(tile.entry and EntryLabel(tile.entry) or "+")
        tile.name:SetShown(not tile.entry or not (BindCardsDB and BindCardsDB.settings and
            BindCardsDB.settings.showAbilityNames == false))
        tile.name:SetTextColor(unpack(tile.entry and C.text or C.muted))
        tile.key:SetText(tile.entry and (FormatKey(EntryBinding(tile.entry), EntryID(tile.entry)) or "") or "")
        local key = tile.entry and EntryBinding(tile.entry)
        key = key and (Call("NormalizeKey", key) or key)
        local winner = key and (winners[key] or (BindCards.lastAppliedGamepadBindings or {})[key] or
            (BindCards.lastAppliedHoverBindings or {})[key])
        tile.bindingActive = active and winner and EntryID(winner) == EntryID(tile.entry) or false
        tile.overridden = key and winner and EntryID(winner) ~= EntryID(tile.entry) or false
        tile.unavailable = EntrySpellUnavailable(tile.entry)
        tile.number:SetText(tile.overridden and "OVR" or index)
        tile:Show()
        self:StyleTile(tile)
    end
    if self.focusedEntry then self:ShowEntryActions(card, self.focusedEntry) else self.entryPanel:Hide(); self.emptyRight:Show() end
end

function UI:RefreshProfiles()
    local profile = Call("GetSelectedProfile")
    local name = profile and profile.name or "Default"
    local paused = profile and profile.bindingsEnabled == false
    self.profileName:SetText(tostring(name) .. (paused and " · PAUSED" or ""))
    self.profileName:SetTextColor(unpack(paused and C.amber or C.muted))
end

function UI:RefreshBindingChrome()
    if not self.frame or not self.frame:IsShown() then return end

    local states = BindCards.lastActiveCardStates
    if type(states) ~= "table" then
        states = select(2, Call("GetActiveCards", Call("GetSelectedProfile")))
    end
    self.activeCardStates = type(states) == "table" and states or {}
    self.activeSnapshotReady = type(states) == "table"
    local winners = BindCards.lastCompiledBindings or {}
    local seen = {}

    local function RefreshTile(tile)
        if not tile or seen[tile] or not tile:IsShown() then return end
        seen[tile] = true
        local entry, card = tile.entry, tile.card
        local key = entry and EntryBinding(entry)
        key = key and (Call("NormalizeKey", key) or key)
        local winner = key and (winners[key] or (BindCards.lastAppliedGamepadBindings or {})[key] or
            (BindCards.lastAppliedHoverBindings or {})[key])
        local active = card and IsCardActive(card) or false
        tile.bindingActive = active and winner and EntryID(winner) == EntryID(entry) or false
        tile.overridden = key and winner and EntryID(winner) ~= EntryID(entry) or false
        tile.unavailable = EntrySpellUnavailable(entry)
        if tile.key then tile.key:SetText(entry and (FormatKey(EntryBinding(entry), EntryID(entry)) or "") or "") end
        if tile.number then tile.number:SetText(tile.overridden and "OVR" or tile.index or "") end
        if tile.override then tile.override:SetShown(tile.overridden) end
        self:StyleTile(tile)
    end

    for _, tile in ipairs(self.tiles or {}) do RefreshTile(tile) end
    for _, view in pairs(self.cardViews or {}) do
        for _, tile in ipairs(view.tiles or {}) do RefreshTile(tile) end
    end
end

-- Brightness of unselected active tab marks in Legacy (1 = the accent).
UI.LEGACY_UNSELECTED_MARK_SHADE = 0.5

function UI:StyleAppearanceTab(tab, selected, active, disabled)
    local skin = self.euiSkin
    if not skin or not skin.GetTabStyle then return end
    local background, ink, border = skin.GetTabStyle(selected, active, disabled)
    if not background then return end
    skin.StyleTab(tab, selected, active, disabled)
    tab:SetBackdropColor(unpack(background))
    tab:SetBackdropBorderColor(unpack(border))
    tab:SetAlpha(1)
    tab.label:SetTextColor(unpack(ink))
    if tab.count then tab.count:SetTextColor(unpack(ink)) end
    if tab.expand then
        for _, line in ipairs(tab.expand.lines) do line:SetColorTexture(unpack(ink)) end
    end
    if tab.activeMark then
        -- Legacy tabs stay dark bronze when selected: the selected mark is the
        -- (class) accent and unselected active marks a deeper shade of it.
        -- Other skins fill the selected tab with the accent and use its ink.
        local legacy = skin.GetStyle and skin.GetStyle() == "legacy"
        local mark
        if legacy then
            local shade = UI.LEGACY_UNSELECTED_MARK_SHADE
            mark = selected and C.teal or { C.teal[1] * shade, C.teal[2] * shade, C.teal[3] * shade, 1 }
        else
            mark = selected and ink or C.teal
        end
        Color(tab.activeMark, mark)
        tab.activeMark:SetShown(not disabled and (selected or active))
    end
end

function UI:RefreshBinderSelectors()
    if not self.generalBinder or not self.classBinder then return end
    local _, selectedKey, model = self:EnsureBinderSelection()
    local anyDockedRoot = false
    local function RefreshButton(button, key)
        local binder = model[key]
        local selected = key == selectedKey
        local panelMode = BindCardsDB and BindCardsDB.settings and BindCardsDB.settings.workspaceMode == "panel"
        local detached = not panelMode and binder.root and
            (binder.root.layoutMode == "floating" or self.peelingCardID == CardID(binder.root))
        if binder.root and not detached then anyDockedRoot = true end
        button.label:SetText(binder.label)
        button.label:SetTextColor(unpack(self.useTopSurfaceText and C.topText or C.text))
        ApplyCardIcon(button.icon, binder.root)
        local active = false
        for _, card in ipairs(binder.cards) do
            if IsCardActive(card) then active = true break end
        end
        Color(button.dot, active and C.teal or C.muted, active and 1 or 0.35)
        Skin(button, selected and C.raised or C.paperAlt, selected and C.blue or C.faint)
        button:SetAlpha(#binder.cards > 0 and 1 or 0.42)
        UI:StyleAppearanceTab(button, selected, active, #binder.cards == 0)
        button:EnableMouse(#binder.cards > 0)
        button:SetShown(#binder.cards > 0 and not detached)
    end
    RefreshButton(self.generalBinder, "general")
    RefreshButton(self.classBinder, "class")
    if self.characterBinder then RefreshButton(self.characterBinder, "character") end
    local wasAllDetached = self.allBindersDetached == true
    local detachedStateChanged = self.allBindersDetached ~= (not anyDockedRoot)
    self.allBindersDetached = not anyDockedRoot
    self.binderBar:SetShown(anyDockedRoot or self.dragSession ~= nil)
    if self.workspaceScroll then
        local panelMode = BindCardsDB and BindCardsDB.settings and BindCardsDB.settings.workspaceMode == "panel"
        self.workspaceScroll:SetShown(panelMode or anyDockedRoot)
    end
    if detachedStateChanged and self.frame then
        local settings = BindCardsDB and BindCardsDB.settings or {}
        if wasAllDetached and anyDockedRoot and settings.binderManualSize and settings.binderHeight then
            self.frame:SetHeight(settings.binderHeight)
        end
        self:ApplySafeWindowBounds(false)
    end
    self:PositionWorkspaceDrop()
    if self.navTitle then self.navTitle:SetText(model[selectedKey].label .. " CARDS") end
end

function UI:PositionWorkspaceDrop()
    if not self.workspaceDrop then return end
    self.workspaceDrop:ClearAllPoints()
    self.workspaceDrop:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 8, -57)
    self.workspaceDrop:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -8, -57)
    self.workspaceDrop:SetHeight(60)
end

function UI:Refresh()
    if not self.frame then return end
    if not self.frame:IsShown() then self.refreshPending = true; return end
    -- A peel queues data refreshes. Rebuilding at the saved floating position
    -- during a drag moves the page away from the cursor; finish/cancel rebuilds.
    if self.dragSession then self.refreshPending = true; return end
    self.refreshPending = nil
    if self.dragEntry or self.pendingEntryDrag then self:CancelDrag(true) end
    local _, states = Call("GetActiveCards", Call("GetSelectedProfile"))
    self.activeCardStates = type(states) == "table" and states or {}
    self.activeSnapshotReady = type(states) == "table"
    self:EnsureBinderSelection()
    self:RefreshBinderSelectors()
    self:RefreshNavigator()
    self:RefreshGrid()
    self:RefreshProfiles()
    local combat = InCombat()
    self.combatBadge:SetShown(combat)
    if combat then self:SetStatus("Editing paused in combat.", "warning") end
end

function UI:RequestRefresh()
    if not self.frame or not self.frame:IsShown() then self.refreshPending = true; return end
    if self.refreshQueued then return end
    self.refreshQueued = true
    local function Run()
        UI.refreshQueued = nil
        UI:Refresh()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, Run) else Run() end
end

function UI:SetColumns(cardOrDelta, maybeDelta)
    local card, delta
    if type(cardOrDelta) == "table" then
        card, delta = cardOrDelta, maybeDelta
    else
        card, delta = self:GetSelectedCard(), cardOrDelta
    end
    if not card then return end
    local oldColumns = min(12, max(3, tonumber(card.columns or card.gridColumns) or 6))
    local columns = min(12, max(3, oldColumns + (tonumber(delta) or 0)))
    local rows = max(math.ceil((tonumber(card.capacity) or oldColumns * 2) / oldColumns), 1)
    Mutate("Grid resized", function()
        return Call("UpdateCard", CardID(card), { columns = columns, capacity = min(192, rows * columns) }) ~= false
    end)
end

function UI:SetRows(card, delta)
    card = card or self:GetSelectedCard()
    if not card then return end
    local columns = min(12, max(3, tonumber(card.columns) or 6))
    local rows = max(1, math.ceil((tonumber(card.capacity) or columns * 2) / columns) + delta)
    rows = min(math.floor(192 / columns), rows)
    Mutate("Grid resized", function()
        return Call("UpdateCard", CardID(card), { capacity = rows * columns }) ~= false
    end)
end

function UI:BeginCardResize(view)
    if InCombat() then return self:SetStatus("Card sizing is unavailable during combat.", "warning") end
    if not view or not view.card or not view:IsShown() then return end
    if self.dragSession then return end
    self.pendingCardDrag = nil
    if self.cardDragWatcher then self.cardDragWatcher:Hide() end
    if self.gridResize then self:FinishGridResize(false) end
    if self.cardResize then self:FinishCardResize(false) end
    local cursorX, cursorY = GetCursorPosition()
    if issecretvalue and (issecretvalue(cursorX) or issecretvalue(cursorY)) then return end
    local viewScale = view:GetEffectiveScale()
    local coordinateScale = viewScale / UIParent:GetEffectiveScale()
    local viewLeft, viewTop = view:GetLeft(), view:GetTop()
    self.cardResize = {
        view = view,
        card = view.card,
        startX = cursorX,
        startY = cursorY,
        scale = viewScale > 0 and viewScale or 1,
        width = view:GetWidth(),
        height = view:GetHeight(),
        originalWidth = view:GetWidth(),
        originalHeight = view:GetHeight(),
        viewLeft = viewLeft and viewLeft * coordinateScale or nil,
        viewTop = viewTop and viewTop * coordinateScale or nil,
    }
    view.resizeBadge:SetText(string.format("%d × %d", floor(view:GetWidth() + 0.5), floor(view:GetHeight() + 0.5)))
    view.resizeBadge:Show()
    if self.resizeCapture then self.resizeCapture:Show(); self.resizeCapture:EnableKeyboard(false) end
    self:SetStatus("Drag the outer corner to resize this card.", "info")
end

function UI:UpdateCardResize()
    local state = self.cardResize
    if not state then return end
    if InCombat() then self:FinishCardResize(false); return end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        self:FinishCardResize(true)
        return
    end
    local cursorX, cursorY = GetCursorPosition()
    if issecretvalue and (issecretvalue(cursorX) or issecretvalue(cursorY)) then return end
    local width = min(720, max(300, state.originalWidth + (cursorX - state.startX) / state.scale))
    local columns = min(12, max(3, tonumber(state.card.columns) or 6))
    local rows = max(1, math.ceil((tonumber(state.card.capacity) or columns * 2) / columns))
    local iconSize = BindCardsDB and BindCardsDB.settings and BindCardsDB.settings.iconSize or 36
    local renderedIconSize = min(iconSize, max(18, floor((width - 16 - (columns - 1) * 6) / columns)))
    local naturalHeight = state.card.collapsed and 35 or (78 + rows * (renderedIconSize + 6) - 6)
    local height = min(1000, max(naturalHeight, state.originalHeight + (state.startY - cursorY) / state.scale))
    if math.abs(width - state.width) < 0.5 and math.abs(height - state.height) < 0.5 then return end
    state.width, state.height = width, height
    state.view.resizeBadge:SetText(string.format("%d × %d", floor(width + 0.5), floor(height + 0.5)))
    self:RefreshWorkspace()
end

function UI:FinishCardResize(commit)
    local state = self.cardResize
    if not state then return end
    self.cardResize = nil
    if self.resizeCapture and not self.gridResize and not self.windowResizing then self.resizeCapture:Hide() end
    if state.view and state.view.resizeBadge then state.view.resizeBadge:Hide() end
    if commit and (math.abs(state.width - state.originalWidth) >= 0.5 or
            math.abs(state.height - state.originalHeight) >= 0.5) then
        local resized = Mutate("Card resized", function()
            return Call("UpdateCard", CardID(state.card), {
                paperWidth = floor(state.width + 0.5),
                paperHeight = floor(state.height + 0.5),
            }) ~= false
        end)
        if resized then self:SetStatus("Card size saved.", "success") end
    end
    self:RefreshWorkspace()
end

function UI:BeginGridResize(view)
    if InCombat() then return self:SetStatus("Grid editing is unavailable during combat.", "warning") end
    if not self.frame or not self.frame:IsShown() then return end
    if not view or not view.card or not view.grid then return end
    if self.dragSession then return end
    self.pendingCardDrag = nil
    if self.cardDragWatcher then self.cardDragWatcher:Hide() end
    if self.cardResize then self:FinishCardResize(false) end
    local left, top = view.grid:GetLeft(), view.grid:GetTop()
    if not left or not top then return end
    local columns = min(12, max(3, tonumber(view.card.columns) or 6))
    local rows = max(1, math.ceil((tonumber(view.card.capacity) or columns * 2) / columns))
    local viewScale = view:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local viewLeft, viewTop = view:GetLeft(), view:GetTop()
    self.gridResize = {
        view = view, card = view.card,
        left = left * view.grid:GetEffectiveScale(), top = top * view.grid:GetEffectiveScale(),
        cell = ((view.renderedIconSize or 36) + 6) * view.grid:GetEffectiveScale(),
        viewLeft = viewLeft and viewLeft * viewScale or nil,
        viewTop = viewTop and viewTop * viewScale or nil,
        columns = columns, rows = rows,
        originalColumns = columns, originalRows = rows,
    }
    view.resizeBadge:SetText(columns .. " × " .. rows)
    view.resizeBadge:Show()
    if self.resizeCapture then
        self.resizeCapture:Show()
        self.resizeCapture:EnableKeyboard(false)
    end
    self:SetStatus("Drag the corner to resize the grid.", "info")
end

function UI:UpdateGridResize()
    local state = self.gridResize
    if not state then return end
    if InCombat() then self:FinishGridResize(false); return end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
        self:FinishGridResize(true)
        return
    end
    local cursorX, cursorY = GetCursorPosition()
    if issecretvalue and (issecretvalue(cursorX) or issecretvalue(cursorY)) then return end
    local columns = min(12, max(3, floor((max(0, cursorX - state.left) + state.cell * 0.5) / state.cell)))
    local minimumRows = 1
    local maximumRows = max(1, math.floor(192 / columns))
    local rows = min(maximumRows, max(minimumRows, floor((max(0, state.top - cursorY) + state.cell * 0.5) / state.cell)))
    if columns == state.columns and rows == state.rows then return end
    state.columns, state.rows = columns, rows
    state.view.resizeBadge:SetText(columns .. " × " .. rows)
    -- Only the paper workspace consumes the live row/column preview. Rebuilding
    -- the entire Panel navigator and surrounding shell while the mouse is down
    -- can leave those siblings in an intermediate visibility state.
    self:RefreshWorkspace()
end

function UI:FinishGridResize(commit)
    local state = self.gridResize
    if not state then return end
    local values = { columns = state.columns, capacity = state.columns * state.rows }
    self.gridResize = nil
    if self.resizeCapture and not self.cardResize and not self.windowResizing then
        self.resizeCapture:Hide(); self.resizeCapture:EnableKeyboard(false)
    end
    if state.view and state.view.resizeBadge then state.view.resizeBadge:Hide() end
    if commit and (state.columns ~= state.originalColumns or state.rows ~= state.originalRows) then
        local resized = Mutate("Grid resized", function()
            return Call("UpdateCard", CardID(state.card), values) ~= false
        end)
        if resized then self:RefreshWorkspace() end
    else
        self:RefreshWorkspace()
        if not commit then self:SetStatus("Grid resize cancelled.", "info") end
    end
end

function UI:SetVisualSetting(key, delta)
    BindCardsDB = type(BindCardsDB) == "table" and BindCardsDB or {}
    BindCardsDB.settings = type(BindCardsDB.settings) == "table" and BindCardsDB.settings or {}
    if key == "uiScale" then
        local screenCap = min(1.40, (UIParent:GetWidth() or 960) / 980, (UIParent:GetHeight() or 650) / 680)
        local value = min(screenCap, max(0.65, (tonumber(BindCardsDB.settings.uiScale) or 1) + delta))
        BindCardsDB.settings.uiScale = floor(value * 20 + 0.5) / 20
        self.frame:SetScale(BindCardsDB.settings.uiScale)
        if self.entryPanel then self.entryPanel:SetScale(BindCardsDB.settings.uiScale) end
        self:ApplySafeWindowBounds(false)
    else
        BindCardsDB.settings.iconSize = min(48, max(24, (tonumber(BindCardsDB.settings.iconSize) or 36) + delta))
    end
    self:RefreshWorkspace()
    self:RefreshVisualLabels()
end

function UI:RefreshAppearancePopoverLayer()
    local display = self.displayPopover
    if not display or not display:IsShown() then return end
    if self.frame then display:SetScale(self.frame:GetScale()) end
    -- The popover is a UIParent-owned sibling of the ears, not a child of
    -- the HIGH workspace. Explicitly layer its controls as well as its plate.
    local function Layer(frame, depth)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetFrameLevel(800 + depth)
        for _, child in ipairs({ frame:GetChildren() }) do Layer(child, depth + 1) end
    end
    Layer(display, 0)
end

function UI:RefreshVisualLabels()
    self:RefreshAppearancePopoverLayer()
    local settings = BindCardsDB and BindCardsDB.settings or {}
    local scaleText = floor((settings.uiScale or 1) * 100 + 0.5) .. "%"
    local iconText = (settings.iconSize or 36) .. "px"
    if self.scaleValue then self.scaleValue:SetText(scaleText) end
    if self.iconValue then self.iconValue:SetText(iconText) end
    if self.scaleHeaderValue then self.scaleHeaderValue:SetText(scaleText) end
    if self.iconHeaderValue then self.iconHeaderValue:SetText(iconText) end
    if self.displayScaleValue then self.displayScaleValue:SetText(scaleText) end
    if self.displayIconValue then self.displayIconValue:SetText(iconText) end
end

function UI:GetSafeWindowBounds()
    local parentScale = UIParent:GetEffectiveScale() or 1
    local frameScale = self.frame and self.frame:GetEffectiveScale() or parentScale
    local ratio = frameScale > 0 and (frameScale / parentScale) or 1
    local screenWidth, screenHeight = UIParent:GetWidth() or 960, UIParent:GetHeight() or 650
    local maximumWidth = min(1200, floor((screenWidth - 32) / ratio))
    local maximumHeight = min(1000, floor((screenHeight - 32) / ratio))
    local binder = BindCardsDB and BindCardsDB.settings and BindCardsDB.settings.workspaceMode ~= "panel"
    local minimumHeight = binder and (self.allBindersDetached and 53 or 150) or 280
    local minimumWidth = binder and 560 or
        (Helpers.PanelMinimumWidth and Helpers.PanelMinimumWidth() or 692)
    return minimumWidth, minimumHeight, max(minimumWidth, maximumWidth), max(minimumHeight, maximumHeight)
end

function UI:ApplySafeWindowBounds(resetOversized)
    if not self.frame then return false end
    local minimumWidth, minimumHeight, maximumWidth, maximumHeight = self:GetSafeWindowBounds()
    if self.frame.SetResizeBounds then
        self.frame:SetResizeBounds(minimumWidth, minimumHeight, maximumWidth, maximumHeight)
    elseif self.frame.SetMinResize then
        self.frame:SetMinResize(minimumWidth, minimumHeight)
        if self.frame.SetMaxResize then self.frame:SetMaxResize(maximumWidth, maximumHeight) end
    end
    local settings = BindCardsDB and BindCardsDB.settings or {}
    local panel = settings.workspaceMode == "panel"
    local savedWidth = tonumber(panel and settings.windowWidth or settings.binderWidth) or self.frame:GetWidth()
    local savedHeight = tonumber(panel and settings.windowHeight or settings.binderHeight) or self.frame:GetHeight()
    local oversized = savedWidth > maximumWidth or savedHeight > maximumHeight or
        self.frame:GetWidth() > maximumWidth or self.frame:GetHeight() > maximumHeight
    local clearlyUnusable = savedWidth > 900 or savedHeight > 700
    if resetOversized and (oversized or clearlyUnusable) then
        local width = min(maximumWidth, panel and 820 or 580)
        local height = min(maximumHeight, panel and 520 or 300)
        self.frame:SetSize(max(minimumWidth, width), max(minimumHeight, height))
        if panel then
            settings.windowWidth, settings.windowHeight, settings.windowManualSize = self.frame:GetWidth(), self.frame:GetHeight(), false
        else
            settings.binderWidth, settings.binderHeight, settings.binderManualSize = self.frame:GetWidth(), self.frame:GetHeight(), false
        end
        self.frame:ClearAllPoints()
        self.frame:SetPoint("LEFT", UIParent, "LEFT", 34, 0)
        return true
    end
    local width = min(maximumWidth, max(minimumWidth, self.frame:GetWidth()))
    local height = min(maximumHeight, max(minimumHeight, self.frame:GetHeight()))
    self.frame:SetSize(width, height)
    if panel and settings.windowManualSize then
        settings.windowWidth, settings.windowHeight = width, height
    elseif not panel and settings.binderManualSize and not self.allBindersDetached then
        settings.binderWidth, settings.binderHeight = width, height
    end
    if self.frame.ClampToScreen then self.frame:ClampToScreen() end
    return oversized
end

function UI:SaveWindowPosition()
    if not self.frame then return end
    local x, y = self.frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if issecretvalue and
        (issecretvalue(x) or issecretvalue(y) or issecretvalue(parentX) or issecretvalue(parentY)) then return end
    if not (x and y and parentX and parentY) then return end
    local coordinateScale = self.frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local settings = BindCardsDB and BindCardsDB.settings
    if not settings then return end
    settings.windowX = floor(x * coordinateScale - parentX + 0.5)
    settings.windowY = floor(y * coordinateScale - parentY + 0.5)
end

function UI:SaveWindowSize(markManual)
    if not self.frame then return end
    local settings = BindCardsDB and BindCardsDB.settings
    if not settings then return end
    local width, height = self.frame:GetWidth(), self.frame:GetHeight()
    if issecretvalue and (issecretvalue(width) or issecretvalue(height)) then return end
    if not (width and height) then return end
    width, height = floor(width + 0.5), floor(height + 0.5)
    if settings.workspaceMode == "panel" then
        if markManual then settings.windowManualSize = true end
        if settings.windowManualSize then
            settings.windowWidth, settings.windowHeight = width, height
        end
    else
        if markManual then settings.binderManualSize = true end
        -- The all-detached header is a temporary collapsed state, not the
        -- user's chosen Binder size.
        if settings.binderManualSize and not self.allBindersDetached then
            settings.binderWidth, settings.binderHeight = width, height
        end
    end
end

function UI:SaveWindowPlacement(markManual)
    self:SaveWindowSize(markManual)
    self:SaveWindowPosition()
end

function UI:FinishWindowResize(cancelled)
    local state = self.windowResizing
    if not state or not self.frame then return false end
    self.frame:StopMovingOrSizing()
    self.windowResizing = nil
    self.resizeHoverToken = (self.resizeHoverToken or 0) + 1
    if self.resizeCapture and not self.gridResize and not self.cardResize then self.resizeCapture:Hide() end
    if self.windowResizeGrip then self.windowResizeGrip:Show() end

    local token = {}
    self.windowResizeFinishToken = token
    local function CompleteResize()
        if UI.windowResizeFinishToken ~= token then return end
        UI.windowResizeFinishToken = nil
        local settings = BindCardsDB and BindCardsDB.settings or {}
        local mode = state.mode or (settings.workspaceMode == "panel" and "panel" or "binder")
        UI:ApplyWorkspaceMode(mode, true)
        UI:SaveWindowPlacement(not cancelled)
        UI:UpdateWorkspaceScrollbars()
        if UI.frame:IsShown() then
            UI.frame:Raise()
            if not cancelled then UI:SetStatus("Window resized.", "success") end
        end
        UI:SetBinderResizeHover(CursorInside(UI.frame))
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, CompleteResize) else CompleteResize() end
    return true
end

function UI:RestoreWindowPosition()
    local settings = BindCardsDB and BindCardsDB.settings or {}
    if not self.frame or type(settings.windowX) ~= "number" or
        type(settings.windowY) ~= "number" then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", settings.windowX, settings.windowY)
    if self.frame.ClampToScreen then self.frame:ClampToScreen() end
end

-- Binder mode: the window around the pages is see-through, so let clicks
-- reach the world (camera, targeting). The header still moves the window.
function UI:ApplyWorkspacePassThrough(mode)
    if InCombat() then return end
    local binder = mode ~= "panel"
    local function Clicks(frame, enabled)
        if frame and frame.SetMouseClickEnabled then pcall(frame.SetMouseClickEnabled, frame, enabled) end
    end
    Clicks(self.frame, not binder)
    Clicks(self.workspaceScroll, not binder)
    self:UpdateWorkspaceWheel()
end

-- The workspace takes the mouse wheel only when there is something to
-- scroll; otherwise the wheel zooms the camera, like the rest of the world.
function UI:UpdateWorkspaceWheel()
    local scroll = self.workspaceScroll
    if not scroll or not scroll.EnableMouseWheel or InCombat() then return end
    local panel = BindCardsDB and BindCardsDB.settings and BindCardsDB.settings.workspaceMode == "panel"
    local range = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange() or 0
    pcall(scroll.EnableMouseWheel, scroll, panel or range > 0.5)
end

function UI:ApplyWorkspaceMode(mode, preserveSize)
    mode = mode == "panel" and "panel" or "binder"
    if mode ~= "panel" and self.entryPanel then
        self.entryInspectorDismissed = true
        self.entryPanel:Hide()
    end
    BindCardsDB = type(BindCardsDB) == "table" and BindCardsDB or {}
    BindCardsDB.settings = type(BindCardsDB.settings) == "table" and BindCardsDB.settings or {}
    BindCardsDB.settings.workspaceMode = mode
    if not self.centerPanel then return end
    self:ApplyWorkspacePassThrough(mode)
    if not preserveSize then
        local left, top = self.frame:GetLeft(), self.frame:GetTop()
        local panelMinimum = Helpers.PanelMinimumWidth and Helpers.PanelMinimumWidth() or 692
        if mode == "panel" and BindCardsDB.settings.windowManualSize then
            self.frame:SetSize(max(panelMinimum, BindCardsDB.settings.windowWidth or 820),
                BindCardsDB.settings.windowHeight or 520)
        elseif mode == "binder" and BindCardsDB.settings.binderManualSize then
            self.frame:SetSize(max(560, BindCardsDB.settings.binderWidth or 580), BindCardsDB.settings.binderHeight or 300)
        else
            self.frame:SetSize(mode == "panel" and 820 or 580, mode == "panel" and 520 or 300)
        end
        if left and top then
            self.frame:ClearAllPoints()
            self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end
    self.navPanel:SetShown(mode == "panel")
    self.rightPanel:SetShown(mode == "panel")
    self.frame:EnableMouse(mode == "panel")
    self.statusText:SetShown(mode == "panel")
    self.windowResizeGrip:SetShown(mode == "panel")
    self.centerPanel:ClearAllPoints()
    if mode == "panel" then
        self.panelShell:SetAlpha(1)
        self.panelShell:Show()
        self.frame:SetBackdropColor(0, 0, 0, 0)
        self.frame:SetBackdropBorderColor(0, 0, 0, 0)
        if self:IsEUITheme() and self.euiSkin and self.euiSkin.Panel then
            pcall(self.euiSkin.Panel, self.centerBackdrop, { inset = true })
        else
            Skin(self.centerBackdrop, C.paperAlt, C.faint)
        end
        self.centerBackdrop:Show()
        self.centerPanel:SetPoint("TOPLEFT", self.navPanel, "TOPRIGHT", 8, 0)
        self.centerPanel:SetPoint("BOTTOMRIGHT", -196, 35)
    else
        self.panelShell:SetAlpha(0)
        self.panelShell:Hide()
        self.centerBackdrop:Hide()
        self.frame:SetBackdropColor(0, 0, 0, 0)
        self.frame:SetBackdropBorderColor(0, 0, 0, 0)
        if self.centerPanel.SetBackdrop then self.centerPanel:SetBackdrop(nil) end
        self.centerPanel:SetPoint("TOPLEFT", 0, -55)
        self.centerPanel:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    if self.binderMode then
        Skin(self.binderMode, mode == "binder" and C.blueSoft or C.raised, mode == "binder" and C.blue or C.faint)
        Skin(self.panelMode, mode == "panel" and C.blueSoft or C.raised, mode == "panel" and C.blue or C.faint)
    end
    self:ApplySafeWindowBounds(false)
    self:Refresh()
end

function UI:CreateWorkspaceTile(view, index)
    local tile = CreateFrame("Button", nil, view.grid, "BackdropTemplate")
    tile.bindCardsEntryTile = true
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tile:RegisterForDrag("LeftButton")
    tile:EnableMouseWheel(true)
    tile:EnableKeyboard(false)
    tile.icon = tile:CreateTexture(nil, "ARTWORK")
    tile.icon:SetPoint("TOPLEFT", 3, -3); tile.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    tile.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    self.themeIcons[#self.themeIcons + 1] = { texture = tile.icon, parent = tile }
    if self.euiApplied and self.euiSkin and self.euiSkin.SquareIcon then pcall(self.euiSkin.SquareIcon, tile.icon, tile) end
    tile.wash = tile:CreateTexture(nil, "OVERLAY"); tile.wash:SetAllPoints(tile.icon); tile.wash:SetColorTexture(0.02, 0.03, 0.04, 0.38)
    tile.key = ShortcutLabel(tile, 20); tile.keySize = 20; tile.activeKeySize = tile.keySize * 0.75; tile.inactiveKeySize = tile.keySize * 0.75; tile.key:SetPoint("TOPRIGHT", -3, -2)
    tile.name = Font(tile, 8, C.text, "OUTLINE"); tile.name:SetPoint("BOTTOMLEFT", 3, 3); tile.name:SetPoint("BOTTOMRIGHT", -3, 3); tile.name:SetJustifyH("CENTER")
    tile.override = Font(tile, 7, C.muted, "OUTLINE"); tile.override:SetPoint("TOPLEFT", 3, -2); tile.override:SetText("OVR")
    ConfigureEntryTileCommon(tile)
    tile:SetScript("OnClick", function(self, button)
        if UI.suppressClick then return end
        if not self.entry then
            local payload = CursorPayload()
            if payload then UI:AddEntry(self.card, payload, self.index) else UI:ShowMacroDialog(self.card, nil, self.index, self) end
            return
        end
        if UI.quickBind then
            local key = MouseKey(button)
            if key then UI:SetEntryBinding(self.card, self.entry, key) end
        else
            UI.selectedCardID = CardID(self.card)
            local mode = BindCardsDB and BindCardsDB.settings and BindCardsDB.settings.workspaceMode or "binder"
            if button == "RightButton" and IsShiftKeyDown and IsShiftKeyDown() then
                UI:Confirm("Remove " .. EntryLabel(self.entry) .. "?", "Remove tile", function() UI:DeleteEntry(self.card, self.entry) end)
            elseif button == "RightButton" and (self.entry.kind == "spell" or self.entry.type == "spell") then
                UI:ShowSpellMenu(self, self.card, self.entry)
                -- RefreshWorkspace hides/reuses the owner and dismisses its menu.
                return
            elseif button == "RightButton" and (self.entry.kind == "macro" or self.entry.type == "macro") then
                UI:ShowMacroDialog(self.card, self.entry, nil, self)
            elseif mode == "panel" then
                UI:ShowEntryActions(self.card, self.entry, true)
                UI:RefreshNavigator(); UI:RefreshConditions(self.card); UI:RefreshWorkspace()
            else
                UI:BeginBindCapture(self.card, self.entry)
            end
            UI:RefreshWorkspace()
        end
    end)
    view.tiles[index] = tile
    return tile
end

function UI:CardMacroAction(card)
    local entry = self.focusedCardID == CardID(card) and self.focusedEntry or nil
    if entry and (entry.kind == "spell" or entry.type == "spell") then self:ShowSpellMacroDialog(card, entry)
    elseif entry and (entry.kind == "macro" or entry.type == "macro") then self:ShowMacroDialog(card, entry)
    else self:ShowMacroDialog(card) end
end

-- Addon-owned popup menus avoid Forever's native controller-focus bindings
-- (Blizzard's context menus run SmartNavigation under addon taint). The
-- build callback describes the entries like a Blizzard menu generator: titles,
-- buttons, dividers and nested buttons (rendered as submenus with "< Back").
-- Opening the menu again from the same owner closes it.
function UI:ShowMenu(owner, build)
    local menu = self.cardMenu
    if menu and menu:IsShown() and menu.owner == owner then menu:Hide(); return end
    if not menu then
        menu = CreateFrame("Frame", "BindCardsCardMenu", UIParent, "BackdropTemplate")
        self.cardMenu = menu
        menu:SetWidth(280)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        Skin(menu, C.panel, C.border)
        menu.rows = {}
        menu:RegisterEvent("GLOBAL_MOUSE_DOWN")
        menu:SetScript("OnEvent", function(self)
            if self:IsShown() and not CursorInside(self) and not CursorInside(self.owner) then self:Hide() end
        end)
        menu:SetScript("OnHide", function(self) self.owner = nil end)
        if UISpecialFrames then tinsert(UISpecialFrames, "BindCardsCardMenu") end
    end
    menu.owner = owner
    if not owner.bindCardsMenuHideHook then
        owner.bindCardsMenuHideHook = true
        owner:HookScript("OnHide", function()
            if menu.owner == owner then menu:Hide() end
        end)
    end
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(800)
    -- Keep the action descriptions separate from pooled buttons so callbacks
    -- always refer to the currently selected card, including submenus.
    local function Description()
        local description = {}
        function description:CreateButton(label, callback)
            local entry = Description()
            entry.label, entry.callback, entry.enabled = label, callback, true
            function entry:SetEnabled(enabled) self.enabled = enabled end
            self[#self + 1] = entry
            return entry
        end
        function description:CreateTitle(label)
            self:CreateButton(label):SetEnabled(false)
        end
        function description:CreateDivider() end
        return description
    end
    local root = Description()
    build(root)
    local function Render(entries, parent)
        for _, row in ipairs(menu.rows) do row:Hide() end
        local count = 0
        local function AddRow(label, enabled, callback)
            count = count + 1
            local row = menu.rows[count]
            if not row then
                row = Button(menu, "", 264, 26)
                menu.rows[count] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 8, -8 - (count - 1) * 30)
            row.label:SetText(label)
            row:SetEnabled(enabled)
            row:SetScript("OnClick", function() if enabled then callback() end end)
            row:SetFrameLevel(801)
            row:Show()
        end
        if parent then AddRow("< Back", true, function() Render(parent) end) end
        for _, entry in ipairs(entries) do
            AddRow(entry.label, entry.enabled, function()
                if #entry > 0 then
                    Render(entry, entries)
                elseif entry.callback then
                    menu:Hide()
                    entry.callback()
                end
            end)
        end
        menu:SetHeight(16 + count * 30)
    end
    Render(root)
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -6)
    menu:Show()
end

function UI:ShowCardMenu(owner, card)
    self:ShowMenu(owner, function(root)
        root:CreateTitle(CardName(card))
        local rename = root:CreateButton("Rename", function() UI:RenameCard(card) end)
        if IsFixedCard(card) and rename.SetEnabled then rename:SetEnabled(false) end
        root:CreateButton("New subcard", function() UI:AddCard(CardID(card)) end)
        local condition = card.condition or {}
        local supportsFormChildren = IsMainBinderRoot(card) or tonumber(condition.specGroup) ~= nil
        local formBinderId = supportsFormChildren and Call("GetCardBinderId", card) or nil
        local binderClass = type(formBinderId) == "string" and formBinderId:match("^class:(.+)$") or nil
        local formOptions = binderClass and (Call("GetFormOptions", binderClass) or {}) or {}
        if #formOptions > 0 then
            local formMenu = root:CreateButton("New form subcard")
            if formMenu and formMenu.CreateButton then
                for _, option in ipairs(formOptions) do
                    local formID = option.id
                    formMenu:CreateButton(option.label, function() UI:AddFormCard(card, formID) end)
                end
            end
        end
        -- Character card: add racials it lacks; replace it with another character's.
        if card.templateKey == "default:character" then
            root:CreateButton("Add racial abilities", function() UI:AddMissingRacials() end)
            local others = Call("GetOtherCharacterSets") or {}
            local copyMenu = root:CreateButton("Copy from…")
            if #others == 0 and copyMenu.SetEnabled then copyMenu:SetEnabled(false) end
            for _, other in ipairs(others) do
                local source = other
                copyMenu:CreateButton(tostring(source.name) .. " (" .. tostring(source.tiles or 0) .. ")",
                    function() UI:CopyCharacterFrom(source) end)
            end
        end
        if not ParentID(card) then
            local peeledChild = card.homeParentId ~= nil
            root:CreateButton(peeledChild and "Return card to stack" or
                (card.layoutMode == "floating" and "Return stack to binder" or "Detach stack"), function()
                Mutate("Card layout changed", function()
                    if peeledChild then
                        return UI:ReturnPeeledCard(card)
                    end
                    if IsMainBinderRoot(card) and card.layoutMode == "floating" then
                        return UI:ReturnBinderStack(card)
                    end
                    return Call("UpdateCard", CardID(card), {
                        layoutMode = card.layoutMode == "floating" and "stacked" or "floating",
                    }) ~= false
                end)
            end)
        elseif UI:CanPeelCard(card) then
            root:CreateButton("Take sheet out", function()
                local binderId = Call("GetCardBinderId", card)
                Mutate("Card detached", function()
                    return Call("UpdateCard", CardID(card), {
                        parentId = false,
                        homeParentId = ParentID(card),
                        binderId = binderId,
                        layoutMode = "floating",
                    }) ~= false
                end)
            end)
        end
        if not IsStandardCard(card) then
            root:CreateDivider()
            root:CreateButton("Delete card", function() UI:DeleteCard(card) end)
        end
    end)
end

function UI:ShowAddRuleMenu(owner, card)
    if IsFixedCard(card) then
        self:SetStatus("Default card rules are fixed.", "warning")
        return
    end
    self:ShowMenu(owner, function(root)
        root:CreateTitle("Add condition")
        local definitions = { { "content", "Content" } }
        local binderId = Call("GetCardBinderId", card)
        local binderClass = type(binderId) == "string" and binderId:match("^class:(.+)$") or nil
        if (ParentID(card) ~= nil or card.homeParentId ~= nil) and
            #(Call("GetFormOptions", binderClass) or {}) > 0 then
            definitions[#definitions + 1] = { "form", "Form" }
        end
        if binderClass then
            definitions[#definitions + 1] = { "spec", "Build" }
        end
        for _, definition in ipairs(definitions) do
            local key, label = definition[1], definition[2]
            root:CreateButton(label, function() UI:ShowConditionMenu(owner, card, key) end)
        end
    end)
end

function UI:ApplyTabHierarchy(tab, depth, mainRoot)
    depth = max(0, tonumber(depth) or 0)
    local metrics = Helpers.HierarchyTabMetrics and Helpers.HierarchyTabMetrics(depth, mainRoot) or
        (mainRoot and { width = 164, height = 34, iconSize = 16, fontSize = 12, indent = 0, gap = 4 } or
            (depth <= 1 and { width = 150, height = 30, iconSize = 14, fontSize = 10, indent = 0, gap = 4 } or
                (depth == 2 and { width = 136, height = 27, iconSize = 13, fontSize = 9, indent = 0, gap = 4 } or
                    { width = 122, height = 24, iconSize = 12, fontSize = 9, indent = 0, gap = 4 })))
    local width, height = metrics.width, metrics.height
    tab:SetSize(width, height)
    tab.icon:SetSize(metrics.iconSize, metrics.iconSize)
    tab.expand:SetSize(20, height)
    local fontPath, _, fontFlags = tab.label:GetFont()
    tab.label:SetFont(fontPath, metrics.fontSize, fontFlags or "")
    local countFontPath, _, countFontFlags = tab.count:GetFont()
    tab.count:SetFont(countFontPath, metrics.fontSize, countFontFlags or "")
    tab.count:SetWidth(32)
    tab.count:ClearAllPoints()
    tab.count:SetPoint("RIGHT", -24, 0)
    tab.label:ClearAllPoints()
    tab.label:SetPoint("LEFT", tab.icon, "RIGHT", mainRoot and 7 or 5, 0)
    tab.label:SetPoint("RIGHT", tab.count, "LEFT", -3, 0)
    return metrics
end

local function UTF8Prefix(text, characterCount)
    local byteIndex, characters, length = 1, 0, #text
    while byteIndex <= length and characters < characterCount do
        local value = string.byte(text, byteIndex)
        local size = value < 0x80 and 1 or (value < 0xE0 and 2 or (value < 0xF0 and 3 or 4))
        byteIndex = byteIndex + size
        characters = characters + 1
    end
    return string.sub(text, 1, byteIndex - 1)
end

local function EllipsizeLabel(label, text, maximumWidth)
    label:SetText(text)
    local width = label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth()
    if width <= maximumWidth then return end
    local length = strlenutf8 and strlenutf8(text) or #text
    local low, high, best = 0, length, "..."
    while low <= high do
        local middle = floor((low + high) / 2)
        local candidate = UTF8Prefix(text, middle) .. "..."
        label:SetText(candidate)
        local candidateWidth = label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth()
        if candidateWidth <= maximumWidth then
            best, low = candidate, middle + 1
        else
            high = middle - 1
        end
    end
    label:SetText(best)
end

function UI:FitTabToLabel(tab, metrics)
    local fullText = tab.label:GetText() or ""
    -- Ear width communicates hierarchy, so labels never resize one ear or the
    -- selected state. The count and arrow have their own reserved columns.
    local width = metrics.width
    tab:SetWidth(width)
    local left = tab.label:GetLeft()
    local right = tab.count:GetLeft()
    local maximumLabelWidth = left and right and max(20, right - left - 3) or
        max(20, width - tab.icon:GetWidth() - 61)
    EllipsizeLabel(tab.label, fullText, maximumLabelWidth)
    metrics.width = width
    return metrics
end

function UI:CreateWorkspaceCard(id)
    local view = CreateFrame("Button", nil, self.workspaceContent, "BackdropTemplate")
    view.bindCardsLegacyRole = "card"
    view.bindCardsCardSurface = true
    view:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    view:RegisterForDrag("LeftButton")
    view.shadow = view:CreateTexture(nil, "BACKGROUND")
    view.shadow:SetPoint("TOPLEFT", 3, -3); view.shadow:SetPoint("BOTTOMRIGHT", 3, -3); view.shadow:SetColorTexture(0, 0, 0, 0.22)
    view.tab = CreateFrame("Button", nil, view, "BackdropTemplate")
    view.tab.bindCardsCardSurface = true
    view.tab.bindCardsTopSurface = true
    view.tab:SetSize(140, 28); Skin(view.tab, C.paperAlt, C.faint)
    view.tab.icon = view.tab:CreateTexture(nil, "ARTWORK")
    view.tab.icon:SetSize(14, 14); view.tab.icon:SetPoint("LEFT", 5, 0)
    view.tab.Icon = view.tab.icon
    view.tab.activeMark = view.tab:CreateTexture(nil, "OVERLAY")
    view.tab.activeMark:SetWidth(3)
    view.tab.activeMark:SetPoint("TOPLEFT", 1, -1)
    view.tab.activeMark:SetPoint("BOTTOMLEFT", 1, 1)
    ThemeSolid(view.tab.activeMark, C.teal)
    view.tab.ThemeMark = view.tab.activeMark
    view.tab.activeMark:Hide()
    self.themeIcons[#self.themeIcons + 1] = { texture = view.tab.icon }
    self.themeButtons[#self.themeButtons + 1] = view.tab
    if self.euiApplied and self.euiSkin and self.euiSkin.Button then
        pcall(self.euiSkin.Button, view.tab, ButtonKeepKeys(view.tab))
        if self.euiSkin.TopSurface then pcall(self.euiSkin.TopSurface, view.tab) end
    end
    view.tab.label = Font(view.tab, 10, C.muted)
    view.tab.label:SetPoint("LEFT", 23, 0)
    if view.tab.label.SetWordWrap then view.tab.label:SetWordWrap(false) end
    if view.tab.label.SetMaxLines then view.tab.label:SetMaxLines(1) end
    view.tab.count = Font(view.tab, 10, C.muted)
    view.tab.count:SetJustifyH("RIGHT")
    view.tab.count:SetWidth(26); view.tab.count:SetPoint("RIGHT", -24, 0)
    view.tab.label:SetPoint("RIGHT", view.tab.count, "LEFT", -3, 0)
    view.tab.expand = CreateFrame("Button", nil, view.tab)
    view.tab.expand:SetSize(20, 28); view.tab.expand:SetPoint("RIGHT", -2, 0)
    view.tab.expand:RegisterForClicks("LeftButtonUp")
    if view.tab.expand.SetPropagateMouseClicks then view.tab.expand:SetPropagateMouseClicks(false) end
    view.tab.expand.lines = {}
    for index = 1, 2 do
        local line = view.tab.expand:CreateTexture(nil, "ARTWORK")
        line:SetSize(7, 1)
        view.tab.expand.lines[index] = line
    end
    view.tab.expand:Hide()
    view.tab.expand:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            UI.pendingCardDrag = nil
            UI:ArmCardExpandPress(view.tab.expand)
        end
    end)
    view.tab.expand:SetScript("OnHide", function()
        view.tab.expand.bindCardsPressSerial = nil
    end)
    view.tab.expand:SetScript("OnLeave", function()
        view.tab.expand.bindCardsPressSerial = nil
    end)
    view.tab.expand:SetScript("OnClick", function()
        local pressed = UI:ConsumeCardExpandPress(view.tab.expand)
        if UI.suppressClick or not view.card or not pressed then return end
        local expanded = view.card.treeExpanded == true
        if expanded then
            local groupRoot = view.tab.groupRoot or view.groupRoot
            local selectedID = groupRoot and UI.floatingSelection and
                UI.floatingSelection[CardID(groupRoot)] or UI.selectedCardID
            local collapsedSelection = Helpers.CollapsedSelection and Helpers.CollapsedSelection(
                selectedID, CardID(view.card), function(childID, parentID)
                    return UI:IsDescendant(childID, parentID)
                end) or selectedID
            if collapsedSelection ~= selectedID then
                if groupRoot and groupRoot.layoutMode == "floating" then
                    UI.floatingSelection[CardID(groupRoot)] = collapsedSelection
                else
                    UI:SetSelectedCardState(view.card)
                end
            end
        end
        Mutate(expanded and "Subcards folded" or "Subcards unfolded", function()
            return Call("UpdateCard", CardID(view.card), { treeExpanded = not expanded }) ~= false
        end)
    end)
    view.tab:RegisterForDrag("LeftButton")
    view.tab:EnableMouseWheel(true)
    view.tab:SetScript("OnMouseWheel", function(_, delta) UI:ScrollWorkspace(delta) end)
    view.tab:SetScript("OnClick", function()
        if UI.suppressClick then return end
        local groupRoot = view.tab.groupRoot
        if groupRoot and groupRoot.layoutMode == "floating" then
            UI:RaiseFloatingGroup(view.tab.moveView or view)
            UI.floatingSelection = UI.floatingSelection or {}
            UI.floatingSelection[CardID(groupRoot)] = CardID(view.card)
        end
        UI:SelectCard(view.card)
    end)
    view.tab:SetScript("OnEnter", function(self)
        UI:SetBinderResizeHover(true)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(CardName(view.card))
        local rootCard = view.tab.groupRoot or view.groupRoot or view.card
        local peelCard = UI:CanPeelCard(view.card)
        GameTooltip:AddLine(peelCard and "Drag out for temporary editing" or
            (rootCard.layoutMode == "floating" and "Drag to move or return stack" or "Drag to detach stack"), unpack(C.muted))
        GameTooltip:Show()
    end)
    view.tab:SetScript("OnLeave", function() GameTooltip:Hide(); UI:SetBinderResizeHover(false) end)
    view.tab:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or InCombat() then return end
        local rootCard = view.tab.groupRoot or view.groupRoot or view.card
        if UI:CanPeelCard(view.card) then rootCard = view.card end
        local selectedView = UI.cardViews and UI.cardViews[UI.selectedCardID]
        local moveView = rootCard == view.card and view or view.tab.moveView or
            (selectedView and selectedView.groupRoot == rootCard and selectedView) or view
        UI:ArmCardDrag(moveView, rootCard, view.tab, rootCard.layoutMode ~= "floating")
    end)
    view.tab:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then UI:ReleaseCardDrag() end
    end)
    view.tab:SetScript("OnDragStart", function()
        if InCombat() then UI:SetStatus("Cards cannot be detached during combat.", "warning"); return end
        local rootCard = view.tab.groupRoot or view.groupRoot or view.card
        if UI:CanPeelCard(view.card) then rootCard = view.card end
        local selectedView = UI.cardViews and UI.cardViews[UI.selectedCardID]
        local moveView = rootCard == view.card and view or view.tab.moveView or
            (selectedView and selectedView.groupRoot == rootCard and selectedView) or view
        UI:BeginCardDrag(moveView, rootCard.layoutMode ~= "floating", rootCard, view.tab)
    end)
    view.tab:SetScript("OnDragStop", function() UI:FinishCardDrag() end)
    view.connector = view:CreateTexture(nil, "BACKGROUND"); ThemeSolid(view.connector, C.faint)
    view.collapse = IconButton(view, "−", 21); view.collapse:SetPoint("TOPLEFT", 7, -7)
    view.collapse:RegisterForClicks("LeftButtonUp")
    if view.collapse.SetPropagateMouseClicks then view.collapse:SetPropagateMouseClicks(false) end
    view.collapse:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then UI.pendingCardDrag = nil end
    end)
    view.cardIcon = view:CreateTexture(nil, "ARTWORK"); view.cardIcon:SetSize(18, 18); view.cardIcon:SetPoint("LEFT", view.collapse, "RIGHT", 6, 0)
    self.themeIcons[#self.themeIcons + 1] = { texture = view.cardIcon }
    if self.euiApplied and self.euiSkin and self.euiSkin.SquareIcon then pcall(self.euiSkin.SquareIcon, view.cardIcon) end
    if self.euiApplied and self.euiSkin and self.euiSkin.SquareIcon then pcall(self.euiSkin.SquareIcon, view.tab.icon) end
    view.activeDot = view:CreateTexture(nil, "ARTWORK"); view.activeDot:SetSize(7, 7); view.activeDot:SetTexture(EDGE); view.activeDot:SetPoint("LEFT", view.cardIcon, "RIGHT", 5, 0)
    view.title = Font(view, 13, C.text); view.title:SetPoint("LEFT", view.activeDot, "RIGHT", 7, 0); view.title:SetWidth(170); view.title:SetWordWrap(false)
    view.state = Font(view, 8, C.muted); view.state:SetPoint("LEFT", view.title, "RIGHT", 8, 0)
    view.enable = Button(view, "", 28, 16); view.enable:SetPoint("LEFT", view.state, "RIGHT", 7, 0)
    -- Match Frame Gambit's compact, font-safe four-dot drag cue. Colons are
    -- present in every supported UI font, unlike the former Braille glyph.
    view.handle = Font(view, 10, C.muted)
    view.handle:SetSize(12, 18); view.handle:SetJustifyH("CENTER")
    view.handle:SetPoint("TOPRIGHT", -7, -6); view.handle:SetText("::")
    view.actions = Button(view, "•••", 31, 21); view.actions:SetPoint("RIGHT", view.handle, "LEFT", -6, 0)
    view.sub = IconButton(view, "+", 21); view.sub:SetPoint("RIGHT", view.handle, "LEFT", -8, 0)
    view.rename = IconButton(view, "✎", 21); view.rename:SetPoint("RIGHT", view.sub, "LEFT", -5, 0)
    view.macro = IconButton(view, "M", 21); view.macro:SetPoint("RIGHT", view.rename, "LEFT", -5, 0)
    view.delete = IconButton(view, "×", 21); view.delete:SetPoint("RIGHT", view.macro, "LEFT", -5, 0)
    view.more = IconButton(view, "+", 21); view.more:SetPoint("RIGHT", view.delete, "LEFT", -8, 0)
    view.columns = Button(view, "", 43, 21); view.columns:SetPoint("RIGHT", view.more, "LEFT", -6, 0)
    view.columns.label:SetFont(view.columns.label:GetFont(), 9, "")
    view.less = IconButton(view, "−", 21); view.less:SetPoint("RIGHT", view.columns, "LEFT", -6, 0)
    view.chips = {}
    for index, key in ipairs({ "class", "spec", "content", "form" }) do
        local chip = Button(view, "", 76, 16)
        chip.label:SetFont(chip.label:GetFont(), 8, "")
        chip:SetPoint("TOPLEFT", 8 + (index - 1) * 80, -35)
        chip:SetScript("OnClick", function()
            UI:SetSelectedCardState(view.card)
            UI:ShowConditionMenu(chip, view.card, key)
        end)
        view.chips[key] = chip
    end
    view.always = Font(view, 9, C.muted)
    view.always:SetPoint("TOPLEFT", 10, -39); view.always:SetText("Always")
    view.addRule = Button(view, "+ Rule", 50, 16)
    view.addRule.label:SetFont(view.addRule.label:GetFont(), 8, "")
    view.addRule:SetScript("OnClick", function() UI:ShowAddRuleMenu(view.addRule, view.card) end)
    view.overrideAll = Button(view, "GLOBAL PRIORITY: OFF", 116, 16)
    view.overrideAll.label:SetFont(view.overrideAll.label:GetFont(), 8, "")
    view.overrideAll:SetScript("OnClick", function()
        local card = view.card
        if not card or Call("CanCardUseGlobalPriority", card) ~= true then
            UI:SetStatus("Global priority is available on added General subcards.", "warning")
            return
        end
        Mutate(card.overrideAllBindingsWhenActive and "Normal priority restored" or
            "Global priority enabled", function()
            return Call("UpdateCard", CardID(card), {
                overrideAllBindingsWhenActive = card.overrideAllBindingsWhenActive ~= true,
            }) ~= false
        end)
    end)
    view.overrideAll:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText("Global priority")
        GameTooltip:AddLine("While this card is active, its assigned keys override Class, Build, and Form cards.",
            unpack(C.muted))
        GameTooltip:Show()
    end)
    view.overrideAll:SetScript("OnLeave", function() GameTooltip:Hide() end)
    view.rule = Divider(view); view.rule:SetPoint("TOPLEFT", 7, -55); view.rule:SetPoint("RIGHT", -7, 0)
    view.grid = CreateFrame("Frame", nil, view); view.grid:SetPoint("TOPLEFT", 8, -62); view.grid:SetPoint("RIGHT", -8, 0); view.grid:SetHeight(1)
    view.resizeGrip = CreateFrame("Button", nil, view, "BackdropTemplate")
    view.resizeGrip:SetSize(18, 18); Skin(view.resizeGrip, C.paperAlt, C.faint)
    view.resizeGrip:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    view.resizeGrip.lines = {}
    for index = 1, 3 do
        local line = view.resizeGrip:CreateTexture(nil, "OVERLAY")
        ThemeSolid(line, C.muted); line:SetSize(2 + index * 3, 1)
        line:SetPoint("BOTTOMRIGHT", -3, 2 + index * 3)
        view.resizeGrip.lines[index] = line
    end
    view.resizeBadge = Font(view, 9, C.text)
    view.resizeBadge:SetJustifyH("CENTER"); view.resizeBadge:SetSize(48, 18)
    view.resizeBadge:Hide()
    view.cropRight = Font(view, 9, C.amber, "OUTLINE")
    view.cropRight:SetJustifyH("CENTER"); view.cropRight:SetSize(34, 16); view.cropRight:Hide()
    view.cropDown = Font(view, 9, C.amber, "OUTLINE")
    view.cropDown:SetJustifyH("CENTER"); view.cropDown:SetSize(34, 16); view.cropDown:Hide()
    view.resizeGrip:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.teal)) end)
    view.resizeGrip:SetScript("OnLeave", function(self) if not UI.gridResize then self:SetBackdropBorderColor(unpack(C.faint)) end end)
    if view.resizeGrip.SetPropagateMouseClicks then view.resizeGrip:SetPropagateMouseClicks(false) end
    view.resizeGrip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        UI.pendingCardDrag = nil
        UI:BeginGridResize(view)
    end)
    view.paperResizeGrip = CreateFrame("Button", nil, view, "BackdropTemplate")
    view.paperResizeGrip:SetSize(16, 16)
    view.paperResizeGrip:SetFrameLevel(view:GetFrameLevel() + 12)
    Skin(view.paperResizeGrip, C.raised, C.blue)
    view.paperResizeGrip.resizeArt = AddResizeGripArt(view.paperResizeGrip)
    view.paperResizeGrip:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    if view.paperResizeGrip.SetPropagateMouseClicks then view.paperResizeGrip:SetPropagateMouseClicks(false) end
    view.paperResizeGrip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        UI.pendingCardDrag = nil
        UI:BeginCardResize(view)
    end)
    view.paperResizeGrip:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(C.teal))
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Resize card paper")
        GameTooltip:AddLine("The icon grid does not change.", unpack(C.muted))
        GameTooltip:Show()
    end)
    view.paperResizeGrip:SetScript("OnLeave", function(self)
        if not UI.cardResize then self:SetBackdropBorderColor(unpack(C.blue)) end
        GameTooltip:Hide()
    end)
    view.paperResizeGrip:Hide()
    view.paperGrid = {}
    view.tiles = {}
    view:SetScript("OnClick", function(self, button)
        if UI.suppressClick or button == "RightButton" then return end
        UI:SelectCard(self.card)
    end)
    view:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(UI.dragEntry and C.drop or
            (IsAmberNestedCard(self.card) and C.amber or C.blue)))
        UI:SetBinderResizeHover(true)
    end)
    view:SetScript("OnLeave", function(self)
        UI:SetBinderResizeHover(false)
        if UI.dragEntry then return end
        local selected = UI.selectedCardID == CardID(self.card)
        self:SetBackdropBorderColor(unpack(CardSelectionBorder(self.card, selected)))
    end)
    view:SetMovable(true)
    view:SetClampedToScreen(true)
    view:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or InCombat() then return end
        local rootCard = self.groupRoot or self.card
        if UI:CanPeelCard(self.card) then rootCard = self.card end
        UI:ArmCardDrag(self, rootCard, nil, rootCard and rootCard.layoutMode ~= "floating")
    end)
    view:SetScript("OnDragStart", function(self)
        if InCombat() then UI:SetStatus("Cards cannot be moved during combat.", "warning"); return end
        local rootCard = self.groupRoot or self.card
        local peel = UI:CanPeelCard(self.card)
        if peel then rootCard = self.card end
        if rootCard and (rootCard.layoutMode == "floating" or peel) then
            UI:BeginCardDrag(self, peel, rootCard, nil)
        end
    end)
    view:SetScript("OnDragStop", function()
        UI:ReleaseCardDrag()
    end)
    view:SetScript("OnMouseUp", function(self)
        UI:ReleaseCardDrag()
        if not UI.dragCard then return end
        local dragged = UI.dragCard; UI:CancelDrag(true)
        if dragged == self.card then return end
        Mutate("Card reordered", function() return Call("MoveCard", CardID(dragged), ParentID(dragged), self.card.order or 1) ~= false end)
    end)
    view.collapse:SetScript("OnClick", function()
        Mutate(view.card.collapsed and "Card expanded" or "Card collapsed", function()
            return Call("UpdateCard", CardID(view.card), { collapsed = not view.card.collapsed }) ~= false
        end)
    end)
    view.enable:SetScript("OnClick", function()
        if IsFixedCard(view.card) then
            UI:SetStatus("Default cards stay enabled.", "warning")
            return
        end
        Mutate(view.card.enabled == false and "Card enabled" or "Card disabled", function()
            return Call("UpdateCard", CardID(view.card), { enabled = view.card.enabled == false }) ~= false
        end)
    end)
    view.sub:SetScript("OnClick", function() UI:AddCard(CardID(view.card)) end)
    view.rename:SetScript("OnClick", function() UI:RenameCard(view.card) end)
    view.macro:SetScript("OnClick", function() UI:CardMacroAction(view.card) end)
    view.actions:SetScript("OnClick", function(self) UI:ShowCardMenu(self, view.card) end)
    view.delete:SetScript("OnClick", function() UI:DeleteCard(view.card) end)
    view.less:SetScript("OnClick", function() UI.selectedCardID = CardID(view.card); UI:SetColumns(-1) end)
    view.more:SetScript("OnClick", function() UI.selectedCardID = CardID(view.card); UI:SetColumns(1) end)
    view.columns:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    view.columns:SetScript("OnClick", function(_, button) UI:SetRows(view.card, button == "RightButton" and -1 or 1) end)
    view.columns:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Grid size")
        GameTooltip:AddLine("Left-click adds a row. Right-click removes one.", C.muted[1], C.muted[2], C.muted[3], true)
        GameTooltip:Show()
    end)
    view.columns:HookScript("OnLeave", function() GameTooltip:Hide() end)
    self.cardViews[id] = view
    return view
end

function UI:GetFloatingSheet(rootID, index)
    self.floatingSheets = self.floatingSheets or {}
    self.floatingSheets[rootID] = self.floatingSheets[rootID] or {}
    local sheet = self.floatingSheets[rootID][index]
    if sheet then return sheet end

    sheet = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    sheet.bindCardsLegacyRole = "sheet"
    Skin(sheet, C.paperAlt, C.border)
    sheet.shadow = sheet:CreateTexture(nil, "BACKGROUND")
    sheet.shadow:SetPoint("TOPLEFT", 3, -3)
    sheet.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    sheet.shadow:SetColorTexture(0, 0, 0, 0.22)
    sheet.edge = sheet:CreateTexture(nil, "BACKGROUND", nil, 1)
    sheet.edge:SetPoint("TOPLEFT", 1, -1)
    sheet.edge:SetPoint("TOPRIGHT", -1, -1)
    sheet.edge:SetHeight(14)
    ThemeSolid(sheet.edge, C.raised)
    sheet.nest = sheet:CreateTexture(nil, "ARTWORK")
    sheet.nest:SetSize(3, 11)
    sheet.nest:SetPoint("TOPLEFT", 3, -2)
    ThemeSolid(sheet.nest, C.teal)
    sheet.icon = sheet:CreateTexture(nil, "ARTWORK")
    sheet.icon:SetSize(10, 10)
    sheet.icon:SetPoint("TOPLEFT", 8, -3)
    sheet.label = Font(sheet, 8, C.muted, "OUTLINE")
    sheet.label:SetPoint("LEFT", sheet.icon, "RIGHT", 4, 0)
    sheet.label:SetPoint("RIGHT", -10, 0)
    sheet:SetScript("OnClick", function(self)
        if UI.suppressClick or not self.card then return end
        if self.moveView then UI:RaiseFloatingGroup(self.moveView) end
        UI.floatingSelection = UI.floatingSelection or {}
        UI.floatingSelection[self.rootID] = CardID(self.card)
        UI:SelectCard(self.card)
    end)
    sheet:SetScript("OnEnter", function(self)
        if not self.card then return end
        if self.restingAlpha then self:SetAlpha(min(1, self.restingAlpha + 0.14)) end
        self.label:SetTextColor(unpack(C.text))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(CardName(self.card))
        GameTooltip:Show()
    end)
    sheet:SetScript("OnLeave", function(self)
        if self.restingAlpha then self:SetAlpha(self.restingAlpha) end
        self.label:SetTextColor(unpack(C.muted))
        GameTooltip:Hide()
    end)
    self.floatingSheets[rootID][index] = sheet
    return sheet
end

function UI:ResetWorkspaceViewAttachments()
    -- Floating ears are reparented to the visible page in their stack. Break
    -- those cross-view anchors before any page is returned to workspaceContent;
    -- otherwise WoW can reject the new page anchor as an anchor-family cycle.
    for _, view in pairs(self.cardViews or {}) do
        view:Hide()
        if view.tab then view.tab:Hide() end
    end
    for _, view in pairs(self.cardViews or {}) do
        local tab = view.tab
        if tab then
            tab:ClearAllPoints()
            tab:SetParent(UIParent)
            tab.groupRoot, tab.moveView = nil, nil
            tab.bindCardsFloatingOwner = nil
        end
    end
    for _, sheets in pairs(self.floatingSheets or {}) do
        for _, sheet in ipairs(sheets) do
            sheet:Hide()
            sheet:ClearAllPoints()
            sheet.card, sheet.moveView = nil, nil
        end
    end
    -- Pages can still belong to the floating anchor family after their ears
    -- are released. Clear them before rebuilding tabs or changing parents;
    -- SetParent must never carry a screen anchor into the scroll-child family.
    for _, view in pairs(self.cardViews or {}) do
        view:ClearAllPoints()
    end
end

local function DrawPaperGrid(view, width, height, step, shown)
    local geometryKey = table.concat({ width, height, step, shown and 1 or 0 }, ":")
    if view.paperGridGeometryKey == geometryKey then return end
    view.paperGridGeometryKey = geometryKey
    for _, line in ipairs(view.paperGrid) do line:Hide() end
    if not shown then return end
    local index = 0
    for x = step, width - 1, step do
        index = index + 1
        local line = view.paperGrid[index] or view:CreateTexture(nil, "BACKGROUND")
        view.paperGrid[index] = line
        line:ClearAllPoints(); line:SetPoint("TOPLEFT", 8 + x, -62); line:SetHeight(height)
        line:SetWidth(1); line:SetColorTexture(0.32, 0.36, 0.41, 0.055); line:Show()
    end
    for y = step, height - 1, step do
        index = index + 1
        local line = view.paperGrid[index] or view:CreateTexture(nil, "BACKGROUND")
        view.paperGrid[index] = line
        line:ClearAllPoints(); line:SetPoint("TOPLEFT", 8, -62 - y); line:SetWidth(width)
        line:SetHeight(1); line:SetColorTexture(0.32, 0.36, 0.41, 0.055); line:Show()
    end
end

function UI:RefreshWorkspace()
    if not self.workspaceContent then return end
    self:ResetWorkspaceViewAttachments()
    if not self.frame or not self.frame:IsShown() then return end
    if not self.binderSheets then
        self.binderSheets = {}
        for index = 1, 6 do
            local sheet = CreateFrame("Button", nil, self.workspaceContent, "BackdropTemplate")
            sheet.bindCardsLegacyRole = "sheet"
            Skin(sheet, C.paperAlt, C.border)
            sheet.edge = sheet:CreateTexture(nil, "BACKGROUND", nil, 1)
            sheet.edge:SetPoint("TOPLEFT", 1, -1); sheet.edge:SetPoint("TOPRIGHT", -1, -1)
            sheet.edge:SetHeight(14); ThemeSolid(sheet.edge, C.raised)
            sheet.nest = sheet:CreateTexture(nil, "ARTWORK")
            sheet.nest:SetSize(3, 11); sheet.nest:SetPoint("TOPLEFT", 3, -2)
            ThemeSolid(sheet.nest, C.teal); sheet.nest:Hide()
            sheet.icon = sheet:CreateTexture(nil, "ARTWORK")
            sheet.icon:SetSize(10, 10); sheet.icon:SetPoint("TOPLEFT", 8, -3)
            sheet.label = Font(sheet, 8, C.muted, "OUTLINE")
            sheet.label:SetPoint("LEFT", sheet.icon, "RIGHT", 4, 0)
            -- The sheet body lets the mouse through to the world (camera,
            -- clicks); only its top strip selects the card behind.
            sheet:EnableMouse(false)
            sheet.hit = CreateFrame("Button", nil, sheet)
            sheet.hit:SetPoint("TOPLEFT"); sheet.hit:SetPoint("TOPRIGHT"); sheet.hit:SetHeight(18)
            sheet.hit:SetScript("OnClick", function(self)
                local owner = self:GetParent()
                if UI.suppressClick or not owner.card then return end
                UI:SelectCard(owner.card)
            end)
            sheet.hit:SetScript("OnEnter", function(self)
                local owner = self:GetParent()
                if not owner.card then return end
                if owner.restingAlpha then owner:SetAlpha(min(1, owner.restingAlpha + 0.14)) end
                owner.label:SetTextColor(unpack(C.text))
                GameTooltip:SetOwner(owner, "ANCHOR_TOP")
                GameTooltip:SetText(CardName(owner.card))
                GameTooltip:Show()
            end)
            sheet.hit:SetScript("OnLeave", function(self)
                local owner = self:GetParent()
                if owner.restingAlpha then owner:SetAlpha(owner.restingAlpha) end
                owner.label:SetTextColor(unpack(C.muted))
                GameTooltip:Hide()
            end)
            self.binderSheets[index] = sheet
        end
    end
    for _, sheet in ipairs(self.binderSheets) do
        sheet.bindCardsBinderCoverKey = nil
        sheet:Hide()
    end
    local allCards = GetCards()
    local selectedCard, binderKey, binderModel = self:EnsureBinderSelection()
    local visibleCards = {}
    for _, card in ipairs(binderModel.general.cards) do visibleCards[#visibleCards + 1] = card end
    for _, card in ipairs(binderModel.class.cards) do visibleCards[#visibleCards + 1] = card end
    for _, card in ipairs(binderModel.character and binderModel.character.cards or {}) do
        visibleCards[#visibleCards + 1] = card
    end
    local flat = FlattenCards(visibleCards)
    local binderFlat = FlattenCards(binderModel[binderKey].cards)
    local binderMembers = {}
    local depthByID = {}
    for _, info in ipairs(flat) do depthByID[CardID(info.card)] = info.depth end
    for _, info in ipairs(binderFlat) do binderMembers[CardID(info.card)] = true end
    local settings = BindCardsDB and BindCardsDB.settings or {}
    local mode = settings.workspaceMode == "panel" and "panel" or "binder"
    local iconSize = min(48, max(24, tonumber(settings.iconSize) or 36))
    local selectedColumns = selectedCard and min(12, max(3, tonumber(selectedCard.columns) or 6)) or 6
    local selectedCapacity = selectedCard and
        max(selectedColumns, tonumber(selectedCard.capacity) or selectedColumns * 2) or selectedColumns * 2
    local widestColumns = selectedColumns
    local earlyCardsByID = {}
    for _, card in ipairs(binderModel[binderKey].cards) do earlyCardsByID[CardID(card)] = card end
    local function EarlyRoot(card)
        local cursor, seen = card, {}
        while cursor and ParentID(cursor) and earlyCardsByID[ParentID(cursor)] and not seen[CardID(cursor)] do
            seen[CardID(cursor)] = true
            cursor = earlyCardsByID[ParentID(cursor)]
        end
        return cursor or card
    end
    for _, info in ipairs(binderFlat) do
        local root = EarlyRoot(info.card)
        if root.layoutMode ~= "floating" and self.peelingCardID ~= CardID(root) then
            widestColumns = max(widestColumns, min(12, max(3, tonumber(info.card.columns) or 6)))
        end
    end
    local intrinsicPageWidth = widestColumns * (iconSize + 6) - 6 + 16
    local intrinsicSelectedPageWidth = selectedColumns * (iconSize + 6) - 6 + 16
    local generalNaturalWidth = Helpers.GeneralPageFootprint and
        Helpers.GeneralPageFootprint(selectedColumns, selectedCapacity, iconSize) or intrinsicSelectedPageWidth
    local requestedBinderRailWidth = Helpers.HierarchyEarRailWidth and Helpers.HierarchyEarRailWidth() or 170
    for _, info in ipairs(binderFlat) do
        local mainRoot = IsMainBinderRoot(info.card)
        if mainRoot then
            local required = math.ceil(#CardName(info.card) * 7.5) + 62
            requestedBinderRailWidth = max(requestedBinderRailWidth, min(220, required))
        end
    end
    local viewportWidth = max(300, self.workspaceScroll:GetWidth() - 2)
    local binderRailWidth = min(requestedBinderRailWidth, max(154, viewportWidth - 300))
    self.binderRailWidth = binderRailWidth
    -- Binders cascade left to right: General, class, then the character card.
    local hierarchyLaneSpace = (binderModel.character and binderModel.character.root) and 80 or 40
    if mode == "binder" and self.frame and not self.dragSession and not self.windowResizing and
        not self.cardResize and
        not self.profileSwitchGeometry and not settings.binderManualSize then
        local _, _, safeMaximumWidth = self:GetSafeWindowBounds()
        local autoPageWidth = binderKey == "general" and generalNaturalWidth or intrinsicPageWidth
        local desiredWidth = min(safeMaximumWidth,
            max(560, min(720, autoPageWidth) + binderRailWidth + hierarchyLaneSpace))
        if math.abs(self.frame:GetWidth() - desiredWidth) > 0.5 then self.frame:SetWidth(desiredWidth) end
        -- Resizing the shell changes its anchored viewport immediately. Lay
        -- out this pass against that width, not the previous binder's width.
        viewportWidth = max(300, self.workspaceScroll:GetWidth() - 2)
        binderRailWidth = min(requestedBinderRailWidth, max(154, viewportWidth - 300))
        self.binderRailWidth = binderRailWidth
    end
    local hasDockedBinderCard = false
    for _, info in ipairs(binderFlat) do
        if info.depth == 0 and info.card.layoutMode ~= "floating" and
            self.peelingCardID ~= CardID(info.card) then
            hasDockedBinderCard = true
            break
        end
    end
    self.hasDockedBinderCard = hasDockedBinderCard
    local contentWidth = viewportWidth
    local laneSpace = mode == "binder" and hierarchyLaneSpace or 0
    local availablePageWidth = min(720, max(300,
        contentWidth - (mode == "binder" and binderRailWidth or 10) - laneSpace))
    local automaticFrontPageWidth = mode == "binder" and Helpers.DockedPageWidth and
        Helpers.DockedPageWidth(binderKey, availablePageWidth, intrinsicSelectedPageWidth,
            selectedColumns, selectedCapacity, iconSize) or availablePageWidth
    local selectedCardResize = self.cardResize and self.cardResize.card == selectedCard and self.cardResize or nil
    local requestedFrontPageWidth = selectedCardResize and selectedCardResize.width or
        (selectedCard and tonumber(selectedCard.paperWidth) or nil)
    local frontPageWidth = requestedFrontPageWidth and
        min(availablePageWidth, max(300, requestedFrontPageWidth)) or automaticFrontPageWidth
    self.frontPageWidth = frontPageWidth
    self.workspaceContent:SetWidth(contentWidth)
    local winners = BindCards.lastCompiledBindings or Call("CompileBindings") or {}
    local selectedID = CardID(selectedCard)
    local frontCard, frontID = selectedCard, selectedID
    local cardsByID = {}
    for _, card in ipairs(allCards) do cardsByID[CardID(card)] = card end
    local function RootCard(card)
        local cursor, seen = card, {}
        while cursor and ParentID(cursor) and not seen[CardID(cursor)] do
            seen[CardID(cursor)] = true
            cursor = cardsByID[ParentID(cursor)]
        end
        return cursor or card
    end
    local function RootIsFloating(root)
        return mode == "binder" and root and
            (root.layoutMode == "floating" or self.peelingCardID == CardID(root))
    end
    if frontCard and RootIsFloating(RootCard(frontCard)) then
        for _, info in ipairs(binderFlat) do
            local candidateRoot = RootCard(info.card)
            if info.depth == 0 and not RootIsFloating(candidateRoot) then
                frontCard, frontID = info.card, CardID(info.card)
                break
            end
        end
    end
    -- Every other docked binder shows as a silhouette behind the open one,
    -- in cascade order (General, class, character), each in its own lane.
    local binderCovers = {}
    local selectedRoot = binderModel[binderKey] and binderModel[binderKey].root
    if mode == "binder" and selectedRoot and not RootIsFloating(selectedRoot) then
        for _, key in ipairs({ "general", "class", "character" }) do
            local root = key ~= binderKey and binderModel[key] and binderModel[key].root
            if root and #binderModel[key].cards > 0 and not RootIsFloating(root) then
                local coverCard = root
                local remembered = self.selectedCardByBinder and self:FindCard(self.selectedCardByBinder[key])
                if remembered and RootCard(remembered) == root then coverCard = remembered end
                binderCovers[#binderCovers + 1] = { card = coverCard, root = root, binderCover = true, binderKey = key }
            end
        end
    end
    local maximumAncestors = MAX_HIERARCHY_SHEETS - #binderCovers
    local ancestors = Helpers.HierarchyAncestors and
        Helpers.HierarchyAncestors(frontCard, cardsByID, CardID, ParentID, maximumAncestors) or {}
    local selectedPathIDs = {}
    if frontID then selectedPathIDs[frontID] = true end
    for _, ancestor in ipairs(ancestors) do selectedPathIDs[CardID(ancestor)] = true end
    local pageLayers = {}
    if mode == "binder" then
        for _, cover in ipairs(binderCovers) do pageLayers[#pageLayers + 1] = cover end
        local dockedAncestors = {}
        for _, ancestor in ipairs(ancestors) do
            if not RootIsFloating(RootCard(ancestor)) then
                dockedAncestors[#dockedAncestors + 1] = ancestor
            end
        end
        for _, ancestor in ipairs(dockedAncestors) do
            pageLayers[#pageLayers + 1] = { card = ancestor, ancestor = true }
        end
    end
    local pageStackCount = mode == "binder" and #pageLayers or 0
    local generalLaneX, classLaneX, characterLaneX = 5, 45, 85
    local selectedLaneX = Helpers.WorkspaceLaneX and Helpers.WorkspaceLaneX(mode, binderKey) or
        (mode == "panel" and generalLaneX or (binderKey == "class" and classLaneX or
            (binderKey == "character" and characterLaneX or generalLaneX)))
    local selectedDepth = min(3, depthByID[frontID] or 0)
    local selectedGeometry = Helpers.HierarchySheetGeometry and
        Helpers.HierarchySheetGeometry(selectedDepth, selectedDepth, frontPageWidth, selectedLaneX) or
        { x = selectedLaneX + selectedDepth * 16, width = frontPageWidth }
    selectedGeometry.right = selectedGeometry.right or (selectedGeometry.x + selectedGeometry.width)
    local earAnchorX = selectedGeometry.right - 1
    local frontPageOffsetY = 0
    for _, layer in ipairs(pageLayers) do
        if not layer.binderCover then frontPageOffsetY = frontPageOffsetY + 18 end
    end
    local function NaturalPageHeight(card, pageWidth, pageBinderKey)
        return CardPageHeight(card, pageWidth or frontPageWidth, iconSize,
            pageBinderKey or self:GetBinderKeyForCard(card))
    end
    local layerGeometry = {}
    local activeLayerY = 5
    local selectedPageHeight = frontCard and NaturalPageHeight(frontCard) or 200
    local selectedPageY = 5 + frontPageOffsetY
    for index, layer in ipairs(pageLayers) do
        local geometry
        if layer.binderCover then
            local coverLaneX = layer.binderKey == "class" and classLaneX or
                (layer.binderKey == "character" and characterLaneX or generalLaneX)
            local coverColumns = min(12, max(3, tonumber(layer.card and layer.card.columns) or 6))
            local coverCapacity = max(coverColumns,
                tonumber(layer.card and layer.card.capacity) or coverColumns * 2)
            local coverIntrinsicWidth = coverColumns * (iconSize + 6) - 6 + 16
            -- The backing binder keeps its natural width and visible silhouette.
            local coverWidth = Helpers.DockedPageWidth and
                Helpers.DockedPageWidth(layer.binderKey, availablePageWidth, coverIntrinsicWidth,
                    coverColumns, coverCapacity, iconSize) or
                availablePageWidth
            local coverDepth = min(3, depthByID[CardID(layer.card)] or 0)
            local naturalHeight = NaturalPageHeight(layer.card, coverWidth, layer.binderKey)
            -- Silhouettes must stick out of the open page (pages are slightly
            -- see-through, so edges hidden under it show as stray lines).
            -- Binders further right in the cascade protrude on the right,
            -- and no silhouette ends above the open page's bottom.
            if coverLaneX > selectedLaneX then coverWidth = max(coverWidth, frontPageWidth) end
            local coverHeight = Helpers.HierarchyCoverHeight and
                Helpers.HierarchyCoverHeight(naturalHeight, coverDepth) or
                (naturalHeight + coverDepth * 18 + 8)
            coverHeight = max(coverHeight, selectedPageY - 5 + selectedPageHeight + 8)
            geometry = {
                x = coverLaneX,
                y = 5,
                width = coverWidth,
                height = coverHeight,
            }
        else
            local layerDepth = min(3, depthByID[CardID(layer.card)] or 0)
            geometry = Helpers.HierarchySheetGeometry and
                Helpers.HierarchySheetGeometry(layerDepth, selectedDepth, frontPageWidth, selectedLaneX) or {
                    x = selectedLaneX + layerDepth * 16,
                    width = frontPageWidth + max(0, selectedDepth - layerDepth) * 16,
                }
            geometry.y = activeLayerY
            geometry.height = selectedPageHeight + max(0, selectedPageY - activeLayerY) + 8
            activeLayerY = activeLayerY + 18
        end
        layerGeometry[index] = geometry
    end
    local childCount = {}
    for _, info in ipairs(flat) do
        local parentID = ParentID(info.card)
        if parentID then childCount[parentID] = (childCount[parentID] or 0) + 1 end
    end
    local function AncestorsExpanded(card)
        local parentID, seen = ParentID(card), {}
        while parentID and not seen[parentID] do
            seen[parentID] = true
            local parent = cardsByID[parentID]
            if not parent or parent.treeExpanded ~= true then return false end
            parentID = ParentID(parent)
        end
        return true
    end
    self.floatingSelection = self.floatingSelection or {}
    local floatingPageID = {}
    for _, info in ipairs(flat) do
        local root = RootCard(info.card)
        if RootIsFloating(root) and not floatingPageID[CardID(root)] then
            local wantedID = self.floatingSelection[CardID(root)]
            local wanted = wantedID and cardsByID[wantedID]
            if not wanted or RootCard(wanted) ~= root or (wanted ~= root and not AncestorsExpanded(wanted)) then
                wanted = root
                self.floatingSelection[CardID(root)] = CardID(root)
            end
            floatingPageID[CardID(root)] = CardID(wanted)
        end
    end
    local tabY, pageHeight = 7, 1
    local lastTabKindByParent = {}
    local selectedView
    local floatingGroups = {}
    for _, info in ipairs(flat) do
        local card = info.card
        local rootCard = RootCard(card)
        local rootID = CardID(rootCard)
        local view = self.cardViews[CardID(card)] or self:CreateWorkspaceCard(CardID(card))
        local resizeState = self.gridResize and self.gridResize.card == card and self.gridResize or nil
        local paperResizeState = self.cardResize and self.cardResize.card == card and self.cardResize or nil
        local columns = resizeState and resizeState.columns or min(12, max(3, tonumber(card.columns) or 6))
        local entryList = Entries(card)
        local capacity = resizeState and (resizeState.columns * resizeState.rows) or max(columns, tonumber(card.capacity) or columns * 2)
        local slots = capacity
        local rows = math.ceil(slots / columns)
        local entries, croppedRight, croppedDown = EntriesBySlot(card, columns, rows)
        local rootFloating = RootIsFloating(rootCard)
        local floating = rootFloating and floatingPageID[rootID] == CardID(card)
        local selected = not rootFloating and frontID == CardID(card)
        local active = IsCardActive(card)
        view.card, view.depth, view.groupRoot = card, info.depth, rootCard
        -- The General/Class roots are binder covers; descendants remain pages.
        view.bindCardsLegacyRole = IsMainBinderRoot(card) and "cover" or "card"
        view.tab.bindCardsCard = card

        local showBinderTab = mode == "binder" and binderMembers[CardID(card)] and not rootFloating and
            (info.depth == 0 or AncestorsExpanded(card))
        if showBinderTab then
            if info.depth == 0 and tabY > 7 then tabY = tabY + 6 end
            local parentKey = ParentID(card) or ("root:" .. rootID)
            local tabKind = IsMutuallyExclusiveSheet(card) and "exclusive" or
                (IsMainBinderRoot(card) and "root" or "custom")
            if tabKind == "custom" and lastTabKindByParent[parentKey] == "exclusive" then
                tabY = tabY + 6
            end
            lastTabKindByParent[parentKey] = tabKind
            local mainRoot = IsMainBinderRoot(card)
            local metrics = self:ApplyTabHierarchy(view.tab, info.depth, mainRoot)
            -- ApplyDockedEarLayer hosts tabs on the editor, outside the scroll
            -- clipping rectangle; their anchors still follow the workspace.
            if view.tab.SetClipsChildren then view.tab:SetClipsChildren(false) end
            view.tab.groupRoot, view.tab.moveView = nil, nil
            view.tab.bindCardsFloatingOwner = nil
            -- All labels must receive clicks above the DIALOG workspace. The
            -- selected label remains above its siblings within that tab band.
            self:ApplyDockedEarLayer(view.tab, selected)
            view.tab.label:SetText(CardName(card))
            view.tab.count:SetText("· " .. #entryList)
            metrics = self:FitTabToLabel(view.tab, metrics)
            local tabLift = selected and 2 or 0
            view.tab:ClearAllPoints()
            view.tab:SetPoint("TOPLEFT", self.workspaceContent, "TOPLEFT", earAnchorX, -tabY + tabLift)
            local onSelectedPath = selectedPathIDs[CardID(card)] == true
            local emphasized = selected or active or onSelectedPath
            local amberNested = IsAmberNestedCard(card)
            local selectedAccent = amberNested and C.amber or C.blue
            local pathAccent = amberNested and C.amber or C.teal
            local tabTextColor = amberNested and C.amber or
                (selected and C.blue or ((active or onSelectedPath) and C.text or C.muted))
            if self.useTopSurfaceText then tabTextColor = C.topText end
            view.tab.label:SetTextColor(unpack(tabTextColor))
            view.tab.count:SetTextColor(unpack(tabTextColor))
            local hasChildren = (childCount[CardID(card)] or 0) > 0
            local childrenVisible = hasChildren and card.treeExpanded == true
            local lineColor = selected and selectedAccent or (amberNested and C.amber or C.muted)
            local first, second = view.tab.expand.lines[1], view.tab.expand.lines[2]
            first:ClearAllPoints(); second:ClearAllPoints()
            first:SetColorTexture(lineColor[1], lineColor[2], lineColor[3], selected and 1 or 0.75)
            second:SetColorTexture(lineColor[1], lineColor[2], lineColor[3], selected and 1 or 0.75)
            if childrenVisible then
                first:SetPoint("CENTER", -2, 0); first:SetRotation(-math.pi / 4)
                second:SetPoint("CENTER", 2, 0); second:SetRotation(math.pi / 4)
            else
                first:SetPoint("CENTER", 0, 2); first:SetRotation(-math.pi / 4)
                second:SetPoint("CENTER", 0, -2); second:SetRotation(math.pi / 4)
            end
            view.tab.expand:SetShown(hasChildren)
            ApplyCardIcon(view.tab.icon, card)
            view.tab.icon:SetDesaturated(not emphasized)
            view.tab.icon:SetAlpha(emphasized and 1 or 0.42)
            Color(view.tab.activeMark, selected and selectedAccent or pathAccent)
            view.tab.activeMark:SetShown(active)
            Skin(view.tab, CardSurface(emphasized and C.raised or C.paperAlt,
                    card, amberNested and 0.045 or 0.024),
                amberNested and C.amber or
                (selected and C.blue or ((active or onSelectedPath) and C.teal or C.faint)))
            view.tab:SetAlpha(card.enabled == false and 0.30 or
                (selected and 1 or (onSelectedPath and 0.84 or (active and 0.76 or 0.48))))
            self:StyleAppearanceTab(view.tab, selected, active or onSelectedPath, card.enabled == false)
            view.tab:Show()
            tabY = tabY + metrics.height + metrics.gap
        end

        if floating or selected then
            local hierarchyX = mode == "panel" and 0 or min(3, tonumber(info.depth) or 0) * 16
            local pageX = selectedLaneX + hierarchyX
            local requestedPaperWidth = paperResizeState and paperResizeState.width or
                tonumber(card.paperWidth)
            local viewWidth = floating and min(720, requestedPaperWidth or rootCard.floatWidth or 430) or frontPageWidth
            local cardIconSize = min(iconSize, max(18, floor((viewWidth - 16 - (columns - 1) * 6) / columns)))
            local gridStep = cardIconSize + 6
            local gridWidth = columns * gridStep - 6
            local gridHeight = rows * gridStep - 6
            local naturalHeight = card.collapsed and 35 or (78 + gridHeight)
            local requestedPaperHeight = paperResizeState and paperResizeState.height or
                tonumber(card.paperHeight)
            local height = card.collapsed and 35 or max(naturalHeight, requestedPaperHeight or naturalHeight)
            if floating then
                view:SetParent(UIParent); view:SetFrameStrata("DIALOG"); view:SetFrameLevel(40)
                view:SetScale(self.frame:GetEffectiveScale() / UIParent:GetEffectiveScale())
                view:SetSize(viewWidth, height)
                view:ClearAllPoints()
                local positionState = paperResizeState or resizeState
                if positionState and positionState.viewLeft and positionState.viewTop then
                    view:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", positionState.viewLeft, positionState.viewTop)
                else
                    local coordinateScale = view:GetEffectiveScale() / UIParent:GetEffectiveScale()
                    local rootHeight = CardPageHeight(rootCard, viewWidth, iconSize)
                    local floatingHierarchyX = min(3, tonumber(info.depth) or 0) * 16
                    view:SetPoint("TOPLEFT", UIParent, "CENTER",
                        (rootCard.floatX or 0) - viewWidth * coordinateScale / 2 + floatingHierarchyX * coordinateScale,
                        (rootCard.floatY or 0) + rootHeight * coordinateScale / 2)
                end
                floatingGroups[rootID] = {
                    root = rootCard,
                    view = view,
                    pageID = CardID(card),
                    width = viewWidth,
                }
            else
                view:SetParent(self.workspaceContent); view:SetFrameStrata("DIALOG"); view:SetFrameLevel(self.workspaceContent:GetFrameLevel() + 5)
                view:SetScale(1)
                view:SetSize(viewWidth, height)
                view:ClearAllPoints(); view:SetPoint("TOPLEFT", self.workspaceContent, "TOPLEFT", pageX, -5 - frontPageOffsetY)
                selectedView = view
                pageHeight = max(pageHeight, height + 22 + frontPageOffsetY)
            end
            if mode == "panel" and not floating then
                view.tab:Hide()
            end
            -- Card tabs now live in the top rail; the old mid-edge stub
            -- connected to nothing and showed as a stray line.
            view.connector:Hide()
            local mainRoot = IsMainBinderRoot(card)
            local headerIconSize = mainRoot and 18 or (info.depth <= 1 and 16 or 14)
            local headerFontSize = mainRoot and 13 or (info.depth <= 1 and 12 or 11)
            local titleFont, _, titleFlags = view.title:GetFont()
            view.title:SetFont(titleFont, headerFontSize, titleFlags or "")
            view.cardIcon:SetSize(headerIconSize, headerIconSize)
            local activeDotSize = mainRoot and 7 or (info.depth <= 1 and 6 or 5)
            view.activeDot:SetSize(activeDotSize, activeDotSize)
            view.title:SetText(CardName(card)); view.columns.label:SetText(columns .. "×" .. rows)
            view.title:SetTextColor(unpack(IsAmberNestedCard(card) and C.amber or C.text))
            ApplyCardIcon(view.cardIcon, card)
            Color(view.activeDot, active and C.teal or C.muted, active and 1 or 0.42)
            local stateText = card.enabled == false and "Disabled" or (active and "Active" or "No match")
            if card.overrideAllBindingsWhenActive then stateText = stateText .. " · Priority" end
            view.state:SetText(stateText)
            view.state:SetTextColor(unpack(card.overrideAllBindingsWhenActive and C.amber or
                (active and C.teal or C.muted)))
            view.enable.label:SetText(card.enabled == false and "OFF" or "ON")
            view.enable:SetShown(not IsFixedCard(card))
            view.collapse.label:SetText(card.collapsed and "+" or "−")
            local condition = card.condition or {}
            local specName = condition.specGroup == 1 and "Primary" or "Secondary"
            local chipValues = {
                class = condition.class and ("Class · " .. Friendly(condition.class)) or "Any class",
                spec = condition.specGroup and ("Build · " .. specName) or "Any build",
                content = condition.content and condition.content ~= "ANY" and ("Content · " .. Friendly(condition.content)) or "Any content",
                form = condition.form and ("Form · " .. ((BindCards.FORM_DEFINITIONS[condition.form] and
                    BindCards.FORM_DEFINITIONS[condition.form].label) or condition.form)) or "Any form",
            }
            local ruleKeys = { "class", "spec", "content", "form" }
            local present = {}
            for _, key in ipairs(ruleKeys) do
                if (key == "class" and condition.class) or
                    (key == "spec" and condition.specGroup) or
                    (key == "content" and condition.content and condition.content ~= "ANY") or
                    (key == "form" and condition.form) then
                    present[#present + 1] = key
                end
            end
            local ruleCount = #present
            local showOverride = Call("CanCardUseGlobalPriority", card) == true
            local overrideReserve = showOverride and 122 or 0
            local chipWidth = min(112, max(52,
                floor((viewWidth - 70 - overrideReserve) / max(1, ruleCount + 1))))
            local visibleIndex = {}
            for index, key in ipairs(present) do visibleIndex[key] = index end
            for _, key in ipairs(ruleKeys) do
                local chip = view.chips[key]
                chip.label:SetText(chipValues[key])
                local canEditRules = not IsFixedCard(card)
                chip:SetEnabled(canEditRules)
                chip:SetAlpha(canEditRules and 1 or 0.48)
                local hasRule = visibleIndex[key] ~= nil
                if hasRule then
                    chip:SetWidth(chipWidth)
                    chip:ClearAllPoints(); chip:SetPoint("TOPLEFT", 8 + (visibleIndex[key] - 1) * (chipWidth + 4), -35)
                end
                chip:SetShown(not card.collapsed and hasRule)
            end
            view.always:SetShown(not card.collapsed and ruleCount == 0)
            local addRuleX = ruleCount == 0 and 56 or (8 + ruleCount * (chipWidth + 4))
            view.addRule:ClearAllPoints(); view.addRule:SetPoint("TOPLEFT", addRuleX, -35)
            view.addRule:SetShown(not card.collapsed)
            view.addRule:SetEnabled(not IsFixedCard(card))
            view.addRule:SetAlpha(IsFixedCard(card) and 0.32 or 1)
            view.overrideAll:ClearAllPoints(); view.overrideAll:SetPoint("TOPRIGHT", -8, -35)
            view.overrideAll.label:SetText(card.overrideAllBindingsWhenActive and "GLOBAL PRIORITY: ON" or
                "GLOBAL PRIORITY: OFF")
            view.overrideAll:SetShown(not card.collapsed and showOverride)
            Skin(view.overrideAll, card.overrideAllBindingsWhenActive and C.raised or C.paperAlt,
                card.overrideAllBindingsWhenActive and C.amber or C.faint)
            Skin(view, CardSurface(C.paper, card, 0.022),
                IsAmberNestedCard(card) and C.amber or (selected and C.blue or C.faint))
            view:SetAlpha(card.enabled == false and 0.52 or (active and 1 or 0.78))
            local compactHeader = viewWidth < 700
            local canRename = not IsFixedCard(card)
            view.rename:SetEnabled(canRename)
            view.rename:SetAlpha(canRename and 1 or 0.32)
            view.actions:SetShown(compactHeader)
            view.sub:SetShown(not compactHeader); view.rename:SetShown(not compactHeader); view.macro:SetShown(not compactHeader); view.delete:SetShown(not compactHeader)
            view.less:Hide(); view.columns:Hide(); view.more:Hide()
            -- Reserve the right-hand actions and optional ON/OFF control;
            -- long priority labels must not run underneath either button.
            local headerBudget = viewWidth - 80 - (compactHeader and 66 or 150) -
                (canRename and 35 or 0) - 16
            local titleWidth = min(210, max(50, headerBudget - 70))
            view.title:SetWidth(titleWidth)
            view.state:SetWidth(max(24, headerBudget - titleWidth))
            view.state:SetWordWrap(false)
            DrawPaperGrid(view, gridWidth, gridHeight, gridStep, not card.collapsed)
            view.grid:SetShown(not card.collapsed); view.rule:SetShown(not card.collapsed)
            view.grid:ClearAllPoints(); view.grid:SetPoint("TOPLEFT", 8, -62); view.grid:SetSize(gridWidth, gridHeight)
            view.renderedIconSize = cardIconSize
            view.resizeGrip:ClearAllPoints(); view.resizeGrip:SetPoint("CENTER", view.grid, "TOPLEFT", gridWidth, -gridHeight)
            view.resizeGrip:SetShown(not card.collapsed and not InCombat())
            view.paperResizeGrip:ClearAllPoints()
            if mode == "panel" then
                -- The panel's ScrollFrame clips anything beyond the page edge.
                view.paperResizeGrip:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -3, 3)
            else
                view.paperResizeGrip:SetPoint("TOPLEFT", view, "BOTTOMRIGHT", 3, 3)
            end
            view.paperResizeGrip:SetFrameLevel(view:GetFrameLevel() + 12)
            view.paperResizeGrip:SetShown(not card.collapsed and not InCombat())
            view.resizeBadge:ClearAllPoints(); view.resizeBadge:SetPoint("BOTTOMRIGHT", view.resizeGrip, "TOPRIGHT", 0, 3)
            if paperResizeState then
                view.resizeBadge:ClearAllPoints(); view.resizeBadge:SetPoint("BOTTOMRIGHT", view.paperResizeGrip, "TOPRIGHT", 0, 3)
                view.resizeBadge:SetText(string.format("%d × %d",
                    floor(paperResizeState.width + 0.5), floor(paperResizeState.height + 0.5)))
            elseif resizeState then
                view.resizeBadge:SetText(columns .. " × " .. rows)
            end
            view.resizeBadge:SetShown(resizeState ~= nil or paperResizeState ~= nil)
            view.cropRight:ClearAllPoints(); view.cropRight:SetPoint("RIGHT", view.grid, "RIGHT", -2, 0)
            view.cropRight:SetText("→ " .. croppedRight); view.cropRight:SetShown(not card.collapsed and croppedRight > 0)
            view.cropDown:ClearAllPoints(); view.cropDown:SetPoint("TOP", view.grid, "BOTTOM", 0, -1)
            view.cropDown:SetText("↓ " .. croppedDown); view.cropDown:SetShown(not card.collapsed and croppedDown > 0)
            for _, tile in ipairs(view.tiles) do tile:Hide() end
            if not card.collapsed then
                view.grid:SetHeight(gridHeight)
                for index = 1, slots do
                    local tile = view.tiles[index] or self:CreateWorkspaceTile(view, index)
                    local col, row = (index - 1) % columns, floor((index - 1) / columns)
                    tile:SetSize(cardIconSize, cardIconSize); tile:ClearAllPoints(); tile:SetPoint("TOPLEFT", col * (cardIconSize + 6), -row * (cardIconSize + 6))
                    tile.index, tile.card, tile.entry = index, card, entries[index]
                    tile.icon:SetTexture(tile.entry and EntryIcon(tile.entry) or WHITE_ICON)
                    tile.icon:SetDesaturated(not tile.entry); tile.icon:SetAlpha(tile.entry and 1 or 0.025)
                    tile.name:SetText(tile.entry and EntryLabel(tile.entry) or "+")
                    local showAbilityNames = not (BindCardsDB and BindCardsDB.settings and
                        BindCardsDB.settings.showAbilityNames == false)
                    tile.name:SetShown(not tile.entry or (showAbilityNames and cardIconSize > 36))
                    tile.key:SetText(tile.entry and (FormatKey(EntryBinding(tile.entry), EntryID(tile.entry)) or "") or "")
                    local key = tile.entry and EntryBinding(tile.entry)
                    key = key and (Call("NormalizeKey", key) or key)
                    local winner = key and (winners[key] or (BindCards.lastAppliedGamepadBindings or {})[key] or
            (BindCards.lastAppliedHoverBindings or {})[key])
                    tile.bindingActive = active and winner and EntryID(winner) == EntryID(tile.entry) or false
                    tile.overridden = key and winner and EntryID(winner) ~= EntryID(tile.entry) or false
                    tile.unavailable = EntrySpellUnavailable(tile.entry)
                    tile.override:SetShown(tile.overridden)
                    tile:Show(); self:StyleTile(tile)
                end
            end
            view:Show()
        end
    end
    for rootID, group in pairs(floatingGroups) do
        local floatingTabY = 6
        local floatingEarWidth = 0
        local lastFloatingKindByParent = {}
        local selectedFloatingCard = cardsByID[group.pageID] or group.root
        local ancestorCards = Helpers.HierarchyAncestors and Helpers.HierarchyAncestors(
            selectedFloatingCard, cardsByID, CardID, ParentID, MAX_HIERARCHY_SHEETS) or {}
        local floatingPathIDs = {}
        if group.pageID then floatingPathIDs[group.pageID] = true end
        for _, ancestor in ipairs(ancestorCards) do floatingPathIDs[CardID(ancestor)] = true end
        for _, info in ipairs(flat) do
            local card = info.card
            if RootCard(card) == group.root and (card == group.root or AncestorsExpanded(card)) then
                local parentKey = ParentID(card) or ("root:" .. rootID)
                local tabKind = IsMutuallyExclusiveSheet(card) and "exclusive" or
                    (IsMainBinderRoot(card) and "root" or "custom")
                if tabKind == "custom" and lastFloatingKindByParent[parentKey] == "exclusive" then
                    floatingTabY = floatingTabY + 6
                end
                lastFloatingKindByParent[parentKey] = tabKind
                local tabView = self.cardViews[CardID(card)] or self:CreateWorkspaceCard(CardID(card))
                local tab = tabView.tab
                local tabSelected = group.pageID == CardID(card)
                local tabActive = IsCardActive(card)
                local mainRoot = IsMainBinderRoot(card)
                local metrics = self:ApplyTabHierarchy(tab, info.depth, mainRoot)
                tab.groupRoot, tab.moveView = group.root, group.view
                tab:SetParent(group.view); tab:SetScale(1); tab:SetFrameLevel(group.view:GetFrameLevel() + 3)
                if group.view.SetClipsChildren then group.view:SetClipsChildren(false) end
                if tab.SetClipsChildren then tab:SetClipsChildren(false) end
                tab.label:SetText(CardName(card))
                tab.count:SetText("· " .. #Entries(card))
                metrics = self:FitTabToLabel(tab, metrics)
                floatingEarWidth = max(floatingEarWidth, metrics.width)
                local tabLift = tabSelected and 2 or 0
                tab:ClearAllPoints(); tab:SetPoint("TOPLEFT", group.view, "TOPRIGHT", -1, -floatingTabY + tabLift)
                local onSelectedPath = floatingPathIDs[CardID(card)] == true
                local emphasized = tabSelected or tabActive or onSelectedPath
                local amberNested = IsAmberNestedCard(card)
                local selectedAccent = amberNested and C.amber or C.blue
                local pathAccent = amberNested and C.amber or C.teal
                local tabTextColor = amberNested and C.amber or
                    (tabSelected and C.blue or ((tabActive or onSelectedPath) and C.text or C.muted))
                if self.useTopSurfaceText then tabTextColor = C.topText end
                tab.label:SetTextColor(unpack(tabTextColor))
                tab.count:SetTextColor(unpack(tabTextColor))
                local hasChildren = (childCount[CardID(card)] or 0) > 0
                local first, second = tab.expand.lines[1], tab.expand.lines[2]
                local lineColor = tabSelected and selectedAccent or (amberNested and C.amber or C.muted)
                first:ClearAllPoints(); second:ClearAllPoints()
                first:SetColorTexture(lineColor[1], lineColor[2], lineColor[3], tabSelected and 1 or 0.75)
                second:SetColorTexture(lineColor[1], lineColor[2], lineColor[3], tabSelected and 1 or 0.75)
                if card.treeExpanded == true then
                    first:SetPoint("CENTER", -2, 0); first:SetRotation(-math.pi / 4)
                    second:SetPoint("CENTER", 2, 0); second:SetRotation(math.pi / 4)
                else
                    first:SetPoint("CENTER", 0, 2); first:SetRotation(-math.pi / 4)
                    second:SetPoint("CENTER", 0, -2); second:SetRotation(math.pi / 4)
                end
                tab.expand:SetShown(hasChildren)
                ApplyCardIcon(tab.icon, card)
                tab.icon:SetDesaturated(not emphasized)
                tab.icon:SetAlpha(emphasized and 1 or 0.42)
                Color(tab.activeMark, tabSelected and selectedAccent or pathAccent)
                tab.activeMark:SetShown(tabActive)
                Skin(tab, CardSurface(emphasized and C.raised or C.paperAlt,
                        card, amberNested and 0.045 or 0.024),
                    amberNested and C.amber or
                    (tabSelected and C.blue or ((tabActive or onSelectedPath) and C.teal or C.faint)))
                tab:SetAlpha(card.enabled == false and 0.30 or
                    (tabSelected and 1 or (onSelectedPath and 0.84 or (tabActive and 0.76 or 0.48))))
                self:StyleAppearanceTab(tab, tabSelected, tabActive or onSelectedPath, card.enabled == false)
                tab:Show()
                floatingTabY = floatingTabY + metrics.height + metrics.gap
            end
        end
        if Helpers.ClampFloatingStack then
            local viewScale = group.view:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local viewLeft, viewTop = group.view:GetLeft(), group.view:GetTop()
            if viewLeft and viewTop and not (issecretvalue and
                (issecretvalue(viewLeft) or issecretvalue(viewTop))) then
                local left, top = Helpers.ClampFloatingStack(
                    viewLeft * viewScale, viewTop * viewScale,
                    group.width * viewScale, group.view:GetHeight() * viewScale,
                    floatingEarWidth * viewScale, floatingTabY * viewScale,
                    UIParent:GetWidth(), UIParent:GetHeight(), 8)
                if math.abs(left - viewLeft * viewScale) > 0.5 or
                    math.abs(top - viewTop * viewScale) > 0.5 then
                    group.view:ClearAllPoints()
                    group.view:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
                end
            end
        end
        local stackCards, maximumSheets = {}, MAX_HIERARCHY_SHEETS
        local ancestorStart = max(1, #ancestorCards - maximumSheets + 1)
        for index = ancestorStart, #ancestorCards do stackCards[#stackCards + 1] = ancestorCards[index] end
        local stackOffsets, stackOffset = {}, 0
        for index = #stackCards, 1, -1 do
            stackOffset = stackOffset + 18
            stackOffsets[index] = stackOffset
        end
        for index, layerCard in ipairs(stackCards) do
            local sheet = self:GetFloatingSheet(rootID, index)
            local activeDepth = min(3, depthByID[group.pageID] or 0)
            local layerDepth = min(3, depthByID[CardID(layerCard)] or 0)
            local mainRoot = IsMainBinderRoot(layerCard)
            sheet.card = layerCard
            sheet.rootID = rootID
            sheet.moveView = group.view
            sheet:SetParent(UIParent)
            sheet:SetScale(group.view:GetScale())
            local depthWidth = group.width + max(0, activeDepth - layerDepth) * 16
            sheet:SetSize(depthWidth, group.view:GetHeight() + stackOffsets[index] + 8)
            sheet:ClearAllPoints()
            sheet:SetPoint("TOPLEFT", group.view, "TOPLEFT",
                (layerDepth - activeDepth) * 16, stackOffsets[index])
            ApplyCardIcon(sheet.icon, layerCard)
            sheet.label:SetText(CardName(layerCard))
            sheet.icon:SetSize(mainRoot and 13 or 10, mainRoot and 13 or 10)
            local sheetFont, _, sheetFlags = sheet.label:GetFont()
            sheet.label:SetFont(sheetFont, mainRoot and 10 or 8, sheetFlags or "OUTLINE")
            sheet.nest:SetShown(ParentID(layerCard) ~= nil)
            local amberNested = IsAmberNestedCard(layerCard)
            Color(sheet.nest, amberNested and C.amber or C.teal)
            sheet.edge:SetColorTexture(unpack(amberNested and C.amber or
                (ParentID(layerCard) and C.raised or C.paper)))
            Skin(sheet, CardSurface(C.paperAlt, layerCard, 0.018), amberNested and C.amber or
                (ParentID(layerCard) and C.teal or C.border))
            sheet.restingAlpha = mainRoot and 0.70 or 0.62
            sheet:SetAlpha(sheet.restingAlpha)
            if self:IsEUITheme() and self.euiSkin and self.euiSkin.Panel and sheet.bindCardsEUISkin ~= self.euiSkin then
                pcall(self.euiSkin.Panel, sheet, { inset = true })
                sheet.bindCardsEUISkin = self.euiSkin
            end
            sheet:Show()
        end
        group.view.groupRoot = group.root
        self.floatingSelection[rootID] = group.pageID
        self:ApplyFloatingGroupLayer(group.view, false)
    end
    if mode == "binder" and (selectedView or pageStackCount > 0) then
        for index, sheet in ipairs(self.binderSheets) do
            if index <= pageStackCount then
                sheet:SetFrameLevel(self.workspaceContent:GetFrameLevel() + index * 3)
                local geometry = layerGeometry[index]
                sheet:SetSize(geometry.width, geometry.height)
                local layer = pageLayers[index]
                local layerCard = layer and layer.card
                sheet.card = layerCard
                ApplyCardIcon(sheet.icon, layerCard)
                sheet.label:SetText(CardName(layerCard))
                local cover = layer and layer.binderCover == true
                sheet.bindCardsBinderCoverKey = cover and layer.binderKey or nil
                sheet.bindCardsLegacyRole = cover and "cover" or "sheet"
                local detachedGhost = layer and layer.detachedGhost == true
                local mainRoot = IsMainBinderRoot(layerCard)
                local sheetIconSize = (cover or mainRoot) and 13 or (layer and layer.ancestor and 10 or 11)
                local sheetFontSize = (cover or mainRoot) and 10 or (layer and layer.ancestor and 8 or 9)
                sheet.icon:SetSize(sheetIconSize, sheetIconSize)
                sheet.icon:ClearAllPoints(); sheet.icon:SetPoint("TOPLEFT", cover and 9 or 8, cover and -4 or -3)
                sheet.label:ClearAllPoints()
                sheet.label:SetPoint("LEFT", sheet.icon, "RIGHT", 4, 0)
                sheet.label:SetPoint("RIGHT", -10, 0)
                sheet.icon:SetShown(not cover)
                sheet.label:SetShown(not cover)
                local sheetFont, _, sheetFlags = sheet.label:GetFont()
                sheet.label:SetFont(sheetFont, sheetFontSize, sheetFlags or "OUTLINE")
                sheet.edge:SetHeight(cover and 18 or 14)
                sheet.nest:SetShown(layer and layer.ancestor == true)
                local amberNested = layerCard and IsAmberNestedCard(layerCard)
                Color(sheet.nest, amberNested and C.amber or C.teal)
                sheet.edge:SetColorTexture(unpack(cover and C.blueSoft or
                    (amberNested and C.amber or (layer and layer.ancestor and C.raised or C.paper))))
                Skin(sheet, CardSurface(C.paperAlt, layerCard, 0.018), amberNested and C.amber or
                    (layer and layer.ancestor and C.teal or (cover and C.blue or C.border)))
                sheet.restingAlpha = detachedGhost and 0.24 or
                    (cover and 0.42 or (mainRoot and 0.70 or 0.62))
                sheet:SetAlpha(sheet.restingAlpha)
                if self:IsEUITheme() and self.euiSkin and self.euiSkin.Panel and sheet.bindCardsEUISkin ~= self.euiSkin then
                    pcall(self.euiSkin.Panel, sheet, { inset = true })
                    sheet.bindCardsEUISkin = self.euiSkin
                end
                sheet:ClearAllPoints()
                sheet:SetPoint("TOPLEFT", geometry.x, -geometry.y)
                sheet:Show()
                pageHeight = max(pageHeight, geometry.y + geometry.height + 5)
            else
                sheet.card = nil
                sheet:Hide()
            end
        end
        if selectedView then self:ApplyEmbeddedLayer(selectedView, self.workspaceContent:GetFrameLevel() + 30) end
    end
    self.workspaceContent:SetHeight(max(1, pageHeight, mode == "binder" and (tabY + 5) or 1))
    self:UpdateWorkspaceWheel()
    if mode == "binder" and self.frame and not self.dragSession and not self.windowResizing and
        not self.cardResize and
        not self.profileSwitchGeometry and
        (self.allBindersDetached or not settings.binderManualSize) then
        local _, _, _, safeMaximumHeight = self:GetSafeWindowBounds()
        local desiredHeight = self.allBindersDetached and 53 or
            min(safeMaximumHeight, max(180, max(pageHeight, tabY + 5) + 107))
        if math.abs(self.frame:GetHeight() - desiredHeight) > 0.5 then
            local left, top = self.frame:GetLeft(), self.frame:GetTop()
            self.frame:SetHeight(desiredHeight)
            if left and top then
                self.frame:ClearAllPoints()
                self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
            if not self.gridResize and not self.cardResize and self.frame.ClampToScreen then self.frame:ClampToScreen() end
        end
    end
    self.workspaceEmpty:SetShown(#binderFlat == 0)
    self:RefreshEditorChromeLayer()
    self:UpdateBinderStrings()
    self:UpdateWorkspaceScrollbars()
    if C_Timer and C_Timer.After and not self.scrollbarRefreshQueued then
        self.scrollbarRefreshQueued = true
        C_Timer.After(0, function()
            UI.scrollbarRefreshQueued = nil
            if UI.frame and UI.frame:IsShown() then UI:UpdateWorkspaceScrollbars() end
        end)
    end
end

function UI:SetProfileManagerStatus(message, tone)
    local manager = self.profileManager
    if not manager or not manager.status then return end
    local color = tone == "error" and C.red or tone == "warning" and C.amber or
        tone == "success" and C.teal or C.muted
    manager.status:SetText(message or "")
    manager.status:SetTextColor(unpack(color))
end

function UI:GetProfilesForBinder(binderId)
    local profiles = Call("GetProfiles", binderId) or {}
    if Helpers.ProfileLibraryList then return Helpers.ProfileLibraryList(profiles, binderId) end
    local list = {}
    for _, profile in pairs(profiles) do
        if profile.binderId == binderId then list[#list + 1] = profile end
    end
    tsort(list, function(left, right)
        return tostring(left.name or ""):lower() < tostring(right.name or ""):lower()
    end)
    return list
end

local function ProfileScopeLabel(profile)
    if not profile then return "BINDING SET" end
    if profile.binderId == "general" then return "GENERAL" end
    return tostring(profile.binderId or "CLASS"):match("^class:(.+)$") or "CLASS"
end

function UI:RefreshProfileManager()
    local manager = self.profileManager
    if not manager or not manager:IsShown() then return end
    local currentClass = Call("GetCurrentClassFile")
    local classBinderId = currentClass and ("class:" .. currentClass) or nil
    local generalSet, classSet = Call("GetSelectedProfileSets")
    if manager.focusedBinderId ~= "general" and manager.focusedBinderId ~= classBinderId then
        manager.focusedBinderId = classBinderId or "general"
    end
    local inspected = manager.focusedBinderId == "general" and generalSet or classSet
    manager.profileId = inspected and inspected.id or nil
    manager.count:SetText("2 libraries")
    if manager.listTitle then manager.listTitle:SetText("PROFILE LIBRARIES") end
    if manager.activeSetup then
        local classLabel = classSet and ProfileScopeLabel(classSet) or (currentClass or "CLASS")
        manager.activeSetup:SetText(string.format("General: %s  •  %s: %s",
            generalSet and generalSet.name or "None",
            classLabel, classSet and classSet.name or "None"))
    end

    local sections = {
        { binderId = "general", label = "GENERAL", selected = generalSet },
        { binderId = classBinderId, label = currentClass or "CLASS", selected = classSet },
    }
    for index, info in ipairs(sections) do
        local section = manager.librarySections[index]
        local list = info.binderId and self:GetProfilesForBinder(info.binderId) or {}
        local focused = manager.focusedBinderId == info.binderId
        section.binderId = info.binderId
        section.scope:SetText(info.label)
        section.scope:SetTextColor(unpack(focused and C.teal or C.muted))
        section.current:SetText(info.selected and info.selected.name or "No set available")
        section.current:SetTextColor(unpack(info.selected and C.text or C.muted))
        section.count:SetText(string.format("%d SET%s", #list, #list == 1 and "" or "S"))
        section.arrow:SetExpanded(section.expanded ~= false)
        Skin(section.header, focused and C.raised or C.paperAlt, focused and C.teal or C.faint)
        section.listScroll:SetShown(section.expanded ~= false)
        for rowIndex, profile in ipairs(list) do
            local row = section.rows[rowIndex]
            if not row then
                row = CreateFrame("Button", nil, section.listContent, "BackdropTemplate")
                row:SetHeight(24)
                row:SetPoint("TOPLEFT", 0, -(rowIndex - 1) * 26)
                row:SetPoint("TOPRIGHT", -2, -(rowIndex - 1) * 26)
                row.name = Font(row, 9, C.text)
                row.name:SetPoint("LEFT", 8, 0)
                row.name:SetPoint("RIGHT", -52, 0)
                row.name:SetWordWrap(false)
                row.state = Font(row, 7, C.muted, "OUTLINE")
                row.state:SetPoint("RIGHT", -7, 0)
                row:SetScript("OnClick", function(self)
                    if not (self.profileId and section.binderId) then return end
                    manager.focusedBinderId = section.binderId
                    if Mutate("Binding set loaded", function()
                        if Call("SelectProfileSet", self.profileId) == false then return false end
                        return Call("SetProfileBindingsEnabled", self.profileId, true) ~= false
                    end) then
                        manager.profileId = self.profileId
                        UI:RefreshProfileManager()
                    end
                end)
                row:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.blue)) end)
                row:SetScript("OnLeave", function() UI:RefreshProfileManager() end)
                section.rows[rowIndex] = row
            end
            local active = info.selected and info.selected.id == profile.id
            row.profileId = profile.id
            row.name:SetText(profile.name or "Binding set")
            row.name:SetTextColor(unpack(active and C.teal or C.text))
            row.state:SetText(active and (profile.bindingsEnabled == false and "INACTIVE" or "ACTIVE") or "")
            row.state:SetTextColor(unpack(profile.bindingsEnabled == false and C.muted or C.teal))
            Skin(row, active and C.raised or C.paperAlt, active and C.teal or C.faint)
            row:Show()
        end
        for rowIndex = #list + 1, #section.rows do
            section.rows[rowIndex].profileId = nil
            section.rows[rowIndex]:Hide()
        end
        section.listContent:SetHeight(max(section.listScroll:GetHeight(), #list * 26))
        UpdateSlimScroll(section.listScroll)
    end

    manager.name:SetText(inspected and inspected.name or "No binding set")
    if manager.scope then manager.scope:SetText(ProfileScopeLabel(inspected) .. " SET") end
    local paused = inspected and inspected.bindingsEnabled == false
    manager.bindingState:SetText(paused and "Inactive — select to activate" or "Active for this character")
    manager.bindingState:SetTextColor(unpack(paused and C.muted or C.teal))
    local stats = Helpers.ProfileStats and Helpers.ProfileStats(inspected) or
        { cards = 0, tiles = 0, bindings = 0, macros = 0 }
    manager.stats:SetText(string.format(
        "%d cards\n%d placed icons\n%d assigned bindings\n%d macros",
        stats.cards, stats.tiles, stats.bindings, stats.macros))
    local focusedScope = ProfileScopeLabel({ binderId = manager.focusedBinderId })
    manager.new.label:SetText("+ New " .. focusedScope:lower():gsub("^%l", string.upper) .. " set")
    SetButtonEnabled(manager.copy, inspected ~= nil)
    SetButtonEnabled(manager.rename, inspected ~= nil)
    SetButtonEnabled(manager.delete, inspected ~= nil)
end

function UI:CloseProfileTransfer()
    local transfer = self.profileTransfer
    if not transfer then return end
    if transfer.edit then
        transfer.edit:ClearFocus()
        if transfer.edit.SetPropagateKeyboardInput then transfer.edit:SetPropagateKeyboardInput(true) end
    end
    transfer:Hide()
    transfer.overlay:Hide()
    transfer:EnableKeyboard(false)
    transfer:SetPropagateKeyboardInput(true)
    if transfer.returnToManager and self.profileManager and self.frame and self.frame:IsShown() then
        self.profileManager:Show()
        self.profileManager:Raise()
        self:RefreshProfileManager()
    end
end

function UI:ConfigureProfileTransferReview(reviewing)
    local transfer = self.profileTransfer
    if not transfer or transfer.mode ~= "import" then return end
    transfer.reviewing = reviewing == true
    if transfer.reviewing then transfer.edit:ClearFocus() end
    transfer.editScroll:SetShown(not transfer.reviewing)
    transfer.summary:ClearAllPoints()
    if transfer.reviewing then
        transfer.title:SetText("Review import")
        transfer.message:SetText("Confirm the binding-set contents before importing.")
        transfer.summary:SetPoint("TOPLEFT", 24, -96)
        transfer.summary:SetPoint("BOTTOMRIGHT", -24, 62)
        transfer.back.label:SetText("Back")
        transfer.accept.label:SetText("Import set")
    else
        transfer.title:SetText("Import binding set")
        transfer.message:SetText("Paste a BindCards set or legacy profile export.")
        transfer.summary:SetPoint("BOTTOMLEFT", 24, 62)
        transfer.summary:SetPoint("BOTTOMRIGHT", -24, 62)
        transfer.summary:SetHeight(54)
        transfer.back.label:SetText("Close")
        transfer.accept.label:SetText("Review import")
        transfer.editScroll:Show()
        transfer.edit:SetFocus()
    end
end

function UI:ValidateProfileTransfer()
    local transfer = self.profileTransfer
    if not transfer or transfer.mode ~= "import" or transfer.reviewing then return end
    local value = transfer.edit:GetText() or ""
    transfer.importText = value
    transfer.importSummary = nil
    if value:gsub("%s", "") == "" then
        transfer.summaryText:SetText("Paste an export to preview its contents.")
        transfer.summaryText:SetTextColor(unpack(C.muted))
        SetButtonEnabled(transfer.accept, false)
        return
    end
    local summary, message = Call("GetImportSummary", value)
    UI.lastCallError = nil
    if not summary or summary == false then
        transfer.summaryText:SetText(message or "This export could not be read.")
        transfer.summaryText:SetTextColor(unpack(C.red))
        SetButtonEnabled(transfer.accept, false)
        return
    end
    transfer.importSummary = summary
    transfer.summaryText:SetText(string.format(
        "%s  •  %d cards  •  %d placed icons  •  %d bindings  •  %d macros\nImported sets stay inactive until selected.",
        summary.name, summary.cards, summary.tiles, summary.bindings, summary.macros))
    transfer.summaryText:SetTextColor(unpack(C.teal))
    SetButtonEnabled(transfer.accept, true)
end

function UI:OpenProfileTransfer(mode, profileId)
    local transfer = self.profileTransfer
    if not transfer then return false end
    if self.displayPopover then self.displayPopover:Hide() end
    self:ApplyProfileDialogScale()
    self:SetQuickBind(false)
    self:CancelDrag(true)
    transfer.returnToManager = self.profileManager and self.profileManager:IsShown() or false
    transfer.mode = mode == "import" and "import" or "export"
    transfer.profileId = profileId
    transfer.reviewing = false
    transfer.importText, transfer.importSummary = nil, nil
    transfer.editScroll:Show()
    transfer.summary:ClearAllPoints()
    transfer.summary:SetPoint("BOTTOMLEFT", 24, 62)
    transfer.summary:SetPoint("BOTTOMRIGHT", -24, 62)
    transfer.summary:SetHeight(54)
    transfer.back.label:SetText("Close")
    if transfer.mode == "export" then
        local exported, message = Call("ExportProfile", profileId)
        if not exported or exported == false then
            self:SetStatus(message or "Could not export profile.", "error")
            return false
        end
        local profile = profileId and Call("GetProfile", profileId) or nil
        local stats = Helpers.ProfileStats and Helpers.ProfileStats(profile) or
            { cards = 0, tiles = 0, bindings = 0, macros = 0 }
        transfer.title:SetText("Export " .. ProfileScopeLabel(profile) .. " set")
        transfer.message:SetText("The export is selected. Press Ctrl+C to copy it.")
        transfer.edit:SetText(exported)
        transfer.summaryText:SetText(string.format(
            "%s  •  %d cards  •  %d placed icons  •  %d bindings",
            profile and profile.name or "Profile", stats.cards, stats.tiles, stats.bindings))
        transfer.summaryText:SetTextColor(unpack(C.muted))
        transfer.accept.label:SetText("Select all")
        SetButtonEnabled(transfer.accept, true)
    else
        transfer.title:SetText("Import binding set")
        transfer.message:SetText("Paste a BindCards set or legacy profile export.")
        transfer.edit:SetText("")
        transfer.summaryText:SetText("Paste an export to preview its contents.")
        transfer.summaryText:SetTextColor(unpack(C.muted))
        transfer.accept.label:SetText("Review import")
        SetButtonEnabled(transfer.accept, false)
    end
    transfer.overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    transfer.overlay:SetFrameLevel(1190)
    transfer:SetFrameStrata("FULLSCREEN_DIALOG")
    transfer:SetFrameLevel(1191)
    -- Hide the top-level manager while its sibling transfer dialog is open.
    if transfer.returnToManager and self.profileManager then self.profileManager:Hide() end
    transfer.overlay:Show()
    transfer:Show()
    transfer:Raise()
    transfer:EnableKeyboard(true)
    transfer:SetPropagateKeyboardInput(true)
    self:StyleEditableText(transfer.edit)
    transfer.edit:SetFocus()
    if transfer.edit.SetPropagateKeyboardInput then transfer.edit:SetPropagateKeyboardInput(false) end
    if transfer.mode == "export" then transfer.edit:HighlightText() end
    return true
end

function UI:CreateProfileTransfer()
    if self.profileTransfer then return end
    local overlay = CreateFrame("Frame", "BindCardsProfileTransferOverlay", UIParent, "BackdropTemplate")
    overlay.bindCardsLegacyRole = "none" -- Preserve the translucent screen dimmer.
    overlay:SetAllPoints(UIParent)
    Skin(overlay, { 0, 0, 0, 0.66 }, { 0, 0, 0, 0 })
    overlay:EnableMouse(true)
    overlay:Hide()
    local transfer = CreateFrame("Frame", "BindCardsProfileTransfer", overlay, "BackdropTemplate")
    transfer:SetSize(560, 420)
    transfer:SetPoint("CENTER", UIParent, "CENTER", 0, 18)
    transfer:SetClampedToScreen(true)
    Skin(transfer, C.window, C.blueSoft)
    transfer:EnableMouse(true)
    transfer:Hide()
    transfer.overlay = overlay
    transfer.title = Font(transfer, 17, C.text)
    transfer.title:SetPoint("TOPLEFT", 24, -20)
    transfer.message = Font(transfer, 10, C.muted)
    transfer.message:SetPoint("TOPLEFT", transfer.title, "BOTTOMLEFT", 0, -8)
    local close = IconButton(transfer, "×", 26)
    close:SetPoint("TOPRIGHT", -14, -14)
    close:SetScript("OnClick", function() UI:CloseProfileTransfer() end)

    -- Blizzard's scrolling editor owns multiline mouse selection and caret routing.
    transfer.editScroll = CreateFrame("Frame", nil, transfer, "BackdropTemplate")
    transfer.editScroll:SetPoint("TOPLEFT", 24, -96)
    transfer.editScroll:SetPoint("BOTTOMRIGHT", -24, 124)
    Skin(transfer.editScroll, C.paper)
    transfer.editHost = CreateFrame("Frame", nil, transfer.editScroll, "ScrollingEditBoxTemplate")
    transfer.editHost:SetPoint("TOPLEFT", 7, -7)
    transfer.editHost:SetPoint("BOTTOMRIGHT", -7, 7)
    transfer.edit = transfer.editHost:GetEditBox()
    transfer.edit:EnableMouse(true)
    transfer.edit:SetFontObject("ChatFontNormal")
    self:StyleEditableText(transfer.edit)
    transfer.edit:SetAutoFocus(false)
    transfer.edit:SetMaxLetters(2097152)
    transfer.edit:SetScript("OnTextChanged", function(self)
        if transfer:IsShown() and transfer.mode == "import" and not transfer.reviewing then
            UI:ValidateProfileTransfer()
        end
    end)
    transfer.edit:SetScript("OnEscapePressed", function(self)
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        self:ClearFocus()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() UI:CloseProfileTransfer() end)
        else
            UI:CloseProfileTransfer()
        end
    end)

    transfer.summary = CreateFrame("Frame", nil, transfer, "BackdropTemplate")
    Skin(transfer.summary, C.paperAlt, C.faint)
    transfer.summaryText = Font(transfer.summary, 10, C.muted)
    transfer.summaryText:SetPoint("TOPLEFT", 12, -10)
    transfer.summaryText:SetPoint("BOTTOMRIGHT", -12, 9)
    transfer.summaryText:SetJustifyV("MIDDLE")
    transfer.summaryText:SetWordWrap(true)
    transfer.back = Button(transfer, "Close", 92, 26)
    transfer.back:SetPoint("BOTTOMRIGHT", -132, 18)
    transfer.back:SetScript("OnClick", function()
        if transfer.mode == "import" and transfer.reviewing then
            UI:ConfigureProfileTransferReview(false)
            UI:ValidateProfileTransfer()
        else
            UI:CloseProfileTransfer()
        end
    end)
    transfer.accept = Button(transfer, "Select all", 104, 26, "primary")
    transfer.accept:SetPoint("BOTTOMRIGHT", -20, 18)
    transfer.accept:SetScript("OnClick", function()
        if transfer.mode == "export" then
            transfer.edit:SetFocus()
            transfer.edit:HighlightText()
        elseif transfer.reviewing then
            local summary = transfer.importSummary
            local importedName = summary and summary.name or "Profile"
            if Mutate("Profile imported", function()
                return Call("ImportProfile", transfer.importText, false) ~= false
            end) then
                UI:CloseProfileTransfer()
                if UI.profileManager then UI.profileManager.profileId = nil end
                UI:SetProfileManagerStatus(
                    importedName .. " imported. Select a set to activate it.",
                    "success")
                UI:RefreshProfileManager()
            end
        elseif transfer.importSummary then
            UI:ConfigureProfileTransferReview(true)
        end
    end)
    transfer:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() if self:IsShown() then UI:CloseProfileTransfer() end end)
            else
                UI:CloseProfileTransfer()
            end
        end
    end)
    transfer:SetScript("OnHide", function(self)
        self.edit:ClearFocus()
        self:EnableKeyboard(false)
        self:SetPropagateKeyboardInput(true)
        overlay:Hide()
    end)
    self.profileTransfer = transfer
end

function UI:ApplyProfileDialogScale()
    local settings = BindCardsDB and BindCardsDB.settings or {}
    local wanted = tonumber(settings.uiScale) or 1
    local screenWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 960
    local screenHeight = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 650
    local function Apply(frame, width, height)
        if not frame then return end
        local fit = min(1.2, (screenWidth - 36) / width, (screenHeight - 36) / height)
        frame:SetScale(max(0.65, min(wanted, fit)))
        if frame.ClampToScreen then frame:ClampToScreen() end
    end
    Apply(self.profileManager, 680, 390)
    Apply(self.profileTransfer, 560, 420)
end

function UI:CreateProfileManager()
    if self.profileManager then return end
    local manager = CreateFrame("Frame", "BindCardsProfileManager", UIParent, "BackdropTemplate")
    manager:SetSize(680, 390)
    manager:SetPoint("CENTER", UIParent, "CENTER", 0, 18)
    manager:SetClampedToScreen(true)
    manager:SetMovable(true)
    manager:SetFrameStrata("FULLSCREEN_DIALOG")
    manager:SetFrameLevel(850)
    manager:EnableMouse(true)
    Skin(manager, C.window, C.blueSoft)
    manager:Hide()
    local header = CreateFrame("Frame", nil, manager, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(52)
    Skin(header, C.panel, C.faint)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() manager:StartMoving() end)
    header:SetScript("OnDragStop", function() manager:StopMovingOrSizing() end)
    local mark = header:CreateTexture(nil, "ARTWORK")
    mark:SetSize(4, 28)
    mark:SetPoint("LEFT", 15, 0)
    ThemeSolid(mark, C.blue)
    local title = Font(header, 16, C.text)
    title:SetPoint("LEFT", mark, "RIGHT", 9, 4)
    title:SetText("Binding sets")
    local subtitle = Font(header, 9, C.muted)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetPoint("RIGHT", -208, 0)
    subtitle:SetWordWrap(false)
    subtitle:SetText("General + Class")
    manager.activeSetup = subtitle
    local close = IconButton(header, "×", 26)
    close:SetPoint("RIGHT", -12, 0)
    close:SetScript("OnClick", function() manager:Hide() end)
    local export = Button(header, "Export", 62, 23)
    export:SetPoint("RIGHT", close, "LEFT", -8, 0)
    export:SetScript("OnClick", function() UI:OpenProfileTransfer("export", manager.profileId) end)
    local import = Button(header, "Import", 62, 23)
    import:SetPoint("RIGHT", export, "LEFT", -6, 0)
    import:SetScript("OnClick", function() UI:OpenProfileTransfer("import") end)

    local listPane = CreateFrame("Frame", nil, manager, "BackdropTemplate")
    listPane:SetPoint("TOPLEFT", 14, -66)
    listPane:SetPoint("BOTTOMLEFT", 14, 14)
    listPane:SetWidth(292)
    Skin(listPane, C.panel, C.faint)
    local listTitle = Font(listPane, 10, C.muted, "OUTLINE")
    listTitle:SetPoint("TOPLEFT", 10, -10)
    listTitle:SetText("PROFILE LIBRARIES")
    manager.listTitle = listTitle
    manager.count = Font(listPane, 8, C.muted)
    manager.count:SetPoint("TOPRIGHT", -10, -12)
    manager.librarySections = {}
    local function CreateLibrarySection(index)
        local section = CreateFrame("Frame", nil, listPane, "BackdropTemplate")
        section:SetPoint("TOPLEFT", 8, -32 - (index - 1) * 133)
        section:SetPoint("TOPRIGHT", -8, -32 - (index - 1) * 133)
        section:SetHeight(125)
        Skin(section, C.paper, C.faint)
        section.expanded = true
        section.rows = {}
        section.header = CreateFrame("Button", nil, section, "BackdropTemplate")
        section.header:SetPoint("TOPLEFT", 1, -1)
        section.header:SetPoint("TOPRIGHT", -1, -1)
        section.header:SetHeight(38)
        Skin(section.header, C.paperAlt, C.faint)
        section.scope = Font(section.header, 9, C.muted, "OUTLINE")
        section.scope:SetPoint("TOPLEFT", 9, -6)
        section.current = Font(section.header, 10, C.text)
        section.current:SetPoint("TOPLEFT", section.scope, "BOTTOMLEFT", 0, -2)
        section.current:SetPoint("RIGHT", -66, 0)
        section.current:SetWordWrap(false)
        section.count = Font(section.header, 7, C.muted, "OUTLINE")
        section.count:SetPoint("RIGHT", -22, 7)
        section.arrow = Chevron(section.header, 12)
        section.arrow:SetPoint("RIGHT", -7, 0)
        section.header:SetScript("OnClick", function()
            if not section.binderId then return end
            manager.focusedBinderId = section.binderId
            section.expanded = not section.expanded
            UI:RefreshProfileManager()
        end)
        section.header:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.blue)) end)
        section.header:SetScript("OnLeave", function() UI:RefreshProfileManager() end)
        section.listScroll = CreateFrame("ScrollFrame", nil, section, "UIPanelScrollFrameTemplate")
        section.listScroll:SetPoint("TOPLEFT", 6, -43)
        section.listScroll:SetPoint("BOTTOMRIGHT", -25, 5)
        SkinScrollFrame(section.listScroll)
        section.listContent = CreateFrame("Frame", nil, section.listScroll)
        section.listContent:SetWidth(238)
        section.listContent:SetHeight(1)
        section.listScroll:SetScrollChild(section.listContent)
        manager.librarySections[index] = section
    end
    CreateLibrarySection(1)
    CreateLibrarySection(2)

    local detail = CreateFrame("Frame", nil, manager, "BackdropTemplate")
    detail:SetPoint("TOPLEFT", listPane, "TOPRIGHT", 12, 0)
    detail:SetPoint("BOTTOMRIGHT", -14, 14)
    Skin(detail, C.panel, C.faint)
    manager.name = Font(detail, 16, C.text)
    manager.name:SetPoint("TOPLEFT", 16, -16)
    manager.name:SetPoint("TOPRIGHT", -90, -16)
    manager.name:SetWordWrap(false)
    manager.scope = Font(detail, 8, C.muted, "OUTLINE")
    manager.scope:SetPoint("TOPRIGHT", -16, -20)
    manager.bindingState = Font(detail, 9, C.teal, "OUTLINE")
    manager.bindingState:SetPoint("TOPLEFT", manager.name, "BOTTOMLEFT", 0, -7)
    local statsCard = CreateFrame("Frame", nil, detail, "BackdropTemplate")
    statsCard:SetPoint("TOPLEFT", 16, -64)
    statsCard:SetPoint("TOPRIGHT", -16, -64)
    statsCard:SetHeight(90)
    Skin(statsCard, C.paperAlt, C.faint)
    manager.stats = Font(statsCard, 10, C.muted)
    manager.stats:SetPoint("TOPLEFT", 12, -11)
    manager.stats:SetPoint("BOTTOMRIGHT", -12, 10)
    manager.stats:SetJustifyV("TOP")
    manager.new = Button(detail, "+ New binding set", 184, 27, "primary")
    manager.new:SetPoint("TOPLEFT", statsCard, "BOTTOMLEFT", 0, -14)
    manager.new:SetPoint("TOPRIGHT", statsCard, "BOTTOMRIGHT", 0, -14)
    manager.new:SetScript("OnClick", function()
        local currentClass = Call("GetCurrentClassFile")
        local classBinderId = currentClass and ("class:" .. currentClass) or nil
        local binderId = manager.focusedBinderId == classBinderId and classBinderId or "general"
        local scope = ProfileScopeLabel({ binderId = binderId })
        UI:ShowPrompt("New " .. scope .. " set", "Create a fresh " .. scope .. " binding set.", "Create", function(name)
            if not name or name:gsub("%s", "") == "" then return false end
            local changed = Mutate("Binding set created", function()
                return Call("CreateProfileSet", binderId, name) ~= false
            end)
            if changed then
                manager.focusedBinderId = binderId
                manager.profileId = nil
                UI:RefreshProfileManager()
            end
            return changed
        end, { value = "" })
    end)
    manager.copy = Button(detail, "Copy", 100, 25)
    manager.copy:SetPoint("TOPLEFT", manager.new, "BOTTOMLEFT", 0, -10)
    manager.copy:SetScript("OnClick", function()
        local profile = manager.profileId and Call("GetProfile", manager.profileId) or nil
        if not profile then return end
        UI:ShowPrompt("Copy " .. ProfileScopeLabel(profile) .. " set", "Create a copy of " .. profile.name .. ".", "Copy", function(name)
            if not name or name:gsub("%s", "") == "" then return false end
            local changed = Mutate("Profile copied", function() return Call("CopyProfile", profile.id, name) ~= false end)
            if changed then UI:RefreshProfileManager() end
            return changed
        end, { value = profile.name .. " Copy" })
    end)
    manager.rename = Button(detail, "Rename", 100, 25)
    manager.rename:SetPoint("LEFT", manager.copy, "RIGHT", 8, 0)
    manager.rename:SetScript("OnClick", function()
        local profile = manager.profileId and Call("GetProfile", manager.profileId) or nil
        if not profile then return end
        UI:ShowPrompt("Rename profile", "Choose a new profile name.", "Rename", function(name)
            if not name or name:gsub("%s", "") == "" then return false end
            local changed = Mutate("Profile renamed", function() return Call("RenameProfile", profile.id, name) ~= false end)
            if changed then UI:RefreshProfileManager() end
            return changed
        end, { value = profile.name })
    end)
    manager.delete = Button(detail, "Delete", 100, 25, "danger")
    manager.delete:SetPoint("TOPRIGHT", manager.new, "BOTTOMRIGHT", 0, -10)
    manager.delete:SetScript("OnClick", function()
        local profile = manager.profileId and Call("GetProfile", manager.profileId) or nil
        if not profile then return end
        UI:Confirm("Delete binding set?", profile.name .. " can be restored once with Undo.", function()
            if InCombat() then
                UI:SetStatus("Editing is unavailable during combat.", "warning")
                return
            end
            local previousUndo = UI.lastUndo
            UI:CaptureUndo("profile deletion", profile.id)
            if Mutate("Profile deleted", function() return Call("DeleteProfile", profile.id) ~= false end) then
                manager.profileId = nil
                UI:RefreshProfileManager()
            else
                UI.lastUndo = previousUndo
            end
        end)
    end)
    manager.status = Font(detail, 9, C.muted)
    manager.status:SetPoint("BOTTOMLEFT", 16, 11)
    manager.status:SetPoint("BOTTOMRIGHT", -16, 11)
    manager.status:SetWordWrap(false)
    manager.status:SetText("General and Class set changes apply immediately.")
    manager:SetScript("OnShow", function(self)
        self:EnableKeyboard(true)
        self:SetPropagateKeyboardInput(true)
        UI:SetProfileManagerStatus("General and Class set changes apply immediately.", "info")
        UI:RefreshProfileManager()
        manager:Raise()
    end)
    manager:SetScript("OnKeyDown", function(self, key)
        local childOpen = (UI.modal and UI.modal:IsShown()) or
            (UI.profileTransfer and UI.profileTransfer:IsShown())
        local closeManager = key == "ESCAPE" and not childOpen
        self:SetPropagateKeyboardInput(not closeManager)
        if closeManager then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() if self:IsShown() then self:Hide() end end)
            else
                self:Hide()
            end
        end
    end)
    manager:SetScript("OnHide", function(self)
        self:EnableKeyboard(false)
        self:SetPropagateKeyboardInput(true)
    end)
    self.profileManager = manager
    self:CreateProfileTransfer()
    self:ApplyProfileDialogScale()
end

function UI:ShowProfiles()
    if not self.frame or not self.frame:IsShown() then return false end
    if self.displayPopover then self.displayPopover:Hide() end
    if not self.profileManager then self:CreateProfileManager() end
    self.profileManager:Show()
    self.profileManager:Raise()
    self:RefreshProfileManager()
    return true
end

function UI:CreateModal(parent)
    -- UIParent hosting keeps prompts above UIParent-hosted floating binders.
    local modalParent = UIParent or parent
    local overlay = CreateFrame("Frame", "BindCardsModalOverlay", modalParent, "BackdropTemplate")
    overlay.bindCardsLegacyRole = "none" -- Preserve the translucent screen dimmer.
    overlay:SetAllPoints(modalParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    overlay:SetFrameLevel(MODAL_OVERLAY_LEVEL)
    Skin(overlay, { 0, 0, 0, 0.68 }, { 0, 0, 0, 0 })
    overlay:EnableMouse(true)
    overlay:Hide()
    local m = CreateFrame("Frame", "BindCardsModal", overlay, "BackdropTemplate")
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetFrameLevel(MODAL_FRAME_LEVEL)
    m:SetSize(480, 330)
    m:SetPoint("CENTER")
    m:SetClampedToScreen(true)
    Skin(m, C.window, C.blueSoft)
    m:EnableMouse(true)
    m:Hide()
    m.overlay = overlay
    m.title = Font(m, 17, C.text)
    m.title:SetPoint("TOPLEFT", 20, -18)
    m.message = Font(m, 11, C.muted)
    m.message:SetPoint("TOPLEFT", m.title, "BOTTOMLEFT", 0, -10)
    m.message:SetPoint("RIGHT", -20, 0)
    m.message:SetJustifyH("LEFT")
    m.previewIcon = m:CreateTexture(nil, "ARTWORK")
    m.previewIcon:SetSize(38, 38)
    m.previewIcon:SetPoint("TOPRIGHT", -20, -16)
    m.previewIcon:Hide()
    m.previewLabel = Font(m, 9, C.muted, "OUTLINE")
    m.previewLabel:SetPoint("TOPRIGHT", m.previewIcon, "BOTTOMRIGHT", 0, -3)
    m.previewLabel:SetWidth(170)
    m.previewLabel:SetJustifyH("RIGHT")
    m.previewLabel:Hide()
    m.counter = Font(m, 9, C.muted, "OUTLINE")
    m.counter:SetPoint("BOTTOMLEFT", 20, 20)
    m.counter:Hide()
    m.edit = CreateFrame("EditBox", nil, m, "BackdropTemplate")
    m.edit:SetSize(440, 30)
    m.edit:SetPoint("TOPLEFT", 20, -92)
    Skin(m.edit, C.paper)
    m.edit:SetFontObject("GameFontHighlight")
    m.edit:EnableMouse(true)
    self:StyleEditableText(m.edit)
    m.edit:SetTextInsets(8, 8, 0, 0)
    m.edit:SetAutoFocus(false)
    m.multiScroll = CreateFrame("Frame", nil, m, "BackdropTemplate")
    m.multiScroll:SetSize(440, 180)
    m.multiScroll:SetPoint("TOPLEFT", 20, -92)
    Skin(m.multiScroll, C.paper)
    m.multiHost = CreateFrame("Frame", nil, m.multiScroll, "ScrollingEditBoxTemplate")
    m.multiHost:SetPoint("TOPLEFT", 7, -7)
    m.multiHost:SetPoint("BOTTOMRIGHT", -7, 7)
    m.multi = m.multiHost:GetEditBox()
    m.multi:EnableMouse(true)
    m.multi:SetFontObject("ChatFontNormal")
    self:StyleEditableText(m.multi)
    m.multi:SetAutoFocus(false)
    m.multi:SetMaxLetters(2097152)
    m.multi:SetScript("OnTextChanged", function(self)
        if m.macroPreview then UI:UpdateMacroPreview(m, self:GetText()) end
        if m.counter:IsShown() then
            local maximum = self.GetMaxLetters and self:GetMaxLetters() or 0
            m.counter:SetText(#self:GetText() .. " / " .. maximum)
            m.counter:SetTextColor(unpack(#self:GetText() >= maximum and C.amber or C.muted))
        end
    end)
    m.cancel = Button(m, "Cancel", 88, 25)
    m.cancel:SetPoint("BOTTOMRIGHT", -116, 16)
    local function Close()
        pcall(m.EnableKeyboard, m, false)
        pcall(m.SetPropagateKeyboardInput, m, true)
        if m.edit then m.edit:ClearFocus() end
        if m.multi then m.multi:ClearFocus() end
        m:Hide(); overlay:Hide()
    end
    m.cancel:SetScript("OnClick", Close)
    m.accept = Button(m, "Save", 88, 25, "primary")
    m.accept:SetPoint("BOTTOMRIGHT", -20, 16)
    local function Accept()
        local value = m.activeEdit and m.activeEdit:GetText()
        local callback = m.callback
        local result = callback and callback(value)
        if m.callback ~= callback then return end
        if result ~= false then Close() elseif m.activeEdit then m.activeEdit:SetFocus() end
    end
    m.accept:SetScript("OnClick", Accept)
    m.edit:SetScript("OnEnterPressed", Accept)
    m.edit:SetScript("OnEscapePressed", Close)
    m.multi:SetScript("OnEscapePressed", Close)
    m.multi:HookScript("OnKeyDown", function(_, key)
        if key == "ENTER" and IsControlKeyDown and IsControlKeyDown() then Accept() end
    end)
    m:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE" and key ~= "ENTER")
        if key == "ESCAPE" then Close()
        elseif key == "ENTER" and (not m.activeEdit or m.activeEdit == m.edit or (IsControlKeyDown and IsControlKeyDown())) then Accept() end
    end)
    m:EnableKeyboard(false)
    m:SetPropagateKeyboardInput(true)
    m:SetScript("OnHide", function(self)
        pcall(self.EnableKeyboard, self, false)
        pcall(self.SetPropagateKeyboardInput, self, true)
        if self.edit then self.edit:ClearFocus() end
        if self.multi then self.multi:ClearFocus() end
        self.activeEdit = nil
        self.macroPreview, self.previewFallback = false, nil
        self.previewIcon:Hide()
        self.previewLabel:Hide()
        self.counter:Hide()
        self.multiScroll:Hide()
        overlay:Hide()
    end)
    self.modal = m
end

function UI:CreateCapture(parent)
    local captureParent = UIParent or parent
    local c = CreateFrame("Button", "BindCardsBindingCapture", captureParent, "BackdropTemplate")
    c:SetFrameStrata("FULLSCREEN_DIALOG")
    c:SetFrameLevel(1100)
    c:SetSize(480, 252)
    c:SetPoint("CENTER", UIParent, "CENTER")
    c:SetClampedToScreen(true)
    Skin(c, C.window, C.amber)
    c:EnableMouse(true)
    c:EnableMouseWheel(true)
    c:RegisterForClicks("AnyDown")
    c:Hide()
    c:EnableKeyboard(false)
    c.title = Font(c, 16, C.text)
    c.title:SetPoint("TOP", 0, -23)
    c.key = Font(c, 12, C.amber)
    c.key:SetPoint("TOP", c.title, "BOTTOM", 0, -20)

    -- Mouseover: neither toggle = a normal key; one = that disposition only;
    -- both = any unit frame. The captured key is saved as HOVER:<scope>:<key>.
    local hoverLabel = Font(c, 11, C.muted)
    hoverLabel:SetPoint("TOPLEFT", 30, -97)
    hoverLabel:SetText("Mouseover:")
    c.hoverButtons = {}
    c.hoverFriendly, c.hoverHostile = false, false
    local help = Font(c, 10, C.muted)
    help:SetPoint("BOTTOM", 0, 18)
    c.help = help
    function c:GetHoverScope()
        return Call("GetHoverScope", self.hoverFriendly, self.hoverHostile)
    end
    function c:SetHoverScope(friendly, hostile)
        self.hoverFriendly, self.hoverHostile = friendly and true or false, hostile and true or false
        local scope = self:GetHoverScope()
        for _, button in ipairs(self.hoverButtons) do
            local on = self[button.hoverField]
            button.label:SetText((on and "• " or "") .. button.hoverText)
            Skin(button, on and C.raised or C.paperAlt, on and button.hoverColor or C.faint)
            local ink = on and button.hoverColor or C.muted
            if ink then button.label:SetTextColor(ink[1], ink[2], ink[3]) end
        end
        -- Controller gestures belong to native bars, not unit frames.
        for _, button in ipairs(self.pageButtons) do SetButtonEnabled(button, not scope) end
        if scope then
            self.key:SetText("Press a key or click · " .. (Call("FormatHoverScope", scope) or ""))
            local text = "Works only while the cursor is over a matching unit frame.\n" ..
                "Plain left and right click can be bound here.\nClear removes this mouseover binding  •  Escape cancels"
            -- Blizzard Click Casting runs first on Blizzard frames: name its clicks.
            local native = Call("GetNativeActionClicks") or {}
            if #native > 0 then
                local names = {}
                for index = 1, math.min(#native, 4) do names[index] = ReadableClick(native[index]) end
                text = text .. "\n|cffeea840Blizzard Click Casting still uses: " .. table.concat(names, ", ") ..
                    (#native > 4 and ", …" or "") .. "|r"
            end
            self.help:SetText(text)
        else
            self.key:SetText("Press a key, mouse button, or gamepad combination")
            self.help:SetText("Choose Bar 1, 2 or 3, then hold LT / RT and press a face or D-pad button.\n" ..
                "Applies to native bars outside combat. Base face buttons are reserved.\n" ..
                "Mouse and wheel supported  •  Right-click clears  •  Escape cancels")
        end
    end
    for index, spec in ipairs({
        { field = "hoverFriendly", text = "Friendly", color = C.hoverFriendly },
        { field = "hoverHostile", text = "Hostile", color = C.hoverHostile },
    }) do
        local button = Button(c, spec.text, 78, 24)
        button.hoverField, button.hoverText, button.hoverColor = spec.field, spec.text, spec.color
        button:SetPoint("TOPLEFT", 160 + (index - 1) * 86, -91)
        button:SetScript("OnClick", function()
            if spec.field == "hoverFriendly" then c:SetHoverScope(not c.hoverFriendly, c.hoverHostile)
            else c:SetHoverScope(c.hoverFriendly, not c.hoverHostile) end
        end)
        -- Button's OnLeave restores the default skin; keep the scope colors.
        button:HookScript("OnLeave", function() c:SetHoverScope(c.hoverFriendly, c.hoverHostile) end)
        c.hoverButtons[index] = button
    end
    -- Hover modes capture right click, so clearing needs its own control.
    c.clearButton = Button(c, "Clear", 78, 24)
    c.clearButton:SetPoint("TOPLEFT", 332, -91)
    c.clearButton:SetScript("OnClick", function()
        local scope = c:GetHoverScope()
        if scope then UI:ClearEntryHoverBinding(c.card, c.entry, scope)
        else UI:SetEntryBinding(c.card, c.entry, nil) end
        c:Hide()
    end)
    -- Resolve a captured key against the current mouseover scope.
    function c:Commit(key)
        if not key then return end
        local scope = self:GetHoverScope()
        if scope then key = Call("MakeHoverBinding", scope, key) end
        if key then UI:SetEntryBinding(self.card, self.entry, key); self:Hide() end
    end

    local pageLabel = Font(c, 11, C.muted)
    pageLabel:SetPoint("TOPLEFT", 30, -131)
    pageLabel:SetText("Gamepad override:")
    c.pageButtons = {}
    function c:SelectGamepadPage(page)
        self.gamepadPage = page
        for index, button in ipairs(self.pageButtons) do
            button.label:SetText((index == page and "• " or "") .. "Bar " .. index)
            Skin(button, index == page and C.raised or C.paperAlt, index == page and C.amber or C.faint)
        end
    end
    for page = 1, 3 do
        local selectedPage = page
        local button = Button(c, "Bar " .. page, 78, 24)
        button:SetPoint("TOPLEFT", 160 + (page - 1) * 86, -125)
        button:SetScript("OnClick", function() c:SelectGamepadPage(selectedPage) end)
        c.pageButtons[page] = button
    end
    if c.EnableGamePadButton then
        c:SetScript("OnGamePadButtonDown", function(self, button)
            if InCombat() then self:Hide(); return end
            if self:GetHoverScope() then return end
            self.gamepadHeld = self.gamepadHeld or {}
            self.gamepadHeld[button] = true
            if button == "PADLTRIGGER" or button == "PADRTRIGGER" then
                self.key:SetText("Press a face or D-pad button")
                return
            end
            local key = Call("MakeGamepadShortcut", button,
                self.gamepadHeld.PADLTRIGGER, self.gamepadHeld.PADRTRIGGER, self.gamepadPage)
            if key then UI:SetEntryBinding(self.card, self.entry, key); self:Hide() end
        end)
        c:SetScript("OnGamePadButtonUp", function(self, button)
            if self.gamepadHeld then self.gamepadHeld[button] = nil end
        end)
    end
    c:SetScript("OnKeyDown", function(self, raw)
        -- Controller events have their own trigger-aware capture path. Some
        -- clients also deliver PAD keys here; never record a partial chord.
        if type(raw) == "string" and raw:match("^PAD") then return end
        if raw == "ESCAPE" then
            -- Keep propagation disabled until WoW has finished dispatching this
            -- key. Hiding synchronously runs OnHide, restores propagation, and
            -- lets the same Escape continue into UISpecialFrames.
            self:SetPropagateKeyboardInput(false)
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() if self:IsShown() then self:Hide() end end)
            else
                self:Hide()
            end
            return
        end
        local key = CapturedKey(raw)
        -- Backspace/Delete clear, as in normal mode, but only this scope.
        if self:GetHoverScope() and (key == "BACKSPACE" or key == "DELETE") then
            UI:ClearEntryHoverBinding(self.card, self.entry, self:GetHoverScope())
            self:Hide()
            return
        end
        self:Commit(key)
    end)
    c:SetScript("OnMouseDown", function(self, button)
        local hover = self:GetHoverScope() ~= nil
        local modified = (IsAltKeyDown and IsAltKeyDown()) or
            (IsControlKeyDown and IsControlKeyDown()) or
            (IsShiftKeyDown and IsShiftKeyDown())
        if button == "RightButton" and not modified and not hover then
            UI:SetEntryBinding(self.card, self.entry, nil)
            self:Hide()
            return
        end
        self:Commit(MouseKey(button, hover))
    end)
    c:SetScript("OnMouseWheel", function(self, delta)
        self:Commit(CapturedKey(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
    end)
    c:SetScript("OnHide", function(self)
        self:EnableKeyboard(false)
        if self.EnableGamePadButton then self:EnableGamePadButton(false) end
        self.gamepadHeld = nil
        pcall(self.SetPropagateKeyboardInput, self, true)
        self.card, self.entry = nil, nil
        self.hoverFriendly, self.hoverHostile = false, false
    end)
    self.capture = c
end

function UI:ToggleSpellbook()
    -- Guidance only when the native hardware-click target is unavailable or
    -- combat prevents the template action. Never retry via an addon opener.
    local key
    if type(GetBindingKey) == "function" then
        local ok, first, second = pcall(GetBindingKey, "TOGGLESPELLBOOK")
        if ok then
            local candidates = { first, second }
            for index = 1, 2 do
                local candidate = candidates[index]
                if not (issecretvalue and issecretvalue(candidate)) and type(candidate) == "string" and candidate ~= "" then
                    key = candidate
                    break
                end
            end
        end
    end
    local message = key and ("Open your spellbook with " .. key .. ", or choose Spells in the controller menu.")
        or "Open Spells from the controller menu or the spellbook button on Blizzard's micro menu."
    self:SetStatus(message, "info")
    return false, message
end

function UI:RefreshSpellbookButton()
    local button = self.spellbookButton
    if not button or (InCombatLockdown and InCombatLockdown()) then return end
    local delegate = SpellbookMicroButton
    local aspect = Enum and Enum.ForbiddenAspect and Enum.ForbiddenAspect.ScriptedInput
    local usable = false
    if delegate and aspect and type(delegate.HasAccessConstraints) == "function"
        and type(delegate.HasAnyForbiddenAspects) == "function" then
        local accessOK, constrained = pcall(delegate.HasAccessConstraints, delegate)
        local scriptOK, forbidden = pcall(delegate.HasAnyForbiddenAspects, delegate, aspect)
        usable = accessOK and scriptOK and not (issecretvalue and (issecretvalue(constrained) or issecretvalue(forbidden)))
            and constrained == false and forbidden == false
    end
    button:SetAttribute("type", usable and "click" or nil)
    button:SetAttribute("clickbutton", usable and delegate or nil)
    self.spellbookActionReady = usable
end

-- Keep the header menu out of Blizzard_Menu: Forever's native menu also
-- activates controller bindings/focus, which can be blocked for addon callers.
function UI:ToggleHeaderMenu(owner, display)
    local menu = self.headerMenu
    if menu and menu:IsShown() then menu:Hide(); return end
    if not menu then
        menu = CreateFrame("Frame", "BindCardsHeaderMenu", owner, "BackdropTemplate")
        self.headerMenu = menu
        menu:SetWidth(280)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        Skin(menu, C.panel, C.border)
        menu.rows = {}
        menu:RegisterEvent("GLOBAL_MOUSE_DOWN")
        menu:SetScript("OnEvent", function(self)
            if self:IsShown() and not CursorInside(self) and not CursorInside(owner) then
                self:Hide()
            end
        end)
        owner:HookScript("OnHide", function() menu:Hide() end)
        if UISpecialFrames then tinsert(UISpecialFrames, "BindCardsHeaderMenu") end
    end
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(800)
    for _, row in ipairs(menu.rows) do row:Hide() end
    local count = 0
    local function AddRow(label, callback)
        count = count + 1
        local row = menu.rows[count]
        if not row then
            row = Button(menu, "", 264, 26)
            menu.rows[count] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 8, -8 - (count - 1) * 30)
        row.label:SetText(label)
        row:SetScript("OnClick", function()
            menu:Hide()
            callback()
        end)
        row:SetFrameLevel(801)
        row:Show()
    end
    if self.lastUndo then
        AddRow("Undo " .. self.lastUndo.label, function() UI:UndoLastChange() end)
    end
    AddRow("Display", function() display:SetShown(not display:IsShown()) end)
    local settings = BindCardsDB.settings
    local function ToggleSetting(key, label, refresh)
        AddRow((settings[key] ~= false and "[x] " or "[ ] ") .. label, function()
            settings[key] = settings[key] == false
            if refresh then UI:RefreshGrid(); UI:RefreshWorkspace() end
        end)
    end
    ToggleSetting("showAbilityNames", "Show ability names", true)
    ToggleSetting("gatherLooseSheets", "Gather loose sheets with binder")
    AddRow("Profiles", function() UI:ShowProfiles(owner) end)
    -- Stand-in unit frames for testing mouseover bindings without a group.
    AddRow("Test unit frames", function() Call("ToggleHoverTestFrames") end)
    menu:SetHeight(16 + count * 30)
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -6)
    menu:Show()
end

-- A center-panel ShowUIPanel closes UISpecialFrames before showing the book.
-- Only restore a binder hidden in that same UI turn, never one closed earlier.
function UI:RememberSpellbookClose()
    if not C_Timer or not C_Timer.After then return end
    local pending = {}
    self.spellbookClosePending = pending
    C_Timer.After(0, function()
        if UI.spellbookClosePending == pending then UI.spellbookClosePending = nil end
    end)
end

function UI:InstallSpellbookKeepOpen()
    if self.spellbookKeepOpenHook or not hooksecurefunc or not ShowUIPanel then return end
    self.spellbookKeepOpenHook = true
    hooksecurefunc("ShowUIPanel", function(panel)
        if not panel or (panel ~= PlayerSpellsFrame and panel ~= SpellBookFrame) then return end
        local pending = UI.spellbookClosePending
        UI.spellbookClosePending = nil
        if not pending or not panel:IsShown() or not UI.frame or UI.frame:IsShown() or InCombat() then return end
        UI.frame:Show()
        UI:RequestRefresh()
    end)
end

function UI:ConfigureSpellbookButton(button)
    self.spellbookButton = button
    -- Keep the engine-owned template OnClick intact. This template explicitly
    -- supports out-of-combat actions without protecting the Binder ancestry.
    button:RegisterForClicks("LeftButtonUp")
    button:SetAttribute("useOnKeyDown", false)
    button:HookScript("OnShow", function() UI:RefreshSpellbookButton() end)
    button:HookScript("OnEnter", function() UI:RefreshSpellbookButton() end)
    button:SetScript("PreClick", function()
        -- Native panel opening may close UISpecialFrames, including our editor.
        -- Remember only this click's editor; never alter Blizzard's close list.
        UI.spellbookReturnFrame = UI.frame and UI.frame:IsShown() and UI.frame or nil
    end)
    button:SetScript("PostClick", function()
        local returnFrame = UI.spellbookReturnFrame
        UI.spellbookReturnFrame = nil
        if returnFrame and not returnFrame:IsShown() and not (InCombatLockdown and InCombatLockdown()) then
            returnFrame:Show()
            UI:RequestRefresh()
        end
        if (InCombatLockdown and InCombatLockdown()) or not UI.spellbookActionReady then
            UI:ToggleSpellbook()
        end
    end)
    self:RefreshSpellbookButton()
end

function UI:Build()
    if self.frame then return end
    -- Initial construction configures keyboard handlers and secure ancestry.
    -- pcall does not prevent Blizzard from reporting blocked protected calls.
    if InCombat() then
        Call("Notify", "Open BindCards after combat to initialize the editor.")
        return
    end
    self:ApplyAppearanceTheme(self:GetAppearanceTheme(), false)
    local f = CreateFrame("Frame", "BindCardsFrame", UIParent, "BackdropTemplate")
    f:SetSize(580, 520)
    f:SetPoint("LEFT", UIParent, "LEFT", 34, 0)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    if f.SetResizable then f:SetResizable(true) end
    if f.SetResizeBounds then f:SetResizeBounds(560, 280, 1200, 1000)
    elseif f.SetMinResize then
        f:SetMinResize(560, 280)
        if f.SetMaxResize then f:SetMaxResize(1200, 1000) end
    end
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not UI.modal:IsShown() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI:SaveWindowPlacement(false)
    end)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    Skin(f, C.window, C.border)
    f:Hide()
    self.frame = f
    self:InstallSpellbookKeepOpen()
    if UISpecialFrames then
        local registered
        for _, name in ipairs(UISpecialFrames) do
            if name == "BindCardsFrame" then registered = true; break end
        end
        if not registered then UISpecialFrames[#UISpecialFrames + 1] = "BindCardsFrame" end
    end

    local panelShell = CreateFrame("Frame", nil, f, "BackdropTemplate")
    panelShell.bindCardsLegacyRole = "cover"
    panelShell:SetAllPoints(f); panelShell:SetFrameLevel(f:GetFrameLevel())
    panelShell:EnableMouse(false); Skin(panelShell, C.window, C.border)
    self.panelShell = panelShell

    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header.bindCardsLegacyRole = "cover"
    header.bindCardsTopSurface = "header"
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(51)
    Skin(header, C.panel, C.faint)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() if not UI.modal:IsShown() then f:StartMoving() end end)
    header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        UI:SaveWindowPlacement(false)
    end)
    header:SetScript("OnEnter", function() UI:SetBinderResizeHover(true) end)
    header:SetScript("OnLeave", function() UI:SetBinderResizeHover(false) end)
    self.header = header
    local mark = header:CreateTexture(nil, "ARTWORK")
    mark:SetSize(4, 28); mark:SetPoint("LEFT", 16, 0); ThemeSolid(mark, C.blue)
    local title = Font(header, 16, C.text)
    title:SetPoint("LEFT", mark, "RIGHT", 9, 0); title:SetText("BindCards"); title:SetWidth(76); title:SetWordWrap(false)
    self.profileName = Font(header, 10, C.muted)
    self.profileName:SetPoint("LEFT", title, "RIGHT", 6, -2); self.profileName:SetWidth(64); self.profileName:SetWordWrap(false)
    local close = IconButton(header, "×", 28)
    close:SetPoint("RIGHT", -11, 0)
    close:SetScript("OnClick", function() UI:SetQuickBind(false); f:Hide() end)
    self.closeButton = close
    self.quickButton = Button(header, "Quick Bind", 88, 25, "primary")
    self.quickButton:SetPoint("RIGHT", close, "LEFT", -8, 0)
    self.quickButton:SetScript("OnClick", function() UI:SetQuickBind(not UI.quickBind) end)
    self.quickEscape = CreateFrame("Frame", nil, f)
    self.quickEscape:SetAllPoints(f)
    self.quickEscape:SetFrameLevel(f:GetFrameLevel() + 1)
    self.quickEscape:Hide()
    self.quickEscape:EnableKeyboard(false)
    self.combatBadge = Font(header, 10, C.amber)
    self.combatBadge:SetPoint("RIGHT", self.quickButton, "LEFT", -14, 0)
    self.combatBadge:SetText("Combat")
    local menuButton = Button(header, "Menu", 56, 24); menuButton:SetPoint("RIGHT", self.quickButton, "LEFT", -7, 0)
    self.headerMenuButton = menuButton
    local spellbookButton = Button(header, "Spells", 48, 24, nil, "InsecureActionButtonTemplate")
    spellbookButton:SetPoint("RIGHT", menuButton, "LEFT", -7, 0)
    self:ConfigureSpellbookButton(spellbookButton)
    self.combatBadge:ClearAllPoints(); self.combatBadge:SetPoint("RIGHT", spellbookButton, "LEFT", -8, 0)
    local display = CreateFrame("Frame", "BindCardsAppearancePopover", UIParent, "BackdropTemplate")
    display:SetSize(252, 306); display:SetPoint("TOPRIGHT", menuButton, "BOTTOMRIGHT", 0, -6)
    -- Above DIALOG card ears/inspectors, but below profile windows and modal
    -- overlays. TOOLTIP would outrank even the full-screen confirmation veil.
    display:SetFrameStrata("FULLSCREEN_DIALOG")
    display:SetFrameLevel(800)
    display:SetClampedToScreen(true)
    Skin(display, C.panel, C.border); display:Hide(); display:EnableMouse(true)
    self.displayPopover = display
    display:SetScript("OnShow", function() UI:RefreshAppearancePopoverLayer() end)
    local appearance = Font(display, 9, C.muted); appearance:SetPoint("TOPLEFT", 10, -9); appearance:SetText("APPEARANCE")
    self.appearanceButtons = {}
    local appearanceOptions = {
        { "eui", "Ellesmere", 70, 10, -25 },
        { "mimezu", "Mimezu", 68, 86, -25 },
        { "luminous", "Luminous", 78, 160, -25 },
        { "charcoal", "Charcoal", 70, 10, -53 },
        { "chalk", "Chalk", 68, 86, -53 },
        { "tungsten", "Tungsten", 78, 160, -53 },
        { "editorial", "Editorial", 70, 10, -81 },
        { "snes", "Super NES", 74, 86, -81 },
        { "famicom", "Famicom", 76, 166, -81 },
        { "gamecube", "GameCube", 70, 10, -109 },
        { "genesis", "Genesis", 68, 86, -109 },
        { "ps1", "PS1", 78, 160, -109 },
        { "ps2", "PS2", 70, 10, -137 },
        { "xbox", "Xbox", 68, 86, -137 },
        { "xbox360", "Xbox 360", 78, 160, -137 },
        { "violetmist", "Violet Mist", 100, 10, -165 },
        { "violetbloom", "Violet Bloom", 120, 116, -165 },
        { "legacy", "Blizzard Legacy", 228, 10, -193 },
    }
    for _, option in ipairs(appearanceOptions) do
        local theme, label, width, x, y = option[1], option[2], option[3], option[4], option[5]
        local choice = Button(display, label, width, 22)
        choice:SetPoint("TOPLEFT", x, y)
        local choiceMark = choice:CreateTexture(nil, "OVERLAY")
        choiceMark:SetPoint("BOTTOMLEFT", 4, 2); choiceMark:SetPoint("BOTTOMRIGHT", -4, 2)
        choiceMark:SetHeight(2); ThemeSolid(choiceMark, C.teal)
        choice.ThemeMark = choiceMark
        choice:SetScript("OnClick", function() UI:SetAppearanceTheme(theme) end)
        self.appearanceButtons[theme] = choice
    end
    local ds = Font(display, 10, C.muted); ds:SetPoint("TOPLEFT", 10, -233); ds:SetText("Scale")
    local dsm = IconButton(display, "−", 20); dsm:SetPoint("TOPLEFT", 65, -226); dsm:SetScript("OnClick", function() UI:SetVisualSetting("uiScale", -0.05) end)
    self.displayScaleValue = Font(display, 9, C.text); self.displayScaleValue:SetWidth(42); self.displayScaleValue:SetJustifyH("CENTER"); self.displayScaleValue:SetPoint("LEFT", dsm, "RIGHT", 3, 0)
    local dsp = IconButton(display, "+", 20); dsp:SetPoint("TOPLEFT", 138, -226); dsp:SetScript("OnClick", function() UI:SetVisualSetting("uiScale", 0.05) end)
    local di = Font(display, 10, C.muted); di:SetPoint("TOPLEFT", 10, -264); di:SetText("Icons")
    local dim = IconButton(display, "−", 20); dim:SetPoint("TOPLEFT", 65, -257); dim:SetScript("OnClick", function() UI:SetVisualSetting("iconSize", -2) end)
    self.displayIconValue = Font(display, 9, C.text); self.displayIconValue:SetWidth(42); self.displayIconValue:SetJustifyH("CENTER"); self.displayIconValue:SetPoint("LEFT", dim, "RIGHT", 3, 0)
    local dip = IconButton(display, "+", 20); dip:SetPoint("TOPLEFT", 138, -257); dip:SetScript("OnClick", function() UI:SetVisualSetting("iconSize", 2) end)
    self:RefreshAppearanceSelector()
    menuButton:SetScript("OnClick", function(self)
        UI:ToggleHeaderMenu(self, display)
    end)
    self.displayPopover = display
    local newCard = Button(header, "+ Card", 56, 24, "primary"); newCard:SetPoint("LEFT", self.profileName, "RIGHT", 7, 0)
    newCard:SetScript("OnClick", function() UI:AddCard(nil) end)
    self.binderMode = Button(header, "Binder", 48, 22); self.binderMode:SetPoint("LEFT", newCard, "RIGHT", 5, 0)
    self.binderMode:SetScript("OnClick", function() UI:ApplyWorkspaceMode("binder") end)
    self.panelMode = Button(header, "Panel", 44, 22); self.panelMode:SetPoint("LEFT", self.binderMode, "RIGHT", 3, 0)
    self.panelMode:SetScript("OnClick", function() UI:ApplyWorkspaceMode("panel") end)

    local nav = CreateFrame("Frame", nil, f, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", 10, -61); nav:SetPoint("BOTTOMLEFT", 10, 35); nav:SetWidth(178)
    Skin(nav, C.panel, C.faint)
    local navTitle = Font(nav, 11, C.muted)
    navTitle:SetPoint("TOPLEFT", 12, -11); navTitle:SetText("CARD STACK")
    self.navTitle = navTitle
    local addRoot = IconButton(nav, "+", 23)
    addRoot:SetPoint("TOPRIGHT", -8, -6)
    addRoot:SetScript("OnClick", function() UI:AddCard(nil) end)
    local navLine = Divider(nav); navLine:SetPoint("TOPLEFT", 8, -37); navLine:SetPoint("RIGHT", -8, 0)
    local scroll = CreateFrame("ScrollFrame", nil, nav)
    scroll:SetPoint("TOPLEFT", 5, -42); scroll:SetPoint("BOTTOMRIGHT", -5, 6)
    scroll:EnableMouseWheel(true)
    local navContent = CreateFrame("Frame", nil, scroll)
    navContent:SetWidth(166); navContent:SetHeight(1)
    scroll:SetScrollChild(navContent)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        self:SetVerticalScroll(min(range, max(0, self:GetVerticalScroll() - delta * 36)))
    end)
    self.navContent, self.navRows = navContent, {}
    self.navPanel = nav
    self.emptyNav = Font(navContent, 11, C.muted)
    self.emptyNav:SetPoint("TOPLEFT", 10, -14); self.emptyNav:SetText("No cards")

    local center = CreateFrame("Frame", nil, f, "BackdropTemplate")
    center:SetPoint("TOPLEFT", nav, "TOPRIGHT", 8, 0); center:SetPoint("BOTTOMRIGHT", -226, 35)
    center:SetBackdrop(nil)
    self.centerPanel = center
    local centerBackdrop = CreateFrame("Frame", nil, center, "BackdropTemplate")
    centerBackdrop:SetAllPoints(center)
    centerBackdrop:SetFrameLevel(center:GetFrameLevel())
    centerBackdrop:EnableMouse(false)
    Skin(centerBackdrop, C.paperAlt, C.faint)
    self.centerBackdrop = centerBackdrop
    self.cardArea = CreateFrame("Frame", nil, center)
    self.cardArea.bindCardsCardSurface = true
    self.cardArea:SetAllPoints()
    self.cardTitle = Font(self.cardArea, 20, C.text)
    self.cardTitle:SetPoint("TOPLEFT", 17, -15)
    self.cardStatus = Font(self.cardArea, 9, C.teal)
    self.cardStatus:SetPoint("TOPLEFT", self.cardTitle, "BOTTOMLEFT", 0, -6)
    self.cardReason = Font(self.cardArea, 10, C.muted)
    self.cardReason:SetPoint("LEFT", self.cardStatus, "RIGHT", 9, 0)
    self.inherited = Font(self.cardArea, 9, C.blue)
    self.inherited:SetPoint("TOPRIGHT", -15, -19)
    self.inherited:SetText("Inherits")
    local staple = self.cardArea:CreateTexture(nil, "ARTWORK")
    staple:SetSize(16, 3); staple:SetPoint("RIGHT", self.inherited, "LEFT", -6, 0); ThemeSolid(staple, C.blueSoft)
    self.renameButton = IconButton(self.cardArea, "✎", 24)
    self.renameButton:SetPoint("TOPRIGHT", -15, -43)
    self.renameButton:SetScript("OnClick", function() local card = UI:GetSelectedCard(); if card then UI:RenameCard(card) end end)
    self.addSubButton = Button(self.cardArea, "+ Subcard", 76, 24)
    self.addSubButton:SetPoint("RIGHT", self.renameButton, "LEFT", -6, 0)
    self.addSubButton:SetScript("OnClick", function() local card = UI:GetSelectedCard(); if card then UI:AddCard(CardID(card)) end end)
    local gridTools = CreateFrame("Frame", nil, self.cardArea)
    gridTools:SetPoint("TOPLEFT", 14, -72); gridTools:SetPoint("TOPRIGHT", -14, -72); gridTools:SetHeight(28)
    local less = IconButton(gridTools, "−", 24); less:SetPoint("LEFT")
    less:SetScript("OnClick", function() UI:SetColumns(-1) end)
    self.columnValue = Font(gridTools, 10, C.muted); self.columnValue:SetPoint("LEFT", less, "RIGHT", 8, 0)
    local more = IconButton(gridTools, "+", 24); more:SetPoint("LEFT", self.columnValue, "RIGHT", 8, 0)
    more:SetScript("OnClick", function() UI:SetColumns(1) end)
    local addMacro = Button(gridTools, "+ Macro", 68, 23)
    addMacro:SetPoint("RIGHT")
    addMacro:SetScript("OnClick", function() local card = UI:GetSelectedCard(); if card then UI:ShowMacroDialog(card) end end)
    local gridScroll = CreateFrame("ScrollFrame", nil, self.cardArea)
    gridScroll:SetPoint("TOPLEFT", 10, -108); gridScroll:SetPoint("BOTTOMRIGHT", -6, 8)
    gridScroll:EnableMouseWheel(true)
    local gridContent = CreateFrame("Frame", nil, gridScroll)
    gridContent:SetWidth(490); gridContent:SetHeight(1)
    gridScroll:SetScrollChild(gridContent)
    gridScroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(min(self:GetVerticalScrollRange(), max(0, self:GetVerticalScroll() - delta * 48)))
    end)
    self.gridScroll, self.gridContent, self.tiles = gridScroll, gridContent, {}
    self.welcome = Font(center, 14, C.muted)
    self.welcome:SetPoint("CENTER", 0, 8); self.welcome:SetText("Create a card to begin")
    self.cardArea:Hide()
    self.welcome:Hide()

    local binderBar = CreateFrame("Frame", nil, center, "BackdropTemplate")
    binderBar:SetPoint("TOPLEFT", 5, -5); binderBar:SetPoint("TOPRIGHT", -5, -5); binderBar:SetHeight(30)
    binderBar:SetBackdrop(nil)
    self.binderBar = binderBar
    local function BinderSelector(label, width)
        local button = CreateFrame("Button", nil, binderBar, "BackdropTemplate")
        button.bindCardsTopSurface = true
        button:SetSize(width, 25); Skin(button, C.paperAlt, C.faint)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(15, 15); button.icon:SetPoint("LEFT", 7, 0)
        button.Icon = button.icon
        button.label = Font(button, 11, C.text)
        button.label:SetPoint("LEFT", button.icon, "RIGHT", 7, 0); button.label:SetPoint("RIGHT", -20, 0)
        button.label:SetText(label)
        button.dot = button:CreateTexture(nil, "ARTWORK")
        button.dot:SetTexture(EDGE); button.dot:SetSize(6, 6); button.dot:SetPoint("RIGHT", -8, 0)
        button.Dot = button.dot
        button:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.blue)) end)
        button:SetScript("OnLeave", function() UI:RefreshBinderSelectors() end)
        UI.themeButtons[#UI.themeButtons + 1] = button
        UI.themeIcons[#UI.themeIcons + 1] = { texture = button.icon }
        return button
    end
    self.generalBinder = BinderSelector("GENERAL", 160)
    self.generalBinder.bindCardsBinderKey = "general"
    self.generalBinder:SetPoint("LEFT", 2, 0)
    self.generalBinder:SetScript("OnClick", function()
        if not UI.suppressClick then UI:SelectBinder("general") end
    end)
    self.classBinder = BinderSelector("CLASS", 160)
    self.classBinder.bindCardsBinderKey = "class"
    self.classBinder:SetPoint("LEFT", self.generalBinder, "RIGHT", 5, 0)
    self.classBinder:SetScript("OnClick", function()
        if not UI.suppressClick then UI:SelectBinder("class") end
    end)
    -- Third tab: this character's own card (racials, professions, anything).
    self.characterBinder = BinderSelector("CHARACTER", 160)
    self.characterBinder.bindCardsBinderKey = "character"
    self.characterBinder:SetPoint("LEFT", self.classBinder, "RIGHT", 5, 0)
    self.characterBinder:SetScript("OnClick", function()
        if not UI.suppressClick then UI:SelectBinder("character") end
    end)

    local workspaceScroll = CreateFrame("ScrollFrame", nil, center)
    workspaceScroll:SetPoint("TOPLEFT", 5, -39); workspaceScroll:SetPoint("BOTTOMRIGHT", -14, 5)
    workspaceScroll:EnableMouseWheel(true)
    local workspaceContent = CreateFrame("Frame", nil, workspaceScroll)
    workspaceContent:SetWidth(500); workspaceContent:SetHeight(1)
    workspaceScroll:SetScrollChild(workspaceContent)
    workspaceScroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetHorizontalScroll(0)
        self:SetVerticalScroll(min(self:GetVerticalScrollRange(), max(0, self:GetVerticalScroll() - delta * 52)))
        UI:UpdateWorkspaceScrollbars()
    end)
    workspaceScroll:SetScript("OnEnter", function() UI:SetBinderResizeHover(true) end)
    workspaceScroll:SetScript("OnLeave", function() UI:SetBinderResizeHover(false) end)
    self.workspaceScroll, self.workspaceContent, self.cardViews = workspaceScroll, workspaceContent, {}
    local vbar = CreateFrame("Slider", nil, center, "BackdropTemplate")
    vbar:SetOrientation("VERTICAL"); vbar:SetPoint("TOPRIGHT", -3, -7); vbar:SetPoint("BOTTOMRIGHT", -3, 5); vbar:SetWidth(8)
    vbar:SetValueStep(1); vbar:SetObeyStepOnDrag(false); Skin(vbar, C.paperAlt, C.faint)
    vbar:SetThumbTexture(EDGE)
    local vthumb = vbar:GetThumbTexture(); ThemeSolid(vthumb, C.muted); vthumb:SetSize(8, 30)
    vbar:SetScript("OnValueChanged", function(_, value) workspaceScroll:SetVerticalScroll(value) end); vbar:Hide()
    local hbar = CreateFrame("Slider", nil, center, "BackdropTemplate")
    hbar:SetOrientation("HORIZONTAL"); hbar:SetPoint("BOTTOMLEFT", 7, 4); hbar:SetPoint("BOTTOMRIGHT", -17, 4); hbar:SetHeight(8)
    hbar:SetValueStep(1); hbar:SetObeyStepOnDrag(false); Skin(hbar, C.paperAlt, C.faint)
    hbar:SetThumbTexture(EDGE)
    local hthumb = hbar:GetThumbTexture(); ThemeSolid(hthumb, C.muted); hthumb:SetSize(30, 8)
    hbar:SetScript("OnValueChanged", function(_, value) workspaceScroll:SetHorizontalScroll(value) end); hbar:Hide()
    self.workspaceVBar, self.workspaceHBar = vbar, hbar
    self.workspaceEmpty = Font(workspaceContent, 13, C.muted)
    self.workspaceEmpty:SetPoint("TOPLEFT", 18, -18); self.workspaceEmpty:SetText("No cards")

    local rail = CreateFrame("Frame", nil, f, "BackdropTemplate")
    rail:SetPoint("TOPRIGHT", -10, -61); rail:SetPoint("BOTTOMRIGHT", -10, 35); rail:SetWidth(178)
    Skin(rail, C.panel, C.faint)
    self.rightPanel = rail
    local railTitle = Font(rail, 11, C.muted); railTitle:SetPoint("TOPLEFT", 12, -11); railTitle:SetText("CARD RULES")
    local conditionDefs = {
        { "class", "Class" }, { "spec", "Build" }, { "form", "Form" }, { "content", "Content" },
    }
    self.conditionOptions = {
        class = { "Any class", "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" },
        spec = { "Any build", "Primary", "Secondary" },
        content = { "Any content", "PVE", "PVP" },
        form = { "Any form" },
    }
    self.conditionControls = {}
    self.conditionControlOrder = {}
    for i, def in ipairs(conditionDefs) do
        self.conditionControlOrder[#self.conditionControlOrder + 1] = def[1]
        local control = CreateFrame("Button", nil, rail, "BackdropTemplate")
        control:SetPoint("TOPLEFT", 9, -35 - (i - 1) * 43); control:SetPoint("RIGHT", -9, 0); control:SetHeight(36)
        Skin(control, C.paperAlt, C.faint)
        control.label = Font(control, 9, C.muted); control.label:SetPoint("TOPLEFT", 8, -5); control.label:SetText(def[2])
        control.value = Font(control, 10, C.text); control.value:SetPoint("BOTTOMLEFT", 8, 5); control.value:SetPoint("RIGHT", -18, 0)
        local caret = Font(control, 10, C.muted); caret:SetPoint("RIGHT", -7, -5); caret:SetText("›")
        control:SetScript("OnClick", function(self) local card = UI:GetSelectedCard(); if card then UI:ShowConditionMenu(self, card, def[1]) end end)
        control:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.blue)) end)
        control:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.faint)) end)
        self.conditionControls[def[1]] = control
    end
    local conditionHint = Font(rail, 9, C.muted)
    conditionHint:SetPoint("TOPLEFT", 12, -253); conditionHint:SetPoint("RIGHT", -12, 0)
    conditionHint:SetText("Subcards inherit parent rules.")
    local visualTitle = Font(rail, 9, C.muted)
    visualTitle:SetPoint("TOPLEFT", 12, -278); visualTitle:SetText("WORKSPACE")
    local scaleLess = IconButton(rail, "−", 20); scaleLess:SetPoint("TOPLEFT", 10, -294)
    scaleLess:SetScript("OnClick", function() UI:SetVisualSetting("uiScale", -0.05) end)
    self.scaleValue = Font(rail, 9, C.text); self.scaleValue:SetPoint("LEFT", scaleLess, "RIGHT", 5, 0); self.scaleValue:SetWidth(34); self.scaleValue:SetJustifyH("CENTER")
    local scaleMore = IconButton(rail, "+", 20); scaleMore:SetPoint("LEFT", self.scaleValue, "RIGHT", 5, 0)
    scaleMore:SetScript("OnClick", function() UI:SetVisualSetting("uiScale", 0.05) end)
    local scaleLabel = Font(rail, 9, C.muted); scaleLabel:SetPoint("LEFT", scaleMore, "RIGHT", 5, 0); scaleLabel:SetText("Scale")
    local iconLess = IconButton(rail, "−", 20); iconLess:SetPoint("TOPLEFT", 10, -319)
    iconLess:SetScript("OnClick", function() UI:SetVisualSetting("iconSize", -2) end)
    self.iconValue = Font(rail, 9, C.text); self.iconValue:SetPoint("LEFT", iconLess, "RIGHT", 5, 0); self.iconValue:SetWidth(34); self.iconValue:SetJustifyH("CENTER")
    local iconMore = IconButton(rail, "+", 20); iconMore:SetPoint("LEFT", self.iconValue, "RIGHT", 5, 0)
    iconMore:SetScript("OnClick", function() UI:SetVisualSetting("iconSize", 2) end)
    local iconLabel = Font(rail, 9, C.muted); iconLabel:SetPoint("LEFT", iconMore, "RIGHT", 5, 0); iconLabel:SetText("Icons")
    self.emptyRight = Font(rail, 11, C.muted)
    self.emptyRight:SetPoint("TOPLEFT", 12, -353); self.emptyRight:SetPoint("RIGHT", -12, 0)
    self.emptyRight:SetText("Click an ability for settings.")
    self.entryPanel = CreateFrame("Frame", "BindCardsAbilityInspector", UIParent, "BackdropTemplate")
    self.entryPanel:SetSize(190, 180)
    self.entryPanel:SetClampedToScreen(true)
    self.entryPanel:SetMovable(true)
    self.entryPanel:SetToplevel(true)
    self.entryPanel:SetFrameStrata("DIALOG")
    self.entryPanel:SetFrameLevel(700)
    self.entryPanel:EnableMouse(true)
    local inspectorSettings = BindCardsDB and BindCardsDB.settings or {}
    self.entryPanel:SetScale(tonumber(inspectorSettings.uiScale) or 1)
    if type(inspectorSettings.entryInspectorX) == "number" and
        type(inspectorSettings.entryInspectorY) == "number" then
        self.entryPanel:SetPoint("CENTER", UIParent, "CENTER",
            inspectorSettings.entryInspectorX, inspectorSettings.entryInspectorY)
    else
        self.entryPanel:SetPoint("CENTER", UIParent, "CENTER", 280, -20)
    end
    Skin(self.entryPanel, C.window, C.blueSoft)
    local inspectorHeader = CreateFrame("Frame", nil, self.entryPanel)
    inspectorHeader:SetPoint("TOPLEFT", 1, -1); inspectorHeader:SetPoint("TOPRIGHT", -27, -1)
    inspectorHeader:SetHeight(27); inspectorHeader:EnableMouse(true); inspectorHeader:RegisterForDrag("LeftButton")
    inspectorHeader:SetScript("OnDragStart", function()
        if InCombat() then return end
        UI.entryPanel:StartMoving()
    end)
    inspectorHeader:SetScript("OnDragStop", function()
        UI.entryPanel:StopMovingOrSizing()
        local x, y = UI.entryPanel:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        if x and y and parentX and parentY and not (issecretvalue and
            (issecretvalue(x) or issecretvalue(y) or issecretvalue(parentX) or issecretvalue(parentY))) then
            BindCardsDB.settings.entryInspectorX = x - parentX
            BindCardsDB.settings.entryInspectorY = y - parentY
        end
    end)
    local inspectorLabel = Font(inspectorHeader, 9, C.muted)
    inspectorLabel:SetPoint("LEFT", 9, 0); inspectorLabel:SetText("ABILITY SETTINGS")
    local inspectorClose = IconButton(self.entryPanel, "×", 22)
    inspectorClose:SetPoint("TOPRIGHT", -4, -4)
    inspectorClose:SetScript("OnClick", function()
        UI.entryInspectorDismissed = true
        UI.entryPanel:Hide()
        UI.emptyRight:Show()
    end)
    self.entryInspectorClose = inspectorClose
    self.entryTitle = Font(self.entryPanel, 12, C.text)
    self.entryTitle:SetPoint("TOPLEFT", 10, -35); self.entryTitle:SetPoint("TOPRIGHT", -10, -35)
    self.entryBinding = Font(self.entryPanel, 9, C.blue)
    self.entryBinding:SetPoint("TOPLEFT", self.entryTitle, "BOTTOMLEFT", 0, -7)
    local bind = Button(self.entryPanel, "Set binding", 102, 24, "primary"); bind:SetPoint("TOPLEFT", 10, -79)
    bind:SetScript("OnClick", function() local card = UI:GetSelectedCard(); if card and UI.focusedEntry then UI:BeginBindCapture(card, UI.focusedEntry) end end)
    local clear = Button(self.entryPanel, "Clear", 62, 24); clear:SetPoint("LEFT", bind, "RIGHT", 6, 0)
    clear:SetScript("OnClick", function() local card = UI:GetSelectedCard(); if card and UI.focusedEntry then UI:SetEntryBinding(card, UI.focusedEntry, nil) end end)
    local editMacro = Button(self.entryPanel, "Edit macro", 102, 24); editMacro:SetPoint("TOPLEFT", bind, "BOTTOMLEFT", 0, -7)
    self.entryMacroButton = editMacro
    editMacro:SetScript("OnClick", function() local card = UI:GetSelectedCard(); if card then UI:CardMacroAction(card) end end)
    local entryIcon = Button(self.entryPanel, "Icon ID", 62, 24); entryIcon:SetPoint("LEFT", editMacro, "RIGHT", 6, 0)
    self.entryIconButton = entryIcon
    entryIcon:SetScript("OnClick", function() UI:EditEntryIcon(UI.focusedEntry) end)
    local remove = Button(self.entryPanel, "Remove", 170, 24, "danger"); remove:SetPoint("TOPLEFT", editMacro, "BOTTOMLEFT", 0, -7)
    remove:SetScript("OnClick", function()
        local card, entry = UI:GetSelectedCard(), UI.focusedEntry
        if card and entry then UI:Confirm("Remove " .. EntryLabel(entry) .. "?", "This removes the tile and its bindings.", function()
            UI:DeleteEntry(card, entry); UI.focusedEntry = nil; UI.entryInspectorDismissed = true
            UI.entryPanel:Hide(); UI.emptyRight:Show()
        end) end
    end)
    self.entryPanel:Hide()
    local deleteCard = Button(rail, "Delete card", 86, 24, "danger")
    deleteCard:SetPoint("BOTTOMRIGHT", -9, 9)
    deleteCard:SetScript("OnClick", function() local card = UI:GetSelectedCard(); if card then UI:DeleteCard(card) end end)
    self.deleteCardButton = deleteCard
    self.workspaceDrop = CreateFrame("Frame", nil, f, "BackdropTemplate")
    self.workspaceDrop:SetAlpha(0.30)
    self.workspaceDrop:SetSize(160, 62)
    self.workspaceDrop:SetPoint("TOPLEFT", binderBar, "BOTTOMLEFT", 2, -4)
    self.workspaceDrop:SetFrameStrata("DIALOG")
    self.workspaceDrop:SetFrameLevel(center:GetFrameLevel() + 8); Skin(self.workspaceDrop, { 0.08, 0.16, 0.21, 0.62 }, C.blue)
    local dropText = Font(self.workspaceDrop, 11, C.text); dropText:SetPoint("CENTER"); dropText:SetWidth(140); dropText:SetJustifyH("CENTER"); dropText:SetText("Return to main binder")
    self.workspaceDropText = dropText
    self.workspaceDrop:SetScript("OnUpdate", function(self)
        local over = CursorInside(self)
        if self.wasOver == over then return end
        self.wasOver = over
        Skin(self, over and { 0.05, 0.20, 0.13, 0.72 } or { 0.04, 0.14, 0.10, 0.55 }, C.drop)
    end)
    self.workspaceDrop:Hide()

    self.quickBanner = CreateFrame("Frame", nil, f)
    self.quickBanner:Hide()

    self.resizeCapture = CreateFrame("Frame", nil, f)
    self.resizeCapture:SetAllPoints(f)
    self.resizeCapture:SetFrameLevel(f:GetFrameLevel() + 2)
    self.resizeCapture:Hide()
    self.resizeCapture:EnableKeyboard(false)
    self.resizeCapture:SetScript("OnUpdate", function()
        if UI.gridResize then UI:UpdateGridResize() end
        if UI.cardResize then UI:UpdateCardResize() end
        if UI.windowResizing and IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            UI:FinishWindowResize(false)
        end
    end)

    local windowGrip = CreateFrame("Button", nil, f, "BackdropTemplate")
    windowGrip:SetSize(18, 18); windowGrip:SetPoint("BOTTOMRIGHT", -2, 2)
    windowGrip:SetFrameLevel(f:GetFrameLevel() + 12); Skin(windowGrip, C.paperAlt, C.faint)
    windowGrip.resizeArt = AddResizeGripArt(windowGrip)
    local function FinishWindowResize()
        UI:FinishWindowResize(false)
    end
    -- Attached only for the duration of a resize; detaches itself afterwards.
    local function TrackWindowResize(self)
        local state = UI.windowResizing
        if not state then self:SetScript("OnUpdate", nil); return end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then FinishWindowResize(); return end
        local width, height = f:GetWidth(), f:GetHeight()
        if math.abs(width - state.width) >= 2 or math.abs(height - state.height) >= 2 then
            state.width, state.height = width, height
        end
    end
    windowGrip:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    windowGrip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or InCombat() then return end
        if UI.windowResizing then UI:FinishWindowResize(true) end
        UI.windowResizeFinishToken = nil
        UI.resizeHoverToken = (UI.resizeHoverToken or 0) + 1
        UI.windowResizing = {
            width = f:GetWidth(), height = f:GetHeight(),
            mode = BindCardsDB.settings.workspaceMode == "panel" and "panel" or "binder",
        }
        if UI.resizeCapture then UI.resizeCapture:Show() end
        windowGrip:Show()
        windowGrip:SetScript("OnUpdate", TrackWindowResize)
        f:StartSizing("BOTTOMRIGHT")
    end)
    windowGrip:SetScript("OnMouseUp", FinishWindowResize)
    windowGrip:SetScript("OnDoubleClick", function()
        if BindCardsDB.settings.workspaceMode == "panel" then return end
        BindCardsDB.settings.binderManualSize = false
        UI:RefreshWorkspace()
        UI:SetStatus("Binder fitted.", "success")
    end)
    windowGrip:SetScript("OnEnter", function(self)
        UI:SetBinderResizeHover(true)
        self:SetBackdropBorderColor(unpack(C.teal))
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Resize binder")
        GameTooltip:AddLine("Drag to resize · Double-click to fit", unpack(C.muted))
        GameTooltip:Show()
    end)
    windowGrip:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(C.faint)); GameTooltip:Hide(); UI:SetBinderResizeHover(false)
    end)
    self.windowResizeGrip = windowGrip

    self.statusText = Font(f, 10, C.muted)
    self.statusText:SetPoint("BOTTOMLEFT", 13, 12); self.statusText:SetPoint("RIGHT", windowGrip, "LEFT", -5, 0)
    self.statusText:SetText("Drop spells, items, toys, mounts, or macros into any open cell.")
    f:EnableKeyboard(false)
    f:SetScript("OnShow", function()
        UI:EndTransientInteraction()
        UI:RequestRefresh()
        if not UI.keyboardGuardTicker and C_Timer and C_Timer.NewTicker then
            UI.keyboardGuardTicker = C_Timer.NewTicker(0.10, function() UI:GuardKeyboardFocus() end)
        end
    end)
    f:SetScript("OnHide", function()
        UI:RememberSpellbookClose()
        UI:SaveWindowPlacement(false)
        UI:SaveRememberedSelection()
        if UI.entryPanel then UI.entryPanel:Hide() end
        UI.entryInspectorDismissed = true
        if UI.keyboardGuardTicker then UI.keyboardGuardTicker:Cancel(); UI.keyboardGuardTicker = nil end
        UI:EndTransientInteraction()
        if UI.profileTransfer then
            UI.profileTransfer.returnToManager = false
            UI.profileTransfer:Hide()
            UI.profileTransfer.overlay:Hide()
        end
        if UI.profileManager then UI.profileManager:Hide() end
        for _, view in pairs(UI.cardViews or {}) do view:Hide(); view.tab:Hide() end
        for _, sheets in pairs(UI.floatingSheets or {}) do
            for _, sheet in ipairs(sheets) do sheet:Hide() end
        end
        UI:UpdateBinderStrings()
    end)

    self:CreateModal(f)
    self:CreateCapture(f)
    self:CreateProfileManager()
    local settings = BindCardsDB and BindCardsDB.settings or {}
    local initialCap = min(1.40, (UIParent:GetWidth() or 960) / 980, (UIParent:GetHeight() or 650) / 680)
    settings.uiScale = min(initialCap, max(0.65, tonumber(settings.uiScale) or 1))
    f:SetScale(settings.uiScale)
    self:ApplyProfileDialogScale()
    self:RefreshVisualLabels()
    self:ApplyWorkspaceMode(settings.workspaceMode or "binder")
    -- Apply saved dimensions before restoring the saved center.
    self:ApplySafeWindowBounds(false)
    self:RestoreWindowPosition()
    self:Refresh()
    if self.euiSkin then self:ApplyEUITheme(self.euiSkin) end
end

function UI:Toggle()
    self:Build()
    if not self.frame then return end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        if not self.hasOpened then self:SelectInitialCard(); self.hasOpened = true end
        self:Refresh()
        self.frame:Show()
        self.frame:Raise()
    end
end

function BindCards:ToggleUI() UI:Toggle() end
function BindCards:ToggleWindow() UI:Toggle() end
function BindCards:ShowUI()
    UI:Build()
    if not UI.frame then return end
    if not UI.hasOpened then UI:SelectInitialCard(); UI.hasOpened = true end
    UI:Refresh()
    UI.frame:Show()
    UI.frame:Raise()
end
function BindCards:HideUI() if UI.frame then UI.frame:Hide() end end
function BindCards:RefreshUI() if UI.frame then UI:RequestRefresh() end end
function BindCards:SetUIStatus(message, tone) UI:SetStatus(message, tone) end

local events = CreateFrame("Frame")
local MACRO_ICON_EVENTS = {
    MODIFIER_STATE_CHANGED = true,
    PLAYER_CAN_GLIDE_CHANGED = true,
    PLAYER_IS_GLIDING_CHANGED = true,
    PLAYER_MOUNT_DISPLAY_CHANGED = true,
    UPDATE_OVERRIDE_ACTIONBAR = true,
    UPDATE_SHAPESHIFT_FORM = true,
    PLAYER_TARGET_CHANGED = true,
    PLAYER_EQUIPMENT_CHANGED = true,
    SPELLS_CHANGED = true,
    BAG_UPDATE_DELAYED = true,
    ZONE_CHANGED_NEW_AREA = true,
    PLAYER_FOCUS_CHANGED = true,
    UNIT_PET = true,
    UPDATE_STEALTH = true,
    PLAYER_FLAGS_CHANGED = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    ITEM_DATA_LOAD_RESULT = true,
    GET_ITEM_INFO_RECEIVED = true,
}
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
events:RegisterEvent("TRAIT_CONFIG_UPDATED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:RegisterEvent("UI_SCALE_CHANGED")
for event in pairs(MACRO_ICON_EVENTS) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then UI:RefreshSpellbookButton() end
    if event == "PLAYER_REGEN_ENABLED" and UI.transientCleanupPending then
        UI:EndTransientInteraction()
    end
    if event == "PLAYER_LOGOUT" then
        UI:SaveWindowPlacement(false)
        UI:SaveRememberedSelection()
        return
    end
    if MACRO_ICON_EVENTS[event] then
        local unit = (event == "UNIT_PET" or event == "PLAYER_FLAGS_CHANGED" or
            event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_STOP") and ... or nil
        local macroEditorOpen = UI.modal and UI.modal:IsShown() and
            UI.modal.macroPreview and UI.modal.activeEdit ~= nil
        if not Helpers.ShouldRefreshMacroEvent or Helpers.ShouldRefreshMacroEvent(event, unit, macroEditorOpen) then
            local firstArgument = select(1, ...)
            local itemID = (event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED") and
                tonumber(firstArgument) or nil
            if itemID and BindCards.pendingMacroItemIDs then BindCards.pendingMacroItemIDs[itemID] = nil end
            Call("InvalidateMacroIcons", event)
            UI:RequestMacroIconRefresh()
        end
        if (event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_STEALTH" or
            event == "UPDATE_OVERRIDE_ACTIONBAR" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" or
            event == "PLAYER_CAN_GLIDE_CHANGED" or event == "PLAYER_IS_GLIDING_CHANGED") and
            UI.frame and UI.frame:IsShown() then
            local winners, _, states = Call("CompileCurrentBindings")
            if type(winners) == "table" then BindCards.lastCompiledBindings = winners end
            if type(states) == "table" then BindCards.lastActiveCardStates = states end
            UI:RequestRefresh()
        end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or
        event == "PLAYER_SPECIALIZATION_CHANGED" or event == "TRAIT_CONFIG_UPDATED" or
        event == "PLAYER_ENTERING_WORLD" then
        Call("InvalidateMacroIcons", event)
        if UI.modal and UI.modal:IsShown() and UI.modal.macroPreview and UI.modal.activeEdit then
            UI:UpdateMacroPreview(UI.modal, UI.modal.activeEdit:GetText())
        end
    end
    if event == "PLAYER_LOGIN" then
        if BindCards.RegisterCallback then
            Call("RegisterCallback", "DATA_CHANGED", function(_, _, changeKind)
                if changeKind == "bindings" then UI:RefreshBindingChrome() else UI:RequestRefresh() end
                UI:RefreshProfileManager()
            end, UI)
            Call("RegisterCallback", "PROFILES_CHANGED", function()
                UI:RequestRefresh()
                UI:RefreshProfileManager()
            end, UI)
            Call("RegisterCallback", "PROFILE_SELECTED", function(_, profileId, binderId)
                UI:HandleProfileSetSelected(profileId, binderId)
                UI:RefreshProfileManager()
            end, UI)
            Call("RegisterCallback", "SETTINGS_CHANGED", function(_, settings)
                local theme = settings and settings.theme or UI:GetAppearanceTheme()
                if UI.appliedAppearanceTheme ~= theme then UI:ApplyAppearanceTheme(theme, true)
                else UI:RequestRefresh() end
            end, UI)
            Call("RegisterCallback", "BINDINGS_APPLIED", function() UI:RefreshBindingChrome() end, UI)
            Call("RegisterCallback", "GAMEPAD_BINDINGS_UPDATED", function() UI:RefreshBindingChrome() end, UI)
            Call("RegisterCallback", "BINDINGS_CONFLICTS", function() UI:RefreshBindingChrome() end, UI)
            Call("RegisterCallback", "NOTIFICATION", function(_, message) UI:SetStatus(message, "info") end, UI)
        end
    elseif (event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED") and UI.frame then
        UI:ApplySafeWindowBounds(false)
        UI:ApplyProfileDialogScale()
        UI:RequestRefresh()
    elseif event == "PLAYER_REGEN_DISABLED" and UI.frame then
        if UI.frame:IsShown() then UI:EndTransientInteraction("Combat lockdown: editing and binding are paused.") end
        UI:RequestRefresh()
    elseif UI.frame then
        UI:RequestRefresh()
    end
end)
