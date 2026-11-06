local _, Core = ...
--[[
  Boîte à outils de style commune (Quintessence.Style). Deux interfaces au choix (QuintessenceDB.theme) :
    'modern'  : sombre et plate, accents or et menthe (par défaut) ;
    'classic' : façon WoW Classic, avec les textures du jeu (cadre de dialogue, bordure d'infobulle, boutons rouges,
                surlignage du journal de quêtes, texte or).
  Les modules l'utilisent pour rester cohérents avec la fenêtre du conteneur : ils n'ont rien à savoir du thème.
  Le thème est fixé une fois au chargement (S.Apply depuis Core.Init) ; en changer recharge l'interface.
  Tout est construit avec nos propres cadres ; rien n'est écrit dans les objets de Blizzard.
]]
local S = {}
Core.Style = S

S.colors = {
    bg = { 0.047, 0.063, 0.098, 0.97 },      -- fond de la fenêtre
    side = { 0.035, 0.047, 0.075, 1 },       -- barre latérale
    panel = { 0.075, 0.098, 0.145, 1 },      -- cartes, listes
    raised = { 0.105, 0.135, 0.195, 1 },     -- survol, champs
    line = { 0.165, 0.208, 0.290, 1 },       -- bordures
    text = { 0.91, 0.92, 0.95, 1 },
    muted = { 0.58, 0.63, 0.72, 1 },
    gold = { 0.85, 0.70, 0.36, 1 },
    goldSoft = { 0.85, 0.70, 0.36, 0.16 },
    mint = { 0.36, 0.82, 0.66, 1 },
    red = { 0.90, 0.33, 0.36, 1 },
    blue = { 0.36, 0.56, 0.93, 1 },
}
S.hex = { gold = 'ffd9b35c', mint = 'ff5cd1a8', muted = 'ff94a1b8', red = 'ffe5545c', text = 'ffe8ebf2' }

-- Palettes des deux interfaces ; S.colors et S.hex sont modifiés sur place (les modules gardent les mêmes tables).
local function copy(t) local out = {}; for k, v in pairs(t) do out[k] = type(v) == 'table' and { unpack(v) } or v end; return out end
S.THEMES = {
    modern = { label = 'Moderne', colors = copy(S.colors), hex = copy(S.hex) },
    classic = {
        label = 'WoW Classic',
        colors = {
            bg = { 0, 0, 0, 0.75 },
            side = { 0, 0, 0, 0.45 },
            panel = { 0.04, 0.035, 0.03, 0.85 },
            raised = { 0.12, 0.10, 0.07, 0.95 },
            line = { 0.62, 0.60, 0.56, 1 },
            text = { 1, 1, 1, 1 },                -- HIGHLIGHT_FONT_COLOR
            muted = { 0.74, 0.74, 0.74, 1 },
            gold = { 1, 0.82, 0, 1 },             -- NORMAL_FONT_COLOR
            goldSoft = { 1, 0.82, 0, 0.14 },
            mint = { 0.12, 1, 0.12, 1 },          -- GREEN_FONT_COLOR
            red = { 1, 0.13, 0.13, 1 },
            blue = { 0.30, 0.62, 1, 1 },
        },
        hex = { gold = 'ffffd100', mint = 'ff20ff20', muted = 'ffbdbdbd', red = 'ffff2020', text = 'ffffffff' },
    },
}
S.THEME_ORDER = { 'modern', 'classic' }
S.theme = 'modern'

--- Nom de thème valide (accepte aussi les mots français de /quinte interface).
function S.ThemeName(name)
    name = type(name) == 'string' and name:lower() or ''
    if name == 'classique' or name == 'classic' or name == 'wow' then return 'classic' end
    if name == 'moderne' or name == 'modern' then return 'modern' end
    return nil
end

