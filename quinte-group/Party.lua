local _, Q = ...
--[[
  Party.lua : ce qui sert au groupe pendant la phase de pex.
  - Quêtes à prendre avant un donjon (DungeonQuests.lua) : pour chaque quête, si je l'ai, l'ai faite ou dois la prendre,
    quels inscrits ou membres du groupe l'ont (journaux partagés par Leveling.lua), partage au groupe et demande en un clic.
  - Annonce de la progression des quêtes au groupe (réglage, désactivé au départ) : les messages du jeu
    « Sanglier tué : 5/10 » (UI_INFO_MESSAGE) redits dans le chat du groupe, hors raid et hors restriction du chat.
  - XP du groupe : chaque membre envoie son niveau et son XP aux autres membres du groupe (canal qgroup, message `xp`,
    au plus toutes les 15 s), affichés dans l'onglet Quêtes partagées.
]]
local XP_GAP, XP_TTL = 15, 120
local GROUP_LOG_TTL = 1800 -- journal d'un membre du groupe cru 30 min (comme les quêtes communes)

local function isSecret(v) return type(issecretvalue) == 'function' and issecretvalue(v) end
local function settings()
    QuinteGroupDB.settings = type(QuinteGroupDB.settings) == 'table' and QuinteGroupDB.settings or {}
    return QuinteGroupDB.settings
end

-- ---------------------------------------------------------------------------------------------- Quêtes de donjon
-- Titre anglais de secours d'une quête de la liste des donjons (quête précédente notée dans DungeonQuests.lua)
local knownTitles
local function knownTitle(id)
    if not knownTitles then
        knownTitles = {}
        for _, list in pairs(Q.DUNGEON_QUESTS or {}) do
            for _, q in ipairs(list) do knownTitles[q[1]] = q[3] end
        end
    end
    return knownTitles[id]
end

local function questTitle(id, fallback)
    local fn = C_QuestLog and C_QuestLog.GetTitleForQuestID
    if fn then
        local ok, title = pcall(fn, id)
        if ok and not isSecret(title) and type(title) == 'string' and title ~= '' then return title end
        if C_QuestLog.RequestLoadQuestByID then pcall(C_QuestLog.RequestLoadQuestByID, id) end
    end
    return fallback
end
local function done(id)
    local fn = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
    if not fn then return false end
    local ok, value = pcall(fn, id)
    return ok and not isSecret(value) and value == true
end

--- Vrai si la quête est dans mon journal, même sous une zone repliée (la liste du journal ne montre alors pas ses quêtes).
function Q.IsOnQuest(id)
    local fn = C_QuestLog and C_QuestLog.IsOnQuest
    if fn then
        local ok, value = pcall(fn, id)
        if ok and value == true then return true end
    end
    return false
end
local function logIndex(id)
    local fn = (C_QuestLog and C_QuestLog.GetLogIndexForQuestID) or GetQuestLogIndexByID
    if not fn then return nil end
    local ok, index = pcall(fn, id)
    return ok and type(index) == 'number' and index > 0 and index or nil
end
local function complete(id)
    local fn = C_QuestLog and C_QuestLog.IsComplete
    if not fn then return false end
    local ok, value = pcall(fn, id)
    return ok and not isSecret(value) and value == true
end
local function sameTitle(title) return type(title) == 'string' and not isSecret(title) and title:lower() or nil end

--- Vrai si le jeu permet de partager cette quête de mon journal.
function Q.CanShareQuest(id)
    if C_QuestLog and C_QuestLog.IsPushableQuest then
        local ok, value = pcall(C_QuestLog.IsPushableQuest, id)
        return ok and not isSecret(value) and value == true
    end
    local index = logIndex(id)
    if not (index and SelectQuestLogEntry and GetQuestLogPushable) then return false end
    local previous = GetQuestLogSelection and GetQuestLogSelection()
    SelectQuestLogEntry(index)
    local ok, value = pcall(GetQuestLogPushable)
    if previous then SelectQuestLogEntry(previous) end
    return ok and value and true or false
end

