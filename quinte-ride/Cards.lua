local addonName, A = ...
local G=A.Game
-- Cartes à jouer : textures dessinées par scripts/make_cards.py (Media/Cards1-4.tga, une couleur par fichier,
-- 7 × 2 cases de 146 × 204 dans 1024 × 512). Animations sobres : retournement (0,3 s) et halo qui respire.
-- Aucune écriture dans un objet de Blizzard ; couleurs des halos prises dans le kit du conteneur (S.colors).
local Cards={};A.Cards=Cards
local MEDIA='Interface\\AddOns\\'..(addonName or 'quinte-ride')..'\\Media\\'
local CELL_W,CELL_H,ATLAS_W,ATLAS_H,COLS=146,204,1024,512,7
-- Ombre et halo : la carte occupe le rectangle intérieur de leur case (marge de 12 pixels)
local SOFT_W,SOFT_H=CELL_W/(CELL_W-24),CELL_H/(CELL_H-24)
Cards.FLIP=0.30
--- Fichier et coordonnées d'une carte (1 à 52) ou de 'back', 'slot', 'shadow', 'glow'.
function Cards.Texture(card)
    local file,index
    if card=='back' then file,index=1,13
    elseif card=='slot' then file,index=2,13
    elseif card=='shadow' then file,index=3,13
    elseif card=='glow' then file,index=4,13
    else file,index=G.Suit(card),(card-1)%13 end
    local col,row=index%COLS,math.floor(index/COLS)
    return MEDIA..'Cards'..file,col*CELL_W/ATLAS_W,(col+1)*CELL_W/ATLAS_W,row*CELL_H/ATLAS_H,(row+1)*CELL_H/ATLAS_H
end
local function apply(texture,card)
    local file,l,r,t,b=Cards.Texture(card)
    texture:SetTexture(file);texture:SetTexCoord(l,r,t,b)
end
local function colors() return Quintessence.Style.colors end
-- Une seule fonction d'animation par carte, branchée seulement pendant un retournement ou un halo qui respire
local function animate(self,elapsed)
    local busy=false
    if self.flip then
        local f=self.flip;f.t=f.t+(elapsed or 0)
        local half=Cards.FLIP/2
        if f.t<half then
            self.art:SetWidth(math.max(.01,self.w*math.cos(f.t/half*math.pi/2)))
        else
            if not f.swapped then f.swapped=true;self:Draw(f.value) end
            local k=math.min(1,(f.t-half)/half)
            self.art:SetWidth(math.max(.01,self.w*math.sin(k*math.pi/2)))
            if k>=1 then self.flip=nil;self.art:SetWidth(self.w) end
        end
        busy=busy or self.flip~=nil
    end
    if self.pulse then
        self.clock=(self.clock or 0)+(elapsed or 0)
        self.glow:SetAlpha(.55+.4*(.5+.5*math.sin(self.clock*4)))
        busy=true
    end
    if not busy then self:SetScript('OnUpdate',nil) end
end
local methods={}
--- Dessine sans animation : carte 1 à 52, 'back' (dos), ou rien (place vide).
function methods:Draw(value)
    self.shown=value
    if type(value)=='number' and value>0 then apply(self.art,value);self.art:SetVertexColor(1,1,1,1);self.shadow:Show()
    elseif value=='back' then apply(self.art,'back');self.art:SetVertexColor(1,1,1,1);self.shadow:Show()
    else
        apply(self.art,'slot');local c=colors().muted;self.art:SetVertexColor(c[1],c[2],c[3],.7);self.shadow:Hide()
    end
end
--- Change la carte ; flip = retournement animé (dos puis face) quand la valeur change.
function methods:Set(value,flip)
    if value==0 then value=nil end
    if flip and value~=self.value and type(value)=='number' and self:IsVisible() then
        self.value=value;self:Draw('back');self.flip={t=0,value=value};self:SetScript('OnUpdate',animate)
    elseif value~=self.value or not self.flip then
        self.value=value;self.flip=nil;self.art:SetWidth(self.w);self:Draw(value)
    end
    self:Show()
end
--- Halo autour de la carte : 'gold', 'mint', 'red' (couleurs du kit) ou nil ; pulse = respire doucement.
function methods:SetGlow(kind,pulse)
    self.hover=nil
    if not kind then self.glow:Hide();self.pulse=nil;return end
    local c=colors()[kind] or colors().gold
    self.glow:SetVertexColor(c[1],c[2],c[3],1);self.glow:SetAlpha(1);self.glow:Show()
    self.pulse=pulse or nil
    if pulse then self:SetScript('OnUpdate',animate) end
end
function methods:SetDim(dim) self.art:SetAlpha(dim and .45 or 1) end
--- Nouvelle carte (Button) de w × h ; onClick(self) au clic.
function Cards.New(parent,w,h,onClick)
    local b=CreateFrame('Button',nil,parent);b:SetSize(w,h);b.w,b.h=w,h
    for k,fn in pairs(methods) do b[k]=fn end
    b.shadow=b:CreateTexture(nil,'BACKGROUND');apply(b.shadow,'shadow');b.shadow:SetAlpha(.6)
    b.shadow:SetSize(w*SOFT_W,h*SOFT_H);b.shadow:SetPoint('CENTER',1.5,-2.5)
    b.glow=b:CreateTexture(nil,'BORDER');apply(b.glow,'glow');b.glow:SetSize(w*SOFT_W*1.04,h*SOFT_H*1.03);b.glow:SetPoint('CENTER');b.glow:Hide()
    b.art=b:CreateTexture(nil,'ARTWORK');b.art:SetSize(w,h);b.art:SetPoint('CENTER')
    b:Draw(nil)
    if onClick then
        b:SetScript('OnClick',onClick)
        b:SetScript('OnEnter',function(self) if self.clickable and not self.glow:IsShown() then self:SetGlow('gold');self.hover=true end end)
        b:SetScript('OnLeave',function(self) if self.hover then self.hover=false;self:SetGlow(nil) end end)
    end
    return b
end
