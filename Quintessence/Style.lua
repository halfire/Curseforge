local _, Core = ...
--[[
  Boîte à outils de style commune (Quintessence.Style). Trois interfaces au choix (QuintessenceDB.theme) :
    'modern'    : sombre et plate, accents or et menthe (par défaut) ;
    'classic'   : façon WoW Classic, avec les textures du jeu (cadre de dialogue, bordure d'infobulle, boutons rouges,
                  surlignage du journal de quêtes, texte or) ;
    'future'    : Futuriste (1.50.0) — fond presque noir, accent cyan, police étroite, crochets d'angle sur les cadres
                  et les boutons, libellés en capitales, lignes de balayage et filet lumineux dans la fenêtre ;
  (Le thème clair Parchemin de la 1.50.0 a été retiré à la demande du GM en 1.50.2 ; une ancienne valeur 'parchment'
  revient au thème moderne.)
  Chaque thème a une palette (S.colors / S.hex, modifiées sur place) et un rendu (S.Kind()). Rôles de couleur à utiliser
  plutôt que des valeurs écrites en dur : hover (survol), onAccent (texte sur un fond d'accent), shade (voile),
  goldSoft (accent pâle). Les modules l'utilisent pour rester cohérents avec la fenêtre du conteneur.
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
    gold = { 0.85, 0.70, 0.36, 1 },          -- accent du thème (or, cyan en Futuriste)
    goldSoft = { 0.85, 0.70, 0.36, 0.16 },
    mint = { 0.36, 0.82, 0.66, 1 },
    red = { 0.90, 0.33, 0.36, 1 },
    blue = { 0.36, 0.56, 0.93, 1 },
    hover = { 1, 1, 1, 0.05 },               -- survol d'une ligne ou d'une carte
    onAccent = { 0.08, 0.07, 0.04, 1 },      -- texte posé sur l'accent (bouton principal, pastille)
    shade = { 0, 0, 0, 0.35 },               -- voile (socle, fond d'image)
}
S.hex = { gold = 'ffd9b35c', mint = 'ff5cd1a8', muted = 'ff94a1b8', red = 'ffe5545c', text = 'ffe8ebf2', blue = 'ff5c8fed' }

local FRIZ = 'Fonts\\FRIZQT__.TTF'
local NARROW = 'Fonts\\ARIALN.TTF'

-- Palettes et rendus des interfaces ; S.colors et S.hex sont modifiés sur place (les modules gardent les mêmes tables).
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
            hover = { 1, 1, 1, 0.06 },
            onAccent = { 0.08, 0.06, 0.02, 1 },
            shade = { 0, 0, 0, 0.4 },
        },
        hex = { gold = 'ffffd100', mint = 'ff20ff20', muted = 'ffbdbdbd', red = 'ffff2020', text = 'ffffffff', blue = 'ff4d9eff' },
    },
    future = {
        label = 'Futuriste', font = NARROW, titleFont = NARROW, boost = 1, upper = true, spaced = true,
        colors = {
            bg = { 0.012, 0.024, 0.039, 0.97 },
            side = { 0.008, 0.016, 0.028, 1 },
            panel = { 0.024, 0.047, 0.071, 0.94 },
            raised = { 0.035, 0.075, 0.106, 1 },
            line = { 0.05, 0.42, 0.50, 0.75 },
            text = { 0.84, 0.97, 1, 1 },
            muted = { 0.43, 0.62, 0.68, 1 },
            gold = { 0, 0.90, 1, 1 },             -- accent cyan
            goldSoft = { 0, 0.90, 1, 0.13 },
            mint = { 0.20, 1, 0.62, 1 },
            red = { 1, 0.26, 0.46, 1 },
            blue = { 0.58, 0.48, 1, 1 },
            hover = { 0, 0.90, 1, 0.06 },
            onAccent = { 0.01, 0.06, 0.08, 1 },
            shade = { 0, 0.05, 0.08, 0.5 },
        },
        hex = { gold = 'ff00e5ff', mint = 'ff33ff9e', muted = 'ff6e9ead', red = 'ffff4275', text = 'ffd6f7ff', blue = 'ff947aff' },
    },
}
S.THEME_ORDER = { 'modern', 'classic', 'future' }
S.theme = 'modern'

