local addonName, Q = ...
-- Nom réel du dossier installé (ex. « Quinte-Caract » cloné depuis GitHub) : ADDON_LOADED le renvoie tel quel.
Q.name, Q.version = addonName or 'quinte-caract', '0.15.0'
Q.api, Q.errors, Q.pendingItems = {}, {}, {}
Q.scans, Q.changes, Q.slow = 0, 0, {}

function Q.Secret(value)
    if type(issecretvalue) ~= 'function' then return false end
    local ok, secret = pcall(issecretvalue, value)
    return not ok or secret
end
function Q.String(value, maximum)
    if Q.Secret(value) or type(value) ~= 'string' or #value == 0 or #value > (maximum or 100) then return nil end
    if value:find('[%z\1-\31]') then return nil end
    return value
end
function Q.Number(value, minimum, maximum, integer)
    if Q.Secret(value) or type(value) ~= 'number' then return nil end
    if value ~= value or value < (minimum or 0) or value > (maximum or 1e12) then return nil end
    if integer and value % 1 ~= 0 then return nil end
    return value
end
function Q.Error(context, reason)
    Q.errors[#Q.errors + 1] = context .. ': ' .. tostring(reason)
    if #Q.errors > 10 then table.remove(Q.errors, 1) end
end
-- Chronomètre : tout traitement de plus de 50 ms est noté (visible dans /qcaract debug).
function Q.Run(context, fn, ...)
    local started = debugprofilestop and debugprofilestop()
    local ok, result = pcall(fn, ...)
    if not ok then Q.Error(context, result) end
    if started then
        local elapsed = debugprofilestop() - started
        if elapsed > 50 then Q.slow[context] = math.max(Q.slow[context] or 0, math.floor(elapsed)) end
    end
    return ok, result
end
function Q.Read(label, fn, ...)
    if type(fn) ~= 'function' then Q.api[label] = {state = 'absente'}; return nil end
    local function pack(...) return {n = select('#', ...), ...} end
    local results = pack(pcall(fn, ...))
    local ok, values = results[1], {}
    for i = 2, math.min(results.n, 13) do values[i - 1] = results[i] end
    if not ok then
        Q.api[label] = {state = 'erreur'}; Q.Error(label, values[1]); return nil
    end
    for i = 1, 12 do
        if Q.Secret(values[i]) then Q.api[label] = {state = 'restreinte'}; return nil end
    end
    Q.api[label] = {state = 'ok', values = values}
    return unpack(values, 1, 12)
end
function Q.Now() return (time or GetServerTime)() end
-- Clé du personnage : celle du conteneur (nom complet « Prénom Nom » sur WoW Forever)
function Q.Key() return Quintessence.Key() end
function Q.Safe(value) return (tostring(value or '?'):gsub('|', '||')) end
function Q.Print(value)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage('|cff70d5bfQuintessence|r ' .. value)
    end
end
function Q.Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not Q.Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
function Q.Changed(localChange)
    if localChange then
        Q.changes = Q.changes + 1
        if Q.sync then Q.sync:NotifyLocal() end
    end
    if Q.UI then Q.UI.OnDataChanged() end
end
-- Caractéristiques et PvP bougent avec chaque buff, forme, proc ou victoire honorable : chaque fin de combat diffusait
-- une nouvelle fiche à toute la guilde (delta GUILD, puis une demande et une réponse par membre). Un changement de ces
-- seuls champs est gardé localement et diffusé au plus une fois par VOLATILE_DELAY ; le reste (stuff, talents, niveau,
-- métiers, accès…) part tout de suite. À la déconnexion, la date est mise à jour pour que le site importe la fiche.
local VOLATILE, VOLATILE_DELAY = {stats = true, pvp = true, gameStats = true}, 900
local function sameExceptVolatile(a, b)
    for k, v in pairs(a) do if not VOLATILE[k] and not Q.Equal(v, b[k]) then return false end end
    for k in pairs(b) do if not VOLATILE[k] and a[k] == nil then return false end end
    return true
end
function Q.Capture(final)
    if not Q.ready or Q.disabled then return end
    local record = Q.CollectCharacter()
    if not record then return end
    if Q.IdentityMetadata then Q.IdentityMetadata(record) end
    local old = QuinteCaractDB.characters[Q.Key()]
    local previous = {}
    if old and old.source == 'self' then
        for k, v in pairs(old) do
            if k ~= 'updated' and k ~= 'source' and k ~= 'syncedFrom' and k ~= 'syncedAt' then previous[k] = v end
        end
    end
    Q.scans = Q.scans + 1
    local now = Q.Now()
    local fresh = old and old.source == 'self' and (old.updated or 0) > now - VOLATILE_DELAY
    if old and old.source == 'self' and Q.Equal(record, previous) then
        -- Changement de caractéristiques gardé en attente : diffusé une fois le délai écoulé (ou à la déconnexion)
        if not Q.volatilePending or (fresh and not final) then return end
    elseif fresh and not final and sameExceptVolatile(record, previous) then
        record.source, record.updated = 'self', old.updated
        QuinteCaractDB.characters[Q.Key()] = record
        if not Q.volatilePending and C_Timer and C_Timer.After then
            C_Timer.After(old.updated + VOLATILE_DELAY - now + 1, function() Q.Schedule() end)
        end
        Q.volatilePending = true
        Q.Changed(false)
        return
    end
    Q.volatilePending = nil
    record.source = 'self'
    record.updated = math.max(now, (old and old.updated or 0) + 1)
    QuinteCaractDB.characters[Q.Key()] = record
    Q.Changed(true)
end
function Q.Schedule()
    if Q.scheduled or not Q.ready or Q.disabled then return end
    Q.scheduled = true
    if C_Timer and C_Timer.After then
        -- Regroupe les rafales d'événements : au plus un relevé toutes les 5 secondes
        local since = GetTime and Q.lastCapture and (GetTime() - Q.lastCapture) or 5
        C_Timer.After(since < 5 and (5 - since) or 1, function()
            Q.scheduled = false
            Q.lastCapture = GetTime and GetTime() or nil
            Q.Run('instantané différé', Q.Capture)
        end)
    else Q.scheduled = false; Q.Run('instantané', Q.Capture) end
end
local frame = CreateFrame('Frame')
local events = {'ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_EQUIPMENT_CHANGED', 'PLAYER_LEVEL_UP',
    'PLAYER_GUILD_UPDATE', 'CHARACTER_POINTS_CHANGED', 'SKILL_LINES_CHANGED', 'PLAYER_LOGOUT',
    'GET_ITEM_INFO_RECEIVED', 'PLAYER_TALENT_UPDATE', 'ACTIVE_TALENT_GROUP_CHANGED',
    'PLAYER_SPECIALIZATION_CHANGED', 'TRAIT_CONFIG_UPDATED', 'TRAIT_CONFIG_LIST_UPDATED',
    'HONOR_LEVEL_UPDATE', 'PVP_RANK_UPDATE', 'PLAYER_PVP_KILLS_CHANGED', 'PLAYER_REGEN_ENABLED', 'UPDATE_INSTANCE_INFO'}
for _, event in ipairs(events) do pcall(frame.RegisterEvent, frame, event) end
-- Initialisation unique : à ADDON_LOADED de cet addon, ou en secours à PLAYER_LOGIN si l'événement a été manqué.
function Q.Init()
    if Q.ready or Q.disabled then return end
    if type(QuinteCaractDB) ~= 'table' then QuinteCaractDB = {format = 1, characters = {}} end
    if QuinteCaractDB.format == nil and QuinteCaractDB.characters == nil then QuinteCaractDB.format, QuinteCaractDB.characters = 1, {} end
    if QuinteCaractDB.format ~= 1 or type(QuinteCaractDB.characters) ~= 'table' then
        Q.disabled = true; Q.Print('Format inconnu : collecte suspendue pour préserver la sauvegarde.'); return
    end
    -- WoW Forever : fiche enregistrée avant 1.3.0 sous « Prénom-Royaume » → « Prénom Nom-Royaume »
    -- Sortie de WoW Forever : fiches de la bêta effacées une fois (le perso connecté est relevé de nouveau)
    if Q.ResetBeforeLaunch then Q.ResetBeforeLaunch(QuinteCaractDB) end
    Quintessence.MigrateSelf(QuinteCaractDB.characters, function(c) c.name = Quintessence.PlayerName() end)
    Q.ready = true
    Q.Run('synchro', Q.SyncInit)
    if Q.IdentityInit then Q.Run('principaux et rerolls', Q.IdentityInit) end
    if Q.InitStatisticsPrivacy then Q.Run('confidentialité des statistiques', Q.InitStatisticsPrivacy) end
end
frame:SetScript('OnEvent', function(_, event, arg)
    Q.Run(event, function()
        if event == 'ADDON_LOADED' then
            if arg == Q.name then Q.Init() end
            return
        end
        if event == 'PLAYER_LOGIN' then Q.Init() end
        if not Q.ready or Q.disabled then return
        elseif event == 'PLAYER_LOGIN' then
            Q.Schedule(); if Q.sync then Q.sync:Start() end
            -- Verrous de raid : le jeu les donne après une demande (réponse UPDATE_INSTANCE_INFO)
            if type(RequestRaidInfo) == 'function' then pcall(RequestRaidInfo) end
            if C_Timer and C_Timer.After then C_Timer.After(3, function() Q.Schedule() end) end
        elseif event == 'PLAYER_LOGOUT' then Q.Capture(true)
        elseif event == 'GET_ITEM_INFO_RECEIVED' then
            if Q.pendingItems[arg] then Q.Schedule() end
        elseif event == 'PLAYER_GUILD_UPDATE' or event == 'PLAYER_SPECIALIZATION_CHANGED' then
            if not arg or arg == 'player' then Q.Schedule() end
        else Q.Schedule() end
    end)
end)
SLASH_QUINTECARACT1 = '/qcaract'
SlashCmdList.QUINTECARACT = function(message)
    Q.Run('commande', function()
        if Q.disabled then return Q.Print('Collecte suspendue : le fichier QuinteCaractDB a un format inconnu.') end
        if not Q.ready then Q.Init() end
        if not Q.ready then return Q.Print('Addon pas encore initialisé : reconnecte-toi ou fais /reload.') end
        Q.Command(message or '')
    end)
end
