local addonName, Core = ...
-- Service commun : moteur terrain embarqué et préférences de voyage du conteneur.
local N = {}
Core.Navigation = N
local OWNER = addonName or 'Quintessence'
local running, pending, driver
local ignoreAuto = false
local function number(v)
    return not (issecretvalue and issecretvalue(v)) and type(v) == 'number'
        and v == v and v > -math.huge and v < math.huge
end
local function api()
    local a = Core.TravelEngine and Core.TravelEngine.API
    if not a then return nil, 'missing' end
    if a.version ~= 1 or type(a.Navigate) ~= 'function' or type(a.Cancel) ~= 'function'
        or type(a.CurrentStop) ~= 'function' then return nil, 'incompatible' end
    return a
end
local function copy(p)
    if not p then return nil end
    return { source = p.source, mapID = p.mapID, x = p.x, y = p.y, title = p.title,
        pending = p == pending, engine = 'Quintessence', kind = p.kind }
end
function N.Message(reason)
    local text = {
        missing = 'Le moteur de voyage intégré est indisponible. Réinstalle Quintessence ; voir /quinte erreurs.',
        disabled = 'Le guidage est désactivé dans Quintessence : Réglages > Voyages.',
        incompatible = 'Mets à jour Quintessence : le moteur de voyage intégré est incompatible.',
        pending = 'Itinéraire demandé : le calcul commencera à la fin du combat.',
        started = 'Calcul de l’itinéraire lancé sur le terrain. /quinte chemin stop pour arrêter.',
        invalid = 'Itinéraire impossible : coordonnées de destination invalides.',
        refused = 'Itinéraire non démarré : vérifie la destination et Réglages > Voyages dans Quintessence.',
        error = 'Le moteur de navigation a rencontré une erreur ; voir /quinte erreurs.',
    }
    return text[reason] or text.refused
end
function N.Current()
    if pending then return copy(pending) end
    if not running then return nil end
    local a = api()
    if not a then running = nil; return nil end
    local ok, stop = pcall(a.CurrentStop, OWNER)
    if not ok or not stop then running = nil; return nil end
    return copy(running)
end
local function navigate(p)
    local a, reason = api()
    if not a then return false, reason end
    local ok, accepted = pcall(a.Navigate, OWNER, p.mapID, p.x / 100, p.y / 100, p.title, p.kind)
    if not ok then Core.Error('itinéraire', accepted); return false, 'error' end
    if accepted ~= true then return false, 'refused' end
    running = p
    return true, 'started'
end
local function unqueue()
    pending = nil
    if driver then driver:UnregisterAllEvents() end
end
local function afterCombat()
    if InCombatLockdown and InCombatLockdown() then return end
    local p = pending
    unqueue()
    if not p or not N.Options().enabled or (Core.GuildBlocked and Core.GuildBlocked()) then return end
    local ok, reason = navigate(p)
    Core.Print(N.Message(reason))
end
--- Coordonnées de carte en pourcentage, comme les marqueurs des modules.
function N.Start(source, mapID, x, y, title, kind)
    if not N.Options().enabled then return false, 'disabled' end
    if type(source) ~= 'string' or source == '' or not number(mapID) or mapID <= 0 or mapID % 1 ~= 0
        or not number(x) or not number(y) or x < 0 or x > 100 or y < 0 or y > 100 then return false, 'invalid' end
    local a, reason = api()
    if not a then return false, reason end
    if Core.GuildBlocked and Core.GuildBlocked() then return false, 'refused' end
    local p = { source = source, mapID = mapID, x = x, y = y,
        title = type(title) == 'string' and title or 'Destination', kind = type(kind) == 'string' and kind or nil }
    if InCombatLockdown and InCombatLockdown() then
        if not driver then
            driver = CreateFrame('Frame')
            driver:SetScript('OnEvent', function(_, event)
                if event == 'USER_WAYPOINT_UPDATED' then unqueue() else afterCombat() end
            end)
        end
        driver:RegisterEvent('PLAYER_REGEN_ENABLED')
        driver:RegisterEvent('USER_WAYPOINT_UPDATED')
        pending = p
        return true, 'pending'
    end
    local ok, result = navigate(p)
    if ok then unqueue() end
    return ok, result
