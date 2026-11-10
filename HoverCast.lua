local _, BindCards = ...

-- Mouseover bindings on unit frames (HOVER:<scope>:<key>), in four parts:
--   1. Clicks: attributes stamped on each registered unit frame (below).
--   2. Keys and the wheel: secure OnEnter/OnLeave wraps claim matching keys
--      while the cursor is over a frame (see ENTER_SNIPPET).
--   3. Forms: per-form tables switched by a "bcform" state driver, also in
--      combat (see ENTER_SNIPPET and HEADER_CHANGED_SNIPPET).
--   4. Test unit frames and /bc hover diagnostics (end of file).
-- Frames: Blizzard player/target/ToT/focus/pet/party/compact frames, plus the
-- ClickCastFrames registry. BindCards yields entirely when Clique is loaded.
-- Design notes and in-game checks: README.md, PORT-VALIDATION.md.
--
-- Clicks. Forever's Blizzard unit frames run SecureUnitButton_OnClick: native Click
-- Casting first, then the frame's own secure action code, which remaps the
-- button by the unit's disposition (helpbutton / harmbutton) and performs the
-- action of the remapped button. BindCards writes only:
--   [mods]helpbutton<N> / [mods]harmbutton<N> = <token>
--   *type-<token>, *spell-<token> (or item/toy/macrotext) = the tile action
-- A unit that does not match keeps the frame's own click (Target, menu).
--
-- The native check treats an unbound modified click (Shift-Left) as the
-- frame's wildcard "target" and drops it before the remap. On Blizzard frames
-- the exact modified type attribute is therefore set to ATTRIBUTE_NOOP. A
-- modified click with no native binding does nothing natively either.
--
-- Every attribute written is backed up and restored when the binding goes.
-- Attributes on protected frames cannot change in combat: work waits for
-- PLAYER_REGEN_ENABLED, which recompiles and calls ApplyHoverBindings.

local MOUSE_SUFFIX = { BUTTON1 = "1", BUTTON2 = "2", BUTTON3 = "3", BUTTON4 = "4", BUTTON5 = "5" }
local NOOP = ATTRIBUTE_NOOP or ""
local NONE = {} -- backup sentinel: the attribute was unset
local HOVER = {
    frames = {}, order = {}, backups = {}, queue = {},
    stamped = false, installed = false, pending = false,
}
BindCards.hoverCast = HOVER

-- "HOVER:HELP:ALT-SHIFT-BUTTON1" -> "alt-shift-", "1"; nil for keys and wheel.
local function MouseCombo(key)
    local hover = BindCards:ParseHoverBinding(key)
    if not hover then return nil end
    local base = hover.key:match("([^-]+)$")
    local suffix = MOUSE_SUFFIX[base]
    if not suffix then return nil end
    -- SecureButton_GetModifierPrefix order: alt-ctrl-shift-
    local prefix = ""
    for _, modifier in ipairs({ "ALT", "CTRL", "SHIFT" }) do
        if hover.key:find(modifier .. "-", 1, true) then prefix = prefix .. modifier:lower() .. "-" end
    end
    return prefix, suffix, hover.scope
end

function BindCards:IsHoverMouseBinding(key)
    return MouseCombo(key) ~= nil
end

local function CliqueActive()
    if rawget(_G, "ClickCastHeader") ~= nil then return true end
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if type(loaded) == "function" then
        local ok, result = pcall(loaded, "Clique")
        if ok and result then return true end
    end
    return false
end

local function IsBlizzardUnitButton(frame)
    return type(SecureUnitButton_OnClick) == "function" and frame.GetScript and
        frame:GetScript("OnClick") == SecureUnitButton_OnClick
end

local function ValidFrame(frame)
    if type(frame) ~= "table" or type(frame.SetAttribute) ~= "function" or
        type(frame.GetAttribute) ~= "function" then return false end
    if frame.IsForbidden and frame:IsForbidden() then return false end
    -- Nameplates are compact unit frames too (Blizzard sets them up through
    -- CompactUnitFrame_SetUpFrame), but Blizzard keeps their mouse off and
    -- hit-tests them in the engine. An OnEnter wrap turns the mouse on, and
    -- the plate then swallows the press that should start a camera drag.
    if type(frame.GetNamePlateFrame) == "function" or type(frame.UpdateHitTestArea) == "function" then
        return false
    end
    return true
