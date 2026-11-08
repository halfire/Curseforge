local _, Q = ...
--[[
  Pins.lua : Repères de navigation (Waypoints Blizzard C_Map / C_SuperTrack, liens carte cliquables et TomTom).
  Règle Retail 12+ / Midnight : aucune écriture ni attache de cadre dans WorldMapFrame (évite tout taint ou
  blocage ADDON_ACTION_FORBIDDEN / ADDON_ACTION_BLOCKED). Le repère diamant Blizzard et le lien |Hworldmap:...|h
  dans le chat sont 100 % natifs et sans restriction.
]]

local function getBestMapID()
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, id = pcall(C_Map.GetBestMapForUnit, 'player')
        if ok and type(id) == 'number' and id > 0 then return id end
    end
    return nil
end

-- Carte du monde ouverte par C_Map.OpenWorldMap : fonction du jeu prévue pour les addons, sans taint. La carte de
-- Forever n'a aucun cadre sécurisé : elle s'ouvre aussi en combat (un SOS PvP se lit en plein combat). Si le jeu la
-- refuse quand même en combat, on l'ouvre à la fin du combat (PLAYER_REGEN_ENABLED). Avant, le bouton Carte ne posait
-- qu'un repère et un lien dans le chat : il fallait encore cliquer sur le lien (deux clics).
local pendingMap
local function openWorldMap(mapID)
    if not (C_Map and C_Map.OpenWorldMap) then return 'absent' end
    local ok
    if mapID then ok = pcall(C_Map.OpenWorldMap, mapID) else ok = pcall(C_Map.OpenWorldMap) end
    if ok then return 'ok' end
    if InCombatLockdown and InCombatLockdown() then pendingMap = mapID or true; return 'combat' end
    return 'erreur'
end

--- Place un repère Waypoint Blizzard (flèche 3D de suivi + repère diamant sur la carte) ou TomTom
--- open : ouvre aussi la carte du monde sur ce repère
function Q.SetWaypoint(mapID, x, y, title, open, route)
    local mID = tonumber(mapID) or getBestMapID()
    x = tonumber(x)
    y = tonumber(y)
    if not x or not y then return end

    local normX = math.max(0.001, math.min(0.999, x / 100))
    local normY = math.max(0.001, math.min(0.999, y / 100))
    local waypointSet = false

    if route then
        local navigation = Quintessence and Quintessence.Navigation
        if not navigation then Q.Print('Mets à jour le conteneur Quintessence pour utiliser les itinéraires.'); return false end
        local accepted, reason = navigation.Start('map', mID, normX * 100, normY * 100, title)
        Q.Print(navigation.Message(reason))
        if not accepted then return false end
        waypointSet = true
    else
        if Quintessence and Quintessence.Navigation then Quintessence.Navigation.Clear(nil, true) end
    end

    -- Waypoint natif Blizzard (C_Map + C_SuperTrack) sans toucher WorldMapFrame
    if not route and mID and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        pcall(function()
            local canSet = true
            if C_Map.CanSetUserWaypointOnMap then
                canSet = C_Map.CanSetUserWaypointOnMap(mID)
            end
            if canSet then
                local point = UiMapPoint.CreateFromCoordinates(mID, normX, normY)
                if point then
                    C_Map.SetUserWaypoint(point)
                    waypointSet = true
                    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                    end
                end
            end
        end)
    end

    -- Carte reste neutre avec le moteur intégré (ou son ancien addon autonome).
    local navigation = Quintessence and Quintessence.Navigation
    local integrated = navigation and navigation.Available and navigation.Available()
    if not route and not integrated and not (ShortestPathForever and ShortestPathForever.API) and mID and TomTom and TomTom.AddWaypoint then
        pcall(TomTom.AddWaypoint, TomTom, mID, normX, normY, { title = title or 'Quintessence' })
    end

    local label = Q.Safe(title or 'Objectif')
    local opened = open and openWorldMap(mID)
    if opened == 'ok' then
        Q.Print(string.format('Carte ouverte sur |cffffd100%s|r (%.1f, %.1f)%s.', label, x, y,
            waypointSet and ', repère et flèche de suivi placés' or ''))
        return
    elseif opened == 'combat' then
        Q.Print(string.format('Repère placé sur |cffffd100%s|r (%.1f, %.1f) : la carte s’ouvrira à la fin du combat.', label, x, y))
        return
    end
    if mID then
        local coordX = math.floor(normX * 10000 + 0.5)
        local coordY = math.floor(normY * 10000 + 0.5)
        local link = string.format('|cffffff00|Hworldmap:%d:%d:%d|h[Carte : %s (%.1f, %.1f)]|h|r', mID, coordX, coordY, label, x, y)
        Q.Print(string.format('Repère placé : %s%s.', link, waypointSet and ' (flèche de suivi activée)' or ''))
    else
        Q.Print(string.format('Repère placé vers |cffffd100%s|r (%.1f, %.1f).', label, x, y))
    end
end

--- Bouton Carte : repère + carte du monde ouverte en un clic (jamais WorldMapFrame directement)
function Q.ShowOnWorldMap(mapID, x, y, title)
    Q.SetWaypoint(mapID, x, y, title, true)
end

--- Option explicite : même destination que Carte, avec le trait sur carte et minicarte.
function Q.ShowRoute(mapID, x, y, title)
    return Q.SetWaypoint(mapID, x, y, title, true, true)
end

--- Conservé par compatibilité interne (n'attache aucun cadre à WorldMapFrame pour éviter tout taint Midnight 12.0)
function Q.UpdateWorldMapPins()
end

function Q.InitPins()
    local frame = CreateFrame('Frame')
    Q.Call(frame.RegisterEvent, frame, 'PLAYER_REGEN_ENABLED')
    frame:SetScript('OnEvent', function()
        if not pendingMap then return end
        local mapID = pendingMap ~= true and pendingMap or nil
        pendingMap = nil
        Q.Run('carte', openWorldMap, mapID)
    end)
end
