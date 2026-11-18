local _, Core = ...
--[[
  Boîte à outils commune (1.50.0, T186) : complète Quintessence.Style avec les éléments que les modules refaisaient
  chacun de leur côté. Tout suit le thème choisi (S.colors, modifiées sur place par S.Apply) ; rien n'est écrit dans les
  objets de Blizzard, rien n'est enregistré (aucune SavedVariable).

    Jetons      S.size (tailles de texte), S.space (espacements), S.Tone(nom) (couleur par rôle)
    Couleurs    S.ClassColor(jeton), S.ClassText(texte, jeton), S.QualityColor(qualité), S.Hex(couleur)
    Icône       S.Icon(parent, taille, texture)               icône recadrée (sans la bordure grise du jeu)
    Saisie      S.OnText(champ, fn)                           réaction au texte sans perdre le texte indicatif
                S.TextArea(parent, largeur, hauteur, max)      zone de texte sur plusieurs lignes, défilante
    Fenêtres    S.Dialog(titre, largeur, hauteur)              petite fenêtre déplaçable, fermable, Échap
                S.MakeDialog(cadre, largeur, hauteur)          même chose sur un cadre existant
    Choix       S.Check(parent, libellé, fn)                  case à cocher
                S.Dropdown(parent, largeur, fn)               liste déroulante (:SetItems, :SetValue)
                S.Tabs(parent, onglets, fn, options)          barre d'onglets (fil d'Ariane de l'en-tête)
                S.Stars(parent, taille, fn, texture)          note de 1 à 5 avec aperçu au survol
    Affichage   S.Tooltip(cadre, titre, lignes)               infobulle au survol
                S.Empty(parent, largeur, icône, titre, texte) message « rien à afficher »
                S.Badge(parent, texte, ton)                   pastille
                S.Toast(texte, ton, secondes)                 message bref en haut de la fenêtre
]]
local S = Core.Style

--- Appelle une méthode si le cadre l'a (cadres simulés des tests, clients anciens) ; sinon ne fait rien.
function S.Call(f, method, ...)
    if type(f) ~= 'table' and type(f) ~= 'userdata' then return nil end
    local fn = f[method]
    if type(fn) == 'function' then return fn(f, ...) end
end
local FONT = STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF'
local function font() return S.Font and S.Font() or FONT end
local WHITE = 'Interface\\Buttons\\WHITE8X8'

-- ---------------------------------------------------------------------------------------------------------------------
-- Jetons
-- ---------------------------------------------------------------------------------------------------------------------

S.size = { xs = 10, sm = 11, md = 12, lg = 14, xl = 16, title = 20 }
S.space = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24 }
-- Rôles des couleurs : les modules disent ce que la couleur signifie, le thème choisit la teinte
local ROLES = { success = 'mint', ok = 'mint', warning = 'gold', warn = 'gold', danger = 'red', error = 'red', info = 'blue',
    accent = 'gold', text = 'text', muted = 'muted', gold = 'gold', mint = 'mint', red = 'red', blue = 'blue' }

--- Couleur d'un rôle ('success', 'warning', 'danger', 'info', 'muted'…) ou d'un nom de la palette.
function S.Tone(name) return S.colors[ROLES[name or 'text'] or 'text'] or S.colors.text end

--- Couleur au format |cffRRGGBB (sans le |c).
function S.Hex(color)
    color = color or S.colors.text
    return string.format('ff%02x%02x%02x', math.floor((color[1] or 1) * 255 + 0.5), math.floor((color[2] or 1) * 255 + 0.5),
        math.floor((color[3] or 1) * 255 + 0.5))
end

--- Texte coloré selon un rôle ou une couleur.
function S.Color(text, tone)
    local key = type(tone) == 'string' and ROLES[tone]
    if key and S.hex[key] then return '|c' .. S.hex[key] .. tostring(text or '') .. '|r' end
    local color = type(tone) == 'table' and tone or S.Tone(tone)
    return '|c' .. S.Hex(color) .. tostring(text or '') .. '|r'
end

