-- Run from the game directory. Actual facade/layouts, mocked rendering API.
-- Verifies geometry and theme lifecycle; screenshots still verify the artwork.
local root="Interface/AddOns/BindCards/"
local M={}; M.__index=M
local frames,textures=0,0
local function Object(kind,parent)
    return setmetatable({kind=kind,parent=parent,regions={},points={},hooks={},
        width=180,height=40,level=20,alpha=1,shown=true,enabled=true},M)
end
function CreateFrame(kind,_,parent) frames=frames+1; return Object(kind,parent) end
function M:IsObjectType(kind) return self.kind==kind end
function M:GetRegions() return unpack(self.regions) end
function M:CreateTexture(_,layer,_,sub)
    textures=textures+1
    local t=Object("Texture",self); t.layer,t.sub=layer,sub
    table.insert(self.regions,t); return t
end
function M:SetSize(w,h) self.width,self.height=w,h; self:Fire("OnSizeChanged") end
function M:GetSize() return self.width,self.height end
function M:SetWidth(w) self.width=w end
function M:SetHeight(h) self.height=h end
function M:GetWidth() return self.width end
function M:GetHeight() return self.height end
function M:SetPoint(...) table.insert(self.points,{...}) end
function M:ClearAllPoints() self.points={} end
function M:SetAllPoints(owner) self.all=owner end
function M:GetFrameLevel() return self.level end
function M:SetFrameLevel(v) self.level=v end
function M:SetFrameStrata(v) self.strata=v end
function M:SetTexture(v) self.texture=v end
function M:SetColorTexture(...) self.color={...} end
function M:SetVertexColor(...) self.tint={...} end
function M:SetTexCoord(...) self.coords={...} end
function M:SetAlpha(v) self.alpha=v end
function M:GetAlpha() return self.alpha end
function M:SetShown(v) self.shown=not not v end
function M:Show() self.shown=true end
function M:Hide() self.shown=false end
function M:SetDrawLayer(layer,sub) self.layer,self.sub=layer,sub end
function M:SetHorizTile(v) self.horizTile=v end
function M:SetVertTile(v) self.vertTile=v end
function M:SetSnapToPixelGrid(v) self.snap=v end
function M:SetTexelSnappingBias(v) self.bias=v end
function M:IsEnabled() return self.enabled end
function M:SetBackdropColor(...) self.bg={...} end
function M:SetBackdropBorderColor(...) self.edge={...} end
function M:HookScript(event,fn)
    self.hooks[event]=self.hooks[event] or {}; table.insert(self.hooks[event],fn)
end
function M:Fire(event,...) for _,fn in ipairs(self.hooks[event] or {}) do fn(self,...) end end
function hooksecurefunc(object,key,hook)
    local original=object[key]
    object[key]=function(...) original(...); hook(...) end
end
function wipe(t) for k in pairs(t) do t[k]=nil end end
C_Texture={}
function C_Texture.GetAtlasInfo(name)
    local w,h=16,16
    if name:find("EdgeTop") or name:find("EdgeBottom") then w,h=256,16
    elseif name:find("EdgeLeft") or name:find("EdgeRight") then w,h=16,256
    elseif name=="Legacy-Challenge-BG" then w,h=920,575
    elseif name=="common-button-list-collapseExpand" then w,h=300,25
    elseif name=="common-searchbar-a" then w,h=120,20 end
    return {file=123,width=w,height=h,leftTexCoord=.1,rightTexCoord=.9,topTexCoord=.2,bottomTexCoord=.8,
        tilesHorizontally=name:sub(1,1)=="_",tilesVertically=name:sub(1,1)=="!"}
end
function M:SetAtlas(name,size)
    self.atlas=name
    if size then local a=C_Texture.GetAtlasInfo(name); self.width,self.height=a.width,a.height end
