local _, Q = ...
--[[
  SOS.lua : Système d'Appel aux Armes (SOS PvP Sauvage).
  En 1 clic, alerte résonnant dans toute la guilde avec la position exacte
  (zone, sous-zone, coordonnées X/Y, layer) et bouton d'invitation directe.
]]

local SOS_TTL = 600 -- 10 minutes
local SOS_GAP = 5 -- secondes entre deux SOS : un double clic faisait sonner deux alertes de raid chez toute la guilde
local lastSOS = 0

-- Récupération sécurisée de la position du joueur
function Q.GetPlayerCoordinates()
    local x, y, mapID = 0, 0, nil
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
        mapID = C_Map.GetBestMapForUnit('player')
        if mapID then
            local pos = C_Map.GetPlayerMapPosition(mapID, 'player')
            if pos and pos.GetXY then
                x, y = pos:GetXY()
                x = math.floor((x or 0) * 1000) / 10
                y = math.floor((y or 0) * 1000) / 10
            end
        end
    elseif GetPlayerMapPosition then
        x, y = GetPlayerMapPosition('player')
        x = math.floor((x or 0) * 1000) / 10
        y = math.floor((y or 0) * 1000) / 10
    end
    return x, y, mapID
end

-- Récupération du layer actuel (depuis quinte-layer si chargé)
function Q.DetectCurrentLayer()
    -- Layer courant publié par quinte-layer ; la liste des membres ne contient le joueur que si le radar a été ouvert
    -- (et parfois sur deux layers), d'où des SOS souvent annoncés « Layer 1 »
    if QuinteLayerDB and type(QuinteLayerDB.currentLayer) == 'number' then return QuinteLayerDB.currentLayer end
    if QuinteLayerDB and QuinteLayerDB.layers then
        local myName = Q.PlayerName and Q.PlayerName()
        for layerNum, members in pairs(QuinteLayerDB.layers) do
            if members[myName] then return layerNum end
        end
    end
    return nil -- inconnu (« Layer ? ») : avant, « Layer 1 » par défaut, souvent faux
end

-- Identifiant brut de notre layer (quinte-layer 0.3.0+), envoyé avec les SOS et camps
function Q.CurrentZid()
    local L = Quintessence.Layer
    return L and L.MyZid and L.MyZid() or nil
end
-- Layer d'une alerte reçue dans NOTRE numérotation (celle du radar), sinon le numéro de l'expéditeur
function Q.LayerFor(record)
    local L = Quintessence.Layer
    if type(record) == 'table' and record.zid and L and L.LayerOf then
        local layer = L.LayerOf(record.zone, record.zid)
        if layer and layer > 0 then return layer end
    end
    return type(record) == 'table' and record.layer or nil
end

-- « Layer 3 », ou « Layer ? » si le layer n'est pas connu
function Q.LayerLabel(layer)
    layer = tonumber(layer)
    return (layer and layer > 0) and ('Layer ' .. layer) or 'Layer ?'
end

