local _, Core = ...
--[[
  Diagnostic.lua (1.52.11, T252) : fenêtre de diagnostic, ouverte par /quinte debug (/quinte debug chat : l'ancien
  résumé dans le chat). Tout l'état utile à un dépannage dans une grande zone de texte à copier (Tout sélectionner puis
  Ctrl+C) : version et jeu, écart entre l'horloge du PC et celle du serveur, guilde, synchro complète (compteurs, file,
  résumés par groupe), trafic de la dernière heure, une section par module (Core.RegisterDiagnostic), versions, erreurs
  de la session et historique des erreurs de 10 jours. Lecture seule : rien n'est envoyé, sauvegardé ni lu par le site.
]]
local D = {}
Core.Diagnostic = D
local W, H = 760, 520
local page
local sections = {}

--- Section d'un module : fn() renvoie une liste de lignes (texte). Appelée dans un pcall : une erreur n'empêche pas le reste.
function Core.RegisterDiagnostic(id, title, fn)
    if type(id) ~= 'string' or type(fn) ~= 'function' then return false end
    for _, s in ipairs(sections) do
        if s.id == id then s.title, s.fn = tostring(title or id), fn; return true end
    end
    sections[#sections + 1] = { id = id, title = tostring(title or id), fn = fn }
    return true
end
-- (même fonction appelée en méthode : Quintessence:RegisterDiagnostic(...))
local plainRegister = Core.RegisterDiagnostic
Core.RegisterDiagnostic = function(a, ...)
    if a == Core then return plainRegister(...) end
    return plainRegister(a, ...)
end

local function secret(v) return type(issecretvalue) == 'function' and issecretvalue(v) end
local function txt(v)
    if secret(v) then return '(secret)' end
    if v == nil then return '—' end
    return tostring(v)
end
local function when(t)
    t = tonumber(t)
    if not t or not date then return '?' end
    return date('%d/%m %H:%M:%S', t)
end
D.When = when
--- Âge lisible : « 3 min », « 5 h », « 2 j »
function D.Ago(t, now)
    t = tonumber(t)
    if not t then return '?' end
    local d = (now or Core.Now()) - t
    if d < 0 then return 'dans ' .. math.floor(-d) .. ' s (futur)' end
    if d < 120 then return math.floor(d) .. ' s' end
    if d < 7200 then return math.floor(d / 60) .. ' min' end
    if d < 172800 then return math.floor(d / 3600) .. ' h' end
    return math.floor(d / 86400) .. ' j'
end
local function call(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function header(lines)
    local ok, version, number, _, toc = false, nil, nil, nil, nil
    if type(GetBuildInfo) == 'function' then ok, version, number, _, toc = pcall(GetBuildInfo) end
    if not ok then version, number, toc = nil, nil, nil end
    local who = Core.PlayerName and call(Core.PlayerName) or call(UnitName, 'player')
    lines[#lines + 1] = 'Quintessence ' .. Core.version .. ' · jeu ' .. txt(version) .. ' (' .. txt(number) .. ', interface ' .. txt(toc) .. ') · '
        .. txt(who) .. ' · ' .. when(Core.Now())
    lines[#lines + 1] = 'Clé ' .. txt(Core.Key and call(Core.Key)) .. ' · édition ' .. txt(Core.Edition and call(Core.Edition) or 'site')
        .. ' · thème ' .. txt(Core.Style and Core.Style.theme) .. ' · langue ' .. txt(call(GetLocale))
    -- Le client Forever 71037 ne donne plus le royaume : celui des clés est alors repris de nos personnages connus
    local lib = LibStub and LibStub('LibQuinteSync-1.0', true)
    local game = lib and lib.GameRealm and call(lib.GameRealm)
    lines[#lines + 1] = 'Royaume : jeu « ' .. txt(game) .. ' » · clés « ' .. txt(Core.Realm and call(Core.Realm)) .. ' »'
        .. ((game == '' and (Core.Realm and call(Core.Realm) or '') ~= '') and ' (retrouvé dans tes personnages)'
            or (game == '' and '  << royaume caché par le jeu et introuvable' or ''))
    -- Les fiches et le craft sont datés à l'horloge du PC ; les autres refusent une donnée datée de plus de 5 min dans le futur
    local pc, server = call(time), call(GetServerTime)
    if pc and server then
        local gap = pc - server
        lines[#lines + 1] = 'Horloge : PC ' .. when(pc) .. ' · serveur ' .. when(server) .. ' · écart ' .. gap .. ' s'
            .. (math.abs(gap) > 120 and '  << ATTENTION : heure du PC fausse, régler l’heure automatique' or ' (correct)')
    else
        lines[#lines + 1] = 'Horloge : PC ' .. when(pc) .. ' · serveur ' .. txt(server)
    end
end

local function modules(lines)
    local names = {}
    for _, m in ipairs(Core:ModuleList()) do names[#names + 1] = m.id .. ' ' .. txt(m.version) end
    lines[#lines + 1] = (#names > 0 and table.concat(names, ', ') or 'aucun module')
end

local function guild(lines)
    local status, name = 'inconnu', nil
    if Core.GuildStatus then status, name = Core.GuildStatus() end
    local officer = Core.Announce and Core.Announce.IsOfficer and call(Core.Announce.IsOfficer)
    local inGuild = call(IsInGuild)
    lines[#lines + 1] = 'Guilde : ' .. txt(name) .. ' · statut ' .. txt(status) .. ' · dans une guilde ' .. txt(inGuild)
        .. ' · officier ' .. (officer and 'oui' or 'non') .. ' · membres dans la liste du jeu ' .. txt(call(GetNumGuildMembers))
end

local function sync(lines)
    local s = Core.sync
    if not s then lines[#lines + 1] = 'Synchro non démarrée.'; return end
    local st = s:Status()
    lines[#lines + 1] = 'Activée ' .. txt(st.enabled) .. ' · retenue ' .. txt(st.deferred) .. ' · préfixe ' .. txt(st.prefix)
        .. ' · ChatThrottleLib ' .. txt(st.ctl) .. (ChatThrottleLib and ChatThrottleLib.bQueueing and ' (file en attente)' or '')
        .. ' · noms régionaux ' .. txt(st.regional) .. ' · moi ' .. txt(st.player)
    lines[#lines + 1] = 'Envois ' .. txt(st.sent) .. ' · échecs ' .. txt(st.failed) .. ' · nouveaux essais ' .. txt(st.retries)
        .. ' · dernier code ' .. txt(Core.ResultName and call(Core.ResultName, st.lastResult) or st.lastResult)
        .. ' · file ' .. txt(st.queued) .. ' · file pleine ' .. txt(st.full) .. ' · destinataires hors ligne ' .. txt(st.offline)
    lines[#lines + 1] = 'Reçus ' .. txt(st.received) .. ' (dernier : ' .. txt(st.lastFrom) .. ') · réassemblages ' .. txt(st.buffers)
        .. ' · gardés pour plus tard ' .. txt(st.waiting) .. ' · perdus ' .. txt(st.lost) .. ' · refusés ' .. txt(st.rejected)
        .. ' · inconnus ' .. txt(st.strangers)
    lines[#lines + 1] = 'Liste de guilde : ' .. txt(st.roster) .. ' membres' .. (st.rosterKnown and '' or ' (pas encore reçue)')
        .. ' · demandes en cours ' .. txt(st.pending) .. ' · demandes en attente ' .. txt(st.wants)
        .. ' · membres entendus ' .. txt(LibStub and LibStub('LibQuinteSync-1.0', true) and call(LibStub('LibQuinteSync-1.0').Heard))
    local restricted = C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
    if restricted then lines[#lines + 1] = 'Indicateur de restriction du jeu : ' .. txt(call(restricted)) .. ' (ignoré)' end
    local groups = s.Groups and s:Groups() or {}
    for _, group in ipairs(groups) do
        local scan = s:Scan(group)
        lines[#lines + 1] = '  groupe ' .. group .. ' : ' .. txt(scan and scan.n) .. ' entrée(s) · résumé ' .. txt(scan and scan.summary)
    end
    local m = st.messages or {}
    local kinds = {}
    for kind, n in pairs(m) do kinds[#kinds + 1] = kind .. '=' .. n end
    table.sort(kinds)
    if #kinds > 0 then lines[#lines + 1] = 'Messages préparés depuis la connexion : ' .. table.concat(kinds, ' ') end
end

local KIND = { S = 'résumé', H = 'bonjour', A = 'réponse au bonjour', W = 'demande de liste', M = 'liste', U = 'changement',
    R = 'demande', D = 'données', P = 'ping', O = 'réponse au ping', X = 'temps réel' }
local function traffic(lines)
    if not (Core.sync and Core.sync.Traffic) then lines[#lines + 1] = 'Synchro non démarrée.'; return end
    local rows = Core.sync:Traffic()
    local LABEL = { queued = 'préparé', out = 'envoyé', ['in'] = 'reçu' }
    if #rows == 0 then lines[#lines + 1] = 'Aucun message cette heure.' end
    for _, dir in ipairs({ 'out', 'in', 'queued' }) do
        for _, row in ipairs(rows) do
            if row.dir == dir then
                local kind, what = tostring(row.name):match('^(%u):?(.*)$')
                lines[#lines + 1] = string.format('  %s %s%s · %s : %d message(s), %.1f Ko', LABEL[dir] or dir, KIND[kind or ''] or txt(row.name),
                    (what and what ~= '') and (' ' .. what) or '', txt(row.channel), tonumber(row.messages) or 0, (tonumber(row.bytes) or 0) / 1024)
            end
        end
    end
end

--- Texte complet à copier.
function D.Report()
    local lines = {}
    local function section(title, fn)
        lines[#lines + 1] = ''
        lines[#lines + 1] = '== ' .. title
        local ok, err = pcall(fn, lines)
        if not ok then lines[#lines + 1] = '(section illisible : ' .. tostring(err) .. ')' end
    end
    local ok, err = pcall(header, lines)
    if not ok then lines[#lines + 1] = '(en-tête illisible : ' .. tostring(err) .. ')' end
    section('Modules', modules)
    section('Guilde', guild)
    section('Synchro', sync)
    section('Trafic de la dernière heure', traffic)
    for _, s in ipairs(sections) do
        section(s.title, function(out)
            local result = s.fn()
            for _, l in ipairs(type(result) == 'table' and result or { tostring(result) }) do out[#out + 1] = tostring(l) end
        end)
    end
    section('Versions', function(out)
        out[#out + 1] = Core.Versions and Core.Versions.Summary and txt(Core.Versions.Summary()) or '—'
    end)
    section('Traitements lents et erreurs de la session', function(out)
        for context, ms in pairs(Core.debug.slow) do out[#out + 1] = 'lent : ' .. txt(context) .. ' ' .. ms .. ' ms' end
        for _, e in ipairs(Core.debug.errors) do out[#out + 1] = 'erreur : ' .. txt(e) end
        if not next(Core.debug.slow) and #Core.debug.errors == 0 then out[#out + 1] = 'rien' end
    end)
    section('Historique des erreurs', function(out)
        local text = Core.ErrorPage and Core.ErrorPage.Report and Core.ErrorPage.Report() or '—'
        for l in tostring(text):gmatch('[^\n]*') do out[#out + 1] = l end
    end)
    return table.concat(lines, '\n')
end

local function create()
    local S = Core.Style
    page = S.Dialog('Diagnostic de Quintessence', W, H)
    page.sub = S.Text(page, S.size.sm, S.colors.muted); page.sub:SetPoint('TOPLEFT', 12, -36); page.sub:SetWidth(W - 24)
    page.sub:SetText('À copier tel quel pour le GM ou Discord : synchro, modules, versions et erreurs. Rien n’est envoyé.')
    page.edit = S.TextArea(page, W - 24, H - 110, 0)
    page.edit.container:SetPoint('TOPLEFT', 12, -56)
    if page.edit.SetMaxLetters then page.edit:SetMaxLetters(0) end
    -- Lecture seule : une frappe remet le texte
    page.edit:SetScript('OnTextChanged', function(self, user)
        if user and page.report then self:SetText(page.report); self:HighlightText() end
    end)
    page.select = S.Button(page, 'Tout sélectionner', 150, 26, 'primary')
    page.select:SetPoint('BOTTOMLEFT', 12, 12)
    page.select:SetScript('OnClick', function() page.edit:SetFocus(); page.edit:HighlightText() end)
    page.hint = S.Text(page, S.size.sm, S.colors.muted); page.hint:SetPoint('LEFT', page.select, 'RIGHT', 10, 0)
    page.hint:SetText('puis Ctrl+C (Cmd+C sur Mac) pour copier')
    page.reload = S.Button(page, 'Actualiser', 100, 26, 'ghost'); page.reload:SetPoint('BOTTOMRIGHT', -12, 12)
    page.reload:SetScript('OnClick', function() D.Refresh() end)
    page.syncNow = S.Button(page, 'Relancer la synchro', 160, 26, 'ghost'); page.syncNow:SetPoint('RIGHT', page.reload, 'LEFT', -8, 0)
    page.syncNow:SetScript('OnClick', function()
        if Core.sync and Core.sync.Recover then
            Core.sync.recoveredAt = nil -- (Recover se limite à une fois par 10 min ; ici, à la demande du joueur)
            Core.Run('relance de la synchro', Core.sync.Recover, Core.sync)
            Core.Print('Synchro relancée : bonjour envoyé à la guilde, rattrapage complet en cours.')
        end
        D.Refresh()
    end)
end

function D.Refresh()
    if not page then return end
    local text = D.Report()
    page.report = text
    page.edit:SetText(text)
    local lines = select(2, text:gsub('\n', '\n')) + 1
    page.edit:SetHeight(math.max(H - 114, lines * 15 + 8))
    if page.edit.SetCursorPosition then page.edit:SetCursorPosition(0) end
    if page.edit.scroll and page.edit.scroll.SetVerticalScroll then page.edit.scroll:SetVerticalScroll(0) end
end

function D.Open()
    if not page then create() end
    D.Refresh()
    page:Show()
    return true
end
function D.Frame() return page end
