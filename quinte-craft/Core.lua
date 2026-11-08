local addonName, Q = ...
-- Nom réel du dossier installé (ex. « Quinte-craft » cloné depuis GitHub) : ADDON_LOADED le renvoie tel quel.
Q.name, Q.version, Q.revision = addonName or 'quinte-craft', '0.11.0', 0
Q.debug = { errors = {}, scans = 0, changes = 0, slow = {} }
function Q.Call(fn, ...)
    if type(fn) ~= 'function' then return false end
    return pcall(fn, ...)
end
function Q.Error(context, reason)
    Q.debug.errors[#Q.debug.errors+1] = context .. ': ' .. tostring(reason)
    if #Q.debug.errors > 10 then table.remove(Q.debug.errors, 1) end
end
-- Chronomètre : tout traitement de plus de 50 ms est noté (visible dans /qcraft debug).
local clock = debugprofilestop
function Q.Run(context, fn, ...)
    local started = clock and clock()
    local ok, result = Q.Call(fn, ...)
    if not ok then Q.Error(context, result) end
    if started then
        local elapsed = clock() - started
        if elapsed > 50 then
            local slow = Q.debug.slow
            slow[context] = math.max(slow[context] or 0, math.floor(elapsed))
        end
    end
    return ok, result
end
function Q.Now() return (time or GetServerTime)() end
function Q.Tick(previous) return math.max(Q.Now(), (previous or 0) + 1) end
-- Clé et nom du personnage : ceux du conteneur (nom complet « Prénom Nom » sur WoW Forever)
function Q.Key() return Quintessence.Key() end
function Q.Safe(text) return (tostring(text or ''):gsub('|', '||')) end
function Q.Print(text)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage('|cff70d5bfQuintessence|r ' .. text)
    elseif print then print(text) end
end
function Q.Changed(localChange)
    Q.revision = Q.revision + 1
    if localChange then Q.debug.changes = Q.debug.changes + 1 end
    if localChange and Q.sync then Q.sync:NotifyLocal() end
    if Q.UI then Q.UI.OnDataChanged() end
end
function Q.Identity(level)
    local key = Q.Key()
    local c = QuinteCraftDB.characters[key]
    local name, realm = Quintessence.PlayerName(), GetRealmName()
    local _, class = UnitClass('player')
    level = tonumber(level) or UnitLevel('player')
    if not c or c.source ~= 'self' then
        c = { source = 'self', professions = {} }; QuinteCraftDB.characters[key] = c
    end
    -- Date avancée au moins une fois par semaine : signe de vie pour les autres (craft retiré après un mois sans connexion)
    if c.name ~= name or c.realm ~= realm or c.class ~= class or c.level ~= level or not c.updated
        or Q.Now() - c.updated > 7 * 86400 then
        c.name, c.realm, c.class, c.level = name, realm, class, level
        c.updated = Q.Tick(c.updated); Q.Changed(true)
    end
    c.syncedFrom, c.syncedAt = nil, nil
    return c
end
local frame = CreateFrame('Frame')
local function register(event) Q.Call(frame.RegisterEvent, frame, event) end
for _, event in ipairs({ 'ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_LEVEL_UP', 'GUILD_ROSTER_UPDATE',
    'TRADE_SKILL_SHOW', 'TRADE_SKILL_LIST_UPDATE', 'TRADE_SKILL_DATA_SOURCE_CHANGED', 'TRADE_SKILL_CLOSE',
    'CRAFT_SHOW', 'CRAFT_UPDATE', 'CRAFT_CLOSE' }) do register(event) end
-- Initialisation unique : à ADDON_LOADED de cet addon, ou en secours à PLAYER_LOGIN si l'événement a été manqué.
function Q.Init()
    if Q.ready or Q.disabled then return end
    if type(QuinteCraftDB) ~= 'table' then QuinteCraftDB = { format = 1, characters = {} } end
    if QuinteCraftDB.format == nil and QuinteCraftDB.characters == nil then QuinteCraftDB.format, QuinteCraftDB.characters = 1, {} end
    if QuinteCraftDB.format ~= 1 or type(QuinteCraftDB.characters) ~= 'table' then
        Q.disabled = true; Q.Print('Format de sauvegarde inconnu : collecte suspendue pour préserver le fichier.'); return
    end
    -- Sortie de WoW Forever : craft de la bêta effacé une fois (le perso connecté est relevé de nouveau)
    if Q.ResetBeforeLaunch then Q.ResetBeforeLaunch(QuinteCraftDB) end
    -- WoW Forever : fiche enregistrée avant 1.3.0 sous « Prénom-Royaume » → « Prénom Nom-Royaume »
    Quintessence.MigrateSelf(QuinteCraftDB.characters, function(c) c.name = Quintessence.PlayerName() end)
    Q.ready = true
    Q.Run('synchro', Q.SyncInit)
    Q.Run('infobulle', Q.TooltipInit)
    Q.Run('commandes', Q.InitOrders)
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
            Q.Identity(); if Q.sync then Q.sync:Start() end
            if C_Timer and C_Timer.After then C_Timer.After(3, function() Q.Run('identité différée', Q.Identity) end) end
        elseif event == 'PLAYER_LEVEL_UP' then Q.Identity(arg)
        elseif event == 'GUILD_ROSTER_UPDATE' then return -- le roster est relu par LibQuinteSync (au plus toutes les 10 s)
        elseif event == 'TRADE_SKILL_CLOSE' or event == 'CRAFT_CLOSE' then Q.CancelScan(event == 'CRAFT_CLOSE' and 'craft' or 'trade')
        else Q.OnProfessionEvent(event) end
    end)
end)
SLASH_QUINTECRAFT1 = '/qcraft'
SlashCmdList.QUINTECRAFT = function(message)
    Q.Run('commande', function()
        if Q.disabled then return Q.Print('Collecte suspendue : le fichier QuinteCraftDB a un format inconnu.') end
        if not Q.ready then Q.Init() end
        if not Q.ready then return Q.Print('Addon pas encore initialisé : reconnecte-toi ou fais /reload.') end
        local command, value = message:match('^(%S+)%s*(.-)%s*$')
        if command == 'sync' then
            if not Q.sync then return Q.Print('Synchro indisponible : voir /qcraft debug.') end
            if value == 'off' then Q.sync:SetEnabled(false)
            elseif value == 'on' then Q.sync:SetEnabled(true)
            elseif value == 'now' then Q.sync:Announce()
            else return Q.Print('/qcraft sync on|off|now') end
            Q.Print('Synchro : ' .. (Q.sync.enabled and 'activée' or 'désactivée'))
        elseif command == 'debug' then Q.Debug()
        elseif command == 'resume' then Q.Summary()
        elseif command == 'chat' then Q.Search(value)
        elseif command == 'aide' or command == 'help' then
            Q.Print('/qcraft : ouvrir la fenêtre · /qcraft <texte> : chercher une recette · /qcraft chat <texte> : résultat dans le chat')
            Q.Print('/qcraft resume · /qcraft sync on|off|now · /qcraft debug')
        elseif not command then Q.UI.Toggle()
        else Q.UI.Open(message:match('^%s*(.-)%s*$')) end
    end)
end
