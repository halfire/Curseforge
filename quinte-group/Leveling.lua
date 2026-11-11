local _, Q = ...
--[[
  Leveling.lua : Compagnon de Leveling et détection des quêtes partagées.
  Scanne automatiquement le journal de quêtes et détecte les membres de la guilde
  qui ont les mêmes quêtes en cours pour monter un groupe instantané.
]]

-- Liste inchangée : pas de nouvel envoi avant KEEPALIVE (les autres gardent nos quêtes 30 min, voir SHARED_TTL).
-- Liste modifiée (quête prise, rendue, abandonnée) : envoyée dans les secondes qui suivent, au plus une fois par
-- MIN_GAP. Avant (0.3.0), chaque QUEST_LOG_UPDATE (à chaque monstre tué pour une quête) repoussait l'envoi d'une
-- minute : en pleine session de quêtes, une nouvelle quête ne partait jamais, et les autres ne la voyaient qu'après
-- un redémarrage du jeu (premier envoi de la session).
local KEEPALIVE = 900
local MIN_GAP = 10
local SETTLE = 2 -- journal relu 2 s après une rafale d'événements de quêtes
local SHARED_TTL = 1800
local MEMBER_QUESTS_TTL = 86400 -- quêtes d'un membre oubliées au bout d'un jour (inutiles après 30 min)
local lastSent, lastSignature = 0, nil
local replied = {}
local checkPending = false

local function who(name)
    if Quintessence.CanonicalKey then return Quintessence.CanonicalKey(name) end
    return (tostring(name or ''):gsub('%s', ''):lower())
end

-- Les zones repliées du journal cachent leurs quêtes à la liste : on rajoute les quêtes de donjon que le jeu dit en cours.
local dungeonQuestIDs
local function addHiddenDungeonQuests(quests)
    if not (Q.DUNGEON_QUESTS and Q.IsOnQuest) then return quests end
    if not dungeonQuestIDs then
        dungeonQuestIDs = {}
        for _, list in pairs(Q.DUNGEON_QUESTS) do
            for _, q in ipairs(list) do
                dungeonQuestIDs[q[1]] = q
                local info = Q.REFERENCE_QUEST_INFO and Q.REFERENCE_QUEST_INFO[q[1]]
                for _, step in ipairs(info and info.prereqs or {}) do
                    dungeonQuestIDs[step.id] = dungeonQuestIDs[step.id] or { step.id, 0, step.title }
                end
            end
        end
    end
    local seen = {}
    for _, q in ipairs(quests) do seen[q.id] = true end
    for id, q in pairs(dungeonQuestIDs) do
        if not seen[id] and Q.IsOnQuest(id) then
            local fn = C_QuestLog and C_QuestLog.GetTitleForQuestID
            local ok, title = false, nil
            if fn then ok, title = pcall(fn, id) end
            quests[#quests + 1] = { id = id, title = (ok and not (issecretvalue and issecretvalue(title))
                and type(title) == 'string' and title ~= '') and title or q[3], level = q[2] }
        end
    end
    table.sort(quests, function(a, b) return a.id < b.id end)
    return quests
end

-- Récupération du journal de quêtes du joueur
function Q.GetMyQuests()
    local quests = {}

    -- API moderne Retail / Midnight (C_QuestLog)
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local num = C_QuestLog.GetNumQuestLogEntries() or 0
        for i = 1, num do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and not info.isHidden and info.title and info.title ~= '' then
                quests[#quests + 1] = {
                    id = info.questID or i,
                    title = info.title,
                    level = info.level or 0
                }
            end
        end
        return addHiddenDungeonQuests(quests)
    end

    -- API Classic / Vanilla (GetNumQuestLogEntries / GetQuestLogTitle)
    if GetNumQuestLogEntries and GetQuestLogTitle then
        local num = GetNumQuestLogEntries() or 0
        for i = 1, num do
            local title, level, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
            if title and not isHeader and title ~= '' then
                quests[#quests + 1] = {
                    id = questID or i,
                    title = title,
                    level = level or 0
                }
            end
        end
    end

    return addHiddenDungeonQuests(quests)
end

local function questSignature(quests, level)
    local parts = { tostring(level) }
    for i, q in ipairs(quests) do parts[i + 1] = tostring(q.id) .. '=' .. tostring(q.title) end
    return table.concat(parts, '\n')
