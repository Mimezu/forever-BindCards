local _, BC = ...

-- Native storage supplies both the icon and native execution. No input hooks,
-- native frame writes, or global PAD bindings are needed. All edits are OOC.
local offsets = { base = 0, lt = 8, rt = 16, both = 24 }
local buttons = { PADDLEFT = 1, PADDUP = 2, PADDRIGHT = 3, PADDDOWN = 4,
    PAD3 = 5, PAD4 = 6, PAD2 = 7, PAD1 = 8 }
local running, queued, ready = false, false, false
local statuses = {}
local function Combat() return InCombatLockdown and InCombatLockdown() end
local function Body(body) return (body or ''):gsub('\r\n', '\n'):gsub('\n+$', '') end
local function Available()
    return C_GamepadUI and C_GamepadUI.GetFirstGamepadActionStorageSlotIndex and
        C_GamepadUI.IsValidGamepadActionStorageSlotIndex and GetActionInfo and
        GetCursorInfo and PlaceAction and PickupAction and ClearCursor
end

function BC:GetGamepadStorageSlot(key)
    local g = self:ParseGamepadShortcut(key)
    if not g or not g.page or not Available() then return nil end
    local position = offsets[g.layer] + buttons[g.button]
    if position >= 5 and position <= 8 then return nil, 'Reserved native control.' end
    local first = C_GamepadUI.GetFirstGamepadActionStorageSlotIndex()
    if type(first) ~= 'number' then return nil end
    -- Blizzard pages contain 32 positions but omit four base face controls.
    local slot = first + (g.page - 1) * 28 + position - 1 - (position > 8 and 4 or 0)
    if C_GamepadUI.IsValidGamepadActionStorageSlotIndex(slot) then return slot end
end

local function Journal()
    local guid = UnitGUID and UnitGUID('player')
    if not guid then return nil end
    BindCardsGamepadStorage = BindCardsGamepadStorage or { characters = {} }
    local db = BindCardsGamepadStorage
    db.characters = db.characters or {}
    db.characters[guid] = db.characters[guid] or { slots = {}, suppressed = {}, serial = 0 }
    return db.characters[guid]
end
local function Read(slot)
    local kind, id = GetActionInfo(slot)
    if not kind then return { kind = 'empty' } end
    local action = { kind = kind, id = id }
    if kind == 'macro' and GetMacroInfo then
        local name, _, body = GetMacroInfo(id)
        action.name, action.body = name, Body(body)
    end
    return action
end
local function Same(a, b)
    if not a or not b or a.kind ~= b.kind then return false end
    if a.kind == 'empty' then return true end
    if a.kind == 'macro' then return a.name == b.name and a.body == b.body end
    return a.id == b.id