--- Applique un thème pour la session (avant la création des fenêtres).
function S.Apply(name)
    name = S.ThemeName(name) or 'modern'
    local theme = S.THEMES[name]
    for key, value in pairs(theme.colors) do
        local target = S.colors[key]
        if target then for i = 1, 4 do target[i] = value[i] end else S.colors[key] = { unpack(value) } end
    end
    for key, value in pairs(theme.hex) do S.hex[key] = value end
    S.theme = name
    return name
end

function S.IsClassic() return S.theme == 'classic' end

-- Texture classique absente du client : notée une seule fois dans les erreurs de /quinte debug
local missing = {}
function S.Missing(file)
    if missing[file] then return end
    missing[file] = true
    if Core.Error then Core.Error('interface classique', 'texture absente du client : ' .. tostring(file)) end
end

local WHITE = 'Interface\\Buttons\\WHITE8X8'
local FONT = STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF'
-- Textures de l'interface d'origine (présentes dans les clients Classic et Retail)
S.TEX = {
    dialogBg = 'Interface\\DialogFrame\\UI-DialogBox-Background',
    dialogBorder = 'Interface\\DialogFrame\\UI-DialogBox-Border',
    dialogHeader = 'Interface\\DialogFrame\\UI-DialogBox-Header',
    tooltipBg = 'Interface\\Tooltips\\UI-Tooltip-Background',
    tooltipBorder = 'Interface\\Tooltips\\UI-Tooltip-Border',
    buttonUp = 'Interface\\Buttons\\UI-Panel-Button-Up',
    buttonDown = 'Interface\\Buttons\\UI-Panel-Button-Down',
    buttonDisabled = 'Interface\\Buttons\\UI-Panel-Button-Disabled',
    buttonHighlight = 'Interface\\Buttons\\UI-Panel-Button-Highlight',
    input = 'Interface\\Common\\Common-Input-Border',
    rowHighlight = 'Interface\\QuestFrame\\UI-QuestTitleHighlight',
    rowSelected = 'Interface\\QuestFrame\\UI-QuestLogTitleHighlight',
    knob = 'Interface\\Buttons\\UI-ScrollBar-Knob',
    closeUp = 'Interface\\Buttons\\UI-Panel-MinimizeButton-Up',
    closeDown = 'Interface\\Buttons\\UI-Panel-MinimizeButton-Down',
    closeHighlight = 'Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight',
}
local T = S.TEX
-- Bordure d'infobulle : cadres intérieurs du thème classique (teintable, comme les bordures de qualité des objets)
local CLASSIC_BOX = { bgFile = T.tooltipBg, edgeFile = T.tooltipBorder, tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } }
-- Grand cadre de dialogue (fenêtre principale)
S.CLASSIC_WINDOW = { bgFile = T.dialogBg, edgeFile = T.dialogBorder, tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 } }

