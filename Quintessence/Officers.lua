local _, Core = ...
--[[
  Officers.lua : section « Officiers » (rangs de guilde 0 et 1, voir Announce.lua), avec ses onglets :
  Annonces (Announce.lua), Joueurs (notes et vitesse de leveling), Chat (canal officier du jeu), Versions (Versions.lua), Pack.

  - Relevé : toutes les 5 min, chez TOUS les joueurs qui ont l'addon, la liste de guilde donne le niveau, la zone et la dernière
    connexion de chacun, y compris des membres sans addon. Un point par jour (60 au plus) sert à la vitesse de leveling.
  - Partage : personne n'envoie son relevé toutes les 5 min. Un membre n'est publié (synchro de guilde, groupe 'gscan') que tous les
    3 niveaux, ou après 2 h de jeu de plus que la version connue : aucune date n'est perdue, chaque version porte tout le journal. Le premier qui le voit publie, les autres reçoivent la
    version et n'ont plus rien à publier ; entre deux versions, les minutes les plus hautes gagnent, sans additionner.
    Garde-fou : deux joueurs qui ne se sont pas croisés ont chacun une partie de la nuit. Celui qui reçoit une version plus récente
    garde ce qu'il sait de plus (niveaux, zones, temps), et republie le tout : la version la plus haute finit complète chez tous.
  - Notes : une par joueur, 200 caractères, la plus récente gagne. Elles ne partent qu'en chuchotement vers les officiers
    en ligne (canal 'qoff'), jamais sur le canal de guilde que tout membre peut lire. Un message d'un non-officier est jeté.
  - Chat : le canal officier du jeu, avec son historique (200 lignes) ; envoi à un clic ou à la touche Entrée.
  Le site lit seulement le relevé (`roster`, page /statistiques, envoi par un officier).
  Notes et chat restent en jeu : le site ne les lit jamais.
]]
local O = {}
Core.Officers = O
local S = Core.Style
local A, V = Core.Announce, Core.Versions

O.PACK_URL = 'quintessence-community.fr/addons/pack-complet'
local SCAN, ROSTER_WAIT, FIRST_SCAN = 300, 5, 30
local KEEP_GONE, MAX_SAMPLES, MAX_CHAT, MAX_NOTE = 60 * 86400, 60, 200, 200
local MAX_LEVELS, MAX_ZONES, MAX_MINUTES = 80, 64, 5000000
local PUBLISH_MINUTES, PUBLISH_LEVELS, MAX_SHARED = 120, 3, 2000 -- 2 h de jeu ou 3 niveaux de plus que la version connue
local PUBLISH_WAIT, EXTRA_MINUTES = 7200, 30 -- un niveau pas encore envoyé part au bout de 2 h ; écart qui mérite une republication
local DAY = 86400
local W, H, BODY_TOP = 760, 476, 36

local function secret(v) return type(issecretvalue) == 'function' and issecretvalue(v) end
local function now() return (GetServerTime or Core.Now)() end
local function db()
    QuintessenceDB = QuintessenceDB or {}
    local d = QuintessenceDB.officers
    if type(d) ~= 'table' then d = {}; QuintessenceDB.officers = d end
    for _, k in ipairs({ 'notes', 'roster', 'chat' }) do if type(d[k]) ~= 'table' then d[k] = {} end end
    return d
end
O.DB = db

-- ---------------------------------------------------------------------------------------------------------------------
-- Relevé de la guilde et vitesse de leveling
-- ---------------------------------------------------------------------------------------------------------------------
local function lastOnline(i, online, at)
    if online then return at end
    if not GetGuildRosterLastOnline then return nil end
    local y, m, d, h = GetGuildRosterLastOnline(i)
    if secret(y) or (y == nil and m == nil and d == nil and h == nil) then return nil end
    return at - ((y or 0) * 365 + (m or 0) * 30 + (d or 0)) * DAY - (h or 0) * 3600
