local addonName, Core = ...
--[[
  Quintessence : conteneur des addons de la guilde. Il embarque les bibliothèques, gère seul la synchro de guilde
  (un seul canal d'addon, une seule file d'envoi bridée) et affiche une fenêtre à onglets. Les modules
  (quinte-craft, quinte-caract, quinte-raid, quinte-ride…) s'y enregistrent comme fonctionnalités :

    Quintessence:RegisterModule({ id = 'craft', title = 'Craft', order = 20, version = '0.5.0',
        width = 1078, height = 658, create = function(parent) return frame end, refresh = function() end,
        summary = function() return 'texte court pour l'accueil' end })
    local sync = Quintessence:RegisterSync('craft', QuinteCraftDB, adapter)      -- enregistrements partagés
    local comm = Quintessence:RegisterChannel('ride', function(data, sender, channel) end) -- messages temps réel

  Règle Retail 12+ : aucune écriture dans une table, une fonction ou un cadre de Blizzard.
]]
Quintessence = Core -- seule globale publique de la suite (nom propre, jamais une globale de Blizzard)
Core.name, Core.version = addonName or 'Quintessence', '1.39.0'
Core.modules, Core.syncModules, Core.channels, Core.debug = {}, {}, {}, { errors = {}, slow = {} }

function Core.Call(fn, ...)
    if type(fn) ~= 'function' then return false end
    return pcall(fn, ...)
end
function Core.Error(context, reason)
    local entry = context .. ': ' .. tostring(reason)
    local list = Core.debug.errors
    list[#list + 1] = entry
    if #list > 20 then table.remove(list, 1) end
    if type(QuintessenceDB) == 'table' then
        QuintessenceDB.lastErrors = QuintessenceDB.lastErrors or {}
        local saved = QuintessenceDB.lastErrors
        saved[#saved + 1] = date and (date('%H:%M:%S') .. ' ' .. entry) or entry
        while #saved > 20 do table.remove(saved, 1) end
    end
end
local clock = debugprofilestop
function Core.Run(context, fn, ...)
    local started = clock and clock()
    local ok, result = Core.Call(fn, ...)
    if not ok then Core.Error(context, result) end
    if started then
        local elapsed = clock() - started
        if elapsed > 50 then Core.debug.slow[context] = math.max(Core.debug.slow[context] or 0, math.floor(elapsed)) end
    end
    return ok, result
end
function Core.Now() return (time or GetServerTime)() end
-- Noms : tout passe par LibQuinteSync, qui connaît les noms de WoW Forever (« Prénom Nom », sans royaume, uniques dans
-- la région ; UnitName y renvoie le nom de famille en 2e valeur ; chuchotement refusé avec un royaume).
local Names = LibStub('LibQuinteSync-1.0')
function Core.Realm() return Names.Realm() end
--- Nom complet du joueur (« Prénom Nom » sur Forever, « Nom » ailleurs).
function Core.PlayerName() return Names.PlayerName() or UnitName('player') end
--- Clé de son personnage dans les données des modules : « Nom-Royaume » (Forever : « Prénom Nom-Royaume »).
function Core.Key() return Core.PlayerName() .. '-' .. Core.Realm() end
Core.PlayerKey = Core.Key
--- Nom complet d'une unité (groupe, raid, cible).
function Core.UnitFullName(unit) return Names.UnitFullName(unit) end
--- WoW Forever (noms « Prénom Nom » uniques dans la région, royaumes cachés) ?
function Core.IsRegional() return Names.Regional() end
--- Deux noms désignent-ils le même personnage (royaume et majuscules mis à part selon le client) ?
function Core.SameName(a, b) return Names.CanonicalKey(a) == Names.CanonicalKey(b) end
--- Nom à afficher (sans royaume sur Forever).
function Core.DisplayName(name) return Names.DisplayName(name) end
--- Clé de comparaison d'un nom (minuscules, sans espaces, royaume réglé selon le client) : à utiliser comme clé de
--- table pour tout ce qui vient du réseau. L'expéditeur d'un message n'a pas toujours la même forme que le nom écrit
--- par le joueur lui-même (« Prénom Nom » ou « Prénom Nom-Royaume » selon le canal) : une alerte rangée sous l'un
--- n'était jamais retrouvée avec l'autre (« Lever l'alerte » sans effet chez les autres).
function Core.CanonicalKey(name) return Names.CanonicalKey(name) end

-- ---------------------------------------------------------------------------------------------------------------------
-- Guilde : les addons ne servent qu'aux membres de Quintessence
-- ---------------------------------------------------------------------------------------------------------------------
Core.GUILD = 'Quintessence'
local function guildKey(name) return (name:gsub('^%s+', ''):gsub('%s+$', ''):lower()) end
--- 'ok' (membre de Quintessence), 'pending' (guilde pas encore donnée par le jeu), 'none' (sans guilde) ou 'other'
--- (autre guilde, nom en 2e valeur). Sans l'API (simulateur), rien à vérifier : 'ok'.
function Core.GuildStatus()
    if type(GetGuildInfo) ~= 'function' then return 'ok' end
    local ok, name = pcall(GetGuildInfo, 'player')
    if ok and type(name) == 'string' and name ~= '' and not (type(issecretvalue) == 'function' and issecretvalue(name)) then
        if guildKey(name) == guildKey(Core.GUILD) then return 'ok', name end
        return 'other', name
    end
    -- Le jeu ne donne la guilde que quelques secondes après la connexion : « sans guilde » seulement ensuite
    if not Core.guildSettled or (IsInGuild and IsInGuild()) then return 'pending' end
    return 'none'
end
--- Raison du blocage ('none' ou 'other', puis le nom de l'autre guilde), nil pour un membre (ou guilde pas encore lue).
--- Édition réduite : .toc avec « ## X-Quinte-Edition: curseforge » ou « site » (ajouté par scripts/build_suite.py).
--- Les membres n'y ont que Craft, Fiches, BiS, Donjons & Quêtes, SOS et Camp ; nil pour le pack complet des officiers.
function Core.Edition()
    local fn = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not fn then return nil end
    local ok, value = pcall(fn, 'Quintessence', 'X-Quinte-Edition')
    return ok and (value == 'curseforge' or value == 'site') and value or nil
end
function Core.IsCurseForge() return Core.Edition() == 'curseforge' end

function Core.GuildBlocked()
    local status, name = Core.GuildStatus()
    if status == 'none' or status == 'other' then return status, name end
    return nil
end
local guildWarned, guildWasOk
function Core.GuildChanged()
    local blocked, name = Core.GuildBlocked()
    if blocked and not guildWarned then
        guildWarned = true
        Core.Print('|cffff8040Addons réservés aux membres de la guilde ' .. Core.GUILD .. '|r'
            .. (blocked == 'other' and (' (tu es dans « ' .. Core.Safe(name) .. ' »)') or ' (tu n’es dans aucune guilde)')
            .. ' : synchro et outils de guilde désactivés.')
    elseif not blocked then guildWarned = nil end
    -- Guilde qui devient « Quintessence » (lue, ou rejointe) : la synchro reprend ce qu'elle retenait
    local ok = Core.GuildStatus() == 'ok'
    if ok and guildWasOk == false and Core.sync then Core.Call(Core.sync.Resume, Core.sync) end
    guildWasOk = ok
    if Core.UI and Core.UI.OnGuildChanged then Core.Run('guilde', Core.UI.OnGuildChanged) end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Présence : qui est connecté (SOS, layers et quêtes des déconnectés retirés tout de suite)
-- ---------------------------------------------------------------------------------------------------------------------
local presence = { on = {}, off = {}, handlers = {} }
local function moment() return GetTime and GetTime() or Core.Now() end
--- Le module est prévenu quand un membre se connecte ou se déconnecte : handler(nom, enLigne).
function Core:OnPresence(handler)
    if type(handler) == 'function' then presence.handlers[#presence.handlers + 1] = handler end
end
local function setPresence(name, online, quiet)
    if type(name) ~= 'string' or name == '' then return end
    local key = Names.CanonicalKey(name)
    if online then presence.on[key] = moment() else presence.off[key] = moment() end
    if quiet then return end
    for _, handler in ipairs(presence.handlers) do Core.Run('présence', handler, name, online) end
end
--- Un message reçu de ce membre prouve qu'il est connecté (plus récent que la liste de guilde).
function Core.Seen(name) setPresence(name, true, true) end
--- true si connecté, false si déconnecté, nil si on ne sait pas (liste de guilde pas encore lue, membre inconnu).
function Core.IsOnline(name)
    if type(name) ~= 'string' or name == '' then return nil end
    local key = Names.CanonicalKey(name)
    if key == Names.CanonicalKey(Core.PlayerName() or '') then return true end
    local on, off = presence.on[key], presence.off[key]
    if off and off >= (on or 0) then return false end
    local sync = Core.sync
    local rosterAt = sync and sync.rosterKnown and sync.rosterAt
    if on and (not rosterAt or on >= rosterAt) then return true end
    if not rosterAt then return nil end
    local member = sync.roster and sync.roster[key]
    if not member then return nil end
    if off and off >= rosterAt then return false end
    return member.online and true or false
end
-- « Prénom Nom s'est déconnecté(e). » / « [Prénom Nom] s'est connecté(e). » : modèles tirés des textes du jeu
local systemPattern = Names.SystemPattern
local offlinePattern, onlinePattern
function Core.OnSystemMessage(text)
    if type(text) ~= 'string' or (type(issecretvalue) == 'function' and issecretvalue(text)) then return end
    offlinePattern = offlinePattern or systemPattern(ERR_FRIEND_OFFLINE_S or '%s has gone offline.')
    onlinePattern = onlinePattern or systemPattern(ERR_FRIEND_ONLINE_SS or '|Hplayer:%s|h[%s]|h has come online.')
    local who = offlinePattern and text:match(offlinePattern)
    if who then return setPresence(who, false) end
    who = onlinePattern and text:match(onlinePattern)
    if who then setPresence(who, true) end
end
function Core.Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
--- Nom à utiliser pour chuchoter ou inviter (Forever refuse « Prénom Nom-Royaume »).
function Core.WhisperTarget(name) return Names.WhisperTarget(name) end
--- Ouvre la saisie d'un chuchotement vers ce joueur (nom avec espace compris).
function Core.Whisper(name)
    local target = Core.WhisperTarget(name)
    if type(target) ~= 'string' or target == '' then return end
    local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if tell then Core.Call(tell, target) elseif ChatFrame_OpenChat then Core.Call(ChatFrame_OpenChat, '/w ' .. target .. ' ') end
end
--- Maj+clic sur un objet de nos fenêtres : met son lien dans le chat (ouvert s'il est fermé, dans le dernier canal utilisé).
--- `item` : numéro ou lien d'objet. Renvoie vrai si le clic était un Maj+clic : l'appelant ne fait alors rien d'autre.
function Core.LinkItem(item)
    if not (IsModifiedClick and IsModifiedClick('CHATLINK')) then return false end
    local link = type(item) == 'string' and item:find('|Hitem:', 1, true) and item or nil
    local id = not link and (tonumber(item) or (type(item) == 'string' and tonumber(item:match('item:(%d+)')))) or nil
    if id then
        local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if fn then
            local ok, _, found = pcall(fn, id)
            if ok and type(found) == 'string' then link = found end
        end
    end
    if not link then
        if id and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        if id then Core.Print('Objet pas encore chargé par le jeu, refais Maj+clic dans une seconde.') end
        return true
    end
    -- Forever : ChatFrameUtil.InsertLink (ChatEdit_InsertLink n'y est pas chargé). Le drapeau évite qu'un module
    -- qui surveille les liens (liste BiS de quinte-bis) prenne ce clic pour le sien.
    Core.linkingItem = true
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    local inserted = false
    if insert then
        local ok, value = pcall(insert, link)
        inserted = ok and value and true or false
    end
    if not inserted then
        local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
        if open then pcall(open, link) end
    end
    Core.linkingItem = false
    return true
end

--- Anciennes clés possibles du joueur dans les données d'un module (avant 1.3.0, WoW Forever : « Prénom-Royaume »,
--- sans le nom de famille). Sur les autres clients, la liste est vide.
function Core.LegacyKeys()
    local first = UnitName('player')
    local out = {}
    -- (au chargement le jeu donne « Unknown » : rien à déplacer, sinon la fiche partait sous « Unknown-Royaume »)
    if type(first) ~= 'string' or first == '' or first == UNKNOWNOBJECT or first == 'Unknown' then return out end
    local key = Core.Key()
    for _, old in ipairs({ first .. '-' .. Core.Realm(), first .. '-' .. (GetRealmName():gsub('%s', '')) }) do
        if old ~= key and not out[old] then out[old] = true; out[#out + 1] = old end
    end
    return out
end
--- Déplace la fiche du joueur rangée sous une ancienne clé vers la bonne clé ; rename(fiche) corrige ses champs.
function Core.MigrateSelf(records, rename)
    if type(records) ~= 'table' then return false end
    local key, moved = Core.Key(), false
    for _, old in ipairs(Core.LegacyKeys()) do
        local record = records[old]
        if type(record) == 'table' and record.source == 'self' then
            if not records[key] then records[key] = record; if rename then rename(record) end end
            records[old] = nil; moved = true
        end
    end
    return moved
end
--- Invite ce joueur dans le groupe.
function Core.Invite(name)
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if invite then Core.Call(invite, Core.WhisperTarget(name)) end
end
function Core.Safe(text) return (tostring(text or ''):gsub('|', '||')) end
function Core.Print(text)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage('|cff70d5bfQuintessence|r ' .. text)
    end
end

--- Déclare un module (fonctionnalité). Peut être appelé avant ou après l'initialisation du conteneur.
function Core:RegisterModule(def)
    assert(type(def) == 'table' and type(def.id) == 'string' and def.id:match('^[%w_]+$'), 'module invalide')
    def.title = def.title or def.id
    def.order = def.order or 100
    self.modules[def.id] = def
    if self.UI and self.UI.OnModulesChanged then self.UI.OnModulesChanged() end
    return def
end

function Core:ModuleList()
    local list = {}
    -- def.visible : onglet réservé à certains joueurs (ex. Annonces, pour les officiers)
    for _, m in pairs(self.modules) do if not m.visible or m.visible() then list[#list + 1] = m end end
    table.sort(list, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.id < b.id end)
    return list
end

-- Initialisation à ADDON_LOADED du conteneur (avant celle des modules, qui en dépendent)
function Core.Init()
    if Core.ready then return end
    if type(QuintessenceDB) ~= 'table' then QuintessenceDB = {} end
    QuintessenceDB.format = QuintessenceDB.format or 1
    if QuintessenceDB.syncEnabled == nil then QuintessenceDB.syncEnabled = true end
    -- Interface choisie (moderne par défaut), fixée pour la session avant la création de toute fenêtre
    QuintessenceDB.theme = Core.Style.ThemeName(QuintessenceDB.theme) or 'modern'
    Core.Style.Apply(QuintessenceDB.theme)
    Core.ready = true
    Core.Run('synchro', Core.SyncInit)
    if Core.Versions then Core.Run('versions', Core.Versions.Init) end
end

-- Liste de guilde redemandée chaque minute (le jeu la bride à 10 s) : l'état « en ligne » des membres reste frais
local function rosterTicker()
    if IsInGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then Core.Call(C_GuildInfo.GuildRoster) end
    if C_Timer and C_Timer.After then C_Timer.After(60, rosterTicker) end
end

local frame = CreateFrame('Frame')
for _, event in ipairs({ 'ADDON_LOADED', 'PLAYER_LOGIN', 'ADDON_ACTION_FORBIDDEN', 'ADDON_ACTION_BLOCKED', 'PLAYER_GUILD_UPDATE', 'CHAT_MSG_SYSTEM' }) do
    Core.Call(frame.RegisterEvent, frame, event)
end
frame:SetScript('OnEvent', function(_, event, arg, arg2)
    Core.Run(event, function()
        if event == 'ADDON_ACTION_FORBIDDEN' or event == 'ADDON_ACTION_BLOCKED' then
            local who = tostring(arg or '?')
            local fn = tostring(arg2 or '?')
            if who:lower():find('quinte', 1, true) then
                Core.Error(event, who .. ' -> ' .. fn)
                Core.Print('|cffff5555[' .. event .. ']|r ' .. Core.Safe(who) .. ' a tenté d’appeler ' .. Core.Safe(fn) .. ' (/quinte erreurs pour le détail).')
            end
            return
        end
        if event == 'ADDON_LOADED' then
            if arg == Core.name then Core.Init() end
            return
        end
        if event == 'CHAT_MSG_SYSTEM' then return Core.OnSystemMessage(arg) end
        if event == 'PLAYER_GUILD_UPDATE' then
            if Core.GuildStatus() ~= 'pending' then Core.guildSettled = true end
            return Core.GuildChanged()
        end
        Core.Init()
        Core.StartSync()
        Core.MinimapCreate()
        if not Core.loginDone then
            Core.loginDone = true
            -- Guilde considérée comme connue 15 s après la connexion (ou dès PLAYER_GUILD_UPDATE)
            if C_Timer and C_Timer.After then
                C_Timer.After(15, function() Core.guildSettled = true; Core.Run('guilde', Core.GuildChanged) end)
                C_Timer.After(20, rosterTicker)
            end
            if Core.GuildStatus() == 'ok' then Core.guildSettled = true end
        end
    end)
end)

SLASH_QUINTESSENCE1, SLASH_QUINTESSENCE2 = '/quinte', '/quintessence'
SlashCmdList.QUINTESSENCE = function(message)
    Core.Run('commande', function()
        local command, value = (message or ''):match('^%s*(%S*)%s*(.-)%s*$')
        if command == '' then Core.UI.Toggle()
        elseif command == 'sync' then
            if value == 'off' then Core:SetSyncEnabled(false)
            elseif value == 'on' then Core:SetSyncEnabled(true)
            elseif value == 'now' then if Core.sync then Core.sync:Announce() end
            else return Core.Print('/quinte sync on|off|now · /quinte test') end
            Core.Print('Synchro : ' .. (QuintessenceDB.syncEnabled and 'activée' or 'désactivée'))
        elseif command == 'debug' then Core.Debug()
        elseif command == 'erreurs' or command == 'errors' or command == 'error' then Core.ShowErrors(value)
        elseif command == 'test' then Core.Test()
        elseif command == 'versions' or command == 'version' then
            if Core.Versions then Core.Versions.Check(); if Core.Officers then Core.Officers.Open('versions') end end
        elseif command == 'chemin' then Core.Navigation.Command(value)
        elseif command == 'minimap' then Core.MinimapToggle()
        elseif command == 'taille' or command == 'size' or command == 'scale' then
            local pct = tonumber((value:gsub('%%', '')))
            if value == '+' then Core.UI.StepScale(1) elseif value == '-' then Core.UI.StepScale(-1)
            elseif pct then Core.UI.SetScalePercent(pct)
            elseif value ~= '' then return Core.Print('/quinte taille 50 à 200 (100 = taille normale) · /quinte taille + ou -') end
            Core.Print('Taille de la fenêtre : ' .. Core.UI.ScalePercent() .. ' % · /quinte taille 50 à 200, + ou -')
        elseif command == 'interface' or command == 'theme' then
            if value == '' then
                return Core.Print('Interface : ' .. Core.Style.THEMES[Core.Style.theme].label .. ' · /quinte interface moderne|classique')
            end
            Core.SetTheme(value)
        elseif Core.modules[command] then Core.UI.Open(command)
        else
            Core.Print('/quinte : ouvrir la fenêtre · /quinte <module> · /quinte versions · /quinte sync on|off|now · /quinte test · /quinte debug · /quinte minimap · /quinte taille 50-200 · /quinte interface moderne|classique')
        end
    end)
end

--- Change d'interface ('modern' ou 'classic', mots français acceptés) : enregistrée puis interface rechargée, car
--- toutes les fenêtres (conteneur et modules) sont construites avec le thème du chargement.
function Core.SetTheme(name)
    local theme = Core.Style.ThemeName(name)
    if not theme then return Core.Print('Interface inconnue : /quinte interface moderne|classique') end
    QuintessenceDB.theme = theme
    if theme == Core.Style.theme then return Core.Print('Interface ' .. Core.Style.THEMES[theme].label .. ' déjà active.') end
    Core.Print('Interface ' .. Core.Style.THEMES[theme].label .. ' choisie : rechargement de l’interface…')
    local reload = (C_UI and C_UI.Reload) or ReloadUI
    if not (reload and Core.Call(reload)) then Core.Print('Tape /reload pour l’appliquer.') end
end

function Core.Debug()
    local names = {}
    for _, m in ipairs(Core:ModuleList()) do names[#names + 1] = m.id .. ' ' .. tostring(m.version or '?') end
    Core.Print('Conteneur ' .. Core.version .. ' (dossier ' .. Core.Safe(Core.name) .. ') · modules : ' .. (#names > 0 and table.concat(names, ', ') or 'aucun')
        .. ' · interface ' .. tostring(Core.Style and Core.Style.theme))
    local state = Core.sync and Core.sync:Status()
    if state then
        Core.Print('Synchro : ' .. (state.enabled and 'on' or 'off') .. ', file=' .. state.queued .. ', réassemblages=' .. state.buffers
            .. ', report=' .. state.deferred .. ', refus=' .. state.rejected)
        Core.Print('Envois ' .. state.sent .. ' (échecs ' .. state.failed .. ', nouveaux essais ' .. state.retries .. ', dernier code '
            .. Core.ResultName(state.lastResult) .. ') · reçus '
            .. state.received .. (state.lastFrom and (' (dernier : ' .. Core.Safe(state.lastFrom) .. ')') or '') .. ' · en attente ' .. state.waiting
            .. ' · inconnus ' .. state.strangers)
        Core.Print('Moi : ' .. Core.Safe(tostring(state.player)) .. (state.regional and ' (noms régionaux, WoW Forever)' or '')
            .. ' · demandes en cours ' .. state.pending .. ' · en attente ' .. state.wants)
        local gstatus, gname = Core.GuildStatus()
        Core.Print('Guilde du personnage : ' .. Core.Safe(gname or '?') .. ' (' .. ({ ok = 'membre de ' .. Core.GUILD, pending = 'en lecture', none = 'aucune', other = 'autre guilde : addons coupés' })[gstatus] .. ')')
        Core.Print('Guilde : ' .. state.roster .. ' membres lus' .. (state.rosterKnown and '' or ' (liste pas encore reçue)')
            .. ' · préfixe ' .. tostring(state.prefix) .. ' · ChatThrottleLib ' .. tostring(state.ctl) .. ' · moi ' .. Core.Safe(Core.Key()))
        local restricted = C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
        if restricted then
            local ok, value = pcall(restricted)
            -- Indication seulement : sur WoW Forever elle répond « oui » alors que les messages partent
            Core.Print('Indicateur de restriction du jeu : ' .. (ok and tostring(value) or 'erreur') .. ' (ignoré, seul le code d’envoi compte)')
        end
    end
    if Core.Versions then Core.Print('Versions : ' .. Core.Versions.Summary() .. ' · /quinte versions pour vérifier la guilde') end
    for context, ms in pairs(Core.debug.slow) do Core.Print('Traitement lent : ' .. Core.Safe(context) .. ' ' .. ms .. ' ms') end
    for _, errorText in ipairs(Core.debug.errors) do Core.Print('|cffff6060Erreur session :|r ' .. Core.Safe(errorText)) end
    if QuintessenceDB and type(QuintessenceDB.lastErrors) == 'table' and #QuintessenceDB.lastErrors > 0 and #Core.debug.errors == 0 then
        Core.Print('Dernières erreurs enregistrées (' .. #QuintessenceDB.lastErrors .. ') : tape /quinte erreurs pour les afficher.')
    end
end

function Core.ShowErrors(arg)
    if arg == 'clear' or arg == 'vider' then
        Core.debug.errors = {}
        if QuintessenceDB then QuintessenceDB.lastErrors = {} end
        return Core.Print('Journal des erreurs Quintessence vidé.')
    end
    local session = Core.debug.errors or {}
    local saved = (QuintessenceDB and QuintessenceDB.lastErrors) or {}
    Core.Print('=== Diagnostic des erreurs Quintessence ===')
    Core.Print('Astuce WoW : tape |cffffd100/console scriptErrors 1|r pour afficher les erreurs Lua détaillées de Blizzard.')
    if #session == 0 and #saved == 0 then
        Core.Print('|cff5cd1a8Aucune erreur ni action bloquée enregistrée.|r')
        return
    end
    for i, err in ipairs(saved) do
        Core.Print(string.format('|cffff8040[%d]|r %s', i, Core.Safe(err)))
    end
    Core.Print('Tape |cffffd100/quinte erreurs vider|r pour effacer cet historique.')
end

-- /quinte test : ping de guilde, chaque membre qui a le conteneur répond en privé avec ses versions.
-- m : texte lisible (lu par les versions ≤ 1.7.1) ; t : table { id = version } pour l'outil Versions (1.8.0+)
function Core.Info()
    local modules = {}
    for _, m in ipairs(Core:ModuleList()) do
        if m.id ~= 'versions' and m.id ~= 'annonces' then modules[#modules + 1] = m.id .. ' ' .. tostring(m.version or '?') end
    end
    return { v = Core.version, m = table.concat(modules, ', '):sub(1, 200), t = Core.Versions and Core.Versions.Mine().m or nil }
end
function Core.Pong(sender, info)
    -- Versions enregistrées pour l'onglet Versions ; pendant /quinte versions, pas une ligne par réponse
    if Core.Versions and Core.Versions.OnPong(sender, info) then return end
    Core.test = Core.test or {}
    Core.test[#Core.test + 1] = sender
    info = type(info) == 'table' and info or {}
    local mine = Core.version
    local version = type(info.v) == 'string' and info.v:sub(1, 20) or '?'
    Core.Print('Réponse de ' .. Core.Safe(sender) .. ' : conteneur ' .. Core.Safe(version)
        .. (type(info.m) == 'string' and (' · ' .. Core.Safe(info.m:sub(1, 200))) or '')
        .. (version ~= mine and ' |cffff8040(version différente de la tienne : ' .. mine .. ')|r' or ''))
end
function Core.Test()
    if not Core.sync then return Core.Print('Synchro non initialisée.') end
    if not IsInGuild() then return Core.Print('Tu n’es pas dans une guilde : la synchro ne fonctionne qu’entre membres.') end
    local blocked, guildName = Core.GuildBlocked()
    if blocked == 'other' then return Core.Print('Tu es dans « ' .. Core.Safe(guildName) .. ' » : la synchro est réservée à la guilde ' .. Core.GUILD .. '.') end
    local state = Core.sync:Status()
    if not state.enabled then return Core.Print('Synchro coupée : /quinte sync on') end
    if state.deferred ~= 'non' then Core.Print('Synchro en pause : ' .. state.deferred .. ' (le test partira dès que possible).') end
    Core.test = {}
    Core.sync:Ping(Core.Info())
    Core.Print('Test envoyé à la guilde, réponses dans les 15 secondes…')
    C_Timer.After(15, function()
        local n = #(Core.test or {})
        if n == 0 then
            Core.Print('Aucune réponse. Vérifie que l’autre joueur a le même conteneur Quintessence ' .. Core.version
                .. ' activé (pas « obsolète » dans la liste des addons) et la synchro active, puis /quinte debug.')
        else
            Core.Print(n .. ' membre(s) ont répondu : la synchro passe. Échange des données dans la minute.')
        end
    end)
end

-- Nom du code de retour de C_ChatInfo.SendAddonMessage (Enum.SendAddonMessageResult), pour les messages au joueur
function Core.ResultName(code)
    if code == nil then return 'aucun' end
    for name, value in pairs(Enum and Enum.SendAddonMessageResult or {}) do
        if value == code then return tostring(code) .. ' ' .. name end
    end
    return tostring(code)
end
-- Premier envoi refusé par le jeu dans la session : un seul message dans le chat, avec le code
function Core.Problem(code, channel)
    Core.Print('Le jeu a refusé un message de synchro (' .. Core.ResultName(code) .. ', canal ' .. tostring(channel or '?')
        .. '). La synchro continue d’essayer ; /quinte debug pour le détail.')
end