end

-- Keys and the mouse wheel while hovering. Each registered frame's OnEnter is
-- wrapped with a secure snippet (runs in combat on protected frames): it reads
-- the frame's unit, checks its disposition and claims only the matching keys
-- as priority override bindings owned by that frame, pointing at one named
-- BindCards button (pooled party frames are anonymous). OnLeave releases them,
-- so a key keeps its normal binding everywhere else. A mouseover state driver
-- clears keys left behind when a frame hides under the cursor.
-- Forms: the header carries a "bcform" state driver (the same driver as
-- normal form keys). The snippet uses that state's tables, and when forms
-- change what a click does it also writes that state's remaps onto the
-- hovered frame (secure code may set attributes in combat). A form change
-- while hovering re-runs the snippet for the hovered frame.
local ENTER_SNIPPET = [[
    local unit = self:GetAttribute("unit")
    self:ClearBindings()
    if not unit or not keyButton or not stateKeys then return end
    hovered = self
    local state = header:GetAttribute("bcform") or "base"
    if not stateKeys[state] then state = "base" end
    if formClicks and stateClicks[state] then
        local remaps = stateClicks[state]
        for name in pairs(clickNames) do self:SetAttribute(name, remaps[name]) end
    end
    local keys = stateKeys[state]
    if not keys then return end
    local kind = SecureCmdOptionParse("[@" .. unit .. ",harm] harm; [@" .. unit .. ",help] help; none")
    local specific = (kind == "harm" and keys.harm) or (kind == "help" and keys.help) or nil
    keyButton:SetAttribute("unit", unit)
    for key, token in pairs(keys.any) do
        if not (specific and specific[key]) then self:SetBindingClick(true, key, keyButton, token) end
    end
    if specific then
        for key, token in pairs(specific) do self:SetBindingClick(true, key, keyButton, token) end
    end
]]
local LEAVE_SNIPPET = [[
    self:ClearBindings()
    if hovered == self then hovered = nil end
]]
local HEADER_CHANGED_SNIPPET = [[
    if name == "hasunit" and value == "false" and hovered then
        hovered:ClearBindings()
        hovered = nil
    elseif name == "bcform" and hovered then
        self:RunFor(hovered, self:GetAttribute("bc-enter"))
    end
]]

local function EnsureKeyRouting()
    if HOVER.header then return true end
    if InCombatLockdown() or not SecureHandlerWrapScript then return false end
    local header = CreateFrame("Frame", "BindCardsHoverHeader", UIParent,
        "SecureHandlerBaseTemplate,SecureHandlerAttributeTemplate")
    local keyButton = CreateFrame("Button", "BindCardsHoverKeys", UIParent, "SecureActionButtonTemplate")
    keyButton:SetSize(1, 1)
    keyButton:SetAlpha(0)
    keyButton:EnableMouse(false)
    keyButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -300, 0)
    keyButton:Show()
    header:SetFrameRef("keys", keyButton)
    header:Execute([[
        keyButton = self:GetFrameRef("keys")
        header = self
    ]])
    header:SetAttribute("bc-enter", ENTER_SNIPPET)
    header:SetAttribute("_onattributechanged", HEADER_CHANGED_SNIPPET)
    if RegisterAttributeDriver then RegisterAttributeDriver(header, "hasunit", "[@mouseover,exists] true; false") end
    HOVER.header, HOVER.keyButton, HOVER.keyAttributes = header, keyButton, {}
    return true
end

local function IsUnitButton(frame)
    if HOVER.frames[frame] then return true end
    local ok, unit = pcall(frame.GetAttribute, frame, "unit")
    if ok and issecretvalue and issecretvalue(unit) then return true end
    return ok and unit ~= nil
end

-- Some children (TargetFrame.Auras) answer these queries with secret
-- booleans while BindCards is on the stack, and testing one throws. Returns
-- nil for an unreadable answer so the caller leaves that child alone; a
-- missing method reads as false.
local function ReadFlag(object, method)
    local fn = object[method]
    if not fn then return false end
    local ok, value = pcall(fn, object)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    return value == true
end