-- Couleurs de classe de WoW Classic (repli si RAID_CLASS_COLORS manque ; lu, jamais modifié)
local CLASS = {
    WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 },
    ROGUE = { 1.00, 0.96, 0.41 }, PRIEST = { 1.00, 1.00, 1.00 }, SHAMAN = { 0.00, 0.44, 0.87 },
    MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 }, DRUID = { 1.00, 0.49, 0.04 },
}
-- Noms français des classes (fiches, profils) vers le jeton du jeu
local CLASS_FR = { guerrier = 'WARRIOR', paladin = 'PALADIN', chasseur = 'HUNTER', voleur = 'ROGUE', ['prêtre'] = 'PRIEST',
    pretre = 'PRIEST', chaman = 'SHAMAN', mage = 'MAGE', ['démoniste'] = 'WARLOCK', demoniste = 'WARLOCK', druide = 'DRUID' }

local function classToken(token)
    if type(token) ~= 'string' then return nil end
    if CLASS[token] then return token end
    local upper = token:upper()
    if CLASS[upper] then return upper end
    return CLASS_FR[token:lower()]
end

--- Couleur d'une classe (jeton du jeu WARRIOR… ou nom français) ; nil si inconnue.
function S.ClassColor(token)
    token = classToken(token)
    if not token then return nil end
    local game = type(RAID_CLASS_COLORS) == 'table' and RAID_CLASS_COLORS[token]
    if type(game) == 'table' and type(game.r) == 'number' then return { game.r, game.g, game.b, 1 } end
    local c = CLASS[token]
    return { c[1], c[2], c[3], 1 }
end

--- Nom écrit dans la couleur de sa classe (texte inchangé si la classe est inconnue).
function S.ClassText(text, token)
    local color = S.ClassColor(token)
    if not color then return tostring(text or '') end
    return '|c' .. S.Hex(color) .. tostring(text or '') .. '|r'
end

-- Qualités des objets (0 médiocre à 5 légendaire)
local QUALITY = { [0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 } }
-- Qualités en texte |c : couleurs du jeu, foncées sur le thème clair (le blanc des objets communs y serait invisible)
local QUALITY_GAME = { [0] = 'ff9d9d9d', 'ffffffff', 'ff1eff00', 'ff0070dd', 'ffa335ee', 'ffff8000', 'ffe6cc80', 'ff00ccff' }
local QUALITY_LIGHT = { [0] = 'ff6b5d4a', nil, 'ff1a6e0e', 'ff0a4a96', 'ff6516a3', 'ffa34b00', 'ff7d6430', 'ff006b8a' }
function S.QualityHex(q)
    q = tonumber(q) or 1
    if S.IsLight and S.IsLight() then return q == 1 and S.hex.text or QUALITY_LIGHT[q] or S.hex.text end
    return QUALITY_GAME[q] or 'ffffffff'
end
function S.QualityColor(q)
    local c = QUALITY[tonumber(q) or 1] or QUALITY[1]
    return { c[1], c[2], c[3], 1 }
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Icône recadrée
-- ---------------------------------------------------------------------------------------------------------------------

--- Icône du jeu sans sa bordure grise (8 % rognés de chaque côté).
function S.Icon(parent, size, texture, layer)
    local t = parent:CreateTexture(nil, layer or 'ARTWORK')
    t:SetSize(size or 18, size or 18)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if texture then t:SetTexture(texture) end
    return t
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Saisie
-- ---------------------------------------------------------------------------------------------------------------------

--- Ajoute une réaction au texte d'un champ sans effacer celle du kit (texte indicatif de S.Input).
function S.OnText(box, fn)
    local previous = box.GetScript and box:GetScript('OnTextChanged')
    box:SetScript('OnTextChanged', function(self, ...)
        if previous then previous(self, ...) end
        fn(self, ...)
    end)
end