--- Cadre avec fond et bordure (BackdropTemplate si disponible, sinon textures).
--- Moderne : plat, bordure d'un pixel. Classique : fond et bordure d'infobulle du jeu.
function S.Box(parent, color, border, frameType)
    local f = CreateFrame(frameType or 'Frame', nil, parent, BackdropTemplateMixin and 'BackdropTemplate' or nil)
    if f.SetBackdrop then
        f:SetBackdrop(S.IsClassic() and CLASSIC_BOX or { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        f:SetBackdropColor(unpack(color or S.colors.panel))
        f:SetBackdropBorderColor(unpack(border or S.colors.line))
    else
        local bg = f:CreateTexture(nil, 'BACKGROUND'); bg:SetAllPoints(); bg:SetColorTexture(unpack(color or S.colors.panel))
    end
    return f
end

--- Texte avec taille et couleur explicites (ombre portée en classique, comme les polices du jeu).
function S.Text(parent, size, color, justify, flags)
    local fs = parent:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    fs:SetFont(FONT, size or 12, flags or '')
    fs:SetTextColor(unpack(color or S.colors.text))
    fs:SetJustifyH(justify or 'LEFT')
    fs:SetWordWrap(false)
    if S.IsClassic() and fs.SetShadowOffset then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1) end
    return fs
end

--- Aplat de couleur (fond, surlignage, barre d'accent).
function S.Fill(parent, layer, color)
    local t = parent:CreateTexture(nil, layer or 'BACKGROUND')
    t:SetColorTexture(unpack(color))
    return t
end

-- Texture découpée en trois (bords fixes, milieu étiré) : boutons rouges et champs de saisie classiques.
-- coords = { gauche, milieu, droite, bas } en coordonnées de texture ; edge = largeur des bords en pixels.
local function threeSlice(frame, layer, file, coords, edge)
    local l = frame:CreateTexture(nil, layer); l:SetPoint('TOPLEFT'); l:SetPoint('BOTTOMLEFT'); l:SetWidth(edge)
    local r = frame:CreateTexture(nil, layer); r:SetPoint('TOPRIGHT'); r:SetPoint('BOTTOMRIGHT'); r:SetWidth(edge)
    local m = frame:CreateTexture(nil, layer); m:SetPoint('TOPLEFT', l, 'TOPRIGHT'); m:SetPoint('BOTTOMRIGHT', r, 'BOTTOMLEFT')
    l:SetTexCoord(0, coords[1], 0, coords[4]); m:SetTexCoord(coords[1], coords[2], 0, coords[4]); r:SetTexCoord(coords[2], coords[3], 0, coords[4])
    local pieces = { l, m, r }
    local function set(path) for _, t in ipairs(pieces) do t:SetTexture(path) end end
    -- SetTexture renvoie false si le client n'a pas le fichier : aplat de secours et trace dans /quinte debug
    if l:SetTexture(file) == false then
        S.Missing(file)
        local fallback = frame:CreateTexture(nil, layer, nil, -1); fallback:SetAllPoints(); fallback:SetColorTexture(0.35, 0.04, 0.03, 0.95)
    end
    set(file)
    return set
end

-- Bouton rouge de l'interface d'origine (UIPanelButtonTemplate refait avec nos textures)
local function classicButton(parent, label, width, height, kind)
    local c = S.colors
    local b = CreateFrame('Button', nil, parent)
    b:SetSize(width or 120, height or 24)
    local setTexture = threeSlice(b, 'BACKGROUND', T.buttonUp, { 0.09375, 0.53125, 0.625, 0.6875 }, 12)
    b:SetHighlightTexture(T.buttonHighlight, 'ADD')
    local highlight = b.GetHighlightTexture and b:GetHighlightTexture()
    if highlight then highlight:SetTexCoord(0, 0.625, 0, 0.6875) end
    b.label = S.Text(b, 12, c.gold, 'CENTER')
    b.label:SetPoint('CENTER', 0, 1)
    b.label:SetText(label or '')
    b.kind = kind
    local function paint(self)
        local enabled = not self.IsEnabled or self:IsEnabled()
        setTexture(not enabled and T.buttonDisabled or ((self.pressed or self.active) and T.buttonDown) or T.buttonUp)
        local color = not enabled and { 0.5, 0.5, 0.5, 1 } or ((self.hover or self.active) and (kind == 'danger' and self.hover and c.red or c.text)) or c.gold
        self.label:SetTextColor(unpack(color))
        self.label:SetPoint('CENTER', (self.pressed or self.active) and 1 or 0, (self.pressed or self.active) and -1 or 1)
        if self.active then self:LockHighlight() else self:UnlockHighlight() end
    end
    b:SetScript('OnEnter', function(self) self.hover = true; paint(self) end)
    b:SetScript('OnLeave', function(self) self.hover = false; self.pressed = false; paint(self) end)
    b:SetScript('OnMouseDown', function(self) self.pressed = true; paint(self) end)
    b:SetScript('OnMouseUp', function(self) self.pressed = false; paint(self) end)
    b:SetScript('OnEnable', paint)
    b:SetScript('OnDisable', paint)
    function b:SetLabel(text) self.label:SetText(text) end
    function b:SetActive(value) self.active = value and true or false; paint(self) end
    paint(b)
    return b
end

--- Bouton. kind : 'primary' (or), 'ghost' (discret), 'danger'. b:SetActive(true) le met en évidence.
--- Classique : bouton rouge du jeu (texte or, blanc au survol, enfoncé quand il est actif).
function S.Button(parent, label, width, height, kind)
    if S.IsClassic() then return classicButton(parent, label, width, height, kind) end
    local c = S.colors
    local b = S.Box(parent, kind == 'primary' and c.gold or c.raised, kind == 'primary' and c.gold or c.line, 'Button')
    b:SetSize(width or 120, height or 26)
    b.label = S.Text(b, 12, kind == 'primary' and { 0.08, 0.07, 0.04, 1 } or c.text, 'CENTER')
    b.label:SetPoint('CENTER', 0, 0)
    b.label:SetText(label or '')
    b.kind = kind
    local function paint(self)
        if not self.SetBackdropBorderColor then return end
        local enabled = not self.IsEnabled or self:IsEnabled()
        local border = (self.active and c.gold) or (self.hover and enabled and (kind == 'danger' and c.red or c.gold)) or (kind == 'primary' and c.gold or c.line)
        self:SetBackdropBorderColor(unpack(border))
        if kind ~= 'primary' then self:SetBackdropColor(unpack(self.active and { 0.85, 0.70, 0.36, 0.18 } or c.raised)) end
        self:SetAlpha(enabled and 1 or 0.4)
    end
    b:SetScript('OnEnter', function(self) self.hover = true; paint(self) end)
    b:SetScript('OnLeave', function(self) self.hover = false; paint(self) end)
    b:SetScript('OnEnable', paint)
    b:SetScript('OnDisable', paint)
    function b:SetLabel(text) self.label:SetText(text) end
    function b:SetActive(value) self.active = value and true or false; paint(self) end
    paint(b)
    return b
end

--- Champ de saisie avec texte indicatif (classique : bordure de saisie du jeu).
function S.Input(parent, width, placeholder)
    local classic = S.IsClassic()
    local box
    if classic then
        box = CreateFrame('EditBox', nil, parent)
        threeSlice(box, 'BACKGROUND', T.input, { 0.0625, 0.9375, 1, 0.625 }, 8)
    else
        box = S.Box(parent, S.colors.raised, S.colors.line, 'EditBox')
    end
    box:SetSize(width or 200, classic and 24 or 26)
    box:SetAutoFocus(false)
    if box.SetFontObject and ChatFontNormal then box:SetFontObject(ChatFontNormal) end
    box:SetTextInsets(26, 8, 0, 0)
    -- Loupe en image : les polices du jeu n'ont pas de caractère loupe
    local icon = box:CreateTexture(nil, 'OVERLAY'); icon:SetTexture('Interface\\Common\\UI-Searchbox-Icon'); icon:SetSize(14, 14)
    icon:SetPoint('LEFT', 7, -1); icon:SetVertexColor(unpack(S.colors.muted))
    box.placeholder = S.Text(box, 12, S.colors.muted); box.placeholder:SetPoint('LEFT', 26, 0); box.placeholder:SetText(type(placeholder) == 'string' and placeholder or '')
    local rawSetText = box.SetText
    if type(rawSetText) == 'function' then
        function box:SetText(value)
            rawSetText(self, value)
            if self.placeholder then self.placeholder:SetShown((tostring(value or '')) == '') end
        end
    end
    box:SetScript('OnTextChanged', function(self)
        if self.placeholder then self.placeholder:SetShown((self:GetText() or '') == '') end
    end)
    if classic then
        box:SetScript('OnEditFocusGained', function() icon:SetVertexColor(unpack(S.colors.gold)) end)
        box:SetScript('OnEditFocusLost', function() icon:SetVertexColor(unpack(S.colors.muted)) end)
    else
        box:SetScript('OnEditFocusGained', function(self) self:SetBackdropBorderColor(unpack(S.colors.gold)) end)
        box:SetScript('OnEditFocusLost', function(self) self:SetBackdropBorderColor(unpack(S.colors.line)) end)
    end
    box:SetScript('OnEscapePressed', box.ClearFocus)
    box:SetScript('OnEnterPressed', box.ClearFocus)
    return box
end

--- Ligne de liste cliquable : fond au survol, mise en évidence quand elle est choisie (row:SetSelected).
--- Moderne : barre d'accent or. Classique : surlignage du journal de quêtes.
function S.Row(parent, width, height)
    local row = CreateFrame('Button', nil, parent)
    row:SetSize(width, height)
    if S.IsClassic() then
        row.hoverBg = row:CreateTexture(nil, 'HIGHLIGHT'); row.hoverBg:SetTexture(T.rowHighlight); row.hoverBg:SetBlendMode('ADD')
        row.hoverBg:SetAllPoints(); row.hoverBg:SetAlpha(0.7)
        row.selectedBg = row:CreateTexture(nil, 'BACKGROUND'); row.selectedBg:SetTexture(T.rowSelected); row.selectedBg:SetBlendMode('ADD')
        row.selectedBg:SetAllPoints(); row.selectedBg:SetVertexColor(1, 0.82, 0.2, 0.9); row.selectedBg:Hide()
        -- Pas de barre d'accent en classique : le champ existe pour les modules, toujours caché
        row.accent = S.Fill(row, 'ARTWORK', { 0, 0, 0, 0 }); row.accent:SetPoint('TOPLEFT'); row.accent:SetPoint('BOTTOMLEFT'); row.accent:SetWidth(1); row.accent:Hide()
        function row:SetSelected(value)
            self.isSelected = value and true or false
            self.selectedBg:SetShown(self.isSelected)
        end
        return row
    end
    -- Couche HIGHLIGHT : affichée au survol par le jeu, sans script (les modules gardent OnEnter pour leurs infobulles)
    row.hoverBg = S.Fill(row, 'HIGHLIGHT', { 1, 1, 1, 0.05 }); row.hoverBg:SetAllPoints()
    row.selectedBg = S.Fill(row, 'BACKGROUND', S.colors.goldSoft); row.selectedBg:SetAllPoints(); row.selectedBg:Hide()
    row.accent = S.Fill(row, 'ARTWORK', S.colors.gold); row.accent:SetPoint('TOPLEFT'); row.accent:SetPoint('BOTTOMLEFT'); row.accent:SetWidth(3); row.accent:Hide()
    function row:SetSelected(value)
        self.isSelected = value and true or false
        self.selectedBg:SetShown(self.isSelected); self.accent:SetShown(self.isSelected)
    end
    return row
end

--- Titre de section (moderne : petites capitales espacées ; classique : texte or du jeu).
function S.Heading(parent, text)
    if S.IsClassic() then
        local fs = S.Text(parent, 12, S.colors.gold)
        fs:SetText(text or '')
        return fs
    end
    local fs = S.Text(parent, 10, S.colors.gold)
    fs:SetText(string.upper(text or ''))
    return fs
end

--- Barre de défilement (Slider vertical) : plate, ou avec le curseur du jeu en classique.
function S.Scrollbar(parent, height, onChange)
    local slider = CreateFrame('Slider', nil, parent)
    slider:SetOrientation('VERTICAL')
    slider:SetSize(6, height)
    local track = S.Fill(slider, 'BACKGROUND', S.colors.panel); track:SetAllPoints()
    local thumb = slider:CreateTexture(nil, 'OVERLAY')
    if S.IsClassic() then
        track:SetColorTexture(0, 0, 0, 0.45)
        thumb:SetTexture(T.knob); thumb:SetTexCoord(0.22, 0.78, 0.125, 0.875); thumb:SetSize(12, 22)
    else
        thumb:SetColorTexture(unpack(S.colors.line)); thumb:SetSize(6, 36)
    end
    slider:SetThumbTexture(thumb)
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetScript('OnValueChanged', function(_, value) onChange(math.floor(value + 0.5)) end)
    return slider
end
