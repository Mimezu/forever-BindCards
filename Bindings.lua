local _, BindCards = ...

local bindingOwner = CreateFrame("Frame", "BindCardsBindingOwner", UIParent)
BindCards.bindingOwner = bindingOwner
BindCards.secureButtons = BindCards.secureButtons or {}
BindCards.secureButtonTokens = BindCards.secureButtonTokens or {}

-- The Forever beta ships RestrictedExecution.lua without its native compiler.
-- Do not enter that runtime (even through pcall): Blizzard reports the error
-- before Execute returns. Secure action buttons themselves still work.
local hasRestrictedCompiler = type(loadstring_untainted) == "function"

local FORM_STATE_SNIPPET = [[
    self:ClearBindings()
    local state = newstate or "base"
    local count = self:GetAttribute("bc-count") or 0
    for index = 1, count do
        local key = self:GetAttribute("bc-key-" .. index)
        local kind = self:GetAttribute("bc-kind-" .. index .. "-" .. state)
        local value = self:GetAttribute("bc-value-" .. index .. "-" .. state)
        if not kind then
            kind = self:GetAttribute("bc-kind-" .. index .. "-base")
            value = self:GetAttribute("bc-value-" .. index .. "-base")
        end
        if key and kind == "spell" and value then
            self:SetBindingSpell(true, key, value)
        elseif key and kind == "click" and value then
            local target = self:GetAttribute("bc-click-target")
            if target then self:SetBindingClick(true, key, target, value) end
        elseif key and self:GetAttribute("bc-block-inactive-" .. index) then
            local target = self:GetAttribute("bc-click-target")
            -- This reserved token has no action attributes: form-only keys
            -- must not fall through to an unrelated normal WoW binding.
            if target then self:SetBindingClick(true, key, target, "BC_INACTIVE_FORM") end
        end
    end
]]
local APPLY_CURRENT_FORM_STATE_SNIPPET = [[
    local newstate = self:GetAttribute("state-bcform") or "base"
]] .. FORM_STATE_SNIPPET

local function GetFormBindingManager()
    if not hasRestrictedCompiler then return nil end
    if BindCards.formBindingManager then return BindCards.formBindingManager end
    if InCombatLockdown() then return nil end
    local manager = CreateFrame("Frame", "BindCardsFormBindingManager", UIParent, "SecureHandlerStateTemplate")
    if manager.SetAttributeNoHandler then manager:SetAttributeNoHandler("_onstate-bcform", FORM_STATE_SNIPPET)
    else manager:SetAttribute("_onstate-bcform", FORM_STATE_SNIPPET) end
    BindCards.formBindingManager = manager
    return manager
end

local nativeDriverFrame, nativeDriverAttributes
local function ClearNativeFormDrivers()
    if not nativeDriverFrame then return true end
    for attribute in pairs(nativeDriverAttributes or {}) do
        local ok, result = pcall(UnregisterAttributeDriver, nativeDriverFrame, attribute)
        if not ok or result == false then return false end
        if not pcall(nativeDriverFrame.SetAttribute, nativeDriverFrame, attribute, nil) then return false end
    end
    nativeDriverFrame, nativeDriverAttributes = nil, nil
    return true
end

local function ClearFormBindings()
    if InCombatLockdown() then return false end
    if not ClearNativeFormDrivers() then return false end
    local manager = BindCards.formBindingManager
    if not manager or InCombatLockdown() then return manager == nil end
    if UnregisterStateDriver then pcall(UnregisterStateDriver, manager, "bcform") end
    -- RestrictedFrames.ClearBindings delegates to this same owner API.
    local ok, result = pcall(ClearOverrideBindings, manager)
    return ok and result ~= false
end

-- A mouseover failure must not cut the rest of an apply short. xpcall keeps
-- the stack for BugSack.
local function ApplyHoverSafely(self)
    if not self.ApplyHoverBindings then return end
    local handler = geterrorhandler and geterrorhandler() or print
    xpcall(function() self:ApplyHoverBindings() end, handler)
end

local function IsHouseEditorActive()
    if not C_HouseEditor or type(C_HouseEditor.IsHouseEditorActive) ~= "function" then return false end
    local ok, active = pcall(C_HouseEditor.IsHouseEditorActive)
    if not ok or (issecretvalue and issecretvalue(active)) then return false end
    return active == true
end

function BindCards:HouseEditorOwnsBindings()
    return self.houseEditorBindingsSuspended == true or IsHouseEditorActive()
end

function BindCards:SetHouseEditorBindingSuspended(active)
    active = active == true
    if active then
        self.houseEditorBindingsSuspended = true
        -- Overrides are about to be cleared; the next install must be a full one.
        self.lastBindingSignature = nil
        if InCombatLockdown() then
            self.bindingsPending = "house-editor-opened"
            self:Fire("BINDINGS_QUEUED", self.bindingsPending)
            return false
        end
        if self.houseEditorOverridesCleared then return true end
        local ok, result = pcall(ClearOverrideBindings, bindingOwner)
        if not ok or result == false then return false end
        if not ClearFormBindings() then return false end
        self.houseEditorOverridesCleared = true
        self.lastBindingConflicts = {}
        self:Fire("BINDINGS_CONFLICTS", self.lastBindingConflicts)
        return true
    end

    local wasSuspended = self.houseEditorBindingsSuspended or self.houseEditorOverridesCleared
    self.houseEditorBindingsSuspended = false
    self.houseEditorOverridesCleared = false
    if wasSuspended then self:RequestRecompile("house-editor-closed", true) end
    return true
end

function BindCards:OnHouseEditorStateUpdated(active)
    self:SetHouseEditorBindingSuspended(active)
end

function BindCards:InstallHouseEditorBindingHook()
    if self.houseEditorBindingHookInstalled then return true end
    if not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then return false end
    local ok = pcall(EventRegistry.RegisterCallback, EventRegistry,
        "HouseEditor.StateUpdated", self.OnHouseEditorStateUpdated, self)
    if not ok then return false end
    self.houseEditorBindingHookInstalled = true
    if IsHouseEditorActive() then self:SetHouseEditorBindingSuspended(true) end
    return true
end

local function IsBindCardsBindingAction(action)
    if issecretvalue and issecretvalue(action) then return false end
    return type(action) == "string" and (
        action:match("^CLICK BindCardsBindingProxy%d*:") or
        action:match("^CLICK BindCardsBindingButton%d+:") or
        action:match("^CLICK BindCardsFormBindingManager:") or
        action:match("^CLICK BindCardsHoverKeys:")
    )
end

-- Keys claimed while the cursor is over a unit frame (HoverCast.lua).
local function IsHoverKeyAction(action)
    return type(action) == "string" and not (issecretvalue and issecretvalue(action)) and
        action:match("^CLICK BindCardsHoverKeys:") ~= nil
end

local function IsBindPadBindingAction(action)
    if issecretvalue and issecretvalue(action) then return false end
    return type(action) == "string" and action:match("^CLICK BindPad") ~= nil
end

local function GetBindPadBindingKeys()
    local keys = {}
    if not GetNumBindings or not GetBinding then return keys end
    for index = 1, GetNumBindings() do
        local command, _, key1, key2 = GetBinding(index)
        if IsBindPadBindingAction(command) then
            if type(key1) == "string" and key1 ~= "" then keys[key1] = true end
            if type(key2) == "string" and key2 ~= "" then keys[key2] = true end
        end
    end
    return keys
end

local function GetBindPadBlocker()
    if BindCards.bindPadBlocker then return BindCards.bindPadBlocker end
    if InCombatLockdown() then return nil end
    local button = CreateFrame("Button", "BindCardsBindPadBlocker", UIParent, "SecureActionButtonTemplate")
    button:EnableMouse(false)
    button:SetSize(1, 1)
    button:SetAlpha(0)
    button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -300, 98)
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:Show()
    BindCards.bindPadBlocker = button
    return button
end

