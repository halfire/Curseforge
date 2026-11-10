local _, Q = ...
local function fold(value)
    local text = value
    for _, letters in ipairs({{'À','à'}, {'Â','â'}, {'Ä','ä'}, {'É','é'}, {'È','è'}, {'Ê','ê'}, {'Ë','ë'},
        {'Î','î'}, {'Ï','ï'}, {'Ô','ô'}, {'Ö','ö'}, {'Ù','ù'}, {'Û','û'}, {'Ü','ü'}, {'Ç','ç'}}) do
        text = text:gsub(letters[1], letters[2])
    end
    return (text:gsub('[A-Z]', string.lower))
end
local function className(class)
    return (LOCALIZED_CLASS_NAMES_MALE or {})[class] or class or '?'
end
local function colored(record)
    local color = ((CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[record.class or ''] or {}).colorStr
    if type(color) ~= 'string' or not color:match('^%x%x%x%x%x%x%x%x$') then color = 'ffffffff' end
    return '|c' .. color .. Q.Safe(record.name) .. '|r'
end
local function professions(value)
    if not value then return '?' end
    local parts = {}
    for _, p in ipairs(value) do parts[#parts + 1] = Q.Safe(p.name) .. ' ' .. Q.Safe(p.skill) .. '/' .. Q.Safe(p.maxSkill) end
    return #parts > 0 and table.concat(parts, ', ') or 'aucun métier relevé'
end
local function syncStatus()
    if Q.sync then return Q.sync:Status() end
    return {enabled = false, queued = 0, buffers = 0, deferred = 'non démarrée', rejected = 0}
end
function Q.Summary()
    local own, remote = 0, 0
    for _, c in pairs(QuinteCaractDB.characters) do
        if c.source == 'self' then own = own + 1 elseif c.source == 'sync' then remote = remote + 1 end
    end
    local status = syncStatus()
    Q.Print(own .. ' perso(s) locaux, ' .. remote .. ' synchronisé(s). Synchro : ' .. (status.enabled and 'on' or 'off')
        .. ', file : ' .. status.queued .. ', report : ' .. status.deferred .. '.')
    Q.Print('Fais /reload puis envoie WTF/Account/<COMPTE>/SavedVariables/quinte-caract.lua sur la page Importer du site.')
end
function Q.Search(query)
    local matches, needle = {}, fold(query)
    for key, c in pairs(QuinteCaractDB.characters) do
        if ((c.level or 0) >= Q.MIN_LEVEL or c.source == 'self') and fold(key):find(needle, 1, true) then matches[#matches + 1] = {key = key, data = c} end
    end
    table.sort(matches, function(a, b) return a.key < b.key end)
    if #matches == 0 then return Q.Print('Aucun personnage correspondant à « ' .. Q.Safe(query) .. ' ».') end
    for index, row in ipairs(matches) do
        if index > 20 then Q.Print('Affichage limité à 20 personnages : préciser le nom.'); break end
        local c = row.data
        local fire = c.stats and c.stats.resistances and c.stats.resistances.fire
        local pvp = c.pvp or {}
        Q.Print(colored(c) .. ' (' .. Q.Safe(c.realm) .. ') — ' .. Q.Safe(className(c.class)) .. ', niveau ' .. Q.Safe(c.level)
            .. ', ilvl ' .. (c.itemLevel and string.format('%.1f', c.itemLevel) or '?') .. ', spé ' .. Q.Safe(c.spec)
            .. ', RF ' .. Q.Safe(fire) .. ', PvP ' .. Q.Safe(pvp.rank) .. ' ' .. Q.Safe(pvp.rankName) .. '.')
        Q.Print('Métiers : ' .. professions(c.professions) .. '. Relevé : ' .. Q.Safe(c.updated)
            .. (c.source == 'sync' and ' ; reçu via ' .. Q.Safe(c.syncedFrom) or ' ; local') .. '.')
    end
end
local function trace(value)
    if type(value) == 'string' then return Q.Safe(value:sub(1, 120)) end
    if type(value) == 'number' or type(value) == 'boolean' then return tostring(value) end
    return value == nil and 'nil' or type(value)
end
function Q.Debug()
    Q.Print('Statistiques du jeu : ' .. ((Q.StatisticsMessages or {})[Q.statisticsState] or 'pas encore relevées') .. ' ; /qcaract statistiques pour relire.')
    Q.Run('relevé diagnostic', Q.Capture)
    local keys = {}
    for label in pairs(Q.api) do
        if label:find('Talent') or label:find('Specialization') or label:find('Config') or label:find('ImportString')
            or label:find('PVP') or label:find('Item') then keys[#keys + 1] = label end
    end
    table.sort(keys)
    for _, label in ipairs(keys) do
        local state, values = Q.api[label], {}
        for i = 1, 4 do values[i] = trace(state.values and state.values[i]) end
        Q.Print(Q.Safe(label) .. ' : ' .. state.state .. ' ; ' .. table.concat(values, ', '))
    end
    local status = syncStatus()
    Q.Print('Scans : ' .. Q.scans .. ', changements : ' .. Q.changes .. ', synchro : ' .. (status.enabled and 'on' or 'off')
        .. ', file : ' .. status.queued .. ', réassemblages : ' .. status.buffers .. ', report : ' .. status.deferred
        .. ', rejets : ' .. status.rejected .. '.')
    Q.Print('Addon : dossier ' .. Q.Safe(Q.name) .. ', version ' .. Q.version .. ', prêt : ' .. tostring(Q.ready) .. '.')
    for context, ms in pairs(Q.slow) do Q.Print('Traitement lent : ' .. Q.Safe(context) .. ' ' .. ms .. ' ms') end
    for _, err in ipairs(Q.errors) do Q.Print('Diagnostic protégé : ' .. Q.Safe(err)) end
end
function Q.Command(message)
    local command, value = message:match('^%s*(%S+)%s*(.-)%s*$')
    if not command then return Q.UI and Quintessence.UI.Open('caract') end
    if command == 'resume' then return Q.Summary() end
    if command == 'debug' then return Q.Debug() end
    if command == 'statistiques' then return Q.RequestStatistics(true, true) end
    if command == 'sync' then
        if not Q.sync then return Q.Print('Synchro indisponible : voir /qcaract debug.') end
        if value == 'on' then Q.sync:SetEnabled(true)
        elseif value == 'off' then Q.sync:SetEnabled(false)
        elseif value == 'now' then Q.sync:Announce()
        else return Q.Print('/qcaract sync on|off|now') end
        return Q.Print('Synchro : ' .. (Q.sync.enabled and 'activée' or 'désactivée'))
    end
    Q.Search(message:match('^%s*(.-)%s*$'))
end
