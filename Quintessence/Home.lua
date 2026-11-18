local _, Core = ...
--[[
  Accueil en tuiles (1.49.0, T173) : remplace la grille « Modules installés ». De haut en bas :
    - salutation au nom du joueur et ligne d'état (groupe, membres connectés, layer et world buffs) ;
    - bandeau rouge seulement s'il y a une urgence (SOS) ;
    - grande tuile (prochain événement) et colonne « À faire » ;
    - rangée de petites tuiles chiffrées (PvP de la semaine, raids de la semaine, donjons, commandes).
  Synchro, Interface et Taille sont passées dans Réglages > Affichage ; la liste des modules reste dans la barre latérale.

  Contrat des modules : champ facultatif home() de RegisterModule, appelé à chaque affichage de l'accueil (et toutes les
  15 s tant qu'il est visible). Il renvoie nil (rien à dire) ou une table dont chaque partie est facultative :
    alert = { text, button, action }                               bandeau d'urgence en haut
    main  = { kicker, title, lines = { {texte, ton}… }, hint, action } grande tuile (une seule : la première reçue)
    todo  = { { text, tone, order, action }… }                     lignes de la colonne À faire
    tile  = { title, icon, value, label, lines, hint, order, action } petite tuile
    line  = 'texte court'                                           ajouté à la ligne d'état du haut
  ton (tone) : 'text', 'muted', 'gold', 'mint', 'red' ou 'blue'. Les textes sont affichés tels quels : le module échappe
  les noms reçus du réseau (|). Une ligne À faire rouge passe en premier. Rien n'est enregistré : aucune SavedVariable.
  Règle Retail 12+ : uniquement nos propres cadres, aucune écriture dans les objets de Blizzard.
]]
local H = {}
Core.Home = H
local S = Core.Style
local W, HEIGHT, GAP = 1078, 658, 12
local TOP = 40                          -- sous la salutation
local ALERT_H = 36
local MAIN_W = 640
local TILE_H = 260
local MAX_TILES = 4
local ICON = 'Interface\\Icons\\INV_Misc_Note_01'
local home, tiles, todoRows = nil, {}, {}
local token = 0

