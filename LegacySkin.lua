local _, private = ...
local Addon = _G.BindCards or private
local S = Addon.EUIFacade
local L = { objects = setmetatable({}, { __mode = "k" }) }
Addon.LegacySkin = L

-- Decorations only: no changes to card geometry, frame strata, input scripts,
-- binding state, or attachment/stack ordering. Independent of Frame Gambit.
local function Enabled() return S.GetStyle() == "legacy" end
local function Texture(frame, atlas, layer, sub)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetAtlas(atlas, true)
    return t
end

-- The smooth rail uses a center texel of the native atlas. Repeating the
-- entire ornamented edge produces the seams found during Frame Gambit QA.
local function Plate(frame, atlas, borderOnly)
    local art = { pieces = {} }
    function art:Update()
        local info = C_Texture.GetAtlasInfo(atlas)
        if not info then return end
        local w,h = frame:GetSize()
        if w <= 0 or h <= 0 then return end
        if self.w == w and self.h == h then return end
        self.w,self.h = w,h
        local x,y = math.min(5,w/2,info.width/2),math.min(5,h/2,info.height/2)
        local iw,ih = info.width,info.height
        local sections = {
            {0,0,x,y,0,0,x,y}, {w-x,0,x,y,iw-x,0,x,y},
            {0,h-y,x,y,0,ih-y,x,y}, {w-x,h-y,x,y,iw-x,ih-y,x,y},
            {x,0,w-2*x,y,math.floor(iw/2),0,1,y},
            {x,h-y,w-2*x,y,math.floor(iw/2),ih-y,1,y},
            {0,y,x,h-2*y,0,math.floor(ih/2),x,1},
            {w-x,y,x,h-2*y,iw-x,math.floor(ih/2),x,1},
            {x,y,w-2*x,h-2*y,x,y,iw-2*x,ih-2*y},
        }
        for i,p in ipairs(sections) do
            if borderOnly and i==9 then break end
            local t = self.pieces[i] or frame:CreateTexture(nil,borderOnly and "BORDER" or "BACKGROUND",nil,borderOnly and 1 or -2)
            self.pieces[i] = t
            t:SetTexture(info.file or info.filename)
            local du,dv = info.rightTexCoord-info.leftTexCoord,info.bottomTexCoord-info.topTexCoord
            t:SetTexCoord(info.leftTexCoord+du*p[5]/iw,info.leftTexCoord+du*(p[5]+p[7])/iw,
                info.topTexCoord+dv*p[6]/ih,info.topTexCoord+dv*(p[6]+p[8])/ih)
            t:ClearAllPoints(); t:SetPoint("TOPLEFT",frame,"TOPLEFT",p[1],-p[2])
            t:SetSize(math.max(.01,p[3]),math.max(.01,p[4]))
            t:SetShown(self.visible ~= false)
        end
    end
    function art:SetShown(show)
        self.visible=show
        if show then self:Update() end
        for _,t in ipairs(self.pieces) do t:SetAlpha(1); t:SetShown(show) end
    end
    function art:Tint(color)
        for _,t in ipairs(self.pieces) do t:SetVertexColor(color[1],color[2],color[3],color[4] or 1) end
    end
    art:Update()
    return art
end

local function Leather(frame)
    local t = Texture(frame,"Legacy-Challenge-BG","BACKGROUND",-4)
    t:ClearAllPoints(); t:SetPoint("TOPLEFT",3,-3); t:SetPoint("BOTTOMRIGHT",-3,3)
    local info = C_Texture.GetAtlasInfo("Legacy-Challenge-BG")
    if info then
        local du,dv=info.rightTexCoord-info.leftTexCoord,info.bottomTexCoord-info.topTexCoord
        t:SetTexture(info.file or info.filename)
        t:SetTexCoord(info.leftTexCoord+.05*du,info.rightTexCoord-.05*du,
            info.topTexCoord+.20*dv,info.bottomTexCoord-.02*dv)
    end
    return t
end

local pieces = {"TopLeftCorner","TopRightCorner","BottomLeftCorner","BottomRightCorner",
    "TopEdge","BottomEdge","LeftEdge","RightEdge"}