function BindCards:InstallBindPadRefreshHooks()
    if self.bindPadRefreshHooksInstalled or not hooksecurefunc or not _G.BindPadCore then return end
    local core = _G.BindPadCore
    local function RefreshAfterBindPadChange()
        if BindCards.db and BindCards.db.settings and BindCards.db.settings.suspendBindPad == true then
            BindCards:RequestRecompile("bindpad-bindings-changed")
        end
    end
    local hooked = false
    for _, method in ipairs({ "DoRestoreAllKeys", "ManuallySetBinding" }) do
        if type(core[method]) == "function" then
            hooksecurefunc(core, method, RefreshAfterBindPadChange)
            hooked = true
        end
    end
    self.bindPadRefreshHooksInstalled = hooked
end

local function ReadBindingAction(key, checkOverride)
    -- Persisted controller gestures and mouseover bindings are not keys
    -- accepted by native APIs.
    if type(key) == "string" and (key:match("^GAMEPAD:") or key:match("^HOVER:")) then return "" end
    if not GetBindingAction then return "" end
    local action = GetBindingAction(key, checkOverride)
    if issecretvalue and issecretvalue(action) then return nil end
    return type(action) == "string" and action or ""
end

local MODIFIER_ORDER = { "ALT", "CTRL", "SHIFT" }
local MODIFIERS = { ALT = true, CTRL = true, SHIFT = true }
local GAMEPAD_BUTTONS = {
    PAD1 = "South", PAD2 = "East", PAD3 = "West", PAD4 = "North",
    PADDUP = "D-pad Up", PADDDOWN = "D-pad Down",
    PADDLEFT = "D-pad Left", PADDRIGHT = "D-pad Right",
}
local GAMEPAD_LAYERS = { BASE = "", LT = "LT + ", RT = "RT + ", BOTH = "LT + RT + " }

-- Semantic gestures, not WoW binding strings. Keep ALL readable for old saves;
-- new assignments identify one of the three ordinary native gameplay pages.
function BindCards:ParseGamepadShortcut(key)
    if type(key) ~= "string" then return nil end
    local scope, layer, button = key:match("^GAMEPAD:([A-Z0-9]+):([A-Z]+):(PAD[A-Z0-9]+)$")
    local page = scope and tonumber(scope:match("^BAR([123])$"))
    if scope ~= "ALL" and not page then return nil end
    if not GAMEPAD_LAYERS[layer] or not GAMEPAD_BUTTONS[button] then return nil end
    return { scope = page and "page" or "all", page = page, layer = layer:lower(), button = button }
end

function BindCards:IsGamepadShortcut(key)
    return type(key) == "string" and (key:match("^GAMEPAD:") ~= nil or
        key:match("^PAD[A-Z0-9]+$") ~= nil or key:match("%-PAD[A-Z0-9]+$") ~= nil)
end

function BindCards:MakeGamepadShortcut(button, lt, rt, page)
    page = page or 1
    if not GAMEPAD_BUTTONS[button] or (page ~= 1 and page ~= 2 and page ~= 3) then return nil end
    local layer = lt and (rt and "BOTH" or "LT") or (rt and "RT" or "BASE")
    return "GAMEPAD:BAR" .. page .. ":" .. layer .. ":" .. button
end

function BindCards:FormatGamepadShortcut(key)
    local gesture = self:ParseGamepadShortcut(key)
    if gesture then
        return (gesture.page and ("Bar " .. gesture.page) or "All bars") .. " · " ..
            GAMEPAD_LAYERS[gesture.layer:upper()] .. GAMEPAD_BUTTONS[gesture.button]
    end
    if self:IsGamepadShortcut(key) then return key end
end

function BindCards:GetGamepadBindingCapabilities()
    -- A companion state feed is informational: it cannot authorize protected
    -- rebinding, synchronise the native action icons, or yield to UI contexts.
    return { capture = true, overrides = false, scope = "page", pages = 3, status = "saved-not-active",
        reason = "Gamepad shortcuts are saved, not active. Blizzard's bindings remain in use." }
end

function BindCards:GetGamepadBindingStatus(key)
    if self:IsGamepadShortcut(key) then return self:GetGamepadBindingCapabilities().reason end
end
local NAMED_KEYS = {
    SPACE = true, TAB = true, ENTER = true, ESCAPE = true, BACKSPACE = true, DELETE = true,
    INSERT = true, HOME = true, END = true, PAGEUP = true, PAGEDOWN = true,
    UP = true, DOWN = true, LEFT = true, RIGHT = true,
    MOUSEWHEELUP = true, MOUSEWHEELDOWN = true,
    NUMPADPLUS = true, NUMPADMINUS = true, NUMPADMULTIPLY = true,
    NUMPADDIVIDE = true, NUMPADDECIMAL = true,
}
local PUNCTUATION_KEYS = { ["-"] = true, ["="] = true, [";"] = true, [","] = true,
    ["."] = true, ["/"] = true, ["["] = true, ["]"] = true, ["\\"] = true,
    ["'"] = true, ["`"] = true }

local function ValidKeyBase(base)
    if NAMED_KEYS[base] or PUNCTUATION_KEYS[base] or base:match("^[A-Z0-9]$") then return true end
    local functionNumber = tonumber(base:match("^F(%d+)$"))
    if functionNumber and functionNumber >= 1 and functionNumber <= 24 then return true end
    local numpadNumber = tonumber(base:match("^NUMPAD(%d+)$"))
    if numpadNumber and numpadNumber >= 0 and numpadNumber <= 9 then return true end
    local mouseButton = tonumber(base:match("^BUTTON(%d+)$"))
    if mouseButton and mouseButton >= 1 and mouseButton <= 31 then return true end
    return base:match("^PAD[A-Z0-9]+$") ~= nil
end