end

-- Diffusion de ses quêtes actives à la guilde (target : réponse privée à un membre qui arrive)
function Q.BroadcastMyQuests(force, target)
    local now = Q.Now()
    local quests = Q.GetMyQuests()
    local myLevel = UnitLevel and UnitLevel('player') or 60
    local _, class = UnitClass and UnitClass('player')

    if not target then
        local signature = questSignature(quests, myLevel)
        if not force and signature == lastSignature and (now - lastSent) < KEEPALIVE then return end
        -- Journal vide jamais envoyé : rien à dire (mais une liste qui se vide part, pour effacer nos quêtes chez les autres)
        if #quests == 0 and lastSignature == nil then return end
        if not force and (now - lastSent) < MIN_GAP then
            -- Changement juste après un envoi : il part dès la fin du délai, pas 15 min plus tard
            if not checkPending and C_Timer and C_Timer.After then
                checkPending = true
                C_Timer.After(MIN_GAP - (now - lastSent) + 1, function()
                    checkPending = false
                    Q.Run('sync_quetes', Q.BroadcastMyQuests, false)
                end)
            end
            return
        end
        lastSignature, lastSent = signature, now
    end

    if Q.comm and Q.comm.Send then
        Q.comm:Send({
            t = 'quest_sync',
            quests = quests,
            level = myLevel,
            class = class or 'WARRIOR',
            r = target and 1 or nil -- réponse : le destinataire ne répond pas à son tour
        }, target)
    end
end

-- Réception de la liste de quêtes d'un membre
function Q.OnReceiveQuestSync(data, sender)
    if not sender or not data or type(data.quests) ~= 'table' then return end
    if not QuinteGroupDB.memberQuests then QuinteGroupDB.memberQuests = {} end

    -- Membre qui arrive (ou revient après 30 min) : on lui répond en privé avec nos quêtes, puisqu'on ne
    -- rediffuse plus une liste inchangée qu'au bout de 15 min
    local now = Q.Now()
    local key = who(sender)
    local previous = QuinteGroupDB.memberQuests[key]
    if not data.r and (not previous or now - (previous.updated or 0) >= SHARED_TTL)
        and (now - (replied[key] or 0)) >= 300 and C_Timer and C_Timer.After then
        replied[key] = now
        C_Timer.After(1 + math.random() * 4, function()
            Q.Run('sync_quetes', Q.BroadcastMyQuests, true, sender)
        end)
    end

    QuinteGroupDB.memberQuests[key] = {
        name = Quintessence.DisplayName and Quintessence.DisplayName(sender) or sender,
        class = data.class or 'WARRIOR',
        level = data.level or 60,
        quests = data.quests,
        updated = Q.Now()
    }

    if Q.UI and Q.UI.RefreshLeveling then Q.UI.RefreshLeveling() end
    if Q.UI and Q.UI.RefreshDungeons then Q.UI.RefreshDungeons() end
end

