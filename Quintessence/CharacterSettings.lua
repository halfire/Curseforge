local _, Core = ...
local C, S, controls, page = Core.Characters, Core.Style, nil, 0
function C.RefreshSettings()
    if not controls then return end
    local all, candidates = C.Own(), {}
    for _, c in ipairs(all) do if c.level >= 60 then candidates[#candidates + 1] = c end end
    page = math.max(0, math.min(page, math.max(0, math.ceil(#candidates / 4) - 1)))
    local main = C.Main()
    controls.value:SetText(main and ('Principal : ' .. Core.DisplayName(main)) or 'Principal : en attente du premier relevé')
    local d = QuintessenceDB and QuintessenceDB.characterProfile
    controls.auto:SetActive(not (d and d.manual))
    for i, button in ipairs(controls.buttons) do
        local c = candidates[page * 4 + i]
        button.key = c and c.key
        button:SetShown(c ~= nil)
        if c then button:SetLabel(Core.DisplayName(c.key)); button:SetActive(c.main) end
    end
    controls.note:SetText(#candidates == 0 and 'Le choix manuel sera disponible avec tes personnages de niveau 60.'
        or ('Choisis un de tes niveaux 60 · page ' .. (page + 1) .. '/' .. math.ceil(#candidates / 4)))
    controls.previous:SetShown(page > 0)
    controls.next:SetShown((page + 1) * 4 < #candidates)
end
function C.AddSettings(panel)
    controls = {buttons = {}}
    local heading = S.Heading(panel, 'Personnage principal'); heading:SetPoint('TOPLEFT', 0, -484)
    local hint = S.Text(panel, 11, S.colors.muted); hint:SetPoint('TOPLEFT', 0, -506); hint:SetWidth(1068)
    hint:SetText('Automatique : le plus haut niveau, puis le premier 60 connu. Choix commun à tous les addons Quintessence.')
    controls.value = S.Text(panel, 12, S.colors.gold); controls.value:SetPoint('TOPLEFT', 0, -532); controls.value:SetWidth(800)
    controls.auto = S.Button(panel, 'Choix automatique', 170, 24, 'ghost'); controls.auto:SetPoint('TOPRIGHT', 0, -526)
    controls.auto:SetScript('OnClick', function() C.Automatic() end)
    for i = 1, 4 do
        local b = S.Button(panel, '', 250, 26, 'ghost'); b:SetPoint('TOPLEFT', (i - 1) * 272, -560)
        b:SetScript('OnClick', function(self)
            if self.key then local _, message = C.Select(self.key); Core.Print(message) end
        end)
        controls.buttons[i] = b
    end
    controls.note = S.Text(panel, 11, S.colors.muted); controls.note:SetPoint('TOPLEFT', 0, -600); controls.note:SetWidth(760)
    controls.previous = S.Button(panel, 'Précédent', 96, 24, 'ghost'); controls.previous:SetPoint('TOPRIGHT', -102, -594)
    controls.next = S.Button(panel, 'Suivant', 96, 24, 'ghost'); controls.next:SetPoint('TOPRIGHT', 0, -594)
    controls.previous:SetScript('OnClick', function() page = page - 1; C.RefreshSettings() end)
    controls.next:SetScript('OnClick', function() page = page + 1; C.RefreshSettings() end)
    panel.characters = controls
    C.RefreshSettings()
end
C.OnChanged(function() C.RefreshSettings() end)