--- Partage une quête avec le groupe (un clic = un partage, le jeu demande l'accord à chacun). Renvoie vrai si c'est parti.
function Q.ShareQuest(id, title)
    if not (IsInGroup and IsInGroup()) then Q.Print('Rejoins un groupe pour partager une quête.'); return false end
    if not QuestLogPushQuest then Q.Print('Le partage de quête n\'existe pas sur ce client.'); return false end
    if not Q.CanShareQuest(id) then Q.Print('Cette quête ne peut pas être partagée.'); return false end
    local index = logIndex(id)
    if not index then Q.Print('Déplie la zone de cette quête dans ton journal (L), puis réessaie.'); return false end
    -- Selon le client, la quête partagée est l'index donné ou la quête sélectionnée dans le journal.
    local get, set = C_QuestLog and C_QuestLog.GetSelectedQuest, C_QuestLog and C_QuestLog.SetSelectedQuest
    local previous = get and set and get()
    local ok
    if set then
        set(id)
        ok = pcall(QuestLogPushQuest, index)
        if previous then set(previous) end
    else
        local before = GetQuestLogSelection and GetQuestLogSelection()
        if SelectQuestLogEntry then SelectQuestLogEntry(index) end
        ok = pcall(QuestLogPushQuest, index)
        if before and SelectQuestLogEntry then SelectQuestLogEntry(before) end
    end
    if ok then Q.Print('Quête proposée au groupe : ' .. tostring(title or id) .. '.') end
    return ok and true or false
end

--- Lien cliquable donné par le jeu, sinon le titre entre crochets (un lien fabriqué à la main peut être refusé par le chat).
local function questLink(id, title)
    if GetQuestLink then
        local ok, link = pcall(GetQuestLink, id)
        if ok and type(link) == 'string' and not isSecret(link) and link:find('|Hquest:', 1, true) then return link end
    end
    return '[' .. tostring(title or id) .. ']'
end

--- Message au groupe (au clic) pour demander une quête à ceux qui l'ont.
function Q.AskQuest(title, names, id)
    if not (IsInGroup and IsInGroup()) or type(title) ~= 'string' then return false end
    local who = type(names) == 'table' and #names > 0 and table.concat(names, ', ') or 'quelqu\'un'
    return Q.GroupChat(who .. ', tu peux me partager la quête ' .. questLink(id, title) .. ' ?')
end

--- Dit au groupe les quêtes du donjon qui me manquent (un clic, au plus 2 messages entiers, jamais un lien coupé).
local MISSING_GAP, MISSING_MESSAGES, MESSAGE_MAX = 15, 2, 250
local lastMissing = -MISSING_GAP
function Q.AnnounceMissingQuests(code)
    if not (IsInGroup and IsInGroup()) then Q.Print('Rejoins un groupe pour annoncer tes quêtes.'); return false end
    if Q.Now() - lastMissing < MISSING_GAP then return false end
    local links = {}
    for _, q in ipairs(Q.DungeonQuests(code)) do
        if q.state == 'todo' then links[#links + 1] = questLink(q.id, q.title) end
    end
    if #links == 0 then Q.Print('Il ne te manque aucune quête pour ce donjon.'); return false end
    local info = Q.GetDungeonInfo and Q.GetDungeonInfo(code)
    local messages = {}
    local line = 'Il me manque pour ' .. tostring(info and info.name or code) .. ' :'
    local used = 0
    for i, link in ipairs(links) do
        -- Dans le dernier message, on garde la place de « (+N) » s'il reste d'autres quêtes.
        local last = #messages + 1 >= MISSING_MESSAGES
        local limit = (last and i < #links) and MESSAGE_MAX - 6 or MESSAGE_MAX
        if #line + 1 + #link > limit then
            if last then break end
            messages[#messages + 1] = line
            line = 'Il me manque aussi :'
        end
        line = line .. ' ' .. link
        used = used + 1
    end
    if used < #links then
        line = line .. string.format(' (+%d)', #links - used)
    end
    messages[#messages + 1] = line
    local sent = false
    for _, text in ipairs(messages) do
        if Q.GroupChat(text) then sent = true end
    end
    if sent then lastMissing = Q.Now() end
    return sent
end

-- Masques de classes du jeu (DungeonQuestInfo.lua)
local CLASS_MASK = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128,
    WARLOCK = 256, MONK = 512, DRUID = 1024 }
local CLASS_NAME = { { 1, 'Guerrier' }, { 2, 'Paladin' }, { 4, 'Chasseur' }, { 8, 'Voleur' }, { 16, 'Prêtre' }, { 64, 'Chaman' },
    { 128, 'Mage' }, { 256, 'Démoniste' }, { 1024, 'Druide' } }
local function hasClass(mask, class)
    local bit = CLASS_MASK[class]
    if not (mask and bit) then return true end -- pas de condition, ou classe inconnue : on ne cache rien
    return math.floor(mask / bit) % 2 == 1
end
--- Classes d'une quête réservée, en toutes lettres : « Guerrier, Paladin ».
local function classNames(mask)
    local names = {}
    for _, c in ipairs(CLASS_NAME) do if math.floor(mask / c[1]) % 2 == 1 then names[#names + 1] = c[2] end end
    return table.concat(names, ', ')
end
local function myClass()
    if not UnitClass then return nil end
    local _, class = UnitClass('player')
    return not isSecret(class) and class or nil
end

--- Quêtes du donjon : { id, logId, level, title, state = 'log' | 'done' | 'todo', complete, shareable,
--- holders = { inscrits ou membres du groupe qui l'ont }, groupHas, groupMissing = { membres du groupe qui l'ont, qui ne l'ont pas },
--- known (conditions connues), classes (réservée à), minLevel, prev, prevTitle, prevState ('log' | 'done' | 'todo'), start,
--- tag ('suite' | 'prérequis' | 'suite hors du donjon' | nil), chain = { { id, title, state, here, step } } (Wowhead Forever) }.
--- Une quête réservée à une autre classe n'est pas listée, sauf si elle est dans mon journal.
--- state vaut aussi 'locked' (quête précédente pas faite) ou 'low' (niveau trop bas) : le jeu ne la proposerait pas.
--- Une quête est « en cours » si son numéro est dans le journal, même zone repliée, ou si une quête du journal porte le même titre.
function Q.DungeonQuests(code)
    local list = Q.DUNGEON_QUESTS and Q.DUNGEON_QUESTS[Q.NormalizeDungeonCode and Q.NormalizeDungeonCode(code) or code]
    if type(list) ~= 'table' then return {} end
    local mine, mineTitles = {}, {}
    for _, q in ipairs(Q.GetMyQuests and Q.GetMyQuests() or {}) do
        if q.id then
            mine[q.id] = true
            local t = sameTitle(q.title)
            if t then mineTitles[t] = q.id end
        end
    end
    -- Journaux des inscrits sur ce donjon et des membres de mon groupe
    local signed = {}
    local needs = Q.GetDungeonNeeds and Q.GetDungeonNeeds(code)
    for _, m in ipairs(needs and needs.members or {}) do if not m.isPlayer then signed[Quintessence.CanonicalKey(m.name)] = m.name end end
    local logs, now = {}, Q.Now()
    local class = myClass()
    local level = UnitLevel and UnitLevel('player')
    if isSecret(level) or type(level) ~= 'number' then level = nil end
    for key, info in pairs(QuinteGroupDB.memberQuests or {}) do
        if type(info) == 'table' and type(info.quests) == 'table' then
            local inGroup = Q.InMyGroup(info.name) and now - (tonumber(info.updated) or 0) <= GROUP_LOG_TTL
            local name = signed[key] or (info.name and signed[Quintessence.CanonicalKey(info.name)]) or (inGroup and info.name)
            if name then
                local ids, titles = {}, {}
                for _, q in ipairs(info.quests) do
                    if type(q) == 'table' and q.id then
                        ids[q.id] = true
                        local t = sameTitle(q.title)
                        if t then titles[t] = true end
                    end
                end
                logs[#logs + 1] = { name = name, ids = ids, titles = titles, inGroup = inGroup, class = info.class }
            end
        end
    end
    table.sort(logs, function(a, b) return tostring(a.name) < tostring(b.name) end)
    local inList = {}
    for _, q in ipairs(list) do inList[q[1]] = true end
    local out = {}
    for _, q in ipairs(list) do
        local id = q[1]
        local title = questTitle(id, q[3])
        local key = sameTitle(title)
        local logId = (mine[id] or Q.IsOnQuest(id)) and id or (key and mineTitles[key]) or nil
        local info = Q.DUNGEON_QUEST_INFO and Q.DUNGEON_QUEST_INFO[id]
        local reference = Q.REFERENCE_QUEST_INFO and Q.REFERENCE_QUEST_INFO[id]
        if reference then
            info = { class = reference.class, start = reference.start, chain = {} }
            for _, step in ipairs(reference.prereqs or {}) do
                info.chain[#info.chain + 1] = { step.id, step.title }
                if not done(step.id) then info.prev, info.prevTitle = step.id, step.title end
            end
            info.chain[#info.chain + 1] = { id, reference.title }
            -- Un prénom/titre identique dans deux étapes n'identifie pas la quête du donjon.
            for _, step in ipairs(reference.prereqs or {}) do
                if step.title == q[3] and not mine[id] and not Q.IsOnQuest(id) then logId = nil end
            end
        end
        -- Niveau requis recoupé (DungeonQuests.lua), puis Forever (lieux) ; la table d'informations ne sert plus que pour
        -- la classe et la suite (ou la quête précédente notée dans DungeonQuests.lua)
        local place = Q.DUNGEON_QUEST_PLACES and Q.DUNGEON_QUEST_PLACES[id]
        local minLevel = tonumber(q[4]) or (place and place.level) or (info and info.level)
        local prev = reference and info.prev or (info and info.prev) or tonumber(q[5])
        local classMask = (info and info.class) or tonumber(q[6])
        local holders, groupHas, groupMissing = {}, {}, {}
        for _, l in ipairs(logs) do
            local has = l.ids[id] or (key and l.titles[key])
            if has then holders[#holders + 1] = l.name end
            if l.inGroup then
                if has then groupHas[#groupHas + 1] = l.name
                elseif hasClass(classMask, l.class) then groupMissing[#groupMissing + 1] = l.name end
            end
        end
        if logId or hasClass(classMask, class) then
            local state = logId and 'log' or (done(id) and 'done' or 'todo')
            local prevState
            if prev then
                prevState = (Q.IsOnQuest(prev) and 'log') or (done(prev) and 'done') or 'todo'
                if state == 'todo' and prevState ~= 'done' then state = 'locked' end
            end
            if state == 'todo' and minLevel and level and level < minLevel then state = 'low' end
            -- Chaîne de Wowhead Forever : chaque étape (titre du jeu si connu), ce qui vient avant (prérequis) et après (suite)
            local chain, here
            if info and type(info.chain) == 'table' then
                chain = {}
                for i, step in ipairs(info.chain) do
                    local sid = step[1]
                    if sid == id then here = i end
                    local other = Q.DUNGEON_QUEST_INFO and Q.DUNGEON_QUEST_INFO[sid]
                    chain[i] = { id = sid, title = questTitle(sid, step[2]), here = sid == id,
                        inDungeon = inList[sid] and not (other and other.outside) or false,
                        outside = other and other.outside or false,
                        state = (sid == id and state) or ((Q.IsOnQuest(sid) and 'log') or (done(sid) and 'done') or 'todo') }
                end
                for i, step in ipairs(chain) do
                    step.step = here and ((i < here and 'prérequis') or (i > here and 'suite')) or nil
                end
            end
            -- Entre parenthèses : une étape qui n'est pas la quête du donjon elle-même
            local tag
            if info and info.outside and chain and here then
                local later = false
                for i, step in ipairs(chain) do
                    local other = Q.DUNGEON_QUEST_INFO[step.id]
                    if i > here and inList[step.id] and not (other and other.outside) then later = true end
                end
                -- Hors du donjon : avant une quête du donjon = prérequis ; après = suite ; début d'une chaîne qui reste dehors = rien
                tag = (later and 'prérequis') or (here > 1 and 'suite hors du donjon') or nil
            elseif info and info.outside then
                tag = 'étape hors du donjon'
            elseif prev then
                tag = 'suite'
            end
            out[#out + 1] = { id = id, logId = logId, level = q[2], title = title, state = state,
                complete = logId and complete(logId) or false,
                shareable = logId and Q.CanShareQuest(logId) or false,
                holders = holders, groupHas = groupHas, groupMissing = groupMissing,
                known = info ~= nil or q[6] ~= nil, classes = classMask and classNames(classMask) or nil,
                minLevel = minLevel, start = (place and place.start) or (info and info.start),
                prev = prev, prevState = prevState,
                prevTitle = prev and questTitle(prev, (info and info.prevTitle) or knownTitle(prev)) or nil,
                tag = tag, chain = chain, note = info and info.note, narrative = info and info.narrative }
        end
    end
    -- Ce que je peux faire d'abord : mes quêtes, puis celles à prendre, puis celles déjà faites.
    local RANK = { log = 1, todo = 2, locked = 3, low = 4, done = 5 }
    table.sort(out, function(a, b)
        if a.state ~= b.state then return RANK[a.state] < RANK[b.state] end
        if a.level ~= b.level then return a.level < b.level end
        return a.title < b.title
    end)
    return out
end

--- Liste à afficher : les étapes d'une même chaîne se suivent, dans l'ordre de la chaîne, à la place de la première
--- d'entre elles ; chaque étape est décalée d'un cran de plus (q.depth = 0, 1, 2…). Les étapes de la chaîne qui ne sont
--- pas des quêtes de ce donjon (prérequis faits dehors, étapes entre deux quêtes du donjon) sont ajoutées comme lignes
--- d'information (q.virtual = true) : tout le chemin, y compris les suites après le donjon. Ne change pas Q.DungeonQuests.
local STEP_STATE = { done = 'faite', log = 'en cours', todo = 'à faire' }
function Q.ChainOrder(quests)
    local groups, out, placed = {}, {}, {}
    local function chainKey(q)
        if not (q.chain and q.chain[1]) then return nil end
        local ids = {}
        for _, step in ipairs(q.chain) do ids[#ids + 1] = tostring(step.id) end
        return table.concat(ids, ':')
    end
    for _, q in ipairs(quests) do
        local first = chainKey(q)
        if first then
            groups[first] = groups[first] or {}
            groups[first][#groups[first] + 1] = q
        end
    end
    local function position(q)
        for i, step in ipairs(q.chain) do if step.here then return i end end
        return 0
    end
    for _, q in ipairs(quests) do
        local first = chainKey(q)
        if not first then
            q.depth = 0; out[#out + 1] = q
        elseif not placed[first] then
            placed[first] = true
            local group, byId, firstPos, lastPos = groups[first], {}, math.huge, 0
            for _, member in ipairs(group) do
                local pos = position(member)
                byId[member.id] = member
                if pos > 0 then firstPos = math.min(firstPos, pos); lastPos = math.max(lastPos, pos) end
            end
            local chain = group[1].chain
            if lastPos == 0 then
                for depth, member in ipairs(group) do member.depth = depth - 1; out[#out + 1] = member end
            else
                for i = 1, #chain do
                    local step = chain[i]
                    local member = byId[step.id]
                    if member then
                        member.depth = i - 1; member.chainIndex = i; member.chainLength = #chain
                        out[#out + 1] = member
                    else
                        -- Étape hors de ce donjon : son état, sa place, et la chaîne vue depuis elle (infobulle)
                        local view = {}
                        for k, s in ipairs(chain) do
                            view[k] = { id = s.id, title = s.title, state = s.state, inDungeon = s.inDungeon, outside = s.outside, here = k == i,
                                step = (k < i and 'prérequis') or (k > i and 'suite') or nil }
                        end
                        local elsewhere
                        for code, list in pairs(Q.DUNGEON_QUESTS or {}) do
                            for _, candidate in ipairs(list) do
                                if candidate[1] == step.id and not step.outside and Q.DUNGEON_BY_CODE[code] then
                                    local dungeon = Q.GetDungeonInfo and Q.GetDungeonInfo(code)
                                    if dungeon then elsewhere = dungeon.name; break end
                                end
                            end
                            if elsewhere then break end
                        end
                        out[#out + 1] = { virtual = true, id = step.id, title = step.title, state = step.state,
                            stateText = STEP_STATE[step.state] or 'à faire', depth = i - 1,
                            tag = (elsewhere and ('autre donjon : ' .. elsewhere))
                                or (i < firstPos and not q.narrative) and 'prérequis, hors du donjon'
                                or (i > lastPos and 'suite après le donjon') or 'étape hors du donjon',
                            chainIndex = i, chainLength = #chain, narrative = q.narrative,
                            chain = view, holders = {}, groupHas = {}, groupMissing = {}, known = true }
                    end
                end
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------------------------- Annonce au groupe
local PROGRESS = { ERR_QUEST_ADD_KILL_SII = true, ERR_QUEST_ADD_ITEM_SII = true, ERR_QUEST_ADD_FOUND_SII = true,
    ERR_QUEST_ADD_PLAYER_KILL_SII = true, ERR_QUEST_OBJECTIVE_COMPLETE_S = true }
function Q.AnnounceProgressOn() return settings().announceProgress == true end
function Q.SetAnnounceProgress(on) settings().announceProgress = on and true or false end

--- Écrit dans le chat du groupe (instance, raid ou groupe), sauf si le jeu coupe le chat.
function Q.GroupChat(message)
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if not ok or locked then return false end
    end
    local sendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not sendChat then return false end
    local channel = 'PARTY'
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then channel = 'INSTANCE_CHAT'
    elseif IsInRaid and IsInRaid() then channel = 'RAID' end
    return pcall(sendChat, message:sub(1, 250), channel)
end

--- Message du jeu (UI_INFO_MESSAGE) : redit dans le chat du groupe si c'est une progression de quête.
function Q.OnInfoMessage(messageType, message)
    if not Q.AnnounceProgressOn() or isSecret(messageType) or isSecret(message) or type(message) ~= 'string' then return false end
    local kind = GetGameMessageInfo and select(1, GetGameMessageInfo(messageType))
    if not kind or not PROGRESS[kind] then return false end
    if not (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) then return false end
    return Q.GroupChat(message)
end

-- ---------------------------------------------------------------------------------------------- XP du groupe
local partyXP, lastXP = {}, 0
Q.partyXP = partyXP
local function groupUnits()
    local units = {}
    if not (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) then return units end
    for i = 1, 4 do units[#units + 1] = 'party' .. i end
    return units
end

--- Envoie mon niveau et mon XP aux membres du groupe (au plus une fois toutes les 15 s, sauf `force`).
function Q.SendMyXP(force)
    local now = Q.Now()
    if not force and now - lastXP < XP_GAP then return false end
    if not Q.comm or not Q.comm.Send then return false end
    local level, xp, max = UnitLevel and UnitLevel('player'), UnitXP and UnitXP('player'), UnitXPMax and UnitXPMax('player')
    if isSecret(level) or isSecret(xp) or isSecret(max) or type(level) ~= 'number' then return false end
    local sent = false
    for _, unit in ipairs(groupUnits()) do
        local name = Quintessence.UnitFullName and Quintessence.UnitFullName(unit)
        if type(name) == 'string' and not isSecret(name) then
            Q.comm:Send({ t = 'xp', l = level, x = tonumber(xp) or 0, m = tonumber(max) or 0 }, Quintessence.WhisperTarget(name))
            sent = true
        end
    end
    if sent then lastXP = now end
    return sent
end

function Q.OnReceiveXP(data, sender)
    if type(data) ~= 'table' or not Q.InMyGroup(sender) then return end
    local l, x, m = tonumber(data.l), tonumber(data.x), tonumber(data.m)
    if not l or l < 1 or l > 100 or not x or x < 0 or not m or m < 0 or x > m + 1 then return end
    partyXP[Quintessence.CanonicalKey(sender)] = { name = sender, level = l, xp = x, max = m, at = Q.Now() }
    if Q.UI and Q.UI.RefreshLeveling then Q.UI.RefreshLeveling() end
end

--- Membres du groupe avec leur XP connue (moins de 2 min) : { name, level, percent }.
function Q.PartyXP()
    local out, now = {}, Q.Now()
    for key, e in pairs(partyXP) do
        if now - e.at > XP_TTL or not Q.InMyGroup(e.name) then partyXP[key] = nil
        else out[#out + 1] = { name = e.name, level = e.level, percent = e.max > 0 and math.floor(e.xp / e.max * 100) or 100 } end
    end
    table.sort(out, function(a, b) if a.level ~= b.level then return a.level > b.level end return a.percent > b.percent end)
    return out
end

function Q.InitParty()
    local f = CreateFrame('Frame')
    for _, ev in ipairs({ 'UI_INFO_MESSAGE', 'PLAYER_XP_UPDATE', 'PLAYER_LEVEL_UP', 'GROUP_ROSTER_UPDATE' }) do Q.Call(f.RegisterEvent, f, ev) end
    f:SetScript('OnEvent', function(_, event, a, b)
        if event == 'UI_INFO_MESSAGE' then Q.Run('annonce', Q.OnInfoMessage, a, b)
        else Q.Run('xp', Q.SendMyXP, event == 'PLAYER_LEVEL_UP') end
    end)
end
