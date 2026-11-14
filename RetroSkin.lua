local _, private = ...
local Addon = _G.BindCards or private
local S = Addon.EUIFacade
local R = { objects = setmetatable({}, { __mode = "k" }), inks = setmetatable({}, { __mode = "k" }) }
Addon.RetroSkin = R

-- Chrome for the retro desktops (Mac 1-bit, MS-DOS, Windows 3.1). Drawn on
-- top of the flat palette surfaces: outlines, bevels, shadows, pinstripes and
-- double lines measured in retro "dots" (the font's pixel size). Decoration
-- only: no geometry, strata, scripts or stacking changes.
local BLACK, WHITE = { 0, 0, 0, 1 }, { 1, 1, 1, 1 }
local GRAY, FACE = { 0.502, 0.502, 0.502, 1 }, { 0.753, 0.753, 0.753, 1 }
local SHADOW = { 0, 0, 0, 0.85 }

local function Kind() return S.GetRetro and S.GetRetro() end

local function Role(frame, data)
    local ui = Addon.UI
    if ui and (frame == ui.frame or frame == ui.centerPanel) then return "none" end
    if data and data.close then return "close" end
    if frame.bindCardsTopSurface == "header" then return "header" end
    if ui and (frame == ui.modal or frame == ui.capture or frame == ui.profileManager or
        frame == ui.profileTransfer or frame == ui.displayPopover) then return "cover" end
    if frame.bindCardsLegacyRole then return frame.bindCardsLegacyRole end
    if data and data.shell then return "cover" end
    if frame.bindCardsEntryTile then return "tile" end
    if frame.bindCardsTopSurface then return "tab" end
    if frame.bindCardsCardSurface then return "card" end
    if data and data.editBox then return "edit" end
    if frame:IsObjectType("Button") or (data and data.button) then return "button" end
    return "panel"
end

-- Parts ---------------------------------------------------------------------
local function Part(item, frame, key, layer, sub)
    local t = item.parts[key]
    if not t then
        t = frame:CreateTexture(nil, layer or "OVERLAY", nil, sub or -8)
        item.parts[key] = t
    end
    item.used[key] = true
    return t
end

local function Rect(item, frame, key, x, y, w, h, color, layer, sub)
    local t = Part(item, frame, key, layer, sub)
    if w <= 0 or h <= 0 then item.used[key] = nil; return end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
    t:SetSize(w, h)
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

local function Outline(item, frame, key, W, H, inset, t, color)
    local span = W - 2 * inset
    Rect(item, frame, key .. "T", inset, inset, span, t, color)
    Rect(item, frame, key .. "B", inset, H - inset - t, span, t, color)
    Rect(item, frame, key .. "L", inset, inset + t, t, H - 2 * inset - 2 * t, color)
    Rect(item, frame, key .. "R", W - inset - t, inset + t, t, H - 2 * inset - 2 * t, color)
end

-- Light top/left, dark bottom/right; the dark edge owns the shared corners.
local function Bevel(item, frame, key, W, H, inset, t, light, dark)
    Rect(item, frame, key .. "T", inset, inset, W - 2 * inset - t, t, light)
    Rect(item, frame, key .. "L", inset, inset + t, t, H - 2 * inset - 2 * t, light)
    Rect(item, frame, key .. "B", inset, H - inset - t, W - 2 * inset, t, dark)
    Rect(item, frame, key .. "R", W - inset - t, inset, t, H - 2 * inset - t, dark)
end

local function Corners(item, frame, key, W, H, inset, size, color)
    Rect(item, frame, key .. "1", inset, inset, size, size, color)
    Rect(item, frame, key .. "2", W - inset - size, inset, size, size, color)
    Rect(item, frame, key .. "3", inset, H - inset - size, size, size, color)
    Rect(item, frame, key .. "4", W - inset - size, H - inset - size, size, size, color)
end

local function Shadow(item, frame, key, W, H, dx, dy, color)
    Rect(item, frame, key .. "R", W, dy, dx, H, color, "BACKGROUND", -8)
    Rect(item, frame, key .. "B", dx, H, W - dx, dy, color, "BACKGROUND", -8)
end

-- Color directly behind a control, for the "cut" corners of rounded buttons.
local function Behind(frame)
    local parent = frame.GetParent and frame:GetParent()
    while parent do
        if parent.bindCardsTopSurface == "header" then return S.GetThemeColor("headerTop") or WHITE end
        local owner = R.objects[parent]
        if owner and owner.color and (owner.color[4] or 1) >= 0.9 then return owner.color end
        parent = parent.GetParent and parent:GetParent()
    end
    return S.GetPalette().panel
end

local function Big(W, H) return W >= 60 and H >= 40 end

-- Layouts -------------------------------------------------------------------
local Layout = {}

function Layout.mac(frame, item, role, data, W, H, d)
    if role == "edit" or role == "tile" or role == "panel" or role == "card" or role == "sheet" or
        role == "cover" or role == "header" or role == "tab" then
        Outline(item, frame, "o", W, H, 0, d, BLACK)
    end
    if role == "button" or role == "close" then
        Outline(item, frame, "o", W, H, 0, d, BLACK)
        Corners(item, frame, "c", W, H, 0, d, Behind(frame))
        if frame.bindCardsButtonKind == "primary" then
            -- The default button's heavy rounded ring, one dot clear of it.
            Outline(item, frame, "ring", W, H, -3 * d, 2 * d, BLACK)
            Corners(item, frame, "rc", W, H, -3 * d, d, Behind(frame))
        end
        local enabled = not frame.IsEnabled or frame:IsEnabled()
        if item.pressed and enabled then
            Rect(item, frame, "inv", d, d, W - 2 * d, H - 2 * d, BLACK, "BACKGROUND", 7)
            local label = frame.label
            if label and not item.pressInk then
                item.pressInk = { label:GetTextColor() }
                label:SetTextColor(1, 1, 1, 1)
            end
        end
    end
    if role == "cover" or role == "card" or role == "sheet" or role == "header" then
        Shadow(item, frame, "s", W, H, d, d, BLACK)
    end
    if (role == "header" or role == "cover") and W >= 80 and H >= 40 then
        -- Title-bar pinstripes across the top band.
        for line = 1, role == "header" and 4 or 3 do
            Rect(item, frame, "p" .. line, 2 * d, 2 * d * line, W - 4 * d, d, BLACK, "BACKGROUND", 7)
        end
    end
end

function Layout.dos(frame, item, role, data, W, H, d)
    local line = item.border or S.GetPalette().border
    if role == "cover" or role == "card" or role == "sheet" or (role == "panel" and Big(W, H)) then
        Outline(item, frame, "o", W, H, 0, d, line)
        Outline(item, frame, "i", W, H, 2 * d, d, line)
    end
    if role == "cover" or role == "card" or role == "sheet" then
        Shadow(item, frame, "s", W, H, 4 * d, 4 * d, SHADOW)
    end
    if role == "button" or role == "close" then
        local enabled = not frame.IsEnabled or frame:IsEnabled()
        if not (item.pressed and enabled) then Shadow(item, frame, "s", W, H, 2 * d, 2 * d, BLACK) end
        if frame.label and frame.bindCardsButtonKind ~= "primary" then R:Ink(frame.label, "buttonInk") end
    end
end

function Layout.win(frame, item, role, data, W, H, d)
    if role == "button" or role == "close" or role == "tab" then
        local selected = role == "tab" and data.tabState and data.tabState.selected
        local t = frame.bindCardsButtonKind == "primary" and 2 * d or d
        Outline(item, frame, "o", W, H, 0, t, BLACK)
        Corners(item, frame, "c", W, H, 0, d, Behind(frame))
        local enabled = not frame.IsEnabled or frame:IsEnabled()
        if selected then
            -- Selected tabs are flat navy highlight, like a chosen list item.
        elseif item.pressed and enabled then
            Rect(item, frame, "bT", t, t, W - 2 * t, d, GRAY)
            Rect(item, frame, "bL", t, t + d, d, H - 2 * t - d, GRAY)
        else
            Bevel(item, frame, "b", W, H, t, d, WHITE, GRAY)
        end
    elseif role == "tile" then
        Bevel(item, frame, "b", W, H, 0, d, GRAY, WHITE)
    elseif role == "edit" or role == "panel" or role == "card" or role == "header" then
        Outline(item, frame, "o", W, H, 0, d, BLACK)
    elseif role == "cover" or role == "sheet" then
        -- Window frame: black rim, two dots of face grey, black inner rim.
        Outline(item, frame, "o", W, H, 0, d, BLACK)
        if Big(W, H) then
            Outline(item, frame, "f", W, H, d, 2 * d, FACE)
            Outline(item, frame, "i", W, H, 3 * d, d, BLACK)
        end
    end
end

-- Painting ------------------------------------------------------------------
function R:Paint(frame)
    local item = self.objects[frame]
    if not item or item.painting then return end
    item.painting = true
    for key in pairs(item.used) do item.used[key] = nil end
    local kind = Kind()
    local data = S.GetVisualState(frame)
    local role = Role(frame, data)
    local W, H = frame:GetSize()
    local on = kind and Layout[kind] and role ~= "none" and type(W) == "number" and W >= 10 and H >= 10 and
        not (item.color and (item.color[4] or 1) < 0.4)
    if on then Layout[kind](frame, item, role, data, W, H, S.GetDot(frame)) end
    for key, t in pairs(item.parts) do t:SetShown(item.used[key] == true) end
    if item.pressInk and not item.used.inv then
        if frame.label then frame.label:SetTextColor(unpack(item.pressInk)) end
        item.pressInk = nil
    end
    -- The close glyph is an atlas X; retro skins print their own font's ×.
    if role == "close" and frame.label then
        local glyph = data.closeGlyph
        if on and not item.closeText then
            item.closeText = true
            frame.label:SetText("\195\151")
            if glyph then glyph:SetAlpha(0) end
        elseif not on and item.closeText then
            item.closeText = nil
            frame.label:SetText("")
            if glyph then glyph:SetAlpha(1) end
        end
    end
    item.painting = nil
end

function R:Surface(frame, color, border)
    if not frame or not frame.CreateTexture then return end
    local item = self.objects[frame]
    if not item then
        item = { parts = {}, used = {}, color = color, border = border }
        self.objects[frame] = item
        if frame.HookScript then
            frame:HookScript("OnSizeChanged", function() if Kind() then R:Paint(frame) end end)
            frame:HookScript("OnShow", function() R:Paint(frame) end)
            if frame:IsObjectType("Button") then
                local function Press(down)
                    item.pressed = down
                    if Kind() or item.pressInk then R:Paint(frame) end
                end
                frame:HookScript("OnMouseDown", function() Press(true) end)
                frame:HookScript("OnMouseUp", function() Press(false) end)
                frame:HookScript("OnHide", function() item.pressed = false end)
                frame:HookScript("OnEnable", function() if Kind() then R:Paint(frame) end end)
                frame:HookScript("OnDisable", function() if Kind() then R:Paint(frame) end end)
            end
        end
        -- Track the colors BindCards asks for (hover, selection, drop) so the
        -- chrome follows them. Blizzard Legacy zeroes backdrops; ignore those.
        if hooksecurefunc and frame.SetBackdropBorderColor then
            hooksecurefunc(frame, "SetBackdropBorderColor", function(_, r, g, b, a)
                if item.painting or S.GetStyle() == "legacy" then return end
                item.border = { r, g, b, a or 1 }
                if Kind() then R:Paint(frame) end
            end)
            hooksecurefunc(frame, "SetBackdropColor", function(_, r, g, b, a)
                if item.painting or S.GetStyle() == "legacy" then return end
                item.color = { r, g, b, a or 1 }
                if Kind() then R:Paint(frame) end
            end)
        end
    end
    if color then item.color = color end
    if border then item.border = border end
    self:Paint(frame)
end

-- Inks ----------------------------------------------------------------------
-- A font string whose color follows a retro-only theme color: header text on
-- the navy/grey title bar, dark text on DOS grey buttons.
local inking
local function Darken(r, g, b)
    if math.abs(r - g) < 0.08 and math.abs(g - b) < 0.08 then return 0, 0, 0 end
    if r > 0.6 and g > 0.6 and b < 0.5 then return 0.667, 0.333, 0 end   -- yellow -> brown
    return r > 0.6 and 0.667 or 0, g > 0.6 and 0.667 or 0, b > 0.6 and 0.667 or 0
end

local function InkColor(key, r, g, b)
    local color = S.GetThemeColor(key)
    if not color then return end
    if key == "buttonInk" then return Darken(r or 1, g or 1, b or 1) end
    return color[1], color[2], color[3]
end

function R:Ink(fontString, key)
    if not fontString or self.inks[fontString] then return end
    self.inks[fontString] = key
    if hooksecurefunc then
        hooksecurefunc(fontString, "SetTextColor", function(fs, r, g, b, a)
            if inking then return end
            local nr, ng, nb = InkColor(key, r, g, b)
            if not nr then return end
            inking = true
            fs:SetTextColor(nr, ng, nb, a or 1)
            inking = nil
        end)
    end
    if Kind() then fontString:SetTextColor(fontString:GetTextColor()) end
end

function R:Refresh()
    for frame in pairs(self.objects) do self:Paint(frame) end
    if Kind() then
        for fontString in pairs(self.inks) do fontString:SetTextColor(fontString:GetTextColor()) end
    end
end

-- UI scale changed: re-snap fonts and chrome to whole screen pixels.
function R:Rescale()
    if not Kind() then return end
    if S.RefreshFonts then S.RefreshFonts() end
    self:Refresh()
end

-- Finish after facade methods have painted their own flat regions.
for _, name in ipairs({ "Shell", "Panel", "Button", "EditBox", "TopSurface", "StyleTab", "CloseButton" }) do
    local original = S[name]
    S[name] = function(frame, ...)
        local result = original(frame, ...)
        if frame then R:Surface(frame) end
        return result
    end
end
for _, name in ipairs({ "SetTheme", "RefreshLooks" }) do
    local original = S[name]
    S[name] = function(...)
        local result = original(...)
        R:Refresh()
        return result
    end
end