end
--- Cancel ne peut enlever que le trajet dont Quintessence est propriétaire, jamais celui d'un autre addon.
function N.Clear(source)
    local current = N.Current()
    if not current or (source and current.source ~= source) then return false end
    ignoreAuto = true
    local a = api()
    if a then
        local ok, err = pcall(a.Cancel, OWNER)
        if not ok then ignoreAuto = false; Core.Error('arrêt itinéraire', err); return false end
    end
    unqueue()
    running = nil
    if C_Timer and C_Timer.After then C_Timer.After(0, function() ignoreAuto = false end) else ignoreAuto = false end
    return true
end
function N.Command(value)
    if value == 'stop' or value == 'off' then N.Clear(); Core.Print('Guidage Quintessence arrêté.'); return end
    local current = N.Current()
    if current then
        Core.Print('Itinéraire : ' .. Core.Safe(current.title) .. (current.pending and ' (en attente de la fin du combat).' or '.'))
    else
        Core.Print('Aucun itinéraire Quintessence actif. Clique sur Chemin près du marqueur voulu.')
    end
end

--- Copie des préférences : l'interface ne peut pas changer le moteur sans passer par SetOption.
function N.Options()
    local prefs = Core.TravelEngine.Preferences()
    local copy = {}
    for k, v in pairs(prefs) do copy[k] = v end
    return copy
end
function N.SetOption(key, value)
    if Core.TravelDefaults[key] == nil or type(value) ~= 'boolean' then return false end
    if key == 'enabled' and not value then N.Clear() end
    Core.TravelEngine.Preferences()[key] = value
    Core.TravelEngine.ApplyPreferences()
    if N.RefreshSettings then N.RefreshSettings() end
    return true
end
function N.Available() return api() ~= nil end
-- Une sélection de marqueur natif peut lancer un trajet si le joueur le demande.
-- Aucun crochet dans la carte : seul l'événement public du jeu est écouté.
local auto = CreateFrame('Frame')
auto:RegisterEvent('USER_WAYPOINT_UPDATED')
local autoQueued = false
local function waypoint()
    autoQueued = false
    local prefs = N.Options()
    if ignoreAuto or not prefs.enabled or not prefs.automatic then return end
    if not (C_Map and C_Map.GetUserWaypoint) then return end
    local ok, point = pcall(C_Map.GetUserWaypoint)
    if not ok or not point or not point.position then return end
    if Core.TravelEngine.OwnsWaypoint and Core.TravelEngine.OwnsWaypoint(point) then return end
    local x, y = point.position.x, point.position.y
    if point.position.GetXY then
        local got, px, py = pcall(point.position.GetXY, point.position)
        if not got then return end
        x, y = px, py
    end
    if not number(x) or not number(y) or not number(point.uiMapID) then return end
    local current = N.Current()
    if current and current.mapID == point.uiMapID and math.abs(current.x - x * 100) < 0.001
        and math.abs(current.y - y * 100) < 0.001 then return end
    local accepted, reason = N.Start('waypoint', point.uiMapID, x * 100, y * 100, 'Marqueur de carte')
    if not accepted then Core.Print(N.Message(reason)) end
end
auto:SetScript('OnEvent', function()
    -- Regroupe les événements et laisse le moteur terminer sa propre pose de repère.
    if autoQueued then return end
    if C_Timer and C_Timer.After then autoQueued = true; C_Timer.After(0, waypoint) else waypoint() end
end)
if Core.TravelEngine.Init then Core.TravelEngine.Init(Core.TravelEngine.ApplyPreferences) end