local function tone(name) return S.colors[name or 'text'] or S.colors.text end
-- Majuscules françaises (string.upper ne connaît que l'ASCII : « événement » donnerait « éVéNEMENT »)
local ACCENTS = { ['é'] = 'É', ['è'] = 'È', ['ê'] = 'Ê', ['ë'] = 'Ë', ['à'] = 'À', ['â'] = 'Â', ['ç'] = 'Ç', ['î'] = 'Î',
    ['ï'] = 'Ï', ['ô'] = 'Ô', ['û'] = 'Û', ['ù'] = 'Ù', ['ü'] = 'Ü' }
local function upper(text)
    return (string.upper(text):gsub('\195[\160-\191]', function(c) return ACCENTS[c] or c end))
end
H.Upper = upper
local function secret(v) return type(issecretvalue) == 'function' and issecretvalue(v) end

-- ---------------------------------------------------------------------------------------------------------------------
-- Données : ce que dit le conteneur lui-même, puis chaque module
-- ---------------------------------------------------------------------------------------------------------------------

--- Membres de la guilde connectés (liste de guilde du jeu) ; nil si elle n'est pas encore lue.
local function onlineMembers()
    if type(GetNumGuildMembers) ~= 'function' or type(GetGuildRosterInfo) ~= 'function' then return nil end
    local ok, total, online = pcall(GetNumGuildMembers)
    if not ok or type(total) ~= 'number' or secret(total) or total <= 0 then return nil end
    if type(online) == 'number' and not secret(online) and online > 0 then return online end
    local n = 0
    for i = 1, math.min(total, 1000) do
        local good, name, _, _, _, _, _, _, _, isOnline = pcall(GetGuildRosterInfo, i)
        if good and type(name) == 'string' and not secret(name) and isOnline == true then n = n + 1 end
    end
    return n
end

local function groupLine()
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if type(n) ~= 'number' or secret(n) or n <= 0 then return 'Solo' end
    return (IsInRaid and IsInRaid()) and (n .. ' en raid') or (n .. ' en groupe')
end

--- Partie de l'accueil fournie par le conteneur : état, nouvelle version, annonces refusées (officiers).
function H.Own()
    local out = { todo = {} }
    local online = onlineMembers()
    out.line = groupLine() .. (online and ('  ·  ' .. online .. ' membre' .. (online > 1 and 's' or '') .. ' connecté' .. (online > 1 and 's' or '')) or '')
    local V = Core.Versions
    if V and V.update and V.update.label then
        out.todo[#out.todo + 1] = { text = 'Nouvelle version disponible : ' .. Core.Safe(V.update.label), tone = 'red', order = 1,
            action = function() Core.UI.Open('aide'); if Core.Help and Core.Help.Select then Core.Help.Select('update') end end }
    end
    local A = Core.Announce
    if A and A.IsOfficer and A.IsOfficer() and A.RefusedCount then
        local bad = A.RefusedCount()
        if bad > 0 then
            out.todo[#out.todo + 1] = { text = bad .. ' annonce' .. (bad > 1 and 's' or '') .. ' de guilde refusée' .. (bad > 1 and 's' or '') .. ' par le jeu',
                tone = 'gold', order = 80, action = function() if Core.Officers then Core.Officers.Open('annonces') end end }
        end
    end
    return out
end

local function lines(list)
    local out = {}
    if type(list) ~= 'table' then return out end
    for _, l in ipairs(list) do
        if type(l) == 'string' then out[#out + 1] = { l, 'text' }
        elseif type(l) == 'table' and type(l[1]) == 'string' then out[#out + 1] = { l[1], l[2] } end
    end
    return out
end

--- Rassemble l'accueil : { alerts, main, todo, tiles, lines }.
--- quiet : erreurs des modules ignorées en silence (pastilles de l'en-tête, déjà notées par l'accueil).
function H.Collect(quiet)
    local out = { alerts = {}, todo = {}, tiles = {}, lines = {} }
    local function add(id, r)
        if type(r) ~= 'table' then return end
        if type(r.alert) == 'table' and type(r.alert.text) == 'string' then out.alerts[#out.alerts + 1] = r.alert end
        if type(r.main) == 'table' and type(r.main.title) == 'string' and not out.main then out.main = r.main; r.main.module = id end
        if type(r.todo) == 'table' then
            for _, t in ipairs(r.todo) do
                if type(t) == 'table' and type(t.text) == 'string' then t.module = t.module or id; out.todo[#out.todo + 1] = t end
            end
        end
        if type(r.tile) == 'table' and type(r.tile.title) == 'string' then r.tile.module = id; out.tiles[#out.tiles + 1] = r.tile end
        if type(r.line) == 'string' and r.line ~= '' then out.lines[#out.lines + 1] = r.line end
    end
    add('home', H.Own())
    for _, m in ipairs(Core:ModuleList()) do
        if type(m.home) == 'function' then
            local ok, r
            if quiet then ok, r = pcall(m.home) else ok, r = Core.Run('accueil ' .. m.id, m.home) end
            if ok then add(m.id, r) end
        end
    end
    for i, t in ipairs(out.todo) do t.rank = i end
    table.sort(out.todo, function(a, b)
        local ua, ub = a.tone == 'red', b.tone == 'red'
        if ua ~= ub then return ua end
        local oa, ob = tonumber(a.order) or 50, tonumber(b.order) or 50
        if oa ~= ob then return oa < ob end
        return a.rank < b.rank
    end)
    table.sort(out.tiles, function(a, b)
        local oa, ob = tonumber(a.order) or 50, tonumber(b.order) or 50
        if oa ~= ob then return oa < ob end
        return a.title < b.title
    end)
    while #out.tiles > MAX_TILES do table.remove(out.tiles) end
    return out
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Cadres
-- ---------------------------------------------------------------------------------------------------------------------

local function run(action, what)
    if type(action) == 'function' then Core.Run('accueil ' .. (what or 'clic'), action) end
end

local function newTile(parent)
    local t = S.Box(parent, S.colors.panel, S.colors.line, 'Button')
    t.icon = t:CreateTexture(nil, 'ARTWORK'); t.icon:SetSize(26, 26); t.icon:SetPoint('TOPLEFT', 12, -12)
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.title = S.Text(t, 13, S.colors.text); t.title:SetPoint('TOPLEFT', 46, -18)
    t.value = S.Text(t, 26, S.colors.gold); t.value:SetPoint('TOPLEFT', 12, -50)
    t.label = S.Text(t, 11, S.colors.muted); t.label:SetPoint('BOTTOMLEFT', t.value, 'BOTTOMRIGHT', 8, 4)
    t.lines = {}
    for i = 1, 8 do
        local fs = S.Text(t, 11, S.colors.text); fs:SetPoint('TOPLEFT', 12, -92 - (i - 1) * 18)
        t.lines[i] = fs
    end
    t.hint = S.Text(t, 10, S.colors.muted); t.hint:SetPoint('BOTTOMLEFT', 12, 10)
    local hl = S.Fill(t, 'HIGHLIGHT', S.colors.hover); hl:SetAllPoints()
    t:SetScript('OnClick', function(self) run(self.action, self.what) end)
    return t
end

local function newTodoRow(parent)
    local row = S.Row(parent, 400, 30)
    row.dot = S.Fill(row, 'ARTWORK', S.colors.gold); row.dot:SetSize(6, 6); row.dot:SetPoint('LEFT', 8, 0)
    row.text = S.Text(row, 12, S.colors.text); row.text:SetPoint('LEFT', 22, 0)
    row:SetScript('OnClick', function(self) run(self.action, self.what) end)
    return row
end

function H.Create(parent)
    home = CreateFrame('Frame', nil, parent)
    home:SetAllPoints(parent)
    home.greeting = S.Text(home, 20, S.colors.text); home.greeting:SetPoint('TOPLEFT', 0, -2)
    home.status = S.Text(home, 11, S.colors.muted, 'RIGHT'); home.status:SetPoint('TOPRIGHT', 0, -10); home.status:SetWidth(660)

    -- Bandeau d'urgence (SOS)
    local alert = S.Box(home, S.colors.raised, S.colors.red)
    alert:SetSize(W, ALERT_H); alert:SetPoint('TOPLEFT', 0, -TOP)
    alert.bar = S.Fill(alert, 'ARTWORK', S.colors.red); alert.bar:SetPoint('TOPLEFT', 1, -1); alert.bar:SetPoint('BOTTOMLEFT', 1, 1); alert.bar:SetWidth(4)
    alert.text = S.Text(alert, 13, S.colors.red); alert.text:SetPoint('LEFT', 16, 0); alert.text:SetWidth(W - 180)
    alert.button = S.Button(alert, '', 140, 24, 'primary'); alert.button:SetPoint('RIGHT', -8, 0)
    alert.button:SetScript('OnClick', function(self) run(self.action, 'alerte') end)
    home.alert = alert

    -- Grande tuile : prochain événement
    local main = S.Box(home, S.colors.panel, S.colors.line, 'Button')
    main.kicker = S.Heading(main, ''); main.kicker:SetPoint('TOPLEFT', 16, -14)
    main.title = S.Text(main, 20, S.colors.gold); main.title:SetPoint('TOPLEFT', 16, -34); main.title:SetWidth(MAIN_W - 32)
    main.lines = {}
    for i = 1, 11 do
        local fs = S.Text(main, 13, S.colors.text); fs:SetPoint('TOPLEFT', 16, -74 - (i - 1) * 22); fs:SetWidth(MAIN_W - 32)
        main.lines[i] = fs
    end
    main.hint = S.Text(main, 11, S.colors.muted); main.hint:SetPoint('BOTTOMLEFT', 16, 12)
    local hl = S.Fill(main, 'HIGHLIGHT', S.colors.hover); hl:SetAllPoints()
    main:SetScript('OnClick', function(self) run(self.action, 'événement') end)
    home.main = main

    -- Colonne À faire
    local todo = S.Box(home, S.colors.panel, S.colors.line)
    todo.heading = S.Heading(todo, 'À faire'); todo.heading:SetPoint('TOPLEFT', 14, -14)
    todo.empty = S.Text(todo, 12, S.colors.muted); todo.empty:SetPoint('TOPLEFT', 14, -42)
    todo.empty:SetText('Rien à faire pour l’instant.')
    home.todo = todo

    home.empty = S.Text(home, 12, S.colors.muted); home.empty:SetWordWrap(true); home.empty:SetWidth(W)
    home.empty:SetText('Les tuiles arrivent avec les modules de la guilde (Événements, Craft, Fiches, Donjons & Quêtes, Carte). '
        .. 'Ajoute-les à côté de Quintessence dans Interface/AddOns.')

    -- Dessiné par UI.Open à chaque ouverture ; l'affichage lance seulement le rafraîchissement périodique
    home:SetScript('OnShow', function() H.Schedule() end)
    return home
end

--- Tant que l'accueil est visible : redessiné toutes les 15 s (compte à rebours, commandes et SOS reçus).
function H.Schedule()
    if not (C_Timer and C_Timer.After) then return end
    token = token + 1
    local mine = token
    C_Timer.After(15, function()
        if mine ~= token or not (home and home:IsVisible()) then return end
        Core.Run('accueil', H.Render)
        H.Schedule()
    end)
end

local function greeting()
    local hour = tonumber(date and date('%H') or 12) or 12
    local hello = (hour >= 5 and hour < 18) and 'Bonjour' or 'Bonsoir'
    local name = Core.DisplayName and Core.DisplayName(Core.PlayerName() or '') or Core.PlayerName()
    return hello .. ' ' .. Core.Safe(name or '')
end

local function fill(fs, entry)
    if entry then
        fs:SetText(entry[1]); fs:SetTextColor(unpack(tone(entry[2]))); fs:Show()
    else fs:SetText(''); fs:Hide() end
end

function H.Render()
    if not home then return end
    local data = H.Collect()
    home.greeting:SetText(greeting())
    home.status:SetText(table.concat(data.lines, '  ·  '))

    -- Bandeau d'urgence : plusieurs SOS = le premier, et le nombre des autres
    local top = TOP
    local alert = data.alerts[1]
    if alert then
        local extra = #data.alerts > 1 and ('  (+' .. (#data.alerts - 1) .. ')') or ''
        home.alert.text:SetText(alert.text .. extra)
        home.alert.button:SetLabel(alert.button or 'Voir')
        home.alert.button.action = alert.action
        home.alert.button:SetShown(type(alert.action) == 'function')
        home.alert:Show()
        top = TOP + ALERT_H + 10
    else home.alert:Hide() end

    local mainH = HEIGHT - top - GAP - TILE_H
    local main = data.main
    if main then
        local m = home.main
        m:ClearAllPoints(); m:SetPoint('TOPLEFT', 0, -top); m:SetSize(MAIN_W, mainH)
        local kicker = main.kicker or 'Prochain événement'
        m.kicker:SetText(S.IsClassic() and kicker or upper(kicker))
        m.title:SetText(main.title)
        local list = lines(main.lines)
        local room = math.max(1, math.floor((mainH - 74 - 34) / 22) + 1)
        for i, fs in ipairs(m.lines) do fill(fs, i <= room and list[i] or nil) end
        m.hint:SetText(main.hint or '')
        m.action = main.action
        m:Show()
    else home.main:Hide() end

    -- À faire : à droite de la grande tuile, ou sur toute la largeur sans elle
    local t = home.todo
    local todoX = main and (MAIN_W + GAP) or 0
    local todoW = W - todoX
    t:ClearAllPoints(); t:SetPoint('TOPLEFT', todoX, -top); t:SetSize(todoW, mainH)
    local room = math.max(1, math.floor((mainH - 46) / 32))
    for i = 1, math.max(room, #todoRows) do
        local item = i <= room and data.todo[i] or nil
        local row = todoRows[i]
        if item and not row then row = newTodoRow(t); todoRows[i] = row end
        if row then
            if item then
                row:ClearAllPoints(); row:SetPoint('TOPLEFT', 12, -38 - (i - 1) * 32); row:SetSize(todoW - 24, 30)
                row.text:SetWidth(todoW - 60)
                row.text:SetText(item.text)
                row.text:SetTextColor(unpack(item.tone == 'red' and S.colors.red or S.colors.text))
                row.dot:SetColorTexture(unpack(tone(item.tone == 'text' and 'gold' or item.tone or 'gold')))
                row.action, row.what = item.action, item.module
                row:Show()
            else row:Hide() end
        end
    end
    t.empty:SetShown(#data.todo == 0)

    -- Petites tuiles, étirées sur toute la largeur
    local n = #data.tiles
    local tileY = -(top + mainH + GAP)
    local tileW = n > 0 and (W - GAP * (n - 1)) / n or W
    for i = 1, math.max(n, #tiles) do
        local d = data.tiles[i]
        local tile = tiles[i]
        if d and not tile then tile = newTile(home); tiles[i] = tile end
        if tile then
            if d then
                tile:ClearAllPoints(); tile:SetPoint('TOPLEFT', (i - 1) * (tileW + GAP), tileY); tile:SetSize(tileW, TILE_H)
                tile.icon:SetTexture(d.icon or (Core.modules[d.module] and Core.modules[d.module].icon) or ICON)
                tile.title:SetText(d.title); tile.title:SetWidth(tileW - 58)
                tile.value:SetText(d.value ~= nil and tostring(d.value) or '')
                tile.label:SetText(d.label or ''); tile.label:SetWidth(math.max(40, tileW - 90))
                local list = lines(d.lines)
                for j, fs in ipairs(tile.lines) do fs:SetWidth(tileW - 24); fill(fs, list[j]) end
                tile.hint:SetText(d.hint or ''); tile.hint:SetWidth(tileW - 24)
                tile.action, tile.what = d.action, d.module
                tile:Show()
            else tile:Hide() end
        end
    end
    home.empty:ClearAllPoints(); home.empty:SetPoint('TOPLEFT', 0, tileY - 8)
    home.empty:SetShown(n == 0)
end