--- Zone de texte sur plusieurs lignes : curseur visible, clic n'importe où pour écrire, défilement à la molette et
--- au curseur, bordure or quand elle est active. Renvoie l'EditBox ; edit.container est le cadre à placer.
--- (Reprise de la zone de commentaire de la Liste noire, corrigée en T172–T185 : SetFont reçoit ses trois arguments.)
function S.TextArea(parent, width, height, maxLetters)
    local area = S.Box(parent, S.colors.raised, S.colors.line); area:SetSize(width, height)
    local scroll = CreateFrame('ScrollFrame', nil, area)
    scroll:SetPoint('TOPLEFT', 2, -2); scroll:SetPoint('BOTTOMRIGHT', -2, 2)
    local edit = CreateFrame('EditBox', nil, scroll)
    local inner = height - 4
    edit:SetWidth(width - 4); edit:SetHeight(inner); edit:SetMultiLine(true); edit:SetAutoFocus(false)
    if ChatFontNormal and edit.SetFontObject then edit:SetFontObject(ChatFontNormal) end
    if edit.SetBlinkSpeed then edit:SetBlinkSpeed(0.5) end
    if edit:SetFont(font(), 12, '') == false then edit:SetFont(FONT, 12, '') end
    edit:SetTextColor(unpack(S.colors.text))
    edit:SetPoint('TOPLEFT', scroll, 'TOPLEFT', 0, 0); edit:EnableMouse(true); edit:EnableKeyboard(true)
    edit:SetTextInsets(1, 1, 0, 0); edit:SetMaxLetters(maxLetters or 600); scroll:SetScrollChild(edit)
    edit.container, edit.scroll = area, scroll
    area:EnableMouse(true); area:SetScript('OnMouseDown', function() edit:SetFocus() end)
    scroll:EnableMouse(true); scroll:SetScript('OnMouseDown', function() edit:SetFocus() end)
    edit:SetScript('OnEditFocusGained', function() area:SetBackdropBorderColor(unpack(S.colors.gold)) end)
    edit:SetScript('OnEditFocusLost', function() area:SetBackdropBorderColor(unpack(S.colors.line)) end)
    edit:SetScript('OnEscapePressed', edit.ClearFocus)
    area:Show(); scroll:Show(); edit:Show()
    local function wheel(_, delta)
        local maximum = math.max(0, scroll:GetVerticalScrollRange() or 0)
        scroll:SetVerticalScroll(math.max(0, math.min(maximum, (scroll:GetVerticalScroll() or 0) - delta * 24)))
    end
    scroll:EnableMouseWheel(true); scroll:SetScript('OnMouseWheel', wheel)
    edit:EnableMouseWheel(true); edit:SetScript('OnMouseWheel', wheel)
    edit:SetScript('OnCursorChanged', function(self, _, y, _, h)
        if type(y) ~= 'number' or type(h) ~= 'number' then return end
        local top = scroll:GetVerticalScroll() or 0
        local cursor = -y
        local required = cursor + h + 4
        if required > (self:GetHeight() or 0) then self:SetHeight(required) end
        if cursor < top then scroll:SetVerticalScroll(math.max(0, cursor))
        elseif cursor + h > top + inner then scroll:SetVerticalScroll(math.max(0, cursor + h - inner)) end
    end)
    edit:SetScript('OnTextChanged', function(self)
        if (self:GetText() or '') == '' then self:SetHeight(inner); scroll:SetVerticalScroll(0) end
    end)
    return edit
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Petites fenêtres
-- ---------------------------------------------------------------------------------------------------------------------

local function call(frame, method, ...)
    local fn = frame and frame[method]
    if type(fn) ~= 'function' then return false end
    return pcall(fn, frame, ...)
end

