-- lua5.1 tests/RetroSkin.lua [addon root]. Real facade + skins, mocked API.
local root = (... or ".") .. "/"
local M = {}; M.__index = M
local function Object(kind, parent)
    return setmetatable({ kind = kind, parent = parent, regions = {}, points = {}, hooks = {},
        width = 120, height = 24, level = 20, alpha = 1, shown = true, enabled = true }, M)
end
function CreateFrame(kind, _, parent) return Object(kind, parent) end
function CreateFont() return Object("Font") end
function GetPhysicalScreenSize() return 2560, 1440 end
function M:IsObjectType(kind) return self.kind == kind end
function M:GetRegions() return unpack(self.regions) end
function M:GetParent() return self.parent end
function M:GetEffectiveScale() return 1 end
function M:CreateTexture(_, layer, _, sub)
    local t = Object("Texture", self); t.layer, t.sub = layer, sub
    table.insert(self.regions, t); return t
end
function M:CreateFontString()
    local f = Object("FontString", self); f.font, f.size, f.flags = "Fonts\\FRIZQT__.TTF", 11, ""
    f.r, f.g, f.b, f.a, f.sx, f.sy = 1, 1, 1, 1, 1, -1
    return f
end
function M:SetSize(w, h) self.width, self.height = w, h; self:Fire("OnSizeChanged") end
function M:GetSize() return self.width, self.height end
function M:SetWidth(w) self.width = w end
function M:SetHeight(h) self.height = h end
for _, name in ipairs({ "SetPoint", "SetAllPoints", "SetFrameLevel", "SetFrameStrata", "SetTexture",
    "SetVertexColor", "SetTexCoord", "SetDrawLayer", "SetSnapToPixelGrid", "SetTexelSnappingBias",
    "SetJustifyV", "SetShadowColor", "SetFontObject", "SetAtlas" }) do M[name] = function() end end
