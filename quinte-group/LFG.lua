local _, Q = ...
local Core, S = Quintessence, Quintessence.Style
local PAGE_SIZE = 5
local roles = {
    { label = 'Tous les rôles' },
    { label = 'Place de tank', key = 'TANK', solo = 'tank', needed = 1 },
    { label = 'Place de soigneur', key = 'HEALER', solo = 'healer', needed = 1 },
    { label = 'Place de DPS', key = 'DAMAGER', solo = 'dps', needed = 3 },
}

-- Les données du Cherche-groupe peuvent devenir secrètes en instance.
local function readable(value, kind)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) == kind then return value end
end

local function read(fn, kind, ...)
    local ok, value = Q.Call(fn, ...)
    if ok then return readable(value, kind) end
end

local function listing(id)
    local info = read(C_LFGList.GetSearchResultInfo, 'table', id)
    if not info or readable(info.isDelisted, 'boolean') == true then return end
    return info
end

local function activityNames(info)
    local names = {}
    for _, value in ipairs(readable(info.activityIDs, 'table') or {}) do
        local id = readable(value, 'number')
        local activity = id and read(C_LFGList.GetActivityInfoTable, 'table', id)
        if activity then
            local name = read(LFGUtil_GetActivityInfoName, 'string', activity)
                or readable(activity.fullName, 'string') or readable(activity.shortName, 'string')
            if name and name ~= '' then names[#names + 1] = name end
        end
    end
    return table.concat(names, ' · ')
end

local function contact(info)
    -- Exiger un indicateur explicite pour éviter les actions sur une annonce illisible.
    if readable(info.hasSelf, 'boolean') ~= false or readable(info.isDelisted, 'boolean') ~= false then return end
    local name = readable(info.leaderName, 'string')
    if name and name ~= '' and not Core.SameName(name, Core.PlayerName()) then return name end
end

local function canInvite(id, info)
    if readable(info.numMembers, 'number') ~= 1 then return false end
    if LFGBrowseUtil_GetInviteActionForResult then
        local ok, _, action = Q.Call(LFGBrowseUtil_GetInviteActionForResult, id)
        return ok and readable(action, 'function') ~= nil
    end
    local inGroup = read(IsInGroup, 'boolean')
    if inGroup == false then return true end
    return read(UnitIsGroupLeader, 'boolean', 'player') == true
        and read(IsInRaid, 'boolean') == false
end

local function roleMatches(id, info, role)
    if not role.key then return true end
    local dungeon
    for _, value in ipairs(readable(info.activityIDs, 'table') or {}) do
        local activityID = readable(value, 'number')
        local activity = activityID and read(C_LFGList.GetActivityInfoTable, 'table', activityID)
        if activity and readable(activity.maxNumPlayers, 'number') == 5 then dungeon = true; break end
    end
    local size = readable(info.numMembers, 'number')
    if not dungeon or not size or size >= 5 then return false end
    if size == 1 then
        local player = read(C_LFGList.GetSearchResultPlayerInfo, 'table', id, 1)
        local available = player and readable(player.lfgRoles, 'table')
        return available and readable(available[role.solo], 'boolean') == true
    end
    local counts = read(C_LFGList.GetSearchResultMemberCounts, 'table', id)
    local count = counts and readable(counts[role.key], 'number')
    return count and count < role.needed
end

function Q.CreateLFGPanel(parent)
    if Q.LFGForever then return Q.LFGForever.CreateEmbeddedPanel(parent) end
    local panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints()
    local roleIndex, page = 1, 1
    local rows, ids = {}, {}
    local completed, failure
    local search = S.Button(panel, 'Actualiser les annonces', 220, 28, 'primary')
    search:SetPoint('TOPLEFT', 0, 0)
    local filter = S.Input(panel, 230, 'Activité, joueur ou annonce')
    filter:SetPoint('LEFT', search, 'RIGHT', 12, 0)
    local role = S.Button(panel, roles[1].label, 155, 28, 'ghost')
    role:SetPoint('LEFT', filter, 'RIGHT', 8, 0)

    local status = S.Text(panel, 12, S.colors.muted)
    status:SetPoint('TOPLEFT', 2, -39)
    local previous = S.Button(panel, 'Précédent', 95, 24, 'ghost')
    previous:SetPoint('TOPLEFT', 0, -56)
    local nextPage = S.Button(panel, 'Suivant', 95, 24, 'ghost')
    nextPage:SetPoint('LEFT', previous, 'RIGHT', 8, 0)
    local pageLabel = S.Text(panel, 12, S.colors.muted)
    pageLabel:SetPoint('LEFT', nextPage, 'RIGHT', 10, 0)

    local function render()
        if not panel:IsVisible() then return end
        local matches = {}
        local query = filter:GetText():lower()
        for _, id in ipairs(ids) do
            local info = listing(id)
            if info and roleMatches(id, info, roles[roleIndex]) then
                local title = readable(info.name, 'string') or 'Annonce du Cherche-groupe'
                local comment = readable(info.comment, 'string') or ''
                local leader = readable(info.leaderName, 'string') or ''
                local activities = activityNames(info)
                local haystack = table.concat({ title, leader, activities, comment }, ' '):lower()
                if haystack:find(query, 1, true) then
                    matches[#matches + 1] = { id = id, title = title, info = info,
                        comment = comment, leader = leader, activities = activities }
                end
            end
        end
        local pages = math.max(1, math.ceil(#matches / PAGE_SIZE))
        page = math.min(page, pages)
        previous:SetEnabled(page > 1)
        nextPage:SetEnabled(page < pages)
        pageLabel:SetText(page .. ' / ' .. pages)
        status:SetText(failure
            or (not completed and 'Aucune annonce chargée sur ce client.')
            or (#matches == 0 and 'Aucune annonce ne correspond aux filtres.')
            or (#matches .. ' annonce(s)'))
        for index, row in ipairs(rows) do
            local entry = matches[(page - 1) * PAGE_SIZE + index]
            row.entry = entry
            row:SetShown(entry ~= nil)
            if entry then
                local size = readable(entry.info.numMembers, 'number')
                row.title:SetText(Q.Safe(entry.activities ~= '' and entry.activities or entry.title))
                local details = {}
                if entry.leader ~= '' then details[#details + 1] = entry.leader end
                if size then details[#details + 1] = size == 1 and 'Joueur seul' or (size .. ' membres') end
                if entry.title ~= entry.activities and entry.activities ~= '' then details[#details + 1] = entry.title end
                if entry.comment ~= '' then details[#details + 1] = entry.comment end
                row.details:SetText(Q.Safe(table.concat(details, ' · ')))
                local name = contact(entry.info)
                row.whisper:SetShown(name ~= nil)
                row.whisper:SetLabel(size == 1 and 'Chuchoter' or 'Demander à rejoindre')
                row.invite:SetShown(name ~= nil and canInvite(entry.id, entry.info))
            end
        end
    end

    local function act(row, invite)
        local entry = row.entry
        if not entry or not row:IsVisible() or Core.GuildStatus() ~= 'ok' then return end
        local info = listing(entry.id)
        local name = info and contact(info)
        if not name or not Core.SameName(name, entry.leader) then return render() end
        if invite then
            if canInvite(entry.id, info) and not (InCombatLockdown and InCombatLockdown()) then Core.Invite(name) end
        else
            Core.Whisper(name)
        end
    end

    for index = 1, PAGE_SIZE do
        local row = S.Box(panel, S.colors.panel, S.colors.line)
        row:SetPoint('TOPLEFT', 0, -88 - (index - 1) * 47)
        row:SetPoint('RIGHT', panel, 'RIGHT', 0, 0)
        row:SetHeight(42)
        row.title = S.Text(row, 13, S.colors.gold)
        row.title:SetPoint('TOPLEFT', 10, -5)
        row.title:SetPoint('RIGHT', row, 'RIGHT', -263, 0)
        row.details = S.Text(row, 11, S.colors.text)
        row.details:SetPoint('BOTTOMLEFT', 10, 5)
        row.details:SetPoint('RIGHT', row.title, 'RIGHT', 0, 0)
        row.invite = S.Button(row, 'Inviter', 76, 25, 'ghost')
        row.invite:SetPoint('RIGHT', -8, 0)
        row.whisper = S.Button(row, 'Chuchoter', 158, 25, 'ghost')
        row.whisper:SetPoint('RIGHT', row.invite, 'LEFT', -7, 0)
        row.invite:SetScript('OnClick', function() act(row, true) end)
        row.whisper:SetScript('OnClick', function() act(row, false) end)
        row:Hide()
        rows[index] = row
    end

    local function collect()
        local ok, _, results = Q.Call(C_LFGList.GetFilteredSearchResults)
        ids = {}
        for _, value in ipairs(ok and readable(results, 'table') or {}) do
            local id = readable(value, 'number')
            if id then ids[#ids + 1] = id end
        end
    end

    search:SetScript('OnClick', function()
        if Core.GuildStatus() ~= 'ok' then return end
        if C_LFGList then collect() end
        completed, failure, page = true, nil, 1
        render()
    end)
    role:SetScript('OnClick', function()
        roleIndex, page = roleIndex % #roles + 1, 1
        role:SetLabel(roles[roleIndex].label)
        render()
    end)
    previous:SetScript('OnClick', function() page = math.max(1, page - 1); render() end)
    nextPage:SetScript('OnClick', function() page = page + 1; render() end)
    filter:SetScript('OnTextChanged', function(self)
        self.placeholder:SetShown(self:GetText() == '')
        page = 1
        render()
    end)
    filter:SetScript('OnEscapePressed', function(self) self:ClearFocus() end)

    panel:SetScript('OnShow', function()
        if C_LFGList and not failure then collect() end
        if #ids > 0 then completed = true end
        render()
    end)
    if C_LFGList and type(C_LFGList.GetFilteredSearchResults) == 'function' then
        panel:RegisterEvent('LFG_LIST_SEARCH_RESULTS_RECEIVED')
        panel:RegisterEvent('LFG_LIST_SEARCH_FAILED')
        panel:RegisterEvent('LFG_LIST_SEARCH_RESULT_UPDATED')
        panel:RegisterEvent('REPORT_PLAYER_RESULT')
        panel:SetScript('OnEvent', function(_, event)
            if event == 'LFG_LIST_SEARCH_FAILED' then
                ids, completed, failure, page = {}, false, 'La recherche a échoué dans WoW.', 1
            elseif event == 'LFG_LIST_SEARCH_RESULTS_RECEIVED' then
                completed, failure, page = true, nil, 1
                collect()
            elseif completed then
                collect()
            end
            render()
        end)
    end
    return panel
end