end
local function MacroIndices()
    local account, character = GetNumMacros()
    local maximum = MAX_ACCOUNT_MACROS or (Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS) or 120
    local indices = {}
    for index = 1, account do indices[#indices + 1] = index end
    for index = 1, character do indices[#indices + 1] = maximum + index end
    return indices
end
local function FindMacro(action)
    if not GetNumMacros or not GetMacroInfo then return nil end
    for _, index in ipairs(MacroIndices()) do
        local name, _, body = GetMacroInfo(index)
        if name == action.name and Body(body) == action.body then return index end
    end
end
local function Restorable(action)
    if action.kind == 'empty' then return true end
    if action.kind == 'spell' then return (C_Spell and C_Spell.PickupSpell) or PickupSpell end
    if action.kind == 'item' then return (C_Item and C_Item.PickupItem) or PickupItem end
    if action.kind == 'macro' then return PickupMacro and FindMacro(action) end
end

local function Write(slot, action, restoring)
    if Combat() or GetCursorInfo() then return false, 'Waiting for combat to end or cursor to clear.' end
    if not Restorable(action) then return false, 'Cannot safely restore this action type.' end
    local before = Read(slot)
    if not Restorable(before) then return false, 'Cannot safely restore this action type.' end
    local function Pickup()
        if action.kind == 'spell' then
            ((C_Spell and C_Spell.PickupSpell) or PickupSpell)(action.id)
        elseif action.kind == 'item' then
            ((C_Item and C_Item.PickupItem) or PickupItem)(action.id)
        else
            PickupMacro(FindMacro(action))
        end
        if not GetCursorInfo() then error('Action could not be picked up.') end
    end
    local ok, errorText = pcall(function()
        -- Validate the replacement before removing the original action.
        if action.kind ~= 'empty' then Pickup() end
        -- Match the native gamepad editor: empty an occupied slot before
        -- placing its replacement. Direct swaps can be rejected by the client.
        if before.kind ~= 'empty' then
            ClearCursor()
            PickupAction(slot)
            if Read(slot).kind ~= 'empty' then error('Existing action could not be removed.') end
            ClearCursor()
            if action.kind ~= 'empty' then Pickup() end
        end
        if action.kind == 'empty' then
            return
        else
            PlaceAction(slot)
        end
    end)
    -- The cursor was empty on entry, so any remaining payload is ours.
    ClearCursor()
    if not ok or not Same(Read(slot), action) then
        local reason = not ok and ('Native action update failed: ' .. tostring(errorText)) or
            'Native action update was not accepted.'
        if not restoring and not Same(Read(slot), before) then
            local restored = Write(slot, before, true)
            if not restored then reason = reason .. ' Original action could not be restored.' end
        end
        return false, reason
    end
    return true
end

local function TileAction(tile, journal)
    if tile.kind == 'spell' and not tile.highestRank then return { kind = 'spell', id = tile.spellID } end
    if tile.kind == 'item' then return { kind = 'item', id = tile.itemID } end
    if tile.kind ~= 'macro' and not tile.highestRank then return nil, 'Unsupported controller action.' end
    if not GetNumMacros or not GetMacroInfo or not CreateMacro or not PickupMacro then
        return nil, 'Native macros are unavailable.'
    end
    local spellName = tile.highestRank and BC:GetTileDisplay(tile)
    local body = tile.highestRank and ('#showtooltip\n/cast ' .. spellName) or Body(tile.macrotext)
    if #body > 255 then return nil, 'Gamepad macros must fit the native 255-character limit.' end
    local _, icon = BC:GetTileDisplay(tile)
    icon = icon or 134400
    -- Native bars use the stored macro icon. Match it as well as the body;
    -- older question-mark macros must not hide the resolved tooltip icon.
    -- Never edit or delete existing macros (they may be used elsewhere).
    for _, index in ipairs(MacroIndices()) do
        local name, existingIcon, existingBody = GetMacroInfo(index)
        if Body(existingBody) == body and existingIcon == icon then
            return { kind = 'macro', id = index, name = name, body = body }
        end
    end
    local _, count = GetNumMacros()
    local maximum = MAX_CHARACTER_MACROS or (Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_CHARACTER_MACROS) or 30
    if count >= maximum then return nil, 'No free character macro slot for this controller macro.' end
    local name
    repeat
        journal.serial = (journal.serial or 0) + 1
        name = 'BCPad' .. journal.serial
    until not GetMacroIndexByName or GetMacroIndexByName(name) == 0
    local ok, index = pcall(CreateMacro, name, icon, body, true)
    if not ok or not index then return nil, 'Could not create the native controller macro.' end
    local actualName, _, actualBody = GetMacroInfo(index)
    if actualName ~= name or Body(actualBody) ~= body then return nil, 'Native macro was not saved exactly.' end
    return { kind = 'macro', id = index, name = name, body = body }
end
local function Signature(key, tile)
    return table.concat({ key, tile.id, tile.kind, tostring(tile.spellID or tile.itemID or tile.macrotext), tile.highestRank and 'highest' or 'exact' }, '\031')
end
local APPLIED = 'Applied to native gamepad bar. Condition changes during combat wait until combat ends.'

function BC:ReclaimGamepadBinding(key)
    if not ready or not Available() or Combat() then return end
    local slot = self:GetGamepadStorageSlot(key)
    local journal = Journal()
    if not slot or not journal then return end
    local record = journal.slots[slot]
    if record and not Same(Read(slot), record.applied) then journal.slots[slot] = nil end
    journal.suppressed[slot] = nil
end

function BC:ApplyGamepadBindings()
    if running or not ready or not self.db or not Available() then return end
    if Combat() or GetCursorInfo() then self.gamepadPending = true; return end
    local journal = Journal()
    if not journal then return end
    running = true
    local ok, failure = pcall(function()
        statuses = {}
        local desired = journal.enabled == false and {} or self:CompileCurrentGamepadBindings()
        self.lastCompiledGamepadBindings = desired
        self.lastAppliedGamepadBindings = {}
        local slots = {}
        for key, tile in pairs(desired) do
            local slot, reason = self:GetGamepadStorageSlot(key)
            if slot then slots[slot] = { key = key, tile = tile, signature = Signature(key, tile) }
            else statuses[key] = reason or 'Native gamepad storage is unavailable.' end
        end
        for slot, record in pairs(journal.slots) do
            local current = Read(slot)
            if self:GetGamepadStorageSlot(record.key) ~= slot then
                statuses[record.key] = 'Native slot mapping changed; automatic restoration stopped.'
            elseif not Same(current, record.applied) then
                -- A native edit owns the slot now. Do not undo or fight it.
                journal.slots[slot] = nil
                journal.suppressed[slot] = slots[slot] and slots[slot].signature or nil
            elseif not slots[slot] then
                local restored, reason = Write(slot, record.before)
                if restored then journal.slots[slot] = nil
                else statuses[record.key] = reason end
            end
        end
        for slot in pairs(journal.suppressed) do
            if not slots[slot] then journal.suppressed[slot] = nil end
        end
        for slot, target in pairs(slots) do
            if journal.suppressed[slot] == target.signature then
                statuses[target.key] = 'Native bar edited. Reassign this shortcut in BindCards to apply it again.'
            else
                journal.suppressed[slot] = nil
                local record = journal.slots[slot]
                local before = record and record.before or Read(slot)
                if not Restorable(before) then
                    statuses[target.key] = 'Existing native action cannot be restored safely; slot left unchanged.'
                else
                    local action, reason = TileAction(target.tile, journal)
                    if action then
                        local current = Read(slot)
                        if Same(current, action) then
                            -- Track even an already matching native action so
                            -- later edits are respected instead of overwritten.
                            record = record or { before = before }
                            record.key, record.applied = target.key, action
                            journal.slots[slot] = record
                            statuses[target.key] = APPLIED
                        else
                            record = record or { before = before }
                            record.key, record.applied = target.key, action
                            journal.slots[slot] = record
                            local written
                            written, reason = Write(slot, action)
                            if written then statuses[target.key] = APPLIED
                            else
                                -- Roll back a partially accepted native write before retrying.
                                if not Same(Read(slot), current) then Write(slot, current) end
                                record.applied = Read(slot)
                            end
                        end
                    elseif record then
                        -- An invalid replacement must not leave the previous
                        -- BindCards spell in the slot under the new assignment.
                        local restored = Write(slot, record.before)
                        if restored then journal.slots[slot] = nil end
                    end
                    if not statuses[target.key] then statuses[target.key] = reason or 'Controller assignment could not be applied.' end
                end
            end
        end
        for key, tile in pairs(desired) do
            if statuses[key] == APPLIED then self.lastAppliedGamepadBindings[key] = tile end
        end
        self.gamepadPending = false
    end)
    running = false
    if not ok then self.gamepadLastError = tostring(failure)
    else self.gamepadLastError = nil end
    self:Fire('GAMEPAD_BINDINGS_UPDATED')
end

function BC:GetGamepadBindingCapabilities()
    return { capture = true, overrides = Available() and true or false, scope = 'page', pages = 3,
        combatUpdates = false, status = Available() and 'native-storage' or 'unavailable' }
end
function BC:GetGamepadBindingStatus(key, tileId)
    if not self:IsGamepadShortcut(key) then return nil end
    if self.gamepadLastError then return 'Gamepad update failed: ' .. self.gamepadLastError end
    if self.gamepadPending then return 'Gamepad update queued until combat ends or the cursor clears.' end
    if tileId then
        local winner = self.lastCompiledGamepadBindings and self.lastCompiledGamepadBindings[key]
        if winner and winner.id ~= tileId then return 'Another active card overrides this controller shortcut.' end
    end
    if statuses[key] then return statuses[key] end
    local journal = Journal()
    if journal and journal.enabled == false then return 'Gamepad overrides are disabled. Use /bc gamepad on to enable.' end
    if not Available() then return 'Native gamepad action storage is unavailable.' end
    local g = self:ParseGamepadShortcut(key)
    if not g then return 'Legacy PAD binding is inactive; recapture it with a bar selection.' end
    if not g.page then return 'Legacy all-bars assignment. Select a bar to inspect its applied status.' end
    return 'No active override from the selected cards for this shortcut.'
end
function BC:GetGamepadBindingLabel(key, tileId)
    local status = self:GetGamepadBindingStatus(key, tileId)
    return status and status:match('^Applied') and 'active' or 'saved'
end

function BC:SetGamepadBindingsEnabled(enabled)
    local journal = Journal()
    if not journal then return false end
    journal.enabled = enabled == true
    self:ApplyGamepadBindings()
    self:Notify(enabled and 'Gamepad overrides enabled.' or
        'Gamepad overrides disabled; original actions restore outside combat with a clear cursor. Hover any remaining assignment to inspect errors.')
    return true
end

local function Queue()
    if queued or running or not ready then return end
    queued = true
    C_Timer.After(0, function() queued = false; BC:ApplyGamepadBindings() end)
end
BC:RegisterCallback('BINDINGS_APPLIED', Queue)
BC:RegisterCallback('BINDINGS_QUEUED', function() BC.gamepadPending = true end)
BC:RegisterCallback('DATA_CHANGED', Queue)
local events = CreateFrame('Frame')
for _, event in ipairs({ 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'PLAYER_REGEN_ENABLED',
    'ACTIONBAR_SLOT_CHANGED', 'CURSOR_CHANGED', 'UPDATE_MACROS', 'UPDATE_SHAPESHIFT_FORM' }) do
    events:RegisterEvent(event)
end
events:SetScript('OnEvent', function(_, event)
    if event == 'PLAYER_LOGIN' or event == 'PLAYER_ENTERING_WORLD' then ready = true end
    Queue()
end)