function M:GetFrameLevel() return self.level end
function M:ClearAllPoints() self.points = {} end
function M:SetColorTexture(...) self.color = { ... } end
function M:SetAlpha(v) self.alpha = v end
function M:GetAlpha() return self.alpha end
function M:SetShown(v) self.shown = not not v end
function M:Show() self.shown = true end
function M:Hide() self.shown = false end
function M:IsEnabled() return self.enabled end
function M:SetBackdropColor(...) self.bg = { ... } end
function M:SetBackdropBorderColor(...) self.edge = { ... } end
function M:SetFont(file, size, flags) self.font, self.size, self.flags = file, size, flags end
function M:GetFont() return self.font, self.size, self.flags end
function M:SetTextColor(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a or 1 end
function M:GetTextColor() return self.r, self.g, self.b, self.a end
function M:SetShadowOffset(x, y) self.sx, self.sy = x, y end
function M:GetShadowOffset() return self.sx, self.sy end
function M:GetJustifyH() return "CENTER" end
function M:SetJustifyH(v) self.justify = v end
function M:SetText(v) self.text = v end
function M:HookScript(event, fn)
    self.hooks[event] = self.hooks[event] or {}; table.insert(self.hooks[event], fn)
end
function M:Fire(event, ...) for _, fn in ipairs(self.hooks[event] or {}) do fn(self, ...) end end
function hooksecurefunc(object, key, hook)
    local original = object[key]
    object[key] = function(...) original(...); hook(...) end
end
function wipe(t) for k in pairs(t) do t[k] = nil end end
C_Texture = { GetAtlasInfo = function() return nil end }

local addon = {}
for _, file in ipairs({ "EUIFacade.lua", "LegacySkin.lua", "RetroSkin.lua" }) do
    assert(loadfile(root .. file))("BindCards", addon)
end
local S, R = addon.EUIFacade, addon.RetroSkin
local function Near(a, b) return math.abs(a - b) < 1e-6 end
local function Shown(frame)
    local n = 0
    for _, t in pairs(R.objects[frame].parts) do if t.shown then n = n + 1 end end
    return n
end

S.SetTheme("eui")
local panel = CreateFrame("Frame"); panel:SetSize(300, 200); S.Panel(panel)
local button = CreateFrame("Button", nil, panel); button:SetSize(88, 24)
button.label = button:CreateFontString(); S.Font(button.label); S.Button(button)
local primary = CreateFrame("Button", nil, panel); primary:SetSize(88, 24)
primary.bindCardsButtonKind = "primary"; S.Button(primary)
local tile = CreateFrame("Button", nil, panel); tile:SetSize(36, 36); tile.bindCardsEntryTile = true; S.Button(tile)
local header = CreateFrame("Frame"); header:SetSize(900, 51); header.bindCardsTopSurface = "header"
header.bindCardsLegacyRole = "cover"; S.Panel(header)
local title = header:CreateFontString(); title.size = 16; S.Font(title); R:Ink(title, "headerInk")
local close = CreateFrame("Button", nil, header); close:SetSize(28, 28)
close.label = close:CreateFontString(); close.label.text = ""; S.CloseButton(close)

-- Default skin: no retro chrome, Friz font, normal shadow.
assert(Shown(panel) == 0 and Shown(button) == 0)
assert(button.label.font == "Fonts\\FRIZQT__.TTF" and button.label.size == 11 and button.label.flags == "")

-- 1440p, scale 1: one physical pixel = 768/1440 UI; size 11 -> 2-pixel dots.
local px = 768 / 1440
S.SetTheme("win31")
assert(S.GetRetro() == "win")
assert(button.label.font:find("RetroBold.ttf", 1, true), "Win 3.1 buttons use the bold System face")
assert(Near(button.label.size, 24 * px) and button.label.flags == "MONOCHROME" and button.label.sx == 0)
assert(Near(S.GetDot(panel), 2 * px))
assert(Shown(button) > 0 and Shown(tile) > 0 and Shown(header) > 0)
assert(R.objects[button].parts.bT and R.objects[button].parts.bT.color[1] == 1, "white top bevel")
assert(R.objects[tile].parts.bT.color[1] == 0.502, "sunken tile: grey top-left")
assert(title.r == 1 and title.g == 1, "white title on the navy bar")
assert(S.GetNativeTopColor("header")[3] > 0.4 and S.GetNativeTopColor("header")[1] == 0, "navy header backdrop")
assert(S.GetNativeTopColor(true) == nil, "tabs keep their own colors")
assert(close.label.text == "\195\151", "retro close prints the font's x")
local glyph = S.GetVisualState(close).closeGlyph
glyph:SetAlpha(1); glyph:Show(); R:Paint(close)
assert(glyph.alpha == 0 and not glyph.shown, "atlas X stays hidden under the font's x")
assert(Near(title.size, 24 * px), "one system size: titles stay on 2-pixel dots")
-- Primary (default) button gets the heavier black rim.
local rim = R.objects[primary].parts.oT
assert(Near(rim.height, 2 * S.GetDot(primary)))
-- Pressed: highlight bevel gives way to the grey inset line.
button:Fire("OnMouseDown")
assert(not R.objects[button].parts.bR.shown and R.objects[button].parts.bT.color[1] == 0.502)
button:Fire("OnMouseUp")

-- A later SetFont (IconButton's bigger glyph) becomes the new base size.
button.label:SetFont("x", 16, "")
assert(Near(button.label.size, 24 * px), "bigger glyphs keep the system size")
button.label:SetFont("x", 11, "")

S.SetTheme("msdos")
assert(button.label.font:find("RetroMono.ttf", 1, true))
button.label:SetTextColor(1, 1, 1, 1)
assert(button.label.r == 0 and button.label.g == 0, "white text turns black on DOS grey buttons")
button.label:SetTextColor(1, 1, 0.333, 1)
assert(Near(button.label.r, 0.667) and Near(button.label.g, 0.333), "yellow becomes CGA brown")
assert(title.r == 0, "black title on the grey menu bar")
assert(R.objects[panel].parts.iT.shown, "double line")
assert(R.objects[button].parts.sR.shown, "button drop shadow")

S.SetTheme("macmono")
assert(button.label.font:find("RetroBold.ttf", 1, true))
assert(R.objects[primary].parts.ringT.shown, "default button ring")
assert(R.objects[header].parts.p4.shown, "pinstripes")
button.label:SetTextColor(0, 0, 0, 1) -- ApplyAppearanceTheme resets inks in game
button:Fire("OnMouseDown")
assert(R.objects[button].parts.inv.shown and button.label.r == 1, "pressed buttons invert")
button:Fire("OnMouseUp")
assert(not R.objects[button].parts.inv.shown and button.label.r == 0, "and restore")

-- Back to a modern skin: everything retro is gone again.
S.SetTheme("eui")
assert(Shown(panel) == 0 and Shown(button) == 0 and Shown(header) == 0)
assert(button.label.font == "Fonts\\FRIZQT__.TTF" and button.label.size == 11 and button.label.flags == "")
assert(button.label.sx == 1 and button.label.sy == -1, "shadow restored")
assert(close.label.text == "")
-- Translucent dimmers never get chrome.
local dim = CreateFrame("Frame"); dim:SetSize(500, 500); R:Surface(dim, { 0, 0, 0, 0.3 })
S.SetTheme("win31"); assert(Shown(dim) == 0)
print("PASS: retro skins: fonts snap to whole pixels, chrome per role, inks, press states, clean exit")