local function NormalizeInputKey(key, allowPlainPrimary)
    local modifiers, base = {}, key
    while true do
        local token, remainder = base:match("^([A-Z]+)%-(.+)$")
        if not token or not MODIFIERS[token] then break end
        if modifiers[token] then return nil end
        modifiers[token], base = true, remainder
    end
    if not ValidKeyBase(base) then return nil end
    -- Plain left/right click belong to the world and UI, except on unit frames.
    if (base == "BUTTON1" or base == "BUTTON2") and not next(modifiers) and not allowPlainPrimary then return nil end
    local normalized = {}
    for _, modifier in ipairs(MODIFIER_ORDER) do
        if modifiers[modifier] then normalized[#normalized + 1] = modifier end
    end
    normalized[#normalized + 1] = base
    return table.concat(normalized, "-")
end

-- Mouseover bindings act only while the cursor is over a unit frame of the
-- matching disposition. Saved as HOVER:<scope>:<key>, like gamepad gestures.
local HOVER_SCOPES = { HELP = "friendly", HARM = "hostile", ANY = "friendly or hostile" }

function BindCards:NormalizeKey(key)
    if type(key) ~= "string" then return nil end
    key = key:upper():gsub("%s+", "")
    if key == "" or #key > 64 then return nil end
    if self:ParseGamepadShortcut(key) then return key end
    if key:match("^HOVER:") then
        local hover = self:ParseHoverBinding(key)
        return hover and ("HOVER:" .. hover.scope .. ":" .. hover.key) or nil
    end
    return NormalizeInputKey(key, false)
end

-- Returns { scope = "HELP"|"HARM"|"ANY", key = "SHIFT-BUTTON1" } or nil.
function BindCards:ParseHoverBinding(key)
    if type(key) ~= "string" then return nil end
    local scope, inner = key:upper():gsub("%s+", ""):match("^HOVER:([A-Z]+):(.+)$")
    if not scope or not HOVER_SCOPES[scope] or self:IsGamepadShortcut(inner) then return nil end
    inner = NormalizeInputKey(inner, true)
    return inner and { scope = scope, key = inner } or nil
end

function BindCards:IsHoverBinding(key)
    return self:ParseHoverBinding(key) ~= nil
end

-- The capture window has two toggles; both on means any unit frame.
function BindCards:GetHoverScope(friendly, hostile)
    if friendly and hostile then return "ANY" end
    if friendly then return "HELP" end
    if hostile then return "HARM" end
end

function BindCards:MakeHoverBinding(scope, key)
    if not HOVER_SCOPES[scope] or type(key) ~= "string" then return nil end
    return self:NormalizeKey("HOVER:" .. scope .. ":" .. key)
end

local NATIVE_CLICK_BUTTONS = {
    BUTTON1 = "LeftButton", BUTTON2 = "RightButton", BUTTON3 = "MiddleButton",
    BUTTON4 = "Button4", BUTTON5 = "Button5",
}

-- Clicks the native Click Casting profile runs as spells, macros or pet
-- actions, as BindCards keys ("SHIFT-BUTTON1"). Target/menu interactions are
-- not listed: they cooperate with addon bindings.
local function NativeActionClicks()
    local native = C_ClickBindings
    if type(native) ~= "table" or type(native.GetProfileInfo) ~= "function" or
        type(GetStringFromModifiers) ~= "function" then return {} end
    local ok, profile = pcall(native.GetProfileInfo)
    if not ok or type(profile) ~= "table" then return {} end
    local buttons, types, clicks = {}, Enum and Enum.ClickBindingType or {}, {}
    for key, button in pairs(NATIVE_CLICK_BUTTONS) do buttons[button] = key end
    for _, info in ipairs(profile) do
        local kind = type(info) == "table" and info.type
        local base = kind and buttons[info.button]
        if base and (kind == types.Spell or kind == types.Macro or kind == types.PetAction) then
            local textOK, text = pcall(GetStringFromModifiers, info.modifiers)
            if textOK and type(text) == "string" then
                local found = {}
                for token in text:upper():gmatch("%u+") do
                    if MODIFIERS[token] then found[token] = true end
                end
                local parts = {}
                for _, modifier in ipairs(MODIFIER_ORDER) do
                    if found[modifier] then parts[#parts + 1] = modifier end
                end
                parts[#parts + 1] = base
                clicks[#clicks + 1] = table.concat(parts, "-")
            end
        end
    end
    table.sort(clicks)
    return clicks
end

-- Blizzard unit frames on Forever run native Click Casting (C_ClickBindings)
-- before any attribute: a native spell, macro or pet action on the same click
-- always wins. Returns true when the native profile claims this click.
function BindCards:GetNativeClickBindingConflict(key)
    local hover = self:ParseHoverBinding(key)
    if not hover then return nil end
    for _, click in ipairs(NativeActionClicks()) do
        if click == hover.key then return true end
    end
    return nil
end

-- For the Bind window: native clicks that would beat mouseover clicks.
function BindCards:GetNativeActionClicks()
    return NativeActionClicks()
end

-- Live status comes from HoverCast.lua (clicks, keys and the wheel).
function BindCards:GetHoverBindingStatus(key)
    local hover = self:ParseHoverBinding(key)
    if not hover then return nil end
    local status
    if self.GetHoverCastStatus then status = self:GetHoverCastStatus(key) end
    status = status or "Saved."
    if self:GetNativeClickBindingConflict(key) then
        status = status .. " Blizzard Click Casting uses this click and runs first."
    end
    return status
end

function BindCards:FormatHoverScope(scope)
    local label = HOVER_SCOPES[scope]
    return label and (label:sub(1, 1):upper() .. label:sub(2) .. " frames") or nil
end

local function ClearSecureToken(button, token)
    if not button or not token then return end
    button:SetAttribute("*type-" .. token, nil)
    button:SetAttribute("*spell-" .. token, nil)
    button:SetAttribute("*item-" .. token, nil)
    button:SetAttribute("*toy-" .. token, nil)
    button:SetAttribute("*macrotext-" .. token, nil)
    button:SetAttribute("*pressAndHoldAction-" .. token, nil)
end

local function CreateBindingProxy(index)
    local name = index == 1 and "BindCardsBindingProxy" or ("BindCardsBindingProxy" .. index)
    local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    button:EnableMouse(false)
    button:SetSize(1, 1)
    button:SetAlpha(0)
    button:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -300, 100 - index)
    button:SetAttribute("*checkselfcast*", true)
    button:SetAttribute("*checkfocuscast*", true)
    button:Show()
    return button
end

local function SecureToken(tile)
    if tile.kind == "spell" then return "SPELL " .. tostring(tile.spellID) .. (tile.highestRank and " HIGHEST" or "") end
    if tile.kind == "item" then return "ITEM " .. tostring(tile.itemID) end
    if tile.kind == "macro" then return "MACRO " .. tostring(tile.id) end
end

local function ResolveNativeSpellCast(spellID, spellName, highestRank)
    if highestRank then return spellName, false end
    -- Forever build 69893's secure spell action dispatches numeric IDs to
    -- CastSpellByID. Name bindings would silently select the highest rank.
    -- Keep the selected rank on the secure click route, including form routes.
    return spellID, true
end

local function PrepareSecureSpec(tile)
    if tile.kind == "spell" and issecretvalue and issecretvalue(tile.spellID) then return nil end
    local token = SecureToken(tile)
    if not token then return nil end
    local spec = { kind = tile.kind, token = token, tile = tile, tileId = tile.id }
    if tile.kind == "spell" then
        spec.spellID = tonumber(tile.spellID)
        if not spec.spellID or spec.spellID <= 0 or spec.spellID % 1 ~= 0 then return nil end
        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(tile.spellID)
        local spellName = (spellInfo and spellInfo.name) or tile.name
        if (not spellName or spellName == "") and GetSpellInfo then spellName = GetSpellInfo(tile.spellID) end
        if issecretvalue and issecretvalue(spellName) then spellName = nil end
        if type(spellName) ~= "string" or spellName == "" then return nil end
        spec.spellName = spellName
        spec.spellCast, spec.exactSpell = ResolveNativeSpellCast(spec.spellID, spellName, tile.highestRank)
        spec.pressAndHold = C_Spell and C_Spell.IsPressHoldReleaseSpell and
            C_Spell.IsPressHoldReleaseSpell(tile.spellID) == true or false
    elseif tile.kind == "item" then
        local toyItemID = C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(tile.itemID)
        if tonumber(toyItemID) then spec.toy = tile.itemID
        else spec.item = "item:" .. tostring(tile.itemID) end
    elseif tile.kind == "macro" then
        if type(tile.macrotext) ~= "string" or tile.macrotext == "" then return nil end
        spec.macrotext = tile.macrotext
    end
    return spec
end

local function CopySecureSpecs(specs)
    local result = {}
    for token, spec in pairs(specs or {}) do
        result[token] = {
            kind = spec.kind, token = spec.token, tileId = spec.tileId,
            spellID = spec.spellID, spellName = spec.spellName, spellCast = spec.spellCast,
            exactSpell = spec.exactSpell,
            pressAndHold = spec.pressAndHold,
            item = spec.item, toy = spec.toy, macrotext = spec.macrotext,
            tile = { kind = spec.kind },
        }
    end
    return result
end

function BindCards:GetBindingConflict(key)
    key = self:NormalizeKey(key)
    if not key then return nil end
    if self:IsGamepadShortcut(key) then return nil end
    local normal = ReadBindingAction(key, false)
    local effective = ReadBindingAction(key, true)
    if not normal or not effective or effective == "" or effective == normal then return nil end
    if self.lastAppliedBindingActions and self.lastAppliedBindingActions[key] == effective then return nil end
    if self.formBindingActions and self.formBindingActions[key] and self.formBindingActions[key][effective] then return nil end
    if IsBindCardsBindingAction(effective) then return nil end
    return effective
end

function BindCards:RefreshBindingConflicts()
    if self:HouseEditorOwnsBindings() then
        self.lastBindingConflicts = {}
        self:Fire("BINDINGS_CONFLICTS", self.lastBindingConflicts)
        return self.lastBindingConflicts, false
    end
    local conflicts, missingOverride = {}, false
    for key in pairs(self.lastCompiledBindings or {}) do
        local effective = ReadBindingAction(key, true)
        if effective ~= nil then
            local conflict = self:GetBindingConflict(key)
            if conflict then
                conflicts[key] = conflict
            else
                -- Native SPELL overrides own both edges of empowered casts and
                -- therefore have no secure button token.
                local expected = self.lastAppliedBindingActions and
                    self.lastAppliedBindingActions[key] or nil
                local validFormAction = self.formBindingActions and self.formBindingActions[key] and
                    self.formBindingActions[key][effective]
                -- A hover key temporarily outranks the normal override; not a loss.
                if expected and effective ~= expected and not validFormAction and
                    not IsHoverKeyAction(effective) then missingOverride = true end
            end
        end
    end
    self.lastBindingConflicts = conflicts
    self:Fire("BINDINGS_CONFLICTS", conflicts)
    if missingOverride then self:RequestRecompile("external-binding-change") end
    return conflicts, missingOverride
end

function BindCards:RequestBindingConflictRefresh()
    if not self.db then return end
    local function Run()
        BindCards.bindingConflictTimer = nil
        BindCards.bindingConflictFallbackToken = nil
        BindCards:RefreshBindingConflicts()
    end
    if C_Timer and C_Timer.NewTimer then
        if self.bindingConflictTimer and self.bindingConflictTimer.Cancel then
            self.bindingConflictTimer:Cancel()
        end
        self.bindingConflictTimer = C_Timer.NewTimer(0.075, Run)
    elseif C_Timer and C_Timer.After then
        local token = {}
        self.bindingConflictFallbackToken = token
        C_Timer.After(0.075, function()
            if BindCards.bindingConflictFallbackToken ~= token then return end
            Run()
        end)
    else
        Run()
    end
end

function BindCards:GetSecureButton(tile)
    local button = self.secureButtons[tile.id]
    if button then return button, self.secureButtonTokens[tile.id] end
    if InCombatLockdown() then return nil end
    local poolIndex = (self.activeButtonCount or 0) + 1
    if poolIndex > self.MAX_TILES then return nil end
    self.activeButtonCount = poolIndex
    button = self.bindingProxy
    if not button then
        button = CreateBindingProxy(1)
        self.bindingProxy = button
        self.bindingProxySlots = self.bindingProxySlots or {}
        self.bindingProxySlots[1] = button
    end
    local token = SecureToken(tile)
    if not token then return nil end
    self.secureButtons[tile.id] = button
    self.secureButtonTokens[tile.id] = token
    return button, token
end

function BindCards:ConfigureSecureButton(tile, targetButton, prepared)
    local button, token
    if targetButton then
        button = targetButton
        prepared = prepared or PrepareSecureSpec(tile)
        token = prepared and prepared.token
    else
        button, token = self:GetSecureButton(tile)
        prepared = PrepareSecureSpec(tile)
    end
    if not button or InCombatLockdown() then return nil end
    if not prepared or prepared.token ~= token then return nil end
    ClearSecureToken(button, token)
    button:SetAttribute("*pressAndHoldAction-" .. token, false)
    local useKeyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
    button:RegisterForClicks(useKeyDown and "AnyDown" or "AnyUp")
    button:SetAttribute("useOnKeyDown", useKeyDown == true)
    if tile.kind == "spell" then
        button:SetAttribute("*type-" .. token, "spell")
        -- Preserve the selected Forever spell rank as an exact spell ID.
        button:SetAttribute("*spell-" .. token, prepared.spellCast)
        if prepared.pressAndHold then
            button:SetAttribute("*pressAndHoldAction-" .. token, true)
        end
    elseif tile.kind == "item" then
        if prepared.toy then
            button:SetAttribute("*type-" .. token, "toy")
            button:SetAttribute("*toy-" .. token, prepared.toy)
        else
            button:SetAttribute("*type-" .. token, "item")
            button:SetAttribute("*item-" .. token, prepared.item)
        end
    elseif tile.kind == "macro" then
        button:SetAttribute("*type-" .. token, "macro")
        button:SetAttribute("*macrotext-" .. token, prepared.macrotext)
    end
    return button, token
end

local function GetBindingSources(addon, profile)
    if profile and not profile.isComposite then return { profile } end
    -- Later sources win a shared key: General < class < character.
    local general, class, character = addon:GetSelectedProfileSets()
    local sources = {}
    if general then sources[#sources + 1] = general end
    if class then sources[#sources + 1] = class end
    if character then sources[#sources + 1] = character end
    return sources
end

local function CompileBindingsForContext(addon, sources, context, gamepad)
    local winners, cards, states, hoverWinners = {}, {}, {}, {}
    local overlays = {}
    local function ApplyCardTiles(card)
        local tiles = {}
        for _, tile in ipairs(card.tiles or {}) do tiles[#tiles + 1] = tile end
        table.sort(tiles, function(left, right)
            if (left.order or 0) ~= (right.order or 0) then return (left.order or 0) < (right.order or 0) end
            return left.id < right.id
        end)
        for _, tile in ipairs(tiles) do
            if addon:IsValidTilePayload(tile) then
                for _, rawKey in ipairs(tile.bindings or {}) do
                    local key = addon:NormalizeKey(rawKey)
                    -- Fail closed for saved gestures and legacy raw PAD keys.
                    -- They must never enter normal overrides or form drivers.
                    if key and gamepad then
                        local gesture = addon:ParseGamepadShortcut(key)
                        if gesture then
                            if gesture.page then winners[key] = tile
                            else
                                for page = 1, 3 do
                                    winners[key:gsub(':ALL:', ':BAR' .. page .. ':')] = tile
                                end
                            end
                        end
                    elseif key and addon:IsHoverBinding(key) then
                        -- Unit-frame bindings never become global overrides.
                        if not gamepad then hoverWinners[key] = tile end
                    elseif key and not addon:IsGamepadShortcut(key) then winners[key] = tile end
                end
            end
        end
    end
    for _, source in ipairs(sources) do
        local active, sourceStates = addon:GetActiveCards(source, context)
        local byId = {}
        for _, card in ipairs(source.cards or {}) do byId[card.id] = card end
        for _, card in ipairs(source.cards or {}) do
            states[card.id] = sourceStates[card.id]
        end
        for _, card in ipairs(active) do cards[#cards + 1] = card end
        if source.bindingsEnabled ~= false then
            for _, card in ipairs(active) do
                ApplyCardTiles(card)
                if source.binderId == addon.GENERAL_BINDER_ID then
                    local cursor, seen, isOverlay = card, {}
                    while cursor and not seen[cursor.id] do
                        seen[cursor.id] = true
                        if cursor.overrideAllBindingsWhenActive == true and
                            addon:CanCardUseGlobalPriority(cursor, source) then
                            isOverlay = true
                            break
                        end
                        cursor = byId[cursor.parentId or cursor.homeParentId]
                    end
                    if isOverlay then overlays[#overlays + 1] = card end
                end
            end
        end
    end
    for _, card in ipairs(overlays) do ApplyCardTiles(card) end
    return winners, cards, states, hoverWinners
end

local function HasSkyridingCondition(addon, sources)
    for _, source in ipairs(sources) do
        if source.binderId == addon.GENERAL_BINDER_ID and source.bindingsEnabled ~= false then
            for _, card in ipairs(source.cards or {}) do
                if card.enabled ~= false and card.condition and card.condition.activity == "SKYRIDING" then
                    return true
                end
            end
        end
    end
    return false
end

function BindCards:CompileCurrentBindings(profile)
    local sources, context = GetBindingSources(self, profile), self:GetPlayerContext()
    return CompileBindingsForContext(self, sources, context)
end

function BindCards:CompileCurrentGamepadBindings(profile)
    return CompileBindingsForContext(self, GetBindingSources(self, profile), self:GetPlayerContext(), true)
end

local function BindingIdentity(tile)
    return tile and (tile.kind .. ":" .. tostring(tile.spellID or tile.itemID or tile.id) .. (tile.highestRank and ":highest" or "")) or "none"
end

function BindCards:CompileBindings(profile)
    local sources, context = GetBindingSources(self, profile), self:GetPlayerContext()
    local winners, cards, states, hoverWinners = CompileBindingsForContext(self, sources, context)
    -- Mouseover bindings per form state. Form changes do not recompile, so
    -- HoverCast switches between these in its secure snippets, following the
    -- same form state driver as normal keys.
    local hoverStates = { states = { "base" }, byState = { base = hoverWinners }, current = "base" }
    self.lastCompiledHoverStates = hoverStates
    self.lastCompiledHoverBindings = hoverWinners
    local options = self:GetFormOptions(context.class)
    local hasSkyriding = HasSkyridingCondition(self, sources)
    if #options == 0 and not hasSkyriding then return winners, cards, states, {}, nil end

    local variants, allStates = {}, { "base" }
    local baseContext = self.CopyTable(context)
    baseContext.form = nil
    baseContext.activity = nil
    local baseWinners, _, _, baseHoverWinners = CompileBindingsForContext(self, sources, baseContext)
    variants.base = baseWinners
    hoverStates.byState.base = baseHoverWinners
    for _, option in ipairs(options) do
        local stateContext = self.CopyTable(baseContext)
        stateContext.form = option.id
        local formWinners, _, _, formHoverWinners = CompileBindingsForContext(self, sources, stateContext)
        variants[option.id] = formWinners
        allStates[#allStates + 1] = option.id
        hoverStates.states[#hoverStates.states + 1] = option.id
        hoverStates.byState[option.id] = formHoverWinners
        if context.form == option.id then hoverStates.current = option.id end
    end
    if #options > 0 then hoverStates.driver = self:GetConditionalBindingStateDriver(context.class) end
    self.lastCompiledHoverBindings = hoverStates.byState[hoverStates.current]
    if hasSkyriding then
        local skyridingContext = self.CopyTable(baseContext)
        skyridingContext.activity = "SKYRIDING"
        variants.skyriding = CompileBindingsForContext(self, sources, skyridingContext)
        allStates[#allStates + 1] = "skyriding"
        for _, option in ipairs(options) do
            local state = "skyriding_" .. option.id
            local stateContext = self.CopyTable(skyridingContext)
            stateContext.form = option.id
            variants[state] = CompileBindingsForContext(self, sources, stateContext)
            allStates[#allStates + 1] = state
        end
    end

    local allKeys = {}
    for _, state in ipairs(allStates) do
        for key in pairs(variants[state]) do allKeys[key] = true end
    end
    local routes = {}
    for key in pairs(allKeys) do
        local distinct, count = {}, 0
        for _, state in ipairs(allStates) do
            local tile = variants[state][key]
            local identity = BindingIdentity(tile)
            if not distinct[identity] then distinct[identity], count = true, count + 1 end
        end
        if count > 1 then
            routes[key] = {}
            for _, state in ipairs(allStates) do routes[key][state] = variants[state][key] end
            for _, option in ipairs(options) do
                if BindingIdentity(variants[option.id][key]) ~= BindingIdentity(variants.base[key]) or
                    (hasSkyriding and BindingIdentity(variants["skyriding_" .. option.id][key]) ~=
                        BindingIdentity(variants.skyriding[key])) then
                    routes[key].blockInactive = true
                    break
                end
            end
        end
    end
    return winners, cards, states, routes,
        self:GetConditionalBindingStateDriver(context.class, hasSkyriding), allStates
end

local function InstallOverridePlan(plan)
    if not ClearOverrideBindings or not SetOverrideBindingClick then return false end
    local cleared, clearResult = pcall(ClearOverrideBindings, bindingOwner)
    if not cleared or clearResult == false then return false end
    for _, target in ipairs(plan or {}) do
        local ok, result
        if target.kind == "spell" then
            if not SetOverrideBindingSpell then return false end
            ok, result = pcall(SetOverrideBindingSpell, bindingOwner, false,
                target.key, target.spellName)
        else
            ok, result = pcall(SetOverrideBindingClick, bindingOwner, target.priority == true,
                target.key, target.buttonName, target.token)
        end
        if not ok or result == false then return false end
    end
    return true
end

local function ConfigureFormBindingPlan(plan)
    if not plan or not next(plan.routes or {}) then return ClearFormBindings() end
    if plan.nativeDrivers then
        if not ClearFormBindings() then return false end
        local proxy = BindCards.bindingProxySlots and BindCards.bindingProxySlots[1]
        if not proxy or proxy:GetName() ~= plan.clickTarget then return false end
        nativeDriverFrame, nativeDriverAttributes = proxy, {}
        for attribute, driver in pairs(plan.nativeDrivers) do
            nativeDriverAttributes[attribute] = true
            local ok, result = pcall(RegisterAttributeDriver, proxy, attribute, driver)
            if not ok or result == false then return false end
        end
        return true
    end
    if not ClearNativeFormDrivers() then return false end
    if not RegisterStateDriver then return false end
    local manager = GetFormBindingManager()
    if not manager or not manager.Execute then return false end
    if UnregisterStateDriver then pcall(UnregisterStateDriver, manager, "bcform") end
    if not pcall(manager.Execute, manager, "self:ClearBindings()") then return false end

    local previousCount = tonumber(manager:GetAttribute("bc-count")) or 0
    local stateSet, attributeStates = {}, {}
    for _, state in ipairs(BindCards.formBindingAttributeStates or { "base" }) do stateSet[state] = true end
    for _, state in ipairs(plan.states) do stateSet[state] = true end
    for state in pairs(stateSet) do attributeStates[#attributeStates + 1] = state end
    table.sort(attributeStates)
    BindCards.formBindingAttributeStates = attributeStates
    local configured = pcall(function()
        for index = 1, math.max(previousCount, #plan.keys) do
            manager:SetAttribute("bc-key-" .. index, nil)
            manager:SetAttribute("bc-block-inactive-" .. index, nil)
            for _, state in ipairs(attributeStates) do
                manager:SetAttribute("bc-kind-" .. index .. "-" .. state, nil)
                manager:SetAttribute("bc-value-" .. index .. "-" .. state, nil)
            end
        end
        manager:SetAttribute("bc-click-target", plan.clickTarget)
        manager:SetAttribute("bc-count", #plan.keys)
        for index, key in ipairs(plan.keys) do
            manager:SetAttribute("bc-key-" .. index, key)
            manager:SetAttribute("bc-block-inactive-" .. index,
                plan.blockInactive and plan.blockInactive[key] or nil)
            for _, state in ipairs(plan.states) do
                local action = plan.routes[key] and plan.routes[key][state]
                if action then
                    manager:SetAttribute("bc-kind-" .. index .. "-" .. state, action.kind)
                    manager:SetAttribute("bc-value-" .. index .. "-" .. state, action.value)
                end
            end
        end
    end)
    if not configured then return false end
    local ok, result = pcall(RegisterStateDriver, manager, "bcform", plan.driver)
    if not ok or result == false then
        pcall(manager.Execute, manager, "self:ClearBindings()")
        return false
    end
    -- Registering the same already-active state does not reliably invoke the
    -- state handler. Apply it once explicitly so the base route is never left
    -- empty after an out-of-combat rebuild.
    local applied, applyResult = pcall(manager.Execute, manager, APPLY_CURRENT_FORM_STATE_SNIPPET)
    if not applied or applyResult == false then
        if UnregisterStateDriver then pcall(UnregisterStateDriver, manager, "bcform") end
        pcall(manager.Execute, manager, "self:ClearBindings()")
        return false
    end
    BindCards.formBindingAttributeStates = attributeStates
    return true
end

local function CopyFormBindingPlan(plan)
    if not plan then return nil end
    return BindCards.CopyTable(plan)
end

local function RestoreNormalBindings(changes)
    local restored = true
    for index = #changes, 1, -1 do
        local change = changes[index]
        local ok, result = pcall(SetBinding, change.key, change.before ~= "" and change.before or nil)
        if not ok or result == false then restored = false end
    end
    return restored
end

-- Recompiles triggered by the world rather than by an edit. They fire often
-- (every subzone, every combat end) and usually leave the result unchanged.
local AMBIENT_RECOMPILE_REASONS = {
    ["combat-ended"] = true, ["pvp-status"] = true, specialization = true,
    ZONE_CHANGED = true, ZONE_CHANGED_INDOORS = true, ZONE_CHANGED_NEW_AREA = true,
    PLAYER_ENTERING_WORLD = true, WAR_MODE_STATUS_UPDATE = true,
    ACTIVE_PLAYER_SPECIALIZATION_CHANGED = true, ACTIVE_TALENT_GROUP_CHANGED = true,
    PLAYER_TALENT_UPDATE = true, TRAIT_CONFIG_UPDATED = true, ACTIVE_COMBAT_CONFIG_CHANGED = true,
    UPDATE_SHAPESHIFT_FORMS = true,
}

local function SpecSignature(spec)
    if not spec then return "-" end
    return table.concat({
        tostring(spec.kind), tostring(spec.token), tostring(spec.spellID), tostring(spec.spellName),
        tostring(spec.spellCast), tostring(spec.exactSpell), tostring(spec.pressAndHold),
        tostring(spec.item), tostring(spec.toy), tostring(spec.macrotext),
    }, "\031")
end

-- Everything the secure install depends on: each key's prepared action, the
-- form routes and driver, BindPad-blocked keys and the key-down CVar.
local function BindingSignature(winnerTargets, formRoutes, formDriver, formStates, blockerKeys)
    local parts = { "keydown=" .. tostring(GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")),
        "driver=" .. tostring(formDriver), "states=" .. table.concat(formStates or {}, ",") }
    local keys = {}
    for key in pairs(winnerTargets) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do parts[#parts + 1] = "w:" .. key .. "=" .. SpecSignature(winnerTargets[key]) end
    keys = {}
    for key in pairs(formRoutes) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local route = formRoutes[key]
        parts[#parts + 1] = "f:" .. key .. "=" .. tostring(route.blockInactive)
        for _, state in ipairs(formStates or {}) do
            parts[#parts + 1] = state .. ":" .. SpecSignature(route[state])
        end
    end
    keys = {}
    for key in pairs(blockerKeys) do keys[#keys + 1] = key end
    table.sort(keys)
    parts[#parts + 1] = "b:" .. table.concat(keys, ",")
    return table.concat(parts, "\030")
end

function BindCards:ApplyBindings(reason)
    if not self.db then return false end
    if InCombatLockdown() then
        self.bindingsPending = reason or true
        self:Fire("BINDINGS_QUEUED", reason)
        return false
    end
    if self:HouseEditorOwnsBindings() then
        return self:SetHouseEditorBindingSuspended(true), 0, 0
    end

    local winners, cards, states, formRoutes, formDriver, formStates = self:CompileBindings()
    -- Native attribute drivers do not compile snippets and work in combat.
    local useNativeFormDrivers = type(RegisterAttributeDriver) == "function" and
        type(UnregisterAttributeDriver) == "function"
    local profile = self:GetSelectedProfile()
    local settings = self.db.settings or {}
    local preparedByTile, preparedByToken, winnerTargets, preparedFormRoutes = {}, {}, {}, {}
    local winnerCount = 0

    local function PrepareTile(tile)
        if not tile then return nil end
        local prepared = preparedByTile[tile.id]
        if not prepared then
            local ok
            ok, prepared = pcall(PrepareSecureSpec, tile)
            if not ok or not prepared then return nil end
            preparedByTile[tile.id] = prepared
            preparedByToken[prepared.token] = prepared
            winnerCount = winnerCount + 1
        end
        return prepared
    end

    -- Preflight every state before mutating live secure state.
    for key, tile in pairs(winners) do
        local prepared = PrepareTile(tile)
        if not prepared then
            self:Fire("BINDINGS_APPLIED", 0, cards, reason, 1)
            return false, 0, 1
        end
        winnerTargets[key] = prepared
    end
    for key, route in pairs(formRoutes or {}) do
        preparedFormRoutes[key] = { blockInactive = route.blockInactive }
        for _, state in ipairs(formStates or {}) do
            local tile = route[state]
            if tile then
                local prepared = PrepareTile(tile)
                if not prepared then
                    self:Fire("BINDINGS_APPLIED", 0, cards, reason, 1)
                    return false, 0, 1
                end
                preparedFormRoutes[key][state] = prepared
            end
        end
    end
    if not ClearOverrideBindings or not SetOverrideBindingClick then
        self:Fire("BINDINGS_APPLIED", 0, cards, reason, 1)
        return false, 0, 1
    end

    local blocker, blockerKeys = nil, {}
    if settings.suspendBindPad == true then
        self:InstallBindPadRefreshHooks()
        blocker = GetBindPadBlocker()
        if not blocker then
            self:Fire("BINDINGS_APPLIED", 0, cards, reason, 1)
            return false, 0, 1
        end
        for rawKey in pairs(GetBindPadBindingKeys()) do
            local key = self:NormalizeKey(rawKey)
            if key and not self:IsGamepadShortcut(key) and not winnerTargets[key] and not preparedFormRoutes[key] then blockerKeys[key] = true end
        end
    end

    -- Stage the one-time normal-binding migration before live mutation.
    self.directBindingKeys = self.directBindingKeys or {}
    settings.bindingRestore = settings.bindingRestore or {}
    local migration = {}
    local completeLegacyMigration = settings.legacyBindingsRestored ~= true
    if settings.legacyBindingsRestored ~= true then
        local knownKeys = {}
        for key in pairs(self.directBindingKeys) do knownKeys[key] = true; completeLegacyMigration = true end
        for key in pairs(settings.bindingRestore) do knownKeys[key] = true; completeLegacyMigration = true end
        for _, card in ipairs(profile and profile.cards or {}) do
            for _, tile in ipairs(card.tiles or {}) do
                for _, rawKey in ipairs(tile.bindings or {}) do
                    local key = self:NormalizeKey(rawKey)
                    if key then knownKeys[key] = true end
                end
            end
        end
        for key in pairs(knownKeys) do
            local action = ReadBindingAction(key, false)
            if action == nil then
                self:Fire("BINDINGS_APPLIED", 0, cards, reason, 1)
                return false, 0, 1
            end
            if IsBindCardsBindingAction(action) then
                completeLegacyMigration = true
                migration[#migration + 1] = {
                    key = key, before = action,
                    after = settings.bindingRestore[key] or nil,
                }
            end
        end
    end

    -- An unchanged result needs no secure teardown and reinstall; publish the
    -- refreshed card states only. Pending work and legacy migration always install.
    local signature = #migration == 0 and
        BindingSignature(winnerTargets, preparedFormRoutes, formDriver, formStates, blockerKeys) or nil
    if signature and AMBIENT_RECOMPILE_REASONS[reason] and not self.bindingsPending
        and self.lastAppliedOverridePlan and self.lastBindingSignature == signature then
        self.lastCompiledBindings = winners
        self.lastActiveCardStates = states
        ApplyHoverSafely(self)
        local count = self.lastAppliedBindingCount or 0
        self:Fire("BINDINGS_APPLIED", count, cards, reason, 0)
        return true, count, 0
    end
    -- Live secure state is about to change; the old fingerprint no longer applies.
    self.lastBindingSignature = nil

    -- Validate on an inactive proxy while the live proxy keeps its stable name
    -- and remains reconstructible after a later failure.
    self.bindingProxySlots = self.bindingProxySlots or {}
    local activeProxy = self.bindingProxy or self.bindingProxySlots[1]
    if not activeProxy then
        local created
        created, activeProxy = pcall(CreateBindingProxy, 1)
        if not created or not activeProxy then
            self:Fire("BINDINGS_APPLIED", 0, cards, reason, 1)
            return false, 0, 1
        end
        self.bindingProxySlots[1] = activeProxy
    end
    local stagingProxy = self.bindingProxySlots[2]
    if not stagingProxy then
        local ok
        ok, stagingProxy = pcall(CreateBindingProxy, 2)
        if not ok or not stagingProxy then
            self:Fire("BINDINGS_APPLIED", 0, cards, reason, 1)
            return false, 0, 1
        end
        self.bindingProxySlots[2] = stagingProxy
    end
    self.bindingProxyTokenSets = self.bindingProxyTokenSets or {}
    local stagingOldTokens = self.bindingProxyTokenSets[stagingProxy] or {}
    local stagingNewTokens = {}
    local configured = pcall(function()
        for token in pairs(stagingOldTokens) do ClearSecureToken(stagingProxy, token) end
        for token, prepared in pairs(preparedByToken) do
            local button, configuredToken = self:ConfigureSecureButton(prepared.tile, stagingProxy, prepared)
            if button ~= stagingProxy or configuredToken ~= token then error("secure configuration failed") end
            stagingNewTokens[token] = true
        end
    end)
    if not configured then
        pcall(function()
            for token in pairs(stagingOldTokens) do ClearSecureToken(stagingProxy, token) end
            for token in pairs(preparedByToken) do ClearSecureToken(stagingProxy, token) end
        end)
        self.bindingProxyTokenSets[stagingProxy] = {}
        self:Fire("BINDINGS_APPLIED", 0, cards, reason, 1)
        return false, 0, 1
    end
    self.bindingProxyTokenSets[stagingProxy] = stagingNewTokens

    local previousSpecs = self.lastActiveSecureSpecs or {}
    local function ConfigureLiveProxy(specs)
        local success = pcall(function()
            local tokens = {}
            for token in pairs(previousSpecs) do tokens[token] = true end
            for token in pairs(preparedByToken) do tokens[token] = true end
            for token in pairs(tokens) do ClearSecureToken(activeProxy, token) end
            for token, prepared in pairs(specs) do
                local button, configuredToken = self:ConfigureSecureButton(prepared.tile, activeProxy, prepared)
                if button ~= activeProxy or configuredToken ~= token then error("secure configuration failed") end
            end
        end)
        return success
    end
    if not ConfigureLiveProxy(preparedByToken) then
        ConfigureLiveProxy(previousSpecs)
        self:Fire("BINDINGS_APPLIED", 0, cards, reason, 1)
        return false, 0, 1
    end

    local newPlan, secureButtons, secureTokens, bindingActions = {}, {}, {}, {}
    for key, prepared in pairs(winnerTargets) do
        if not preparedFormRoutes[key] and prepared.kind == "spell" and
            not prepared.exactSpell then
            newPlan[#newPlan + 1] = { key = key, kind = "spell", spellName = prepared.spellName }
            bindingActions[key] = "SPELL " .. prepared.spellName
        elseif not preparedFormRoutes[key] then
            newPlan[#newPlan + 1] = {
                key = key, kind = "click", buttonName = activeProxy:GetName(), token = prepared.token,
            }
            bindingActions[key] = "CLICK " .. activeProxy:GetName() .. ":" .. prepared.token
            secureButtons[prepared.tileId] = activeProxy
            secureTokens[prepared.tileId] = prepared.token
        end
    end
    local formPlan = { driver = formDriver, states = formStates or { "base" }, keys = {}, routes = {}, blockInactive = {},
        clickTarget = activeProxy:GetName() }
    local formBindingActions = {}
    for key, route in pairs(preparedFormRoutes) do
        formPlan.keys[#formPlan.keys + 1] = key
        formPlan.routes[key] = {}
        formPlan.blockInactive[key] = route.blockInactive
        formBindingActions[key] = {}
        for _, state in ipairs(formPlan.states) do
            local prepared = route[state]
            if prepared then
                local action
                if prepared.kind == "spell" and not prepared.exactSpell then
                    action = { kind = "spell", value = prepared.spellName }
                    formBindingActions[key]["SPELL " .. prepared.spellName] = true
                else
                    action = { kind = "click", value = prepared.token }
                    formBindingActions[key]["CLICK " .. activeProxy:GetName() .. ":" .. prepared.token] = true
                    secureButtons[prepared.tileId] = activeProxy
                    secureTokens[prepared.tileId] = prepared.token
                end
                formPlan.routes[key][state] = action
            end
        end
    end
    table.sort(formPlan.keys)
    if useNativeFormDrivers and #formPlan.keys > 0 then
        formPlan.nativeDrivers = {}
        for index, key in ipairs(formPlan.keys) do
            local token = "BC_FORM_" .. index
            local clauses = {}
            for clause in formPlan.driver:gmatch("[^;]+") do
                local condition, state = clause:match("^%s*(.-)%s*([%w_]+)%s*$")
                if not state then return false, 0, 1 end
                local prepared = preparedFormRoutes[key][state] or preparedFormRoutes[key].base
                clauses[#clauses + 1] = condition .. " " .. (prepared and prepared.token or "BC_INACTIVE_FORM")
            end
            -- SecureActionButton remaps helpbutton, then resolves the unit
            -- again for the selected token. Only the routing token targets
            -- player: the real action retains normal target/self/focus rules.
            -- Payloads (including arbitrary multiline macros) stay untouched.
            formPlan.nativeDrivers["*unit-" .. token] = "player"
            formPlan.nativeDrivers["*helpbutton-" .. token] = table.concat(clauses, "; ")
            newPlan[#newPlan + 1] = {
                key = key, kind = "click", buttonName = activeProxy:GetName(), token = token, priority = true,
            }
            bindingActions[key] = "CLICK " .. activeProxy:GetName() .. ":" .. token
        end
    end
    local bindPadBlocked = 0
    for key in pairs(blockerKeys) do
        newPlan[#newPlan + 1] = { key = key, kind = "click", buttonName = blocker:GetName(), token = "LeftButton" }
        bindPadBlocked = bindPadBlocked + 1
    end

    local previousPlan = self.lastAppliedOverridePlan or {}
    local previousFormPlan = self.lastAppliedFormBindingPlan
    if not InstallOverridePlan(newPlan) then
        ConfigureLiveProxy(previousSpecs)
        local rolledBack = InstallOverridePlan(previousPlan)
        self:Fire("BINDINGS_APPLIED", 0, cards, reason, 1)
        if not rolledBack then self:Notify("Bindings could not be restored; use /bc rebind outside combat.") end
        return false, 0, 1
    end
    if not ConfigureFormBindingPlan(formPlan) then
        ConfigureLiveProxy(previousSpecs)
        local staticRolledBack = InstallOverridePlan(previousPlan)
        local formRolledBack = ConfigureFormBindingPlan(previousFormPlan)
        self:Fire("BINDINGS_APPLIED", 0, cards, reason, 1)
        if not staticRolledBack or not formRolledBack then
            self:Notify("Bindings could not be restored; use /bc rebind outside combat.")
        end
        return false, 0, 1
    end

    local normalChanges = {}
    local migrationSucceeded = true
    for _, change in ipairs(migration) do
        local changed, result = pcall(SetBinding, change.key, change.after)
        if not changed or result == false then migrationSucceeded = false break end
        normalChanges[#normalChanges + 1] = change
    end
    if migrationSucceeded and #normalChanges > 0 and SaveBindings and GetCurrentBindingSet then
        local saved, result = pcall(SaveBindings, GetCurrentBindingSet())
        migrationSucceeded = saved and result ~= false
    end
    if not migrationSucceeded then
        RestoreNormalBindings(normalChanges)
        ConfigureLiveProxy(previousSpecs)
        local rolledBack = InstallOverridePlan(previousPlan)
        local formRolledBack = ConfigureFormBindingPlan(previousFormPlan)
        self:Fire("BINDINGS_APPLIED", 0, cards, reason, 1)
        if not rolledBack or not formRolledBack then self:Notify("Bindings could not be restored; use /bc rebind outside combat.") end
        return false, 0, 1
    end

    -- Publish only after secure installation and migration both succeed.
    self.bindingsPending = nil
    self.bindingProxy = activeProxy
    self.secureButtons = secureButtons
    self.secureButtonTokens = secureTokens
    self.activeButtonCount = winnerCount
    self.lastAppliedOverridePlan = newPlan
    self.lastAppliedFormBindingPlan = CopyFormBindingPlan(formPlan)
    self.lastAppliedBindingActions = bindingActions
    self.formBindingActions = formBindingActions
    self.lastActiveSecureSpecs = CopySecureSpecs(preparedByToken)
    self.lastCompiledBindings = winners
    self.lastActiveCardStates = states
    self.lastSuppressedBindPadCount = bindPadBlocked
    self.lastBindingFailureCount = 0
    if settings.legacyBindingsRestored ~= true and completeLegacyMigration then
        settings.legacyBindingsRestored = true
        settings.bindingRestore = {}
        self.displacedBindings = settings.bindingRestore
        for key in pairs(self.directBindingKeys) do self.directBindingKeys[key] = nil end
    end
    local appliedCount = #newPlan - bindPadBlocked + (formPlan.nativeDrivers and 0 or #formPlan.keys)
    self.lastBindingSignature = signature
    self.lastAppliedBindingCount = appliedCount
    ApplyHoverSafely(self)
    self:Fire("BINDINGS_APPLIED", appliedCount, cards, reason, 0)
    return true, appliedCount, 0
end

-- Unit-frame casting (HoverCast.lua) reuses the secure payload preparation.
function BindCards:PrepareHoverAction(tile)
    local ok, prepared = pcall(PrepareSecureSpec, tile)
    return ok and prepared or nil
end

function BindCards:SetBindPadSuspended(enabled)
    if not self.db then return false, "Database is unavailable." end
    self.db.settings = self.db.settings or {}
    self.db.settings.suspendBindPad = enabled == true
    self:RequestRecompile("bindpad-suppression-toggled", true)
    return true
end

function BindCards:RequestRecompile(reason, immediate)
    if not self.db then return end
    if InCombatLockdown() then
        self.recompileGeneration = (self.recompileGeneration or 0) + 1
        if self.recompileTimer and self.recompileTimer.Cancel then self.recompileTimer:Cancel() end
        self.recompileTimer, self.recompileTimerFallback, self.recompileFallbackToken = nil, nil, nil
        self.recompileQueued = nil
        self.bindingsPending = reason or true
        self:Fire("BINDINGS_QUEUED", reason)
        return
    end
    if immediate then
        self.recompileGeneration = (self.recompileGeneration or 0) + 1
        if self.recompileTimer and self.recompileTimer.Cancel then self.recompileTimer:Cancel() end
        self.recompileTimer, self.recompileTimerFallback, self.recompileFallbackToken = nil, nil, nil
        self.recompileQueued, self.recompileReason = nil, nil
        return self:ApplyBindings(reason)
    end
    self.recompileReason = reason or self.recompileReason
    self.recompileGeneration = (self.recompileGeneration or 0) + 1
    self.recompileQueued = true
    local function Run()
        BindCards.recompileTimer = nil
        BindCards.recompileQueued = nil
        local queuedReason = BindCards.recompileReason
        BindCards.recompileReason = nil
        BindCards:ApplyBindings(queuedReason)
    end
    if C_Timer.NewTimer then
        if self.recompileTimer and self.recompileTimer.Cancel then self.recompileTimer:Cancel() end
        self.recompileTimer = C_Timer.NewTimer(0.075, Run)
    elseif not self.recompileTimerFallback then
        self.recompileTimerFallback = true
        local fallbackToken = {}
        self.recompileFallbackToken = fallbackToken
        C_Timer.After(0.075, function()
            if BindCards.recompileFallbackToken ~= fallbackToken then return end
            BindCards.recompileTimerFallback = nil
            BindCards.recompileFallbackToken = nil
            Run()
        end)
    end
end

function BindCards:ApplyPendingBindings()
    if self.bindingsPending or self.recompileQueued then
        self.recompileGeneration = (self.recompileGeneration or 0) + 1
        if self.recompileTimer and self.recompileTimer.Cancel then self.recompileTimer:Cancel() end
        self.recompileTimer, self.recompileTimerFallback, self.recompileFallbackToken = nil, nil, nil
        self.recompileQueued = nil
        local reason = self.bindingsPending or self.recompileReason or "combat-ended"
        self.bindingsPending, self.recompileReason = nil, nil
        self:ApplyBindings(reason)
    end
end

function BindCards:SetTileBinding(tileId, key, replace, profileId)
    local profile, tile = self:FindTileOwner(tileId, profileId)
    if not tile then return false, "Tile not found." end
    key = self:NormalizeKey(key)
    if not key then return false, "That key is not supported." end
    tile.bindings = replace and {} or (tile.bindings or {})
    for _, existing in ipairs(tile.bindings) do if existing == key then return true end end
    if #tile.bindings >= 8 then return false, "A tile can have up to 8 bindings." end
    tile.bindings[#tile.bindings + 1] = key
    self:TouchProfile(profile, "bindings")
    self:RequestRecompile("binding-changed")
    return true
end

-- Remove duplicates only from sibling tiles; conditional cards may share keys.
function BindCards:AssignTileBinding(tileId, key, profileId)
    local profile, tile, card = self:FindTileOwner(tileId, profileId)
    if not tile then return false, "Tile not found." end
    key = self:NormalizeKey(key)
    if not key then return false, "That key is not supported." end
    local saved = {}
    local gamepad = self:IsGamepadShortcut(key)
    local gesture = self:ParseGamepadShortcut(key)
    local hover = self:ParseHoverBinding(key)
    -- One captured gesture per bar on an ability. Preserve other bars and
    -- keyboard bindings. Reassigning a legacy all-bars gesture narrows its scope.
    -- Mouseover bindings keep one key per scope beside the normal key.
    for _, existing in ipairs(tile.bindings or {}) do
        local existingGesture = self:ParseGamepadShortcut(existing)
        local existingHover = self:ParseHoverBinding(existing)
        if self:IsGamepadShortcut(existing) ~= gamepad or (existingHover ~= nil) ~= (hover ~= nil) or
            (hover and existingHover and existingHover.scope ~= hover.scope) or
            (gamepad and gesture and gesture.page and existingGesture and
                existingGesture.page and existingGesture.page ~= gesture.page) then
            saved[#saved + 1] = existing
        end
    end
    if #saved >= 8 then return false, "A tile can have up to 8 bindings." end
    saved[#saved + 1] = key
    for _, sibling in ipairs(card.tiles or {}) do
        if sibling ~= tile then
            local kept = {}
            for _, existing in ipairs(sibling.bindings or {}) do
                if self:NormalizeKey(existing) ~= key then kept[#kept + 1] = existing end
            end
            sibling.bindings = kept
        end
    end
    tile.bindings = saved
    if gamepad and self.ReclaimGamepadBinding then self:ReclaimGamepadBinding(key) end
    self:TouchProfile(profile, "bindings")
    self:RequestRecompile("binding-assigned")
    return true
end

-- Removes the mouseover binding of one scope and keeps every other binding.
function BindCards:ClearTileHoverBindings(tileId, scope, profileId)
    local profile, tile = self:FindTileOwner(tileId, profileId)
    if not tile then return false, "Tile not found." end
    local kept = {}
    for _, existing in ipairs(tile.bindings or {}) do
        local hover = self:ParseHoverBinding(existing)
        if not hover or hover.scope ~= scope then kept[#kept + 1] = existing end
    end
    tile.bindings = kept
    self:TouchProfile(profile, "bindings")
    self:RequestRecompile("binding-cleared")
    return true
end

function BindCards:ClearTileBindings(tileId, profileId)
    local profile, tile = self:FindTileOwner(tileId, profileId)
    if not tile then return false, "Tile not found." end
    tile.bindings = {}
    self:TouchProfile(profile, "bindings")
    self:RequestRecompile("binding-cleared")
    return true
end