--- Rend un cadre existant déplaçable par son titre, fermable (croix et Échap) et au premier plan.
--- frame.title (texte du titre) est créé si title est donné.
function S.MakeDialog(frame, width, height, title)
    frame:SetSize(width, height); frame:SetFrameStrata('DIALOG'); frame:SetFrameLevel(300)
    frame:SetMovable(true); frame:SetClampedToScreen(true); frame:EnableMouse(true)
    frame.drag = CreateFrame('Frame', nil, frame); frame.drag:SetPoint('TOPLEFT', 0, 0); frame.drag:SetPoint('TOPRIGHT', -36, 0)
    frame.drag:SetHeight(32)
    frame.drag:EnableMouse(true); frame.drag:RegisterForDrag('LeftButton')
    frame.drag:SetScript('OnDragStart', function() frame:StartMoving() end)
    frame.drag:SetScript('OnDragStop', function() frame:StopMovingOrSizing() end)
    frame:SetScript('OnHide', function()
        frame:StopMovingOrSizing()
        if frame.comment then frame.comment:ClearFocus() end
        if frame.name then frame.name:ClearFocus() end
        if frame.onClose then Core.Run('fermeture', frame.onClose) end
    end)
    frame.close = S.Button(frame, 'X', 24, 24, 'ghost'); frame.close:SetPoint('TOPRIGHT', -6, -6)
    frame.close:SetScript('OnClick', function() frame:Hide() end)
    if title then
        frame.title = S.Text(frame, S.size.xl, S.colors.text); frame.title:SetPoint('TOPLEFT', 12, -12); frame.title:SetText(title)
    end
    -- Échap ferme la fenêtre ; toutes les autres touches continuent vers le jeu (déplacement, sorts).
    -- Hors combat seulement : SetPropagateKeyboardInput est protégé en combat sur les clients récents.
    if frame.EnableKeyboard and frame.SetPropagateKeyboardInput and not (InCombatLockdown and InCombatLockdown()) then
        if call(frame, 'SetPropagateKeyboardInput', true) then
            frame:EnableKeyboard(true)
            frame:SetScript('OnKeyDown', function(self, key)
                if key == 'ESCAPE' and not (InCombatLockdown and InCombatLockdown()) then
                    if call(self, 'SetPropagateKeyboardInput', false) then self:Hide(); call(self, 'SetPropagateKeyboardInput', true) end
                end
            end)
        end
    end
    return frame
end

--- Nouvelle petite fenêtre centrée, cachée, avec titre.
function S.Dialog(title, width, height)
    local frame = S.Box(UIParent, S.colors.bg, S.colors.line)
    S.MakeDialog(frame, width or 320, height or 200, title)
    frame:SetPoint('CENTER')
    frame:Hide()
    return frame
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Choix
-- ---------------------------------------------------------------------------------------------------------------------

--- Case à cocher avec libellé cliquable. box:SetChecked(v), box:GetChecked().
function S.Check(parent, label, onChange)
    local b = CreateFrame('Button', nil, parent)
    b:SetSize(220, 22)
    local square = S.Box(b, S.colors.raised, S.colors.line); square:SetSize(16, 16); square:SetPoint('LEFT', 0, 0)
    square:EnableMouse(false)
    local mark = square:CreateTexture(nil, 'OVERLAY'); mark:SetTexture('Interface\\Buttons\\UI-CheckBox-Check')
    mark:SetPoint('CENTER', 0, 0); mark:SetSize(20, 20); mark:SetVertexColor(unpack(S.colors.gold)); mark:Hide()
    b.label = S.Text(b, S.size.md, S.colors.text); b.label:SetPoint('LEFT', square, 'RIGHT', 8, 0); b.label:SetText(label or '')
    b.square, b.mark, b.checked = square, mark, false
    function b:SetChecked(value) self.checked = value and true or false; S.Call(self.mark, 'SetShown', self.checked) end
    function b:GetChecked() return self.checked end
    function b:SetLabel(text) self.label:SetText(text or '') end
    b:SetScript('OnEnter', function(self) if self.square.SetBackdropBorderColor then self.square:SetBackdropBorderColor(unpack(S.colors.gold)) end end)
    b:SetScript('OnLeave', function(self) if self.square.SetBackdropBorderColor then self.square:SetBackdropBorderColor(unpack(S.colors.line)) end end)
    b:SetScript('OnClick', function(self)
        self:SetChecked(not self.checked)
        if onChange then onChange(self.checked, self) end
    end)
    return b
end