end
-- Journal d'un membre, même sans addon : niveaux vus avec leur date et leur zone, minutes en ligne (hors absent) par zone.
-- La date d'un niveau pris pendant qu'aucun officier n'était là est celle du relevé suivant : ordre de grandeur.
local function noteJournal(e, level, zone, minutes, at)
    if type(e.levels) ~= 'table' then e.levels = {} end
    if type(e.zones) ~= 'table' then e.zones = {} end
    e.min = math.min((tonumber(e.min) or 0) + minutes, MAX_MINUTES)
    if zone and minutes > 0 and (e.zones[zone] or Core.Count(e.zones) < MAX_ZONES) then e.zones[zone] = (e.zones[zone] or 0) + minutes end
    local rows, known = e.levels, false
    for _, row in ipairs(rows) do if row[1] == level then known = true; break end end
    if not known and #rows < MAX_LEVELS and (not rows[#rows] or level > rows[#rows][1]) then
        rows[#rows + 1] = { level, at, zone or '', e.min }
    end
end
--- Lit la liste de guilde (hors ligne compris) ; rend le nombre de membres lus.
function O.ReadRoster(at)
    at = at or now()
    if not (GetNumGuildMembers and GetGuildRosterInfo) then return 0 end
    local d = db()
    local roster, count, day = d.roster, 0, math.floor(at / DAY)
    -- Temps depuis le relevé précédent, 5 min au plus : un trou (officier déconnecté) ne compte pas comme du jeu
    local gap = d.scanAt and math.max(0, math.min(at - d.scanAt, SCAN)) / 60 or 0
    local changed = false
    for i = 1, GetNumGuildMembers() or 0 do
        local name, rankName, _, level, _, zone, _, _, online, status, class = GetGuildRosterInfo(i)
        if type(name) == 'string' and not secret(name) and type(level) == 'number' and not secret(level) then
            local key = Core.CanonicalKey(name)
            local e = roster[key]
            if type(e) ~= 'table' then
                e = { first = level, firstAt = at, samples = {} }
                roster[key] = e
            end
            if e.level and level > e.level then e.upAt = at end
            e.name, e.level, e.seen = Core.DisplayName(name), level, at
            e.class = type(class) == 'string' and not secret(class) and class or e.class
            e.rank = type(rankName) == 'string' and not secret(rankName) and rankName or e.rank
            e.online = online and not secret(online) and true or false
            e.last = lastOnline(i, e.online, at) or e.last
            local list = e.samples
            if list[#list] and list[#list].d == day then list[#list].l = level
            else list[#list + 1] = { d = day, l = level } end
            while #list > MAX_SAMPLES do table.remove(list, 1) end
            if not e.pubLevel then e.pubLevel, e.pubMin, e.pubAt = level, tonumber(e.min) or 0, at end -- rien à publier à la première vue
            local here = e.online and type(zone) == 'string' and not secret(zone) and zone ~= '' and zone or nil
            local away = secret(status) or status == 1
            noteJournal(e, level, here, (e.online and not away) and gap or 0, at)
            if level >= e.pubLevel + PUBLISH_LEVELS or e.min >= e.pubMin + PUBLISH_MINUTES
                or (level > e.pubLevel and at - (tonumber(e.pubAt) or 0) >= PUBLISH_WAIT) then
                e.v, e.pubLevel, e.pubMin, e.pubAt = math.max(at, (tonumber(e.v) or 0) + 1), level, e.min, at
                changed = true
            end
            count = count + 1
        end
    end
    if count > 0 then d.scanAt = at end
    if changed and O.sync then O.sync:NotifyLocal() end
    -- Parti de la guilde depuis longtemps : oublié, sa note reste jusqu'à ce qu'un officier l'efface
    if count > 0 then
        for key, e in pairs(roster) do
            if type(e) ~= 'table' or (tonumber(e.seen) or 0) < at - KEEP_GONE then roster[key] = nil end
        end
    end
    return count
end
-- ---------------------------------------------------------------------------------------------------------------------
-- Partage du relevé entre tous les addons (seuls ces champs voyagent : jamais les notes ni le chat)
-- ---------------------------------------------------------------------------------------------------------------------
local function cleanRecord(rec, at)
    if type(rec) ~= 'table' or type(rec.name) ~= 'string' or #rec.name > 100 or rec.name:find('|', 1, true) then return nil end
    local function number(v, low, high) v = tonumber(v); return v and v >= low and v <= high and v or nil end
    local out = { name = rec.name, level = number(rec.level, 1, 1000), v = number(rec.v, 1, at + 300), min = number(rec.min, 0, MAX_MINUTES),
        firstAt = number(rec.firstAt, 1, at + 300), seen = number(rec.seen, 1, at + 300), last = number(rec.last, 1, at + 300),
        levels = {}, zones = {} }
    if not (out.level and out.v and out.min) then return nil end
    if type(rec.class) == 'string' and #rec.class <= 16 then out.class = rec.class end
    if type(rec.levels) ~= 'table' or type(rec.zones) ~= 'table' or #rec.levels > MAX_LEVELS then return nil end
    for i, row in ipairs(rec.levels) do
        local place = type(row) == 'table' and row[3]
        if type(place) ~= 'string' or #place > 60 or place:find('|', 1, true) then return nil end
        local lvl, moment, spent = number(row[1], 1, 1000), number(row[2], 1, at + 300), number(row[4], 0, MAX_MINUTES)
        if not (lvl and moment and spent) then return nil end
        out.levels[i] = { lvl, moment, place, spent }
    end
    local zones = 0
    for place, minutes in pairs(rec.zones) do
        zones = zones + 1
        minutes = number(minutes, 0, MAX_MINUTES)
        if zones > MAX_ZONES or type(place) ~= 'string' or #place > 60 or place:find('|', 1, true) or not minutes then return nil end
        out.zones[place] = minutes
    end
    return out
end
local scanAdapter = {}
function scanAdapter.Manifest()
    local batches, batch = {}, {}
    for key, e in pairs(db().roster) do
        if type(e) == 'table' and type(e.v) == 'number' then
            batch[#batch + 1] = { key = key, v = e.v }
            if #batch == 20 then batches[#batches + 1] = batch; batch = {} end
        end
    end
    if #batch > 0 then batches[#batches + 1] = batch end
    return batches
end
function scanAdapter.Need(_, remote)
    local out, roster, at = {}, db().roster, now()
    if type(remote) ~= 'table' or #remote > 20 then return out end
    for _, row in ipairs(remote) do
        if type(row) ~= 'table' or type(row.key) ~= 'string' or #row.key > 100 or type(row.v) ~= 'number' then return {} end
        local e = roster[row.key]
        if row.v <= at + 300 and row.v > at - KEEP_GONE and not (type(e) == 'table' and (tonumber(e.v) or 0) >= row.v) then
            out[#out + 1] = { key = row.key }
        end
    end
    return out
end
function scanAdapter.Export(_, request)
    local e = type(request) == 'table' and type(request.key) == 'string' and db().roster[request.key]
    local rec = type(e) == 'table' and cleanRecord(e, now())
    return rec and { { key = request.key, rec = rec } } or {}
end
function scanAdapter.Merge(_, part, _, at, request)
    if type(part) ~= 'table' or type(request) ~= 'table' or part.key ~= request.key or type(part.key) ~= 'string' then return false end
    local rec = cleanRecord(part.rec, at)
    if not rec or Core.CanonicalKey(rec.name) ~= part.key or not (O.sync and O.sync:Member(rec.name)) then return false end
    local roster = db().roster
    local e = roster[part.key]
    if type(e) ~= 'table' then
        if Core.Count(roster) >= MAX_SHARED then return false end
        e = { first = rec.levels[1] and rec.levels[1][1] or rec.level, firstAt = rec.firstAt or at, samples = {}, levels = {}, zones = {}, min = 0 }
        roster[part.key] = e
    elseif (tonumber(e.v) or 0) >= rec.v then return false end
    if type(e.levels) ~= 'table' then e.levels = {} end
    if type(e.zones) ~= 'table' then e.zones = {} end
    -- Ce que nous savons et que cette version ignore : on le rajoute et on republie, sinon il resterait chez nous
    local known, extra = {}, (tonumber(e.min) or 0) >= rec.min + EXTRA_MINUTES
    for _, row in ipairs(rec.levels) do known[row[1]] = row end
    for _, row in ipairs(e.levels) do
        local theirs = known[row[1]]
        if not theirs or row[2] < theirs[2] - EXTRA_MINUTES * 60 then extra = true end
    end
    for place, minutes in pairs(e.zones) do
        if minutes >= (rec.zones[place] or 0) + EXTRA_MINUTES then extra = true end
    end
    e.name, e.class, e.v = e.name or rec.name, e.class or rec.class, rec.v
    e.level = math.max(tonumber(e.level) or 0, rec.level)
    e.min = math.max(tonumber(e.min) or 0, rec.min)
    e.firstAt = math.min(tonumber(e.firstAt) or rec.firstAt or at, rec.firstAt or at)
    e.seen = math.max(tonumber(e.seen) or 0, rec.seen or 0)
    if rec.last then e.last = math.max(tonumber(e.last) or 0, rec.last) end
    for place, minutes in pairs(rec.zones) do
        if e.zones[place] or Core.Count(e.zones) < MAX_ZONES then e.zones[place] = math.max(e.zones[place] or 0, minutes) end
    end
    -- Niveaux : réunis, la date la plus ancienne gagne (celui qui l'a vu le plus tôt est le plus près de la vérité)
    local byLevel = {}
    for _, row in ipairs(e.levels) do byLevel[row[1]] = row end
    for _, row in ipairs(rec.levels) do
        local old = byLevel[row[1]]
        if not old or row[2] < old[2] then byLevel[row[1]] = row end
    end
    local rows = {}
    for _, row in pairs(byLevel) do rows[#rows + 1] = row end
    table.sort(rows, function(a, b) return a[1] < b[1] end)
    while #rows > MAX_LEVELS do table.remove(rows, 1) end
    e.levels = rows
    -- Version connue : plus rien à publier tant qu'on n'a pas vu mieux
    e.pubLevel, e.pubMin, e.pubAt = math.max(tonumber(e.pubLevel) or 0, rec.level), math.max(tonumber(e.pubMin) or 0, rec.min), at
    if extra then
        e.v, e.pubLevel, e.pubMin = rec.v + 1 > at and rec.v + 1 or at, e.level, e.min
        if O.sync then O.sync:NotifyLocal() end
    end
    return true
end
O.ScanAdapter = scanAdapter
O.sync = Core:RegisterSync('gscan', {}, scanAdapter)

--- Niveaux gagnés sur 7 jours et niveaux par jour depuis le premier relevé (nil tant qu'il y a moins d'un jour de recul).
function O.Stats(e, at)
    at = at or now()
    local day, gain = math.floor(at / DAY), nil
    for _, sample in ipairs(e.samples or {}) do
        if sample.d >= day - 7 then gain = (e.level or 0) - sample.l; break end
    end
    local span = (at - (e.firstAt or at)) / DAY
    local rate = span >= 1 and ((e.level or 0) - (e.first or 0)) / span or nil
    return gain, rate
end
--- Membres relevés, triés par 'last' (dernière connexion), 'level' ou 'speed', filtrés sur le nom.
function O.Rows(sort, query, at)
    at = at or now()
    local rows, needle = {}, tostring(query or ''):lower()
    for key, e in pairs(db().roster) do
        if type(e) == 'table' and (needle == '' or tostring(e.name):lower():find(needle, 1, true)) then
            local gain, rate = O.Stats(e, at)
            rows[#rows + 1] = { key = key, e = e, gain = gain, rate = rate, note = db().notes[key] }
        end
    end
    table.sort(rows, function(a, b)
        local x, y
        if sort == 'level' then x, y = a.e.level or 0, b.e.level or 0
        elseif sort == 'speed' then x, y = a.rate or -1, b.rate or -1
        else x, y = a.e.last or 0, b.e.last or 0 end
        if x ~= y then return x > y end
        return tostring(a.e.name) < tostring(b.e.name)
    end)
    return rows
end
local function ago(at, moment)
    if not moment then return '?' end
    local s = at - moment
    if s < 600 then return 'en ligne' end
    if s < 3600 then return math.floor(s / 60) .. ' min' end
    if s < DAY then return math.floor(s / 3600) .. ' h' end
    return math.floor(s / DAY) .. ' j'
end
O.Ago = ago
function O.Scan()
    -- Seulement dans notre guilde. Tout le monde relève, seuls les officiers demandent aussi les membres hors ligne
    if Core.GuildStatus() ~= 'ok' then return false end
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
    -- La liste ne donne les absents que si « afficher hors ligne » est coché : remis comme le joueur l'avait laissé
    local shown = A.IsOfficer() and GetGuildRosterShowOffline and GetGuildRosterShowOffline()
    if shown == false and SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end
    C_Timer.After(ROSTER_WAIT, function()
        Core.Run('officiers', function()
            O.ReadRoster()
            if shown == false and SetGuildRosterShowOffline then SetGuildRosterShowOffline(false) end
            O.Refresh()
        end)
    end)
    return true
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Notes partagées entre officiers, en chuchotement seulement
-- ---------------------------------------------------------------------------------------------------------------------
local function otherOfficers()
    local out, me = {}, Core.CanonicalKey(Core.PlayerName())
    for _, key in ipairs(A.OnlineOfficers()) do if key ~= me then out[#out + 1] = key end end
    return out
end
local function cleanNote(text)
    local t = tostring(text or ''):gsub('[|\r\n\t]', ' '):gsub('%s%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #t > MAX_NOTE then t = t:sub(1, MAX_NOTE):gsub('[\192-\255][\128-\191]*$', '') end
    return t
end
O.CleanNote = cleanNote
local function validNote(n, at)
    return type(n) == 'table' and type(n.key) == 'string' and #n.key <= 80 and type(n.name) == 'string' and #n.name <= 60
        and type(n.text) == 'string' and #n.text <= MAX_NOTE + 8 and type(n.by) == 'string' and #n.by <= 60
        and type(n.at) == 'number' and n.at > 0 and n.at <= at + 300
end
local function mergeNote(n, at)
    if not validNote(n, at) then return false end
    local key = Core.CanonicalKey(n.key)
    local old = db().notes[key]
    if old and (tonumber(old.at) or 0) >= n.at then return false end
    db().notes[key] = { name = n.name, text = cleanNote(n.text), by = n.by, at = n.at }
    return true
end
--- Écrit (ou efface, texte vide) la note d'un joueur et la transmet aux officiers en ligne.
function O.SetNote(key, name, text)
    if not A.IsOfficer() then return false, 'Réservé aux officiers.' end
    local at = math.max(now(), ((db().notes[key] or {}).at or 0) + 1)
    local note = { name = name, text = cleanNote(text), by = Core.DisplayName(Core.PlayerName()), at = at }
    db().notes[key] = note
    if O.comm then
        for _, target in ipairs(otherOfficers()) do
            O.comm:Send({ t = 'note', key = key, name = note.name, text = note.text, by = note.by, at = at }, target)
        end
    end
    return true
end
function O.OnMessage(data, sender)
    if type(data) ~= 'table' or not A.IsOfficer() or not A.SenderIsOfficer(sender) then return end
    local at = now()
    if data.t == 'note' then
        if mergeNote(data, at) then O.Refresh() end
    elseif data.t == 'ask' then
        local since, list = tonumber(data.since) or 0, {}
        for key, n in pairs(db().notes) do
            if (tonumber(n.at) or 0) > since and #list < 200 then
                list[#list + 1] = { key = key, name = n.name, text = n.text, by = n.by, at = n.at }
            end
        end
        if #list > 0 then O.comm:Send({ t = 'notes', list = list }, sender) end
    elseif data.t == 'notes' and type(data.list) == 'table' then
        local changed = false
        for i = 1, math.min(#data.list, 200) do changed = mergeNote(data.list[i], at) or changed end
        if changed then O.Refresh() end
    end
end
function O.AskNotes()
    if not (O.comm and A.IsOfficer()) then return end
    local since = 0
    for _, n in pairs(db().notes) do since = math.max(since, tonumber(n.at) or 0) end
    for _, target in ipairs(otherOfficers()) do O.comm:Send({ t = 'ask', since = since }, target) end
end
O.comm = Core:RegisterChannel('qoff', function(data, sender) Core.Run('officiers', O.OnMessage, data, sender) end)

-- ---------------------------------------------------------------------------------------------------------------------
-- Chat des officiers
-- ---------------------------------------------------------------------------------------------------------------------
function O.OnOfficerChat(text, sender)
    if type(text) ~= 'string' or secret(text) or secret(sender) or not A.IsOfficer() then return end
    local chat = db().chat
    chat[#chat + 1] = { at = now(), name = Core.DisplayName(sender), text = text:sub(1, 255) }
    while #chat > MAX_CHAT do table.remove(chat, 1) end
    O.Refresh()
end
--- Envoi sur le canal officier du jeu (un clic ou Entrée = un message).
function O.SendChat(text)
    local t = A.Clean(text)
    if t == '' then return false end
    if not A.IsOfficer() then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    return (pcall(send, t, 'OFFICER'))
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Interface
-- ---------------------------------------------------------------------------------------------------------------------
local TABS = {
    { id = 'annonces', label = 'Annonces' }, { id = 'joueurs', label = 'Joueurs' }, { id = 'chat', label = 'Chat' },
    { id = 'versions', label = 'Versions' }, { id = 'pack', label = 'Pack complet' },
}
local root, active = nil, 'annonces'
local pages, tabButtons = {}, {}
local players = { sort = 'last', query = '', offset = 0, selected = nil, confirm = nil }
local chatOffset = 0
local P_ROWS, C_ROWS = 11, 17

local function renderPlayers(p)
    local at = now()
    local rows = O.Rows(players.sort, players.query, at)
    players.offset = math.max(0, math.min(players.offset, math.max(0, #rows - P_ROWS)))
    p.scroll:SetMinMaxValues(0, math.max(0, #rows - P_ROWS)); p.scroll:SetValue(players.offset)
    p.empty:SetShown(#rows == 0)
    for id, b in pairs(p.sorts) do b:SetActive(id == players.sort) end
    for i, r in ipairs(p.rows) do
        local row = rows[players.offset + i]
        if row then
            r.key = row.key
            r:SetSelected(row.key == players.selected)
            r.name:SetText(Core.Safe(row.e.name) .. (row.note and row.note.text ~= '' and (' |c' .. S.hex.gold .. '*|r') or ''))
            r.level:SetText(tostring(row.e.level or '?'))
            r.gain:SetText(row.gain and row.gain > 0 and ('+' .. row.gain) or '—')
            r.rate:SetText(row.rate and string.format('%.1f', row.rate) or '—')
            r.last:SetText(ago(at, row.e.last))
            r:Show()
        else r.key = nil; r:Hide() end
    end
    local e = players.selected and db().roster[players.selected]
    p.detail:SetShown(e ~= nil); p.none:SetShown(e == nil)
    if e then
        local note = db().notes[players.selected]
        local gain, rate = O.Stats(e, at)
        p.who:SetText(Core.Safe(e.name) .. ' · niveau ' .. tostring(e.level or '?'))
        p.info:SetText(string.format('%s\nDernière connexion : %s\nSuivi depuis : niveau %s, il y a %s\n7 derniers jours : %s niveau(x)\nVitesse : %s niveau(x) par jour',
            Core.Safe(e.rank or 'Rang inconnu'), ago(at, e.last), tostring(e.first or '?'), ago(at, e.firstAt), gain and tostring(gain) or '—',
            rate and string.format('%.1f', rate) or 'pas encore assez de recul'))
        p.noteBy:SetText(note and note.text ~= '' and ('Écrite par ' .. Core.Safe(note.by) .. ', il y a ' .. ago(at, note.at)) or 'Aucune note. Seuls les officiers les voient.')
    end
end
local function createPlayers(parent)
    local p = CreateFrame('Frame', nil, parent); p:SetAllPoints(parent)
    p.search = S.Input(p, 190, 'Chercher un joueur'); p.search:SetPoint('TOPLEFT', 0, 0)
    p.search:SetScript('OnTextChanged', function(self) players.query = self:GetText() or ''; players.offset = 0; Core.Run('officiers', renderPlayers, p) end)
    p.sorts = {}
    for i, choice in ipairs({ { 'last', 'Connexion' }, { 'level', 'Niveau' }, { 'speed', 'Vitesse' } }) do
        local b = S.Button(p, choice[2], 78, 24, 'ghost'); b:SetPoint('TOPLEFT', 196 + (i - 1) * 82, -1)
        b:SetScript('OnClick', function() players.sort = choice[1]; Core.Run('officiers', renderPlayers, p) end)
        p.sorts[choice[1]] = b
    end
    local box = S.Box(p, S.colors.panel, S.colors.line); box:SetPoint('TOPLEFT', 0, -32); box:SetSize(444, P_ROWS * 31 + 30)
    box:EnableMouseWheel(true)
    box:SetScript('OnMouseWheel', function(_, delta) players.offset = players.offset - delta * 2; Core.Run('officiers', renderPlayers, p) end)
    for _, h in ipairs({ { 'Joueur', 12 }, { 'Niv.', 190 }, { '7 j', 236 }, { 'Niv./j', 282 }, { 'Vu', 342 } }) do
        local t = S.Heading(box, h[1]); t:SetPoint('TOPLEFT', h[2], -8)
    end
    p.rows = {}
    for i = 1, P_ROWS do
        local r = S.Row(box, 428, 30); r:SetPoint('TOPLEFT', 1, -26 - (i - 1) * 31)
        r.name = S.Text(r, 12); r.name:SetPoint('LEFT', 11, 0); r.name:SetWidth(174)
        r.level = S.Text(r, 12); r.level:SetPoint('LEFT', 189, 0); r.level:SetWidth(40)
        r.gain = S.Text(r, 12, S.colors.mint); r.gain:SetPoint('LEFT', 235, 0); r.gain:SetWidth(40)
        r.rate = S.Text(r, 12); r.rate:SetPoint('LEFT', 281, 0); r.rate:SetWidth(50)
        r.last = S.Text(r, 11, S.colors.muted); r.last:SetPoint('LEFT', 341, 0); r.last:SetWidth(80)
        r:SetScript('OnClick', function(self)
            if not self.key then return end
            players.selected = self.key
            local note = db().notes[self.key]
            p.note:SetText(note and note.text or '')
            Core.Run('officiers', renderPlayers, p)
        end)
        p.rows[i] = r
    end
    p.scroll = S.Scrollbar(box, P_ROWS * 31, function(value)
        if value ~= players.offset then players.offset = value; Core.Run('officiers', renderPlayers, p) end
    end)
    p.scroll:SetPoint('TOPLEFT', 430, -26)
    p.empty = S.Text(box, 12, S.colors.muted, 'CENTER'); p.empty:SetPoint('TOPLEFT', 20, -150); p.empty:SetWidth(400); p.empty:SetWordWrap(true)
    p.empty:SetText('Aucun joueur relevé pour l\'instant : le premier relevé arrive 30 secondes après la connexion.')
    local side = S.Box(p, S.colors.panel, S.colors.line); side:SetPoint('TOPLEFT', 456, 0); side:SetSize(304, P_ROWS * 31 + 62)
    p.none = S.Text(side, 12, S.colors.muted, 'CENTER'); p.none:SetPoint('TOPLEFT', 20, -150); p.none:SetWidth(264); p.none:SetWordWrap(true)
    p.none:SetText('Clique sur un joueur pour voir son suivi et écrire une note.')
    p.detail = CreateFrame('Frame', nil, side); p.detail:SetAllPoints(side)
    p.who = S.Text(p.detail, 14); p.who:SetPoint('TOPLEFT', 14, -12); p.who:SetWidth(276)
    p.info = S.Text(p.detail, 12, S.colors.muted); p.info:SetPoint('TOPLEFT', 14, -36); p.info:SetWidth(276); p.info:SetWordWrap(true)
    local label = S.Heading(p.detail, 'Note des officiers'); label:SetPoint('TOPLEFT', 14, -136)
    p.note = S.Input(p.detail, 276, 'Note sur ce joueur (200 caractères)'); p.note:SetPoint('TOPLEFT', 14, -156)
    if p.note.SetMaxBytes then p.note:SetMaxBytes(MAX_NOTE) end
    p.save = S.Button(p.detail, 'Enregistrer', 110, 24, 'primary'); p.save:SetPoint('TOPLEFT', 14, -190)
    p.save:SetScript('OnClick', function()
        Core.Run('officiers', function()
            local e = players.selected and db().roster[players.selected]
            if e then O.SetNote(players.selected, e.name, p.note:GetText()); renderPlayers(p) end
        end)
    end)
    p.noteBy = S.Text(p.detail, 11, S.colors.muted); p.noteBy:SetPoint('TOPLEFT', 14, -224); p.noteBy:SetWidth(276); p.noteBy:SetWordWrap(true)
    p.refresh = function() renderPlayers(p) end
    return p
end

local function renderChat(p)
    local chat = db().chat
    local first = math.max(1, #chat - C_ROWS + 1 - chatOffset)
    p.empty:SetShown(#chat == 0)
    for i, line in ipairs(p.lines) do
        local m = chat[first + i - 1]
        if m and first + i - 1 <= #chat then
            line:SetText(string.format('|c%s%s|r |c%s%s|r %s', S.hex.muted, date('%d/%m %H:%M', m.at), S.hex.gold, Core.Safe(m.name), Core.Safe(m.text)))
        else line:SetText('') end
    end
end
local function createChat(parent)
    local p = CreateFrame('Frame', nil, parent); p:SetAllPoints(parent)
    local box = S.Box(p, S.colors.panel, S.colors.line); box:SetPoint('TOPLEFT', 0, 0); box:SetSize(W, C_ROWS * 21 + 14)
    box:EnableMouseWheel(true)
    box:SetScript('OnMouseWheel', function(_, delta)
        chatOffset = math.max(0, math.min(chatOffset + delta * 3, math.max(0, #db().chat - C_ROWS)))
        Core.Run('officiers', renderChat, p)
    end)
    p.lines = {}
    for i = 1, C_ROWS do
        local line = S.Text(box, 12); line:SetPoint('TOPLEFT', 12, -7 - (i - 1) * 21); line:SetWidth(W - 24)
        p.lines[i] = line
    end
    p.empty = S.Text(box, 12, S.colors.muted, 'CENTER'); p.empty:SetPoint('TOPLEFT', 60, -150); p.empty:SetWidth(W - 120); p.empty:SetWordWrap(true)
    p.empty:SetText('Le canal officier du jeu, gardé ici. Les messages reçus depuis ta connexion s\'y ajoutent.')
    p.input = S.Input(p, W - 110, 'Message aux officiers'); p.input:SetPoint('TOPLEFT', 0, -(C_ROWS * 21 + 22))
    if p.input.SetMaxBytes then p.input:SetMaxBytes(255) end
    local function submit()
        Core.Run('officiers', function()
            if O.SendChat(p.input:GetText()) then p.input:SetText(''); chatOffset = 0 end
        end)
    end
    p.input:SetScript('OnEnterPressed', submit)
    p.send = S.Button(p, 'Envoyer', 100, 26, 'primary'); p.send:SetPoint('TOPLEFT', W - 100, -(C_ROWS * 21 + 22))
    p.send:SetScript('OnClick', submit)
    p.refresh = function() renderChat(p) end
    return p
end

local function createPack(parent)
    local p = CreateFrame('Frame', nil, parent); p:SetAllPoints(parent)
    local title = S.Text(p, 16); title:SetPoint('TOPLEFT', 0, -2); title:SetText('Pack complet des addons')
    local text = S.Text(p, 12, S.colors.muted); text:SetPoint('TOPLEFT', 0, -30); text:SetWidth(W); text:SetWordWrap(true)
    text:SetText('Le pack du site, pour les membres, contient Craft, Fiches, BiS, Donjons & Quêtes, SOS et Camp. Le pack complet ajoute Événements, Raid, Layers, Ride the Bus et Recrutement. Il se télécharge sur le site, connecté avec un compte officier. Copie le lien ci-dessous (Ctrl+C) dans ton navigateur.')
    p.link = S.Input(p, W, ''); p.link:SetPoint('TOPLEFT', 0, -84); p.link:SetText(O.PACK_URL)
    p.link:SetScript('OnTextChanged', function(self) if self:GetText() ~= O.PACK_URL then self:SetText(O.PACK_URL) end end)
    p.link:SetScript('OnEditFocusGained', function(self) if self.HighlightText then self:HighlightText() end end)
    p.refresh = function() end
    return p
end

local builders = { joueurs = createPlayers, chat = createChat, pack = createPack }
--- Affiche un onglet de la section.
function O.Select(id)
    active = id
    if root then
        if not pages[id] then
            local body = root.body
            if id == 'annonces' then pages[id] = A.CreatePanel(body)
            elseif id == 'versions' then pages[id] = V.CreatePanel(body)
            else pages[id] = builders[id](body) end
        end
        for key, page in pairs(pages) do page:SetShown(key == id) end
        for key, b in pairs(tabButtons) do b:SetActive(key == id) end
    end
    O.Refresh()
end
function O.Refresh()
    if not (root and root:IsVisible()) then return end
    if active == 'annonces' then A.Refresh()
    elseif active == 'versions' then V.Refresh()
    elseif pages[active] then pages[active].refresh() end
end
--- /quinte versions : l'onglet pour un officier ; les autres ont le résumé dans le chat.
function O.Open(id)
    if not A.IsOfficer() then return false end
    Core.UI.Open(A.MODULE)
    O.Select(id)
    return true
end
local function createRoot(parent)
    root = CreateFrame('Frame', nil, parent); root:SetAllPoints(parent)
    local x = 0
    for _, tab in ipairs(TABS) do
        local width = tab.id == 'pack' and 112 or 90
        local b = S.Button(root, tab.label, width, 26, 'ghost'); b:SetPoint('TOPLEFT', x, 0)
        b:SetScript('OnClick', function() Core.Run('officiers', O.Select, tab.id) end)
        tabButtons[tab.id] = b
        x = x + width + 6
    end
    root.body = CreateFrame('Frame', nil, root)
    root.body:SetPoint('TOPLEFT', 0, -BODY_TOP); root.body:SetSize(W, H - BODY_TOP)
    root:SetScript('OnShow', function() Core.Run('officiers', O.Select, active) end)
    root:Hide()
    return root
end
Core:RegisterModule({
    id = A.MODULE, title = 'Officiers', order = 890, icon = 'Interface\\Icons\\INV_Misc_Horn_01', version = Core.version, width = W, height = H,
    visible = function() return A.IsOfficer() end,
    create = function(parent) return createRoot(parent) end,
    refresh = function() O.Select(active) end,
    summary = function() return A.Summary() end,
})

local function scanLoop()
    Core.Run('officiers', O.Scan)
    C_Timer.After(SCAN, scanLoop)
end
local events = CreateFrame('Frame')
Core.Call(events.RegisterEvent, events, 'PLAYER_LOGIN')
Core.Call(events.RegisterEvent, events, 'CHAT_MSG_OFFICER')
events:SetScript('OnEvent', function(_, event, text, sender)
    if event == 'CHAT_MSG_OFFICER' then return Core.Run('officiers', O.OnOfficerChat, text, sender) end
    if O.started then return end
    O.started = true
    if C_Timer and C_Timer.After then
        C_Timer.After(FIRST_SCAN, function()
            Core.Run('officiers', O.AskNotes)
            scanLoop()
        end)
    end
end)
