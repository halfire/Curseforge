local _, Core = ...
--[[
  Bouton rond sur le bord de la minimap : clic gauche ouvre/ferme la fenêtre, clic droit /quinte debug, glisser pour le
  déplacer autour de la minimap. Position et visibilité dans QuintessenceDB.minimap ; /quinte minimap le cache ou le
  réaffiche. Pastille : nombre de notifications (les mêmes que la cloche de la fenêtre, plus les commandes artisan),
  détail dans l'infobulle, clic pour les ouvrir (T223). Notre propre bouton seulement : aucune écriture dans la minimap ni dans les objets de Blizzard.
]]
local button
local notices = {}
local notes = {} -- notifications de la fenêtre (accueil : alertes et « À faire »), T223
local function guildOk() return Core.GuildStatus() == 'ok' end
local function activeNotice()
    if not guildOk() then return nil end
    for _, notice in pairs(notices) do if notice.count > 0 then return notice end end
end
-- Total affiché : les compteurs des modules (commandes artisan…) plus les notifications des autres modules
local function total()
    if not guildOk() then return 0 end
    local n = 0
    for _, notice in pairs(notices) do n = n + notice.count end
    for _, note in ipairs(notes) do if not (note.module and notices[note.module]) then n = n + 1 end end
    return n
end
function Core.MinimapNoticeCount(id)
    if id then return notices[id] and notices[id].count or 0 end
    return total()
end
function Core.RefreshMinimapNotice()
    if not button or not button.notice then return end
    local n = total()
    button.notice:SetShown(n > 0)
    if n > 0 then button.notice.label:SetText(n > 99 and '99+' or tostring(n)) end
end
-- Compteur local fourni par un module ; aucune donnée supplémentaire sauvegardée ou envoyée.
function Core.SetMinimapNotice(id, count, open, label)
    if type(id) ~= 'string' or type(count) ~= 'number' or count ~= count then return end
    notices[id] = { count = math.max(0, math.min(9999, math.floor(count))), open = open, label = label }
    Core.RefreshMinimapNotice()
end
--- Recalcule les notifications (mêmes que la cloche de la fenêtre), même fenêtre fermée.
function Core.MinimapRefreshNotes(list)
    local UI = Core.UI
    if type(list) == 'table' then notes = list
    elseif UI and UI.Notifications then
        local ok, list = pcall(UI.Notifications)
        notes = ok and type(list) == 'table' and list or {}
    end
    Core.RefreshMinimapNotice()
end

local function settings()
    QuintessenceDB.minimap = type(QuintessenceDB.minimap) == 'table' and QuintessenceDB.minimap or {}
    local s = QuintessenceDB.minimap
    if type(s.angle) ~= 'number' then s.angle = 205 end
    return s
end

local function place()
    if not button or not Minimap then return end
    local angle = math.rad(settings().angle)
    local radius = (Minimap:GetWidth() or 140) / 2 + 5
    button:ClearAllPoints()
    button:SetPoint('CENTER', Minimap, 'CENTER', math.cos(angle) * radius, math.sin(angle) * radius)
end

-- Pendant le glisser : angle entre le centre de la minimap et le curseur
local function follow()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if not mx or not cx or not scale or scale == 0 then return end
    settings().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
    place()
end

local function tooltip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
    GameTooltip:AddLine('Quintessence ' .. Core.version)
    local state = Core.sync and Core.sync:Status()
    if state then
        GameTooltip:AddLine((Core.Style.ChatText or tostring)('Synchro : ' .. (not state.enabled and '|c' .. Core.Style.hex.red .. 'coupée|r' or state.deferred ~= 'non' and ('|c' .. Core.Style.hex.gold .. 'en pause (' .. state.deferred .. ')|r')
            or '|c' .. Core.Style.hex.mint .. 'active|r') .. (state.queued > 0 and (' · ' .. state.queued .. ' en file') or '')), 0.8, 0.8, 0.8)
    end
    for _, notice in pairs(guildOk() and notices or {}) do
        if notice.count > 0 then GameTooltip:AddLine((notice.label or 'En attente') .. ' : ' .. notice.count .. ' à traiter', 1, 0.8, 0.2) end
    end
    local shown = 0
    for _, note in ipairs(guildOk() and notes or {}) do
        if not (note.module and notices[note.module]) and shown < 6 then
            shown = shown + 1
            GameTooltip:AddLine('• ' .. (Core.Style.ChatText or tostring)(note.text), note.tone == 'red' and 1 or 0.85, note.tone == 'red' and 0.35 or 0.85, note.tone == 'red' and 0.35 or 0.85, true)
        end
    end
    GameTooltip:AddLine('Clic : ouvrir · clic droit : diagnostic · glisser : déplacer', 0.58, 0.63, 0.72)
    GameTooltip:Show()
