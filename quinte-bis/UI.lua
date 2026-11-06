local _, Q = ...
--[[
  Onglet « BiS & donjons » de la fenêtre Quintessence, deux vues :
    Ma liste BiS        un objet par emplacement (glisser-déposer, Maj+clic sur un objet du jeu, numéro, lien ou adresse
                        Wowhead) et où le trouver
    Butin des boss      une carte par instance, puis boss par boss : un clic met l'objet dans la liste
    Besoins par donjon  pour chaque donjon, les membres qui y cherchent encore un objet : chuchoter, inviter
  Règle Retail 12+ : uniquement nos propres cadres, aucune écriture dans les objets de Blizzard.
]]
local UI = {}
Q.UI = UI
local S = Quintessence.Style
local SOURCE_ROWS, DUNGEON_ROWS, MEMBER_ROWS = 9, 10, 8
local QUALITY_HEX = { [0] = 'ff9d9d9d', 'ffffffff', 'ff1eff00', 'ff0070dd', 'ffa335ee', 'ffff8000', 'ffe6cc80' }
local frame
local state = { view = 'list', slot = 1, sourceOffset = 0, dungeonOffset = 0, memberOffset = 0, dungeon = nil, onlineOnly = false, needs = {},
    raid = nil, boss = 1, bossOffset = 0, lootOffset = 0, slotOnly = false, picked = nil, cardOffset = 0, cardsPlaced = false }
local BOSS_ROWS, LOOT_ROWS = 14, 10
local CARD_COLUMNS, CARD_ROWS, CARD_W, CARD_H, CARD_GAP = 4, 6, 181, 56, 5
local CODE_NAMES = { HEAD = 'Tête', NECK = 'Cou', SHOULDER = 'Épaules', CLOAK = 'Dos', CHEST = 'Torse', WRIST = 'Poignets', HAND = 'Mains',
    WAIST = 'Taille', LEGS = 'Jambes', FEET = 'Pieds', FINGER = 'Doigt', TRINKET = 'Bijou', WEAPON = 'Une main', WEAPONMAINHAND = 'Main droite',
    ['2HWEAPON'] = 'Deux mains', WEAPONOFFHAND = 'Main gauche', SHIELD = 'Bouclier', HOLDABLE = 'Tenu en main gauche', RANGED = 'À distance',
    RELIC = 'Relique', THROWN = 'Arme de jet' }
local refreshPending = false

local function itemText(id, fallback)
    local name, quality = Q.ItemName(id)
    -- (pas encore en cache : nom anglais des tables de butin en attendant le nom du jeu)
    if not name then return '|cff94a1b8' .. (fallback and Q.Safe(fallback) or ('Objet #' .. id)) .. '…|r' end
    return '|c' .. (QUALITY_HEX[quality or 1] or 'ffffffff') .. Q.Safe(name) .. '|r'
end
local function showItemTooltip(owner, id)
    if not id or not GameTooltip then return end
    GameTooltip:SetOwner(owner, 'ANCHOR_RIGHT')
    Q.Call(GameTooltip.SetHyperlink, GameTooltip, 'item:' .. id)
    GameTooltip:Show()
end
local function hideTooltip() if GameTooltip then GameTooltip:Hide() end end
-- Objet tenu par le curseur (glissé depuis les sacs, la fiche personnage, AtlasLoot…)
local function cursorItem()
    local ok, kind, id, link = Q.Call(GetCursorInfo)
    if not ok or kind ~= 'item' then return nil end
    return Q.ParseItem(id) or Q.ParseItem(link)
end
local function dropOn(slot)
    local id = cursorItem()
    if not id then return false end
    Q.Call(ClearCursor)
    local ok, result = Q.SetItem(slot, id)
    if ok then state.slot = result else Q.Print(result) end
    return true
end

-- ---------------------------------------------------------------------------------------------- Ma liste BiS
local function renderList()
    local v, c = frame.list, Q.Mine()
    for i, slot in ipairs(Q.SLOTS) do
        local row, item = v.rows[i], c.items[slot]
        row.slot = slot; row.item = item and item.item
        row:SetSelected(state.slot == slot)
        if item then
            row.icon:SetTexture(Q.ItemIcon(item.item)); row.icon:Show()
            row.label:SetText(itemText(item.item))
            row.source:SetText(item.obtained and '|cff5cd1a8obtenu|r' or (item.source and Q.Safe(Q.DungeonName(item.source)) or '|cffe5545csource ?|r'))
        else
            row.icon:Hide(); row.label:SetText('|cff94a1b8— vide —|r'); row.source:SetText('')
        end
    end
    -- Éditeur de l'emplacement choisi
    local e, item = v.editor, c.items[state.slot]
    e.title:SetText(Q.SLOT_NAMES[state.slot] or '?')
    if item then
        e.icon:SetTexture(Q.ItemIcon(item.item)); e.icon:Show()
        e.name:SetText(itemText(item.item))
        local bossName, bossIn = Q.BossOf(item.item)
        local bossText = (bossName and bossIn == item.source) and (' · ' .. Q.Safe(bossName)) or ''
        e.where:SetText(item.source and (Q.Safe(Q.DungeonName(item.source)) .. bossText .. '  |cff94a1b8' .. Q.DungeonLevels(item.source) .. '|r')
            or '|cffe5545cChoisis où le trouver ci-dessous.|r')
    else
        e.icon:Hide(); e.name:SetText('|cff94a1b8Aucun objet choisi|r'); e.where:SetText('Fais Maj+clic sur un objet du jeu, glisse-le ici ou colle son numéro / adresse Wowhead.')
    end
    e.obtained:SetShown(item ~= nil); e.clear:SetShown(item ~= nil)
    e.obtained:SetActive(item and item.obtained); e.obtained:SetLabel(item and item.obtained and 'Obtenu' or 'Marquer obtenu')
    local sourceList = Q.LEVELING_SOURCES or Q.DUNGEONS
    local total = #sourceList
    state.sourceOffset = math.max(0, math.min(state.sourceOffset, total - SOURCE_ROWS))
    for i = 1, SOURCE_ROWS do
        local row, d = e.sources[i], sourceList[state.sourceOffset + i]
        row.key = d and d.key
        if d and item then
            row.label:SetText(Q.Safe(d.name)); row.levels:SetText(Q.DungeonLevels(d.key))
            row:SetSelected(item.source == d.key); row:Show()
        else row:Hide() end
    end
    e.sourceBox:SetShown(item ~= nil); e.sourceHeading:SetShown(item ~= nil)
    e.scroll:SetMinMaxValues(0, math.max(0, total - SOURCE_ROWS)); e.scroll:SetValue(state.sourceOffset); e.scroll:SetShown(item ~= nil)
