local _, Core = ...
--[[
  Announce.lua : annonces automatiques en guilde, dans la section « Officiers », visible des deux rangs les plus hauts
  de la guilde (rang 0 et 1, lus dans le jeu). Guilde seulement : le recrutement reste à un clic par envoi.

  - Une annonce : { id, text, days = '1010000' (lundi à dimanche), hour, min, enabled, every }. 20 au plus, heure de
    l'ordinateur. `every` (15, 30, 60, 120 ou 240 min) : répétée à partir de hour:min jusqu'à minuit ; sinon une fois par jour.
  - Partage entre officiers sur le canal 'qann' : la liste entière et sa date, la plus récente gagne. Un message d'un
    expéditeur qui n'est pas officier est jeté, les non-officiers ignorent tout le canal.
  - Un seul envoi : les officiers en ligne sont classés par nom, chacun attend position × 8 s après l'heure ; l'écho de
    CHAT_MSG_GUILD (ou le message 'sent') annule les suivants. Fenêtre de 5 min, et seul un officier déjà connecté à
    l'heure prévue envoie : une annonce manquée n'est pas rattrapée à la connexion.
  - L'envoi sans clic n'est pas confirmé sur WoW Forever : sans écho sous 5 s, l'annonce passe « refusée », une alerte
    part dans le chat et le bouton « Envoyer maintenant » reste possible (un clic = un envoi).
  Rien de tout cela n'est lu par le site et rien ne concerne les membres.
]]
local A = {}
Core.Announce = A
local S = Core.Style