-- Forbidden, access-constrained or unreadable (secret) regions such as
-- TargetFrame.Auras belong to the secure environment; never touch them or
-- anything under them.
local function Restricted(frame)
    return ReadFlag(frame, "IsForbidden") ~= false or ReadFlag(frame, "HasAccessConstraints") ~= false or
        ReadFlag(frame, "IsMouseMotionEnabled") == nil
end

local function IsStatusBar(frame)
    local ok, kind = pcall(frame.GetObjectType, frame)
    return ok and not (issecretvalue and issecretvalue(kind)) and kind == "StatusBar"
end

-- Health and mana bars on Forever's unit frames enable mouse motion for
-- their hover text, so moving onto them fires OnLeave on the unit frame and
-- would release the keys. Let such bars pass motion to their parent (they
-- keep their own OnEnter). Only StatusBars are changed, as in Clique. Nested
-- unit frames (target of target) and restricted regions are skipped with
-- their subtrees. Out of combat only.
local function PropagateChildMotion(frame, depth)
    if depth > 6 or not frame.GetChildren then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Restricted(child) and not IsUnitButton(child) then
            if IsStatusBar(child) and child.SetPropagateMouseMotion and ReadFlag(child, "IsMouseMotionEnabled") and
                ReadFlag(child, "GetPropagateMouseMotion") == false then
                pcall(child.SetPropagateMouseMotion, child, true)
            end
            PropagateChildMotion(child, depth + 1)
        end
    end
end

local function WrapFrame(frame)
    local info = HOVER.frames[frame]
    if not info or not HOVER.header or InCombatLockdown() then return end
    -- Children can be created later (auras), so walk on every apply.
    PropagateChildMotion(frame, 1)
    if info.wrapped then return end
    local ok = pcall(SecureHandlerWrapScript, frame, "OnEnter", HOVER.header, ENTER_SNIPPET) and
        pcall(SecureHandlerWrapScript, frame, "OnLeave", HOVER.header, LEAVE_SNIPPET)
    info.wrapped = ok
end

