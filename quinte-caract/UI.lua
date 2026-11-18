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
local state = { query = '', offset = 0, selected = nil, results = {}, mainOpen = true, altOpen = false }
local function view() return (QuinteCaractDB and QuinteCaractDB.view) == 'list' and 'list' or 'sheet' end
local refreshPending = false

function UI.Characters(query)
    local needle, out, families = fold(query or ''), {}, Q.Families()
    for key, c in pairs(QuinteCaractDB.characters) do
        if type(c) == 'table' then
            local main = Q.MainOf(key, c, families)
            local principal = Quintessence.SameName(key, main)
            if ((c.level or 0) >= Q.MIN_LEVEL or c.source == 'self' and principal)
                and (needle == '' or fold(key):find(needle, 1, true)) then
                out[#out + 1] = {key = key, data = c, principal = principal, main = main}
            end
        end
    end
    table.sort(out, function(a, b)
        if a.principal ~= b.principal then return a.principal end
        local la, lb = a.data.level or 0, b.data.level or 0
        if la ~= lb then return la > lb end
        return a.key < b.key
    end)
    return out
end

function UI.MenuRows(results, query)
    local mains, alts, out = {}, {}, {}
    for _, entry in ipairs(results) do
        local list = entry.principal and mains or alts
        list[#list + 1] = entry
    end
    for _, section in ipairs({{'mainOpen', 'Principaux', mains}, {'altOpen', 'Rerolls', alts}}) do
        local open = state[section[1]] or (query or '') ~= ''
        out[#out + 1] = {section = section[1], label = section[2] .. ' (' .. #section[3] .. ')', open = open}
        if open then for _, entry in ipairs(section[3]) do out[#out + 1] = entry end end
    end
    return out
end

-- Profil de guilde déclaré dans l'accueil de Quintessence (conteneur 1.48.4+), affiché sous la fiche.
-- Seuls les profils enregistrés et partagés existent ici : jamais les brouillons ni les alertes.
local function label(list, id)
    for _, r in ipairs(list or {}) do if r[1] == id then return r[2] end end
end
-- Rang de guilde lu en direct dans la liste de guilde du jeu (nom du rang), relu au plus toutes les 30 s ;
-- à défaut, le rang noté dans la fiche au dernier relevé du joueur (c.guildRank).
local rankCache, rankAt = {}, -100
function UI.GuildRank(key, c)
    local now = GetTime and GetTime() or 0
    if now - rankAt > 30 then
        rankAt, rankCache = now, {}
        local ok, n = pcall(GetNumGuildMembers or function() end)
        n = ok and Q.Number(n, 0, 2000, true)
        if n and type(GetGuildRosterInfo) == 'function' then
            for i = 1, n do
                local good, name, rankName = pcall(GetGuildRosterInfo, i)
                name, rankName = good and Q.String(name, 100), good and Q.String(rankName, 64)
                if name and rankName then rankCache[Quintessence.CanonicalKey(name)] = rankName end
            end
        end
    end
    return rankCache[Quintessence.CanonicalKey(key or '')] or (c and Q.String(c.guildRank, 64)) or nil
end

--- Le lecteur voit-il les parties réservées du profil (raids, alertes de commandes) ? Officiers seulement (rangs 0 et 1).
function UI.ProfileOfficer()
    return Q.StatisticsOfficer and Q.StatisticsOfficer() and true or false
end

function UI.ProfileText(key, main)
    local P = Quintessence and Quintessence.Profile
    if not P or not P.Get then return nil end
    local ok, v = pcall(P.Get, key)
    local inherited = false
    if not (ok and v) and main and not Quintessence.SameName(key, main) then
        ok, v = pcall(P.Get, main); inherited = ok and v and true or false
    end
    if not (ok and v) then
        return '|c' .. Quintessence.Style.hex.muted .. 'Profil non renseigné. Il se remplit avec l\'accueil de Quintessence (Réglages > Profil).|r'
    end
    local likes, roles, days = {}, {}, {}
    for _, r in ipairs(P.ACTIVITIES or {}) do
        if v.activities and v.activities[r[1]] and r[1] ~= v.favorite then likes[#likes + 1] = r[2] end
    end
    for _, r in ipairs(P.ROLES or {}) do if v.roles and v.roles[r[1]] then roles[#roles + 1] = r[2] end end
    for i, n in ipairs(P.DAYS or {}) do if v.days and v.days[i] then days[#days + 1] = n end end
    local spec = function(id) local row = P.Spec and P.Spec(v.class, id); return row and row[2] end
    local gold, white = '|c' .. Quintessence.Style.hex.gold .. '', '|c' .. Quintessence.Style.hex.text .. ''
    local lines = {}
    local function add(name, value) lines[#lines + 1] = gold .. name .. '|r  ' .. white .. value .. '|r' end
    add('Favori', label(P.ACTIVITIES, v.favorite) or '?')
    if #likes > 0 then add('Aime aussi', table.concat(likes, ', ')) end
    add('Spé souhaitée', (spec(v.primary) or 'À choisir') .. (spec(v.secondary) and (' / ' .. spec(v.secondary)) or ''))
    if #roles > 0 then add('Rôles', table.concat(roles, ', ')) end
    -- Raids (soirs) et alertes de commandes : réservés aux officiers (demande du GM, 1.50.0)
    if UI.ProfileOfficer() then
        add('Raids', (label(P.RAIDS, v.raid) or '?') .. (v.raid ~= 'none' and #days > 0 and (' · ' .. table.concat(days, ', ')) or ''))
        add('Commandes', v.orders and (v.priority and 'oui, en priorité' or 'oui') or 'non souhaitées')
        lines[#lines + 1] = '|c' .. Quintessence.Style.hex.muted .. 'Raids et commandes : visibles des officiers seulement.|r'
    end
    if inherited then lines[#lines + 1] = '|c' .. Quintessence.Style.hex.muted .. 'Profil du personnage principal.|r' end
    return table.concat(lines, '\n')
end

local function renderDetails()
    local d = frame.details
    local entry = state.selected and QuinteCaractDB.characters[state.selected]
    if not entry then d:Hide(); frame.detailsEmpty:Show(); return end
    frame.detailsEmpty:Hide(); d:Show()
    local c = entry
    local main = Q.MainOf(state.selected, c)
    local canStats = Q.StatisticsOfficer and Q.StatisticsOfficer()
    d.statButton:SetShown(canStats and true or false)
    if not canStats then state.statistics = false end
    d.name:SetText('|c' .. classHex(c.class) .. Q.Safe(c.name) .. '|r' .. (c.source == 'sync' and ' |c' .. Quintessence.Style.hex.muted .. '(reçu par la synchro)|r' or ''))
    -- Rang de guilde en tête, dans la couleur de l'accent (liste de guilde du jeu, sinon dernier relevé)
    local rank = UI.GuildRank(state.selected, c)
    d.meta:SetText((rank and ('|c' .. Quintessence.Style.hex.gold .. Q.Safe(rank) .. '|r · ') or '')
        .. 'Niveau ' .. number(c.level) .. ' · ' .. Q.Safe(c.race or '?') .. ' ' .. Q.Safe(className(c.class))
        .. (c.spec and (' · ' .. Q.Safe(c.spec)) or '')
        .. (c.itemLevel and (' · iLvl ' .. number(c.itemLevel)) or '')
        .. (Quintessence.SameName(state.selected, main) and ' · Principal' or (' · Reroll de ' .. Q.Safe(Quintessence.DisplayName(main)))))
    local s, lines = c.stats or {}, {}
    for _, pair in ipairs({ { 'health', 'Vie' }, { 'power', 'Mana' }, { 'strength', 'Force' }, { 'agility', 'Agilité' }, { 'stamina', 'Endurance' },
        { 'intellect', 'Intelligence' }, { 'spirit', 'Esprit' }, { 'armor', 'Armure' }, { 'attackPower', 'PA' }, { 'spellPower', 'Puiss. sorts' } }) do
        if s[pair[1]] then lines[#lines + 1] = pair[2] .. ' : |c' .. Quintessence.Style.hex.text .. '' .. number(s[pair[1]]) .. '|r' end
    end
    d.stats:SetText(#lines > 0 and table.concat(lines, '\n') or '|c' .. Quintessence.Style.hex.muted .. 'Pas de caractéristiques relevées.|r')
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
        -- Modèle 3D : blason réduit en haut à gauche, niveau d'objet en bas ; sans modèle, ancien affichage centré
        local shown = f.model and Q.Model.Show(f.model, state.selected, c)
        if f.model then
            f.model:SetShown(shown and true or false)
            f.modelHint:SetShown(shown and true or false)
            f.modelNote:SetShown(shown and not f.model.exact or false)
            f.emblem:ClearAllPoints(); f.ilvl:ClearAllPoints()
            if shown then
                f.emblem:SetSize(26, 26); f.emblem:SetPoint('TOPLEFT', 6, -6)
                f.ilvl:SetPoint('BOTTOM', 0, 30)
            else
                f.emblem:SetSize(64, 64); f.emblem:SetPoint('TOP', 0, -44)
                f.ilvl:SetPoint('TOP', 0, -124)
            end
        end
        f.ilvl:SetText(c.itemLevel and ('Niveau d\'objet moyen |c' .. Quintessence.Style.hex.text .. '' .. number(c.itemLevel) .. '|r') or '')
        local function block(pairs_)
            local out = {}
            for _, pair in ipairs(pairs_) do
                if s[pair[1]] then out[#out + 1] = pair[2] .. '  |c' .. Quintessence.Style.hex.text .. '' .. number(s[pair[1]]) .. '|r' end
            end
            return #out > 0 and table.concat(out, '\n') or '|c' .. Quintessence.Style.hex.muted .. '—|r'
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
                    table.insert(attuneList, '|c' .. Quintessence.Style.hex.mint .. '' .. d[2] .. '|r')
                else
                    table.insert(attuneList, '|cff666666' .. d[2] .. '|r')
                end
            end
        end

        f.extra:SetText((#attuneList > 0 and ('|c' .. Quintessence.Style.hex.gold .. 'Accès & Clés|r  ' .. table.concat(attuneList, ' ') .. '\n') or '')
            .. (#resist > 0 and ('|c' .. Quintessence.Style.hex.gold .. 'Résistances|r  ' .. table.concat(resist, ' · ') .. '\n') or '')
            .. ((pvp.rankName or pvp.rank) and ('|c' .. Quintessence.Style.hex.gold .. 'PvP|r  ' .. Q.Safe(pvp.rankName or '') .. (pvp.rank and (' (rang ' .. pvp.rank .. ')') or '')
                .. (pvp.honorableKills and (' · ' .. pvp.honorableKills .. ' VH') or '') .. '\n') or '')
            .. (#profs > 0 and ('|c' .. Quintessence.Style.hex.gold .. 'Métiers|r  ' .. table.concat(profs, ' · ')) or ''))
        local profile = UI.ProfileText(state.selected, main)
        f.profile:SetShown(profile ~= nil)
        f.profile.text:SetText(profile or '')
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
                line.label:SetText('|c' .. Quintessence.Style.hex.muted .. '' .. (SLOT_NAMES[slot] or slot) .. '|r  |c' .. (((Quintessence.Style.QualityHex and Quintessence.Style.QualityHex(row.quality or 1)) or QUALITY_HEX[row.quality or 1]) or 'ffffffff')
                    .. Q.Safe(row.name or ('Objet #' .. row.item)) .. '|r' .. (row.ilvl and (' |c' .. Quintessence.Style.hex.muted .. '' .. number(row.ilvl) .. '|r') or ''))
                line:Show()
            end
        end
    end
    for j = i + 1, #d.gear do d.gear[j]:Hide() end
    d.noGear:SetShown(i == 0)
end

local function renderList()
    local results = UI.MenuRows(state.results, state.query)
    state.offset = math.max(0, math.min(state.offset, #results - ROWS))
    for i = 1, ROWS do
        local row, entry = frame.rows[i], results[state.offset + i]
        row.key = entry and entry.key
        row.section = entry and entry.section
        if entry and entry.section then
            row.label:SetText('|c' .. S.hex.gold .. entry.label .. '|r')
            row.info:SetText(entry.open and '-' or '+')
            row:SetSelected(false); row:Show()
        elseif entry then
            local c = entry.data
            row.label:SetText('|c' .. classHex(c.class) .. Q.Safe(c.name or entry.key) .. '|r')
            row.info:SetText(number(c.level) .. (c.itemLevel and (' · ' .. number(c.itemLevel)) or ''))
            row:SetSelected(state.selected == entry.key)
            row:Show()
        else row:Hide() end
    end
    frame.count:SetText(#state.results .. ' personnage' .. (#state.results > 1 and 's' or ''))
end

function UI.Refresh()
    if not frame or not frame:IsVisible() then return end
    state.results = UI.Characters(state.query)
    local found = false
    for _, entry in ipairs(state.results) do if entry.key == state.selected then found = true; break end end
    if not found then state.selected = state.results[1] and state.results[1].key end
    renderList(); renderDetails()
end

--- Ouvre les fiches sur ce personnage (recherche de l'en-tête du conteneur).
function UI.Select(key)
    state.query, state.offset, state.selected = '', 0, key
    if frame and frame.search then frame.search:SetText('') end
    Quintessence.UI.Open('caract')
    if frame and frame:IsVisible() then state.selected = key; renderList(); renderDetails() end
end

function UI.OnDataChanged()
    if not frame or not frame:IsVisible() or refreshPending then return end
    refreshPending = true
    C_Timer.After(0.3, function() refreshPending = false; Q.Run('fenêtre', UI.Refresh) end)
end

local function create(parent)
    frame = CreateFrame('Frame', nil, parent)
    frame:SetAllPoints(parent)
    local search = S.Input(frame, LIST_W, 'Rechercher un personnage…'); frame.search = search
    search:SetPoint('TOPLEFT', 0, 0); search:SetMaxLetters(40)
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
            if self.section then
                state[self.section] = not state[self.section]; Q.Run('menu des personnages', UI.Refresh); return
            end
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
        local hl = S.Fill(b, 'HIGHLIGHT', S.colors.hover or { 1, 1, 1, 0.12 }); hl:SetPoint('TOPLEFT', 2, -2); hl:SetPoint('BOTTOMRIGHT', -2, 2)
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

    -- Sous le mannequin et les armes : profil de guilde déclaré dans l'accueil (Quintessence.Profile)
    local profileTop = bottomY - SLOT_SIZE - 12
    f.profile = S.Box(f, S.colors.panel, S.colors.line)
    f.profile:SetPoint('TOPLEFT', 0, profileTop); f.profile:SetSize(RIGHT_COL_X + SLOT_SIZE, DH - 44 + profileTop)
    local hp = S.Heading(f.profile, 'Profil de guilde'); hp:SetPoint('TOPLEFT', 12, -10)
    f.profile.text = S.Text(f.profile, 11, S.colors.text); f.profile.text:SetPoint('TOPLEFT', 12, -30)
    f.profile.text:SetWidth(RIGHT_COL_X + SLOT_SIZE - 24); f.profile.text:SetJustifyV('TOP'); f.profile.text:SetWordWrap(true)
    f.profile.text:SetSpacing(4)

    -- Mannequin central aux proportions Blizzard (silhouette / blason de classe / ilvl)
    local center = S.Box(f, S.colors.bg, S.colors.line); center:SetPoint('TOPLEFT', DOLL_LEFT, 0); center:SetSize(DOLL_W, DOLL_H)
    center.pedestal = S.Fill(center, 'BACKGROUND', S.colors.shade or { 0, 0, 0, 0.35 })
    center.pedestal:SetPoint('BOTTOMLEFT', 1, 1); center.pedestal:SetPoint('BOTTOMRIGHT', -1, 1); center.pedestal:SetHeight(42)

    f.emblem = center:CreateTexture(nil, 'ARTWORK'); f.emblem:SetSize(64, 64); f.emblem:SetPoint('TOP', 0, -44)
    -- Aperçu 3D du personnage (Model.lua, 0.20.0) : modèle habillé au centre, comme l'Armurerie ; blason en repli
    f.model = Q.Model and Q.Model.Create(center, DOLL_W - 2, DOLL_H - 2)
    if f.model then
        f.model:SetPoint('TOPLEFT', 1, -1)
        f.modelHint = S.Text(center, 9, S.colors.muted, 'CENTER'); f.modelHint:SetPoint('BOTTOM', 0, 4); f.modelHint:SetWidth(DOLL_W - 8)
        f.modelHint:SetText('Glisser : tourner · Molette : zoom')
        f.modelNote = S.Text(center, 9, S.colors.muted, 'CENTER'); f.modelNote:SetPoint('BOTTOM', 0, 16); f.modelNote:SetWidth(DOLL_W - 8)
        f.modelNote:SetText('Visage et coiffure par défaut')
    end
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
        local hl = S.Fill(line, 'HIGHLIGHT', S.colors.hover or { 1, 1, 1, 0.05 }); hl:SetAllPoints()
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

-- ---------------------------------------------------------------------------
-- Accueil de Quintessence (conteneur 1.49.0) : tuile Raids de la semaine
-- Verrous du jeu (GetSavedInstanceInfo, relevés par Q.CollectLockouts) de chaque personnage du compte (source 'self'),
-- et accès manquants du personnage connecté (Attunements.lua). La date de fin vient du jeu, rien n'est deviné.
-- ---------------------------------------------------------------------------
Q.RAID_ORDER = { 'MC', 'ONY', 'BWL', 'ZG', 'AQ20', 'AQ40', 'NAXX', 'HYJAL', 'BARROW' }
Q.RAID_SHORT = { MC = 'Cœur du Magma', ONY = 'Onyxia', BWL = 'Aile noire', ZG = 'Zul’Gurub', AQ20 = 'Ruines d’Ahn’Qiraj',
    AQ40 = 'Temple d’Ahn’Qiraj', NAXX = 'Naxxramas', HYJAL = 'Hyjal', BARROW = 'Barrow Deeps' }
-- Abréviations des joueurs, pour les listes de la tuile (largeur d'un quart de fenêtre)
Q.RAID_ABBR = { MC = 'MC', ONY = 'Ony', BWL = 'BWL', ZG = 'ZG', AQ20 = 'AQ20', AQ40 = 'AQ40', NAXX = 'Naxx', HYJAL = 'Hyjal', BARROW = 'Barrow' }
local ATTUNE = { MC = 'mc', ONY = 'ony', BWL = 'bwl', NAXX = 'naxx', HYJAL = 'hyjal', BARROW = 'barrow' }
local DAYS = { 'dim.', 'lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.' }
local function untilText(at) return DAYS[tonumber(date('%w', at)) + 1] .. ' ' .. tonumber(date('%H', at)) .. ' h' end
--- Verrous encore valables : liste { key, at } triée par fin.
local function liveLocks(locks, now)
    local out = {}
    for key, at in pairs(type(locks) == 'table' and locks or {}) do
        at = tonumber(at)
        if Q.RAID_SHORT[key] and at and at > now then out[#out + 1] = { key = key, at = at } end
    end
    table.sort(out, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.key < b.key end)
    return out
end

function Q.Home(now)
    if not Q.ready then return nil end
    now = now or Q.Now()
    local me, alts = Q.Key(), {}
    local mine = QuinteCaractDB.characters[me]
    local level = tonumber(mine and mine.level) or tonumber(UnitLevel and UnitLevel('player')) or 0
    local myLocks = liveLocks(Q.CollectLockouts and Q.CollectLockouts(now) or (mine and mine.lockouts), now)
    for key, c in pairs(QuinteCaractDB.characters) do
        if key ~= me and type(c) == 'table' and c.source == 'self' then
            local locks = liveLocks(c.lockouts, now)
            if (tonumber(c.level) or 0) >= 60 or #locks > 0 then alts[#alts + 1] = { c = c, locks = locks } end
        end
    end
    table.sort(alts, function(a, b) if #a.locks ~= #b.locks then return #a.locks > #b.locks end return tostring(a.c.name) < tostring(b.c.name) end)
    local anyAlt = false
    for _, a in ipairs(alts) do if #a.locks > 0 then anyAlt = true end end
    if level < 55 and #myLocks == 0 and not anyAlt then return nil end

    local name = Q.Safe(Quintessence.DisplayName(Quintessence.PlayerName() or '?'))
    local lines, locked = {}, {}
    for i, l in ipairs(myLocks) do
        locked[l.key] = true
        if i <= 4 then lines[#lines + 1] = { name .. ' : ' .. Q.RAID_SHORT[l.key] .. ' → ' .. untilText(l.at), 'gold' } end
    end
    if #myLocks > 4 then lines[#lines + 1] = { '… et ' .. (#myLocks - 4) .. ' autre(s)', 'gold' } end
    if level >= 60 then
        local att = Q.CollectAttunements and Q.CollectAttunements() or (mine and mine.attunements) or {}
        local free, missing = {}, {}
        for _, key in ipairs(Q.RAID_ORDER) do
            local need = ATTUNE[key]
            if need and att[need] == false then missing[#missing + 1] = Q.RAID_ABBR[key]
            elseif not locked[key] then free[#free + 1] = Q.RAID_ABBR[key] end
        end
        if #free > 0 then lines[#lines + 1] = { 'Libres : ' .. table.concat(free, ', '), 'mint' } end
        if #missing > 0 then lines[#lines + 1] = { 'Accès manquant : ' .. table.concat(missing, ', '), 'red' } end
    elseif #myLocks == 0 then lines[#lines + 1] = { name .. ' : aucun raid verrouillé', 'mint' } end
    for i = 1, math.min(3, #alts) do
        local a = alts[i]
        local first = a.locks[1]
        lines[#lines + 1] = { Q.Safe(Quintessence.DisplayName(a.c.name or '?')) .. ' : '
            .. (first and (Q.RAID_SHORT[first.key] .. ' → ' .. untilText(first.at) .. (#a.locks > 1 and (' +' .. (#a.locks - 1)) or '')) or 'tout est libre'),
            first and 'muted' or 'mint' }
    end
    local n = #myLocks
    return { tile = { title = 'Raids de la semaine', icon = 'Interface\\Icons\\INV_Misc_Key_14', order = 20,
        value = n > 0 and n or 'Libre', label = n > 0 and (n > 1 and 'raids verrouillés' or 'raid verrouillé') or 'aucun verrou cette semaine',
        lines = lines, hint = 'Clic : ouvrir les fiches et les accès', action = function() Quintessence.UI.Open('caract') end } }
end

-- Onglet « Fiches » de la fenêtre Quintessence
Quintessence:RegisterModule({
    id = 'caract', title = 'Fiches', order = 25, icon = 'Interface\\Icons\\INV_Chest_Chain', version = Q.version, width = W, height = H,
    create = function(parent) create(parent); return frame end,
    refresh = function() UI.Refresh() end,
    home = function() return Q.Home() end,
    section = 'moi',
    -- Recherche commune de l'en-tête (conteneur 1.50.0) : personnages dont le nom contient le texte
    search = function(query)
        if not (Q.ready and QuinteCaractDB) then return nil end
        local out = {}
        for i, entry in ipairs(UI.Characters(query)) do
            if i > 5 then break end
            local c = entry.data
            out[#out + 1] = { text = '|c' .. classHex(c.class) .. Q.Safe(c.name or Quintessence.DisplayName(entry.key)) .. '|r',
                hint = 'Fiche · niveau ' .. tostring(c.level or '?') .. ' ' .. Q.Safe(className(c.class)),
                action = function() UI.Select(entry.key) end }
        end
        return out
    end,
    summary = function()
        if not Q.ready then return nil end
        local own, remote = 0, 0
        for _, c in pairs(QuinteCaractDB.characters) do if c.source == 'self' then own = own + 1 else remote = remote + 1 end end
        return own .. ' fiche(s) locale(s) · ' .. remote .. ' reçue(s) de la guilde'
    end,
})
