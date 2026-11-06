local _, Core = ...
--[[
  Bouton rond sur le bord de la minimap : clic gauche ouvre/ferme la fenêtre, clic droit /quinte debug, glisser pour le
  déplacer autour de la minimap. Position et visibilité dans QuintessenceDB.minimap ; /quinte minimap le cache ou le
  réaffiche. Notre propre bouton seulement : aucune écriture dans la minimap ni dans les objets de Blizzard.
]]
local button

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
        GameTooltip:AddLine('Synchro : ' .. (not state.enabled and '|cffe5545ccoupée|r' or state.deferred ~= 'non' and ('|cffd9b35cen pause (' .. state.deferred .. ')|r')
            or '|cff5cd1a8active|r') .. (state.queued > 0 and (' · ' .. state.queued .. ' en file') or ''), 0.8, 0.8, 0.8)
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
    button:SetScript('OnClick', function(_, mouse)
        Core.Run('minimap', function() if mouse == 'RightButton' then Core.Debug() else Core.UI.Toggle() end end)
    end)
    button:SetScript('OnDragStart', function(self) self:SetScript('OnUpdate', follow) end)
    button:SetScript('OnDragStop', function(self) self:SetScript('OnUpdate', nil) end)
    button:SetScript('OnEnter', tooltip)
    button:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    place()
    button:SetShown(not settings().hidden)
end

function Core.MinimapToggle()
    local s = settings()
    s.hidden = not s.hidden
    if button then button:SetShown(not s.hidden) end
    Core.Print('Bouton de la minimap ' .. (s.hidden and 'caché (/quinte minimap pour le remettre).' or 'affiché.'))
end
