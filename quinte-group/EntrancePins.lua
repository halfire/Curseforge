local _, Q = ...
local Core = Quintessence
local pins, overlay, lastMap, points, geometry = {}, nil, nil, nil, nil

-- Positions extérieures complémentaires : journal ForeverDungeonJournal 2.0 et relevé Entrances.lua.
local extra = {
    { 'ULDA', 1418, .66, .43, 'Uldaman — entrée arrière', true },
    { 'STRAT', 1423, .44, .19, 'Stratholme — entrée de service' },
}
local corrected = {
    STRAT = { 1423, .30, .15 }, RFD = { 1413, .50, .92 }, KROLDOK = { 2548, .375, .373 },
    DALARAN = { 1416, .085, .593 },
}
local function readable(value)
    return not (issecretvalue and issecretvalue(value))
end
local function number(value)
    return readable(value) and type(value) == 'number' and value == value and math.abs(value) < math.huge
end
local function read(fn, ...)
    if type(fn) ~= 'function' then return end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok and readable(a) and readable(b) and readable(c) and readable(d) then return a, b, c, d end
end

local function project(source, target, x, y)
    if source == target then return x, y end
    local parent = source
    for _ = 1, 8 do
        local info = read(C_Map.GetMapInfo, parent)
        parent = type(info) == 'table' and info.parentMapID
        if not number(parent) or parent <= 0 then return end
        if parent == target then
            local continent, world = read(C_Map.GetWorldPosFromMapPos, source, read(CreateVector2D, x, y))
            if not (number(continent) and world) then return end
            local map, pos = read(C_Map.GetMapPosFromWorldPos, continent, world, target)
            if map == target and pos then return read(pos.GetXY, pos) end
            return
        end
    end
end