--- Liste déroulante : un bouton qui ouvre la liste des choix. d:SetItems({ { value, label }… }), d:SetValue(value),
--- d:GetValue(). onSelect(value, label) au choix.
function S.Dropdown(parent, width, onSelect)
    local d = S.Button(parent, '', width or 180, 26, 'ghost')
    d.items, d.value = {}, nil
    local arrow = S.Text(d, S.size.sm, S.colors.muted, 'RIGHT'); arrow:SetPoint('RIGHT', -8, 0); arrow:SetText('v')
    d.list = S.Box(d, S.colors.panel, S.colors.line)
    d.list:SetPoint('TOPLEFT', d, 'BOTTOMLEFT', 0, -2); d.list:SetFrameStrata('DIALOG'); d.list:SetFrameLevel(400)
    d.list:EnableMouse(true); d.list:Hide()
    d.rows = {}
    local function label(value)
        for _, item in ipairs(d.items) do if item[1] == value then return item[2] end end
    end
    function d:SetValue(value)
        self.value = value
        self:SetLabel(label(value) or self.placeholder or 'Choisir')
    end
    function d:GetValue() return self.value end
    function d:SetItems(items)
        self.items = type(items) == 'table' and items or {}
        for _, row in ipairs(self.rows) do row:Hide() end
        local w = width or 180
        for i, item in ipairs(self.items) do
            local row = self.rows[i]
            if not row then
                row = S.Row(self.list, w - 4, 22)
                row.text = S.Text(row, S.size.md, S.colors.text); row.text:SetPoint('LEFT', 8, 0); row.text:SetWidth(w - 20)
                self.rows[i] = row
            end
            row:ClearAllPoints(); row:SetPoint('TOPLEFT', 2, -2 - (i - 1) * 22)
            row.text:SetText(item[2] or tostring(item[1]))
            row:SetScript('OnClick', function()
                self.list:Hide(); self:SetValue(item[1])
                if onSelect then onSelect(item[1], item[2]) end
            end)
            row:Show()
        end
        self.list:SetSize(w, 4 + #self.items * 22)
        self:SetValue(self.value)
    end
    d:SetScript('OnClick', function(self)
        local open = not self.list:IsShown()
        S.Call(self.list, 'SetShown', open)
        if open then for _, row in ipairs(self.rows) do if row:IsShown() then row:SetSelected(false) end end end
    end)
    if d.HookScript then d:HookScript('OnHide', function(self) self.list:Hide() end) end
    d:SetValue(nil)
    return d
end

-- Onglet moderne : texte et soulignement or, sans cadre (les onglets ne ressemblent plus à des boutons)
local function modernTab(parent, label, width)
    local b = CreateFrame('Button', nil, parent)
    b:SetSize(width, 30)
    b.label = S.Text(b, S.size.lg - 1, S.colors.muted, 'CENTER'); b.label:SetPoint('CENTER', 0, 1); b.label:SetText(label or '')
    b.bar = S.Fill(b, 'ARTWORK', S.colors.gold); b.bar:SetPoint('BOTTOMLEFT', 6, 0); b.bar:SetPoint('BOTTOMRIGHT', -6, 0)
    b.bar:SetHeight(2); b.bar:Hide()
    b.hoverBg = S.Fill(b, 'HIGHLIGHT', S.colors.hover); b.hoverBg:SetAllPoints()
    local function paint(self)
        local enabled = not self.IsEnabled or self:IsEnabled()
        self.label:SetTextColor(unpack((self.active and S.colors.text) or (self.hover and S.colors.gold) or S.colors.muted))
        S.Call(self.bar, 'SetShown', self.active and true or false)
        if self.SetAlpha then self:SetAlpha(enabled and 1 or 0.4) end
    end
    b:SetScript('OnEnter', function(self) self.hover = true; paint(self) end)
    b:SetScript('OnLeave', function(self) self.hover = false; paint(self) end)
    function b:SetLabel(text) self.label:SetText(S.IsFuture() and S.Upper(text) or text) end
    function b:SetActive(value) self.active = value and true or false; paint(self) end
    b:SetLabel(label or '')
    paint(b)
    return b
end

--- Barre d'onglets. defs = { { id, label, w }… } ; onSelect(id) au changement.
--- options : module (id du module : l'onglet choisi s'affiche dans l'en-tête « Module › onglet »), gap, height, x, y.
--- Renvoie { buttons = { [id] = bouton }, Select(id), Selected(), SetBadge(id, n), line }.
function S.Tabs(parent, defs, onSelect, options)
    options = options or {}
    local tabs = { buttons = {}, defs = defs, selected = nil }
    local x, gap = options.x or 0, options.gap or 8
    local classic = S.IsClassic()
    for _, def in ipairs(defs) do
        local w = def.w or 120
        local b = classic and S.Button(parent, def.label, w, options.height or 28, 'ghost') or modernTab(parent, def.label, w)
        b:SetPoint('TOPLEFT', x, options.y or 0)
        b:SetScript('OnClick', function() tabs:Select(def.id) end)
        tabs.buttons[def.id] = b
        x = x + w + gap
    end
    if not classic then
        -- Filet sous les onglets, sur toute la largeur du module
        tabs.line = S.Fill(parent, 'BORDER', S.colors.line); tabs.line:SetPoint('TOPLEFT', 0, (options.y or 0) - 30)
        tabs.line:SetPoint('TOPRIGHT', 0, (options.y or 0) - 30); tabs.line:SetHeight(1)
    end
    --- Met l'onglet en évidence et l'affiche dans l'en-tête, sans appeler onSelect (changement venu du module).
    function tabs:Mark(id)
        if not self.buttons[id] then return end
        self.selected = id
        for key, b in pairs(self.buttons) do b:SetActive(key == id) end
        if options.module and Core.UI and Core.UI.SetCrumb then
            for _, def in ipairs(defs) do if def.id == id then Core.UI.SetCrumb(options.module, def.label) end end
        end
    end
    function tabs:Select(id)
        if not self.buttons[id] then return end
        self:Mark(id)
        if onSelect then onSelect(id) end
    end
    function tabs:Selected() return self.selected end
    function tabs:SetBadge(id, n)
        local b = self.buttons[id]
        if not b then return end
        if not b.badge then b.badge = S.Badge(b, '', 'danger'); b.badge:SetPoint('TOPRIGHT', 2, 4) end
        n = tonumber(n) or 0
        b.badge:SetText(n > 99 and '99+' or tostring(n)); S.Call(b.badge, 'SetShown', n > 0)
    end
    return tabs
end

--- Note de 1 à 5 : étoiles cliquables, aperçu au survol. s:Set(n), s:Get(), s.onPreview(n) facultatif.
function S.Stars(parent, size, onPick, texture)
    size = size or 14
    local stars = CreateFrame('Frame', nil, parent)
    stars:SetSize(5 * (size + 8), size + 6)
    stars.value, stars.buttons = 0, {}
    local file = texture or 'Interface\\Common\\ReputationStar'
    local function paint(n)
        for i, b in ipairs(stars.buttons) do b.star:SetVertexColor(unpack(i <= n and S.colors.gold or S.colors.muted)) end
    end
    for i = 1, 5 do
        local b = CreateFrame('Button', nil, stars); b:SetSize(size + 6, size + 6); b:SetPoint('LEFT', (i - 1) * (size + 8), 0)
        b.star = b:CreateTexture(nil, 'ARTWORK'); b.star:SetSize(size, size); b.star:SetPoint('CENTER'); b.star:SetTexture(file)
        if not texture then b.star:SetTexCoord(0, 0.5, 0, 0.5) end
        b:SetScript('OnEnter', function() paint(i); if stars.onPreview then stars.onPreview(i) end end)
        b:SetScript('OnLeave', function() paint(stars.value); if stars.onPreview then stars.onPreview(nil) end end)
        b:SetScript('OnClick', function() stars:Set(i); if onPick then onPick(i) end end)
        stars.buttons[i] = b
    end
    function stars:Set(n) self.value = math.max(0, math.min(5, tonumber(n) or 0)); paint(self.value) end
    function stars:Get() return self.value end
    paint(0)
    return stars
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Affichage
-- ---------------------------------------------------------------------------------------------------------------------

--- Infobulle au survol d'un cadre. lines : liste de textes, ou fonction qui la renvoie (calculée à chaque survol).
function S.Tooltip(frame, title, lines)
    if not (frame and frame.HookScript) then return end
    frame:HookScript('OnEnter', function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
        local t = type(title) == 'function' and title() or title
        if t then GameTooltip:SetText(tostring(t), (S.OnDark and S.OnDark('gold') or S.colors.gold)[1], (S.OnDark and S.OnDark('gold') or S.colors.gold)[2], (S.OnDark and S.OnDark('gold') or S.colors.gold)[3]) end
        local list = type(lines) == 'function' and lines() or lines
        if type(list) == 'string' then list = { list } end
        for _, line in ipairs(type(list) == 'table' and list or {}) do
            GameTooltip:AddLine(tostring(line), (S.OnDark and S.OnDark('text') or S.colors.text)[1], (S.OnDark and S.OnDark('text') or S.colors.text)[2], (S.OnDark and S.OnDark('text') or S.colors.text)[3], true)
        end
        GameTooltip:Show()
    end)
    frame:HookScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
end

--- Message « rien à afficher » : icône, titre et explication, centrés. e:Set(titre, texte).
function S.Empty(parent, width, icon, title, text)
    local e = CreateFrame('Frame', nil, parent)
    e:SetSize(width or 400, 120)
    e.icon = S.Icon(e, 36, icon or 'Interface\\Icons\\INV_Misc_QuestionMark'); e.icon:SetPoint('TOP', 0, -4)
    e.icon:SetAlpha(0.7)
    e.title = S.Text(e, S.size.lg, S.colors.text, 'CENTER'); e.title:SetPoint('TOP', e.icon, 'BOTTOM', 0, -10)
    e.title:SetWidth(width or 400)
    e.text = S.Text(e, S.size.sm, S.colors.muted, 'CENTER'); e.text:SetPoint('TOP', e.title, 'BOTTOM', 0, -6)
    e.text:SetWidth(width or 400); e.text:SetWordWrap(true)
    function e:Set(t, body) self.title:SetText(t or ''); self.text:SetText(body or '') end
    e:Set(title, text)
    return e
end

--- Pastille colorée (compteur, état). b:SetText(texte), b:SetTone(ton).
function S.Badge(parent, text, tone)
    local b = S.Box(parent, S.Tone(tone or 'warning'), S.Tone(tone or 'warning'))
    b:SetSize(20, 16)
    b.label = S.Text(b, S.size.xs, S.colors.onAccent, 'CENTER'); b.label:SetPoint('CENTER', 0, 0)
    function b:SetText(value)
        self.label:SetText(value or '')
        local w = self.label.GetStringWidth and self.label:GetStringWidth()
        self:SetWidth(math.max(16, (type(w) == 'number' and w or 8 * #(tostring(value or ''))) + 10))
    end
    function b:SetTone(name)
        local c = S.Tone(name)
        if self.SetBackdropColor then self:SetBackdropColor(unpack(c)); self:SetBackdropBorderColor(unpack(c)) end
    end
    b:SetText(text)
    return b
end

-- Messages brefs : un seul cadre, réutilisé ; il s'efface tout seul
local toast
local function showToast(text, tone, seconds)
    local host = _G.QuintessenceFrame
    local anchor = host and host.IsShown and host:IsShown() and host or UIParent
    if not toast then
        toast = S.Box(UIParent, S.colors.panel, S.colors.line)
        toast:SetFrameStrata('TOOLTIP'); toast:SetSize(360, 34)
        toast.bar = S.Fill(toast, 'ARTWORK', S.colors.gold); toast.bar:SetPoint('TOPLEFT', 1, -1); toast.bar:SetPoint('BOTTOMLEFT', 1, 1)
        toast.bar:SetWidth(3)
        toast.text = S.Text(toast, S.size.md, S.colors.text, 'LEFT'); toast.text:SetPoint('LEFT', 14, 0); toast.text:SetWidth(332)
        toast.serial = 0
    end
    local color = S.Tone(tone or 'success')
    toast.bar:SetColorTexture(unpack(color))
    if toast.SetBackdropBorderColor then toast:SetBackdropBorderColor(unpack(color)) end
    toast.text:SetText(text)
    toast:ClearAllPoints()
    if anchor == UIParent then toast:SetPoint('TOP', UIParent, 'TOP', 0, -120) else toast:SetPoint('TOP', anchor, 'TOP', 0, -60) end
    toast:SetScale(anchor == UIParent and 1 or (anchor.GetScale and anchor:GetScale() or 1))
    toast:Show()
    toast.serial = toast.serial + 1
    local serial = toast.serial
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds or 4, function() if toast.serial == serial then toast:Hide() end end)
    end
    return toast
end
--- Un message bref ne doit jamais faire échouer l'action qui l'affiche : erreurs d'affichage ignorées.
function S.Toast(text, tone, seconds)
    if type(text) ~= 'string' or text == '' then return end
    S.lastToast = text
    local ok, frame = pcall(showToast, text, tone, seconds)
    return ok and frame or nil
end
