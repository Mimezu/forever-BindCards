-- Ways in: the window key (a normal game binding), a minimap button and a
-- page in the game's Settings > AddOns. Card bindings stay in Bindings.lua.
local BindCards = _G.BindCards
if not BindCards then return end

local TITLE = "BindCards"
local ACTION = "BINDCARDS_TOGGLE"
BINDING_CATEGORY_BINDCARDS = TITLE
BINDING_NAME_BINDCARDS_TOGGLE = "Open or close BindCards"

local function InCombat() return InCombatLockdown and InCombatLockdown() end
local function Settings_()
    return BindCardsDB and type(BindCardsDB.settings) == "table" and BindCardsDB.settings or {}
end

-- Window key ---------------------------------------------------------------

function BindCards:GetWindowKey()
    return GetBindingKey and GetBindingKey(ACTION) or nil
end

function BindCards:GetWindowKeyText()
    local key = self:GetWindowKey()
    if not key then return "Not set" end
    return GetBindingText and GetBindingText(key) or key
end

-- key nil clears. Replaces the key's old action and says so.
function BindCards:SetWindowKey(key)
    if InCombat() or not SetBinding then
        self:Notify("Keys can't change in combat.")
        return nil, "combat"
    end
    for _, old in ipairs({ GetBindingKey and GetBindingKey(ACTION) }) do SetBinding(old) end
    if key then
        local previous = GetBindingAction and GetBindingAction(key) or ""
        SetBinding(key, ACTION)
        local text = GetBindingText and GetBindingText(key) or key
        if type(previous) == "string" and previous ~= "" and previous ~= ACTION then
            self:Notify(text .. " no longer does \"" .. (_G["BINDING_NAME_" .. previous] or previous) .. "\".")
        end
        local card = self.GetProfileBindingConflict and self:GetProfileBindingConflict(key)
        if card then self:Notify(text .. " is also on " .. tostring(card) .. "; the card wins.") end
    end
    if SaveBindings then SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1) end
    return true
end

local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true, UNKNOWN = true }
local capture, captureDone

function BindCards:StopWindowKeyCapture()
    if not capture or not capture:IsShown() then return end
    capture:Hide()
    local done = captureDone
    captureDone = nil
    if done then done() end
end

-- Listens for the next key: Esc cancels, held modifiers combine.
function BindCards:StartWindowKeyCapture(onDone)
    if InCombat() then self:Notify("Keys can't change in combat."); return false end
    if not capture then
        capture = CreateFrame("Frame", "BindCardsWindowKeyCapture", UIParent)
        capture:SetFrameStrata("TOOLTIP")
        capture:SetSize(1, 1)
        capture:SetPoint("CENTER")
        capture:Hide()
        capture:SetScript("OnKeyDown", function(_, key)
            if MODIFIER_KEYS[key] then return end
            if key ~= "ESCAPE" then
                local prefix = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") ..
                    (IsShiftKeyDown() and "SHIFT-" or "")
                BindCards:SetWindowKey(prefix .. key)
            end
            BindCards:StopWindowKeyCapture()
        end)
        -- Combat would make SetBinding fail; stop listening.
        capture:RegisterEvent("PLAYER_REGEN_DISABLED")
        capture:SetScript("OnEvent", function() BindCards:StopWindowKeyCapture() end)
    end
    self:StopWindowKeyCapture()
    captureDone = onDone
    capture:Show()
    capture:EnableKeyboard(true)
    if capture.SetPropagateKeyboardInput then capture:SetPropagateKeyboardInput(false) end
    return true
end

function BindCards:IsCapturingWindowKey()
    return capture ~= nil and capture:IsShown()
end

-- Minimap button -----------------------------------------------------------

local ICON = "Interface\\AddOns\\BindCards\\Assets\\BindCardsIcon"
local button

local function PlaceButton()
    if not button or not Minimap then return end
    local angle = math.rad(tonumber(Settings_().minimapAngle) or 200)
    local radius = (Minimap:GetWidth() or 140) / 2 + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
    Settings_().minimapAngle = angle
    PlaceButton()
end

local function BuildButton()
    if button or not Minimap then return end
    button = CreateFrame("Button", "BindCardsMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local back = button:CreateTexture(nil, "BACKGROUND")
    back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    back:SetSize(20, 20)
    back:SetPoint("TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    button.icon = icon
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    button:SetScript("OnClick", function() BindCards:ToggleWindow() end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", FollowCursor) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(TITLE)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

function BindCards:RefreshMinimapButton()
    local shown = Settings_().minimapIcon ~= false
    if shown then BuildButton() end
    if not button then return end
    PlaceButton()
    button:SetShown(shown)
    if self.settingsPage and self.settingsPage.Refresh then self.settingsPage:Refresh() end
end

function BindCards:SetMinimapIconShown(shown)
    Settings_().minimapIcon = shown and true or false
    self:RefreshMinimapButton()
end

function BindCards:GetMinimapButton() return button end

-- Settings > AddOns page ---------------------------------------------------

local function RegisterSettingsPage()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    BindCards.settingsPage = panel
    local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 16, -16)
    heading:SetText(TITLE)

    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(120, 26)
    open:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -14)
    open:SetText("Open")
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        BindCards:ShowUI()
    end)
    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", open, "RIGHT", 10, 0)
    hint:SetText("/bc")

    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", open, "BOTTOMLEFT", -2, -14)
    local checkLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    checkLabel:SetPoint("LEFT", check, "RIGHT", 4, 0)
    checkLabel:SetText("Minimap icon")
    check:SetScript("OnClick", function(self) BindCards:SetMinimapIconShown(self:GetChecked()) end)

    local keyLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    keyLabel:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 2, -16)
    keyLabel:SetText("Window key")
    local key = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    key:SetSize(140, 24)
    key:SetPoint("LEFT", keyLabel, "LEFT", 110, 0)
    key:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    key:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            BindCards:StopWindowKeyCapture()
            BindCards:SetWindowKey(nil)
            panel:Refresh()
        elseif BindCards:StartWindowKeyCapture(function() panel:Refresh() end) then
            key:SetText("Press a key")
        end
    end)
    key:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Right-click to clear")
        GameTooltip:Show()
    end)
    key:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    function panel:Refresh()
        check:SetChecked(Settings_().minimapIcon ~= false)
        if not BindCards:IsCapturingWindowKey() then key:SetText(BindCards:GetWindowKeyText()) end
    end
    panel:SetScript("OnShow", function(self) self:Refresh() end)
    panel:SetScript("OnHide", function() BindCards:StopWindowKeyCapture() end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, TITLE)
    Settings.RegisterAddOnCategory(category)
    BindCards.settingsCategory = category
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindCards:RefreshMinimapButton()
    local ok, err = pcall(RegisterSettingsPage)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end)
