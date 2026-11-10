local _, Q = ...
--[[
  Onglet « Fiches » de la fenêtre Quintessence : personnages de la guilde (les tiens et ceux reçus par la synchro),
  recherche, et fiche détaillée (stuff avec infobulles du jeu, stats, résistances, PvP, métiers), en deux vues :
    Fiche  comme la fenêtre de personnage du jeu (emplacements autour, armes en bas, caractéristiques au centre)
    Liste  stuff et caractéristiques en texte
  La vue choisie est retenue (QuinteCaractDB.view).
  Règle Retail 12+ : uniquement nos propres cadres, aucune écriture dans les objets de Blizzard.
]]
local UI = {}
Q.UI = UI
-- Onglet de la grande fenêtre Quintessence (1.38.1+) : 1078 × 658 à l'échelle 1, textes de la même taille qu'avant
local W, H = 1078, 658
local ROW_H = 22
local ROWS = math.floor((H - 74) / ROW_H)  -- 26 personnages visibles
local LIST_W = 280
local DETAIL_X = LIST_W + 12
local DW, DH = W - DETAIL_X - 32, H - 28   -- 754 × 630 : contenu du détail
local TRAIN_LINES = math.floor((DH - 44 - 30) / 18)
local SLOT_NAMES = { [1] = 'Tête', [2] = 'Cou', [3] = 'Épaules', [4] = 'Chemise', [5] = 'Torse', [6] = 'Taille', [7] = 'Jambes',
    [8] = 'Pieds', [9] = 'Poignets', [10] = 'Mains', [11] = 'Doigt 1', [12] = 'Doigt 2', [13] = 'Bijou 1', [14] = 'Bijou 2',
    [15] = 'Dos', [16] = 'Main droite', [17] = 'Main gauche', [18] = 'À distance', [19] = 'Tabard' }
local QUALITY_HEX = { [0] = 'ff9d9d9d', 'ffffffff', 'ff1eff00', 'ff0070dd', 'ffa335ee', 'ffff8000', 'ffe6cc80', 'ff00ccff', 'ff00ccff' }

local function classHex(class)
    local color = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[class or '']
    local hex = color and color.colorStr
    return (type(hex) == 'string' and hex:match('^%x%x%x%x%x%x%x%x$')) and hex or 'ffffffff'
end
local function className(class) return (LOCALIZED_CLASS_NAMES_MALE or {})[class or ''] or class or '?' end
-- Style moderne commun (Quintessence.Style) : les noms de police WoW sont traduits en tailles et couleurs
local S = Quintessence.Style
local FONTS = { GameFontNormalLarge = { 18, 'text' }, GameFontNormal = { 13, 'text' }, GameFontNormalSmall = { 10, 'gold' },
    GameFontHighlight = { 13, 'text' }, GameFontHighlightSmall = { 12, 'text' }, GameFontDisable = { 12, 'muted' }, GameFontDisableSmall = { 11, 'muted' } }
local function text(parent, font, justify)
    local spec = FONTS[font or 'GameFontHighlightSmall'] or FONTS.GameFontHighlightSmall
    return S.Text(parent, spec[1], S.colors[spec[2]], justify)
end
local function fold(value)
    local s = tostring(value or '')
    for _, pair in ipairs({ { 'é', 'e' }, { 'è', 'e' }, { 'ê', 'e' }, { 'É', 'e' }, { 'à', 'a' }, { 'ç', 'c' }, { 'ô', 'o' } }) do s = s:gsub(pair[1], pair[2]) end
    return (s:gsub('[A-Z]', string.lower))
end
local function number(n)
    if type(n) ~= 'number' then return '?' end
    return n == math.floor(n) and tostring(n) or string.format('%.1f', n)
end

-- Fenêtre de personnage du jeu : colonne gauche, colonne droite, armes en bas ; texture d'emplacement vide du jeu
local SHEET_LEFT = { 1, 2, 3, 15, 5, 4, 19, 9 }
local SHEET_RIGHT = { 10, 6, 7, 8, 11, 12, 13, 14 }
local SHEET_BOTTOM = { 16, 17, 18 }
local EMPTY_SLOT = { [1] = 'Head', [2] = 'Neck', [3] = 'Shoulder', [4] = 'Shirt', [5] = 'Chest', [6] = 'Waist', [7] = 'Legs', [8] = 'Feet',
    [9] = 'Wrists', [10] = 'Hands', [11] = 'Finger', [12] = 'Finger', [13] = 'Trinket', [14] = 'Trinket', [15] = 'Chest',
    [16] = 'MainHand', [17] = 'SecondaryHand', [18] = 'Ranged', [19] = 'Tabard' }
