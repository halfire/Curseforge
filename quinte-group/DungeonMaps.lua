local addonName, Q = ...
-- Visionneuse propre à Quintessence : cartes du client et repères par étage.
-- Aucun cadre ni crochet sur WorldMapFrame ; les coordonnées intérieures ne sont jamais des waypoints extérieurs.
local Core = Quintessence
local S = Core.Style
local M = {}
Q.DungeonMaps = M
local window, selected, floorAt, offset = nil, nil, 1, 0
local ROWS, MAP_W, MAP_H = 16, 700, 525
local function readable(v) return not (issecretvalue and issecretvalue(v)) end
local function number(v) return readable(v) and type(v) == 'number' and v == v and math.abs(v) < math.huge end
local function plain(s)
    return readable(s) and type(s) == 'string' and s:lower():gsub('[%s%p]', '') or ''
end
local function call(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, value = pcall(fn, ...)
    if ok and readable(value) then return value end
end
local function nativeMap(code)
    if not (C_Map and C_Map.GetMapChildrenInfo) then return nil end
    local d = Q.DUNGEON_BY_CODE[code]
    if not d then return nil end
    local target = plain(d.name)
    for _, root in ipairs({ 947, 946 }) do
        local list = call(C_Map.GetMapChildrenInfo, root, nil, true)
        if type(list) == 'table' then
            for _, info in ipairs(list) do
                -- Évite de confondre une zone extérieure et son instance (Dalaran, par exemple).
                if readable(info.mapType) and info.mapType == 4 and plain(info.name) == target and number(info.mapID) then
                    return info.mapID
                end
            end
        end
    end
end
local function nativeFloors(id)
    local list = { { mapID = id, name = 'Niveau 1' } }
    local group = call(C_Map.GetMapGroupID, id)
    local members = group and call(C_Map.GetMapGroupMembersInfo, group)
    if type(members) == 'table' and #members > 0 then
        list = {}
        for _, info in ipairs(members) do
            if number(info.mapID) then list[#list + 1] = { mapID = info.mapID, name = readable(info.name) and info.name } end
        end
    end
    return list
end
local function nativeBosses(mapID, floor)
    local out = {}
    local list = C_EncounterJournal and call(C_EncounterJournal.GetEncountersOnMap, mapID)
    if type(list) == 'table' then
        for _, info in ipairs(list) do
            if number(info.encounterID) and number(info.mapX) and number(info.mapY)
                and info.mapX >= 0 and info.mapX <= 1 and info.mapY >= 0 and info.mapY <= 1 then
                local name = call(EJ_GetEncounterInfo, info.encounterID)
                out[#out + 1] = { name = type(name) == 'string' and name or ('Boss ' .. info.encounterID),
                    x = info.mapX, y = info.mapY, floor = floor, native = true }
            end
        end
    elseif type(EJ_GetMapEncounter) == 'function' then
        for i = 1, 100 do
            local ok, x, y, _, name = pcall(EJ_GetMapEncounter, mapID, i)
            if not ok or not number(x) or not number(y) then break end
            if x >= 0 and x <= 1 and y >= 0 and y <= 1 and readable(name) and type(name) == 'string' then
                out[#out + 1] = { name = name, x = x, y = y, floor = floor, native = true }
            end
        end
    end
    return out
end
local function artFor(mapID)
    local layers = call(C_Map.GetMapArtLayers, mapID)
    local layer = type(layers) == 'table' and layers[1]
    if not (layer and number(layer.layerWidth) and number(layer.layerHeight) and number(layer.tileWidth)
        and number(layer.tileHeight) and layer.layerWidth > 0 and layer.layerHeight > 0
        and layer.tileWidth > 0 and layer.tileHeight > 0) then return nil end
    local textures = call(C_Map.GetMapArtLayerTextures, mapID, 1)
    if type(textures) ~= 'table' or #textures == 0 or #textures > 64 then return nil end
    return { width = layer.layerWidth, height = layer.layerHeight, tw = layer.tileWidth, th = layer.tileHeight, textures = textures }
end
--- Résolution à chaque ouverture : les API du client restent prioritaires sur les données Classic de secours.
function M.Data(code)
    local fallback = Q.DUNGEON_MAPS[code]
    local data = { code = code, floors = {}, bosses = {} }
    local id = nativeMap(code)
    if id then
        for _, floor in ipairs(nativeFloors(id)) do
            local art = artFor(floor.mapID)
            if art then
                local index = #data.floors + 1
                data.floors[index] = { name = floor.name or ('Niveau ' .. index), art = art }
                for _, boss in ipairs(nativeBosses(floor.mapID, index)) do data.bosses[#data.bosses + 1] = boss end
            end
        end
    end
    if #data.floors == 0 and fallback then
        data.classic = true
        local indices = {}
        for i, number in ipairs(fallback.floors) do
            data.floors[i] = { name = 'Niveau ' .. number, artName = fallback.art, page = number,
                image = Q.DUNGEON_MAP_ASSETS and Q.DUNGEON_MAP_ASSETS[fallback.art .. '_' .. number] }
            indices[number] = i
        end
        for _, boss in ipairs(fallback.bosses) do
            if indices[boss.floor] then
                data.bosses[#data.bosses + 1] = { name = boss.name, x = boss.x, y = boss.y, floor = indices[boss.floor] }
            end
        end
    end
    -- Les boss sans position restent dans la liste : on ne les place pas arbitrairement sur la carte.
    local catalogue = Core.GetDungeonBosses and call(Core.GetDungeonBosses, code)
    if type(catalogue) == 'table' and #catalogue > 0 then
        local placed, merged = {}, {}
        for _, boss in ipairs(data.bosses) do placed[plain(boss.name)] = boss end
        for _, boss in ipairs(catalogue) do
            local position = placed[plain(boss.name)]
            merged[#merged + 1] = position or { name = boss.name }
            placed[plain(boss.name)] = nil
        end
        -- Rencontres natives localisées : conserver leurs positions même si le catalogue utilise le nom anglais.
        for _, boss in pairs(placed) do if boss.native then merged[#merged + 1] = boss end end
        data.bosses = merged
    end
    return data
end
local function openLoot(boss)
    if not Core.ShowBossLoot then Q.Print('Installe quinte-bis pour consulter le butin de ce boss.'); return end
    local ok, found = pcall(Core.ShowBossLoot, selected.code, boss.name)
    if not ok then Q.Error('butin du plan', found)
    elseif found == false then Q.Print('Butin non répertorié pour ' .. Q.Safe(boss.name) .. '.')
    else
        -- La fiche BiS s'ouvre dans la fenêtre principale : ne pas la masquer sous le plan en DIALOG.
        window:Hide()
        if GameTooltip then GameTooltip:Hide() end
    end
end
local draw
local function pick(boss, loot)
    if not boss then return end
    window.picked = boss
    if boss.floor then floorAt = boss.floor end
    draw()
    if loot then openLoot(boss) end
end
local function tooltip(pin)
    if not (GameTooltip and pin.boss) then return end
    GameTooltip:SetOwner(pin, 'ANCHOR_RIGHT')
    GameTooltip:SetText(Q.Safe(pin.boss.name))
    GameTooltip:AddLine('Clic : voir le butin de ce boss.', unpack(S.colors.muted))
    if pin.classic then GameTooltip:AddLine('Position Classic indicative sur Forever.', unpack(S.colors.gold)) end
    GameTooltip:Show()
end
local function clearTextures()
    for _, texture in ipairs(window.tiles) do texture:Hide() end
    for _, pin in ipairs(window.pins) do pin:Hide() end
end
local function paintArt(view, floor, mapW, mapH)
    local art = floor.art or { width = 1024, height = 768, tw = 256, th = 256 }
    local scale = math.min(mapW / art.width, mapH / art.height)
    local w, h = art.width * scale, art.height * scale
    view.canvas:SetSize(w, h)
    view.canvas:ClearAllPoints()
    view.canvas:SetPoint('TOPLEFT', view, 'TOPLEFT', (view.artX or 230) + (mapW - w) / 2, (view.artY or -88) - (mapH - h) / 2)
    if floor.image then
        local texture = view.tiles[1]
        if not texture then texture = view.canvas:CreateTexture(nil, 'ARTWORK'); view.tiles[1] = texture end
        texture:SetPoint('TOPLEFT', view.canvas, 'TOPLEFT', 0, 0)
        texture:SetSize(w, h); texture:SetTexCoord(0, 1, 0, 0.75)
        local loaded = texture:SetTexture('Interface\\AddOns\\' .. addonName .. '\\' .. floor.image)
        if loaded ~= false then texture:Show(); return true, w, h end
    end
    local columns, rows = math.ceil(art.width / art.tw), math.ceil(art.height / art.th)
    local loaded = false
    for index = 1, math.min(64, columns * rows) do
        local col, row = (index - 1) % columns, math.floor((index - 1) / columns)
        local tw, th = math.min(art.tw, art.width - col * art.tw), math.min(art.th, art.height - row * art.th)
        local texture = view.tiles[index]
        if not texture then texture = view.canvas:CreateTexture(nil, 'ARTWORK'); view.tiles[index] = texture end
        texture:SetPoint('TOPLEFT', view.canvas, 'TOPLEFT', col * art.tw * scale, -row * art.th * scale)
        texture:SetSize(tw * scale, th * scale)
        texture:SetTexCoord(0, tw / art.tw, 0, th / art.th)
        local file
        if floor.art then file = art.textures[index]
        else file = 'Interface\\WorldMap\\' .. floor.artName .. '\\' .. floor.artName .. floor.page .. '_' .. index end
        local ok = file and texture:SetTexture(file)
        if index == 1 then loaded = ok ~= false and file ~= nil end
        if file then texture:Show() end
    end
    return loaded, w, h
end
local function drawPins(view, data, level, w, h, onPick)
    local n = 0
    for i, boss in ipairs(data.bosses) do
        if boss.floor == level and number(boss.x) and number(boss.y) then
            n = n + 1
            local pin = view.pins[n]
            if not pin then
                pin = CreateFrame('Button', nil, view.canvas)
                pin:SetSize(24, 24)
                pin.icon = pin:CreateTexture(nil, 'OVERLAY'); pin.icon:SetAllPoints()
                pin.icon:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcon_8')
                pin.number = S.Text(pin, 10, S.colors.text, 'CENTER'); pin.number:SetPoint('TOP', pin, 'BOTTOM', 0, 1)
                pin:SetScript('OnClick', function(self) if self.onPick then self.onPick(self.boss) end end)
                pin:SetScript('OnEnter', tooltip)
                pin:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
                view.pins[n] = pin
            end
            pin.boss, pin.classic, pin.onPick = boss, data.classic, onPick
            pin:ClearAllPoints(); pin:SetPoint('CENTER', view.canvas, 'TOPLEFT', boss.x * w, -boss.y * h)
            pin.icon:SetVertexColor(unpack(view.picked == boss and S.colors.gold or S.colors.text))
            pin.number:SetText(i); pin:Show()
        end
    end
end
M.PaintArt, M.DrawPins = paintArt, drawPins
function M.Draw()
    if not window or not selected then return end
    clearTextures()
    floorAt = math.max(1, math.min(floorAt, #selected.floors))
    local floor = selected.floors[floorAt]
    local loaded, w, h
    if floor then loaded, w, h = paintArt(window, floor, MAP_W, MAP_H) end
    window.empty:SetShown(not loaded)
    window.empty:SetText('Carte intérieure non disponible dans cette version du client.\nLes boss connus restent dans la liste.')
    if loaded then drawPins(window, selected, floorAt, w, h, function(boss) pick(boss, true) end) end
    window.level:SetText(floor and (floor.name .. ' (' .. floorAt .. '/' .. #selected.floors .. ')') or 'Aucun étage connu')
    window.prev:SetEnabled(floorAt > 1); window.next:SetEnabled(floorAt < #selected.floors)
    offset = math.max(0, math.min(offset, #selected.bosses - ROWS))
    for i, row in ipairs(window.rows) do
        local boss = selected.bosses[offset + i]
        row.boss = boss; row:SetShown(boss ~= nil)
        if boss then
            row.label:SetText((offset + i) .. '. ' .. Q.Safe(boss.name))
            row:SetSelected(window.picked == boss)
        end
    end
    local missing = 0
    for _, boss in ipairs(selected.bosses) do if not boss.floor then missing = missing + 1 end end
    window.hint:SetText((#selected.floors == 0 and 'Aucune carte intérieure connue.' or selected.classic and 'Carte Classic : positions indicatives à confirmer sur Forever.' or 'Carte et positions fournies par le client.')
        .. (missing > 0 and (' ' .. missing .. ' boss sans position connue.') or '') .. ' Clic sur une icône : butin.')
end
draw = M.Draw
local function create()
    window = S.Box(UIParent, S.colors.bg, S.colors.line)
    window:SetSize(950, 660); window:SetPoint('CENTER'); window:SetFrameStrata('DIALOG')
    window:SetMovable(true); window:EnableMouse(true); window:RegisterForDrag('LeftButton')
    window:SetScript('OnDragStart', function(self) self:StartMoving() end)
    window:SetScript('OnDragStop', function(self) self:StopMovingOrSizing() end)
    window.title = S.Text(window, 16, S.colors.gold); window.title:SetPoint('TOPLEFT', 18, -18); window.title:SetWidth(740)
    local close = S.Button(window, 'Fermer', 72, 24, 'ghost'); close:SetPoint('TOPRIGHT', -12, -12)
    close:SetScript('OnClick', function() window:Hide(); if GameTooltip then GameTooltip:Hide() end end)
    window.prev = S.Button(window, '<', 30, 24, 'ghost'); window.prev:SetPoint('TOPLEFT', 230, -48)
    window.next = S.Button(window, '>', 30, 24, 'ghost'); window.next:SetPoint('TOPRIGHT', -20, -48)
    window.prev:SetScript('OnClick', function() floorAt = floorAt - 1; draw() end)
    window.next:SetScript('OnClick', function() floorAt = floorAt + 1; draw() end)
    window.level = S.Text(window, 12, S.colors.text, 'CENTER'); window.level:SetPoint('TOPLEFT', 265, -53); window.level:SetWidth(620)
    window.canvas = CreateFrame('Frame', nil, window)
    window.tiles, window.pins, window.rows = {}, {}, {}
    local list = S.Box(window, S.colors.panel, S.colors.line); list:SetPoint('TOPLEFT', 14, -48); list:SetSize(200, 565)
    list:EnableMouseWheel(true); list:SetScript('OnMouseWheel', function(_, delta) offset = offset - delta * 2; draw() end)
    local title = S.Heading(list, 'Boss · molette pour défiler'); title:SetPoint('TOPLEFT', 8, -8)
    for i = 1, ROWS do
        local row = S.Row(list, 184, 30); row:SetPoint('TOPLEFT', 8, -34 - (i - 1) * 31)
        row.label = S.Text(row, 11, S.colors.text); row.label:SetPoint('LEFT', 6, 0); row.label:SetWidth(172)
        row:SetScript('OnClick', function(self) pick(self.boss, true) end)
        window.rows[i] = row
    end
    window.empty = S.Text(window, 14, S.colors.muted, 'CENTER'); window.empty:SetPoint('CENTER', window, 'CENTER', 105, 0)
    window.empty:SetWidth(600); window.empty:SetWordWrap(true)
    window.hint = S.Text(window, 11, S.colors.muted); window.hint:SetPoint('BOTTOMLEFT', 18, 16); window.hint:SetWidth(914)
    window.hint:SetWordWrap(true)
end
function Q.ShowDungeonMap(code)
    local dungeon = Q.DUNGEON_BY_CODE[code]
    if not dungeon then return false end
    if not window then create() end
    local same = selected and selected.code == code
    local previousFloor = same and floorAt or 1
    local previousBoss = same and window.picked and plain(window.picked.name)
    selected, floorAt, offset = M.Data(code), previousFloor, 0
    window.picked = nil
    if previousBoss then
        for _, boss in ipairs(selected.bosses) do
            if plain(boss.name) == previousBoss then window.picked = boss; break end
        end
    end
    window.title:SetText('Plan du donjon : ' .. Q.Safe(dungeon.name))
    local width = UIParent.GetWidth and UIParent:GetWidth() or 1024
    local height = UIParent.GetHeight and UIParent:GetHeight() or 768
    window:SetScale(math.max(0.35, math.min(1, (width - 30) / 950, (height - 30) / 660)))
    window:Show(); draw()
    return true
end
Core.ShowDungeonMap = function(code) return Q.Run('plan du donjon', Q.ShowDungeonMap, code) end