function BindCards:RegisterHoverFrame(frame)
    if not ValidFrame(frame) or HOVER.frames[frame] then return false end
    if InCombatLockdown() then
        HOVER.queue[frame] = true
        HOVER.pending = true
        return false
    end
    HOVER.frames[frame] = { blizzard = IsBlizzardUnitButton(frame) }
    HOVER.order[#HOVER.order + 1] = frame
    if HOVER.stamped and HOVER.plan then self:StampHoverFrame(frame) end
    if HOVER.plan and (HOVER.plan.hasKeys or HOVER.plan.hasFormClicks) then WrapFrame(frame) end
    return true
end

-- Global names of Blizzard's unit frames, built once (the discovery runs on
-- every binding apply).
local BLIZZARD_FRAME_NAMES = { "PlayerFrame", "PetFrame", "TargetFrame", "TargetFrameToT", "FocusFrame", "FocusFrameToT" }
for index = 1, 5 do
    BLIZZARD_FRAME_NAMES[#BLIZZARD_FRAME_NAMES + 1] = "CompactPartyFrameMember" .. index
    BLIZZARD_FRAME_NAMES[#BLIZZARD_FRAME_NAMES + 1] = "CompactPartyFramePet" .. index
end
for group = 1, 8 do
    for member = 1, 5 do
        BLIZZARD_FRAME_NAMES[#BLIZZARD_FRAME_NAMES + 1] = "CompactRaidGroup" .. group .. "Member" .. member
    end
end
for index = 1, 80 do BLIZZARD_FRAME_NAMES[#BLIZZARD_FRAME_NAMES + 1] = "CompactRaidFrame" .. index end

local function DiscoverBlizzardFrames()
    for _, name in ipairs(BLIZZARD_FRAME_NAMES) do
        local frame = rawget(_G, name)
        if frame then BindCards:RegisterHoverFrame(frame) end
    end
    local party = rawget(_G, "PartyFrame")
    local pool = party and party.PartyMemberFramePool
    if pool and pool.EnumerateActive then
        for member in pool:EnumerateActive() do
            BindCards:RegisterHoverFrame(member)
            if member.PetFrame then BindCards:RegisterHoverFrame(member.PetFrame) end
        end
    end
end

local function InstallHooks()
    if HOVER.installed then return end
    HOVER.installed = true
    if type(hooksecurefunc) == "function" then
        if type(CompactUnitFrame_SetUpFrame) == "function" then
            hooksecurefunc("CompactUnitFrame_SetUpFrame", function(frame) BindCards:RegisterHoverFrame(frame) end)
        end
        local party = rawget(_G, "PartyFrame")
        if party and type(party.InitializePartyMemberFrames) == "function" then
            hooksecurefunc(party, "InitializePartyMemberFrames", DiscoverBlizzardFrames)
        end
    end
    -- Third-party unit frames use the Clique-style ClickCastFrames registry.
    local existing = rawget(_G, "ClickCastFrames")
    HOVER.registry = {}
    ClickCastFrames = setmetatable({}, {
        __index = HOVER.registry,
        __newindex = function(_, frame, value)
            HOVER.registry[frame] = value or nil
            if value then BindCards:RegisterHoverFrame(frame) end
        end,
    })
    if type(existing) == "table" then
        for frame, value in pairs(existing) do
            if value then ClickCastFrames[frame] = value end
        end
    end
end

-- One plan per form state ("base" plus the class's forms, as compiled by
-- CompileBindings). Mouse clicks become per-click combos (remap attributes on
-- the frames); keys and the wheel become per-scope tables for the snippets.
-- Action attributes for every token of every state are stamped out of combat,
-- so switching form only changes remaps and key tables, which secure snippets
-- can do in combat.
local function RemapAttributes(combos)
    local remaps = {}
    for _, combo in pairs(combos) do
        -- A specific disposition beats "both" on the same click.
        local help = combo.HELP or combo.ANY
        local harm = combo.HARM or combo.ANY
        if help then remaps[combo.prefix .. "helpbutton" .. combo.suffix] = help.token end
        if harm then remaps[combo.prefix .. "harmbutton" .. combo.suffix] = harm.token end
    end
    return remaps
end

local function BuildPlan(addon)
    local compiled = addon.lastCompiledHoverStates or {
        states = { "base" }, byState = { base = addon.lastCompiledHoverBindings or {} }, current = "base",
    }
    local plan = {
        states = compiled.states, driver = compiled.driver, current = compiled.current or "base",
        byState = {}, tokens = {}, keyTokens = {}, clickNames = {}, noopCombos = {},
        applied = {}, hasKeys = false, hasFormClicks = false,
    }
    local preparedByTile = {}
    for _, state in ipairs(plan.states) do
        local combos, keys = {}, { HELP = {}, HARM = {}, ANY = {} }
        for key, tile in pairs(compiled.byState[state] or {}) do
            local prepared = preparedByTile[tile]
            if prepared == nil then
                prepared = addon:PrepareHoverAction(tile) or false
                preparedByTile[tile] = prepared
            end
            if prepared then
                local prefix, suffix, scope = MouseCombo(key)
                if prefix then
                    local id = prefix .. suffix
                    combos[id] = combos[id] or { prefix = prefix, suffix = suffix }
                    combos[id][scope] = prepared
                    plan.tokens[prepared.token] = prepared
                    plan.noopCombos[id] = combos[id]
                else
                    local hover = addon:ParseHoverBinding(key)
                    keys[hover.scope][hover.key] = prepared.token
                    plan.keyTokens[prepared.token] = prepared
                    plan.hasKeys = true
                end
                plan.hasAny = true
                if state == plan.current then plan.applied[key] = tile end
            end
        end
        local remaps = RemapAttributes(combos)
        for name in pairs(remaps) do plan.clickNames[name] = true end
        plan.byState[state] = { combos = combos, keys = keys, remaps = remaps }
    end
    -- Clicks need the snippets only when a form changes what a click does.
    local signature
    for _, state in ipairs(plan.states) do
        local parts = {}
        for name in pairs(plan.clickNames) do
            parts[#parts + 1] = name .. "=" .. tostring(plan.byState[state].remaps[name])
        end
        table.sort(parts)
        local current = table.concat(parts, ";")
        if signature and current ~= signature then plan.hasFormClicks = true end
        signature = signature or current
    end
    return plan
end

local function ActionAttributes(attributes, prepared)
    local token = prepared.token
    if prepared.kind == "spell" then
        attributes["*type-" .. token] = "spell"
        attributes["*spell-" .. token] = prepared.spellCast
    elseif prepared.kind == "item" then
        if prepared.toy then
            attributes["*type-" .. token] = "toy"
            attributes["*toy-" .. token] = prepared.toy
        else
            attributes["*type-" .. token] = "item"
            attributes["*item-" .. token] = prepared.item
        end
    elseif prepared.kind == "macro" then
        attributes["*type-" .. token] = "macro"
        attributes["*macrotext-" .. token] = prepared.macrotext
    end
end

-- Written as nil, but backed up: a form snippet may set it later.
local CLEAR = {}

function BindCards:GetHoverFrameAttributes(frame)
    local info, plan = HOVER.frames[frame], HOVER.plan
    local attributes = {}
    if not info or not plan then return attributes end
    local remaps = plan.byState[plan.current] and plan.byState[plan.current].remaps or {}
    for name in pairs(plan.clickNames) do attributes[name] = remaps[name] or CLEAR end
    -- Modified clicks bound in any form: dodge the native drop (see top).
    if info.blizzard then
        for _, combo in pairs(plan.noopCombos) do
            if combo.prefix ~= "" then attributes[combo.prefix .. "type" .. combo.suffix] = NOOP end
        end
    end
    for _, prepared in pairs(plan.tokens) do ActionAttributes(attributes, prepared) end
    return attributes
end

function BindCards:StampHoverFrame(frame, attributes)
    if InCombatLockdown() then HOVER.pending = true return false end
    attributes = attributes or self:GetHoverFrameAttributes(frame)
    local backup = HOVER.backups[frame] or {}
    HOVER.backups[frame] = backup
    local ok = pcall(function()
        for name, original in pairs(backup) do
            if attributes[name] == nil then
                frame:SetAttribute(name, original ~= NONE and original or nil)
                backup[name] = nil
            end
        end
        for name, value in pairs(attributes) do
            if backup[name] == nil then
                local original = frame:GetAttribute(name)
                backup[name] = original == nil and NONE or original
            end
            if value == CLEAR then frame:SetAttribute(name, nil) else frame:SetAttribute(name, value) end
        end
    end)
    return ok
end

local function RestoreAll()
    for _, frame in ipairs(HOVER.order) do BindCards:StampHoverFrame(frame, {}) end
    HOVER.stamped = false
end

-- Publish the per-form key and click tables to the secure header, the key
-- actions to the key button, and the form driver. An empty plan clears them
-- (wraps stay, and then claim nothing).
local function InstallSecurePlan(plan)
    local secure = plan and (plan.hasKeys or plan.hasFormClicks)
    if not secure and not HOVER.header then return true end
    if not EnsureKeyRouting() then return false end
    local header, button = HOVER.header, HOVER.keyButton
    local ok = pcall(function()
        for name in pairs(HOVER.keyAttributes) do button:SetAttribute(name, nil) end
        local attributes = {}
        for _, prepared in pairs(plan and plan.keyTokens or {}) do ActionAttributes(attributes, prepared) end
        for name, value in pairs(attributes) do button:SetAttribute(name, value) end
        HOVER.keyAttributes = attributes
        local keyDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
        button:RegisterForClicks(keyDown and "AnyDown" or "AnyUp")
        button:SetAttribute("useOnKeyDown", keyDown == true)
        local lines = {
            "if hovered then hovered:ClearBindings() hovered = nil end",
            "stateKeys, stateClicks, clickNames = newtable(), newtable(), newtable()",
            "formClicks = " .. tostring(plan and plan.hasFormClicks == true),
        }
        local scopes = { HELP = "help", HARM = "harm", ANY = "any" }
        if secure then
            for name in pairs(plan.clickNames) do lines[#lines + 1] = ("clickNames[%q] = true"):format(name) end
            for _, state in ipairs(plan.states) do
                local data = plan.byState[state]
                lines[#lines + 1] = "do"
                lines[#lines + 1] = "local keys = newtable()"
                lines[#lines + 1] = "keys.help, keys.harm, keys.any = newtable(), newtable(), newtable()"
                lines[#lines + 1] = ("stateKeys[%q] = keys"):format(state)
                for scope, keys in pairs(data.keys) do
                    for key, token in pairs(keys) do
                        lines[#lines + 1] = ("keys.%s[%q] = %q"):format(scopes[scope], key, token)
                    end
                end
                lines[#lines + 1] = "local remaps = newtable()"
                lines[#lines + 1] = ("stateClicks[%q] = remaps"):format(state)
                for name, token in pairs(data.remaps) do
                    lines[#lines + 1] = ("remaps[%q] = %q"):format(name, token)
                end
                lines[#lines + 1] = "end"
            end
        end
        header:Execute(table.concat(lines, "\n"))
        -- Follow the same form state as normal form keys.
        local driver = secure and plan.driver or nil
        if HOVER.formDriver ~= driver then
            if HOVER.formDriver and UnregisterAttributeDriver then UnregisterAttributeDriver(header, "bcform") end
            if driver and RegisterAttributeDriver then RegisterAttributeDriver(header, "bcform", driver) end
            HOVER.formDriver = driver
        end
        if not driver then header:SetAttribute("bcform", "base") end
    end)
    if ok and secure then
        for _, frame in ipairs(HOVER.order) do WrapFrame(frame) end
    end
    return ok
end

function BindCards:ApplyHoverBindings()
    if InCombatLockdown() then HOVER.pending = true return false end
    HOVER.cliqueActive = CliqueActive()
    local plan = BuildPlan(self)
    local wanted = plan.hasAny and not HOVER.cliqueActive
    if not wanted then
        HOVER.plan = nil
        self.lastAppliedHoverBindings = {}
        if HOVER.stamped then RestoreAll() end
        InstallSecurePlan(nil)
        HOVER.pending = false
        return true
    end
    InstallHooks()
    HOVER.plan = plan
    for frame in pairs(HOVER.queue) do HOVER.queue[frame] = nil; self:RegisterHoverFrame(frame) end
    DiscoverBlizzardFrames()
    local failed = 0
    for _, frame in ipairs(HOVER.order) do
        if not self:StampHoverFrame(frame) then failed = failed + 1 end
    end
    HOVER.stamped = true
    local keysInstalled = InstallSecurePlan(plan)
    HOVER.pending = false
    HOVER.failedFrames = failed
    local applied = {}
    for key, tile in pairs(plan.applied) do
        if keysInstalled or BindCards:IsHoverMouseBinding(key) then applied[key] = tile end
    end
    self.lastAppliedHoverBindings = applied
    return failed == 0 and keysInstalled
end

local function FrameLabel(frame)
    local name = frame and frame.GetName and frame:GetName()
    if name then return name end
    local parent = frame and frame.GetParent and frame:GetParent()
    local key = parent and frame.GetParentKey and frame:GetParentKey()
    return key and (FrameLabel(parent) .. "." .. key) or tostring(frame)
end

-- /bc hover: point at a unit frame and type the command (Enter keeps the
-- cursor in place). Reports the frame under the cursor and what each
-- mouseover key is bound to right now.
function BindCards:ReportHoverState()
    local say = function(text) self:Notify(text) end
    local plan = HOVER.plan
    local wrapped, total = 0, #HOVER.order
    for _, frame in ipairs(HOVER.order) do
        if HOVER.frames[frame].wrapped then wrapped = wrapped + 1 end
    end
    say(("Mouseover: %d unit frames, %d with key handlers%s%s."):format(total, wrapped,
        HOVER.cliqueActive and ", Clique active (BindCards off)" or "",
        InCombatLockdown() and ", in combat" or ""))
    local focus = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
    if not focus then
        say("Nothing under the cursor.")
    else
        local owner = focus
        while owner and not HOVER.frames[owner] do owner = owner.GetParent and owner:GetParent() or nil end
        local motion = focus.GetPropagateMouseMotion and focus:GetPropagateMouseMotion()
        say("Under cursor: " .. FrameLabel(focus) .. (motion and " (passes motion to parent)" or ""))
        if owner then
            local ok, unit = pcall(owner.GetAttribute, owner, "unit")
            say("Unit frame: " .. FrameLabel(owner) .. " unit=" .. tostring(ok and unit) ..
                (HOVER.frames[owner].wrapped and "" or " - key handler missing"))
            if owner ~= focus and not motion then
                say("The cursor is on a child that keeps mouse motion: the unit frame saw a leave. Try /bc rebind out of combat.")
            end
        else
            say("That is not a registered unit frame.")
        end
    end
    local shown = 0
    local state = HOVER.header and HOVER.header:GetAttribute("bcform") or "base"
    if not (plan and plan.byState[state]) then state = "base" end
    if plan and #plan.states > 1 then say("Form state: " .. tostring(state)) end
    local current = plan and plan.byState[state]
    for scope, keys in pairs(current and current.keys or {}) do
        for key, token in pairs(keys) do
            local action = GetBindingAction and GetBindingAction(key, true)
            if issecretvalue and issecretvalue(action) then action = "?" end
            local claimed = type(action) == "string" and action:find("BindCardsHoverKeys", 1, true)
            say(("  %s (%s): %s"):format(key, (self:FormatHoverScope(scope) or scope):lower(),
                claimed and ("claimed -> " .. token) or ("not claimed, now: " .. tostring(action ~= "" and action or "unbound"))))
            shown = shown + 1
        end
    end
    if shown == 0 then say("No mouseover keys are installed (clicks are shown in tile tooltips).") end
end

-- Tooltip status for a mouseover binding; nil defers to the generic text.
function BindCards:GetHoverCastStatus(key)
    if not self:IsHoverBinding(key) then return nil end
    if HOVER.cliqueActive then return "Clique is loaded, so BindCards leaves unit frames to Clique." end
    local tile = (self.lastCompiledHoverBindings or {})[key]
    if HOVER.pending and InCombatLockdown() then return "Changes apply when combat ends." end
    if self.lastAppliedHoverBindings and self.lastAppliedHoverBindings[key] then
        local text = MouseCombo(key) and "Active on unit frames." or
            "Active while the cursor is over a unit frame; the key keeps its normal binding elsewhere."
        if tile and tile.kind == "macro" then text = text .. " Use [@mouseover] in the macro to act on the hovered unit." end
        return text
    end
    if tile and not MouseCombo(key) and not HOVER.header then
        return "Keys over unit frames are unavailable: this client lacks secure hover handlers."
    end
    if tile then return "Could not prepare this action." end
    -- Bound on a form card: name the forms where it applies.
    local compiled, forms = self.lastCompiledHoverStates, {}
    for _, state in ipairs(compiled and compiled.states or {}) do
        if state ~= "base" and compiled.byState[state] and compiled.byState[state][key] then
            local definition = self.FORM_DEFINITIONS and self.FORM_DEFINITIONS[state]
            forms[#forms + 1] = definition and definition.label or state
        end
    end
    if #forms > 0 and HOVER.plan then
        return "Active in " .. table.concat(forms, ", ") .. ". Switches with your form, also in combat."
    end
    return "Not active: its card is not active now."
end

-- Test unit frames (Menu → Test unit frames, or /bc testframes).
-- Party and raid units need a group, so these stand-ins point at units that
-- exist solo. They use Blizzard's SecureUnitButtonTemplate, so clicks take the
-- same Forever path as party/raid frames (native Click Casting check,
-- Target/menu rule, help/harm remap). Each has a mouse-motion health bar like
-- Blizzard's. They register as ordinary unit frames (ClickCastFrames path).
-- Built only on request; Blizzard's compact raid code is not touched.
local TEST_UNITS = {
    { unit = "player", label = "You" },
    { unit = "target", label = "Target" },
    { unit = "targettarget", label = "Target's target" },
    { unit = "focus", label = "Focus" },
    { unit = "pet", label = "Pet" },
}
local TEST_COLORS = {
    friendly = { 0.20, 0.576, 0.498 }, hostile = { 0.769, 0.118, 0.227 }, neutral = { 0.55, 0.55, 0.50 },
}

local function Disposition(unit)
    if not UnitExists(unit) then return nil end
    if UnitCanAttack("player", unit) then return "hostile" end
    if UnitCanAssist("player", unit) then return "friendly" end
    return "neutral"
end

local function UpdateTestButton(button)
    local unit = button.unit
    local kind = Disposition(unit)
    local color = TEST_COLORS[kind or "neutral"]
    button.bar:SetStatusBarColor(color[1], color[2], color[3], kind and 0.85 or 0.25)
    if kind then
        pcall(button.bar.SetMinMaxValues, button.bar, 0, UnitHealthMax(unit))
        pcall(button.bar.SetValue, button.bar, UnitHealth(unit))
        pcall(button.nameText.SetText, button.nameText, UnitName(unit))
    else
        button.bar:SetMinMaxValues(0, 1)
        button.bar:SetValue(1)
        button.nameText:SetText(button.label .. " (none)")
    end
    button.kindText:SetText(kind and (button.label .. " · " .. kind) or "")
end

local function UpdateTestFrames()
    local panel = HOVER.testPanel
    if not panel or not panel:IsShown() then return end
    for _, button in ipairs(panel.buttons) do pcall(UpdateTestButton, button) end
end

local TEST_EVENTS = {
    "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_PET", "UNIT_TARGET",
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_FACTION", "UNIT_NAME_UPDATE",
}

local function BuildTestFrames()
    local panel = CreateFrame("Frame", "BindCardsHoverTest", UIParent, "BackdropTemplate")
    panel:SetSize(170, 46 + #TEST_UNITS * 40)
    panel:SetPoint("LEFT", UIParent, "LEFT", 60, 0)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if panel.SetBackdrop then
        panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        panel:SetBackdropColor(0.035, 0.041, 0.052, 0.92)
        panel:SetBackdropBorderColor(0.93, 0.66, 0.25, 0.6)
    end
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetText("BindCards test frames")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() BindCards:ToggleHoverTestFrames(false) end)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 10, 8)
    hint:SetPoint("BOTTOMRIGHT", -10, 8)
    hint:SetJustifyH("LEFT")
    hint:SetText("Target an enemy for a hostile frame.")
    panel.buttons = {}
    for index, spec in ipairs(TEST_UNITS) do
        local button = CreateFrame("Button", "BindCardsHoverTestUnit" .. index, panel, "SecureUnitButtonTemplate")
        button:SetSize(150, 34)
        button:SetPoint("TOPLEFT", 10, -26 - (index - 1) * 40)
        -- As Blizzard's party frames: *type1 target, *type2 menu, AnyUp clicks.
        SecureUnitButton_OnLoad(button, spec.unit)
        button:SetAttribute("*type2", "togglemenu")
        button.unit, button.label = spec.unit, spec.label
        local background = button:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0, 0, 0, 0.6)
        -- Like Blizzard's health bars, this one catches mouse motion.
        local bar = CreateFrame("StatusBar", nil, button)
        bar:SetPoint("TOPLEFT", 1, -1)
        bar:SetPoint("BOTTOMRIGHT", -1, 1)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        if bar.SetMouseMotionEnabled then bar:SetMouseMotionEnabled(true) end
        button.bar = bar
        button.nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.nameText:SetPoint("TOPLEFT", 5, -4)
        button.nameText:SetPoint("RIGHT", -5, 0)
        button.nameText:SetJustifyH("LEFT")
        button.kindText = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        button.kindText:SetPoint("BOTTOMLEFT", 5, 4)
        button:SetScript("OnEnter", function(self)
            if not UnitExists(self.unit) or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetUnit, GameTooltip, self.unit)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        panel.buttons[index] = button
    end
    panel:SetScript("OnEvent", UpdateTestFrames)
    panel:SetScript("OnShow", function(self)
        for _, event in ipairs(TEST_EVENTS) do pcall(self.RegisterEvent, self, event) end
        UpdateTestFrames()
    end)
    panel:SetScript("OnHide", function(self) self:UnregisterAllEvents() end)
    panel:Hide()
    HOVER.testPanel = panel
    for _, button in ipairs(panel.buttons) do BindCards:RegisterHoverFrame(button) end
    return panel
end

function BindCards:ToggleHoverTestFrames(show)
    if InCombatLockdown() then
        self:Notify("Test frames can be opened or closed out of combat only.")
        return false
    end
    local panel = HOVER.testPanel or BuildTestFrames()
    if show == nil then show = not panel:IsShown() end
    panel:SetShown(show)
    if show then
        -- Wrap and stamp the test buttons with the current mouseover bindings.
        if HOVER.plan then self:ApplyHoverBindings() end
        self:Notify("Test frames shown. Mouseover clicks and keys work on them as on party frames.")
    end
    return true
end
