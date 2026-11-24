local _, Q = ...
local Core, S = Quintessence, Quintessence.Style

-- Les panneaux reprennent les modèles propres au Cherche-groupe de Forever.
if not C_LFGList or not C_AddOns or not EventUtil or not EventRegistry
    or not GroupFinderVanillaStyle_LoadUI or not (Enum and Enum.LFGEntryGeneralPlaystyle) then return end

local LFG = { Dialogs = {}, RatingsAvailable = false }
Q.LFGForever = LFG

-- Seuls les cadres et régions créés par le module reçoivent le thème.
function LFG.ThemeFont(text, size, color)
    if not text then return end
    local theme = S.THEMES[S.Kind()]
    local fontSize = size + (theme and theme.boost or 0)
    local font = size >= 16 and S.TitleFont() or S.Font()
    if text:SetFont(font, fontSize, '') == false and STANDARD_TEXT_FONT then
        text:SetFont(STANDARD_TEXT_FONT, fontSize, '')
    end
    text:SetTextColor(unpack(S.colors[color or 'text']))
end

function LFG.CreateDropdown(parent)
    local dropdown = CreateFrame('DropdownButton', nil, parent, 'WowStyle1DropdownTemplate')
    if not S.IsClassic() and dropdown.Background then
        dropdown.Background:SetAlpha(0)
        local border = S.Fill(dropdown, 'BACKGROUND', S.colors.line)
        border:SetAllPoints()
        local body = S.Fill(dropdown, 'BORDER', S.colors.raised)
        body:SetPoint('TOPLEFT', 1, -1)
        body:SetPoint('BOTTOMRIGHT', -1, 1)
    end
    if dropdown.Text and dropdown.Text.SetHeight then dropdown.Text:SetHeight(0) end
    local function paint(self)
        LFG.ThemeFont(self.Text, 12, self:IsEnabled() and 'text' or 'muted')
    end
    for _, script in ipairs({ 'OnShow', 'OnEnable', 'OnDisable', 'OnEnter', 'OnLeave' }) do
        dropdown:HookScript(script, paint)
    end
    paint(dropdown)
    return dropdown
end

LFG.SEARCH_ACTION_LABEL = 'Rechercher'
LFG.NATIVE_HINT = 'Cherche-groupe WoW accessible via le micro-menu.'

function LFG.ShowAllResults()
    if Core.GuildStatus() ~= 'ok' then return end
    EventRegistry:TriggerEvent(LFG.EVENT_FILTERS_APPLIED, nil)
end

-- Les dialogues LFG restent rattachés à l'onglet Quintessence.
local visible = {}
function LFG.CloseDialogs()
    for _, dialog in pairs(visible) do dialog:Hide() end
end

function LFG.ShowDialog(key, _, _, data)
    local definition = LFG.Dialogs[key]
    if not definition or (definition.ratingsOnly and not LFG.ShowPlayerRatings())
        or not LFG.DialogParent or not LFG.DialogParent:IsVisible() or Core.GuildStatus() ~= 'ok' then return end
    local dialog = visible[key]
    if dialog then dialog:Hide() end

    dialog = dialog or S.Box(LFG.DialogParent, S.colors.panel, S.colors.line)
    if not visible[key] then
        visible[key] = dialog
        dialog:SetFrameStrata('DIALOG')
        dialog:SetPoint('CENTER')
        dialog:EnableMouse(true)
        dialog.title = S.Text(dialog, 14, S.colors.text)
        dialog.title:SetPoint('TOPLEFT', 14, -12)
        dialog.title:SetPoint('RIGHT', -14, 0)
        dialog.title:SetWordWrap(true)
        dialog.title:SetText(definition.text)
        dialog.SubText = S.Text(dialog, 12, S.colors.muted)
        dialog.SubText:SetPoint('TOPLEFT', dialog.title, 'BOTTOMLEFT', 0, -7)
        dialog.SubText:SetPoint('RIGHT', -14, 0)
        dialog.SubText:SetWordWrap(true)
        dialog.SubText:SetText(definition.subText or '')

        local input = S.Input(dialog, definition.editBoxWidth or 360, '')
        input:SetPoint('BOTTOMLEFT', 14, 53)
        input:SetMaxLetters(definition.maxLetters)
        dialog.GetEditBox = function() return input end

        local accept = S.Button(dialog, definition.button1, 110, 28, 'primary')
        accept:SetPoint('BOTTOMLEFT', 14, 12)
        dialog.GetButton1 = function() return accept end
        if definition.button2 then
            local cancel = S.Button(dialog, definition.button2, 110, 28, 'ghost')
            cancel:SetPoint('LEFT', accept, 'RIGHT', 7, 0)
            cancel:SetScript('OnClick', function() dialog:Hide() end)
        end
        dialog.Resize = function() end
        dialog:SetSize(math.max(398, (definition.editBoxWidth or 0) + 28), definition.subText and 166 or 139)
        dialog:SetScript('OnHide', function(self)
            if definition.OnHide then definition.OnHide(self) end
            input:ClearFocus()
            dialog.data = nil
        end)
        local function submit()
            if accept:IsEnabled() and (not definition.OnAccept or not definition.OnAccept(dialog, dialog.data)) then dialog:Hide() end
        end
        accept:SetScript('OnClick', submit)
        input:SetScript('OnEscapePressed', function() dialog:Hide() end)
        input:SetScript('OnEnterPressed', function(self)
            if definition.EditBoxOnEnterPressed then
                definition.EditBoxOnEnterPressed(self, dialog.data)
            else
                submit()
            end
        end)
        input:SetScript('OnTextChanged', function(self)
            self.placeholder:SetShown(self:GetText() == '')
            if definition.EditBoxOnTextChanged then definition.EditBoxOnTextChanged(self, dialog.data) end
        end)
    end

    dialog.data = data
    dialog:GetButton1():Enable()
    dialog:Show()
    if definition.OnShow then definition.OnShow(dialog, data) end
    return dialog