-- Trouver les quêtes en commun entre le joueur et ses compagnons de guilde (myQuests : journal déjà lu, facultatif)
-- Index de nos quêtes par identifiant et par titre : chaque quête d'un membre est examinée une seule fois, au lieu
-- de comparer (en minuscules) toutes ses quêtes à chacune des nôtres.
local function addIndex(index, key, i)
    local list = index[key]
    if not list then list = {}; index[key] = list end
    list[#list + 1] = i
end

local function addMatches(indices, seen, matches, memberName, info)
    if not indices then return seen end
    for _, i in ipairs(indices) do
        if not (seen and seen[i]) then
            seen = seen or {}
            seen[i] = true
            local list = matches[i]
            list[#list + 1] = {
                name = memberName,
                class = info.class,
                level = info.level
            }
        end
    end
    return seen
end

function Q.FindSharedQuests(myQuests)
    myQuests = myQuests or Q.GetMyQuests()
    local myKey = who(Q.PlayerName and Q.PlayerName() or '')
    local results = {}

    if not QuinteGroupDB.memberQuests then return results end
    local now = Q.Now()
    local isOnline = Quintessence.IsOnline

    local byId, byTitle, matches = {}, {}, {}
    for i, mq in ipairs(myQuests) do
        if mq.id then addIndex(byId, mq.id, i) end
        addIndex(byTitle, mq.title:lower(), i)
        matches[i] = {}
    end

    for key, info in pairs(QuinteGroupDB.memberQuests) do
        local memberName = type(info) == 'table' and info.name or key
        -- actif depuis moins de 30 min, et pas déconnecté
        if key ~= myKey and type(info) == 'table' and (now - (info.updated or 0)) < SHARED_TTL and type(info.quests) == 'table'
            and key == who(memberName) and not (isOnline and isOnline(memberName) == false) then
            local seen = nil
            for _, oq in ipairs(info.quests) do
                if type(oq) == 'table' then
                    if oq.id then seen = addMatches(byId[oq.id], seen, matches, memberName, info) end
                    if type(oq.title) == 'string' then seen = addMatches(byTitle[oq.title:lower()], seen, matches, memberName, info) end
                end
            end
        end
    end

    for i, mq in ipairs(myQuests) do
        local matchingMembers = matches[i]
        if #matchingMembers > 0 then
            results[#results + 1] = {
                id = mq.id,
                title = mq.title,
                level = mq.level,
                members = matchingMembers
            }
        end
    end

    table.sort(results, function(a, b) return #a.members > #b.members end)
    return results
end

-- Oubli des listes de quêtes périmées (les SavedVariables gardaient pour toujours celles de chaque membre vu)
function Q.PruneMemberQuests()
    local list = QuinteGroupDB and QuinteGroupDB.memberQuests
    if type(list) ~= 'table' then return end
    local now = Q.Now()
    for name, info in pairs(list) do
        if type(info) ~= 'table' or now - (tonumber(info.updated) or 0) > MEMBER_QUESTS_TTL then list[name] = nil end
    end
end

-- Membre déconnecté : ses quêtes ne sont plus proposées
function Q.ForgetMemberQuests(name)
    local list = QuinteGroupDB and QuinteGroupDB.memberQuests
    local key = who(name)
    if type(list) == 'table' and list[key] then
        list[key] = nil
        replied[key] = nil
        if Q.UI and Q.UI.RefreshLeveling then Q.UI.RefreshLeveling() end
        if Q.UI and Q.UI.RefreshDungeons then Q.UI.RefreshDungeons() end
    end
end

-- Journal relu peu après une rafale d'événements (QUEST_LOG_UPDATE arrive à chaque progression d'objectif)
local settlePending = false
function Q.QuestLogChanged()
    if settlePending then return end
    if not (C_Timer and C_Timer.After) then return Q.BroadcastMyQuests(false) end
    settlePending = true
    C_Timer.After(SETTLE, function()
        settlePending = false
        Q.Run('sync_quetes', Q.BroadcastMyQuests, false)
        if Q.UI and Q.UI.RefreshDungeons then Q.Run('sync_quetes', Q.UI.RefreshDungeons) end
    end)
end

function Q.InitLeveling()
    Q.PruneMemberQuests()
    -- Anciennes clés (0.3.0 : expéditeur brut, « Prénom Nom » ou « Prénom Nom-Royaume ») : remplacées à la réception
    for key, info in pairs(QuinteGroupDB.memberQuests or {}) do
        if type(info) ~= 'table' or key ~= who(info.name or key) then QuinteGroupDB.memberQuests[key] = nil end
    end
    if Quintessence.OnPresence then
        Quintessence:OnPresence(function(name, online)
            if not online then Q.ForgetMemberQuests(name) end
        end)
    end
    local frame = CreateFrame('Frame')
    local events = { 'QUEST_LOG_UPDATE', 'QUEST_ACCEPTED', 'QUEST_TURNED_IN', 'QUEST_REMOVED', 'QUEST_DATA_LOAD_RESULT', 'PLAYER_ENTERING_WORLD', 'PLAYER_LEVEL_UP' }
    for _, ev in ipairs(events) do Q.Call(frame.RegisterEvent, frame, ev) end
    frame:SetScript('OnEvent', function()
        Q.Run('sync_quetes', Q.QuestLogChanged)
    end)
    -- Rappel : liste inchangée renvoyée toutes les 15 min (les autres la gardent 30 min)
    if C_Timer and C_Timer.After then
        local function keepalive()
            Q.Run('sync_quetes', Q.BroadcastMyQuests, false)
            C_Timer.After(300, keepalive)
        end
        C_Timer.After(300, keepalive)
    end
end