--- Nom de thème valide (accepte aussi les mots français de /quinte interface).
function S.ThemeName(name)
    name = type(name) == 'string' and name:lower() or ''
    if name == 'classique' or name == 'classic' or name == 'wow' then return 'classic' end
    if name == 'moderne' or name == 'modern' then return 'modern' end
    if name == 'futuriste' or name == 'future' or name == 'futur' or name == 'sf' then return 'future' end
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
--- Rendu du thème : 'modern', 'classic' ou 'future'.
function S.Kind() return S.theme end
function S.IsFuture() return S.theme == 'future' end
--- Thème clair (texte sombre sur fond clair) : ne jamais supposer un fond sombre.
function S.IsLight() return S.THEMES[S.theme] and S.THEMES[S.theme].light == true end

-- Surfaces toujours sombres (chat, infobulles du jeu) : en thème clair, couleurs du thème moderne, sinon celles du
-- thème. S.OnDark('gold') pour une couleur, S.ChatText(texte) pour un texte coloré par S.hex (codes |c… remplacés).
function S.OnDark(name)
    if S.IsLight() then return S.THEMES.modern.colors[name] or S.colors[name] end
    return S.colors[name]
end
function S.ChatText(text)
    if type(text) ~= 'string' or not S.IsLight() then return text end
    local light, dark = S.THEMES[S.theme].hex, S.THEMES.modern.hex
    for key, code in pairs(light) do
        if dark[key] then text = text:gsub('|c' .. code, '|c' .. dark[key]) end
    end
    return text
end

-- Texture classique absente du client : notée une seule fois dans les erreurs de /quinte debug
local missing = {}
function S.Missing(file)
    if missing[file] then return end
    missing[file] = true
    if Core.Error then Core.Error('interface ' .. tostring(S.theme), 'texture absente du client : ' .. tostring(file)) end
end

local WHITE = 'Interface\\Buttons\\WHITE8X8'
local FONT = STANDARD_TEXT_FONT or FRIZ
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
local FLAT_BOX = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }
-- Grand cadre de dialogue (fenêtre principale)
S.CLASSIC_WINDOW = { bgFile = T.dialogBg, edgeFile = T.dialogBorder, tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 } }

local function call(f, method, ...)
    if type(f) ~= 'table' and type(f) ~= 'userdata' then return nil end
    local fn = f[method]
    if type(fn) == 'function' then return fn(f, ...) end
end

--- Polices du thème : texte courant et titres.
function S.Font() return (S.THEMES[S.theme] and S.THEMES[S.theme].font) or FONT end
function S.TitleFont() return (S.THEMES[S.theme] and S.THEMES[S.theme].titleFont) or S.Font() end