end

local function bindingControls(panel, button, controls)
    local actions = {
        { 'QUINTELFG_TOGGLE', 'Ouvrir LFG' },
        { 'CLICK QuinteLFGSearchKeyButton:LeftButton', LFG.SEARCH_ACTION_LABEL },
    }
    local status = S.Text(panel, 11, S.colors.muted)
    status:SetPoint('TOPLEFT', 4, -402)
    status:SetWidth(290)
    status:SetWordWrap(true)

    local input = CreateFrame('Frame', nil, panel)
    input:Hide()
    local selected
    local function stop()
        selected = nil
        if input.EnableKeyboard then input:EnableKeyboard(false) end
        input:Hide()
    end
    panel:HookScript('OnHide', stop)
    input:RegisterEvent('PLAYER_REGEN_DISABLED')
    input:SetScript('OnEvent', function()
        if not selected then return end
        stop()
        status:SetText('Réglage du raccourci interrompu par le combat.')
    end)
    local function begin(command)
        if InCombatLockdown() then
            status:SetText('Les raccourcis se règlent hors combat.')
            return
        end
        if not (GetBindingKey and GetBindingAction and GetCurrentBindingSet and SetBinding and SaveBindings
            and input.EnableKeyboard and input.SetPropagateKeyboardInput) then
            status:SetText('Le réglage des raccourcis est indisponible sur ce client.')
            return
        end
        if not Q.Call(input.SetPropagateKeyboardInput, input, false) then return end
        selected = command
        input:Show()
        input:EnableKeyboard(true)
        status:SetText('Appuie sur une touche. Échap annule, Suppr retire le premier raccourci.')
    end
    input:SetScript('OnKeyDown', function(_, key)
        local command = selected
        if not command then return end
        if InCombatLockdown() then stop(); return end
        if key == 'LSHIFT' or key == 'RSHIFT' or key == 'LCTRL' or key == 'RCTRL'
            or key == 'LALT' or key == 'RALT' or key == 'LMETA' or key == 'RMETA' then return end
        stop()
        status:SetText('')
        if key == 'ESCAPE' then return end

        local previous = GetBindingKey(command)
        local shift, ctrl, alt = IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown()
        local clear = key == 'DELETE' and not (shift or ctrl or alt)
        local chosen = (alt and 'ALT-' or '') .. (ctrl and 'CTRL-' or '') .. (shift and 'SHIFT-' or '') .. key
        if clear then
            if not previous then return end
        else
            local assigned = GetBindingAction(chosen)
            if assigned and assigned ~= '' and assigned ~= command then
                status:SetText('Cette touche sert déjà à une autre action.')
                return
            end
        end

        local ok, changed
        if clear then ok, changed = Q.Call(SetBinding, previous) else ok, changed = Q.Call(SetBinding, chosen, command) end
        if not ok or not changed then status:SetText('WoW a refusé de modifier ce raccourci.'); return end
        if not Q.Call(SaveBindings, GetCurrentBindingSet()) then
            status:SetText('WoW a changé la touche mais sa sauvegarde a échoué.')
        end
        panel.Refresh()
    end)
    for index, action in ipairs(actions) do
        local command, caption = action[1], action[2]
        local control = button(caption, 290, 4, -324 - (index - 1) * 34, function() begin(command) end)
        controls[#controls + 1] = function()
            local first, second = nil, nil
            if GetBindingKey then first, second = GetBindingKey(command) end
            local keys = first and (second and (first .. ', ' .. second) or first) or 'Aucun raccourci'
            control:SetLabel(caption .. ' · ' .. keys)
        end
    end
end

function LFG.CreateEmbeddedSettings(parent)
    local panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints()
    panel:Hide()
    local L = LFG.L
    local controls = {}
    local function button(label, width, x, y, action)
        local control = S.Button(panel, label, width, 28, 'ghost')
        control:SetPoint('TOPLEFT', x, y)
        control:SetScript('OnClick', action)
        return control
    end
    local function set(key, value, event)
        LFG.SaveValue(key, value)
        if event then EventRegistry:TriggerEvent(event, value) end
        panel.Refresh()
    end

    button('Retour aux annonces', 166, 4, -4, LFG.BackToResults)
    button(L.REPORT_BUG, 148, 178, -4, LFG.ShowReportBug)
    local toggles = {
        { 'showAllLevelRanges', L.SETTINGS_SHOW_ALL_LEVELS_LABEL, LFG.EVENT_LEVEL_RANGES_CHANGED },
        { 'showActivityLevelRanges', L.SETTINGS_SHOW_LEVEL_RANGES_LABEL, LFG.EVENT_LEVEL_RANGES_CHANGED },
        { 'markGuildmates', L.SETTINGS_MARK_GUILDMATES_LABEL, LFG.EVENT_PLAYER_SORT_ORDER_CHANGED },
        { 'markFriends', L.SETTINGS_MARK_FRIENDS_LABEL, LFG.EVENT_PLAYER_SORT_ORDER_CHANGED },
        { 'showMinimapButton', L.SETTINGS_MINIMAP_BUTTON_LABEL, LFG.EVENT_MINIMAP_BUTTON_CHANGED },
        { 'askToJoinAutoWhisper', L.SETTINGS_ASK_TO_JOIN_AUTO_WHISPER_LABEL },
        { 'inviteAutoWhisper', L.SETTINGS_INVITE_AUTO_WHISPER_LABEL },
    }
    if LFG.RatingsAvailable then
        toggles[#toggles + 1] = { 'showPlayerRatings', L.PLAYER_RATINGS, LFG.EVENT_PLAYER_RATINGS_CHANGED }
    end
    for index, option in ipairs(toggles) do
        local key, label, event = option[1], option[2], option[3]
        local toggle = button(label, 290, 4, -48 - (index - 1) * 34, function()
            set(key, not LFG.SavedSetting(key), event)
        end)
        controls[#controls + 1] = function()
            local enabled = LFG.SavedSetting(key)
            toggle:SetLabel(label .. (enabled and ' · Oui' or ' · Non'))
            toggle:SetActive(enabled)
        end
    end

    local sortLabels = {
        newest = L.PLAYER_SORT_NEWEST, oldest = L.PLAYER_SORT_OLDEST,
        levelHigh = L.PLAYER_SORT_LEVEL_HIGH, levelLow = L.PLAYER_SORT_LEVEL_LOW, class = L.PLAYER_SORT_CLASS,
    }
    local sort = button(L.SETTINGS_PLAYER_SORT_LABEL, 300, 310, -48, function()
        local order = LFG.PLAYER_SORT_ORDERS
        local current = LFG.PlayerSortOrder()
        for index, name in ipairs(order) do
            if name == current then
                set('playerSortOrder', order[index % #order + 1], LFG.EVENT_PLAYER_SORT_ORDER_CHANGED)
                return
            end
        end
    end)
    controls[#controls + 1] = function() sort:SetLabel('Tri · ' .. sortLabels[LFG.PlayerSortOrder()]) end

    local log = S.Text(panel, 12, S.colors.text)
    log:SetPoint('TOPLEFT', 310, -92)
    controls[#controls + 1] = function()
        log:SetText(L.SETTINGS_WHISPER_LOG_SIZE_LABEL .. ' · ' .. LFG.WhisperLogSize())
    end
    local function stepLog(step)
        set('whisperLogSize', math.max(50, math.min(500, LFG.WhisperLogSize() + step)), LFG.EVENT_WHISPER_LOG_SIZE_CHANGED)
    end
    button('-50', 55, 491, -85, function() stepLog(-50) end)
    button('+50', 55, 554, -85, function() stepLog(50) end)

    local function message(key, label, tooltip, y)
        local title = S.Text(panel, 12, S.colors.gold)
        title:SetPoint('TOPLEFT', 310, y)
        title:SetText(label)
        local input = S.Input(panel, 300, '')
        input:SetPoint('TOPLEFT', 310, y - 20)
        input:SetMaxLetters(200)
        local help = S.Text(panel, 11, S.colors.muted)
        help:SetPoint('TOPLEFT', 310, y - 53)
        help:SetWidth(300)
        help:SetWordWrap(true)
        help:SetText(tooltip)
        local function save()
            LFG.SaveValue(key, input:GetText())
            input:ClearFocus()
        end
        input:SetScript('OnEnterPressed', save)
        input:SetScript('OnEscapePressed', function(self)
            self:SetText(LFG.SavedSetting(key))
            self:ClearFocus()
        end)
        button('Enregistrer', 110, 310, y - 105, save)
        controls[#controls + 1] = function()
            if not input:HasFocus() then input:SetText(LFG.SavedSetting(key)) end
        end
    end
    message('askToJoinMessage', L.SETTINGS_ASK_TO_JOIN_AUTO_WHISPER_LABEL, L.SETTINGS_ASK_TO_JOIN_MESSAGE_TOOLTIP, -127)
    message('inviteMessage', L.SETTINGS_INVITE_AUTO_WHISPER_LABEL, L.SETTINGS_INVITE_MESSAGE_TOOLTIP, -275)

    bindingControls(panel, button, controls)

    function panel.Refresh()
        for _, refresh in ipairs(controls) do refresh() end
    end
    panel:SetScript('OnShow', panel.Refresh)
    return panel
end