end

local function createList(parent)
    local v = CreateFrame('Frame', nil, parent)
    v:SetPoint('TOPLEFT', 0, -40); v:SetPoint('BOTTOMRIGHT')
    local box = S.Box(v, S.colors.panel, S.colors.line); box:SetPoint('TOPLEFT', 0, 0); box:SetSize(330, 400)
    v.rows = {}
    for i in ipairs(Q.SLOTS) do
        local row = S.Row(v, 328, 22); row:SetPoint('TOPLEFT', 1, -4 - (i - 1) * 23)
        row.slotLabel = S.Text(row, 11, S.colors.muted); row.slotLabel:SetPoint('LEFT', 10, 0); row.slotLabel:SetWidth(70)
        row.slotLabel:SetText(Q.SLOT_NAMES[Q.SLOTS[i]])
        row.icon = row:CreateTexture(nil, 'ARTWORK'); row.icon:SetSize(16, 16); row.icon:SetPoint('LEFT', 82, 0); row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.label = S.Text(row, 12, S.colors.text); row.label:SetPoint('LEFT', 104, 0); row.label:SetWidth(132)
        row.source = S.Text(row, 10, S.colors.muted, 'RIGHT'); row.source:SetPoint('RIGHT', -8, 0); row.source:SetWidth(90)
        row:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        row:SetScript('OnClick', function(self, button)
            -- Clic droit : retire l'objet de cette ligne
            if button == 'RightButton' then
                if self.item then Q.Run('retirer', function() Q.ClearSlot(self.slot); UI.Refresh() end) end
                return
            end
            if self.item and Quintessence.LinkItem(self.item) then return end
            Q.Run('emplacement', function() if not dropOn(self.slot) then state.slot = self.slot end; UI.Refresh() end)
        end)
        row:SetScript('OnReceiveDrag', function(self) Q.Run('glisser', function() dropOn(self.slot); UI.Refresh() end) end)
        row:SetScript('OnEnter', function(self) showItemTooltip(self, self.item) end)
        row:SetScript('OnLeave', hideTooltip)
        v.rows[i] = row
    end

    local e = S.Box(v, S.colors.panel, S.colors.line, 'Button'); e:SetPoint('TOPLEFT', 342, 0); e:SetSize(418, 400)
    e:SetScript('OnReceiveDrag', function() Q.Run('glisser', function() dropOn(state.slot); UI.Refresh() end) end)
    e:SetScript('OnClick', function() Q.Run('glisser', function() if dropOn(state.slot) then UI.Refresh() end end) end)
    e.title = S.Heading(e, ''); e.title:SetPoint('TOPLEFT', 16, -14)
    local fromRaid = S.Button(e, 'Choisir chez un boss', 150, 22, 'ghost'); fromRaid:SetPoint('TOPRIGHT', -16, -10)
    fromRaid:SetScript('OnClick', function() state.view = 'loot'; state.lootOffset = 0; state.picked = nil; Q.Run('vue', UI.Refresh) end)
    e.icon = e:CreateTexture(nil, 'ARTWORK'); e.icon:SetSize(36, 36); e.icon:SetPoint('TOPLEFT', 16, -32); e.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    e.name = S.Text(e, 15, S.colors.text); e.name:SetPoint('TOPLEFT', 60, -34); e.name:SetWidth(340)
    e.where = S.Text(e, 11, S.colors.muted); e.where:SetPoint('TOPLEFT', 60, -54); e.where:SetWidth(340)
    e.input = S.Input(e, 278, 'Numéro, lien ou adresse Wowhead'); e.input:SetPoint('TOPLEFT', 16, -82)
    local function submit()
        Q.Run('saisie', function()
            local ok, result = Q.SetItem(state.slot, e.input:GetText())
            if ok then state.slot = result; e.input:SetText(''); e.input:ClearFocus() else Q.Print(result) end
            UI.Refresh()
        end)
    end
    e.input:SetScript('OnTextChanged', function(box) box.placeholder:SetShown((box:GetText() or '') == '') end)
    e.input:SetScript('OnEnterPressed', submit)
    local add = S.Button(e, 'Valider', 100, 26, 'primary'); add:SetPoint('TOPLEFT', 302, -82); add:SetScript('OnClick', submit)
    e.sourceHeading = S.Heading(e, 'Où le trouver'); e.sourceHeading:SetPoint('TOPLEFT', 16, -122)
    e.sourceBox = S.Box(e, S.colors.bg, S.colors.line); e.sourceBox:SetPoint('TOPLEFT', 16, -138); e.sourceBox:SetSize(386, SOURCE_ROWS * 22 + 6)
    e.sources = {}
    for i = 1, SOURCE_ROWS do
        local row = S.Row(e, 370, 21); row:SetPoint('TOPLEFT', 17, -141 - (i - 1) * 22)
        row.label = S.Text(row, 12, S.colors.text); row.label:SetPoint('LEFT', 10, 0); row.label:SetWidth(280)
        row.levels = S.Text(row, 10, S.colors.muted, 'RIGHT'); row.levels:SetPoint('RIGHT', -8, 0)
        row:SetScript('OnClick', function(self)
            Q.Run('source', function()
                local item = Q.Mine().items[state.slot]
                if item and self.key then Q.SetSource(state.slot, item.source ~= self.key and self.key or nil) end
                UI.Refresh()
            end)
        end)
        e.sources[i] = row
    end
    e.scroll = S.Scrollbar(e, SOURCE_ROWS * 22, function(offset) if offset ~= state.sourceOffset then state.sourceOffset = offset; Q.Run('défilement', renderList) end end)
    e.scroll:SetPoint('TOPLEFT', 392, -141)
    e.sourceBox:EnableMouseWheel(true)
    e.sourceBox:SetScript('OnMouseWheel', function(_, delta) state.sourceOffset = state.sourceOffset - delta * 3; Q.Run('défilement', renderList) end)
    e.obtained = S.Button(e, 'Marquer obtenu', 150, 28, 'ghost'); e.obtained:SetPoint('BOTTOMLEFT', 16, 14)
    e.obtained:SetScript('OnClick', function()
        Q.Run('obtenu', function() local item = Q.Mine().items[state.slot]; if item then Q.SetObtained(state.slot, not item.obtained) end; UI.Refresh() end)
    end)
    e.clear = S.Button(e, 'Retirer', 100, 28, 'danger'); e.clear:SetPoint('BOTTOMRIGHT', -16, 14)
    e.clear:SetScript('OnClick', function() Q.Run('retirer', function() Q.ClearSlot(state.slot); UI.Refresh() end) end)
    local hint = S.Text(e, 10, S.colors.muted); hint:SetPoint('BOTTOMLEFT', 16, 50); hint:SetWidth(386); hint:SetWordWrap(true)
    hint:SetText('Les objets portés ou dans tes sacs passent seuls en « obtenu ». Ta liste part à la guilde par la synchro.')
    v.editor = e
    return v
