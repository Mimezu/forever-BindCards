-- Run from the game directory. Uses the extracted beta's real state-driver
-- and secure-action dispatch code; only native APIs/frame storage are mocked.
local root = "Interface/AddOns/BindCards"
local sourceRoot = "StorageInvestigation/dialogueui-forever-source/Interface/AddOns/"
local function Read(path)
    local f = assert(io.open(path, "r")); local s = f:read("*a"); f:close(); return s
end
local fixture = Read("StorageInvestigation/attach-validation-20260918/tests/BindCardsSmoke.lua")
fixture = fixture:sub(1, assert(fixture:find(";(function()", 1, true)) - 1)
fixture = fixture:gsub('local playerClass = "EVOKER"', 'local playerClass = "DRUID"')
loadstring_untainted = nil -- Reproduce the reported client defect.
local addon = assert(loadstring(fixture .. "\nreturn BindCards"))(root)
local combat, form, nativeUpdate, selfCast, focusCast = false, 0, false, false, false
local nativeWrites, cast, failDriver = 0, nil, false
InCombatLockdown = function() return combat end
local oldCreate = CreateFrame
local function GetAttribute(self, prefix, name, suffix)
    local a = self.attributes
    if not name then return a[prefix] end
    return a[prefix .. name .. suffix] or a["*" .. name .. suffix] or
        a[prefix .. name .. "*"] or a["*" .. name .. "*"] or a[name]
end
CreateFrame = function(kind, name, parent, template)
    assert(template ~= "SecureHandlerStateTemplate", "Must not create a snippet manager")
    local frame = oldCreate(kind, name, parent, template)
    frame.scripts = {}
    frame.GetAttribute = GetAttribute
    function frame:SetScript(event, fn) self.scripts[event] = fn end
    function frame:SetAttribute(key, value)
        assert(not combat or nativeUpdate, "Addon changed a protected attribute in combat")
        self.attributes[key] = value
        if self.scripts.OnAttributeChanged then self.scripts.OnAttributeChanged(self, key, value) end
    end
    function frame:Execute() error("Restricted compiler must never be entered") end
    function frame:Hide() self.shown = false end
    if name then _G[name] = frame end
    return frame
end
CopyTable = addon.CopyTable
GetFrameMetatable = function() return { __index = { GetAttribute = GetAttribute } } end
strmatch, gsub = string.match, string.gsub
table.wipe = function(t) for k in pairs(t) do t[k] = nil end end
IsShiftKeyDown = function() return false end
IsControlKeyDown, IsAltKeyDown = IsShiftKeyDown, IsShiftKeyDown
IsModifiedClick = function(kind) return (kind == "SELFCAST" and selfCast) or (kind == "FOCUSCAST" and focusCast) end
UnitHasVehicleUI = function() return false end
SpellCanTargetItem = function() return false end
SpellCanTargetItemID = SpellCanTargetItem
UnitExists = function() return true end
UnitCanAttack = function() return false end
UnitCanAssist = function(_, unit) return unit == "player" end
CastSpellByID = function(id, unit) cast = { kind = "spell", id = id, unit = unit } end
CastSpellByName = function() error("Must preserve exact ranks") end
C_Macro = { RunMacroText = function(text) cast = { kind = "macro", text = text } end }
SecureCmdOptionParse = function(driver)
    for clause in driver:gmatch("[^;]+") do
        local condition, value = clause:match("^%s*%[([^%]]+)%]%s*(.-)%s*$")
        if not condition then return clause:match("^%s*(.-)%s*$") end
        if (condition == "noform" and form == 0) or condition == "form:" .. form then return value end
    end
end
assert(loadfile(sourceRoot .. "Blizzard_RestrictedAddOnEnvironment/SecureStateDriver.lua"))()
assert(loadfile(sourceRoot .. "Blizzard_FrameXML/SecureTemplates.lua"))()
local nativeRegister = RegisterAttributeDriver
RegisterAttributeDriver = function(...)
    assert(not combat, "Addon registered a driver in combat")
    if failDriver then failDriver = false; error("Injected driver failure") end
    nativeWrites = nativeWrites + 1
    return nativeRegister(...)
end
local nativeUnregister = UnregisterAttributeDriver
UnregisterAttributeDriver = function(...)
    assert(not combat, "Addon unregistered a driver in combat")
    return nativeUnregister(...)
end
local oldClear, oldClick = ClearOverrideBindings, SetOverrideBindingClick
ClearOverrideBindings = function(...) assert(not combat); return oldClear(...) end
SetOverrideBindingClick = function(...) assert(not combat); return oldClick(...) end
GetNumShapeshiftForms = function() return 2 end
GetShapeshiftFormInfo = function(index) return 1, form == index, true, index == 1 and 5487 or 768 end
GetShapeshiftForm = function() return form end
addon.RequestRecompile = function() end
addon:InitializeDatabase()
local profile = assert(addon:CreateProfile("Forms", nil, "class:DRUID"))
addon.GetSelectedProfileSets = function() return nil, profile end
addon.GetSelectedProfile = function() return profile end
local base = profile.cards[1]
local bear = assert(addon:CreateCard({ name = "BEAR", parentId = base.id,
    condition = { form = "druid_bear" } }, profile.id))
