-- Intégration Quintessence, adaptée de LFG Forever 2.2.0 (Artefius, GPLv3).
local _, Q = ...
local LFGF = Q.LFGForever
if not LFGF then return end

local Core, S, L = Quintessence, Quintessence.Style, LFGF.L
local NATIVE_ADDON = 'Blizzard_GroupFinder_VanillaStyle'
local WIDTH, HEIGHT = 1165, 623
local tab

-- T241 : jamais GroupFinderVanillaStyle_LoadUI ni LFGVanilla_ToggleFrame depuis l'addon. Le jeu charge lui-même son
-- Cherche-groupe à l'entrée dans le monde ; le charger ou l'ouvrir depuis notre code contaminait le gestionnaire de
-- fenêtres du jeu, puis les barres d'action (ADDON_ACTION_BLOCKED quinte-group -> MultiBar…, StanceBar…, trace du GM
-- du 19/11). On attend donc son chargement par le jeu, et le joueur ouvre la recherche de WoW lui-même.
local prepare
local function loadNative() return C_AddOns.IsAddOnLoaded(NATIVE_ADDON) == true end
local waiting = false
local function waitNative()
    if waiting or not (EventUtil and EventUtil.ContinueOnAddOnLoaded) then return end
    waiting = true
    EventUtil.ContinueOnAddOnLoaded(NATIVE_ADDON, function()
        waiting = false
        if tab and tab:IsVisible() then
            Q.Run('panneaux LFG Forever', function()
                if prepare(tab) then LFGF.RequestGuildRoster(); LFGF.LoadTalentPoints() end
            end)
        end
    end)
end

function LFGF.SetSearchStatus(message)
    if tab and tab.Content then tab.Content.SearchStatus:SetText(message or '') end
end

-- Colonnes reprises de BuildContentPanels, ancrées dans la zone du module.
local function buildContent(content)
    local filter = LFGF.CreateFilterPanel(content)
    filter:SetPoint('TOPRIGHT', -4, -69)
    filter:SetPoint('BOTTOMRIGHT', -4, 4)
    content.FilterPanel = filter

    local list = LFGF.CreateListPanel(content)
    list:SetPoint('TOPLEFT', 4, -69)
    list:SetPoint('BOTTOMRIGHT', filter, 'BOTTOMLEFT', -9, 0)
    content.ListPanel = list
    LFGF.SetInviteActivitySource(function() return filter:SelectedActivityIDs() end)

    content.SearchStatus = S.Text(content, 13, S.colors.muted)
    content.SearchStatus:SetPoint('TOPLEFT', 4, -38)
    content.SearchStatus:SetPoint('TOPRIGHT', -4, -38)
    local all = S.Button(content, 'Toutes les annonces', 168, 28, 'ghost')
    all:SetPoint('TOPLEFT', 4, -2)
    all:SetScript('OnClick', LFGF.ShowAllResults)
    local options = S.Button(content, L.SETTINGS, 124, 28, 'ghost')
    options:SetPoint('TOPRIGHT', -4, -2)
    options:SetScript('OnClick', function() LFGF.OpenSettings() end)
    -- Plus de bouton qui ouvre le Cherche-groupe de WoW (T241) : l'ouvrir depuis l'addon bloquait les barres d'action.
    local native = S.Text(content, 12, S.colors.muted)
    native:SetPoint('RIGHT', options, 'LEFT', -10, 0)
    native:SetText(LFGF.NATIVE_HINT)
    content.NativeHint = native
end

local function fit(panel)
    if not panel.Content then return end
    local scale = math.min(1, panel:GetWidth() / WIDTH, panel:GetHeight() / HEIGHT)
    if scale > 0 then panel.Content:SetScale(scale) end
end

function prepare(panel)
    if panel.Content then return true end
    if panel.buildFailed or not panel:IsVisible() or Core.GuildStatus() ~= 'ok' then return false end
    if not loadNative() then
        panel.status:SetText('Le Cherche-groupe de WoW n’est pas encore chargé par le jeu : ouvre-le une fois avec sa touche ou le micro-menu, cette page s’affichera ensuite.')
        waitNative()
        return false
    end
    local content = CreateFrame('Frame', nil, panel)
    content:SetSize(WIDTH, HEIGHT)
    content:SetPoint('CENTER')
    content:Hide()
    local ok = Q.Run('panneaux LFG Forever', buildContent, content)
    if not ok then
        panel.buildFailed = true
        panel.status:SetText('Les panneaux LFG sont indisponibles. Détail dans /quinte erreurs.')
        return false
    end
    panel.Content = content
    panel.status:Hide()
    fit(panel)
    content:Show()
    return true
end

function LFGF.CreateEmbeddedPanel(parent)
    local panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints()
    panel:Hide()
    panel.status = S.Text(panel, 13, S.colors.muted)
    panel.status:SetPoint('TOPLEFT', 4, -4)
    panel:SetScript('OnSizeChanged', fit)
    panel:SetScript('OnHide', LFGF.CloseDialogs)
    panel:SetScript('OnShow', function(self)
        if prepare(self) then
            LFGF.RequestGuildRoster()
            LFGF.LoadTalentPoints()
        end
    end)
    tab = panel
    LFGF.DialogParent = panel
    return panel
end

function LFGF.ResetWindowPosition()
    for _, key in ipairs({ 'windowX', 'windowY', 'windowWidth', 'windowHeight' }) do
        LFGF.SaveValue(key, nil)
    end
    if tab then fit(tab) end
end

function LFGF.OpenWindow()
    if Core.GuildStatus() ~= 'ok' then return false end
    Q.UI.ShowTab('lfg')
    return tab and prepare(tab) or false
end

function LFGF.ToggleWindow()
    if tab and tab:IsVisible() then Core.UI.Toggle('group') else LFGF.OpenWindow() end
end

function LFGF.OpenSettings()
    if not LFGF.OpenWindow() then return end
    if not tab.Settings then tab.Settings = LFGF.CreateEmbeddedSettings(tab) end
    tab.Content:Hide()
    tab.Settings:Show()
    tab.Settings.Refresh()
end

function LFGF.BackToResults()
    if not tab or not tab.Content then return end
    if tab.Settings then tab.Settings:Hide() end
    tab.Content:Show()
end

function LFGF.SearchFromKey()
    if not LFGF.OpenWindow() then return end
    LFGF.BackToResults()
    if tab.Content.FilterPanel:RequestSearch() then LFGF.PlayClick() end
end

function LFGF.OpenPlayerRatings()
    if not LFGF.ShowPlayerRatings() or not LFGF.OpenWindow() then return end
    LFGF.BackToResults()
    tab.Content.FilterPanel:ShowPlayerRatingsTab()
end