local function Border(frame, cover)
    -- Full window top corners include title-bar artwork and are taller than
    -- the toolbar. Use the compact native gold rim without its center fill:
    -- fixed 5px corners and rails remain inside even a collapsed card.
    if cover then return Plate(frame,"common-button-list-collapseExpand",true) end
    -- Textures belong to the existing surface itself, not a high-level child
    -- frame which could cover the next page after BindCards restacks children.
    local container = { pieces = {} }
    function container:CreateTexture()
        local t = frame:CreateTexture(nil,"BORDER",nil,1)
        self.pieces[#self.pieces+1]=t
        return t
    end
    local layout = NineSliceUtil.GetLayout(cover and "ButtonFrameTemplateNoPortrait" or "InsetFrameTemplate")
    -- NineSliceUtil anchors corner pieces to its container. A temporary
    -- layout copies Blizzard's art but anchors corners to the actual owner.
    local copy = {}
    for key,value in pairs(layout) do
        if type(value)=="table" then
            copy[key]={}
            for k,v in pairs(value) do copy[key][k]=v end
        else copy[key]=value end
    end
    -- Anchor the native-size corners directly to the surface. No extra
    -- child frame participates in stacking or steals a card's click target.
    for _,key in ipairs(pieces) do
        local def=copy[key]
        if def then
            local t=container:CreateTexture()
            container[key]=t
            t:SetAtlas(def.atlas,true)
            t:SetDrawLayer("BORDER",1)
            local info=C_Texture.GetAtlasInfo(def.atlas)
            t:SetHorizTile(info and info.tilesHorizontally or false)
            t:SetVertTile(info and info.tilesVertically or false)
            if copy.disableSharpening then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        end
    end
    for _,key in ipairs({"TopLeftCorner","TopRightCorner","BottomLeftCorner","BottomRightCorner"}) do
        local point=({TopLeftCorner="TOPLEFT",TopRightCorner="TOPRIGHT",BottomLeftCorner="BOTTOMLEFT",BottomRightCorner="BOTTOMRIGHT"})[key]
        container[key]:SetPoint(point,frame,point,0,0)
    end
    container.TopEdge:SetPoint("TOPLEFT",container.TopLeftCorner,"TOPRIGHT")
    container.TopEdge:SetPoint("TOPRIGHT",container.TopRightCorner,"TOPLEFT")
    container.BottomEdge:SetPoint("BOTTOMLEFT",container.BottomLeftCorner,"BOTTOMRIGHT")
    container.BottomEdge:SetPoint("BOTTOMRIGHT",container.BottomRightCorner,"BOTTOMLEFT")
    container.LeftEdge:SetPoint("TOPLEFT",container.TopLeftCorner,"BOTTOMLEFT")
    container.LeftEdge:SetPoint("BOTTOMLEFT",container.BottomLeftCorner,"TOPLEFT")
    container.RightEdge:SetPoint("TOPRIGHT",container.TopRightCorner,"BOTTOMRIGHT")
    container.RightEdge:SetPoint("BOTTOMRIGHT",container.BottomRightCorner,"TOPRIGHT")
    function container:SetShown(show) for _,t in ipairs(self.pieces) do t:SetAlpha(1); t:SetShown(show) end end
    function container:Tint(color)
        for _,t in ipairs(self.pieces) do t:SetVertexColor(color[1],color[2],color[3],color[4] or 1) end
    end
    return container
end

local facadeKeys={"background","overlay","modernBackground","topBar","bottomBar","panelBackground",
    "buttonBackground","buttonHover","editBackground","checkboxBackground","dropdownBackground",
    "closeGlyph","shellBorder","border"}
local function Role(frame,data)
    local ui=Addon.UI
    if ui and (frame==ui.frame or frame==ui.centerPanel) then return "none" end
    if data and data.close then return "close" end
    if ui and (frame==ui.modal or frame==ui.capture or frame==ui.profileManager or frame==ui.profileTransfer) then return "cover" end
    if frame.bindCardsLegacyRole then return frame.bindCardsLegacyRole end
    if data and data.shell then return "cover" end
    if frame.bindCardsEntryTile then return "tile" end
    if frame.bindCardsTopSurface then return "tab" end
    if frame.bindCardsCardSurface then return "card" end
    if data and data.editBox then return "edit" end
    if frame:IsObjectType("Button") or (data and data.button) then return "button" end
    return "panel"
end

function L:Surface(frame,color,border)
    local item=self.objects[frame]
    if not item then
        item={ original={}, color=color, border=border }
        self.objects[frame]=item
        if frame.HookScript then
            frame:HookScript("OnSizeChanged",function() if Enabled() then self:Paint(frame) end end)
            frame:HookScript("OnShow",function() self:Paint(frame) end)
            if frame:IsObjectType("Button") then
                frame:HookScript("OnEnter",function() item.hovered=true; self:Paint(frame) end)
                frame:HookScript("OnLeave",function() item.hovered=false; self:Paint(frame) end)
                frame:HookScript("OnMouseDown",function() item.pressed=true; self:Paint(frame) end)
                frame:HookScript("OnMouseUp",function() item.pressed=false; self:Paint(frame) end)
                frame:HookScript("OnHide",function() item.pressed=false end)
                frame:HookScript("OnEnable",function() self:Paint(frame) end)
                frame:HookScript("OnDisable",function() self:Paint(frame) end)
            end
        end
        -- Existing handlers write their selection/hover/drop colors directly.
        -- Retain those semantics while making the old flat backdrop transparent.
        if hooksecurefunc and frame.SetBackdropBorderColor then
            hooksecurefunc(frame,"SetBackdropBorderColor",function(_,r,g,b,a)
                if item.painting or not Enabled() then return end
                item.border={r,g,b,a or 1}; self:Paint(frame)
            end)
            hooksecurefunc(frame,"SetBackdropColor",function(_,r,g,b,a)
                if item.painting or not Enabled() then return end
                item.color={r,g,b,a or 1}; self:Paint(frame)
            end)
        end
    end
    if color then item.color=color end
    if border then item.border=border end
    self:Paint(frame)
end

function L:Paint(frame)
    local item=self.objects[frame]
    if not item or item.painting then return end
    item.painting=true
    local data=S.GetVisualState(frame)
    local role=Role(frame,data)
    local enabled=Enabled() and role~="none"
    -- Dim overlays, guides and tiny resize grips retain their original art.
    local w,h=frame:GetSize()
    if w<18 or h<18 or (item.color and (item.color[4] or 1)<.4) then enabled=false end
    if not enabled then
        for _,visual in pairs(item.visuals or {}) do visual:SetShown(false) end
        for texture,alpha in pairs(item.original) do texture:SetAlpha(alpha) end
        wipe(item.original)
        if item.hiddenBackdrop then
            if item.color then frame:SetBackdropColor(unpack(item.color)) end
            if item.border then frame:SetBackdropBorderColor(unpack(item.border)) end
            item.hiddenBackdrop=nil
        end
        item.painting=nil
        return
    end
    for _,key in ipairs(facadeKeys) do
        local t=data[key]
        if t and t.SetAlpha then
            if item.original[t]==nil then item.original[t]=t:GetAlpha() end
            t:SetAlpha(0)
        end
    end
    for _,t in ipairs(data.borderTextures or {}) do
        if item.original[t]==nil then item.original[t]=t:GetAlpha() end
        t:SetAlpha(0)
    end
    if frame.SetBackdropColor then
        frame:SetBackdropColor(0,0,0,0); frame:SetBackdropBorderColor(0,0,0,0)
        item.hiddenBackdrop=true
    end
    if item.role~=role then
        for _,visual in pairs(item.visuals or {}) do visual:SetShown(false) end
        item.cache=item.cache or {}; item.cache[role]=item.cache[role] or {}
        item.visuals=item.cache[role]; item.role=role
    end
    local v=item.visuals
    if not v.main then
        if role=="button" or role=="tab" or role=="edit" then
            v.main=Plate(frame,role=="edit" and "common-searchbar-a" or "common-button-list-collapseExpand")
            if role~="edit" then
                v.selection=frame:CreateTexture(nil,"BACKGROUND",nil,-1)
                v.selection:SetColorTexture(1,.7,.2,.16)
                v.selection:SetPoint("TOPLEFT",4,-4); v.selection:SetPoint("BOTTOMRIGHT",-4,4)
            end
        elseif role=="close" then
            local close=Texture(frame,"RedButton-Exit","OVERLAY",7)
            close:SetSize(24,24); close:SetPoint("CENTER")
            v.main=close
        else
            v.main=Leather(frame)
            v.border=Border(frame,role=="cover")
        end
    end
    for _,visual in pairs(v) do
        if visual.SetAlpha then visual:SetAlpha(1) end
        visual:SetShown(true)
    end
    if v.border then
        v.border:Tint(role=="cover" and {1,1,1,1} or item.border or {.72,.57,.36,1})
    end
    if v.main.pieces then
        local disabled=frame.IsEnabled and not frame:IsEnabled()
        local shade=disabled and .55 or item.pressed and .72 or 1
        for _,t in ipairs(v.main.pieces) do t:SetVertexColor(shade,shade,shade) end
        if v.selection then v.selection:SetShown(not disabled and
            (item.hovered or item.pressed or (data.tabState and data.tabState.selected) or frame.bindCardsButtonKind=="primary") or false) end
    elseif role=="close" then
        if frame.label then
            if item.original[frame.label]==nil then item.original[frame.label]=frame.label:GetAlpha() end
            frame.label:SetAlpha(0)
        end
        v.main:SetAtlas(item.pressed and "RedButton-exit-pressed" or "RedButton-Exit")
        v.main:SetSize(24,24)
    else
        local shade=role=="sheet" and .72 or role=="tile" and .55 or 1
        v.main:SetVertexColor(shade,shade,shade)
    end
    item.painting=nil
end

function L:Refresh()
    for frame in pairs(self.objects) do self:Paint(frame) end
end

-- Finish after facade methods have painted/stripped their own flat regions.
for _,name in ipairs({"Shell","Panel","Button","EditBox","TopSurface","StyleTab","CloseButton"}) do
    local original=S[name]
    S[name]=function(frame,...)
        local result=original(frame,...)
        if frame then L:Surface(frame) end
        return result
    end
end
for _,name in ipairs({"SetTheme","RefreshLooks"}) do
    local original=S[name]
    S[name]=function(...)
        local result=original(...)
        L:Refresh()
        return result
    end
end
