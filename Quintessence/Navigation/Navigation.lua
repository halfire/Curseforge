local addonName, Core = ...
-- Pont vers l'API publique de Shortest Path Forever. Le moteur conserve ses données,
-- son calcul du terrain et ses tracés ; Quintessence lui transmet les marqueurs existants.
local N = {}
Core.Navigation = N
local OWNER = addonName or 'Quintessence'
local running, pending, driver
local function number(v)
    return not (issecretvalue and issecretvalue(v)) and type(v) == 'number'
        and v == v and v > -math.huge and v < math.huge
end
local function api()
    local a = ShortestPathForever and ShortestPathForever.API
    if not a then return nil, 'missing' end
    if a.version ~= 1 or type(a.Navigate) ~= 'function' or type(a.Cancel) ~= 'function'
        or type(a.CurrentStop) ~= 'function' then return nil, 'incompatible' end
    return a
end
local function copy(p)
    if not p then return nil end
    return { source = p.source, mapID = p.mapID, x = p.x, y = p.y, title = p.title,
        pending = p == pending, engine = 'ShortestPathForever', kind = p.kind }
end
function N.Message(reason)
    local text = {
        missing = 'Installe ou active Shortest Path Forever pour calculer le chemin (inclus dans le pack Quintessence).',
        incompatible = 'Mets à jour Shortest Path Forever : son API de navigation n’est pas compatible.',
        pending = 'Itinéraire demandé : le calcul commencera à la fin du combat.',
        started = 'Calcul de l’itinéraire lancé sur le terrain. /quinte chemin stop pour arrêter.',
        invalid = 'Itinéraire impossible : coordonnées de destination invalides.',
        refused = 'Itinéraire non démarré : vérifie les réglages Trajets de Shortest Path Forever et la destination.',
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
    if not p or (Core.GuildBlocked and Core.GuildBlocked()) then return end
    local ok, reason = navigate(p)
    Core.Print(N.Message(reason))
end
--- Coordonnées de carte en pourcentage, comme les marqueurs des modules.
function N.Start(source, mapID, x, y, title, kind)
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
    local a = api()
    if a then
        local ok, err = pcall(a.Cancel, OWNER)
        if not ok then Core.Error('arrêt itinéraire', err); return false end
    end
    unqueue()
    running = nil
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
