local _, Core = ...
--[[
  ErrorLog.lua (1.52.0, T223) : page secrète des erreurs, ouverte seulement par /quinte erreurs (jamais dans la barre
  latérale). Historique des 10 derniers jours (QuintessenceDB.errorLog, écrit par Core.LogError) dans une grande zone
  de texte : Tout sélectionner puis Ctrl+C pour le copier-coller (Discord, message au GM). Les addons de la suite y
  envoient aussi leurs erreurs (Quintessence.LogError), et les erreurs Lua non rattrapées d'un addon Quintessence
  sont notées par le gestionnaire d'erreurs du jeu (le précédent est toujours rappelé ensuite).
  Local seulement : rien n'est synchronisé ni lu par le site.
]]
local P = {}
Core.ErrorPage = P
local W, H = 680, 460
local page

local function when(t)
    t = tonumber(t)
    if not t or not date then return '?' end
    return date('%d/%m %H:%M:%S', t)
end

--- Texte complet à copier : en-tête (version, jeu, personnage) puis une entrée par erreur, la plus récente en haut.
function P.Report()
    local log = Core.ErrorLog()
    local lines = {}
    local okB, version, number = false, nil, nil
    if GetBuildInfo then okB, version, number = pcall(GetBuildInfo) end
    local build = okB and (tostring(version) .. ' (' .. tostring(number) .. ')') or '?'
    local okW, who = false, nil
    if UnitName then okW, who = pcall(UnitName, 'player') end
    who = okW and who or '?'
    lines[#lines + 1] = 'Quintessence ' .. Core.version .. ' · jeu ' .. tostring(build) .. ' · ' .. tostring(who) .. ' · ' .. when(Core.Now())
    lines[#lines + 1] = #log .. ' erreur' .. (#log > 1 and 's' or '') .. ' sur les ' .. Core.ERROR_DAYS .. ' derniers jours'
    for i = #log, 1, -1 do
        local e = log[i]
        local n = tonumber(e.n) or 1
        lines[#lines + 1] = ''
        lines[#lines + 1] = '[' .. when(e.last or e.at) .. '] ' .. tostring(e.src or '?') .. ' ' .. tostring(e.v or '')
            .. (n > 1 and (' · ' .. n .. ' fois depuis le ' .. when(e.at)) or '')
        lines[#lines + 1] = tostring(e.text)
        if type(e.stack) == 'string' and e.stack ~= '' then
            for l in e.stack:gmatch('[^\n]+') do lines[#lines + 1] = '    ' .. l end
        end
    end
    return table.concat(lines, '\n'), #log
end

local function create()
    local S = Core.Style
    page = S.Dialog('Erreurs de Quintessence', W, H)
    page.sub = S.Text(page, S.size.sm, S.colors.muted); page.sub:SetPoint('TOPLEFT', 12, -36); page.sub:SetWidth(W - 24)
    page.edit = S.TextArea(page, W - 24, H - 110, 0)
    page.edit.container:SetPoint('TOPLEFT', 12, -56)
    if page.edit.SetMaxLetters then page.edit:SetMaxLetters(0) end
    -- Lecture seule : une frappe remet le texte (on peut sélectionner et copier, pas modifier)
    page.edit:SetScript('OnTextChanged', function(self, user)
        if user and page.report then self:SetText(page.report); self:HighlightText() end
    end)
    page.select = S.Button(page, 'Tout sélectionner', 150, 26, 'primary')
    page.select:SetPoint('BOTTOMLEFT', 12, 12)
    page.select:SetScript('OnClick', function() page.edit:SetFocus(); page.edit:HighlightText() end)
    page.hint = S.Text(page, S.size.sm, S.colors.muted); page.hint:SetPoint('LEFT', page.select, 'RIGHT', 10, 0)
    page.hint:SetText('puis Ctrl+C (Cmd+C sur Mac) pour copier')
    page.clear = S.Button(page, 'Vider', 90, 26, 'ghost'); page.clear:SetPoint('BOTTOMRIGHT', -12, 12)
    page.clear:SetScript('OnClick', function() Core.ShowErrors('vider') end)
    page.reload = S.Button(page, 'Actualiser', 100, 26, 'ghost'); page.reload:SetPoint('RIGHT', page.clear, 'LEFT', -8, 0)
    page.reload:SetScript('OnClick', function() P.Refresh() end)
end

function P.Refresh()
    if not page then return end
    local text, n = P.Report()
    page.report = text
    page.edit:SetText(text)
    local lines = select(2, text:gsub('\n', '\n')) + 1
    page.edit:SetHeight(math.max(H - 114, lines * 15 + 8))
    if page.edit.SetCursorPosition then page.edit:SetCursorPosition(0) end
    if page.edit.scroll and page.edit.scroll.SetVerticalScroll then page.edit.scroll:SetVerticalScroll(0) end
    page.sub:SetText(n == 0 and 'Aucune erreur ces ' .. Core.ERROR_DAYS .. ' derniers jours.'
        or (n .. ' erreur' .. (n > 1 and 's' or '') .. ' sur ' .. Core.ERROR_DAYS .. ' jours, la plus récente en haut. Une erreur répétée n’apparaît qu’une fois, avec son nombre.'))
end

function P.Open()
    if not page then create() end
    P.Refresh()
    page:Show()
    return true
end
function P.Frame() return page end

-- Erreurs Lua non rattrapées venant d'un addon de la suite : notées, puis passées au gestionnaire d'avant (BugSack…)
function P.InstallHandler()
    if type(geterrorhandler) ~= 'function' or type(seterrorhandler) ~= 'function' or P.installed then return end
    P.installed = true
    local previous = geterrorhandler()
    seterrorhandler(function(message, ...)
        local text = tostring(message)
        local low = text:lower()
        if low:find('addons[\\/]quinte') then
            local stack = type(debugstack) == 'function' and select(2, pcall(debugstack, 3, 12, 0)) or nil
            pcall(Core.LogError, (low:match('addons[\\/](quinte[%w%-]*)')) or 'Quintessence', 'erreur Lua', text, stack)
        end
        if type(previous) == 'function' then return previous(message, ...) end
    end)
end
P.InstallHandler()