local function collect(map)
    local list, byPosition = {}, {}
    local function add(source, x, y, label, approximate)
        if not source then return end
        x, y = project(source, map, x, y)
        if not (number(x) and number(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1) then return end
        local key = string.format('%.5f:%.5f', x, y)
        local point = byPosition[key]
        if not point then
            point = { x = x, y = y, labels = {} }
            byPosition[key] = point
            list[#list + 1] = point
        end
        point.labels[#point.labels + 1] = label .. (approximate and ' (approximatif)' or '')
    end
    for _, dungeon in ipairs(Q.FOREVER_DUNGEONS) do
        local code = dungeon.code
        local e, ref = Q.ENTRANCES[code], corrected[code]
        if e then
            local source = Q.EntranceMap(e.zone)
            if ref and read(C_Map.GetMapInfo, ref[1]) then
                add(ref[1], ref[2], ref[3], code == 'STRAT' and 'Stratholme — entrée principale' or dungeon.name)
            else
                add(source, e.x / 100, e.y / 100, dungeon.name, e.approx)
            end
            if code == 'LBRS' then
                add(source, e.x / 100, e.y / 100, 'Pic Rochenoire supérieur', e.approx)
            end
        end
    end
    for _, e in ipairs(extra) do
        local entry = Q.ENTRANCES[e[1]]
        add(Q.EntranceMap(entry.zone) or (read(C_Map.GetMapInfo, e[2]) and e[2]), e[3], e[4], e[5], e[6])
    end
    return list
end

local function marker(index)
    if pins[index] then return pins[index] end
    local pin = CreateFrame('Button', nil, overlay)
    pin:SetSize(19, 19)
    local icon = pin:CreateTexture(nil, 'ARTWORK')
    icon:SetAllPoints()
    local atlas = icon.SetAtlas and (not C_Texture or not C_Texture.GetAtlasInfo or read(C_Texture.GetAtlasInfo, 'Dungeon'))
    if not atlas or not pcall(icon.SetAtlas, icon, 'Dungeon', false) then
        icon:SetTexture('Interface\\Icons\\INV_Misc_Rune_01')
    end
    pin:SetScript('OnEnter', function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
        GameTooltip:SetText('Entrées de donjon')
        for _, label in ipairs(self.labels) do GameTooltip:AddLine(Q.Safe(label), 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    pin:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
    pins[index] = pin
    return pin
end

local function hide()
    if overlay then overlay:Hide() end
    lastMap, geometry = nil, nil
end
local function refresh()
    local map = WorldMapFrame
    if not Q.EntrancePinsEnabled() or Core.GuildBlocked() or not C_Map or not map or read(map.IsShown, map) ~= true then
        hide()
        return
    end
    local id = read(map.GetMapID, map)
    local canvas = read(map.GetCanvas, map)
    local viewport = map.ScrollContainer
    if not number(id) or not canvas or not viewport then hide(); return end
    if id ~= lastMap then
        lastMap, points, geometry = id, collect(id), nil
    end
    if #points == 0 then if overlay then overlay:Hide() end; return end
    local left, bottom, width, height = read(canvas.GetRect, canvas)
    local vl, vb, vw, vh = read(viewport.GetRect, viewport)
    local cs, vs, ui = read(canvas.GetEffectiveScale, canvas), read(viewport.GetEffectiveScale, viewport), read(UIParent.GetEffectiveScale, UIParent)
    if not (number(left) and number(bottom) and number(width) and number(height) and width > 0 and height > 0
        and number(vl) and number(vb) and number(vw) and number(vh)
        and number(cs) and cs > 0 and number(vs) and vs > 0 and number(ui) and ui > 0) then
        hide()
        return
    end
    local strata, level = read(map.GetFrameStrata, map), read(map.GetFrameLevel, map)
    local signature = table.concat({left, bottom, width, height, vl, vb, vw, vh, cs, vs, ui, strata or '', level or ''}, ':')
    if signature == geometry then return end
    geometry = signature
    if not overlay then
        overlay = CreateFrame('Frame', nil, UIParent)
        overlay:SetAllPoints(UIParent)
    end
    overlay:SetFrameStrata((strata == 'FULLSCREEN' or strata == 'FULLSCREEN_DIALOG') and 'FULLSCREEN_DIALOG' or 'DIALOG')
    overlay:SetFrameLevel(number(level) and level + 5 or 5)
    local n = 0
    local l, b, r, t = vl * vs / ui, vb * vs / ui, (vl + vw) * vs / ui, (vb + vh) * vs / ui
    for _, p in ipairs(points) do
        local x, y = (left + p.x * width) * cs / ui, (bottom + (1 - p.y) * height) * cs / ui
        if x >= l + 10 and x <= r - 10 and y >= b + 10 and y <= t - 10 then
            n = n + 1
            local pin = marker(n)
            pin.labels = p.labels
            pin:ClearAllPoints()
            pin:SetPoint('CENTER', overlay, 'BOTTOMLEFT', x, y)
            pin:Show()
        end
    end
    for i = n + 1, #pins do pins[i]:Hide() end
    overlay:Show()
end

function Q.EntrancePinsEnabled()
    local settings = QuinteGroupDB and QuinteGroupDB.settings
    return not settings or settings.entrancePins ~= false
end

local elapsed = 0
local driver = CreateFrame('Frame')
local function update(_, delta)
    elapsed = elapsed + delta
    if elapsed < .08 then return end
    elapsed = 0
    Q.Run('repères d’entrée des donjons', refresh)
end
local function apply()
    driver:SetScript('OnUpdate', Q.EntrancePinsEnabled() and update or nil)
    Q.Run('repères d’entrée des donjons', refresh)
end
Core.DungeonEntrancePins = {
    Enabled = Q.EntrancePinsEnabled,
    Toggle = function()
        if not QuinteGroupDB then return end
        QuinteGroupDB.settings = QuinteGroupDB.settings or {}
        QuinteGroupDB.settings.entrancePins = not Q.EntrancePinsEnabled()
        apply()
    end,
}
driver:RegisterEvent('PLAYER_LOGIN')
driver:RegisterEvent('PLAYER_ENTERING_WORLD')
driver:SetScript('OnEvent', function()
    hide()
    apply()
end)
