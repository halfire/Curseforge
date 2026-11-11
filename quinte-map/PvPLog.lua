local _, Q = ...
--[[
  PvPLog.lua : onglet « Log PvP » de la section Officiers du conteneur (rangs 0 et 1), pour vérifier ce que contient le
  journal PvP avant l'envoi au site : les relevés de l'officier et ceux reçus des membres (PvPShare.lua).
  Liste chronologique d'observations, une ligne par déclarant : jamais de total de kills ni de classement.
  Lecture seule : rien n'est modifié ni envoyé depuis cet onglet.
]]
local P = Q.PvP
local L = {}
Q.PvPLog = L
local S = Quintessence.Style

local FILTERS = {
    { id = 'all', label = 'Tout' },
    { id = 'guild', label = 'Reçus' },
    { id = 'mine', label = 'Les miens' },
    { id = 'bg', label = 'BG / arène' },
}
L.FILTERS = FILTERS
local CONFIDENCE = { identified = 'identifié', probable = 'probable', unknown = 'inconnu' }
local FACTION = { [0] = 'Horde', [1] = 'Alliance' }

local function safe(v) return Q.Safe(type(v) == 'string' and v or (v ~= nil and tostring(v) or '')) end
local function display(name) return (type(name) == 'string' and name ~= '') and safe(Quintessence.DisplayName(name)) or 'Inconnu' end
local function who(a)
    if type(a) ~= 'table' then return 'inconnu' end
    local parts = { display(a.name) }
    if type(a.level) == 'number' then parts[#parts + 1] = 'niv. ' .. a.level end
    if type(a.class) == 'string' then parts[#parts + 1] = safe(a.class):lower() end
    return table.concat(parts, ' ')
end
local function where(r)
    local loc, ctx = type(r.location) == 'table' and r.location or {}, type(r.context) == 'table' and r.context or {}
    if ctx.mode == 'battleground' or ctx.mode == 'arena' then return safe(ctx.name or 'BG') end
    local z = loc.zone and safe(loc.zone) or '?'
    if type(loc.x) == 'number' and type(loc.y) == 'number' then z = z .. string.format(' (%.1f, %.1f)', loc.x, loc.y) end
    return z
end
--- Phrase d'un événement ou d'un relevé BG (une observation du déclarant, telle qu'il l'a enregistrée).
function L.Text(r, isMatch)
    if isMatch then
        local status = r.status == 'complete' and 'terminé' or r.status == 'left' and 'quitté' or 'en cours'
        local text = 'Relevé ' .. (r.context and r.context.mode == 'arena' and 'arène' or 'BG') .. ' ' .. safe(r.context and r.context.name or '?') .. ' · ' .. status
        if FACTION[r.winner] then text = text .. ', vainqueur ' .. FACTION[r.winner] end
        return text .. ' · ' .. #(r.scores or {}) .. ' ligne(s) de score' .. (r.scoresPartial and ' (partiel)' or '') .. ' · rév. ' .. tostring(r.revision or '?')
    end
    local ev = type(r.evidence) == 'table' and r.evidence or {}
    local proof = CONFIDENCE[ev.confidence] or '?'
    if r.kind == 'death' then
        if not r.other then return 'Mort · tueur inconnu (' .. proof .. ')' end
        return 'Mort · tué par ' .. who(r.other) .. (r.pvp == false and ' (pas un joueur)' or '') .. ' (' .. proof .. ')'
    elseif r.kind == 'kill' then
        return 'Coup fatal sur ' .. who(r.other) .. (ev.pet and ' (familier)' or '')
    elseif r.kind == 'group_kill' then
        return 'Coup fatal du groupe sur ' .. who(r.other) .. ', porté par ' .. who(ev.killingBlowBy)
    elseif r.kind == 'honor_credit' then
        return 'Victoire honorable (+' .. tostring(ev.delta or '?') .. ')'
    end
    return safe(r.kind)
end
local function moment(r, isMatch)
    if isMatch then return r.endedAt or r.leftAt or r.updatedAt or r.at or 0 end
    return r.at or 0
end
--- Lignes affichées, les plus récentes d'abord.
function L.Rows(filter, query)
    local store, owner = P.Store(), P.Owner()
    local rows = {}
    if not store then return rows end
    local q = (query or ''):lower()
    local function add(list, isMatch, received)
        for _, r in ipairs(list or {}) do
            if type(r) == 'table' then
                local keep = filter == 'all' or (filter == 'guild' and received) or (filter == 'mine' and not received) or (filter == 'bg' and isMatch)
                if keep and q ~= '' then
                    local hay = ((r.reporter and r.reporter.name or '') .. ' ' .. (r.other and r.other.name or '') .. ' '
                        .. (r.evidence and type(r.evidence.killingBlowBy) == 'table' and r.evidence.killingBlowBy.name or '')):lower()
                    keep = hay:find(q, 1, true) ~= nil
                end
                if keep then rows[#rows + 1] = { r = r, match = isMatch, received = received, at = moment(r, isMatch) } end
            end
        end
    end
    add(store.events, false, false); add(store.matches, true, false)
    local g = P.Share and P.Share.Guild()
    if g then add(g.events, false, true); add(g.matches, true, true) end
    table.sort(rows, function(a, b) return a.at > b.at end)
    return rows, owner
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Onglet
-- ---------------------------------------------------------------------------------------------------------------------
local view = { filter = 'all', query = '', offset = 0 }
local panel
local cache = {}
local function rowsFor()
    if cache.rev ~= P.Revision or cache.filter ~= view.filter or cache.query ~= view.query then
        cache.rows = L.Rows(view.filter, view.query)
        cache.rev, cache.filter, cache.query = P.Revision, view.filter, view.query
    end
    return cache.rows
end
local function render(p)
    local rows = rowsFor()
    local n = p.count_rows
    view.offset = math.max(0, math.min(view.offset, math.max(0, #rows - n)))
    p.scroll:SetMinMaxValues(0, math.max(0, #rows - n)); p.scroll:SetValue(view.offset)
    for id, b in pairs(p.filters) do b:SetActive(id == view.filter) end
    p.status:SetText(P.ready and ('Journal PvP v' .. Q.version .. ' : ' .. (P.Share and P.Share.Status() or '')) or 'Journal PvP en attente (guilde ou personnage pas encore lus).')
    p.empty:SetShown(#rows == 0)
    p.count:SetText(#rows .. ' ligne(s)')
    for i, line in ipairs(p.lines) do
        local row = rows[view.offset + i]
        if row then
            local r = row.r
            line.when:SetText(row.at > 0 and date('%d/%m %H:%M', row.at) or '?')
            line.who:SetText((row.received and '' or '|c' .. S.hex.gold .. '') .. display(r.reporter and r.reporter.name) .. (row.received and '' or '|r'))
            line.text:SetText(L.Text(r, row.match))
            line.where:SetText(where(r))
        else line.when:SetText(''); line.who:SetText(''); line.text:SetText(''); line.where:SetText('') end
    end
end
--- Construit la page (appelé par Officers.lua au premier affichage de l'onglet ; W × H = zone sous les onglets).
function L.CreatePanel(parent, W, H)
    W, H = W or 1078, H or 622
    local p = CreateFrame('Frame', nil, parent); p:SetAllPoints(parent)
    local ROWS = math.floor((H - 112) / 22)
    p.count_rows = ROWS
    p.filters = {}
    for i, f in ipairs(FILTERS) do
        local b = S.Button(p, f.label, 92, 24, 'ghost'); b:SetPoint('TOPLEFT', (i - 1) * 96, 0)
        b:SetScript('OnClick', function() view.filter = f.id; view.offset = 0; Q.Run('log PvP', render, p) end)
        p.filters[f.id] = b
    end
    p.search = S.Input(p, 200, 'Chercher un joueur'); p.search:SetPoint('TOPLEFT', #FILTERS * 96 + 8, 0)
    p.search:SetScript('OnTextChanged', function(self) view.query = self:GetText() or ''; view.offset = 0; Q.Run('log PvP', render, p) end)
    p.count = S.Text(p, 11, S.colors.muted, 'RIGHT'); p.count:SetPoint('TOPLEFT', W - 200, -6); p.count:SetWidth(200)
    p.status = S.Text(p, 11, S.colors.muted); p.status:SetPoint('TOPLEFT', 0, -32); p.status:SetWidth(W); p.status:SetWordWrap(true)
    local note = S.Text(p, 11, S.colors.muted); note:SetPoint('TOPLEFT', 0, -50); note:SetWidth(W); note:SetWordWrap(true)
    note:SetText('Observations de chaque déclarant, telles qu’enregistrées (en doré : les tiennes). Les membres les chuchotent aux officiers en ligne ; le site les reçoit avec ton quinte-map.lua (Quinte-sync ou Importer), après un /reload ou une déconnexion.')
    local box = S.Box(p, S.colors.panel, S.colors.line); box:SetPoint('TOPLEFT', 0, -76); box:SetSize(W, ROWS * 22 + 30)
    box:EnableMouseWheel(true)
    box:SetScript('OnMouseWheel', function(_, delta) view.offset = view.offset - delta * 3; Q.Run('log PvP', render, p) end)
    for _, h in ipairs({ { 'Date', 12 }, { 'Déclarant', 112 }, { 'Observation', 292 }, { 'Lieu', W - 250 } }) do
        local t = S.Heading(box, h[1]); t:SetPoint('TOPLEFT', h[2], -8)
    end
    p.lines = {}
    for i = 1, ROWS do
        local y = -30 - (i - 1) * 22
        local line = {}
        line.when = S.Text(box, 11, S.colors.muted); line.when:SetPoint('TOPLEFT', 12, y - 1); line.when:SetWidth(96)
        line.who = S.Text(box, 12); line.who:SetPoint('TOPLEFT', 112, y); line.who:SetWidth(174)
        line.text = S.Text(box, 12); line.text:SetPoint('TOPLEFT', 292, y); line.text:SetWidth(W - 550)
        line.where = S.Text(box, 11, S.colors.muted); line.where:SetPoint('TOPLEFT', W - 250, y - 1); line.where:SetWidth(230)
        p.lines[i] = line
    end
    p.scroll = S.Scrollbar(box, ROWS * 22, function(value)
        if value ~= view.offset then view.offset = value; Q.Run('log PvP', render, p) end
    end)
    p.scroll:SetPoint('TOPLEFT', W - 14, -28)
    p.empty = S.Text(box, 12, S.colors.muted, 'CENTER'); p.empty:SetPoint('TOPLEFT', 60, -160); p.empty:SetWidth(W - 120); p.empty:SetWordWrap(true)
    p.empty:SetText('Rien pour l’instant. Chaque mort, coup fatal ou BG d’un membre qui a la Carte 0.10.0 arrive ici quelques secondes après (hors combat et hors BG), s’il est connecté en même temps qu’un officier ; sinon dès que vous vous croisez en jeu.')
    p.refresh = function() render(p) end
    panel = p
    L.panel = p
    return p
end
function L.Refresh()
    if panel and panel:IsVisible() then render(panel) end
end
if P.Share then P.Share.OnReceived = L.Refresh end

-- Section Officiers du conteneur (1.44.2+) ; rien dans l'édition CurseForge (SOS seul)
local officers = Quintessence.Officers
if officers and officers.AddTab and not Q.SOSOnly() then
    officers.AddTab({ id = 'pvp', label = 'Log PvP', after = 'journal', create = function(body, w, h) return L.CreatePanel(body, w, h) end })
end
