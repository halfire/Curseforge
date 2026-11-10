local addonName, Q = ...
-- Visionneuse propre à Quintessence : cartes du client et repères par étage.
-- Aucun cadre ni crochet sur WorldMapFrame ; les coordonnées intérieures ne sont jamais des waypoints extérieurs.
local Core = Quintessence
local S = Core.Style
local M = {}
Q.DungeonMaps = M
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
    local d = Q.DUNGEON_BY_KEY[code]
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
local function encounterVisual(encounterID)
    if type(EJ_GetCreatureInfo) ~= 'function' then return nil, nil end
    local ok, _, _, _, display, icon = pcall(EJ_GetCreatureInfo, 1, encounterID)
    if ok then return number(display) and display > 0 and display or nil, number(icon) and icon > 0 and icon or nil end
end
local function nativeBosses(mapID, floor)
    local out = {}
    local list = C_EncounterJournal and call(C_EncounterJournal.GetEncountersOnMap, mapID)
    if type(list) == 'table' then
        for _, info in ipairs(list) do
            if number(info.encounterID) and number(info.mapX) and number(info.mapY)
                and info.mapX >= 0 and info.mapX <= 1 and info.mapY >= 0 and info.mapY <= 1 then
                local name = call(EJ_GetEncounterInfo, info.encounterID)
                local display, icon = encounterVisual(info.encounterID)
                out[#out + 1] = { name = type(name) == 'string' and name or ('Boss ' .. info.encounterID),
                    x = info.mapX, y = info.mapY, floor = floor, native = true, display = display, icon = icon }
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
local assetsByName
local function mapAsset(name)
    if not name then return nil end
    if not assetsByName then
        assetsByName = {}
        for key, value in pairs(Q.DUNGEON_MAP_ASSETS or {}) do assetsByName[key:lower()] = value end
    end
    return assetsByName[name:lower()]
