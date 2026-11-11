local _, Core = ...
--[[
  GuildLog.lua : journal de guilde du jeu, onglet « Journal » de la section Officiers (rangs 0 et 1, voir Announce.lua).
  Qui a invité qui, qui a rejoint, qui est parti de lui-même, qui a été renvoyé et par qui, promotions et rétrogradations
  avec le grade.

  - API du jeu (forme globale, distincte de C_Calendar.GetGuildEventInfo) : QueryGuildEventLog() demande le journal au
    serveur, GUILD_EVENT_LOG_UPDATE dit qu'il est arrivé ; ensuite seulement GetNumGuildEvents() et GetGuildEventInfo(i)
    = type, joueur1, joueur2, grade, années, mois, jours, heures. Types : invite (joueur1 invite joueur2), join (joueur1),
    promote / demote (joueur1 change joueur2 au grade), remove (joueur1 renvoie joueur2), quit (joueur1).
    Les quatre nombres sont le temps ÉCOULÉ depuis l'événement, tronqué à l'heure : pas une date. Le serveur ne garde
    qu'une centaine d'entrées ; nous en gardons MAX_EVENTS.
  - Relevé chez les officiers seulement : 45 s après la connexion puis toutes les 30 min (et à l'ouverture de l'onglet si
    la dernière demande a plus de 10 min, ou au bouton Relire, une fois par minute au plus). Toute mise à jour reçue est
    lue, même demandée par la fenêtre de guilde de Blizzard. Pas de réponse en 30 s : « serveur muet », affiché tel quel.
  - Date : maintenant − temps écoulé. Le jeu tronque à l'heure, donc chaque lecture donne une borne haute de la vraie
    date (au plus une heure trop tard) ; deux lectures du même événement à des moments différents ne donnent pas la même
    valeur. Le même événement = même type, mêmes joueurs (CanonicalKey), même grade, dates à moins de 2 h (3 jours pour
    un événement de plus d'un mois, que le jeu compte en mois) ; on garde la plus petite des deux bornes, ce qui ne
    dépend pas de l'ordre des lectures. Deux événements identiques réels (inviter deux fois la même personne) restent
    deux : une lecture est appariée à la mémoire dans l'ordre des dates, un pour un.
  - Quel index est le plus récent n'est jamais supposé : tout est trié par la date calculée ; le sens constaté est
    noté (state.newest = 'first' | 'last') et montré dans /quinte debug.
  - Partage : seulement entre officiers, en chuchotement (canal 'qoff' de Officers.lua, comme les notes), jamais sur le
    canal de guilde. Une lecture qui trouve du nouveau l'envoie aux officiers en ligne ; à la connexion on demande
    ('gask') ce qui manque. Fusion = même appariement que la lecture : le résultat ne dépend pas de l'ordre d'arrivée.
  - Le site lit QuintessenceDB.officers.guildLog.events (envoi d'un officier, site/docs/ADDON_FORMAT.md).
]]
local G = {}
Core.GuildLog = G
local S = Core.Style
local A = Core.Announce

local FIRST_QUERY, QUERY_EVERY, ANSWER_WAIT, MANUAL_GAP, OPEN_AGE, RETRY = 45, 1800, 30, 60, 600, 60
local MAX_EVENTS, MAX_SHARE, MAX_READ = 1000, 200, 500
local HOUR, DAY = 3600, 86400
local TOL_HOUR, TOL_COARSE = 2 * HOUR, 3 * DAY -- dates tronquées à l'heure ; au-delà d'un mois le jeu compte en mois
local W, H = 1078, 622 -- zone sous les onglets de la section (Officers.lua : 658 − 36)
G.FIRST_QUERY, G.QUERY_EVERY, G.ANSWER_WAIT, G.MAX_EVENTS = FIRST_QUERY, QUERY_EVERY, ANSWER_WAIT, MAX_EVENTS

local function secret(v) return type(issecretvalue) == 'function' and issecretvalue(v) end
local function now() return (GetServerTime or Core.Now)() end
local function store()
    local d = Core.Officers.DB()
    local g = d.guildLog
    if type(g) ~= 'table' then g = {}; d.guildLog = g end
    if type(g.events) ~= 'table' then g.events = {} end
    if type(g.state) ~= 'table' then g.state = {} end
    return g
end
G.DB = store
local function hasApi() return type(QueryGuildEventLog) == 'function' and type(GetNumGuildEvents) == 'function' and type(GetGuildEventInfo) == 'function' end
G.HasApi = hasApi

-- ---------------------------------------------------------------------------------------------------------------------
-- Lecture d'une entrée du jeu et validation (lecture et réseau)
-- ---------------------------------------------------------------------------------------------------------------------
local function cleanName(v)
    if v == nil then return '' end
    if type(v) ~= 'string' or secret(v) or #v > 100 or v:find('|', 1, true) then return nil end
    return v == '' and '' or Core.DisplayName(v)
end
local function cleanRank(v)
    if v == nil or v == '' then return nil, true end
    if type(v) ~= 'string' or secret(v) or #v > 60 or v:find('|', 1, true) then return nil, false end
    return v, true
end
local function cleanType(v)
    if type(v) ~= 'string' or secret(v) or #v > 16 or not v:match('^%a+$') then return nil end
    return v:lower()
end
local function count(v)
    if v == nil then return 0 end
    if type(v) ~= 'number' or secret(v) or v < 0 or v > 1000 then return nil end
    return math.floor(v)
end
--- Une entrée de GetGuildEventInfo → { type, p1, p2, rank, at, seen, c } ; nil si une valeur est secrète ou abîmée.
function G.FromGame(kind, p1, p2, rank, years, months, days, hours, at)
    local t, n1, n2 = cleanType(kind), cleanName(p1), cleanName(p2)
    local r, rankOk = cleanRank(rank)
    local y, mo, d, h = count(years), count(months), count(days), count(hours)
    if not (t and n1 and n2 and rankOk and y and mo and d and h) then return nil end
    local age = (y * 365 + mo * 30 + d) * DAY + h * HOUR
    return { type = t, p1 = n1, p2 = n2, rank = r, at = at - age, seen = at, c = (y > 0 or mo > 0) or nil }
end
-- Événement reçu d'un autre officier : mêmes champs, mêmes bornes
local function cleanShared(e, at)
    if type(e) ~= 'table' then return nil end
    local t, n1, n2 = cleanType(e.type), cleanName(e.p1), cleanName(e.p2)
    local r, rankOk = cleanRank(e.rank)
    local moment, seen = tonumber(e.at), tonumber(e.seen)
    if not (t and n1 and n2 and rankOk and moment and moment > 0 and moment <= at + 600) then return nil end
    seen = seen and seen >= moment and seen <= at + 600 and seen or moment
    return { type = t, p1 = n1, p2 = n2, rank = r, at = math.floor(moment), seen = math.floor(seen), c = e.c and true or nil }
end
G.CleanShared = cleanShared

-- ---------------------------------------------------------------------------------------------------------------------
-- Fusion : même résultat quel que soit l'ordre des lectures et des messages
-- ---------------------------------------------------------------------------------------------------------------------
local function person(name) return (name and name ~= '') and Core.CanonicalKey(name) or '' end
local function signature(e)
    return e.type .. '\1' .. person(e.p1) .. '\1' .. person(e.p2) .. '\1' .. (e.rank and e.rank:lower() or '')
end
local function tolerance(x, y) return (x.c or y.c) and TOL_COARSE or TOL_HOUR end
local function bySig(list)
    local out = {}
    for _, e in ipairs(list) do
        local key = signature(e)
        local group = out[key]
        if not group then group = {}; out[key] = group end
        group[#group + 1] = e
    end
    for _, group in pairs(out) do table.sort(group, function(p, q) return p.at < q.at end) end
    return out
end
--- Réunit `incoming` dans la liste `events` (modifiée sur place) ; rend les événements ajoutés, puis ceux dont la date
--- s'est resserrée (à repartager pour que tous les officiers gardent la même date).
function G.Merge(events, incoming)
    local mine, added, closer = bySig(events), {}, {}
    for key, theirs in pairs(bySig(incoming)) do
        local list, i, j = mine[key] or {}, 1, 1
        while j <= #theirs do
            local m, t = list[i], theirs[j]
            if not m then
                local copy = { type = t.type, p1 = t.p1, p2 = t.p2, rank = t.rank, at = t.at, seen = t.seen, c = t.c }
                events[#events + 1] = copy; added[#added + 1] = copy; j = j + 1
            elseif math.abs(m.at - t.at) <= tolerance(m, t) then
                -- Même événement : la plus petite borne haute est la plus proche de la vraie date
                if t.at < m.at then m.at = t.at; closer[#closer + 1] = m end
                m.seen = math.max(tonumber(m.seen) or m.at, tonumber(t.seen) or t.at)
                m.c = (m.c and t.c) or nil
                if m.p1 == '' then m.p1 = t.p1 end
                if m.p2 == '' then m.p2 = t.p2 end
                i, j = i + 1, j + 1
            elseif m.at < t.at then i = i + 1
            else
                local copy = { type = t.type, p1 = t.p1, p2 = t.p2, rank = t.rank, at = t.at, seen = t.seen, c = t.c }
                events[#events + 1] = copy; added[#added + 1] = copy; j = j + 1
            end
        end
    end
    -- Historique borné : les plus anciens partent
    if #events > MAX_EVENTS then
        table.sort(events, function(p, q) return p.at > q.at end)
        for k = #events, MAX_EVENTS + 1, -1 do events[k] = nil end
    end
    return added, closer
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Lecture du journal du serveur
-- ---------------------------------------------------------------------------------------------------------------------
--- Lit le journal reçu ; rend la liste (dans l'ordre des index), le nombre de lignes sautées et le sens constaté.
function G.Read(at)
    at = at or now()
    if not hasApi() then return nil, 0 end
    local ok, n = pcall(GetNumGuildEvents)
    if not ok or type(n) ~= 'number' or secret(n) then return nil, 0 end
    local list, skipped = {}, 0
    for i = 1, math.min(math.floor(n), MAX_READ) do
        local got, kind, p1, p2, rank, y, mo, d, h = pcall(GetGuildEventInfo, i)
        local e = got and G.FromGame(kind, p1, p2, rank, y, mo, d, h, at)
        if e then list[#list + 1] = e else skipped = skipped + 1 end
    end
    -- Sens du journal : la première et la dernière date différentes le disent, sans rien supposer
    local newest
    for k = 2, #list do
        if list[k].at ~= list[1].at then newest = list[1].at > list[k].at and 'first' or 'last'; break end
    end
    return list, skipped, newest
end

local function otherOfficers()
    local out, me = {}, Core.CanonicalKey(Core.PlayerName())
    for _, key in ipairs(A.OnlineOfficers()) do if key ~= me then out[#out + 1] = key end end
    return out
end
local function wire(list)
    local out = {}
    for i = 1, math.min(#list, MAX_SHARE) do
        local e = list[i]
        out[i] = { type = e.type, p1 = e.p1, p2 = e.p2, rank = e.rank, at = e.at, seen = e.seen, c = e.c }
    end
    return out
end
local function share(list, target)
    local comm = Core.Officers.comm
    if not comm or #list == 0 then return end
    local payload = { t = 'glog', list = wire(list) }
    if target then comm:Send(payload, target); return end
    for _, key in ipairs(otherOfficers()) do comm:Send(payload, key) end
end

--- GUILD_EVENT_LOG_UPDATE : lu chez un officier seulement, réuni, le nouveau est envoyé aux officiers en ligne.
function G.OnUpdate()
    if not A.IsOfficer() or Core.GuildStatus() ~= 'ok' then return false end
    local at = now()
    local list, skipped, newest = G.Read(at)
    if not list then return false end
    local g = store()
    local st = g.state
    st.answered, st.total, st.skipped, st.waiting, st.silent = at, #list + skipped, skipped, nil, nil
    if newest then st.newest = newest end
    local added, closer = G.Merge(g.events, list)
    st.added = #added
    -- Le nouveau, et les dates resserrées par cette lecture : envoyés aux officiers en ligne (eux ne renvoient rien)
    for _, e in ipairs(closer) do added[#added + 1] = e end
    if #added > 0 then
        table.sort(added, function(p, q) return p.at > q.at end)
        share(added)
    end
    G.Refresh()
    return true, #added
end

--- Demande le journal au serveur (officier, dans la guilde). manual : bouton Relire (une fois par minute).
function G.Query(manual)
    if Core.GuildStatus() ~= 'ok' or not A.IsOfficer() then return false, 'officier' end
    local g = store()
    local st, at = g.state, now()
    if not hasApi() then st.api = 'absent'; G.Refresh(); return false, 'absent' end
    st.api = nil
    if (tonumber(st.asked) or 0) > at - MANUAL_GAP then return false, 'tôt' end
    local ok = pcall(QueryGuildEventLog)
    if not ok then st.api = 'erreur'; G.Refresh(); return false, 'erreur' end
    st.asked, st.waiting = at, true
    local asked = at
    if C_Timer and C_Timer.After then
        C_Timer.After(ANSWER_WAIT, function()
            Core.Run('journal de guilde', function()
                local cur = store().state
                -- Aucune réponse à CETTE demande : serveur muet (pas une erreur, les entrées gardées restent)
                if cur.asked == asked and cur.waiting then cur.waiting, cur.silent = nil, at; G.Refresh() end
            end)
        end)
    end
    G.Refresh()
    return true
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Partage entre officiers (messages arrivés par le canal 'qoff', expéditeur officier déjà vérifié par Officers.lua)
-- ---------------------------------------------------------------------------------------------------------------------
local askedBack = {}
local function newest(events)
    local best = 0
    for _, e in ipairs(events) do if e.at > best then best = e.at end end
    return best
end
-- Ce qu'on demande à la connexion : tout tant que l'historique tient dans une réponse (200 entrées), sinon les 30
-- derniers jours (le reste est déjà chez nous ; la réponse donne de toute façon les 200 plus récentes)
local function askSince(events)
    if #events < MAX_SHARE then return 0 end
    return newest(events) - 30 * DAY
end
function G.Ask(target)
    local comm = Core.Officers.comm
    if not (comm and A.IsOfficer()) then return end
    local since = askSince(store().events)
    if target then comm:Send({ t = 'gask', since = since }, target); return end
    for _, key in ipairs(otherOfficers()) do comm:Send({ t = 'gask', since = since }, key) end
end
function G.OnMessage(data, sender, at)
    at = at or now()
    if data.t == 'gask' then
        local since, list = tonumber(data.since) or 0, {}
        for _, e in ipairs(store().events) do if e.at >= since then list[#list + 1] = e end end
        table.sort(list, function(p, q) return p.at > q.at end)
        share(list, sender)
        -- Réponse symétrique : il a peut-être ce qui nous manque (une fois par session et par officier)
        local key = Core.CanonicalKey(sender)
        if not askedBack[key] then askedBack[key] = true; G.Ask(sender) end
    elseif data.t == 'glog' and type(data.list) == 'table' then
        local clean = {}
        for i = 1, math.min(#data.list, MAX_SHARE) do
            local e = cleanShared(data.list[i], at)
            if e then clean[#clean + 1] = e end
        end
        local added = G.Merge(store().events, clean)
        if #added > 0 then G.Refresh() end
    end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Textes et lignes affichées
-- ---------------------------------------------------------------------------------------------------------------------
G.FILTERS = {
    { id = 'all', label = 'Tout' },
    { id = 'in', label = 'Arrivées', types = { invite = true, join = true } },
    { id = 'out', label = 'Départs', types = { quit = true, remove = true } },
    { id = 'rank', label = 'Grades', types = { promote = true, demote = true } },
}
local ORDER = { quit = 6, remove = 5, demote = 4, promote = 3, join = 2, invite = 1 } -- même heure : l'effet après la cause
local function who(name) return (name and name ~= '') and Core.Safe(name) or 'Inconnu' end
--- Phrase française d'un événement.
function G.Text(e)
    local p1, p2, rank = who(e.p1), who(e.p2), e.rank and Core.Safe(e.rank) or '?'
    if e.type == 'invite' then return p2 .. ' invité par ' .. p1
    elseif e.type == 'join' then return p1 .. ' a rejoint la guilde'
    elseif e.type == 'quit' then return p1 .. ' est parti de lui-même'
    elseif e.type == 'remove' then return p2 .. ' renvoyé par ' .. p1
    elseif e.type == 'promote' then return p2 .. ' promu au grade ' .. rank .. ' par ' .. p1
    elseif e.type == 'demote' then return p2 .. ' rétrogradé au grade ' .. rank .. ' par ' .. p1 end
    return Core.Safe(e.type) .. ' : ' .. p1 .. (e.p2 ~= '' and (', ' .. p2) or '')
end
local function when(e, at)
    local s = at - e.at
    local ago = s < HOUR and 'moins d’1 h' or s < DAY and math.floor(s / HOUR) .. ' h' or math.floor(s / DAY) .. ' j'
    local day = date('%d/%m/%Y', e.at)
    if e.c then return day .. ' environ (il y a ' .. math.floor(s / DAY) .. ' j)' end
    -- Borne haute à moins d'une heure près : l'heure pleine qui la précède
    return day .. ' vers ' .. tonumber(date('%H', e.at)) .. ' h (il y a ' .. ago .. ')'
end
G.When = when
--- Événements filtrés ('all', 'in', 'out', 'rank') et cherchés par nom, du plus récent au plus ancien.
function G.Rows(filter, query)
    local types, needle, out = nil, tostring(query or ''):lower(), {}
    for _, f in ipairs(G.FILTERS) do if f.id == filter then types = f.types end end
    for _, e in ipairs(store().events) do
        if (not types or types[e.type]) and (needle == '' or e.p1:lower():find(needle, 1, true) or e.p2:lower():find(needle, 1, true)) then
            out[#out + 1] = e
        end
    end
    table.sort(out, function(p, q)
        if p.at ~= q.at then return p.at > q.at end
        local x, y = ORDER[p.type] or 0, ORDER[q.type] or 0
        if x ~= y then return x > y end
        return signature(p) < signature(q)
    end)
    return out
end
--- État lisible du relevé (onglet et /quinte debug).
function G.Status(at)
    at = at or now()
    if not A.IsOfficer() then return 'réservé aux officiers (rangs 0 et 1) : rien n’est relevé.' end
    local g = store()
    local st, kept = g.state, #g.events
    local function ago(_, moment)
        local s = math.max(0, at - moment)
        return s < 60 and 'moins d’une minute' or s < HOUR and math.floor(s / 60) .. ' min' or s < DAY and math.floor(s / HOUR) .. ' h' or math.floor(s / DAY) .. ' j'
    end
    if st.api == 'absent' or not hasApi() then return 'le jeu ne fournit pas le journal de guilde (QueryGuildEventLog absent) ; ' .. kept .. ' entrée(s) gardée(s).' end
    if st.api == 'erreur' then return 'la demande au serveur a échoué (QueryGuildEventLog) ; nouvel essai dans 30 min.' end
    if st.waiting then return 'demande envoyée au serveur, en attente de sa réponse…' end
    if st.silent and (tonumber(st.silent) or 0) >= (tonumber(st.answered) or 0) then
        return 'le serveur n’a pas répondu à la dernière demande (aucune mise à jour en ' .. ANSWER_WAIT .. ' s). Nouvel essai dans 30 min ; '
            .. kept .. ' entrée(s) gardée(s).'
    end
    if not st.answered then return 'première lecture ' .. FIRST_QUERY .. ' secondes après la connexion.' end
    return 'lu il y a ' .. ago(at, st.answered) .. ' : ' .. tostring(st.total or 0) .. ' entrée(s) sur le serveur (une centaine au plus), '
        .. kept .. ' gardée(s) ici' .. ((tonumber(st.skipped) or 0) > 0 and (', ' .. st.skipped .. ' illisible(s) (valeurs secrètes)') or '')
        .. ' · partagé avec les officiers en ligne.'
end
function G.Summary()
    if not A.IsOfficer() then return 'réservé aux officiers' end
    local st = store().state
    return G.Status() .. (st.newest and (' Index le plus récent constaté : ' .. (st.newest == 'first' and '1 (premier)' or 'le dernier') .. '.') or '')
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Onglet « Journal » de la section Officiers
-- ---------------------------------------------------------------------------------------------------------------------
local view = { filter = 'all', query = '', offset = 0 }
local panel
local ROWS = math.floor((H - 92) / 22)
local function render(p)
    local at = now()
    local rows = G.Rows(view.filter, view.query)
    view.offset = math.max(0, math.min(view.offset, math.max(0, #rows - ROWS)))
    p.scroll:SetMinMaxValues(0, math.max(0, #rows - ROWS)); p.scroll:SetValue(view.offset)
    for id, b in pairs(p.filters) do b:SetActive(id == view.filter) end
    p.status:SetText(G.Status(at))
    p.empty:SetShown(#rows == 0)
    p.count:SetText(#rows .. ' entrée(s)')
    for i, line in ipairs(p.lines) do
        local e = rows[view.offset + i]
        if e then
            line.when:SetText(when(e, at))
            line.text:SetText(G.Text(e))
        else line.when:SetText(''); line.text:SetText('') end
    end
end
--- Construit la page (appelé par Officers.lua au premier affichage de l'onglet).
function G.CreatePanel(parent)
    local p = CreateFrame('Frame', nil, parent); p:SetAllPoints(parent)
    p.filters = {}
    for i, f in ipairs(G.FILTERS) do
        local b = S.Button(p, f.label, 84, 24, 'ghost'); b:SetPoint('TOPLEFT', (i - 1) * 88, 0)
        b:SetScript('OnClick', function() view.filter = f.id; view.offset = 0; Core.Run('journal de guilde', render, p) end)
        p.filters[f.id] = b
    end
    p.search = S.Input(p, 200, 'Chercher un joueur'); p.search:SetPoint('TOPLEFT', #G.FILTERS * 88 + 8, 0)
    p.search:SetScript('OnTextChanged', function(self) view.query = self:GetText() or ''; view.offset = 0; Core.Run('journal de guilde', render, p) end)
    p.reload = S.Button(p, 'Relire', 90, 24, 'primary'); p.reload:SetPoint('TOPLEFT', W - 90, 0)
    p.reload:SetScript('OnClick', function() Core.Run('journal de guilde', function() G.Query(true); render(p) end) end)
    p.count = S.Text(p, 11, S.colors.muted, 'RIGHT'); p.count:SetPoint('TOPLEFT', W - 300, -6); p.count:SetWidth(200)
    p.status = S.Text(p, 11, S.colors.muted); p.status:SetPoint('TOPLEFT', 0, -32); p.status:SetWidth(W); p.status:SetWordWrap(true)
    local box = S.Box(p, S.colors.panel, S.colors.line); box:SetPoint('TOPLEFT', 0, -60); box:SetSize(W, ROWS * 22 + 16)
    box:EnableMouseWheel(true)
    box:SetScript('OnMouseWheel', function(_, delta) view.offset = view.offset - delta * 3; Core.Run('journal de guilde', render, p) end)
    p.lines = {}
    for i = 1, ROWS do
        local line = {}
        line.when = S.Text(box, 11, S.colors.muted); line.when:SetPoint('TOPLEFT', 12, -9 - (i - 1) * 22); line.when:SetWidth(250)
        line.text = S.Text(box, 12); line.text:SetPoint('TOPLEFT', 270, -8 - (i - 1) * 22); line.text:SetWidth(W - 300)
        p.lines[i] = line
    end
    p.scroll = S.Scrollbar(box, ROWS * 22, function(value)
        if value ~= view.offset then view.offset = value; Core.Run('journal de guilde', render, p) end
    end)
    p.scroll:SetPoint('TOPLEFT', W - 14, -8)
    p.empty = S.Text(box, 12, S.colors.muted, 'CENTER'); p.empty:SetPoint('TOPLEFT', 60, -160); p.empty:SetWidth(W - 120); p.empty:SetWordWrap(true)
    p.empty:SetText('Aucune entrée pour l’instant. Le journal du jeu est lu chez les officiers 45 secondes après la connexion, puis toutes les 30 minutes, et partagé entre eux.')
    p.refresh = function()
        local st = store().state
        if (tonumber(st.asked) or 0) < now() - OPEN_AGE then G.Query() end -- onglet ouvert : journal relu s'il est vieux
        render(p)
    end
    panel = p
    return p
end
function G.Refresh()
    if panel and panel:IsVisible() then render(panel) end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Démarrage : première demande après la connexion, puis toutes les 30 min ; rang pas encore lu → nouvel essai en 1 min
-- ---------------------------------------------------------------------------------------------------------------------
local function loop()
    local done, why = G.Query()
    local wait = QUERY_EVERY
    if not done and (why == 'officier' and Core.GuildStatus() == 'pending') then wait = RETRY end
    C_Timer.After(wait, function() Core.Run('journal de guilde', loop) end)
end
local events = CreateFrame('Frame')
Core.Call(events.RegisterEvent, events, 'PLAYER_LOGIN')
Core.Call(events.RegisterEvent, events, 'GUILD_EVENT_LOG_UPDATE')
events:SetScript('OnEvent', function(_, event)
    if event == 'GUILD_EVENT_LOG_UPDATE' then return Core.Run('journal de guilde', G.OnUpdate) end
    if G.started or not (C_Timer and C_Timer.After) then return end
    G.started = true
    C_Timer.After(FIRST_QUERY, function()
        Core.Run('journal de guilde', function() G.Ask(); loop() end)
    end)
end)
