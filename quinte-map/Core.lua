local addonName, Q = ...
--[[
  quinte-map : Carte tactique de guilde pour Quintessence.
  - Bouton SOS PvP sauvage (Appel aux armes en 1 clic avec coordonnées et layer)
  - Carte et suivi des feux de campement sociaux de la guilde (mécanique de camping Forever)
  Règle Retail 12+ : uniquement nos propres cadres, aucune écriture dans les objets de Blizzard.
]]
local Core = Quintessence
Q.name, Q.version = addonName or 'quinte-map', '0.7.1'
Q.debug = { errors = {}, slow = {} }

function Q.Call(fn, ...)
    if type(fn) ~= 'function' then return false end
    return pcall(fn, ...)
end

function Q.Error(context, reason)
    local list = Q.debug.errors
    list[#list + 1] = context .. ': ' .. tostring(reason)
    if #list > 20 then table.remove(list, 1) end
end

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
function Q.Key() return Core.Key() end
function Q.PlayerName() return Core.PlayerName() end
-- Clé des tables (SOS, camps) : nom normalisé, identique quelle que soit la forme reçue du réseau
function Q.Who(name)
    if Core.CanonicalKey then return Core.CanonicalKey(name) end
    return type(name) == 'string' and name:gsub('%s', ''):lower() or ''
end
function Q.DisplayName(name) return Core.DisplayName and Core.DisplayName(name) or name end
-- Déconnecté (false) seulement si le conteneur le sait ; nil = on ne sait pas, on garde
function Q.IsOffline(name) return Core.IsOnline ~= nil and Core.IsOnline(name) == false end
function Q.Safe(text) return (tostring(text or ''):gsub('|', '||')) end

function Q.Print(text)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage('|cffe5484dQuintessence SOS|r ' .. text)
    end
end

--- Édition CurseForge : le SOS seul (ni Vendetta, ni campements, ni rares, même en arrière-plan).
function Q.SOSOnly() return Core.IsCurseForge ~= nil and Core.IsCurseForge() end

local function initSubmodules()
    if Q.InitSOS and not Q.sosInitialized then Q.sosInitialized = true; Q.Run('sos', Q.InitSOS) end
    if Q.SOSOnly() then
        if Q.InitPins and not Q.pinsInitialized then Q.pinsInitialized = true; Q.Run('pins', Q.InitPins) end
        return
    end
    if Q.InitVendetta and not Q.vendettaInitialized then Q.vendettaInitialized = true; Q.Run('vendetta', Q.InitVendetta) end
    if Q.InitCamping and not Q.campInitialized then Q.campInitialized = true; Q.Run('camping', Q.InitCamping) end
    if Q.InitPins and not Q.pinsInitialized then Q.pinsInitialized = true; Q.Run('pins', Q.InitPins) end
    if Q.InitRares and not Q.raresInitialized then Q.raresInitialized = true; Q.Run('rares', Q.InitRares) end
end

function Q.Init()
    if not Q.ready then
        if type(QuinteMapDB) ~= 'table' then QuinteMapDB = {} end
        QuinteMapDB.format = QuinteMapDB.format or 1
        QuinteMapDB.settings = QuinteMapDB.settings or {
            soundAlert = true,
            chatAlert = true,
            autoCampDetect = true
        }
        QuinteMapDB.sosAlerts = QuinteMapDB.sosAlerts or {}
        QuinteMapDB.vendetta = QuinteMapDB.vendetta or {}
        QuinteMapDB.camps = QuinteMapDB.camps or {}
        Q.ready = true

        if Core.RegisterChannel then
            Q.comm = Core:RegisterChannel('qmap', function(data, sender)
                Q.Run('réseau', Q.OnNetworkMessage, data, sender)
            end)
        end
        -- Membre déconnecté : son SOS et son campement disparaissent tout de suite
        if Core.OnPresence then
            Core:OnPresence(function(name, online)
                if online then return end
                Q.Run('déconnexion', Q.ForgetMember, name)
            end)
        end
        -- Tour toutes les 15 s : SOS / camps expirés ou de membres déconnectés retirés, fenêtre et accueil à jour
        if C_Timer and C_Timer.After then
            local function tick()
                Q.Run('tour', function()
                    if Q.GetActiveSOS then Q.GetActiveSOS() end
                    if Q.UI and Q.UI.Refresh then Q.UI.Refresh() end
                end)
                C_Timer.After(15, tick)
            end
            C_Timer.After(15, tick)
        end
    end

    initSubmodules()
end

function Q.ForgetMember(name)
    local who, changed = Q.Who(name), false
    if QuinteMapDB.sosAlerts and QuinteMapDB.sosAlerts[who] then
        QuinteMapDB.sosAlerts[who] = nil; changed = true
        Q.Print('|cff3fb950[Sécurité]|r ' .. Q.Safe(Q.DisplayName(name)) .. ' s’est déconnecté : son alerte SOS est retirée.')
    end
    if QuinteMapDB.camps and QuinteMapDB.camps[who] then QuinteMapDB.camps[who] = nil; changed = true end
    if changed then
        if Q.GetActiveSOS then Q.GetActiveSOS() end
        if Q.UI and Q.UI.Refresh then Q.UI.Refresh() end
    end
end

function Q.OnNetworkMessage(data, sender)
    if type(data) ~= 'table' or not data.t then return end
    if Q.SOSOnly() and data.t ~= 'sos' and data.t ~= 'sos_clear' then return end
    if data.t == 'sos' and Q.OnReceiveSOS then
        Q.OnReceiveSOS(data, sender)
    elseif data.t == 'sos_clear' and Q.OnReceiveSOSClear then
        Q.OnReceiveSOSClear(data, sender)
    elseif data.t == 'vendetta' and Q.OnReceiveVendetta then
        Q.OnReceiveVendetta(data, sender)
    elseif data.t == 'vendetta_avenged' and Q.OnReceiveVendettaAvenged then
        Q.OnReceiveVendettaAvenged(data, sender)
    elseif data.t == 'camp' and Q.OnReceiveCamp then
        Q.OnReceiveCamp(data, sender)
    elseif data.t == 'camp_remove' and Q.OnReceiveCampRemove then
        Q.OnReceiveCampRemove(data, sender)
    elseif data.t == 'rare' and Q.OnReceiveRare then
        Q.OnReceiveRare(data, sender)
    end
end

local frame = CreateFrame('Frame')
for _, event in ipairs({ 'ADDON_LOADED', 'PLAYER_LOGIN' }) do Q.Call(frame.RegisterEvent, frame, event) end
frame:SetScript('OnEvent', function(_, event, arg)
    Q.Run(event, function()
        if event == 'ADDON_LOADED' then
            if arg == Q.name then Q.Init() end
            return
        end
        Q.Init()
    end)
end)

-- Commandes slash /qmap et /qsos
SLASH_QUINTEMAP1 = '/qmap'
SlashCmdList.QUINTEMAP = function(message)
    Q.Run('commande', function()
        if not Q.ready then Q.Init() end
        local cmd, arg = (message or ''):match('^%s*(%S*)%s*(.-)%s*$')
        cmd = (cmd or ''):lower()
        if Q.SOSOnly() and (cmd == 'vendetta' or cmd == 'kos' or cmd == 'vengeance' or cmd == 'camp') then cmd = 'aide' end
        if cmd == '' then
            Q.UI.Toggle()
        elseif cmd == 'sos' then
            if Q.SendSOS then Q.SendSOS() end
        elseif cmd == 'safe' or cmd == 'clear' then
            if Q.ClearSOS then Q.ClearSOS() end
        elseif cmd == 'vendetta' or cmd == 'kos' or cmd == 'vengeance' then
            if arg and arg ~= '' and Q.ReportKillByEnemy then
                Q.ReportKillByEnemy(arg)
            else
                Q.UI.Open('vendetta')
            end
        elseif cmd == 'camp' then
            if Q.DeployCamp then Q.DeployCamp() end
        elseif cmd == 'debug' then
            Q.Debug()
        else
            if Q.SOSOnly() then return Q.Print('/qmap : ouvrir le SOS · /qsos : lancer un SOS · /qmap safe : lever mon alerte') end
            Q.Print('/qmap : ouvrir la carte tactique · /qsos : lancer un SOS · /qmap vendetta [nom] : cible à venger · /qmap camp : poser un campement')
        end
    end)
end

SLASH_QUINTESOS1 = '/qsos'
SlashCmdList.QUINTESOS = function()
    Q.Run('commande_sos', function()
        if not Q.ready then Q.Init() end
        if Q.SendSOS then Q.SendSOS() end
    end)
end

function Q.Debug()
    Q.Print('Module Quinte-map v' .. Q.version)
    local sosCount = Q.GetActiveSOSCount and Q.GetActiveSOSCount() or 0
    local vendettaCount = Q.GetActiveVendettaCount and Q.GetActiveVendettaCount() or 0
    local campCount = Q.GetActiveCampCount and Q.GetActiveCampCount() or 0
    Q.Print(string.format('SOS actifs : %d · Cibles Vendetta à venger : %d · Feux de campement actifs : %d', sosCount, vendettaCount, campCount))
    for _, e in ipairs(Q.debug.errors) do Q.Print(Q.Safe(e)) end
end

function Q.Summary()
    local sosCount = Q.GetActiveSOSCount and Q.GetActiveSOSCount() or 0
    local vendettaCount = Q.GetActiveVendettaCount and Q.GetActiveVendettaCount() or 0
    local campCount = Q.GetActiveCampCount and Q.GetActiveCampCount() or 0
    if sosCount > 0 then
        return '|cffe5484d' .. sosCount .. ' SOS en cours !|r'
    end
    if Q.SOSOnly() then return 'SOS prêt' end
    local parts = {}
    if vendettaCount > 0 then parts[#parts + 1] = vendettaCount .. ' à venger' end
    if campCount > 0 then parts[#parts + 1] = campCount .. ' camp(s)' end
    local rareCount = Q.GetActiveRares and #Q.GetActiveRares() or 0
    if rareCount > 0 then parts[#parts + 1] = rareCount .. ' rare(s)' end
    if #parts > 0 then return table.concat(parts, ' · ') end
    return 'SOS, Vendetta & Camps prêts'
end
