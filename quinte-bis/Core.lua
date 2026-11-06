local addonName, Q = ...
-- quinte-bis : listes BiS des membres et besoins par donjon, pour savoir qui emmener où (module de Quintessence).
Q.name, Q.version, Q.revision = addonName or 'quinte-bis', '0.6.0', 0
Q.debug = { errors = {}, slow = {} }

function Q.Call(fn, ...)
    if type(fn) ~= 'function' then return false end
    return pcall(fn, ...)
end
function Q.Error(context, reason)
    Q.debug.errors[#Q.debug.errors + 1] = context .. ': ' .. tostring(reason)
    if #Q.debug.errors > 10 then table.remove(Q.debug.errors, 1) end
end
-- Chronomètre : tout traitement de plus de 50 ms est noté (visible dans /qbis debug).
local clock = debugprofilestop
function Q.Run(context, fn, ...)
    local started = clock and clock()
    local ok, result = Q.Call(fn, ...)
    if not ok then Q.Error(context, result) end
    if started then
        local elapsed = clock() - started
        if elapsed > 50 then Q.debug.slow[context] = math.max(Q.debug.slow[context] or 0, math.floor(elapsed)) end
    end
    return ok, result
end
function Q.Now() return (time or GetServerTime)() end
function Q.Tick(previous) return math.max(Q.Now(), (previous or 0) + 1) end
function Q.Realm() return (GetRealmName():gsub('%s', '')) end
-- Clé du personnage : celle du conteneur (nom complet « Prénom Nom » sur WoW Forever)
function Q.Key() return Quintessence.Key() end
function Q.Safe(text) return (tostring(text or ''):gsub('|', '||')) end
function Q.Print(text)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage('|cff70d5bfQuintessence|r ' .. text)
    end
end
function Q.Changed(localChange)
    Q.revision = Q.revision + 1
    if localChange and Q.sync then Q.sync:NotifyLocal() end
    if Q.UI then Q.UI.OnDataChanged() end
end

-- Initialisation unique : à ADDON_LOADED de cet addon, ou en secours à PLAYER_LOGIN.
function Q.Init()
    if Q.ready or Q.disabled then return end
    if type(QuinteBisDB) ~= 'table' then QuinteBisDB = { format = 1, characters = {} } end
    if QuinteBisDB.format == nil and QuinteBisDB.characters == nil then QuinteBisDB.format, QuinteBisDB.characters = 1, {} end
    if QuinteBisDB.format ~= 1 or type(QuinteBisDB.characters) ~= 'table' then
        Q.disabled = true; Q.Print('Format de sauvegarde inconnu : quinte-bis suspendu pour préserver le fichier.'); return
    end
    -- WoW Forever : fiche enregistrée avant 1.3.0 sous « Prénom-Royaume » → « Prénom Nom-Royaume »
    Quintessence.MigrateSelf(QuinteBisDB.characters, function(c) c.name = Quintessence.PlayerName() end)
    Q.ready = true
    Q.Run('personnage', Q.Mine)
    Q.Run('synchro', Q.SyncInit)
    Q.Run('infobulles', Q.TooltipInit)
    Q.Run('maj+clic', function() if Q.UI then Q.UI.HookItemClicks() end end)
end

-- Objets obtenus : relecture regroupée après les changements d'équipement ou de sacs (jamais à chaque événement)
local scanPending = false
function Q.ScanSoon()
    if scanPending or not Q.ready then return end
    scanPending = true
    C_Timer.After(2, function() scanPending = false; Q.Run('objets obtenus', Q.ScanOwned) end)
end

local frame = CreateFrame('Frame')
for _, event in ipairs({ 'ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_LEVEL_UP', 'PLAYER_EQUIPMENT_CHANGED', 'BAG_UPDATE_DELAYED', 'GET_ITEM_INFO_RECEIVED' }) do
    Q.Call(frame.RegisterEvent, frame, event)
end
frame:SetScript('OnEvent', function(_, event, arg)
    Q.Run(event, function()
        if event == 'ADDON_LOADED' then
            if arg == Q.name then Q.Init() end
            return
        end
        if event == 'PLAYER_LOGIN' then
            Q.Init()
            if not Q.ready then return end
            if Q.sync then Q.sync:Start() end
            Q.ScanSoon()
        elseif not Q.ready then return
        elseif event == 'PLAYER_LEVEL_UP' then Q.Mine(tonumber(arg))
        elseif event == 'GET_ITEM_INFO_RECEIVED' then if Q.UI then Q.UI.OnDataChanged() end
        else Q.ScanSoon() end
    end)
end)

SLASH_QUINTEBIS1 = '/qbis'
SlashCmdList.QUINTEBIS = function(message)
    Q.Run('commande', function()
        if Q.disabled then return Q.Print('quinte-bis suspendu : le fichier QuinteBisDB a un format inconnu.') end
        if not Q.ready then Q.Init() end
        if not Q.ready then return Q.Print('Addon pas encore initialisé : reconnecte-toi ou fais /reload.') end
        local command = (message or ''):match('^%s*(%S*)')
        if command == '' then Q.UI.Toggle()
        elseif command == 'donjons' then Q.UI.Open('needs')
        elseif command == 'raids' then Q.UI.Open('loot')
        elseif command == 'resume' then Q.Summary()
        elseif command == 'debug' then Q.Debug()
        else
            Q.Print('/qbis : ouvrir ta liste BiS · /qbis raids : butin des raids · /qbis donjons : qui a besoin de quel donjon · /qbis resume · /qbis debug')
        end
    end)
end
