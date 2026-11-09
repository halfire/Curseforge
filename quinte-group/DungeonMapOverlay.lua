local _, Q = ...
-- Remplacement visuel du fond de carte en donjon : cadre propre sous UIParent.
-- La carte Blizzard est uniquement lue (visibilité, rectangle, échelle et carte affichée).
-- Aucun parentage, champ, crochet, raccourci ni fonction de Blizzard n'est modifié.
local Core, S, Maps = Quintessence, Quintessence.Style, Q.DungeonMaps
local O = {}
Q.DungeonMapOverlay = O
local view, codes, instanceKey, chosen, data = nil, {}, nil, nil, nil
local opened, dismissed, originalMap, elapsed = false, false, nil, 0
local geometry, dirty = nil, true
local needsChoice = false
local remembered = {}
local ENGLISH = {
    RFC = 'Ragefire Chasm', WC = 'Wailing Caverns', DM = 'The Deadmines', SFK = 'Shadowfang Keep',
    STOCKS = 'The Stockade', BFD = 'Blackfathom Deeps', GNOMER = 'Gnomeregan', RFK = 'Razorfen Kraul',
    RFD = 'Razorfen Downs', ULDA = 'Uldaman', ZF = "Zul'Farrak", MARA = 'Maraudon',
    ST = "The Temple of Atal'Hakkar", BRD = 'Blackrock Depths', LBRS = 'Lower Blackrock Spire',
    STRAT = 'Stratholme', SCHOLO = 'Scholomance',
}
local FAMILIES = {
    { names = { 'Scarlet Monastery', 'Monastère écarlate' }, codes = { 'SM_GY', 'SM_LIB', 'SM_ARM', 'SM_CATH' },
      wings = { SM_GY = { 'Graveyard', 'Cimetière' }, SM_LIB = { 'Library', 'Bibliothèque' },
        SM_ARM = { 'Armory', 'Armurerie' }, SM_CATH = { 'Cathedral', 'Cathédrale' } } },
    { names = { 'Dire Maul', 'Hache-Tripes' }, codes = { 'DME', 'DMW', 'DMN' },
      wings = { DME = { 'Dire Maul East', 'Hache-Tripes Est' }, DMW = { 'Dire Maul West', 'Hache-Tripes Ouest' },
        DMN = { 'Dire Maul North', 'Hache-Tripes Nord' } } },
    { names = { 'Blackrock Spire', 'Pic Rochenoire' }, codes = { 'LBRS' }, choose = true },
}
local function number(v)
    return not (issecretvalue and issecretvalue(v)) and type(v) == 'number' and v == v and math.abs(v) < math.huge
end
local function key(text)
    if (issecretvalue and issecretvalue(text)) or type(text) ~= 'string' then return '' end
    for _, pair in ipairs({ { 'É', 'e' }, { 'È', 'e' }, { 'Ê', 'e' }, { 'é', 'e' }, { 'è', 'e' }, { 'ê', 'e' },
        { 'à', 'a' }, { 'â', 'a' }, { 'î', 'i' }, { 'ï', 'i' }, { 'ô', 'o' }, { 'ù', 'u' }, { 'û', 'u' }, { 'ç', 'c' } }) do
        text = text:gsub(pair[1], pair[2])
    end
    text = text:gsub('’', "'"):gsub('—', '-'):gsub('–', '-')
    text = text:lower():gsub('^the%s+', ''):gsub('^les%s+', ''):gsub('^la%s+', ''):gsub('^le%s+', '')
    return text:gsub('[%s%p]', '')