local QUALITY_RGB = { [0] = { .62, .62, .62 }, { 1, 1, 1 }, { .12, 1, 0 }, { 0, .44, .87 }, { .64, .21, .93 }, { 1, .5, 0 }, { .9, .8, .5 } }
local SLOT_SIZE, SLOT_GAP = 35, 4
local function itemIcon(id)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local ok, _, _, _, _, icon = pcall(fn, id)
    return ok and icon or 'Interface\\Icons\\INV_Misc_QuestionMark'
end

local frame
local state = { query = '', offset = 0, selected = nil, results = {} }
local function view() return (QuinteCaractDB and QuinteCaractDB.view) == 'list' and 'list' or 'sheet' end
local refreshPending = false

function UI.Characters(query)
    local needle, out = fold(query or ''), {}
    for key, c in pairs(QuinteCaractDB.characters) do
        if type(c) == 'table' and ((c.level or 0) >= Q.MIN_LEVEL or c.source == 'self') and (needle == '' or fold(key):find(needle, 1, true)) then out[#out + 1] = { key = key, data = c } end
    end
    table.sort(out, function(a, b)
        local la, lb = a.data.level or 0, b.data.level or 0
        if la ~= lb then return la > lb end
        return a.key < b.key
    end)
    return out
end

local function renderDetails()
    local d = frame.details
    local entry = state.selected and QuinteCaractDB.characters[state.selected]
    if not entry then d:Hide(); frame.detailsEmpty:Show(); return end
    frame.detailsEmpty:Hide(); d:Show()
    local c = entry
    local canStats = Q.StatisticsOfficer and Q.StatisticsOfficer()
    d.statButton:SetShown(canStats and true or false)
    if not canStats then state.statistics = false end
    d.name:SetText('|c' .. classHex(c.class) .. Q.Safe(c.name) .. '|r' .. (c.source == 'sync' and ' |cff9aa4b8(reçu par la synchro)|r' or ''))
    d.meta:SetText('Niveau ' .. number(c.level) .. ' · ' .. Q.Safe(c.race or '?') .. ' ' .. Q.Safe(className(c.class))
        .. (c.spec and (' · ' .. Q.Safe(c.spec)) or '') .. (c.guildRank and (' · ' .. Q.Safe(c.guildRank)) or '')
        .. (c.itemLevel and (' · iLvl ' .. number(c.itemLevel)) or ''))
    local s, lines = c.stats or {}, {}
    for _, pair in ipairs({ { 'health', 'Vie' }, { 'power', 'Mana' }, { 'strength', 'Force' }, { 'agility', 'Agilité' }, { 'stamina', 'Endurance' },
        { 'intellect', 'Intelligence' }, { 'spirit', 'Esprit' }, { 'armor', 'Armure' }, { 'attackPower', 'PA' }, { 'spellPower', 'Puiss. sorts' } }) do
        if s[pair[1]] then lines[#lines + 1] = pair[2] .. ' : |cffffffff' .. number(s[pair[1]]) .. '|r' end
    end
    d.stats:SetText(#lines > 0 and table.concat(lines, '\n') or '|cff9aa4b8Pas de caractéristiques relevées.|r')
    local r, resist = s.resistances or {}, {}
    for _, pair in ipairs({ { 'fire', 'Feu' }, { 'frost', 'Givre' }, { 'nature', 'Nature' }, { 'shadow', 'Ombre' }, { 'arcane', 'Arcanes' } }) do
        if r[pair[1]] then resist[#resist + 1] = pair[2] .. ' ' .. number(r[pair[1]]) end
    end
    local pvp, profs = c.pvp or {}, {}
    for _, p in ipairs(c.professions or {}) do profs[#profs + 1] = Q.Safe(p.name) .. ' ' .. number(p.skill) end
    d.extra:SetText((#resist > 0 and ('Résistances : ' .. table.concat(resist, ' · ') .. '\n') or '')
        .. ((pvp.rankName or pvp.rank) and ('PvP : ' .. Q.Safe(pvp.rankName or '') .. (pvp.rank and (' (rang ' .. pvp.rank .. ')') or '')
            .. (pvp.honorableKills and (' · ' .. pvp.honorableKills .. ' VH') or '') .. '\n') or '')
        .. (#profs > 0 and ('Métiers : ' .. table.concat(profs, ' · ')) or ''))
    local gear = {}
    for _, row in ipairs(c.equipment or {}) do gear[row.slot] = row end
    -- Vue Entraînement : plan du maître de classe (connu vérifié pour son propre personnage seulement)
    d.train:SetActive(state.training and true or false)
    d.statButton:SetActive(state.statistics and true or false)
    if state.training or state.statistics then
        local mine = state.selected == Q.Key()
        local plan = Q.TrainingPlan(c.class, c.level, mine)
        local all = state.statistics and Q.StatisticsLines(c) or Q.TrainingLines(plan, 200, mine)
        state.trainOffset = math.max(0, math.min(state.trainOffset or 0, math.max(0, #all - #d.training.lines)))
        for i, fs in ipairs(d.training.lines) do fs:SetText(all[state.trainOffset + i] or '') end
        d.training.note:SetText(state.statistics and 'Molette : défiler. Valeurs dans la langue du client du joueur.' or (mine and '' or 'Fiche d\'un membre : sorts des prochains niveaux, d\'après sa classe et son niveau.'))
        d.list:Hide(); d.sheet:Hide(); d.training:Show()
        d.toggle:SetLabel(view() == 'sheet' and 'Vue liste' or 'Vue fiche')
        return
    end
    d.training:Hide()
    local sheet = view() == 'sheet'
    d.list:SetShown(not sheet); d.sheet:SetShown(sheet)
    d.toggle:SetLabel(sheet and 'Vue liste' or 'Vue fiche')
    if sheet then
        local f = d.sheet
        for slot, b in pairs(f.slots) do
            local row = gear[slot]
            b.item, b.enchant = row and row.item, row and row.enchant
            if row then
                local rgb = QUALITY_RGB[row.quality or 1] or QUALITY_RGB[1]
                b.icon:SetTexture(itemIcon(row.item)); b.icon:SetDesaturated(false); b.icon:SetAlpha(1)
                b:SetBackdropBorderColor(rgb[1], rgb[2], rgb[3], 1)
                b.ilvl:SetText(row.ilvl and number(row.ilvl) or '')
            else
                b.icon:SetTexture('Interface\\PaperDoll\\UI-PaperDoll-Slot-' .. EMPTY_SLOT[slot]); b.icon:SetAlpha(.55)
                b:SetBackdropBorderColor(unpack(S.colors.line)); b.ilvl:SetText('')
            end
        end
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.class or '']
        if coords then f.emblem:SetTexture('Interface\\TargetingFrame\\UI-Classes-Circles'); f.emblem:SetTexCoord(unpack(coords))
        else f.emblem:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark'); f.emblem:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        f.ilvl:SetText(c.itemLevel and ('Niveau d\'objet moyen |cffffffff' .. number(c.itemLevel) .. '|r') or '')
        local function block(pairs_)
            local out = {}
            for _, pair in ipairs(pairs_) do
                if s[pair[1]] then out[#out + 1] = pair[2] .. '  |cffffffff' .. number(s[pair[1]]) .. '|r' end
            end
            return #out > 0 and table.concat(out, '\n') or '|cff9aa4b8—|r'
        end
        f.attributes:SetText(block({ { 'health', 'Vie' }, { 'power', 'Mana' }, { 'strength', 'Force' }, { 'agility', 'Agilité' },
            { 'stamina', 'Endurance' }, { 'intellect', 'Intelligence' }, { 'spirit', 'Esprit' } }))
        f.combat:SetText(block({ { 'armor', 'Armure' }, { 'attackPower', 'Puissance d\'attaque' }, { 'spellPower', 'Puiss. des sorts' } }))
        local attuneList = {}
        if c.attunements then
            local defs = {
                { 'ony', 'Ony' }, { 'mc', 'MC' }, { 'bwl', 'BWL' }, { 'naxx', 'Naxx' },
                { 'ubrs', 'UBRS' }, { 'scholo', 'Scholo' }, { 'strath', 'Strath' }, { 'dm', 'HT' }
            }
            for _, d in ipairs(defs) do
                if c.attunements[d[1]] then
                    table.insert(attuneList, '|cff3fb950' .. d[2] .. '|r')
                else
                    table.insert(attuneList, '|cff666666' .. d[2] .. '|r')
                end
            end
        end

        f.extra:SetText((#attuneList > 0 and ('|cffd9b35cAccès & Clés|r  ' .. table.concat(attuneList, ' ') .. '\n') or '')
            .. (#resist > 0 and ('|cffd9b35cRésistances|r  ' .. table.concat(resist, ' · ') .. '\n') or '')
            .. ((pvp.rankName or pvp.rank) and ('|cffd9b35cPvP|r  ' .. Q.Safe(pvp.rankName or '') .. (pvp.rank and (' (rang ' .. pvp.rank .. ')') or '')
                .. (pvp.honorableKills and (' · ' .. pvp.honorableKills .. ' VH') or '') .. '\n') or '')
            .. (#profs > 0 and ('|cffd9b35cMétiers|r  ' .. table.concat(profs, ' · ')) or ''))
        f.noGear:SetShown(not next(gear))
        return
    end
    local i = 0
    for slot = 1, 19 do
        local row = gear[slot]
        if row then
            i = i + 1
            local line = d.gear[i]
            if line then
                line.item, line.enchant = row.item, row.enchant
                line.label:SetText('|cff9aa4b8' .. (SLOT_NAMES[slot] or slot) .. '|r  |c' .. (QUALITY_HEX[row.quality or 1] or 'ffffffff')
                    .. Q.Safe(row.name or ('Objet #' .. row.item)) .. '|r' .. (row.ilvl and (' |cff9aa4b8' .. number(row.ilvl) .. '|r') or ''))
                line:Show()
            end
        end
    end
    for j = i + 1, #d.gear do d.gear[j]:Hide() end
    d.noGear:SetShown(i == 0)
end

local function renderList()
    local results = state.results
    state.offset = math.max(0, math.min(state.offset, #results - ROWS))
    for i = 1, ROWS do
        local row, entry = frame.rows[i], results[state.offset + i]
        row.key = entry and entry.key
        if entry then
            local c = entry.data
            row.label:SetText('|c' .. classHex(c.class) .. Q.Safe(c.name or entry.key) .. '|r')
            row.info:SetText(number(c.level) .. (c.itemLevel and (' · ' .. number(c.itemLevel)) or ''))
            row:SetSelected(state.selected == entry.key)
            row:Show()
        else row:Hide() end
    end
    frame.count:SetText(#results .. ' personnage' .. (#results > 1 and 's' or ''))
end

function UI.Refresh()
    if not frame or not frame:IsVisible() then return end
    state.results = UI.Characters(state.query)
    if state.selected and not QuinteCaractDB.characters[state.selected] then state.selected = nil end
    if not state.selected then state.selected = QuinteCaractDB.characters[Q.Key()] and Q.Key() or (state.results[1] and state.results[1].key) end
    renderList(); renderDetails()
end

function UI.OnDataChanged()
    if not frame or not frame:IsVisible() or refreshPending then return end
    refreshPending = true
    C_Timer.After(0.3, function() refreshPending = false; Q.Run('fenêtre', UI.Refresh) end)
end

local function create(parent)
    frame = CreateFrame('Frame', nil, parent)
    frame:SetAllPoints(parent)
    local search = S.Input(frame, LIST_W, 'Rechercher un personnage…')
    search:SetPoint('TOPLEFT', 0, 0); search:SetMaxLetters(24)
    search:SetScript('OnTextChanged', function(box)
        state.query = box:GetText() or ''; box.placeholder:SetShown(state.query == ''); state.offset = 0
        Q.Run('recherche', UI.Refresh)
    end)
    local listBg = S.Box(frame, S.colors.panel, S.colors.line)
    listBg:SetPoint('TOPLEFT', 0, -34); listBg:SetSize(LIST_W, ROWS * ROW_H + 10)
    frame.rows = {}
    for i = 1, ROWS do
        local row = S.Row(frame, LIST_W - 2, ROW_H)
        row:SetPoint('TOPLEFT', 1, -39 - (i - 1) * ROW_H)
        row.label = text(row, 'GameFontHighlightSmall'); row.label:SetPoint('LEFT', 12, 0); row.label:SetPoint('RIGHT', -110, 0)
        row.info = text(row, 'GameFontDisableSmall', 'RIGHT'); row.info:SetPoint('RIGHT', -10, 0)
        row:SetScript('OnClick', function(self)
            if self.key then state.selected = self.key; Q.Run('sélection', function() renderList(); renderDetails() end) end
        end)
        frame.rows[i] = row
    end
    frame:EnableMouseWheel(true)
    frame:SetScript('OnMouseWheel', function(_, delta) state.offset = state.offset - delta * 3; Q.Run('défilement', renderList) end)
    frame.count = text(frame, 'GameFontDisableSmall'); frame.count:SetPoint('BOTTOMLEFT', 2, 4)

    local detailsBg = S.Box(frame, S.colors.panel, S.colors.line)
    detailsBg:SetPoint('TOPLEFT', DETAIL_X, 0); detailsBg:SetSize(W - DETAIL_X, H)
    local d = CreateFrame('Frame', nil, frame)
    d:SetPoint('TOPLEFT', DETAIL_X + 16, -14); d:SetSize(DW, DH)
    d.name = text(d, 'GameFontNormalLarge'); d.name:SetPoint('TOPLEFT', 0, 0)
    d.name:SetPoint('RIGHT', -320, 0); d.name:SetWordWrap(false)
    d.meta = text(d, 'GameFontDisableSmall'); d.meta:SetPoint('TOPLEFT', 0, -24); d.meta:SetPoint('RIGHT', 0, 0)
    d.toggle = S.Button(d, 'Vue liste', 96, 22, 'ghost'); d.toggle:SetPoint('TOPRIGHT', 0, 2)
    d.toggle:SetScript('OnClick', function()
        if state.training or state.statistics then state.training = false; state.statistics = false
        else QuinteCaractDB.view = view() == 'sheet' and 'list' or 'sheet' end
        Q.Run('vue', renderDetails)
    end)
    d.train = S.Button(d, 'Entraînement', 104, 22, 'ghost'); d.train:SetPoint('TOPRIGHT', -102, 2)
    d.train:SetScript('OnClick', function() state.training = not state.training; state.statistics = false; state.trainOffset = 0; Q.Run('entraînement', renderDetails) end)
    d.statButton = S.Button(d, 'Statistiques', 100, 22, 'ghost'); d.statButton:SetPoint('TOPRIGHT', -212, 2)
    d.statButton:SetScript('OnClick', function()
        if not Q.StatisticsOfficer() then return end
        state.statistics = not state.statistics; state.training = false; state.trainOffset = 0; Q.Run('statistiques', renderDetails)
    end)
    local tv = CreateFrame('Frame', nil, d); tv:SetPoint('TOPLEFT', 0, -44); tv:SetSize(DW, DH - 44)
    tv.lines = {}
    for i = 1, TRAIN_LINES do
        local fs = S.Text(tv, 11, S.colors.text); fs:SetPoint('TOPLEFT', 0, -(i - 1) * 18); fs:SetWidth(DW)
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        tv.lines[i] = fs
    end
    tv.note = S.Text(tv, 10, S.colors.muted); tv.note:SetPoint('BOTTOMLEFT', 0, 0); tv.note:SetWidth(DW)
    tv:EnableMouseWheel(true)
    tv:SetScript('OnMouseWheel', function(_, delta) state.trainOffset = math.max(0, (state.trainOffset or 0) - delta * 3); Q.Run('défilement', renderDetails) end)
    tv:Hide()
    d.training = tv
    local function tooltip(self)
        if not self.item or not GameTooltip then return end
        GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
        pcall(GameTooltip.SetHyperlink, GameTooltip, 'item:' .. self.item .. ':' .. (self.enchant or 0))
        GameTooltip:Show()
    end
    local function untooltip() if GameTooltip then GameTooltip:Hide() end end
    -- Vue fiche : emplacements comme la fenêtre de personnage du jeu
    local f = CreateFrame('Frame', nil, d); f:SetPoint('TOPLEFT', 0, -44); f:SetSize(DW, DH - 44)
    f.slots = {}
    local function slotButton(slot, x, y)
        local b = S.Box(f, S.colors.bg, S.colors.line, 'Button'); b:SetSize(SLOT_SIZE, SLOT_SIZE); b:SetPoint('TOPLEFT', x, y)
        b.icon = b:CreateTexture(nil, 'ARTWORK'); b.icon:SetPoint('TOPLEFT', 2, -2); b.icon:SetPoint('BOTTOMRIGHT', -2, 2); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.ilvl = S.Text(b, 9, S.colors.text, 'RIGHT', 'OUTLINE'); b.ilvl:SetPoint('BOTTOMRIGHT', -2, 2)
        local hl = S.Fill(b, 'HIGHLIGHT', { 1, 1, 1, 0.12 }); hl:SetPoint('TOPLEFT', 2, -2); hl:SetPoint('BOTTOMRIGHT', -2, 2)
        b.slot = slot
        b:SetScript('OnClick', function(self) if self.item then Quintessence.LinkItem(self.item) end end)
        b:SetScript('OnEnter', function(self)
            if self.item then return tooltip(self) end
            if GameTooltip then GameTooltip:SetOwner(self, 'ANCHOR_RIGHT'); GameTooltip:SetText(SLOT_NAMES[slot] or '?'); GameTooltip:Show() end
        end)
        b:SetScript('OnLeave', untooltip)
        f.slots[slot] = b
    end
    -- Proportions authentiques Blizzard CharacterFrame :
    -- Colonne gauche (35px), zone modèle/silhouette au centre (186px), colonne droite (35px) -> largeur mannequin = 266px.
    -- Armes centrées sous le modèle au bas du mannequin.
    -- Volet latéral droit de statistiques (216px) avec les caractéristiques, résistances et PvP.
    local DOLL_W, DOLL_H = 186, 8 * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP
    local DOLL_LEFT = SLOT_SIZE + 5
    local RIGHT_COL_X = DOLL_LEFT + DOLL_W + 5
    local STATS_X = RIGHT_COL_X + SLOT_SIZE + 14
    local STATS_W = DW - STATS_X

    for i, slot in ipairs(SHEET_LEFT) do slotButton(slot, 0, -(i - 1) * (SLOT_SIZE + SLOT_GAP)) end
    for i, slot in ipairs(SHEET_RIGHT) do slotButton(slot, RIGHT_COL_X, -(i - 1) * (SLOT_SIZE + SLOT_GAP)) end
    local bottomY = -DOLL_H - 6
    local weaponStartX = DOLL_LEFT + (DOLL_W - (3 * SLOT_SIZE + 2 * SLOT_GAP)) / 2
    for i, slot in ipairs(SHEET_BOTTOM) do slotButton(slot, weaponStartX + (i - 1) * (SLOT_SIZE + SLOT_GAP), bottomY) end

    -- Mannequin central aux proportions Blizzard (silhouette / blason de classe / ilvl)
    local center = S.Box(f, S.colors.bg, S.colors.line); center:SetPoint('TOPLEFT', DOLL_LEFT, 0); center:SetSize(DOLL_W, DOLL_H)
    center.pedestal = S.Fill(center, 'BACKGROUND', { 0, 0, 0, 0.35 })
    center.pedestal:SetPoint('BOTTOMLEFT', 1, 1); center.pedestal:SetPoint('BOTTOMRIGHT', -1, 1); center.pedestal:SetHeight(42)

    f.emblem = center:CreateTexture(nil, 'ARTWORK'); f.emblem:SetSize(64, 64); f.emblem:SetPoint('TOP', 0, -44)
    f.ilvl = S.Text(center, 12, S.colors.gold, 'CENTER'); f.ilvl:SetPoint('TOP', 0, -124); f.ilvl:SetWidth(DOLL_W - 16)
    f.noGear = S.Text(center, 11, S.colors.muted, 'CENTER'); f.noGear:SetPoint('TOP', 0, -154); f.noGear:SetWidth(DOLL_W - 20); f.noGear:SetWordWrap(true)
    f.noGear:SetText('Aucun équipement relevé.')

    -- Volet latéral droit des caractéristiques (façon panneau de stats Blizzard CharacterFrame)
    local statPanel = S.Box(f, S.colors.panel, S.colors.line)
    statPanel:SetPoint('TOPLEFT', STATS_X, 0); statPanel:SetSize(STATS_W, DH - 44)

    local h1 = S.Heading(statPanel, 'Attributs'); h1:SetPoint('TOPLEFT', 14, -10)
    f.attributes = S.Text(statPanel, 11, S.colors.muted); f.attributes:SetPoint('TOPLEFT', 14, -26); f.attributes:SetWidth(STATS_W - 28); f.attributes:SetJustifyV('TOP'); f.attributes:SetWordWrap(true)

    local h2 = S.Heading(statPanel, 'Combat'); h2:SetPoint('TOPLEFT', 14, -138)
    f.combat = S.Text(statPanel, 11, S.colors.muted); f.combat:SetPoint('TOPLEFT', 14, -154); f.combat:SetWidth(STATS_W - 28); f.combat:SetJustifyV('TOP'); f.combat:SetWordWrap(true)

    local h3 = S.Heading(statPanel, 'Détails & Accès'); h3:SetPoint('TOPLEFT', 14, -216)
    f.extra = S.Text(statPanel, 10, S.colors.muted); f.extra:SetPoint('TOPLEFT', 14, -232); f.extra:SetWidth(STATS_W - 28); f.extra:SetJustifyV('TOP'); f.extra:SetWordWrap(true)
    d.sheet = f
    -- Vue liste
    local lv = CreateFrame('Frame', nil, d); lv:SetAllPoints(); d.list = lv
    local gearTitle = S.Heading(lv, 'Équipement'); gearTitle:SetPoint('TOPLEFT', 0, -50)
    d.gear = {}
    for i = 1, 19 do
        local line = CreateFrame('Button', nil, lv)
        line:SetScript('OnClick', function(self) if self.item then Quintessence.LinkItem(self.item) end end)
        line:SetSize(430, 18); line:SetPoint('TOPLEFT', 0, -66 - (i - 1) * 18)
        line.label = text(line, 'GameFontHighlightSmall'); line.label:SetPoint('LEFT', 0, 0); line.label:SetPoint('RIGHT', 0, 0)
        local hl = S.Fill(line, 'HIGHLIGHT', { 1, 1, 1, 0.05 }); hl:SetAllPoints()
        line:SetScript('OnEnter', tooltip)
        line:SetScript('OnLeave', untooltip)
        d.gear[i] = line
    end
    d.noGear = text(lv, 'GameFontDisableSmall'); d.noGear:SetPoint('TOPLEFT', 0, -66); d.noGear:SetText('Aucun équipement relevé.')
    local statsTitle = S.Heading(lv, 'Caractéristiques'); statsTitle:SetPoint('TOPLEFT', 450, -50)
    d.stats = text(lv, 'GameFontHighlightSmall'); d.stats:SetPoint('TOPLEFT', 450, -66); d.stats:SetWidth(DW - 450); d.stats:SetWordWrap(true); d.stats:SetJustifyV('TOP')
    d.extra = text(lv, 'GameFontHighlightSmall'); d.extra:SetPoint('TOPLEFT', 450, -300); d.extra:SetWidth(DW - 450); d.extra:SetWordWrap(true); d.extra:SetJustifyV('TOP')
    frame.details = d
    frame.detailsEmpty = text(frame, 'GameFontDisable', 'CENTER')
    frame.detailsEmpty:SetPoint('TOPLEFT', DETAIL_X + 16, -290); frame.detailsEmpty:SetWidth(DW)
    frame.detailsEmpty:SetText('Aucune fiche pour l\'instant : elles arrivent à la connexion et par la synchro de guilde.')
    frame:SetScript('OnShow', function() Q.Run('fenêtre', UI.Refresh) end)
    frame:Hide()
end

-- Onglet « Fiches » de la fenêtre Quintessence
Quintessence:RegisterModule({
    id = 'caract', title = 'Fiches', order = 25, icon = 'Interface\\Icons\\INV_Chest_Chain', version = Q.version, width = W, height = H,
    create = function(parent) create(parent); return frame end,
    refresh = function() UI.Refresh() end,
    summary = function()
        if not Q.ready then return nil end
        local own, remote = 0, 0
        for _, c in pairs(QuinteCaractDB.characters) do if c.source == 'self' then own = own + 1 else remote = remote + 1 end end
        return own .. ' fiche(s) locale(s) · ' .. remote .. ' reçue(s) de la guilde'
    end,
})