end
--- Les plans de la référence demandée gardent leur image et leurs positions ; API natives sinon, puis Classic.
function M.Data(code)
    local fallback = Q.DUNGEON_MAPS[code]
    local data = { code = code, floors = {}, bosses = {} }
    local reference = Q.REFERENCE_MAPS and Q.REFERENCE_MAPS[code]
    local id = not reference and nativeMap(code)
    if id then
        for _, floor in ipairs(nativeFloors(id)) do
            local art = artFor(floor.mapID)
            if art then
                local index = #data.floors + 1
                data.floors[index] = { name = floor.name or ('Niveau ' .. index), mapID = floor.mapID, art = art }
                for _, boss in ipairs(nativeBosses(floor.mapID, index)) do data.bosses[#data.bosses + 1] = boss end
            end
        end
    end
    if #data.floors == 0 and reference then
        data.reference = true
        for i, floor in ipairs(reference.floors) do
            local artName, page
            if floor.tiles then
                artName, page = floor.tiles:match('WorldMap\\([^\\]+)\\.-(%d+)_$')
            end
            data.floors[i] = { name = 'Niveau ' .. i, mapID = floor.uiMapID,
                artName = artName, page = tonumber(page), patches = floor.patches,
                image = floor.image or (artName and mapAsset(artName .. '_' .. page)),
                texBottom = floor.texBottom, textureWidth = floor.image and 1024 or nil,
                height = floor.image and (floor.texBottom or 1) * 1024 or nil }
        end
        for _, boss in ipairs(reference.bosses) do
            local copy = {}; for k, v in pairs(boss) do copy[k] = v end
            data.bosses[#data.bosses + 1] = copy
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
        for _, boss in ipairs(data.bosses) do if placed[plain(boss.name)] and (boss.native or data.reference) then merged[#merged + 1] = boss end end
        data.bosses = merged
    end
    for _, boss in ipairs(data.bosses) do
        local visual = (Q.REFERENCE_PORTRAITS and Q.REFERENCE_PORTRAITS[boss.name]) or (Q.DUNGEON_BOSS_PORTRAITS and Q.DUNGEON_BOSS_PORTRAITS[boss.name])
        if visual then boss.image, boss.icon = visual.image, visual.icon or boss.icon end
        if visual then boss.display = boss.display or visual.display; boss.npc = visual.npc end
    end
    return data
end
local function tooltip(pin)
    if not (GameTooltip and pin.boss) then return end
    GameTooltip:SetOwner(pin, 'ANCHOR_RIGHT')
    GameTooltip:SetText(Q.Safe(pin.boss.name))
    GameTooltip:AddLine(pin.boss.quest and 'Clic : voir la quête de cet objectif.' or 'Clic : voir le butin de ce boss.', S.colors.muted[1], S.colors.muted[2], S.colors.muted[3], true)
    if pin.classic then GameTooltip:AddLine('Position Classic indicative sur Forever.', S.colors.gold[1], S.colors.gold[2], S.colors.gold[3], true) end
    GameTooltip:Show()
end
local function paintPatches(view, floor, w, h)
    view.mapPatches = view.mapPatches or {}
    for _, texture in ipairs(view.mapPatches) do texture:Hide() end
    for i, patch in ipairs(floor.patches or {}) do
        local texture = view.mapPatches[i]
        if not texture then texture = view.canvas:CreateTexture(nil, 'ARTWORK', nil, 2); view.mapPatches[i] = texture end
        texture:ClearAllPoints(); texture:SetPoint('TOPLEFT', view.canvas, 'TOPLEFT', patch.x0 * w, -patch.y0 * h)
        texture:SetSize((patch.x1 - patch.x0) * w, (patch.y1 - patch.y0) * h)
        texture:SetTexture('Interface\\AddOns\\' .. addonName .. '\\' .. patch.image)
        texture:SetAlpha(patch.alpha or 1); texture:Show()
    end
end
local function paintArt(view, floor, mapW, mapH)
    -- Le canevas Classic utile mesure 1002 × 668 : les tuiles BLP incluent du noir de remplissage.
    local art = floor.art or { width = floor.textureWidth or 1002, height = floor.height or 668, tw = 256, th = 256 }
    local scale = math.min(mapW / art.width, mapH / art.height)
    local w, h = view.fill and mapW or art.width * scale, view.fill and mapH or art.height * scale
    local sx, sy = w / art.width, h / art.height
    view.canvas:SetSize(w, h)
    view.canvas:ClearAllPoints()
    view.canvas:SetPoint('TOPLEFT', view, 'TOPLEFT', (view.artX or 230) + (mapW - w) / 2, (view.artY or -88) - (mapH - h) / 2)
    if floor.image then
        local texture = view.tiles[1]
        if not texture then texture = view.canvas:CreateTexture(nil, 'ARTWORK'); view.tiles[1] = texture end
        texture:SetPoint('TOPLEFT', view.canvas, 'TOPLEFT', 0, 0)
        texture:SetSize(w, h); texture:SetTexCoord(0, floor.textureWidth and 1 or 1002 / 1024, 0, floor.texBottom or 668 / 1024)
        local loaded = texture:SetTexture('Interface\\AddOns\\' .. addonName .. '\\' .. floor.image)
        if loaded ~= false then texture:Show(); paintPatches(view, floor, w, h); return true, w, h end
    end
    local columns, rows = math.ceil(art.width / art.tw), math.ceil(art.height / art.th)
    local loaded = false
    for index = 1, math.min(64, columns * rows) do
        local col, row = (index - 1) % columns, math.floor((index - 1) / columns)
        local tw, th = math.min(art.tw, art.width - col * art.tw), math.min(art.th, art.height - row * art.th)
        local texture = view.tiles[index]
        if not texture then texture = view.canvas:CreateTexture(nil, 'ARTWORK'); view.tiles[index] = texture end
        texture:SetPoint('TOPLEFT', view.canvas, 'TOPLEFT', col * art.tw * sx, -row * art.th * sy)
        texture:SetSize(tw * sx, th * sy)
        texture:SetTexCoord(0, tw / art.tw, 0, th / art.th)
        local file
        if floor.art then file = art.textures[index]
        else file = 'Interface\\WorldMap\\' .. floor.artName .. '\\' .. floor.artName .. floor.page .. '_' .. index end
        local ok = file and texture:SetTexture(file)
        if index == 1 then loaded = ok ~= false and file ~= nil end
        if file then texture:Show() end
    end
    paintPatches(view, floor, w, h)
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
                pin:SetSize(30, 30)
                pin.icon = pin:CreateTexture(nil, 'OVERLAY'); pin.icon:SetAllPoints()
                pin.icon:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcon_8')
                pin.number = pin:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall'); pin.number:SetJustifyH('CENTER'); pin.number:SetPoint('TOP', pin, 'BOTTOM', 0, 1)
                pin:SetScript('OnClick', function(self)
                    if self.boss.quest and M.ToggleQuestList then
                        local owner = self.mapView
                        if not owner.questList or not owner.questList:IsShown() then M.ToggleQuestList(owner) end
                        owner.selectedQuest = self.boss.quest
                        for index, quest in ipairs(owner.questRecords or {}) do
                            if quest.id == self.boss.quest then owner.questList.offset = index - 1; break end
                        end
                        M.RefreshQuestList(owner)
                    elseif self.onPick then self.onPick(self.boss) end
                end)
                pin:SetScript('OnEnter', tooltip)
                pin:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
                view.pins[n] = pin
            end
            pin.boss, pin.classic, pin.onPick, pin.mapView = boss, data.classic, onPick, view
            pin:ClearAllPoints(); pin:SetPoint('CENTER', view.canvas, 'TOPLEFT', boss.x * w, -boss.y * h)
            -- Les portraits sont rendus par le client, sans téléchargement en jeu.
            pin.icon:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcon_8')
            if boss.image then pin.icon:SetTexture('Interface\\AddOns\\' .. addonName .. '\\' .. boss.image)
            elseif boss.icon then pin.icon:SetTexture(boss.icon)
            elseif number(boss.display) and type(SetPortraitTextureFromCreatureDisplayID) == 'function' then
                pcall(SetPortraitTextureFromCreatureDisplayID, pin.icon, boss.display)
            end
            pin.icon:SetVertexColor(1, 1, 1, 1)
            pin.number:SetTextColor(unpack(view.picked == boss and {1,0.82,0} or {1,1,1}))
            pin.number:SetText(i); pin:Show()
        end
    end
end
M.PaintArt, M.DrawPins = paintArt, drawPins

-- Commandes natives pour la carte du jeu, indépendantes du thème Quintessence.
function M.NativeText(parent, size, color, justify)
    local text = parent:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    text:SetJustifyH(justify or 'LEFT')
    if color then text:SetTextColor(unpack(color)) end
    return text
end
function M.NativeButton(parent, label, width, height)
    local button = CreateFrame('Button', nil, parent, 'UIPanelButtonTemplate')
    button:SetSize(width, height); button:SetText(label)
    function button:SetLabel(value) self:SetText(value) end
    function button:SetActive(active)
        -- Une aile sélectionnée reste identifiable sans couleur du thème de la guilde.
        self:SetButtonState(active and 'PUSHED' or 'NORMAL', active)
    end
    return button
end
function M.Clear(view)
    for _, field in ipairs({ 'tiles', 'pins', 'questPins', 'mapPatches' }) do
        for _, object in ipairs(view[field] or {}) do object:Hide() end
    end
end
local embedded
function M.CreateEmbedded(parent, width, height, onPick)
    local view = CreateFrame('Frame', nil, parent)
    view:SetSize(width, height); view.artX, view.artY = 0, -30
    view.canvas = CreateFrame('Frame', nil, view)
    view.controls = CreateFrame('Frame', nil, view); view.controls:SetAllPoints(view)
    view.controls:SetFrameLevel(view:GetFrameLevel() + 10)
    view.tiles, view.pins, view.floor = {}, {}, 1
    view.previous = S.Button(view.controls, '<', 26, 22, 'ghost'); view.previous:SetPoint('TOPLEFT')
    view.next = S.Button(view.controls, '>', 26, 22, 'ghost'); view.next:SetPoint('LEFT', view.previous, 'RIGHT', 4, 0)
    view.title = S.Text(view.controls, 11); view.title:SetPoint('TOPLEFT', 66, -6); view.title:SetWidth(width - 190)
    view.quests = S.Button(view.controls, 'Quêtes', 110, 22, 'ghost'); view.quests:SetPoint('TOPRIGHT')
    view.quests:SetScript('OnClick', function() if M.ToggleQuestList then M.ToggleQuestList(view) end end)
    view.onPick = onPick
    local function redraw() M.RenderEmbedded(view) end
    view.previous:SetScript('OnClick', function() view.floor = view.floor - 1; redraw() end)
    view.next:SetScript('OnClick', function() view.floor = view.floor + 1; redraw() end)
    view.onQuestSelect = redraw
    embedded = view
    return view
end
function M.RenderEmbedded(view)
    M.Clear(view)
    local data = view.data
    if not data or #data.floors == 0 then view:Hide(); return false end
    view.floor = math.max(1, math.min(view.floor, #data.floors))
    local floor = data.floors[view.floor]
    local loaded, w, h = M.PaintArt(view, floor, view:GetWidth(), view:GetHeight() - 30)
    if loaded then
        M.DrawPins(view, data, view.floor, w, h, view.onPick)
        if M.DrawQuestPins then M.DrawQuestPins(view, data, view.floor, w, h) end
    end
    view.title:SetText(floor.name .. ' (' .. view.floor .. '/' .. #data.floors .. ')' .. (data.classic and ' · Classic, indicatif' or ''))
    view.previous:SetEnabled(view.floor > 1); view.next:SetEnabled(view.floor < #data.floors)
    view.questRecords = M.QuestRecords and M.QuestRecords(data.code) or {}; view.questData = data
    view.quests:SetLabel('Quêtes (' .. #view.questRecords .. ')')
    if M.RefreshQuestList then M.RefreshQuestList(view) end
    view:Show()
    return true
end
function M.ShowEmbedded(view, code, bossName)
    local changed = view.code ~= code
    if changed then view.data = M.Data(code); view.code = code; view.floor = 1; view.selectedQuest = nil end
    if changed or view.bossName ~= bossName then
        view.bossName, view.picked = bossName, nil
        for _, boss in ipairs(view.data.bosses) do
            if plain(boss.name) == plain(bossName) then
                view.picked = boss; view.floor = boss.floor or 1; break
            end
        end
    end
    return M.RenderEmbedded(view)
end
function M.RefreshVisible()
    if embedded and embedded:IsVisible() then M.RenderEmbedded(embedded) end
end
function Q.ShowDungeonMap(code)
    if not Q.DUNGEON_BY_KEY[code] then return false end
    return Q.UI.ShowLoot(code)
end
function Core.ShowDungeonMap(code)
    local ok, result = Q.Run('plan du donjon', Q.ShowDungeonMap, code)
    return ok and result
end