end

function Core.MinimapCreate()
    if button or not Minimap then return end
    button = CreateFrame('Button', 'QuintessenceMinimapButton', Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata('MEDIUM'); button:SetFrameLevel(8)
    button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    button:RegisterForDrag('LeftButton')
    button:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
    local background = button:CreateTexture(nil, 'BACKGROUND'); background:SetSize(20, 20); background:SetPoint('TOPLEFT', 7, -5)
    background:SetTexture('Interface\\Minimap\\UI-Minimap-Background')
    local icon = button:CreateTexture(nil, 'ARTWORK'); icon:SetSize(18, 18); icon:SetPoint('TOPLEFT', 7, -6)
    -- Icône de la Quintessence éternelle (objet 22754)
    icon:SetTexture('Interface\\Icons\\INV_Potion_83'); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = button:CreateTexture(nil, 'OVERLAY'); border:SetSize(53, 53); border:SetPoint('TOPLEFT')
    border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
    local badge = Core.Style.Box(button, Core.Style.colors.red, Core.Style.colors.line)
    badge:SetSize(22, 16); badge:SetPoint('TOPRIGHT', 4, 4); badge:SetFrameLevel(button:GetFrameLevel() + 2)
    badge:EnableMouse(false)
    badge.label = Core.Style.Text(badge, 9, Core.Style.colors.text, 'CENTER'); badge.label:SetPoint('CENTER')
    button.notice = badge
    button:SetScript('OnClick', function(_, mouse)
        Core.Run('minimap', function()
            local notice = activeNotice()
            local others = false
            for _, note in ipairs(guildOk() and notes or {}) do if not (note.module and notices[note.module]) then others = true end end
            if mouse == 'RightButton' then Core.Debug()
            elseif notice and type(notice.open) == 'function' then notice.open()
            elseif others and Core.UI.Open and Core.UI.ShowNotifications then
                -- Notifications : la fenêtre s'ouvre avec la liste de la cloche dépliée
                Core.UI.Open('home'); Core.UI.ShowNotifications()
            else Core.UI.Toggle() end
        end)
    end)
    button:SetScript('OnDragStart', function(self) self:SetScript('OnUpdate', follow) end)
    button:SetScript('OnDragStop', function(self) self:SetScript('OnUpdate', nil) end)
    button:SetScript('OnEnter', tooltip)
    button:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    place()
    Core.RefreshMinimapNotice()
    button:SetShown(not settings().hidden)
end

function Core.MinimapToggle()
    local s = settings()
    s.hidden = not s.hidden
    if button then button:SetShown(not s.hidden) end
    Core.Print('Bouton de la minimap ' .. (s.hidden and 'caché (/quinte minimap pour le remettre).' or 'affiché.'))
end

local noticeFrame = CreateFrame('Frame')
Core.Call(noticeFrame.RegisterEvent, noticeFrame, 'PLAYER_GUILD_UPDATE')
noticeFrame:SetScript('OnEvent', function() Core.RefreshMinimapNotice() end)
-- Notifications recalculées toutes les 30 s hors combat, fenêtre ouverte ou non
local waited = 0
noticeFrame:SetScript('OnUpdate', function(_, dt)
    waited = waited + (tonumber(dt) or 0)
    if waited < 30 or not button then return end
    waited = 0
    if InCombatLockdown and InCombatLockdown() then return end
    Core.Run('notifications minicarte', Core.MinimapRefreshNotes)
end)