end

-- ---------------------------------------------------------------------------------------------- Butin des raids
-- Deux catalogues : donjons de Forever (DungeonLoot.lua) et raids (RaidLoot.lua), présentés ensemble en cartes.
-- Une instance sans table de butin (pas encore ouverte ou pas encore relevée) garde sa carte, éteinte.
local lootByKey
local function lootOf(key)
    if not lootByKey then
        lootByKey = {}
        for _, list in ipairs({ Q.DUNGEON_LOOT or {}, Q.RAID_LOOT or {} }) do
            for _, raid in ipairs(list) do lootByKey[raid.key] = raid end
        end
    end
    if not key then return nil end
    if lootByKey[key] then return lootByKey[key] end
    -- Pas de table, mais la guilde y a vu du butin (Learn.lua)
    if #Q.SeenFor(key) > 0 then return { key = key, bosses = {} } end
    return nil
end
local instanceCards
local function instances()
    if not instanceCards then
        instanceCards = {}
        for _, d in ipairs(Q.DUNGEONS or {}) do
            if not d.other then instanceCards[#instanceCards + 1] = d end
        end
    end
    return instanceCards
end
local function isMyLevel(d)
    local level = UnitLevel and UnitLevel('player') or 0
    return not d.raid and d.min and level >= d.min and level <= d.max
end
-- Objets d'un boss qui se portent, filtrés sur l'emplacement choisi dans la liste si le filtre est actif
local function visibleItems(boss)
    local out = {}
    for _, it in ipairs(boss and boss.items or {}) do
        local code = Q.LootCode(it)
        if code and (not state.slotOnly or Q.Fits(code, state.slot)) then out[#out + 1] = it end
    end
    return out
end
local function renderCards()
    local v, list = frame.loot, instances()
    local totalRows = math.ceil(#list / CARD_COLUMNS)
    local maxOffset = math.max(0, totalRows - CARD_ROWS)
    -- Première ouverture : la grille commence aux donjons de son niveau
    if not state.cardsPlaced then
        state.cardsPlaced = true
        for i, d in ipairs(list) do
            if isMyLevel(d) then state.cardOffset = math.floor((i - 1) / CARD_COLUMNS); break end
        end
    end
    state.cardOffset = math.max(0, math.min(state.cardOffset, maxOffset))
    for i, card in ipairs(v.cardButtons) do
        local d = list[state.cardOffset * CARD_COLUMNS + i]
        local loot = d and lootOf(d.key)
        card.key = loot and d.key or nil
        if d then
            local mine = isMyLevel(d)
            local levels = Q.DungeonLevels(d.key)
            local parts = {}
            if d.raid then parts[#parts + 1] = '|cffe6b450Raid|r' end
            if levels ~= '' then parts[#parts + 1] = levels end
            local shown = loot and #loot.bosses or 0
            if shown > 0 then parts[#parts + 1] = shown .. ' boss' elseif loot then parts[#parts + 1] = 'vu par la guilde' else parts[#parts + 1] = 'butin inconnu' end
            if mine then parts[#parts + 1] = '|cff5cd1a8ton niveau|r' end
            card.label:SetText((loot and '' or '|cff94a1b8') .. Q.Safe(d.name) .. (loot and '' or '|r'))
            card.info:SetText(table.concat(parts, ' · '))
            card.hover:SetShown(loot ~= nil)
            if card.SetBackdropBorderColor then card:SetBackdropBorderColor(unpack(mine and S.colors.gold or S.colors.line)) end
            card:Show()
        else card:Hide() end
    end
    v.cardScroll:SetMinMaxValues(0, maxOffset); v.cardScroll:SetValue(state.cardOffset)
end
local function renderLoot()
    local v, raid = frame.loot, lootOf(state.raid)
    v.cards:SetShown(not raid); v.detail:SetShown(raid ~= nil)
    if not raid then return renderCards() end
    local levels = Q.DungeonLevels(raid.key)
    v.dungeonName:SetText(Q.Safe(raid.name or Q.DungeonName(raid.key)) .. (levels ~= '' and ('  |cff94a1b8' .. levels .. '|r') or ''))
    local bosses = Q.LootBosses(raid)
    state.boss = math.max(1, math.min(state.boss, #bosses))
    state.bossOffset = math.max(0, math.min(state.bossOffset, #bosses - BOSS_ROWS))
    for i = 1, BOSS_ROWS do
        local row, index = v.bossRows[i], state.bossOffset + i
        local boss = bosses[index]
        row.index = boss and index
        if boss then
            local n = #visibleItems(boss)
            row.label:SetText(Q.Safe(boss.name)); row.count:SetText(n > 0 and tostring(n) or '|cff5a6478-|r')
            row:SetSelected(index == state.boss); row:Show()
        else row:Hide() end
    end
    v.bossScroll:SetMinMaxValues(0, math.max(0, #bosses - BOSS_ROWS)); v.bossScroll:SetValue(state.bossOffset)
    local boss = bosses[state.boss]
    local items = visibleItems(boss)
    v.title:SetText(Q.Safe(boss.name)); v.raidName:SetText(Q.Safe(raid.name or Q.DungeonName(raid.key)))
    local slotName = Q.SLOT_NAMES[state.slot] or '?'
    v.slotToggle:SetLabel(state.slotOnly and ('Emplacement : ' .. slotName) or ('Filtrer : ' .. slotName)); v.slotToggle:SetActive(state.slotOnly)
    state.lootOffset = math.max(0, math.min(state.lootOffset, #items - LOOT_ROWS))
    for i = 1, LOOT_ROWS do
        local row, it = v.lootRows[i], items[state.lootOffset + i]
        row.item = it and it[1]
        if it then
            local inList = Q.InMyList(it[1])
            row.icon:SetTexture(Q.ItemIcon(it[1]))
            row.label:SetText(itemText(it[1], it[3]))
            local code = Q.LootCode(it) or '?'
            row.slotText:SetText((CODE_NAMES[code] or code) .. (it.boss and (' · ' .. Q.Safe(it.boss)) or '') .. (inList and ('  |cff5cd1a8dans ta liste (' .. (Q.SLOT_NAMES[inList] or '?') .. ')|r') or ''))
            row:Show()
        else row:Hide() end
    end
    v.lootScroll:SetMinMaxValues(0, math.max(0, #items - LOOT_ROWS)); v.lootScroll:SetValue(state.lootOffset)
    v.empty:SetShown(#items == 0)
    v.empty:SetText(state.slotOnly and ('Rien pour l\'emplacement « ' .. slotName .. ' » chez ce boss.\nClique sur « Emplacement : ' .. slotName .. ' » pour tout voir.')
        or 'Aucun objet connu chez ce boss.')
    v.status:SetText(state.picked or 'Clic : ajouter à ta liste. Clic droit : retirer. Maj+clic : lien dans le chat.')
end

local function createLoot(parent)
    local v = CreateFrame('Frame', nil, parent)
    v:SetPoint('TOPLEFT', 0, -40); v:SetPoint('BOTTOMRIGHT')

    -- Toutes les instances, en cartes
    v.cards = CreateFrame('Frame', nil, v); v.cards:SetAllPoints(v)
    local heading = S.Text(v.cards, 13, S.colors.text); heading:SetPoint('TOPLEFT', 0, -5); heading:SetText('Toutes les instances')
    local hint = S.Text(v.cards, 10, S.colors.muted, 'RIGHT'); hint:SetPoint('TOPRIGHT', -10, -7); hint:SetText('Clique sur une instance pour voir le butin de ses boss')
    v.cards:EnableMouseWheel(true)
    v.cards:SetScript('OnMouseWheel', function(_, delta) state.cardOffset = state.cardOffset - delta; Q.Run('défilement', renderLoot) end)
    v.cardButtons = {}
    for i = 1, CARD_COLUMNS * CARD_ROWS do
        local card = S.Box(v.cards, S.colors.panel, S.colors.line, 'Button'); card:SetSize(CARD_W, CARD_H)
        card:SetPoint('TOPLEFT', ((i - 1) % CARD_COLUMNS) * (CARD_W + 8), -32 - math.floor((i - 1) / CARD_COLUMNS) * (CARD_H + CARD_GAP))
        card.hover = S.Fill(card, 'HIGHLIGHT', { 1, 1, 1, 0.07 }); card.hover:SetAllPoints()
        card.label = S.Text(card, 12, S.colors.text); card.label:SetPoint('TOPLEFT', 8, -7); card.label:SetWidth(CARD_W - 16); card.label:SetWordWrap(true)
        card.info = S.Text(card, 10, S.colors.muted); card.info:SetPoint('BOTTOMLEFT', 8, 6); card.info:SetWidth(CARD_W - 16)
        card:SetScript('OnClick', function(self)
            if not self.key then return end
            state.raid = self.key; state.boss = 1; state.bossOffset = 0; state.lootOffset = 0; state.picked = nil
            Q.Run('instance', renderLoot)
        end)
        v.cardButtons[i] = card
    end
    v.cardScroll = S.Scrollbar(v.cards, CARD_ROWS * (CARD_H + CARD_GAP) - CARD_GAP, function(offset) if offset ~= state.cardOffset then state.cardOffset = offset; Q.Run('défilement', renderLoot) end end)
    v.cardScroll:SetPoint('TOPLEFT', 754, -32)

    -- Une instance : ses boss à gauche, leur butin à droite
    v.detail = CreateFrame('Frame', nil, v); v.detail:SetAllPoints(v)
    v.back = S.Button(v.detail, '< Toutes les instances', 170, 24, 'ghost'); v.back:SetPoint('TOPLEFT', 0, 0)
    v.back:SetScript('OnClick', function() state.raid = nil; state.picked = nil; Q.Run('instances', renderLoot) end)
    v.dungeonName = S.Text(v.detail, 13, S.colors.text); v.dungeonName:SetPoint('TOPLEFT', 182, -5); v.dungeonName:SetWidth(570)
    local box = S.Box(v.detail, S.colors.panel, S.colors.line); box:SetPoint('TOPLEFT', 0, -32); box:SetSize(250, 368)
    box:EnableMouseWheel(true)
    box:SetScript('OnMouseWheel', function(_, delta) state.bossOffset = state.bossOffset - delta * 2; Q.Run('défilement', renderLoot) end)
    v.bossRows = {}
    for i = 1, BOSS_ROWS do
        local row = S.Row(v.detail, 238, 25); row:SetPoint('TOPLEFT', 1, -36 - (i - 1) * 26)
        row.label = S.Text(row, 12, S.colors.text); row.label:SetPoint('LEFT', 12, 0); row.label:SetWidth(190)
        row.count = S.Text(row, 10, S.colors.muted, 'RIGHT'); row.count:SetPoint('RIGHT', -8, 0)
        row:SetScript('OnClick', function(self)
            if self.index then state.boss = self.index; state.lootOffset = 0; state.picked = nil; Q.Run('boss', renderLoot) end
        end)
        v.bossRows[i] = row
    end
    v.bossScroll = S.Scrollbar(v.detail, BOSS_ROWS * 26, function(offset) if offset ~= state.bossOffset then state.bossOffset = offset; Q.Run('défilement', renderLoot) end end)
    v.bossScroll:SetPoint('TOPLEFT', 242, -36)

    local d = S.Box(v.detail, S.colors.panel, S.colors.line); d:SetPoint('TOPLEFT', 262, -32); d:SetSize(498, 368)
    d:EnableMouseWheel(true)
    d:SetScript('OnMouseWheel', function(_, delta) state.lootOffset = state.lootOffset - delta * 2; Q.Run('défilement', renderLoot) end)
    v.title = S.Text(d, 15, S.colors.text); v.title:SetPoint('TOPLEFT', 16, -12); v.title:SetWidth(300)
    v.raidName = S.Text(d, 10, S.colors.muted); v.raidName:SetPoint('TOPLEFT', 16, -31)
    v.slotToggle = S.Button(d, '', 168, 24, 'ghost'); v.slotToggle:SetPoint('TOPRIGHT', -14, -12)
    v.slotToggle:SetScript('OnClick', function() state.slotOnly = not state.slotOnly; state.lootOffset = 0; Q.Run('filtre', renderLoot) end)
    v.lootRows = {}
    for i = 1, LOOT_ROWS do
        local row = S.Row(d, 478, 28); row:SetPoint('TOPLEFT', 1, -50 - (i - 1) * 29)
        row.icon = row:CreateTexture(nil, 'ARTWORK'); row.icon:SetSize(22, 22); row.icon:SetPoint('LEFT', 12, 0); row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.label = S.Text(row, 12, S.colors.text); row.label:SetPoint('LEFT', 42, 6); row.label:SetWidth(420)
        row.slotText = S.Text(row, 10, S.colors.muted); row.slotText:SetPoint('LEFT', 42, -7); row.slotText:SetWidth(420)
        row:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
        row:SetScript('OnClick', function(self, button)
            if not self.item then return end
            -- Clic droit : retire l'objet de la liste, pour corriger une erreur
            if button == 'RightButton' then
                Q.Run('retirer', function()
                    local slot = Q.InMyList(self.item)
                    if slot then
                        Q.ClearSlot(slot)
                        state.picked = '|cffe5545cRetiré :|r ' .. itemText(self.item) .. ' |cff94a1b8(' .. (Q.SLOT_NAMES[slot] or '?') .. ')|r'
                    else state.picked = itemText(self.item) .. ' |cff94a1b8n\'est pas dans ta liste.|r' end
                    UI.Refresh()
                end)
                return
            end
            if Quintessence.LinkItem(self.item) then return end
            Q.Run('butin', function()
                local ok, result = Q.PickRaidItem(self.item, state.raid, state.slot)
                if ok then
                    state.picked = '|cff5cd1a8Ajouté :|r ' .. itemText(self.item) .. ' |cff94a1b8(' .. (Q.SLOT_NAMES[result] or '?') .. ')|r'
                else state.picked = '|cffe5545c' .. Q.Safe(result) .. '|r' end
                UI.Refresh()
            end)
        end)
        row:SetScript('OnEnter', function(self) showItemTooltip(self, self.item) end)
        row:SetScript('OnLeave', hideTooltip)
        v.lootRows[i] = row
    end
    v.lootScroll = S.Scrollbar(d, LOOT_ROWS * 29, function(offset) if offset ~= state.lootOffset then state.lootOffset = offset; Q.Run('défilement', renderLoot) end end)
    v.lootScroll:SetPoint('TOPLEFT', 486, -50)
    v.empty = S.Text(d, 12, S.colors.muted, 'CENTER'); v.empty:SetPoint('TOPLEFT', 30, -150); v.empty:SetWidth(438); v.empty:SetWordWrap(true)
    v.status = S.Text(d, 10, S.colors.muted); v.status:SetPoint('BOTTOMLEFT', 16, 12); v.status:SetWidth(466); v.status:SetWordWrap(true)
    return v
end

-- Maj+clic sur un objet du jeu (sacs, fiche personnage, chat, fenêtre de butin, AtlasLoot…) pendant que l'onglet est
-- ouvert : l'objet va dans la liste, à l'emplacement choisi. hooksecurefunc : aucune écriture dans le code de Blizzard.
local lastLink, lastAt = nil, 0
local function onItemLink(link)
    if Quintessence.linkingItem then return end -- Maj+clic sur une de nos lignes : le lien va au chat, pas dans la liste
    if not frame or not frame:IsVisible() or type(link) ~= 'string' or not link:find('item:', 1, true) then return end
    if IsModifiedClick and not IsModifiedClick('CHATLINK') then return end
    local now = GetTime()
    if link == lastLink and now - lastAt < 0.3 then return end -- même clic vu par deux crochets
    lastLink, lastAt = link, now
    Q.Run('maj+clic', function()
        local ok, result = Q.PickRaidItem(link, nil, state.slot)
        if ok then
            state.slot = result
            state.picked = '|cff5cd1a8Ajouté :|r ' .. itemText(Q.ParseItem(link)) .. ' |cff94a1b8(' .. (Q.SLOT_NAMES[result] or '?') .. ')|r'
        else Q.Print(result) end
        UI.Refresh()
    end)
end
function UI.HookItemClicks()
    if UI.hooked or not hooksecurefunc then return end
    UI.hooked = true
    if HandleModifiedItemClick then hooksecurefunc('HandleModifiedItemClick', onItemLink) end
    if ChatEdit_InsertLink then hooksecurefunc('ChatEdit_InsertLink', onItemLink) end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, 'InsertLink', onItemLink) end
end
UI.OnItemLink = onItemLink -- (tests)

-- ---------------------------------------------------------------------------------------------- Besoins par donjon
local function invite(name) Quintessence.Invite(name) end
local function renderNeeds()
    local v = frame.needs
    state.needs = Q.Needs(state.onlineOnly)
    local needs = state.needs
    local current
    for _, g in ipairs(needs) do if g.key == state.dungeon then current = g end end
    if not current then current = needs[1]; state.dungeon = current and current.key; state.memberOffset = 0 end
    state.dungeonOffset = math.max(0, math.min(state.dungeonOffset, #needs - DUNGEON_ROWS))
    for i = 1, DUNGEON_ROWS do
        local row, g = v.rows[i], needs[state.dungeonOffset + i]
        row.key = g and g.key
        if g then
            row.title:SetText(Q.Safe(g.name))
            row.sub:SetText(#g.members .. ' membre' .. (#g.members > 1 and 's' or '') .. ' · ' .. g.count .. ' objet' .. (g.count > 1 and 's' or '')
                .. (g.online > 0 and ('  |cff5cd1a8' .. g.online .. ' en ligne|r') or ''))
            row:SetSelected(g.key == state.dungeon); row:Show()
        else row:Hide() end
    end
    v.empty:SetShown(#needs == 0)
    v.onlineToggle:SetActive(state.onlineOnly)
    local d = v.details
    d:SetShown(current ~= nil)
    if not current then return end
    d.title:SetText(Q.Safe(current.name))
    local members = current.members
    local itemCounts = {}
    for _, m in ipairs(members) do
        for _, it in ipairs(m.items) do
            itemCounts[it.item] = (itemCounts[it.item] or 0) + 1
        end
    end
    local hasConflict = false
    for _, count in pairs(itemCounts) do
        if count > 1 then hasConflict = true; break end
    end
    local levelStr = current.levels ~= '' and current.levels or ''
    if hasConflict then
        d.levels:SetText(levelStr .. (levelStr ~= '' and ' · ' or '') .. '|c' .. S.hex.red .. 'Conflits de butin détectés|r')
    elseif #members > 0 then
        d.levels:SetText(levelStr .. (levelStr ~= '' and ' · ' or '') .. '|c' .. S.hex.mint .. 'Aucun conflit de butin|r')
    else
        d.levels:SetText(levelStr)
    end

    state.memberOffset = math.max(0, math.min(state.memberOffset, #members - MEMBER_ROWS))
    for i = 1, MEMBER_ROWS do
        local row, m = d.rows[i], members[state.memberOffset + i]
        row.member = m
        if m then
            row.dot:SetVertexColor(unpack(m.online and S.colors.mint or S.colors.line))
            row.name:SetText('|c' .. Q.ClassHex(m.class) .. Q.Safe(m.name) .. '|r' .. (m.level and ('  |cff94a1b8niv. ' .. m.level .. '|r') or '')
                .. (m.key == Q.Key() and '  |cffd9b35c(toi)|r' or ''))
            local names = {}
            for _, it in ipairs(m.items) do
                local txt = itemText(it.item)
                if (itemCounts[it.item] or 0) > 1 then
                    txt = txt .. ' |c' .. S.hex.red .. '(conflit)|r'
                end
                names[#names + 1] = txt
            end
            row.items:SetText(table.concat(names, '|cff94a1b8, |r'))
            row:Show()
        else row:Hide() end
    end
    local onlineOthers = 0
    for _, m in ipairs(members) do if m.online and m.key ~= Q.Key() then onlineOthers = onlineOthers + 1 end end
    d.invite:SetLabel(onlineOthers > 0 and ('Inviter les ' .. math.min(4, onlineOthers) .. ' en ligne') or 'Personne d\'autre en ligne')
    if onlineOthers > 0 then d.invite:Enable() else d.invite:Disable() end
end

local function createNeeds(parent)
    local v = CreateFrame('Frame', nil, parent)
    v:SetPoint('TOPLEFT', 0, -40); v:SetPoint('BOTTOMRIGHT')
    local box = S.Box(v, S.colors.panel, S.colors.line); box:SetPoint('TOPLEFT', 0, 0); box:SetSize(300, 400)
    box:EnableMouseWheel(true)
    box:SetScript('OnMouseWheel', function(_, delta) state.dungeonOffset = state.dungeonOffset - delta * 2; Q.Run('défilement', renderNeeds) end)
    v.rows = {}
    for i = 1, DUNGEON_ROWS do
        local row = S.Row(v, 298, 36); row:SetPoint('TOPLEFT', 1, -4 - (i - 1) * 37)
        row.title = S.Text(row, 12, S.colors.text); row.title:SetPoint('TOPLEFT', 12, -5); row.title:SetWidth(276)
        row.sub = S.Text(row, 10, S.colors.muted); row.sub:SetPoint('TOPLEFT', 12, -21); row.sub:SetWidth(276)
        row:SetScript('OnClick', function(self)
            if self.key then state.dungeon = self.key; state.memberOffset = 0; Q.Run('donjon', renderNeeds) end
        end)
        v.rows[i] = row
    end
    v.empty = S.Text(v, 12, S.colors.muted, 'CENTER'); v.empty:SetPoint('TOPLEFT', 12, -160); v.empty:SetWidth(276); v.empty:SetWordWrap(true)
    v.empty:SetText('Aucun besoin pour l\'instant. Remplis ta liste BiS : celles des autres arrivent par la synchro.')

    local d = S.Box(v, S.colors.panel, S.colors.line); d:SetPoint('TOPLEFT', 312, 0); d:SetSize(448, 400)
    d:EnableMouseWheel(true)
    d:SetScript('OnMouseWheel', function(_, delta) state.memberOffset = state.memberOffset - delta * 2; Q.Run('défilement', renderNeeds) end)
    d.title = S.Text(d, 17, S.colors.text); d.title:SetPoint('TOPLEFT', 16, -14); d.title:SetWidth(300)
    d.levels = S.Text(d, 11, S.colors.muted); d.levels:SetPoint('TOPLEFT', 16, -36)
    local heading = S.Heading(d, 'Qui y cherche encore un objet · clic pour chuchoter'); heading:SetPoint('TOPLEFT', 16, -58)
    d.rows = {}
    for i = 1, MEMBER_ROWS do
        local row = S.Row(d, 446, 34); row:SetPoint('TOPLEFT', 1, -72 - (i - 1) * 35)
        row.dot = S.Fill(row, 'ARTWORK', { 1, 1, 1, 1 }); row.dot:SetSize(7, 7); row.dot:SetPoint('TOPLEFT', 14, -9)
        row.name = S.Text(row, 12, S.colors.text); row.name:SetPoint('TOPLEFT', 28, -4); row.name:SetWidth(400)
        row.items = S.Text(row, 10, S.colors.muted); row.items:SetPoint('TOPLEFT', 28, -19); row.items:SetWidth(404)
        row:SetScript('OnClick', function(self)
            local m = self.member
            if m and not Quintessence.SameName(m.key, Q.Key()) then Quintessence.Whisper(m.key) end
        end)
        row:SetScript('OnEnter', function(self)
            local m = self.member
            if m and m.items[1] then showItemTooltip(self, m.items[1].item) end
        end)
        row:SetScript('OnLeave', hideTooltip)
        d.rows[i] = row
    end
    d.invite = S.Button(d, 'Inviter', 200, 28, 'primary'); d.invite:SetPoint('BOTTOMRIGHT', -16, 14)
    d.invite:SetScript('OnClick', function()
        Q.Run('invitation', function()
            local g
            for _, x in ipairs(state.needs) do if x.key == state.dungeon then g = x end end
            if not g then return end
            local sent = 0
            for _, m in ipairs(g.members) do
                if sent < 4 and m.online and m.key ~= Q.Key() and invite(m.key) then sent = sent + 1 end
            end
            Q.Print(sent .. ' invitation(s) envoyée(s) pour ' .. Q.Safe(g.name) .. '.')
        end)
    end)
    v.onlineToggle = S.Button(d, 'En ligne seulement', 150, 28, 'ghost'); v.onlineToggle:SetPoint('BOTTOMLEFT', 16, 14)
    v.onlineToggle:SetScript('OnClick', function() state.onlineOnly = not state.onlineOnly; Q.Run('filtre', renderNeeds) end)
    v.details = d
    return v
end

-- ---------------------------------------------------------------------------------------------- Onglet
function UI.Refresh()
    if not frame or not frame:IsVisible() or not Q.ready then return end
    frame.tabList:SetActive(state.view == 'list'); frame.tabLoot:SetActive(state.view == 'loot'); frame.tabNeeds:SetActive(state.view == 'needs')
    frame.list:SetShown(state.view == 'list'); frame.loot:SetShown(state.view == 'loot'); frame.needs:SetShown(state.view == 'needs')
    local c, total, done = Q.Mine(), 0, 0
    for _, row in pairs(c.items) do total = total + 1; if row.obtained then done = done + 1 end end
    frame.progress:SetText(done .. ' / ' .. total .. ' objets obtenus')
    if state.view == 'list' then renderList() elseif state.view == 'loot' then renderLoot() else renderNeeds() end
end

function UI.OnDataChanged()
    if not frame or not frame:IsVisible() or refreshPending then return end
    refreshPending = true
    C_Timer.After(0.3, function() refreshPending = false; Q.Run('fenêtre', UI.Refresh) end)
end

local function create(parent)
    frame = CreateFrame('Frame', nil, parent)
    frame:SetAllPoints(parent)
    frame.tabList = S.Button(frame, 'Ma liste BiS', 150, 28, 'ghost'); frame.tabList:SetPoint('TOPLEFT', 0, 0)
    frame.tabList:SetScript('OnClick', function() state.view = 'list'; Q.Run('vue', UI.Refresh) end)
    frame.tabLoot = S.Button(frame, 'Butin des boss', 150, 28, 'ghost'); frame.tabLoot:SetPoint('TOPLEFT', 336, 0)
    frame.tabLoot:SetScript('OnClick', function()
        -- Déjà sur le butin : retour aux cartes ; depuis un autre onglet : on retrouve l'instance ouverte
        if state.view == 'loot' then state.raid = nil end
        state.view = 'loot'; state.picked = nil; Q.Run('vue', UI.Refresh)
    end)
    frame.tabNeeds = S.Button(frame, 'Besoins par donjon', 170, 28, 'ghost'); frame.tabNeeds:SetPoint('TOPLEFT', 158, 0)
    frame.tabNeeds:SetScript('OnClick', function() state.view = 'needs'; Q.Run('vue', UI.Refresh) end)
    frame.progress = S.Text(frame, 11, S.colors.gold, 'RIGHT'); frame.progress:SetPoint('TOPRIGHT', -2, -8)
    frame.list = createList(frame)
    frame.loot = createLoot(frame)
    frame.needs = createNeeds(frame)
    frame:SetScript('OnShow', function() Q.Run('fenêtre', UI.Refresh) end)
    frame:Hide()
end

function UI.Open(view)
    if not Q.ready and Q.Init then Q.Init() end
    if not Q.ready then return Q.Print('Addon pas encore initialisé : reconnecte-toi ou fais /reload.') end
    if view then state.view = view end
    Quintessence.UI.Open('bis')
    UI.Refresh()
end

function UI.Toggle() Quintessence.UI.Toggle('bis') end

--- Ouvre le butin des boss sur ce donjon ou ce raid (clé du site), par exemple depuis l'onglet Donjons.
function UI.ShowLoot(key)
    state.raid = lootOf(key) and key or nil; state.boss = 1; state.bossOffset = 0; state.lootOffset = 0; state.picked = nil
    UI.Open('loot')
end
-- Pont pour les autres modules (onglet Donjons de quinte-group : bouton « Butin des boss »)
function Quintessence.ShowBossLoot(key) Q.Run('butin des boss', UI.ShowLoot, key) end

-- Onglet « BiS & donjons » de la fenêtre Quintessence
Quintessence:RegisterModule({
    id = 'bis', title = 'BiS & donjons', order = 35, icon = 'Interface\\Icons\\INV_Misc_Book_11', version = Q.version, width = 760, height = 440,
    create = function(parent) create(parent); return frame end,
    refresh = function() UI.Refresh() end,
    summary = function()
        if not Q.ready then return nil end
        local c, total = Q.Mine(), 0
        for _ in pairs(c.items) do total = total + 1 end
        local needs = Q.Needs(false)
        local top = needs[1]
        return total .. ' objet(s) dans ta liste · ' .. #needs .. ' donjon(s) utiles'
            .. (top and (' · surtout ' .. Q.Safe(top.name) .. ' (' .. #top.members .. ')') or '')
    end,
})