-- SOS le plus récent, lu par Quintessence/UI.lua (bandeau de l'accueil) : jamais renseigné avant
local function setActiveSOS(list)
    local a = list[1]
    QuinteMapDB.activeSOS = a and { player = a.name, zone = a.zone, x = a.x, y = a.y, layer = a.layer, time = a.time } or nil
end

-- Déclencher l'alerte SOS PvP
function Q.SendSOS()
    local now = Q.Now()
    if now - lastSOS < SOS_GAP then
        Q.Print('SOS déjà transmis il y a quelques secondes.')
        return QuinteMapDB.sosAlerts and QuinteMapDB.sosAlerts[Q.Who(Q.PlayerName())]
    end
    lastSOS = now
    local x, y, mapID = Q.GetPlayerCoordinates()
    local zone = (GetZoneText and GetZoneText()) or 'Inconnue'
    local subzone = (GetSubZoneText and GetSubZoneText()) or ''
    local layer = Q.DetectCurrentLayer()
    local _, class = UnitClass and UnitClass('player')

    local targetName, targetClass = nil, nil
    if UnitExists and UnitExists('target') and UnitIsPlayer and UnitIsPlayer('target') and UnitCanAttack and UnitCanAttack('player', 'target') then
        local okN, rawN = pcall(UnitName, 'target')
        if okN and type(rawN) == 'string' and not (type(issecretvalue) == 'function' and issecretvalue(rawN)) then
            targetName = rawN
        end
        local okC, _, rawC = pcall(UnitClass, 'target')
        if okC and type(rawC) == 'string' and not (type(issecretvalue) == 'function' and issecretvalue(rawC)) then
            targetClass = rawC
        end
    elseif Q.GetLastAttacker then
        local last = Q.GetLastAttacker()
        if last then
            targetName = last.name
            targetClass = last.class
        end
    end

    local sos = {
        name = Q.PlayerName(),
        class = class or 'WARRIOR',
        zone = zone,
        subzone = subzone,
        mapID = mapID,
        x = x,
        y = y,
        layer = layer,
        zid = Q.CurrentZid(),
        targetName = targetName,
        targetClass = targetClass,
        time = Q.Now()
    }

    if not QuinteMapDB.sosAlerts then QuinteMapDB.sosAlerts = {} end
    QuinteMapDB.sosAlerts[Q.Who(sos.name)] = sos

    -- Envoi sur le canal d'addon
    if Q.comm and Q.comm.Send then
        Q.comm:Send({
            t = 'sos',
            sos = sos
        })
    end

    Q.Print(string.format('|cffff2020[APPEL AUX ARMES]|r Alerte transmise à la guilde à %s%s (%.1f, %.1f - %s) !',
        zone, subzone ~= '' and (' - ' .. subzone) or '', x, y, Q.LayerLabel(layer)))

    Q.GetActiveSOS()
    if Q.UI and Q.UI.RefreshSOS then Q.UI.RefreshSOS() end
    return sos
end

-- Annuler l'alerte (sécurité retrouvée)
function Q.ClearSOS()
    local myName = Q.PlayerName and Q.PlayerName()
    local alerts = QuinteMapDB.sosAlerts
    local had = alerts and alerts[Q.Who(myName)] ~= nil
    if alerts then
        alerts[Q.Who(myName)] = nil
        alerts[myName] = nil -- ancienne clé (0.2.0)
    end
    lastSOS = 0 -- un nouveau SOS peut repartir tout de suite

    -- Envoyé même sans SOS connu ici (après un /reload, les autres l'ont encore)
    if Q.comm and Q.comm.Send then
        Q.comm:Send({
            t = 'sos_clear',
            name = myName
        })
    end

    Q.Print(had and '|cff3fb950Alerte levée.|r La guilde sait que tu es désormais en sécurité.'
        or '|cff3fb950Fin d’alerte envoyée à la guilde.|r')
    Q.GetActiveSOS()
    if Q.UI and Q.UI.RefreshSOS then Q.UI.RefreshSOS() end
end

-- Masquer chez soi l'alerte d'un autre membre (elle revient s'il relance un SOS)
function Q.DismissSOS(name)
    if Quintessence.SameName and Quintessence.SameName(name, Q.PlayerName()) then return Q.ClearSOS() end
    local alerts = QuinteMapDB.sosAlerts
    if alerts and alerts[Q.Who(name)] then
        alerts[Q.Who(name)] = nil
        Q.Print('Alerte de ' .. Q.Safe(Q.DisplayName(name)) .. ' masquée.')
        Q.GetActiveSOS()
        if Q.UI and Q.UI.RefreshSOS then Q.UI.RefreshSOS() end
    end
end

-- Réception d'un SOS d'un membre
function Q.OnReceiveSOS(data, sender)
    if not data or type(data.sos) ~= 'table' or not sender then return end
    local sos = data.sos
    -- Nom affiché tiré de l'expéditeur (un message ne peut pas lancer le SOS d'un autre)
    sos.name = Q.DisplayName(sender)
    sos.time = Q.Now() -- heure de réception : les horloges des joueurs ne sont pas réglées pareil

    if not QuinteMapDB.sosAlerts then QuinteMapDB.sosAlerts = {} end
    QuinteMapDB.sosAlerts[Q.Who(sender)] = sos

    local targetInfo = ''
    if sos.targetName then
        targetInfo = string.format(' [Agresseur : %s]', sos.targetName)
    end

    local msg = string.format('|cffff2020[SOS GUILDE]|r |cffffffff%s|r attaqué à %s%s (coords %.1f, %.1f - |cff38bdf8%s|r)%s !',
        Q.Safe(sos.name), Q.Safe(sos.zone or 'Inconnue'), (sos.subzone and sos.subzone ~= '') and (' - ' .. sos.subzone) or '',
        sos.x or 0, sos.y or 0, Q.LayerLabel(Q.LayerFor(sos)), targetInfo)

    if QuinteMapDB.settings and QuinteMapDB.settings.chatAlert then
        Q.Print(msg)
    end

    if QuinteMapDB.settings and QuinteMapDB.settings.soundAlert and PlaySound then
        PlaySound(SOUNDKIT.RAID_WARNING or 8959)
    end

    Q.GetActiveSOS()
    if Q.UI and Q.UI.RefreshSOS then Q.UI.RefreshSOS() end
end

function Q.OnReceiveSOSClear(_, sender)
    -- Seul l'expéditeur peut lever sa propre alerte ; avant, la clé (nom écrit par lui) ne correspondait pas toujours
    -- à celle de l'alerte (expéditeur vu par le réseau) et l'alerte restait affichée
    local alerts = QuinteMapDB.sosAlerts
    if not sender or not alerts then return end
    local who = Q.Who(sender)
    if alerts[who] then
        alerts[who] = nil
        Q.Print('|cff3fb950[Sécurité]|r ' .. Q.Safe(Q.DisplayName(sender)) .. ' a levé son alerte SOS.')
        Q.GetActiveSOS()
        if Q.UI and Q.UI.RefreshSOS then Q.UI.RefreshSOS() end
    end
end

-- Récupération de la liste des SOS actifs
function Q.GetActiveSOS()
    local list = {}
    local now = Q.Now()
    if not QuinteMapDB.sosAlerts then return list end

    for name, sos in pairs(QuinteMapDB.sosAlerts) do
        if type(sos) == 'table' and (now - (sos.time or 0)) <= SOS_TTL and not Q.IsOffline(sos.name or name)
            and name == Q.Who(sos.name or name) then -- (anciennes clés 0.2.0 retirées)
            list[#list + 1] = sos
        else
            QuinteMapDB.sosAlerts[name] = nil
        end
    end

    table.sort(list, function(a, b) return (a.time or 0) > (b.time or 0) end)
    setActiveSOS(list)
    return list
end

function Q.GetActiveSOSCount()
    return #Q.GetActiveSOS()
end

function Q.InitSOS()
    -- Notre propre SOS de la session précédente n'a plus de sens après une reconnexion (les autres l'ont retiré à
    -- notre déconnexion) ; alertes expirées retirées et activeSOS recalculé
    if QuinteMapDB.sosAlerts then QuinteMapDB.sosAlerts[Q.Who(Q.PlayerName())] = nil end
    Q.GetActiveSOS()
end
