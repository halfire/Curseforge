local _, Core = ...
--[[
  Envoi sécurisé des messages (1.50.1, T194). Sur WoW Forever, l'envoi en guilde ou dans un canal public par un addon
  est bloqué par le jeu, même depuis un clic : ADDON_ACTION_BLOCKED « fonction protégée » (trace du GM, 17/11/2026).
  Seul le joueur peut envoyer, par une action sécurisée du jeu. Comme une macro : un bouton sécurisé du jeu
  (SecureActionButtonTemplate, type 'macro') exécute « /g texte » (guilde) ou « /1 texte » (canal Général) au clic ou à la
  touche. Le texte est préparé juste avant le clic (PreClick, hors combat), effacé après (PostClick).

    SS.Overlay(boutonVisible, prepare)   bouton sécurisé posé sur un bouton de l'interface ; prepare() → '/g', texte
    QuintessenceSecureSend               bouton de la touche « Envoyer le message prêt » (Bindings.xml, CLICK …)
    Core:RegisterReadyMessage(id, fn, order)  fn() → préfixe, texte (et note l'envoi en attente) ou nil
    SS.Blocked()                         nombre d'actions de Quintessence bloquées par le jeu (événement)

  En combat, le jeu interdit de changer le texte d'un bouton sécurisé : le clic ne fait alors rien (message expliqué).
  Rien n'est enregistré. Règle Retail 12+ : nos propres cadres seulement, aucune écriture dans les objets de Blizzard.
]]
local SS = {}
Core.SecureSend = SS
local blocked = 0
local readyMessages = {}

local function combat() return InCombatLockdown and InCombatLockdown() == true end
-- Appel protégé qui garde les deux valeurs (Core.Run n'en rend qu'une)
local function run(context, fn)
    local ok, a, b = pcall(fn)
    if not ok then Core.Error(context, a); return false end
    return true, a, b
end
function SS.NoteBlocked() blocked = blocked + 1 end
function SS.Blocked() return blocked end

--- Texte de macro : préfixe + message, 255 octets au plus, jamais une lettre coupée en deux.
function SS.Macro(prefix, text)
    local t = tostring(prefix or '/g') .. ' ' .. tostring(text or ''):gsub('[\r\n|]', ' ')
    if #t > 255 then
        t = t:sub(1, 255)
        while #t > 0 do
            local byte = t:byte(#t)
            if byte < 0x80 then break end
            t = t:sub(1, #t - 1)
            if byte >= 0xC0 then break end
        end
    end
    return t
end

local function secureButton(name, parent)
    local ok, b = pcall(CreateFrame, 'Button', name, parent or UIParent, 'SecureActionButtonTemplate')
    if not ok or type(b) ~= 'table' or type(b.SetAttribute) ~= 'function' then return nil end
    if b.RegisterForClicks then b:RegisterForClicks('AnyUp') end
    b:SetAttribute('type', 'macro')
    return b
end

-- Avant le clic : texte préparé (hors combat). Après : texte effacé, pour qu'un clic suivant ne renvoie jamais l'ancien.
local function arm(b, prepare)
    b:SetScript('PreClick', function(self)
        if combat() then
            Core.Print('En combat, le jeu ne permet pas de préparer le message : réessaie après le combat.')
            return
        end
        local ok, prefix, text = run('envoi sécurisé', prepare)
        self:SetAttribute('macrotext', (ok and prefix and text and text ~= '') and SS.Macro(prefix, text) or nil)
    end)
    b:SetScript('PostClick', function(self)
        if not combat() then self:SetAttribute('macrotext', nil) end
    end)
end

-- Boutons sécurisés posés sur l'interface (1.50.4, T210). Jamais enfants ni ancrés à nos fenêtres : un cadre qui contient
-- un bouton sécurisé, ou auquel un bouton sécurisé est ancré, devient protégé, et le jeu refuse alors de le fermer
-- ou de le déplacer en combat (« QuintessenceFrame:Hide() » bloqué, trace BugSack du GM, 18/11/2026). Le bouton est
-- donc enfant de UIParent, placé aux coordonnées du bouton visible et recalé hors combat seulement.
local overlays = {}
local function place(o)
    local b, visible = o.secure, o.visible
    if combat() then o.dirty = true; return end
    o.dirty = nil
    local shown = visible.IsVisible and visible:IsVisible()
    local l, bottom, w, h
    if shown and visible.GetRect then l, bottom, w, h = visible:GetRect() end
    if not (shown and type(l) == 'number' and type(bottom) == 'number' and type(w) == 'number' and type(h) == 'number' and w > 0 and h > 0) then
        o.rect = nil
        if b.Hide then b:Hide() end
        return
    end
    local scale = 1
    if visible.GetEffectiveScale and UIParent and UIParent.GetEffectiveScale then
        local vs, us = visible:GetEffectiveScale(), UIParent:GetEffectiveScale()
        if type(vs) == 'number' and type(us) == 'number' and us > 0 then scale = vs / us end
    end
    local rect = table.concat({ l * scale, bottom * scale, w * scale, h * scale }, ':')
    if rect ~= o.rect then
        o.rect = rect
        if b.ClearAllPoints then b:ClearAllPoints() end
        b:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', l * scale, bottom * scale)
        b:SetSize(w * scale, h * scale)
    end
    if b.SetFrameStrata and visible.GetFrameStrata then b:SetFrameStrata(visible:GetFrameStrata() or 'HIGH') end
    if b.SetFrameLevel and visible.GetFrameLevel then b:SetFrameLevel((visible:GetFrameLevel() or 1) + 5) end
    if b.Show then b:Show() end
end
function SS.Place() for _, o in ipairs(overlays) do place(o) end end
local regen = CreateFrame('Frame')
if regen.RegisterEvent then regen:RegisterEvent('PLAYER_REGEN_ENABLED') end
if regen.SetScript then regen:SetScript('OnEvent', function() for _, o in ipairs(overlays) do if o.dirty then place(o) end end end) end

--- Pose un bouton sécurisé sur un bouton visible : survol et aspect restent ceux du bouton visible.
function SS.Overlay(visible, prepare)
    if not visible then return nil end
    local b = secureButton(nil, UIParent)
    if not b then return nil end
    local o = { secure = b, visible = visible }
    overlays[#overlays + 1] = o
    if visible.HookScript then
        visible:HookScript('OnShow', function() place(o) end)
        visible:HookScript('OnHide', function() place(o) end)
        -- La fenêtre se déplace, défile ou change de taille : recalé au plus 5 fois par seconde, seulement visible
        local wait = 0
        visible:HookScript('OnUpdate', function(_, dt)
            wait = wait + (tonumber(dt) or 0)
            if wait >= 0.2 then wait = 0; place(o) end
        end)
    end
    place(o)
    arm(b, prepare)
    b:SetScript('OnEnter', function() local f = visible.GetScript and visible:GetScript('OnEnter'); if f then f(visible) end end)
    b:SetScript('OnLeave', function() local f = visible.GetScript and visible:GetScript('OnLeave'); if f then f(visible) end end)
    visible.secure = b
    return b
end

--- Inscrit un message « prêt » pour la touche : fn() renvoie préfixe ('/g', '/1'…) et texte, ou nil.
function Core:RegisterReadyMessage(id, fn, order)
    if type(id) ~= 'string' or type(fn) ~= 'function' then return end
    for i = #readyMessages, 1, -1 do if readyMessages[i].id == id then table.remove(readyMessages, i) end end
    readyMessages[#readyMessages + 1] = { id = id, fn = fn, order = tonumber(order) or 50 }
    table.sort(readyMessages, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.id < b.id end)
end

--- Premier message prêt : annonce de guilde refusée, puis ceux des modules. Renvoie préfixe, texte ou nil.
function SS.NextReady()
    if Core.GuildBlocked() then return nil end
    if Core.Announce and Core.Announce.PreparePending then
        local ok, prefix, text = pcall(Core.Announce.PreparePending)
        if ok and prefix then return prefix, text end
    end
    for _, r in ipairs(readyMessages) do
        local ok, prefix, text = run('message prêt ' .. r.id, r.fn)
        if ok and prefix and text then return prefix, text end
    end
    Core.Print('Aucun message prêt à envoyer.')
    return nil
end

-- Bouton de la touche (créé au chargement : un bouton sécurisé ne peut pas être créé en combat)
SS.key = secureButton('QuintessenceSecureSend', UIParent)
if SS.key then
    SS.key:SetSize(1, 1); SS.key:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', -10, 10)
    if SS.key.EnableMouse then SS.key:EnableMouse(false) end
    arm(SS.key, SS.NextReady)
end
BINDING_HEADER_QUINTESSENCE = 'Quintessence'
_G['BINDING_NAME_CLICK QuintessenceSecureSend:LeftButton'] = 'Envoyer le message prêt (annonce de guilde, recrutement de zone)'
BINDING_NAME_QUINTESSENCE_TOGGLE = 'Ouvrir ou fermer la fenêtre Quintessence'
