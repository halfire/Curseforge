local _, Q = ...
-- Lecture de l'onglet Statistiques, sans identifiant Retail supposé ni journal de combat.
-- Signatures vérifiées dans Blizzard_AchievementUI (branche Forever) ; voir la notice.
local DELAY, MAX_ROWS, MAX_TEXT = 900, 512, 40000
local messages = {
    ok = 'Statistiques du jeu relevées.', partial = 'Relevé partiel : certaines statistiques ne sont pas disponibles.',
    empty = 'Le jeu ne fournit aucune statistique pour ce personnage.',
    absent = 'API des statistiques absente sur ce client.', restricted = 'Lecture des statistiques restreinte par le jeu.',
    error = 'Le jeu refuse la lecture des statistiques.', pending = 'Lecture des statistiques en cours…',
}
Q.StatisticsMessages = messages
local frame = CreateFrame('Frame')
local snapshot, lastStart, pending, worker, announce
local function inCombat()
    if not InCombatLockdown then return false end
    local ok, value = pcall(InCombatLockdown)
    return not ok or Q.Secret(value) or value
end
local function read(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if not ok then error('error', 0) end
    if Q.Secret(a) or Q.Secret(b) or Q.Secret(c) then error('restricted', 0) end
    return a, b, c
end
local function scan()
    for _, name in ipairs({'GetStatisticsCategoryList', 'GetCategoryInfo', 'GetCategoryNumAchievements', 'GetStatistic', 'GetAchievementInfo'}) do
        if type(_G[name]) ~= 'function' then error('absent', 0) end
    end
    local categories = read(GetStatisticsCategoryList)
    if type(categories) ~= 'table' then error('empty', 0) end
    local result = {at = Q.Now(), state = 'ok', categories = {}, rows = {}}
    local seen, seenCats, bytes, steps = {}, {}, 0, 0
    local function pause()
        steps = steps + 1
        if steps % 8 == 0 then coroutine.yield() end
    end
    for index, category in ipairs(categories) do
        if index > 128 then result.state = 'partial'; break end
        category = Q.Number(category, 1, 1e9, true)
        if not category then result.state = 'partial'
        elseif not seenCats[category] then
            seenCats[category] = true
            local label = Q.String(read(GetCategoryInfo, category), 100)
            local count = Q.Number(read(GetCategoryNumAchievements, category), 0, 4096, true)
            if not label or not count then result.state = 'partial'
            else
                if bytes + #label > MAX_TEXT then result.state = 'partial'; return result end
                result.categories[category] = label; bytes = bytes + #label
                for i = 1, count do
                    local value, skip, id = read(GetStatistic, category, i)
                    id = Q.Number(id, 1, 1e9, true)
                    if not skip then
                        if id and not seen[id] then
                            local actual, name = read(GetAchievementInfo, id)
                            name, value = Q.String(name, 100), Q.String(value, 100)
                            if actual == id and name and value and value ~= '--' then
                                if #result.rows >= MAX_ROWS or bytes + #name + #value > MAX_TEXT then
                                    result.state = 'partial'; return result
                                end
                                seen[id] = true; bytes = bytes + #name + #value
                                result.rows[#result.rows + 1] = {id, category, name, value}
                            else result.state = 'partial' end
                        elseif not id then result.state = 'partial' end
                    end
                    pause()
                    if steps >= 8192 then result.state = 'partial'; return result end
                end
            end
            pause()
        end
    end
    if #result.rows == 0 and result.state == 'ok' then result.state = 'empty' end
    return result
end
local function finish(result, state)
    worker = nil; frame:SetScript('OnUpdate', nil)
    Q.statisticsState = state or result.state
    -- Une erreur temporaire ne détruit jamais le dernier relevé réussi.
    if not snapshot then
        local old = QuinteCaractDB and QuinteCaractDB.characters[Q.Key()]
        snapshot = old and old.gameStats
    end
    -- Ne pas rediffuser des centaines de compteurs uniquement pour avancer leur date.
    if result and snapshot and result.state == snapshot.state and Q.Equal(result.categories, snapshot.categories)
        and Q.Equal(result.rows, snapshot.rows) then result = snapshot end
    if result and (#result.rows > 0 or not snapshot or #snapshot.rows == 0) then snapshot = result end
    if not snapshot then snapshot = {at = Q.Now(), state = state, categories = {}, rows = {}} end
    if Q.Schedule then Q.Schedule() end
    if Q.UI then Q.UI.OnDataChanged() end
    if announce then
        Q.Print((messages[Q.statisticsState] or messages.error) .. ' ' .. #(snapshot.rows or {}) .. ' ligne(s) conservée(s).')
        announce = nil
    end
end
local function step()
    if inCombat() then return end
    local ok, result = coroutine.resume(worker)
    if not ok then
        finish(nil, messages[result] and result or 'error')
    elseif coroutine.status(worker) == 'dead' then finish(result) end
end
function Q.RequestStatistics(force, report)
    announce = announce or report
    if worker then return end
    if inCombat() then
        Q.statisticsState = 'restricted'
        if report then Q.Print(messages.restricted .. ' Lecture reprise après le combat.'); announce = nil end
        pending = true; return
    end
    local wait = lastStart and (DELAY - (Q.Now() - lastStart)) or 0
    if not force and wait > 0 then
        if not pending and C_Timer and C_Timer.After then
            pending = true
            C_Timer.After(wait, function() pending = nil; Q.RequestStatistics() end)
        end
        return
    end
    lastStart = Q.Now(); Q.statisticsState = 'pending'
    worker = coroutine.create(scan)
    frame:SetScript('OnUpdate', step)
end
function Q.CollectGameStatistics()
    if snapshot then return snapshot end
    local old = QuinteCaractDB and QuinteCaractDB.characters[Q.Key()]
    return old and old.gameStats or nil
end
function Q.StatisticsLines(c)
    local s = c.gameStats
    local lines = {s and (messages[s.state] or messages.error) or 'Statistiques pas encore relevées.'}
    if not s then return lines end
    lines[#lines + 1] = 'Valeurs fournies par le jeu ; date du relevé : ' .. (date and date('%d/%m/%Y %H:%M', s.at) or s.at)
    for _, row in ipairs(s.rows) do
        lines[#lines + 1] = Q.Safe(s.categories[row[2]] or '?') .. ' : ' .. Q.Safe(row[3]) .. ' — ' .. Q.Safe(row[4])
    end
    return lines
end
for _, event in ipairs({'PLAYER_LOGIN', 'CRITERIA_UPDATE', 'PLAYER_REGEN_ENABLED'}) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript('OnEvent', function(_, event)
    if not Q.ready or Q.disabled then return end
    if event == 'PLAYER_LOGIN' then
        if C_Timer and C_Timer.After then
            local function refresh()
                Q.RequestStatistics()
                C_Timer.After(DELAY, refresh)
            end
            C_Timer.After(5, refresh)
        end
    elseif event == 'PLAYER_REGEN_ENABLED' then
        if pending then pending = nil; Q.RequestStatistics() end
    else Q.RequestStatistics() end
end)