end
assert(loadfile("StorageInvestigation/dialogueui-forever-source/Interface/AddOns/Blizzard_SharedXML/Mainline/NineSliceLayouts.lua"))()
NineSliceUtil={GetLayout=function(name) return NineSliceLayouts[name] end}
local addon={}
assert(loadfile(root.."EUIFacade.lua"))("BindCards",addon)
assert(loadfile(root.."LegacySkin.lua"))("BindCards",addon)
local S,L=addon.EUIFacade,addon.LegacySkin
S.SetTheme("eui")
local card=CreateFrame("Frame"); card.bindCardsLegacyRole="card"
card:SetSize(330,220); card:SetPoint("CENTER",5,6); S.Panel(card)
local before=frames
S.SetTheme("legacy")
local item=L.objects[card]; local art=item.visuals
assert(frames==before,"Native decorations must not add child frames to the card stack")
assert(card.width==330 and card.height==220 and card.level==20 and #card.points==1)
assert(art.main.layer=="BACKGROUND" and art.border.TopEdge.layer=="BORDER")
assert(art.border.TopEdge.horizTile and art.border.LeftEdge.vertTile)
assert(S.GetVisualState(card).panelBackground.alpha==0)
card:SetBackdropBorderColor(.2,.9,.4,1)
assert(art.border.TopEdge.tint[2]==.9 and card.edge[4]==0,"Drop state must survive backdrop stripping")
card:SetSize(500,300)
assert(art.border.TopLeftCorner.width==16,"Resizing must retain native corner dimensions")
local button=CreateFrame("Button"); S.Button(button)
local ba=L.objects[button].visuals
assert(#ba.main.pieces==9,"Fixed nine-piece button")
button:Fire("OnEnter"); assert(ba.selection.shown)
button:Fire("OnMouseDown"); assert(ba.main.pieces[1].tint[1]==.72)
button:Fire("OnMouseUp"); button:Fire("OnLeave"); assert(not ba.selection.shown)
local count=textures
button:SetSize(240,25); L:Refresh()
assert(textures==count and ba.main.pieces[1].width==5,"Resize must reuse fixed corners")
card.bindCardsLegacyRole="cover"; L:Refresh()
assert(not art.main.shown and L.objects[card].visuals.main.shown)
local rim=L.objects[card].visuals.border
assert(#rim.pieces==8,"Cover rim must not include a center fill or title strip")
for _,height in ipairs({51,35,220}) do
    card:SetSize(330,height)
    for _,piece in ipairs(rim.pieces) do
        local point=piece.points[1]
        local x,y=point[4],-point[5]
        assert(x>=0 and y>=0 and x+piece.width<=330 and y+piece.height<=height,
            "Every border piece must remain within the header/card bounds")
        assert(piece.layer=="BORDER")
    end
    assert(rim.pieces[1].width==5 and rim.pieces[1].height==5)
end
card.bindCardsLegacyRole="card"; L:Refresh(); assert(item.visuals==art and art.main.shown)
for _,theme in ipairs({"eui","violetmist","legacy","eui","legacy"}) do
    S.SetTheme(theme)
    assert(art.main.shown==(theme=="legacy"))
    assert(S.GetVisualState(card).panelBackground.alpha==(theme=="legacy" and 0 or 1))
end
S.Panel(card) -- A facade refresh strips unknown textures before native repaint.
assert(art.main.alpha==1 and art.main.shown)
assert(frames==before+2,"Only the button and original facade border add frames")

-- Run the real overlay construction through its first Skin call so the
-- exclusion cannot regress independently of the production constructors.
local sourceFile=assert(io.open(root.."UI.lua","r"))
local source=sourceFile:read("*a"); sourceFile:close()
for name,alpha in pairs({CreateModal=.68,CreateProfileTransfer=.66}) do
    local construction=assert(source:match("function UI:"..name.."%b().-\n(.-)    overlay:EnableMouse"))
    local ui={}
    local create=assert(loadstring("local UI, UIParent, MODAL_OVERLAY_LEVEL, Skin = ...\nlocal self = UI\n"..
        construction.."\nreturn overlay"))
    local overlay=create(ui,{},100,function(frame,color,border)
        frame:SetBackdropColor(unpack(color)); frame:SetBackdropBorderColor(unpack(border))
        L:Surface(frame,color,border)
    end)
    for _,theme in ipairs({"legacy","eui","legacy"}) do
        S.SetTheme(theme)
        overlay:Fire("OnShow"); overlay:SetSize(2560,1440)
        assert(not L.objects[overlay].visuals,"Screen dimmers must not receive leather artwork")
        assert(overlay.bg[1]==0 and overlay.bg[4]==alpha and overlay.edge[4]==0,
            "Screen dimmers must retain their original translucency")
    end
end
-- A surface excluded after painting must also recover its original backdrop.
local excluded=CreateFrame("Frame")
L:Surface(excluded,{0,0,0,.68},{0,0,0,0})
local oldArt=L.objects[excluded].visuals
excluded.bindCardsLegacyRole="none"; L:Refresh()
assert(not oldArt.main.shown and excluded.bg[4]==.68 and excluded.edge[4]==0)
print("PASS: Legacy skin geometry, layering, state, lazy controls and theme switching")

-- Blizzard Legacy uses the class color for "active" marks (tab dots and bars,
-- Active labels) instead of green; gold stays the selection color.
do
    local facadeAddon = {}
    local oldUnitClass, oldColors = UnitClass, RAID_CLASS_COLORS
    UnitClass = function() return 'Paladin', 'PALADIN', 2 end
    RAID_CLASS_COLORS = { PALADIN = { r = 0.96, g = 0.55, b = 0.73 } }
    local oldBindCards = BindCards
    BindCards = facadeAddon -- the facade registers on the global addon table
    assert(loadfile(root .. '/EUIFacade.lua'))('BindCards', facadeAddon)
    BindCards = oldBindCards
    local S = assert(facadeAddon.EUIFacade)
    local legacy = S.GetPalette('legacy')
    -- Class hue, softened toward the Legacy bronze (A18550) so it is not loud.
    local function Near(value, target) return math.abs(value - target) < 0.01 end
    local bronze = { 0xA1 / 255, 0x85 / 255, 0x50 / 255 }
    local expected = {}
    for i = 1, 3 do expected[i] = ({ 0.96, 0.55, 0.73 })[i] * 0.55 + bronze[i] * 0.45 end
    assert(Near(legacy.teal[1], expected[1]) and Near(legacy.teal[2], expected[2]) and Near(legacy.teal[3], expected[3]),
        'Legacy active accent is the muted class color')
    assert(legacy.teal[1] > legacy.teal[2] and legacy.teal[1] > legacy.teal[3], 'still reads as the Paladin hue')
    assert(legacy.blue[1] == 1 and math.abs(legacy.blue[2] - 0xD1 / 255) < 0.01, 'gold selection unchanged')
    local ps2 = S.GetPalette('ps2')
    assert(math.abs(ps2.teal[1] - 0x83 / 255) < 0.01, 'other themes keep their own accent')
    S.SetTheme('legacy')
    local _, _, border = S.GetTabStyle(false, true, false)
    assert(border and Near(border[1], expected[1]) and Near(border[3], expected[3]),
        'active tab border uses the same muted class color')
    UnitClass = function() return 'Mage', 'MAGE', 8 end
    RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
    local mage = S.GetPalette('legacy').teal
    assert(mage[3] > mage[1] and Near(mage[3], 0.92 * 0.55 + bronze[3] * 0.45), 'follows the current character')
    UnitClass, RAID_CLASS_COLORS = oldUnitClass, oldColors
    print('PASS: Legacy skin active accent follows the class color; selection gold and other themes unchanged')
end

-- An accent painted as a solid color and later recolored must show the accent
-- itself, not accent x accent (it looked darker and orange next to the dots).
do
    local ui = assert(io.open(root .. 'UI.lua', 'rb')):read('*a'):gsub('\r\n', '\n')
    local s = assert(ui:find('local function ThemeSolid(dst, c, alpha)', 1, true))
    local e = assert(ui:find('local function Skin(frame, color, border)', s, true))
    local helpers = assert(loadstring('local UI = ...\n' .. ui:sub(s, e - 1) .. '\nreturn ThemeSolid, Color'))
    local ThemeSolid, Color = helpers({ themeTextures = {} })
    local function Texture()
        local t = { paint = { 1, 1, 1 }, tint = { 1, 1, 1 } }
        function t:SetColorTexture(r, g, b) self.paint = { r, g, b } end
        function t:SetVertexColor(r, g, b) self.tint = { r, g, b } end
        function t:Shown() return { self.paint[1] * self.tint[1], self.paint[2] * self.tint[2], self.paint[3] * self.tint[3] } end
        return t
    end
    local rose = { 0.81, 0.54, 0.54, 1 }
    local mark = Texture()
    ThemeSolid(mark, rose)
    Color(mark, rose)
    local shown = mark:Shown()
    assert(math.abs(shown[1] - 0.81) < 1e-6 and math.abs(shown[2] - 0.54) < 1e-6, 'recolored bar shows the accent, not its square')
    local cream = { 1, 0.95, 0.8, 1 }
    Color(mark, cream)
    shown = mark:Shown()
    assert(shown[1] == 1 and shown[3] == 0.8, 'switching to another color replaces it')
    local dot = Texture() -- white texture tinted by vertex color (tab dots)
    Color(dot, rose)
    shown = dot:Shown()
    assert(math.abs(shown[1] - 0.81) < 1e-6, 'tinted white textures unchanged')
    print('PASS: accent marks show the same color everywhere (no double tint)')
end

-- Selected tab mark: a deeper shade of the accent in Legacy (the selected tab
-- stays dark bronze); other skins keep the ink color for contrast.
do
    local ui = assert(io.open(root .. 'UI.lua', 'rb')):read('*a'):gsub('\r\n', '\n')
    local s = assert(ui:find('-- Brightness of unselected active tab marks in Legacy', 1, true))
    local e = assert(ui:find('function UI:RefreshBinderSelectors()', s, true))
    local accent = { 0.81, 0.54, 0.54, 1 }
    local marked
    local UIx = {}
    local chunk = assert(loadstring('local UI, C, Color = ...\n' .. ui:sub(s, e - 1)))
    chunk(UIx, { teal = accent }, function(_, color) marked = color end)
    local function Tab()
        local t = { label = { SetTextColor = function() end }, activeMark = { SetShown = function() end } }
        for _, m in ipairs({ 'SetBackdropColor', 'SetBackdropBorderColor', 'SetAlpha' }) do t[m] = function() end end
        return t
    end
    local style = 'legacy'
    UIx.euiSkin = {
        GetStyle = function() return style end,
        GetTabStyle = function() return { 0, 0, 0, 1 }, { 1, 0.95, 0.8, 1 }, { 0, 0, 0, 1 } end,
        StyleTab = function() end,
    }
    UIx:StyleAppearanceTab(Tab(), true, true, false)
    assert(marked == accent, 'Legacy selected mark is the accent, not cream')
    UIx:StyleAppearanceTab(Tab(), false, true, false)
    local shade = UIx.LEGACY_UNSELECTED_MARK_SHADE
    assert(shade == 0.5, 'unselected marks at half brightness')
    assert(math.abs(marked[1] - 0.81 * shade) < 1e-6 and math.abs(marked[3] - 0.54 * shade) < 1e-6,
        'Legacy unselected active mark is the darker accent')
    style = 'ps2'
    UIx:StyleAppearanceTab(Tab(), true, true, false)
    assert(marked[1] == 1 and marked[3] == 0.8, 'other skins keep the ink color')
    UIx:StyleAppearanceTab(Tab(), false, true, false)
    assert(marked == accent, 'other skins: unselected mark is the accent')
    print('PASS: Legacy tab marks: accent when selected, deeper accent otherwise; other skins unchanged')
end