A.MODULE = 'annonces'
local MAX_ITEMS = 20
local WINDOW = 300      -- secondes après l'heure prévue pendant lesquelles l'annonce peut encore partir
local SLOT = 8          -- attente par place dans la liste des officiers en ligne
local ECHO_WAIT = 5     -- sans écho du jeu passé ce délai, l'envoi est considéré comme refusé
local TICK, IDLE_TICK = 5, 60
local ASK_DELAY = 25    -- la liste de guilde et la synchro sont prêtes
local LOCK_RETRY = 15
local MIN_GAP = 30      -- deux annonces automatiques du même client restent espacées
local REPLY_GAP = 60
local DAY_NAMES = { 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim' }
local TOP_RANK = 1      -- rangs de guilde qui ont la section : 0 (maître de guilde) et 1
local REPEATS = { { nil, 'Une fois' }, { 15, '15 min' }, { 30, '30 min' }, { 60, '1 h' }, { 120, '2 h' }, { 240, '4 h' } }
local VALID_EVERY = { [15] = true, [30] = true, [60] = true, [120] = true, [240] = true }

local plans, waiting, replied = {}, {}, {}
local lastAuto, wasOfficer, asked = 0, false, false
A.plans, A.waiting = plans, waiting

local function now() return (GetServerTime or Core.Now)() end
local function secret(v) return type(issecretvalue) == 'function' and issecretvalue(v) end
local function db()
    QuintessenceDB = QuintessenceDB or {}
    local d = QuintessenceDB.announce
    if type(d) ~= 'table' then d = {}; QuintessenceDB.announce = d end
    d.at = tonumber(d.at) or 0
    if type(d.items) ~= 'table' then d.items = {} end
    if type(d.sent) ~= 'table' then d.sent = {} end
    if type(d.last) ~= 'table' then d.last = {} end
    return d
end
A.DB = db
local function find(id)
    for i, item in ipairs(db().items) do if item.id == id then return item, i end end
end
A.Find = find

--- Texte envoyable : sans code d'échappement ni retour à la ligne, 255 octets au plus, jamais de lettre coupée en deux.
function A.Clean(text)
    local t = tostring(text or ''):gsub('[|\r\n\t]', ' '):gsub('%s%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #t > 255 then
        t = t:sub(1, 255)
        while #t > 0 do
            local byte = t:byte(#t)
            if byte < 0x80 then break end
            t = t:sub(1, #t - 1)
            if byte >= 0xC0 then break end
        end
        t = t:gsub('%s+$', '')
    end
    return t
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Rangs
-- ---------------------------------------------------------------------------------------------------------------------
local function myRank()
    if GetGuildInfo then
        local ok, _, _, rank = pcall(GetGuildInfo, 'player')
        if ok and type(rank) == 'number' and not secret(rank) then return rank end
    end
    if GetNumGuildMembers and GetGuildRosterInfo then
        local me = Core.CanonicalKey(Core.PlayerName())
        for i = 1, GetNumGuildMembers() or 0 do
            local name, _, rank = GetGuildRosterInfo(i)
            if type(name) == 'string' and not secret(name) and type(rank) == 'number' and not secret(rank)
                and Core.CanonicalKey(name) == me then return rank end
        end
    end
    return nil
end
--- Le joueur est-il dans les deux rangs les plus hauts de la guilde ?
function A.IsOfficer()
    local rank = myRank()
    return rank ~= nil and rank <= TOP_RANK
end
local function rankIsOfficer(rank) return rank <= TOP_RANK end
-- Liste de guilde : rang par nom, et officiers en ligne triés
local function roster()
    local ranks, online = {}, {}
    if not (GetNumGuildMembers and GetGuildRosterInfo) then return ranks, online end
    local me = Core.CanonicalKey(Core.PlayerName())
    local rows = {}
    for i = 1, GetNumGuildMembers() or 0 do
        local name, _, rank, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
        if type(name) == 'string' and not secret(name) and type(rank) == 'number' and not secret(rank) then
            local key = Core.CanonicalKey(name)
            ranks[key] = rank
            rows[#rows + 1] = { key = key, rank = rank, online = isOnline and not secret(isOnline) }
        end
    end
    local mine = ranks[me]
    local seenMe = false
    for _, row in ipairs(rows) do
        if row.key == me then seenMe = true; online[#online + 1] = row.key
        elseif row.online and rankIsOfficer(row.rank) then online[#online + 1] = row.key end
    end
    if not seenMe then online[#online + 1] = me end
    table.sort(online)
    return ranks, online, mine
end
local function senderIsOfficer(sender)
    local ranks = roster()
    local rank = ranks[Core.CanonicalKey(sender)]
    return rank ~= nil and rankIsOfficer(rank)
end
A.SenderIsOfficer = senderIsOfficer
--- Officiers en ligne (clés triées), le joueur compris.
function A.OnlineOfficers()
    local _, online = roster()
    return online
end
local function myPlace()
    local _, online = roster()
    local me = Core.CanonicalKey(Core.PlayerName())
    for i, key in ipairs(online) do if key == me then return i - 1 end end
    return 0
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Calendrier
-- ---------------------------------------------------------------------------------------------------------------------
-- Aujourd'hui : numéro du jour dans la semaine (lundi = 1), clé du jour, secondes depuis minuit
local function today()
    local t = date('*t', now())
    return ((t.wday + 5) % 7) + 1, string.format('%d-%d', t.year, t.yday), t.hour * 3600 + t.min * 60 + t.sec
end
-- Envoi attendu de l'annonce aujourd'hui : sa clé (jour, et numéro de répétition) et les secondes écoulées depuis son heure
local function dueSlot(item, weekday, day, seconds)
    if item.days:sub(weekday, weekday) ~= '1' then return nil end
    local delta = seconds - (item.hour * 3600 + item.min * 60)
    if delta < 0 then return nil end
    if not item.every then return day, delta end
    local period = item.every * 60
    local n = math.floor(delta / period)
    return day .. '#' .. n, delta - n * period
end
local function inWindow(item)
    local weekday, day, seconds = today()
    local key, delta = dueSlot(item, weekday, day, seconds)
    if key and delta < WINDOW then return key, delta end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Envoi
-- ---------------------------------------------------------------------------------------------------------------------
local function setLast(id, status, by)
    db().last[id] = { at = now(), by = by or Core.PlayerName(), status = status }
    if A.Refresh then A.Refresh() end
end
local function lockedByGame()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        return ok and locked == true
    end
    return false
end
local function delivered(id, sender)
    local job = waiting[id]
    waiting[id] = nil
    local item = find(id)
    local d = db()
    local day = job and job.day
    if not day and item then day = inWindow(item) end
    if day then d.sent[id] = day end
    setLast(id, 'ok', sender)
    if A.comm then A.comm:Send({ t = 'sent', id = id, day = day }) end
end
local function refused(id, why)
    waiting[id] = nil
    local item = find(id)
    if not item then return end
    setLast(id, 'refused')
    Core.Print('|cffe5545cAnnonce non envoyée|r' .. (why and (' (' .. why .. ')') or '') .. ' : « ' .. Core.Safe(item.text:sub(1, 40))
        .. '… ». Section Officiers, bouton Envoyer maintenant.')
end
local function push(id, item, day)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then refused(id, 'pas de chat'); return false end
    local job = { day = day }
    waiting[id] = job
    if not pcall(send, item.text, 'GUILD') then refused(id, 'refus du jeu'); return false end
    C_Timer.After(ECHO_WAIT, function()
        if waiting[id] == job then Core.Run('annonce', refused, id, 'pas d\'écho du jeu') end
    end)
    return true
end
--- Essai automatique, à la place de cet officier dans la file.
function A.Attempt(id, day)
    local item = find(id)
    if not item or not item.enabled or db().sent[id] == day or not A.IsOfficer() or Core.GuildStatus() ~= 'ok' then return end
    local stillDay = inWindow(item)
    if stillDay ~= day then
        if lockedByGame() then setLast(id, 'locked') end
        return
    end
    if lockedByGame() then
        -- Décalé selon la place : à la levée du verrou, les officiers ne repartent pas tous ensemble
        local plan = plans[id]
        C_Timer.After(LOCK_RETRY + (plan and plan.place or 0) * SLOT, function() Core.Run('annonce', A.Attempt, id, day) end)
        return
    end
    if now() - lastAuto < MIN_GAP then
        C_Timer.After(MIN_GAP, function() Core.Run('annonce', A.Attempt, id, day) end)
        return
    end
    lastAuto = now()
    push(id, item, day)
end
--- Bouton « Envoyer maintenant » : un clic, un envoi.
function A.SendNow(id)
    local item = find(id)
    if not item then return false, 'Annonce introuvable.' end
    if not A.IsOfficer() then return false, 'Réservé aux officiers.' end
    if Core.GuildStatus() ~= 'ok' then return false, 'Guilde pas encore connue.' end
    if lockedByGame() then return false, 'Le jeu bloque les messages pour le moment (boss ou donjon en cours).' end
    if waiting[id] then return false, 'Envoi déjà en cours.' end
    return push(id, item, nil)
end
--- Message de guilde vu par le jeu : confirme notre envoi et annule celui des autres officiers.
function A.OnGuildChat(text, sender)
    if type(text) ~= 'string' or secret(text) or not wasOfficer then return end
    local d = db()
    local who = type(sender) == 'string' and not secret(sender) and Core.DisplayName(sender) or nil
    for _, item in ipairs(d.items) do
        if item.text == A.Clean(text) then
            if waiting[item.id] then
                delivered(item.id, who)
            else
                local day = inWindow(item)
                if day and d.sent[item.id] ~= day then
                    d.sent[item.id] = day
                    setLast(item.id, 'ok', who)
                end
            end
        end
    end
end
--- Tour d'horloge : prépare les annonces de cette minute et suit le rang du joueur (la liste arrive après la connexion).
function A.Tick()
    local officer = A.IsOfficer()
    if officer ~= wasOfficer then
        wasOfficer = officer
        if Core.UI and Core.UI.OnModulesChanged then Core.UI.OnModulesChanged() end
    end
    if not officer or Core.GuildStatus() ~= 'ok' then return end
    if not asked and A.comm and now() - (A.started or 0) >= ASK_DELAY then
        asked = true
        A.comm:Send({ t = 'ask', at = db().at })
    end
    local d = db()
    local weekday, day, seconds = today()
    local place
    for _, item in ipairs(d.items) do
        local plan = plans[item.id]
        local key, delta
        if item.enabled then key, delta = dueSlot(item, weekday, day, seconds) end
        if key and delta < WINDOW and d.sent[item.id] ~= key and not (plan and plan.day == key)
            and (A.started or 0) <= now() - delta then
            place = place or myPlace()
            plans[item.id] = { day = key, place = place }
            -- En retard sur l'heure (écran de chargement…) : l'ordre des officiers reste le même
            local id, slot, wait = item.id, key, delta > TICK + 1 and place * SLOT or math.max(0, place * SLOT - delta)
            C_Timer.After(wait, function() Core.Run('annonce', A.Attempt, id, slot) end)
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Modification et partage entre officiers
-- ---------------------------------------------------------------------------------------------------------------------
local function validItem(item)
    if type(item) ~= 'table' or type(item.id) ~= 'string' or #item.id == 0 or #item.id > 24 or not item.id:match('^[%w_%-]+$') then return nil end
    if type(item.text) ~= 'string' or type(item.days) ~= 'string' or not item.days:match('^[01][01][01][01][01][01][01]$') then return nil end
    local hour, min = item.hour, item.min
    if type(hour) ~= 'number' or hour ~= math.floor(hour) or hour < 0 or hour > 23 then return nil end
    if type(min) ~= 'number' or min ~= math.floor(min) or min < 0 or min > 59 then return nil end
    local text = A.Clean(item.text)
    if text == '' then return nil end
    if item.every ~= nil and not VALID_EVERY[item.every] then return nil end
    return { id = item.id, text = text, days = item.days, hour = hour, min = min, enabled = item.enabled and true or false, every = item.every }
end
local function shareList(target)
    if not A.comm then return end
    local d, sent = db(), {}
    local _, day = today()
    for id, value in pairs(d.sent) do if value == day or value:sub(1, #day + 1) == day .. '#' then sent[id] = value end end
    A.comm:Send({ t = 'list', at = d.at, by = d.by, items = d.items, sent = sent }, target)
end
local function touch()
    local d = db()
    d.at = math.max(now(), d.at + 1)
    d.by = Core.PlayerName()
    shareList()
    if A.Refresh then A.Refresh() end
end
--- Ajoute (sans id) ou modifie une annonce. Renvoie true et son id, ou false et la raison.
function A.Save(draft)
    if not A.IsOfficer() then return false, 'Réservé aux officiers.' end
    local d = db()
    local text = A.Clean(draft.text)
    if text == '' then return false, 'Écris le texte de l\'annonce.' end
    if not tostring(draft.days or ''):find('1', 1, true) then return false, 'Choisis au moins un jour.' end
    local existing = draft.id and find(draft.id)
    if not existing and #d.items >= MAX_ITEMS then return false, MAX_ITEMS .. ' annonces au plus.' end
    local id = existing and existing.id or string.format('%x%04x', now(), math.random(0, 65535))
    -- Répétition sans heure : dès minuit
    local hour, min = draft.hour, draft.min
    if draft.every then hour, min = hour or 0, min or 0 end
    local item = validItem({ id = id, text = text, days = draft.days, hour = hour, min = min, enabled = draft.enabled ~= false, every = draft.every })
    if not item then return false, 'Heure invalide (0 à 23, minutes 0 à 59).' end
    if existing then
        local _, index = find(id)
        d.items[index] = item
    else
        d.items[#d.items + 1] = item
    end
    touch()
    return true, id
end
function A.Delete(id)
    if not A.IsOfficer() then return false end
    local _, index = find(id)
    if not index then return false end
    local d = db()
    table.remove(d.items, index)
    d.sent[id], d.last[id] = nil, nil
    touch()
    return true
end
function A.SetEnabled(id, value)
    local item = find(id)
    if not item or not A.IsOfficer() then return false end
    item.enabled = value and true or false
    touch()
    return true
end
local function mergeList(data)
    if type(data.at) ~= 'number' or data.at > now() + 86400 or type(data.items) ~= 'table' or #data.items > MAX_ITEMS then return end
    local d = db()
    if type(data.sent) == 'table' then
        for id, day in pairs(data.sent) do
            if type(id) == 'string' and type(day) == 'string' and #id <= 24 and #day <= 12 then d.sent[id] = day end
        end
    end
    local by = type(data.by) == 'string' and data.by or ''
    if data.at < d.at or (data.at == d.at and by <= tostring(d.by or '')) then return end
    local items, seen = {}, {}
    for _, raw in ipairs(data.items) do
        local item = validItem(raw)
        if not item or seen[item.id] then return end -- liste abîmée : rien n'est remplacé
        seen[item.id] = true
        items[#items + 1] = item
    end
    d.items, d.at, d.by = items, data.at, by
    if A.Refresh then A.Refresh() end
end
function A.OnMessage(data, sender)
    if type(data) ~= 'table' or type(sender) ~= 'string' or not A.IsOfficer() or Core.SameName(sender, Core.PlayerName()) then return end
    if not senderIsOfficer(sender) then return end
    if data.t == 'list' then
        mergeList(data)
    elseif data.t == 'ask' then
        local d, key = db(), Core.CanonicalKey(sender)
        if d.at > 0 and type(data.at) == 'number' and data.at <= d.at and now() - (replied[key] or 0) >= REPLY_GAP then
            replied[key] = now()
            shareList(sender)
        end
    elseif data.t == 'sent' and type(data.id) == 'string' and find(data.id) then
        if type(data.day) == 'string' and #data.day <= 12 then db().sent[data.id] = data.day end
        setLast(data.id, 'ok', Core.DisplayName(sender))
    end
end
A.comm = Core:RegisterChannel('qann', function(data, sender) Core.Run('annonces', A.OnMessage, data, sender) end)

-- ---------------------------------------------------------------------------------------------------------------------
-- Textes
-- ---------------------------------------------------------------------------------------------------------------------
function A.When(item)
    local names = {}
    for i = 1, 7 do if item.days:sub(i, i) == '1' then names[#names + 1] = DAY_NAMES[i] end end
    local at = string.format('%02d:%02d', item.hour, item.min)
    local every = item.every and (item.every < 60 and (item.every .. ' min') or ((item.every / 60) .. ' h'))
    return table.concat(names, ' ') .. ' · ' .. (every and ('toutes les ' .. every .. ' dès ' .. at) or at)
end
function A.Status(id)
    local last = db().last[id]
    if not last then return '|cff94a1b8Pas encore envoyée|r' end
    local stamp = date('%d/%m %H:%M', last.at)
    if last.status == 'ok' then return '|cff5cd1a8Envoyée|r le ' .. stamp .. ' par ' .. Core.Safe(last.by or '?') end
    if last.status == 'locked' then return '|cffe5545cBloquée par le jeu|r le ' .. stamp end
    return '|cffe5545cRefusée par le jeu|r le ' .. stamp .. ' : Envoyer maintenant la fait partir d\'un clic'
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Onglet
-- ---------------------------------------------------------------------------------------------------------------------
local ROWS = math.floor((622 - 34) / 39) -- 15 annonces (corps de la section Officiers, 1.39.0)
local AW, AL = 1078, 380 -- largeur du corps, liste à gauche
local AE = AW - AL - 12   -- 686 : éditeur à droite
local panel
local state = { offset = 0, selected = nil, days = '0000000', confirm = false, enabled = true, every = nil }

local function fill(id)
    local item = id and find(id)
    state.selected = item and id or nil
    state.confirm = false
    state.days = item and item.days or '0000000'
    state.enabled = not item or item.enabled
    state.every = item and item.every or nil
    panel.text:SetText(item and item.text or '')
    panel.hour:SetText(item and tostring(item.hour) or '')
    panel.min:SetText(item and tostring(item.min) or '')
    panel.note:SetText('')
end
local function setNote(text) panel.note:SetText(text or '') end
local function render()
    local items = db().items
    state.offset = math.max(0, math.min(state.offset, #items - ROWS))
    if state.selected and not find(state.selected) then fill(nil) end
    for i, row in ipairs(panel.rows) do
        local item = items[state.offset + i]
        row.id = item and item.id
        if item then
            row.label:SetText((item.enabled and '' or '|cff94a1b8') .. Core.Safe(item.text) .. (item.enabled and '' or '|r'))
            row.when:SetText(A.When(item) .. (item.enabled and '' or ' · en pause'))
            row:SetSelected(item.id == state.selected)
            row:Show()
        else row:Hide() end
    end
    panel.empty:SetShown(#items == 0)
    panel.scroll:SetMinMaxValues(0, math.max(0, #items - ROWS)); panel.scroll:SetValue(state.offset)
    panel.count:SetText(#items .. ' / ' .. MAX_ITEMS)
    for i, button in ipairs(panel.dayButtons) do button:SetActive(state.days:sub(i, i) == '1') end
    for i, button in ipairs(panel.repeatButtons) do button:SetActive(REPEATS[i][1] == state.every) end
    local item = state.selected and find(state.selected)
    panel.title:SetText(item and 'Modifier l\'annonce' or 'Nouvelle annonce')
    panel.toggle:SetShown(item ~= nil); panel.sendNow:SetShown(item ~= nil); panel.delete:SetShown(item ~= nil)
    panel.toggle:SetLabel(state.enabled and 'Mettre en pause' or 'Réactiver')
    panel.delete:SetLabel(state.confirm and 'Confirmer' or 'Supprimer')
    panel.status:SetText(item and A.Status(item.id) or '')
end
function A.Refresh()
    if panel and panel:IsVisible() then Core.Run('annonces', render) end
end
local function create(parent)
    panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints(parent)
    local heading = S.Heading(panel, 'Annonces en guilde'); heading:SetPoint('TOPLEFT', 0, 0)
    panel.count = S.Text(panel, 11, S.colors.muted, 'RIGHT'); panel.count:SetPoint('TOPLEFT', AW - 100, -3); panel.count:SetWidth(100)
    local box = S.Box(panel, S.colors.panel, S.colors.line); box:SetPoint('TOPLEFT', 0, -24); box:SetSize(AL, ROWS * 39 + 6)
    box:EnableMouseWheel(true)
    box:SetScript('OnMouseWheel', function(_, delta) state.offset = state.offset - delta; Core.Run('annonces', render) end)
    panel.rows = {}
    for i = 1, ROWS do
        local row = S.Row(box, AL - 12, 38); row:SetPoint('TOPLEFT', 1, -3 - (i - 1) * 39)
        row.label = S.Text(row, 12, S.colors.text); row.label:SetPoint('LEFT', 10, 7); row.label:SetWidth(AL - 30)
        row.when = S.Text(row, 10, S.colors.muted); row.when:SetPoint('LEFT', 10, -8); row.when:SetWidth(AL - 30)
        row:SetScript('OnClick', function(self)
            if self.id then fill(self.id); Core.Run('annonces', render) end
        end)
        panel.rows[i] = row
    end
    panel.scroll = S.Scrollbar(box, ROWS * 39, function(offset)
        if offset ~= state.offset then state.offset = offset; Core.Run('annonces', render) end
    end)
    panel.scroll:SetPoint('TOPLEFT', AL - 8, -3)
    panel.empty = S.Text(box, 12, S.colors.muted, 'CENTER'); panel.empty:SetPoint('TOPLEFT', 20, -250); panel.empty:SetWidth(AL - 40)
    panel.empty:SetWordWrap(true); panel.empty:SetText('Aucune annonce. Écris la première à droite.')

    local e = S.Box(panel, S.colors.panel, S.colors.line); e:SetPoint('TOPLEFT', AL + 12, -24); e:SetSize(AE, ROWS * 39 + 6)
    panel.title = S.Text(e, 14, S.colors.text); panel.title:SetPoint('TOPLEFT', 16, -12)
    panel.new = S.Button(e, 'Nouvelle', 84, 22, 'ghost'); panel.new:SetPoint('TOPRIGHT', -14, -10)
    panel.new:SetScript('OnClick', function() fill(nil); Core.Run('annonces', render) end)
    panel.text = S.Input(e, AE - 32, 'Texte envoyé en guilde (255 caractères au plus)'); panel.text:SetPoint('TOPLEFT', 16, -42)
    if panel.text.SetMaxBytes then panel.text:SetMaxBytes(255) end
    local daysLabel = S.Text(e, 11, S.colors.muted); daysLabel:SetPoint('TOPLEFT', 16, -78); daysLabel:SetText('Jours')
    panel.dayButtons = {}
    for i, name in ipairs(DAY_NAMES) do
        local b = S.Button(e, name, 58, 24, 'ghost'); b:SetPoint('TOPLEFT', 16 + (i - 1) * 63, -94)
        b:SetScript('OnClick', function()
            local on = state.days:sub(i, i) == '1' and '0' or '1'
            state.days = state.days:sub(1, i - 1) .. on .. state.days:sub(i + 1)
            Core.Run('annonces', render)
        end)
        panel.dayButtons[i] = b
    end
    local timeLabel = S.Text(e, 11, S.colors.muted); timeLabel:SetPoint('TOPLEFT', 16, -128); timeLabel:SetText('Heure, ou début de la répétition (heure de ton ordinateur)')
    panel.hour = S.Input(e, 76, 'h'); panel.hour:SetPoint('TOPLEFT', 16, -146)
    panel.min = S.Input(e, 76, 'min'); panel.min:SetPoint('TOPLEFT', 100, -146)
    panel.save = S.Button(e, 'Enregistrer', 110, 26, 'primary'); panel.save:SetPoint('TOPLEFT', 190, -146)
    panel.save:SetScript('OnClick', function()
        Core.Run('annonces', function()
            local ok, result = A.Save({ id = state.selected, text = panel.text:GetText(), days = state.days, hour = tonumber(panel.hour:GetText()),
                min = tonumber(panel.min:GetText()), enabled = state.enabled, every = state.every })
            if ok then
                fill(result)
                setNote('|cff5cd1a8Enregistrée et partagée avec les officiers connectés.|r')
            else setNote('|cffe5545c' .. result .. '|r') end
            render()
        end)
    end)
    local repeatLabel = S.Text(e, 11, S.colors.muted); repeatLabel:SetPoint('TOPLEFT', 16, -178); repeatLabel:SetText('Répéter jusqu\'à minuit')
    panel.repeatButtons = {}
    for i, choice in ipairs(REPEATS) do
        local b = S.Button(e, choice[2], 68, 24, 'ghost'); b:SetPoint('TOPLEFT', 16 + (i - 1) * 73, -194)
        b:SetScript('OnClick', function() state.every = choice[1]; Core.Run('annonces', render) end)
        panel.repeatButtons[i] = b
    end
    panel.toggle = S.Button(e, 'Mettre en pause', 130, 24, 'ghost'); panel.toggle:SetPoint('TOPLEFT', 16, -228)
    panel.toggle:SetScript('OnClick', function()
        Core.Run('annonces', function()
            state.enabled = not state.enabled
            A.SetEnabled(state.selected, state.enabled)
            render()
        end)
    end)
    panel.sendNow = S.Button(e, 'Envoyer maintenant', 150, 24, 'ghost'); panel.sendNow:SetPoint('TOPLEFT', 152, -228)
    panel.sendNow:SetScript('OnClick', function()
        Core.Run('annonces', function()
            local ok, why = A.SendNow(state.selected)
            setNote(ok and 'Envoi demandé au jeu…' or ('|cffe5545c' .. tostring(why or 'Le jeu a refusé le message.') .. '|r'))
            render()
        end)
    end)
    panel.delete = S.Button(e, 'Supprimer', 100, 24, 'danger'); panel.delete:SetPoint('TOPLEFT', 308, -228)
    panel.delete:SetScript('OnClick', function()
        Core.Run('annonces', function()
            if state.confirm then
                A.Delete(state.selected); fill(nil); setNote('Annonce supprimée.')
            else state.confirm = true end
            render()
        end)
    end)
    panel.status = S.Text(e, 11, S.colors.muted); panel.status:SetPoint('TOPLEFT', 16, -262); panel.status:SetWidth(AE - 32); panel.status:SetWordWrap(true)
    panel.note = S.Text(e, 11, S.colors.muted); panel.note:SetPoint('TOPLEFT', 16, -296); panel.note:SetWidth(AE - 32); panel.note:SetWordWrap(true)
    local help = S.Text(e, 10, S.colors.muted); help:SetPoint('BOTTOMLEFT', 16, 12); help:SetWidth(AE - 32); help:SetWordWrap(true)
    help:SetText('Part si un officier avec l\'addon est connecté à l\'heure dite. Une annonce manquée n\'est pas rattrapée.')
    panel:SetScript('OnShow', function() Core.Run('annonces', render) end)
    panel:Hide()
    return panel
end

A.CreatePanel = create -- onglet Annonces de la section Officiers (Officers.lua)
function A.Summary()
    local on, bad = 0, 0
    for _, item in ipairs(db().items) do
        if item.enabled then on = on + 1 end
        local last = db().last[item.id]
        if last and last.status ~= 'ok' then bad = bad + 1 end
    end
    return on .. ' annonce(s) active(s)' .. (bad > 0 and (' · ' .. bad .. ' refusée(s)') or '')
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Horloge et écoute du chat
-- ---------------------------------------------------------------------------------------------------------------------
local function ticker()
    Core.Run('annonces', A.Tick)
    C_Timer.After(wasOfficer and TICK or IDLE_TICK, ticker)
end
local events = CreateFrame('Frame')
Core.Call(events.RegisterEvent, events, 'PLAYER_LOGIN')
Core.Call(events.RegisterEvent, events, 'CHAT_MSG_GUILD')
events:SetScript('OnEvent', function(_, event, text, sender)
    if event == 'CHAT_MSG_GUILD' then return Core.Run('annonces', A.OnGuildChat, text, sender) end
    if A.started then return end
    A.started = now()
    if C_Timer and C_Timer.After then C_Timer.After(10, ticker) end
end)