-- Majuscules françaises (string.upper ne connaît que l'ASCII : « événement » donnerait « éVéNEMENT »)
local ACCENTS = { ['é'] = 'É', ['è'] = 'È', ['ê'] = 'Ê', ['ë'] = 'Ë', ['à'] = 'À', ['â'] = 'Â', ['ç'] = 'Ç', ['î'] = 'Î',
    ['ï'] = 'Ï', ['ô'] = 'Ô', ['û'] = 'Û', ['ù'] = 'Ù', ['ü'] = 'Ü' }
function S.Upper(text)
    return (string.upper(tostring(text or '')):gsub('\195[\160-\191]', function(c) return ACCENTS[c] or c end))
end
-- Futuriste : capitales espacées (« Q U I N T E S S E N C E ») pour les grands titres
function S.Spaced(text)
    local out = {}
    for ch in S.Upper(text):gmatch('[%z\1-\127\194-\244][\128-\191]*') do out[#out + 1] = ch end
    return table.concat(out, ' ')
end

--- Crochets d'angle (Futuriste) : deux traits à chaque coin, à la couleur de l'accent.
function S.Brackets(frame, size, thick, color)
    size, thick = size or 8, thick or 1
    local list = {}
    local corners = { { 'TOPLEFT', 1, -1 }, { 'TOPRIGHT', -1, -1 }, { 'BOTTOMLEFT', 1, 1 }, { 'BOTTOMRIGHT', -1, 1 } }
    for _, c in ipairs(corners) do
        local h = frame:CreateTexture(nil, 'OVERLAY'); h:SetColorTexture(unpack(color or S.colors.gold))
        call(h, 'SetPoint', c[1], 0, 0); call(h, 'SetSize', size, thick)
        local v = frame:CreateTexture(nil, 'OVERLAY'); v:SetColorTexture(unpack(color or S.colors.gold))
        call(v, 'SetPoint', c[1], 0, 0); call(v, 'SetSize', thick, size)
        list[#list + 1] = h; list[#list + 1] = v
    end
    frame.brackets = list
    function frame:SetBracketColor(r, g, b, a) for _, t in ipairs(self.brackets) do t:SetColorTexture(r, g, b, a or 1) end end
    return list
end

--- Cadre avec fond et bordure (BackdropTemplate si disponible, sinon textures).
--- Moderne : plat, bordure d'un pixel. Classique : fond et bordure d'infobulle du jeu. Futuriste : plat, crochets
--- d'angle sur les cadres (pas sur les boutons ni les champs).
function S.Box(parent, color, border, frameType)
    local f = CreateFrame(frameType or 'Frame', nil, parent, BackdropTemplateMixin and 'BackdropTemplate' or nil)
    if f.SetBackdrop then
        local kind = S.theme
        f:SetBackdrop(kind == 'classic' and CLASSIC_BOX or FLAT_BOX)
        f:SetBackdropColor(unpack(color or S.colors.panel))
        f:SetBackdropBorderColor(unpack(border or S.colors.line))
        if kind == 'future' and not frameType and (color == nil or color == S.colors.panel or color == S.colors.bg) then
            S.Brackets(f, 8, 1)
        end
    else
        local bg = f:CreateTexture(nil, 'BACKGROUND'); bg:SetAllPoints(); bg:SetColorTexture(unpack(color or S.colors.panel))
    end
    return f
end

--- Texte avec taille et couleur explicites (ombre portée en classique, comme les polices du jeu).
--- Police du thème (Futuriste : police étroite, un point de plus).
function S.Text(parent, size, color, justify, flags)
    local fs = parent:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    local theme = S.THEMES[S.theme] or {}
    size = (size or 12) + (theme.boost or 0)
    local font = (size >= (theme.titleMin or 16) and theme.titleFont) or theme.font or FONT
    -- Police absente du client : retour à la police standard
    if fs:SetFont(font, size, flags or '') == false then fs:SetFont(FONT, size, flags or '') end
    fs:SetTextColor(unpack(color or S.colors.text))
    fs:SetJustifyH(justify or 'LEFT')
    fs:SetWordWrap(false)
    if S.IsClassic() and fs.SetShadowOffset then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1)
    elseif S.IsLight() and fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
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

-- Futuriste : fond transparent, filet fin, crochets d'angle, libellé en capitales ; survol : voile cyan et crochets
-- allumés ; principal : aplat cyan, texte sombre ; actif : barre lumineuse en bas.
local function futureButton(parent, label, width, height, kind)
    local c = S.colors
    local b = S.Box(parent, { c.raised[1], c.raised[2], c.raised[3], 0.55 }, c.line, 'Button')
    b:SetSize(width or 120, height or 26)
    S.Brackets(b, 6, 1, c.muted)
    b.label = S.Text(b, 11, c.text, 'CENTER'); b.label:SetPoint('CENTER', 0, 0)
    b.bar = S.Fill(b, 'OVERLAY', c.gold); call(b.bar, 'SetPoint', 'BOTTOMLEFT', 4, 1); call(b.bar, 'SetPoint', 'BOTTOMRIGHT', -4, 1)
    call(b.bar, 'SetHeight', 2); b.bar:Hide()
    b.kind = kind
    local function paint(self)
        if not self.SetBackdropBorderColor then return end
        local enabled = not self.IsEnabled or self:IsEnabled()
        local hot = (self.hover and enabled) or self.active
        local accent = kind == 'danger' and c.red or c.gold
        if kind == 'primary' then
            self:SetBackdropColor(unpack(hot and { c.gold[1], c.gold[2], c.gold[3], 1 } or { c.gold[1] * 0.85, c.gold[2] * 0.85, c.gold[3] * 0.85, 1 }))
            self:SetBackdropBorderColor(unpack(c.gold))
            self.label:SetTextColor(unpack(c.onAccent))
        else
            self:SetBackdropColor(unpack(hot and c.goldSoft or { c.raised[1], c.raised[2], c.raised[3], 0.55 }))
            self:SetBackdropBorderColor(unpack(hot and accent or c.line))
            self.label:SetTextColor(unpack(hot and accent or c.text))
        end
        if type(self.brackets) == 'table' then self:SetBracketColor(unpack(hot and accent or c.muted)) end
        call(self.bar, 'SetShown', self.active and true or false)
        if self.SetAlpha then self:SetAlpha(enabled and 1 or 0.35) end
    end
    b:SetScript('OnEnter', function(self) self.hover = true; paint(self) end)
    b:SetScript('OnLeave', function(self) self.hover = false; paint(self) end)
    b:SetScript('OnEnable', paint)
    b:SetScript('OnDisable', paint)
    function b:SetLabel(text) self.label:SetText(S.Upper(text)) end
    function b:SetActive(value) self.active = value and true or false; paint(self) end
    b:SetLabel(label or '')
    paint(b)
    return b
end

--- Bouton. kind : 'primary' (accent), 'ghost' (discret), 'danger'. b:SetActive(true) le met en évidence.
--- Classique : bouton rouge du jeu (texte or, blanc au survol, enfoncé quand il est actif). Futuriste : crochets et
--- capitales.
function S.Button(parent, label, width, height, kind)
    if S.IsClassic() then return classicButton(parent, label, width, height, kind) end
    if S.IsFuture() then return futureButton(parent, label, width, height, kind) end
    local c = S.colors
    local b = S.Box(parent, kind == 'primary' and c.gold or c.raised, kind == 'primary' and c.gold or c.line, 'Button')
    b:SetSize(width or 120, height or 26)
    b.label = S.Text(b, 12, kind == 'primary' and c.onAccent or c.text, 'CENTER')
    b.label:SetPoint('CENTER', 0, 0)
    b.label:SetText(label or '')
    b.kind = kind
    local function paint(self)
        if not self.SetBackdropBorderColor then return end
        local enabled = not self.IsEnabled or self:IsEnabled()
        local border = (self.active and c.gold) or (self.hover and enabled and (kind == 'danger' and c.red or c.gold)) or (kind == 'primary' and c.gold or c.line)
        self:SetBackdropBorderColor(unpack(border))
        if kind ~= 'primary' then self:SetBackdropColor(unpack(self.active and c.goldSoft or (self.hover and enabled and S.IsLight() and c.panel) or c.raised)) end
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

--- Champ de saisie avec texte indicatif (classique : bordure de saisie du jeu ; Futuriste : filet lumineux dessous).
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
    -- Police et couleur du thème (jamais la couleur fixe de ChatFontNormal)
    if not classic and box.SetFont then
        if box:SetFont(S.Font(), 12 + ((S.THEMES[S.theme] or {}).boost or 0), '') == false then box:SetFont(FONT, 12, '') end
        call(box, 'SetTextColor', unpack(S.colors.text))
    end
    if box.SetTextInsets then box:SetTextInsets(26, 8, 0, 0) end
    -- Loupe en image : les polices du jeu n'ont pas de caractère loupe
    local icon = box:CreateTexture(nil, 'OVERLAY'); icon:SetTexture('Interface\\Common\\UI-Searchbox-Icon'); icon:SetSize(14, 14)
    icon:SetPoint('LEFT', 7, -1); icon:SetVertexColor(unpack(S.colors.muted))
    box.placeholder = S.Text(box, 12, S.colors.muted); box.placeholder:SetPoint('LEFT', 26, 0); box.placeholder:SetText(type(placeholder) == 'string' and placeholder or '')
    if S.IsFuture() then
        box.glow = S.Fill(box, 'OVERLAY', S.colors.gold); call(box.glow, 'SetPoint', 'BOTTOMLEFT', 1, 1); call(box.glow, 'SetPoint', 'BOTTOMRIGHT', -1, 1)
        call(box.glow, 'SetHeight', 1); call(box.glow, 'SetAlpha', 0.35)
    end
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
        box:SetScript('OnEditFocusGained', function(self)
            self:SetBackdropBorderColor(unpack(S.colors.gold)); icon:SetVertexColor(unpack(S.colors.gold))
            call(self.glow, 'SetAlpha', 1)
        end)
        box:SetScript('OnEditFocusLost', function(self)
            self:SetBackdropBorderColor(unpack(S.colors.line)); icon:SetVertexColor(unpack(S.colors.muted))
            call(self.glow, 'SetAlpha', 0.35)
        end)
    end
    box:SetScript('OnEscapePressed', box.ClearFocus)
    box:SetScript('OnEnterPressed', box.ClearFocus)
    return box
end

--- Ligne de liste cliquable : fond au survol, mise en évidence quand elle est choisie (row:SetSelected).
--- Moderne : barre d'accent or. Classique : surlignage du journal de quêtes. Futuriste : barre cyan et repère à
--- droite.
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
    row.hoverBg = S.Fill(row, 'HIGHLIGHT', S.colors.hover); row.hoverBg:SetAllPoints()
    row.selectedBg = S.Fill(row, 'BACKGROUND', S.colors.goldSoft); row.selectedBg:SetAllPoints(); row.selectedBg:Hide()
    row.accent = S.Fill(row, 'ARTWORK', S.colors.gold); row.accent:SetPoint('TOPLEFT'); row.accent:SetPoint('BOTTOMLEFT')
    row.accent:SetWidth(S.IsFuture() and 2 or 3); row.accent:Hide()
    if S.IsFuture() then
        row.tick = S.Fill(row, 'ARTWORK', S.colors.gold); call(row.tick, 'SetPoint', 'RIGHT', -4, 0); call(row.tick, 'SetSize', 4, 4)
        row.tick:Hide()
    end
    function row:SetSelected(value)
        self.isSelected = value and true or false
        self.selectedBg:SetShown(self.isSelected); self.accent:SetShown(self.isSelected)
        if type(self.tick) == 'table' then self.tick:SetShown(self.isSelected) end
    end
    return row
end

--- Titre de section (moderne : petites capitales espacées ; classique : texte or du jeu ; Futuriste : « // TITRE »
--- en capitales cyan).
function S.Heading(parent, text)
    if S.IsClassic() then
        local fs = S.Text(parent, 12, S.colors.gold)
        fs:SetText(text or '')
        return fs
    end
    if S.IsFuture() then
        local fs = S.Text(parent, 10, S.colors.gold)
        fs:SetText('// ' .. S.Upper(text or ''))
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
    elseif S.IsFuture() then
        track:SetColorTexture(unpack(S.colors.line)); call(track, 'ClearAllPoints'); call(track, 'SetPoint', 'TOP'); call(track, 'SetPoint', 'BOTTOM')
        call(track, 'SetWidth', 1)
        thumb:SetColorTexture(unpack(S.colors.gold)); thumb:SetSize(4, 30)
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