end
local function read(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end
--- Noms fournis par le jeu ; une aile ambiguë doit être choisie, jamais devinée.
function O.Instance()
    local inside, kind = read(IsInInstance)
    if inside ~= true or kind ~= 'party' then return {}, nil end
    local name, instanceType = read(GetInstanceInfo)
    if instanceType ~= 'party' then return {}, nil end
    local target = key(name)
    if target == '' then return {}, nil end
    for _, dungeon in ipairs(Q.FOREVER_DUNGEONS) do
        if target == key(dungeon.name) or target == key(ENGLISH[dungeon.code]) then
            return { dungeon.code }, target, dungeon.code
        end
    end
    for _, family in ipairs(FAMILIES) do
        for _, name in ipairs(family.names) do
            if target == key(name) then
                local subzone, preferred = key(read(GetSubZoneText)), nil
                for code, names in pairs(family.wings or {}) do
                    for _, alias in ipairs(names) do
                        if subzone ~= '' and subzone:find(key(alias), 1, true) then preferred = code end
                    end
                end
                return family.codes, target, preferred or (not family.choose and #family.codes == 1 and family.codes[1] or nil), family.choose
            end
        end
    end
    return {}, nil
end
local function clear()
    for _, texture in ipairs(view.tiles) do texture:Hide() end
    for _, pin in ipairs(view.pins) do pin:Hide() end
end
local function dismiss()
    dismissed = true
    if view then view:Hide() end
    if GameTooltip then GameTooltip:Hide() end
end
local function selectCode(code)
    chosen, data = code, Maps.Data(code)
    remembered[instanceKey] = code
    view.floor = 1; view.picked = nil; dirty = true
end
local function openLoot(boss)
    if not Core.ShowBossLoot then Q.Print('Installe quinte-bis pour voir le butin de ce boss.'); return end
    local ok, found = pcall(Core.ShowBossLoot, chosen, boss.name)
    if not ok then Q.Error('butin de la carte du donjon', found)
    elseif found == false then Q.Print('Butin non répertorié pour ' .. Q.Safe(boss.name) .. '.')
    else
        dismiss()
        if Core.UI and Core.UI.Raise then Core.UI.Raise() end
    end
end
local function create()
    view = S.Box(UIParent, S.colors.bg, S.colors.line)
    view.artX, view.artY, view.floor = 0, -32, 1
    view.canvas = CreateFrame('Frame', nil, view)
    view.tiles, view.pins, view.wings = {}, {}, {}
    view.previous = S.Button(view, '<', 26, 22, 'ghost'); view.previous:SetPoint('TOPLEFT', 6, -5)
    view.next = S.Button(view, '>', 26, 22, 'ghost'); view.next:SetPoint('LEFT', view.previous, 'RIGHT', 5, 0)
    view.previous:SetScript('OnClick', function() view.floor = view.floor - 1; dirty = true end)
    view.next:SetScript('OnClick', function() view.floor = view.floor + 1; dirty = true end)
    view.title = S.Text(view, 12, S.colors.text); view.title:SetPoint('TOPLEFT', 72, -10)
    view.world = S.Button(view, 'Carte du monde', 122, 22, 'ghost'); view.world:SetPoint('TOPRIGHT', -6, -5)
    view.world:SetScript('OnClick', dismiss)
    view.hint = S.Text(view, 10, S.colors.muted); view.hint:SetPoint('BOTTOMLEFT', 8, 6); view.hint:SetWordWrap(true)
    view.empty = S.Text(view, 14, S.colors.muted, 'CENTER'); view.empty:SetPoint('CENTER')
    view.empty:SetWordWrap(true)
    view:EnableMouse(true)
    view:EnableMouseWheel(true); view:SetScript('OnMouseWheel', function() end)
    view:SetScript('OnMouseUp', function(_, button) if button == 'RightButton' then dismiss() end end)
    view:Hide()
end
local function draw()
    clear()
    local width, height = view:GetWidth(), view:GetHeight()
    local multiple = #codes > 1 or needsChoice
    view.artY = multiple and -64 or -32
    for i = 1, 4 do
        local code = codes[i]
        local button = view.wings[i]
        if multiple and code then
            if not button then
                button = S.Button(view, '', 100, 22, 'ghost')
                button:SetScript('OnClick', function(self) selectCode(self.code) end)
                view.wings[i] = button
            end
            local bw = math.min(180, (width - 12) / #codes - 6)
            button.code = code; button:SetWidth(bw); button:ClearAllPoints()
            button:SetPoint('TOPLEFT', 6 + (i - 1) * (bw + 6), -35)
            local dungeon = Q.DUNGEON_BY_CODE[code]
            button:SetLabel(code == 'LBRS' and 'Pic inférieur (LBRS)' or dungeon and dungeon.short or code); button:SetActive(code == chosen); button:Show()
        elseif button then button:Hide() end
    end
    local floor = data and data.floors[view.floor]
    local loaded, w, h
    if floor then loaded, w, h = Maps.PaintArt(view, floor, width, math.max(1, height + view.artY - 26)) end
    if loaded then Maps.DrawPins(view, data, view.floor, w, h, openLoot) end
    view.empty:SetWidth(math.max(100, width - 30)); view.empty:SetShown(not loaded)
    view.empty:SetText(not chosen and 'Choisis l’aile du donjon ci-dessus.' or 'Aucun plan disponible pour ce donjon.')
    local dungeon = chosen and Q.DUNGEON_BY_CODE[chosen]
    view.title:SetWidth(math.max(40, width - 210))
    view.title:SetText(dungeon and (Q.Safe(dungeon.name) .. (floor and (' · ' .. floor.name .. ' (' .. view.floor .. '/' .. #data.floors .. ')') or '')) or 'Choisir l’aile du donjon')
    view.previous:SetEnabled(floor ~= nil and view.floor > 1)
    view.next:SetEnabled(floor ~= nil and view.floor < #data.floors)
    view.hint:SetWidth(math.max(100, width - 16))
    view.hint:SetText(data and data.classic and 'Plan Classic · positions indicatives sur Forever · clic sur un boss : butin · clic droit : monde'
        or 'Clic sur un boss : butin · Carte du monde pour consulter les autres zones')
    dirty = false
end
local function nativeMap(mapID)
    local info = C_Map and read(C_Map.GetMapInfo, mapID)
    if not (type(info) == 'table' and number(info.mapType) and info.mapType == 4) then return false end
    local textures = read(C_Map.GetMapArtLayerTextures, mapID, 1)
    return type(textures) == 'table' and #textures > 0
end
function O.Refresh()
    local map = WorldMapFrame
    local visible = map and read(map.IsShown, map)
    if visible ~= true then
        opened, dismissed, originalMap, geometry = false, false, nil, nil
        if view then view:Hide() end
        return
    end
    if #codes == 0 or (Core.GuildBlocked and Core.GuildBlocked()) then if view then view:Hide() end; return end
    local mapID = read(map.GetMapID, map)
    if not number(mapID) then if view then view:Hide() end; return end
    if not opened then
        opened, originalMap, dirty = true, mapID, true
        if not view then create() end
    elseif mapID ~= originalMap then dismissed = true end
    if dismissed or nativeMap(mapID) then if view then view:Hide() end; return end
    -- Le rectangle est lu en points écran, puis converti dans les coordonnées de UIParent.
    local picture = type(map.ScrollContainer) == 'table' and map.ScrollContainer or map
    local left, bottom, width, height = read(picture.GetRect, picture)
    local scale = read(picture.GetEffectiveScale, picture)
    local parentScale = read(UIParent.GetEffectiveScale, UIParent)
    if not (number(left) and number(bottom) and number(width) and number(height) and width > 0 and height > 0
        and number(scale) and scale > 0 and number(parentScale) and parentScale > 0) then view:Hide(); return end
    if chosen and (not data or #data.floors == 0) then view:Hide(); return end
    local ratio = scale / parentScale
    local signature = table.concat({ left, bottom, width, height, ratio }, ':')
    if geometry ~= signature then
        geometry, dirty = signature, true
        view:ClearAllPoints(); view:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', left * ratio, bottom * ratio)
        view:SetSize(width * ratio, height * ratio)
        local strata, level = read(map.GetFrameStrata, map), read(map.GetFrameLevel, map)
        view:SetFrameStrata((strata == 'FULLSCREEN' or strata == 'FULLSCREEN_DIALOG') and 'FULLSCREEN_DIALOG' or 'DIALOG')
        view:SetFrameLevel(number(level) and level + 20 or 100)
    end
    if dirty then draw() end
    view:Show()
end
local driver = CreateFrame('Frame')
local function probe()
    local newCodes, identity, preferred, choose = O.Instance()
    needsChoice = choose == true
    if identity ~= instanceKey then
        instanceKey, chosen, data = identity, nil, nil
        opened, dismissed, originalMap, geometry = false, false, nil, nil
        if view then view.floor = 1; view.picked = nil; view:Hide() end
    end
    codes = newCodes
    if #codes > 0 then
        local saved = preferred or remembered[instanceKey]
        for _, code in ipairs(codes) do
            if code == saved then
                if not view then create() end
                if code ~= chosen then selectCode(code) end
                break
            end
        end
        driver:SetScript('OnUpdate', function(_, delta)
            elapsed = elapsed + delta
            if elapsed >= 0.05 then elapsed = 0; Q.Run('carte du donjon sur M', O.Refresh) end
        end)
        Q.Run('carte du donjon sur M', O.Refresh)
    else
        driver:SetScript('OnUpdate', nil)
        if view then view:Hide() end
    end
end
for _, event in ipairs({ 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'ZONE_CHANGED_NEW_AREA' }) do driver:RegisterEvent(event) end
driver:SetScript('OnEvent', function() Q.Run('donjon actuel', probe) end)