local attack = assert(addon:CreateTile(base.id, { kind = "spell", spellID = 5176, bindings = { "F6" } }, profile.id))
local maul = assert(addon:CreateTile(bear.id, { kind = "spell", spellID = 6807, bindings = { "F6", "BUTTON3" } }, profile.id))
local body = "/cast [@mouseover,help] Rejuvenation; Healing Touch\n/say untouched"
local macro = assert(addon:CreateTile(bear.id, { kind = "macro", macrotext = body, bindings = { "F7" } }, profile.id))
assert(addon:SetTileBinding(attack.id, "F6", true, profile.id))
assert(addon:SetTileBinding(maul.id, "F6", true, profile.id))
assert(addon:SetTileBinding(maul.id, "BUTTON3", false, profile.id))
assert(addon:SetTileBinding(macro.id, "F7", true, profile.id))
assert(addon:ApplyBindings("bear-created"))
assert(not addon.formBindingManager and addon.lastAppliedFormBindingPlan.nativeDrivers)
local function Shift(index)
    form = index
    nativeUpdate = true
    SecureStateDriverManager.scripts.OnEvent(SecureStateDriverManager, "UPDATE_SHAPESHIFT_FORM")
    SecureStateDriverManager.scripts.OnUpdate(SecureStateDriverManager, 1)
    nativeUpdate = false
end
local function Click(key)
    local name, token = (GetBindingAction(key, true) or ""):match("^CLICK ([^:]+):(.+)$")
    assert(name and token, "Missing live binding for " .. key)
    cast = nil
    local button = assert(_G[name])
    SecureActionButton_OnClick(button, token, button:GetAttribute("useOnKeyDown"), true)
    return cast
end
for _,keyDown in ipairs({true, false}) do
    GetCVarBool = function(name) return name == "ActionButtonUseKeyDown" and keyDown end
    assert(addon:ApplyBindings("key-trigger"))
    local registered = nativeWrites
    combat = true
    Shift(0); assert(Click("F6").id == 5176 and Click("BUTTON3") == nil)
    Shift(1); assert(Click("F6").id == 6807 and Click("BUTTON3").id == 6807)
    assert(Click("F7").text == body, "Macro conditionals/newlines must remain untouched")
    assert(Click("F6").unit == nil, "Routing must not force the real action onto the player")
    selfCast = true; assert(Click("F6").unit == "player"); selfCast = false
    focusCast = true; assert(Click("F6").unit == "focus"); focusCast = false
    Shift(2); assert(Click("F6").id == 5176 and Click("F7") == nil)
    Shift(1); assert(Click("F6").id == 6807)
    assert(nativeWrites == registered, "Combat switches must need no addon reconfiguration")
    combat = false
end
-- Failed rebuild restores the previous native drivers and secure payloads.
failDriver = true
assert(not addon:ApplyBindings("injected-failure"))
combat = true; Shift(0); assert(Click("F6").id == 5176)
Shift(1); assert(Click("F6").id == 6807); combat = false
-- Same spell ID with different rank modes must remain distinct form routes.
maul.spellID = attack.spellID
assert(addon:SetTileHighestRank(maul.id, true, profile.id))
CastSpellByName = function(name, unit) cast = { kind = "name", name = name, unit = unit } end
assert(addon:ApplyBindings("highest-form"))
combat = true
Shift(0); assert(Click("F6").id == 5176)
Shift(1); assert(Click("F6").name == "Spell 5176")
selfCast = true; assert(Click("F6").unit == "player"); selfCast = false
combat = false
-- Removing the final conditional card unregisters all obsolete drivers.
local proxy = addon.bindingProxy
assert(addon:DeleteCard(bear.id, profile.id))
assert(addon:ApplyBindings("bear-deleted"))
for attribute in pairs(proxy.attributes) do
    assert(not attribute:find("BC_FORM_", 1, true), "Stale native routing attribute")
end
combat = true; Shift(1); assert(Click("F6").id == 5176); combat = false
-- Ambient recompiles (zone, combat end) skip the secure reinstall when the
-- compiled result is unchanged, but still install real changes.
local clears = 0
local countedClear = ClearOverrideBindings
ClearOverrideBindings = function(...) clears = clears + 1; return countedClear(...) end
assert(addon:ApplyBindings("ZONE_CHANGED"))
assert(addon:ApplyBindings("combat-ended"))
assert(clears == 0, "Unchanged ambient recompiles must not reinstall bindings")
assert(Click("F6").id == 5176, "Skipped recompile keeps the live binding")
local rejuv = assert(addon:CreateTile(base.id, { kind = "spell", spellID = 774, bindings = { "F8" } }, profile.id))
assert(addon:SetTileBinding(rejuv.id, "F8", true, profile.id))
assert(addon:ApplyBindings("ZONE_CHANGED"))
assert(clears > 0 and Click("F8").id == 774, "A changed result installs even for an ambient reason")
clears = 0
addon.bindingsPending = "queued-in-combat"
assert(addon:ApplyBindings("combat-ended"))
assert(clears > 0 and not addon.bindingsPending, "Pending work always reinstalls")
ClearOverrideBindings = countedClear
print("PASS: native form drivers switch actions in combat, both key edges, exact ranks, macro payloads, targets, inactive keys, rollback, removal and unchanged-recompile skipping")
