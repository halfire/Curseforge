local _, Core = ...
--[[
  Versions.lua : vérification des versions du conteneur Quintessence et de ses modules dans toute la guilde.

  - À la connexion (40 s après), chacun annonce ses versions sur le canal temps réel 'qver' :
      { t = 'v', v = '1.7.2', m = { craft = '0.8.0', map = '0.3.0', … }, r = 1 si réponse privée }
    Un membre qui a une version plus récente de quelque chose lui répond en privé (au plus une fois par heure) :
    celui qui est en retard est prévenu dans le chat (« nouvelle version disponible… ») et sur l'accueil.
  - /quinte versions (ou le bouton « Vérifier maintenant » de l'onglet Versions) : ping de guilde ; chaque membre
    répond avec ses versions (réponse 'O' de la synchro, champ i.t = table des modules), résumé dans le chat.
  - Onglet « Versions » de la section Officiers : chaque membre connu (30 jours), sa version du conteneur, ses modules en retard ou absents.
  - Mémoire : QuintessenceDB.versions[clé normalisée] = { name, v, m = { id = version }, at }.
  Rien n'est envoyé hors de la guilde Quintessence (la synchro le bloque) ; aucune donnée lue par le site.
]]
local V = {}
Core.Versions = V
local S = Core.Style

local KEEP = 30 * 86400        -- version d'un membre oubliée après 30 jours sans nouvelles
local ANNOUNCE_DELAY = 40      -- annonce 40 s après la connexion (la liste de guilde et la synchro sont prêtes)
local REPLY_GAP = 3600         -- au plus une réponse privée par membre et par heure
local CHECK_WAIT = 15          -- attente des réponses du ping
V.PACK_URL = 'quintessence-community.fr/addons/pack'
-- Édition CurseForge ou pack du site : seuls ces modules existent, ceux des autres membres ne sont ni comptés ni nommés
local CURSEFORGE_MODULES = { craft = true, caract = true, bis = true, group = true, map = true }
local function updateHint()
    if Core.IsCurseForge() then return 'mets-le à jour avec l’application CurseForge' end
    if Core.Officers and Core.Announce.IsOfficer() and not Core.Edition() then
        return 'télécharge le pack complet sur ' .. Core.Officers.PACK_URL .. ' puis remplace les dossiers dans Interface/AddOns'
    end
    return 'télécharge le pack sur ' .. V.PACK_URL .. ' puis remplace les dossiers dans Interface/AddOns'
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Versions et comparaison
-- ---------------------------------------------------------------------------------------------------------------------
local function parts(version)
    local out = {}
    for n in tostring(version or ''):gmatch('%d+') do out[#out + 1] = tonumber(n); if #out == 4 then break end end
    return out
end
--- 1 si a est plus récente que b, -1 si plus ancienne, 0 si égales (« 1.10.0 » > « 1.9.2 »).
function V.Compare(a, b)
    local x, y = parts(a), parts(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q and 1 or -1 end
    end
    return 0
end

local function validVersion(v) return type(v) == 'string' and #v > 0 and #v <= 20 and v:match('^[%w%.%-]+$') ~= nil end
local function validId(id) return type(id) == 'string' and #id > 0 and #id <= 24 and id:match('^[%w_%-]+$') ~= nil end

--- Nos versions : { v = conteneur, m = { id = version } } (modules chargés seulement).
function V.Mine()
    local m = {}
    for id, def in pairs(Core.modules) do
        if id ~= 'versions' and id ~= 'annonces' and validVersion(def.version) then m[id] = def.version end
    end
    return { v = Core.version, m = m }
end

-- Modules reçus : table { id = version } (1.7.2+) ou texte « craft 0.8.0, map 0.3.0 » (réponse de /quinte test ≤ 1.7.1)
local function readModules(t, text)
    local out, n = {}, 0
    if type(t) == 'table' then
        for id, version in pairs(t) do
            if validId(id) and validVersion(version) then out[id] = version; n = n + 1; if n >= 30 then break end end
        end
    elseif type(text) == 'string' then
        for id, version in text:sub(1, 400):gmatch('([%w_%-]+) ([%w%.%-]+)') do
            if validId(id) and validVersion(version) then out[id] = version; n = n + 1; if n >= 30 then break end end
        end
    end
    return out
end

local function store()
    if type(QuintessenceDB) ~= 'table' then return {} end
    if type(QuintessenceDB.versions) ~= 'table' then QuintessenceDB.versions = {} end
    return QuintessenceDB.versions
end

function V.Prune(now)
    now = now or Core.Now()
    local limited = Core.Edition() ~= nil
    for key, e in pairs(store()) do
        if type(e) ~= 'table' or type(e.at) ~= 'number' or now - e.at > KEEP or not validVersion(e.v) then store()[key] = nil
        elseif limited and type(e.m) == 'table' then
            for id in pairs(e.m) do if not CURSEFORGE_MODULES[id] then e.m[id] = nil end end
        end
    end
end

-- Ce qu'un membre a de plus récent que nous : liste « conteneur 1.7.2 », « craft 0.9.0 » (modules installés chez nous)
local function newerThanMine(entry, mine)
    local out = {}
    if V.Compare(entry.v, mine.v) > 0 then out[#out + 1] = 'conteneur ' .. entry.v end
    for id, version in pairs(entry.m or {}) do
        if mine.m[id] and V.Compare(version, mine.m[id]) > 0 then out[#out + 1] = id .. ' ' .. version end
    end
    table.sort(out)
    return out
end
-- Avons-nous quelque chose de plus récent que ce membre ?
local function olderThanMine(entry, mine)
    if V.Compare(entry.v, mine.v) < 0 then return true end
    for id, version in pairs(entry.m or {}) do
        if mine.m[id] and V.Compare(version, mine.m[id]) < 0 then return true end
    end
    return false
end

local warned = {}
--- Préviens une fois par version si un membre a plus récent que nous.
function V.CheckNewer(entry)
    local newer = newerThanMine(entry, V.Mine())
    if #newer == 0 then return end
    local label = table.concat(newer, ', ')
    V.update = { from = entry.name, items = newer, label = label }
    if warned[label] then return end
    warned[label] = true
    Core.Print('|cffffd100Nouvelle version disponible|r : ' .. Core.Safe(label) .. ' (chez ' .. Core.Safe(entry.name or '?')
        .. ') : ' .. updateHint() .. '.')
end

--- Enregistre les versions d'un membre (annonce, réponse ou réponse au ping).
function V.Record(sender, version, modules, modulesText, now)
    if type(sender) ~= 'string' or sender == '' or not validVersion(version) then return nil end
    now = now or Core.Now()
    local entry = {
        name = Core.DisplayName(sender),
        v = version,
        m = readModules(modules, modulesText),
        at = now,
    }
    if Core.Edition() then
        for id in pairs(entry.m) do if not CURSEFORGE_MODULES[id] then entry.m[id] = nil end end
    end
    store()[Core.CanonicalKey(sender)] = entry
    V.CheckNewer(entry)
    if V.Refresh then Core.Run('versions', V.Refresh) end
    return entry
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Réseau
-- ---------------------------------------------------------------------------------------------------------------------
local replied = {}
local function send(target)
    if not V.comm then return end
    local mine = V.Mine()
    V.comm:Send({ t = 'v', v = mine.v, m = mine.m, r = target and 1 or nil }, target)
end
V.Announce = function() send(nil) end

function V.OnMessage(data, sender)
    if type(data) ~= 'table' or data.t ~= 'v' then return end
    local entry = V.Record(sender, data.v, data.m)
    if not entry or data.r then return end
    -- Il est en retard sur nous : réponse privée pour qu'il soit prévenu (au plus une fois par heure)
    local key, now = Core.CanonicalKey(sender), Core.Now()
    if olderThanMine(entry, V.Mine()) and now - (replied[key] or 0) >= REPLY_GAP then
        replied[key] = now
        if C_Timer and C_Timer.After then
            C_Timer.After(1 + math.random() * 4, function() Core.Run('versions', send, sender) end)
        else send(sender) end
    end
end

--- /quinte versions : ping de guilde, résumé des réponses dans le chat après 15 s.
function V.Check()
    if not Core.sync then return Core.Print('Synchro non initialisée.') end
    local blocked = Core.GuildBlocked and Core.GuildBlocked()
    if blocked then return Core.Print('Vérification réservée aux membres de la guilde ' .. Core.GUILD .. '.') end
    V.checking = { at = Core.Now(), answers = {} }
    Core.sync:Ping(Core.Info())
    Core.Print('Vérification des versions envoyée à la guilde, résultat dans ' .. CHECK_WAIT .. ' secondes…')
    if V.Refresh then Core.Run('versions', V.Refresh) end
    if C_Timer and C_Timer.After then C_Timer.After(CHECK_WAIT, function() Core.Run('versions', V.Report) end) end
end

-- Réponse au ping (appelée par Core.Pong) : enregistrée ; silencieuse pendant une vérification
function V.OnPong(sender, info)
    info = type(info) == 'table' and info or {}
    local entry = V.Record(sender, info.v, info.t, info.m)
    if entry and V.checking then V.checking.answers[#V.checking.answers + 1] = entry end
    return V.checking ~= nil
end

--- Liste triée des membres connus et leur état par rapport aux versions les plus récentes vues dans la guilde.
function V.Rows()
    V.Prune()
    local mine = V.Mine()
    local latest = { v = mine.v, m = {} }
    for id, version in pairs(mine.m) do latest.m[id] = version end
    local entries = {}
    local myKey = Core.CanonicalKey(Core.PlayerName() or '')
    for key, e in pairs(store()) do
        if key ~= myKey then
            entries[#entries + 1] = e
            if V.Compare(e.v, latest.v) > 0 then latest.v = e.v end
            for id, version in pairs(e.m or {}) do
                if not latest.m[id] or V.Compare(version, latest.m[id]) > 0 then latest.m[id] = version end
            end
        end
    end
    entries[#entries + 1] = { name = Core.PlayerName(), v = mine.v, m = mine.m, at = Core.Now(), isPlayer = true }
    local rows = {}
    for _, e in ipairs(entries) do
        local old, missing = {}, {}
        for id, version in pairs(latest.m) do
            local theirs = e.m and e.m[id]
            if not theirs then missing[#missing + 1] = id
            elseif V.Compare(theirs, version) < 0 then old[#old + 1] = id .. ' ' .. theirs end
        end
        table.sort(old); table.sort(missing)
        rows[#rows + 1] = { entry = e, oldContainer = V.Compare(e.v, latest.v) < 0, old = old, missing = missing,
            upToDate = V.Compare(e.v, latest.v) >= 0 and #old == 0 }
    end
    table.sort(rows, function(a, b)
        if a.upToDate ~= b.upToDate then return not a.upToDate end
        return (a.entry.name or '') < (b.entry.name or '')
    end)
    return rows, latest
end

function V.Report()
    local check = V.checking
    V.checking = nil
    if not check then return end
    local rows, latest = V.Rows()
    local late, fresh = {}, 0
    for _, row in ipairs(rows) do
        if row.entry.at >= check.at and not row.entry.isPlayer then
            if row.upToDate then fresh = fresh + 1 else late[#late + 1] = row.entry.name end
        end
    end
    if #check.answers == 0 then
        Core.Print('Versions : aucune réponse (personne d’autre de connecté avec les addons, ou synchro coupée : /quinte debug).')
    else
        Core.Print(string.format('Versions : %d membre(s) ont répondu · %d à jour · %d à mettre à jour%s. Plus récent vu : conteneur %s.',
            #check.answers, fresh, #late, #late > 0 and (' (' .. Core.Safe(table.concat(late, ', ')) .. ')') or '', latest.v))
    end
    local mineRow
    for _, row in ipairs(rows) do if row.entry.isPlayer then mineRow = row end end
    if mineRow and not mineRow.upToDate then
        Core.Print('|cffffd100Ton pack n’est pas à jour|r : ' .. updateHint() .. '.')
    end
    if V.Refresh then Core.Run('versions', V.Refresh) end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Onglet « Versions »
-- ---------------------------------------------------------------------------------------------------------------------
local W, H = 1078, 622 -- corps de la section Officiers (1.39.0), textes de la même taille
local ROWS = math.floor((H - 134) / 29) -- 16
local panel
local offset = 0

local function ago(at)
    local s = math.max(0, Core.Now() - (at or 0))
    if s < 3600 then return math.floor(s / 60) .. ' min' end
    if s < 86400 then return math.floor(s / 3600) .. ' h' end
    return math.floor(s / 86400) .. ' j'
end

local function create(parent)
    panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints(parent)
    local title = S.Text(panel, 16, S.colors.text); title:SetPoint('TOPLEFT', 0, -2); title:SetText('Versions des addons dans la guilde')
    panel.mine = S.Text(panel, 12, S.colors.muted); panel.mine:SetPoint('TOPLEFT', 0, -26); panel.mine:SetWidth(W - 190)
    panel.mine:SetWordWrap(true)
    local check = S.Button(panel, 'Vérifier maintenant', 170, 26, 'primary'); check:SetPoint('TOPRIGHT', 0, 0)
    check:SetScript('OnClick', function() V.Check() end)
    panel.status = S.Text(panel, 12); panel.status:SetPoint('TOPLEFT', 0, -60); panel.status:SetWidth(W); panel.status:SetWordWrap(true)

    local box = S.Box(panel, S.colors.panel, S.colors.line)
    box:SetPoint('TOPLEFT', 0, -96); box:SetSize(W, H - 96)
    box:EnableMouseWheel(true)
    box:SetScript('OnMouseWheel', function(_, delta) offset = math.max(0, offset - delta * 2); V.Refresh() end)
    local h1 = S.Heading(box, 'Membre'); h1:SetPoint('TOPLEFT', 14, -10)
    local h2 = S.Heading(box, 'Conteneur'); h2:SetPoint('TOPLEFT', 250, -10)
    local h3 = S.Heading(box, 'Modules'); h3:SetPoint('TOPLEFT', 340, -10)
    local h4 = S.Heading(box, 'Vu'); h4:SetPoint('TOPRIGHT', -24, -10)
    panel.rows = {}
    for i = 1, ROWS do
        local r = S.Row(box, W - 16, 28)
        r:SetPoint('TOPLEFT', 1, -28 - (i - 1) * 29)
        r.dot = S.Fill(r, 'ARTWORK', S.colors.mint); r.dot:SetSize(7, 7); r.dot:SetPoint('LEFT', 10, 0)
        r.name = S.Text(r, 12); r.name:SetPoint('LEFT', 24, 0); r.name:SetWidth(220)
        r.container = S.Text(r, 12); r.container:SetPoint('LEFT', 250, 0); r.container:SetWidth(84)
        r.modules = S.Text(r, 11, S.colors.muted); r.modules:SetPoint('LEFT', 340, 0); r.modules:SetWidth(W - 420)
        r.seen = S.Text(r, 11, S.colors.muted, 'RIGHT'); r.seen:SetPoint('RIGHT', -10, 0); r.seen:SetWidth(50)
        panel.rows[i] = r
    end
    panel.scroll = S.Scrollbar(box, ROWS * 29, function(value) if value ~= offset then offset = value; V.Refresh() end end)
    panel.scroll:SetPoint('TOPLEFT', W - 12, -28)
    panel:SetScript('OnShow', function() Core.Run('versions', V.Refresh) end)
    return panel
end

function V.Refresh()
    if not panel or not panel:IsVisible() then return end
    local rows, latest = V.Rows()
    local mine = V.Mine()
    local names = {}
    for id, version in pairs(mine.m) do names[#names + 1] = id .. ' ' .. version end
    table.sort(names)
    panel.mine:SetText('Toi : conteneur ' .. mine.v .. (#names > 0 and (' · ' .. table.concat(names, ', ')) or ' · aucun module'))
    local late = 0
    for _, row in ipairs(rows) do if not row.upToDate then late = late + 1 end end
    local text
    if V.checking then
        text = '|c' .. S.hex.gold .. 'Vérification en cours…|r'
    elseif V.update then
        text = '|c' .. S.hex.red .. 'Ton pack n’est pas à jour|r (' .. Core.Safe(V.update.label) .. ' chez ' .. Core.Safe(V.update.from or '?')
            .. ') : ' .. updateHint() .. '.'
    else
        text = '|c' .. S.hex.mint .. 'Ton pack est à jour|r par rapport aux versions vues dans la guilde (conteneur ' .. latest.v .. ').'
    end
    panel.status:SetText(text .. '  |c' .. S.hex.muted .. #rows .. ' membre(s) connus · ' .. late .. ' à mettre à jour|r')

    local maxOffset = math.max(0, #rows - ROWS)
    if offset > maxOffset then offset = maxOffset end
    panel.scroll:SetMinMaxValues(0, maxOffset); panel.scroll:SetValue(offset); panel.scroll:SetShown(maxOffset > 0)
    for i, r in ipairs(panel.rows) do
        local row = rows[offset + i]
        if row then
            local e = row.entry
            r.dot:SetColorTexture(unpack(row.upToDate and S.colors.mint or S.colors.red))
            r.name:SetText(Core.Safe(e.name or '?') .. (e.isPlayer and (' |c' .. S.hex.gold .. '(toi)|r') or ''))
            r.container:SetText('|c' .. (row.oldContainer and S.hex.red or S.hex.mint) .. Core.Safe(e.v) .. '|r')
            local info = {}
            if #row.old > 0 then info[#info + 1] = '|c' .. S.hex.red .. 'anciens : ' .. Core.Safe(table.concat(row.old, ', ')) .. '|r' end
            if #row.missing > 0 then info[#info + 1] = 'absents : ' .. Core.Safe(table.concat(row.missing, ', ')) end
            r.modules:SetText(#info > 0 and table.concat(info, ' · ') or ('|c' .. S.hex.mint .. 'à jour|r'))
            r.seen:SetText(e.isPlayer and '—' or ago(e.at))
            r:Show()
        else
            r:Hide()
        end
    end
end

function V.Summary()
    if V.update then return '|c' .. S.hex.red .. 'Nouvelle version : ' .. Core.Safe(V.update.label) .. '|r' end
    local rows = V.Rows()
    local late = 0
    for _, row in ipairs(rows) do if not row.upToDate then late = late + 1 end end
    return late > 0 and (late .. ' membre(s) à mettre à jour') or 'Ton pack est à jour'
end

function V.Init()
    if V.ready then return end
    V.ready = true
    V.Prune()
    V.comm = Core:RegisterChannel('qver', function(data, sender) V.OnMessage(data, sender) end)
    if C_Timer and C_Timer.After then
        C_Timer.After(ANNOUNCE_DELAY, function() Core.Run('versions', V.Announce) end)
    end
end

V.CreatePanel = create -- onglet Versions de la section Officiers (Officers.lua)
