local _, Q = ...
--[[
  Fenêtre « Craft de la guilde » : parcourir en jeu toutes les recettes connues (les tiennes et celles reçues
  par la synchro), filtrer par métier et dérouler les catégories en jeu du métier cliqué, rechercher,
  voir les composants et qui sait fabriquer.
  Règle Retail 12+ : on ne crée que nos propres cadres et on n'écrit JAMAIS dans une table ou un cadre de
  Blizzard (pas de UISpecialFrames, pas de champ ajouté sur GameTooltip…). On ne fait qu'appeler leurs méthodes.
]]
local UI = {}
Q.UI = UI
local ROWS, ROW_H = 18, 22
local LEFT_ROWS, LEFT_ROW_H = 14, 24
local MAX_REAGENTS, MAX_CRAFTERS = 12, 10
local QUESTION_MARK = 134400

-- ---------------------------------------------------------------------------
-- Données (sans affichage : testables hors du jeu)
-- ---------------------------------------------------------------------------

local index, indexRevision
-- Nom, catégorie et texte de recherche déjà calculés par recette : gardés d'un index à l'autre, car chaque fusion de
-- synchro change la révision et reconstruisait tout (1 750 recettes : 26 ms et 9 Mo de déchets à chaque fois).
local derived = {}
local function byCrafter(a, b) return a.key < b.key end
local function byName(a, b) if a.name ~= b.name then return a.name < b.name end return a.key < b.key end

--- Regroupe toutes les recettes de la guilde : une entrée par recette et par métier, avec ses artisans et sa catégorie en jeu.
function UI.BuildIndex()
    if index and indexRevision == Q.revision then return index end
    local byKey, professions, characters = {}, {}, 0
    for key, c in pairs(QuinteCraftDB.characters) do
        if type(c) == 'table' and type(c.professions) == 'table' then
            characters = characters + 1
            for prof, p in pairs(c.professions) do
                if type(prof) == 'string' and type(p) == 'table' and type(p.recipes) == 'table' then
                    local bucket = professions[prof]
                    if not bucket then bucket = { name = prof, recipes = 0, crafters = 0 }; professions[prof] = bucket end
                    bucket.crafters = bucket.crafters + 1
                    -- Une seule fiche d'artisan par personnage et métier, partagée par toutes ses recettes (en lecture seule) :
                    -- une table par recette et par artisan faisait 20 000 tables à chaque reconstruction.
                    local who = { key = key, class = c.class, skill = p.skill, maxSkill = p.maxSkill, self = c.source == 'self' }
                    for _, r in ipairs(p.recipes) do
                        if type(r) == 'table' then
                            local id = r.spell and (prof .. '|s' .. r.spell) or r.item and (prof .. '|i' .. r.item) or (prof .. '|' .. tostring(r.name))
                            local e = byKey[id]
                            if not e then
                                e = { key = id, profession = prof, spell = r.spell, item = r.item, crafters = {} }
                                byKey[id] = e; bucket.recipes = bucket.recipes + 1
                            end
                            e.name = e.name or r.name
                            e.rawCategory = e.rawCategory or r.category
                            e.reagents = e.reagents or (type(r.reagents) == 'table' and #r.reagents > 0 and r.reagents or nil)
                            e.item = e.item or r.item
                            e.crafters[#e.crafters + 1] = who
                        end
                    end
                end
            end
        end
    end
    local list, kept = {}, {}
    for id, e in pairs(byKey) do
        e.name = e.name or (e.spell and Q.SpellName(e.spell)) or ('Recette #' .. tostring(e.spell or e.item or '?'))
        local d = derived[id]
        if not d or d.name ~= e.name or d.item ~= e.item or d.raw ~= e.rawCategory then
            local cat, aliases = Q.CategorizeRecipe(e.profession, e.name, e.item, e.rawCategory)
            d = { name = e.name, item = e.item, raw = e.rawCategory, category = cat,
                fold = Q.Fold(e.name .. ' ' .. (cat or '') .. ' ' .. (aliases or '')) }
        end
        kept[id] = d
        e.category, e.fold = d.category, d.fold
        table.sort(e.crafters, byCrafter)
        list[#list + 1] = e
    end
    derived = kept -- les recettes disparues sont oubliées
    table.sort(list, byName)
    local profs = {}
    for _, bucket in pairs(professions) do profs[#profs + 1] = bucket end
    table.sort(profs, function(a, b) return a.name < b.name end)
    index = { recipes = list, professions = profs, characters = characters }
    indexRevision = Q.revision
    return index
end

--- Liste des catégories en jeu pour le métier choisi, avec le nombre de recettes dans chacune.
function UI.Categories(profession)
    local all = UI.BuildIndex().recipes
    if not profession then
        return { { value = nil, label = 'Toutes', count = #all } }
    end
    local counts, total = {}, 0
    for _, e in ipairs(all) do
        if e.profession == profession then
            total = total + 1
            if e.category then counts[e.category] = (counts[e.category] or 0) + 1 end
        end
    end
    local entries = { { value = nil, label = 'Toutes', count = total } }
    local ordered = Q.PROFESSION_CATEGORIES[Q.ProfessionKey(profession)] or {}
    local seen = {}
    for _, cat in ipairs(ordered) do
        local n = counts[cat] or 0
        if n > 0 then
            seen[cat] = true
            entries[#entries + 1] = { value = cat, label = cat, count = n }
        end
    end
    local extras = {}
    for cat, n in pairs(counts) do
        if not seen[cat] and n > 0 then
            extras[#extras + 1] = { value = cat, label = cat, count = n }
        end
    end
    table.sort(extras, function(a, b) return a.label < b.label end)
    for _, ex in ipairs(extras) do entries[#entries + 1] = ex end
    return entries
end

--- Recettes filtrées par métier (nil = tous), par texte (sans accents ni majuscules) et par catégorie du métier (nil = toutes).
function UI.Filter(profession, query, category)
    local all, needle, out = UI.BuildIndex().recipes, Q.Fold(query or ''), {}
    for _, e in ipairs(all) do
        local profOK = not profession or e.profession == profession
        local catOK = not category or e.category == category
        if profOK and catOK and (needle == '' or e.fold:find(needle, 1, true)) then
            out[#out + 1] = e
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Petits utilitaires d'affichage
-- ---------------------------------------------------------------------------

local function itemIcon(id)
    local ok, tex = Q.Call((C_Item or {}).GetItemIconByID or GetItemIcon, id)
    return ok and tex or nil
end
local function spellIcon(id)
    local ok, tex = Q.Call((C_Spell or {}).GetSpellTexture or GetSpellTexture, id)
    return ok and tex or nil
end
local function recipeIcon(e)
    return (e.item and itemIcon(e.item)) or (e.spell and spellIcon(e.spell)) or QUESTION_MARK
end
local function itemName(id)
    local ok, name = Q.Call((C_Item or {}).GetItemNameByID, id)
    if ok and type(name) == 'string' then return name end
    local legacy, oldName = Q.Call(GetItemInfo, id)
    if legacy and type(oldName) == 'string' then return oldName end
    Q.Call((C_Item or {}).RequestLoadItemDataByID, id) -- le nom arrivera via GET_ITEM_INFO_RECEIVED
end
local function classHex(class)
    local color = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[class or '']
    local hex = color and color.colorStr
    return (type(hex) == 'string' and hex:match('^%x%x%x%x%x%x%x%x$')) and hex or 'ffffffff'
end
local function shortName(key) return (tostring(key):match('^[^-]+')) or tostring(key) end
local function showTooltip(owner, spell, item)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, 'ANCHOR_RIGHT')
    local ok = spell and Q.Call(GameTooltip.SetSpellByID, GameTooltip, spell)
    if not ok and item then Q.Call(GameTooltip.SetItemByID, GameTooltip, item) end
    GameTooltip:Show()
end
local function hideTooltip() if GameTooltip then GameTooltip:Hide() end end
-- Chuchotement par le conteneur : nom avec espace et sans royaume sur WoW Forever
local function openWhisper(name) Quintessence.Whisper(name) end
local function flat(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer)
    t:SetColorTexture(r, g, b, a)
    return t
end
-- Style moderne commun (Quintessence.Style) : les noms de police WoW sont traduits en tailles et couleurs
local S = Quintessence.Style
local FONTS = { GameFontNormalLarge = { 17, 'text' }, GameFontNormal = { 14, 'text' }, GameFontNormalSmall = { 10, 'gold' },
    GameFontHighlight = { 13, 'text' }, GameFontHighlightSmall = { 12, 'text' }, GameFontDisable = { 12, 'muted' }, GameFontDisableSmall = { 11, 'muted' } }
local function text(parent, font, justify)
    local spec = FONTS[font or 'GameFontHighlightSmall'] or FONTS.GameFontHighlightSmall
    return S.Text(parent, spec[1], S.colors[spec[2]], justify)
end

-- ---------------------------------------------------------------------------
-- Fenêtre
-- ---------------------------------------------------------------------------

local frame
local state = {
    profession = nil,
    expandedProf = nil,
    category = nil,
    query = '',
    offset = 0,
    leftOffset = 0,
    selected = nil,
    results = {},
    leftItems = {},
    mode = 'recipes',   -- 'recipes' (recettes de la guilde), 'orders' (commandes), 'missing' (recettes que personne n'a)
    quantity = 1,
}
local QUANTITIES = { 1, 5, 10, 20 }
local refreshPending = false

local renderDetails
local function renderOrderDetails()
    local d, o = frame.orderDetails, state.selected
    frame.details:Hide()
    if not o then d:Hide(); frame.detailsEmpty:Show(); return end
    frame.detailsEmpty:Hide(); d:Show()
    local mineTo = Quintessence.CanonicalKey(o.to) == Quintessence.CanonicalKey(Quintessence.PlayerName() or '')
    d.icon:SetTexture((o.item and itemIcon(o.item)) or QUESTION_MARK)
    d.name:SetText(Q.Safe(o.count .. ' × ' .. (o.name or '?')))
    d.who:SetText(mineTo and ('Demandée par ' .. Q.Safe(Quintessence.DisplayName(o.from))) or ('Pour ' .. Q.Safe(Quintessence.DisplayName(o.to))))
    d.status:SetText('État : ' .. (Q.ORDER_STATUSES[o.status] or o.status) .. ((not mineTo and o.status == 'open' and not o.delivered) and ' · pas encore reçue (repartira à sa connexion)' or ''))
    d.note:SetText(o.note and ('« ' .. Q.Safe(o.note) .. ' »') or '')
    local open = o.status == 'open' or o.status == 'accepted'
    d.accept:SetShown(mineTo and o.status == 'open'); d.done:SetShown(mineTo and open); d.decline:SetShown(mineTo and open)
    d.cancel:SetShown(not mineTo and open)
end
local function renderMissingDetails()
    local d, r = frame.details, state.selected
    frame.orderDetails:Hide()
    if not r then d:Hide(); frame.detailsEmpty:Show(); return end
    frame.detailsEmpty:Hide(); d:Show()
    d.icon:SetTexture((r.item and itemIcon(r.item)) or QUESTION_MARK)
    d.name:SetText(Q.Safe(r.name))
    d.profession:SetText('Compétence ' .. r.skill .. ' · ' .. (Q.RECIPE_SOURCES[r.source] or '?'))
    for i = 1, MAX_REAGENTS do d.reagents[i]:Hide() end
    for i = 1, MAX_CRAFTERS do d.crafters[i]:Hide() end
    d.noReagents:SetShown(true); d.noReagents:SetText('Personne dans la guilde ne connaît cette recette.')
    d.craftersTitle:Hide(); d.moreCrafters:Hide(); d.qty:Hide(); d.order:Hide(); d.orderStatus:SetText('')
end
function renderDetails()
    if state.mode == 'orders' then return renderOrderDetails() end
    if state.mode == 'missing' then return renderMissingDetails() end
    frame.orderDetails:Hide()
    local d, e = frame.details, state.selected
    if not e then d:Hide(); frame.detailsEmpty:Show(); return end
    frame.detailsEmpty:Hide(); d:Show()
    d.craftersTitle:Show(); d.qty:Show(); d.order:Show()
    d.noReagents:SetText('Non relevés : survole l\'icône pour l\'infobulle du jeu.')
    d.icon:SetTexture(recipeIcon(e))
    d.name:SetText(e.name)
    d.profession:SetText(e.profession .. (e.category and (' · ' .. e.category) or '') .. ' · ' .. #e.crafters .. ' artisan' .. (#e.crafters > 1 and 's' or ''))
    -- Liste de courses : quantité choisie × composants, ce qu'on a (sacs et banque), et qui sait fabriquer le composant
    local reagents = e.reagents or {}
    local shopping = Q.ShoppingList(e, state.quantity)
    for i = 1, MAX_REAGENTS do
        local line, r, s = d.reagents[i], reagents[i], shopping[i]
        if r then
            line.item = r.item
            line.recipe = s and s.recipe
            line.icon:SetTexture(itemIcon(r.item) or QUESTION_MARK)
            local have = s and (s.missing == 0 and ('|cff5cd1a8' .. s.have .. '/' .. s.need .. '|r') or ('|cffe5545c' .. s.have .. '/' .. s.need .. '|r')) or ''
            line.label:SetText(have .. ' ' .. (r.name or itemName(r.item) or ('Objet #' .. r.item))
                .. (s and s.recipe and ' |cff9aa4b8(fabriqué par la guilde)|r' or ''))
            line:Show()
        else line:Hide() end
    end
    d.qty:SetLabel('Quantité : ' .. state.quantity)
    d.noReagents:SetShown(#reagents == 0)
    local top = -96 - math.max(1, #reagents) * 18
    d.craftersTitle:ClearAllPoints(); d.craftersTitle:SetPoint('TOPLEFT', 0, top - 8)
    for i = 1, MAX_CRAFTERS do
        local line, c = d.crafters[i], e.crafters[i]
        if c then
            local online = Q.Online(c.key)
            line.name = shortName(c.key); line.key = c.key
            line.dot:SetColorTexture(online and 0.25 or 0.45, online and 0.85 or 0.45, online and 0.35 or 0.45, 1)
            line.label:SetText('|c' .. classHex(c.class) .. Q.Safe(line.name) .. '|r'
                .. (c.self and ' |cff9aa4b8(toi)|r' or '') .. (online and '' or ' |cff9aa4b8· hors ligne|r'))
            line.skill:SetText(c.skill and (c.skill .. (c.maxSkill and ('/' .. c.maxSkill) or '')) or '')
            line:ClearAllPoints(); line:SetPoint('TOPLEFT', 0, top - 26 - (i - 1) * 18)
            line:Show()
        else line:Hide() end
    end
    d.moreCrafters:SetShown(#e.crafters > MAX_CRAFTERS)
    d.moreCrafters:SetText('+ ' .. (#e.crafters - MAX_CRAFTERS) .. ' autres')
    d.moreCrafters:ClearAllPoints(); d.moreCrafters:SetPoint('TOPLEFT', 0, top - 26 - MAX_CRAFTERS * 18)
end

local function renderRows()
    frame.ordersButton:SetActive(state.mode == 'orders'); frame.missingButton:SetActive(state.mode == 'missing')
    local waiting = Q.OpenOrdersForMe()
    frame.ordersButton:SetLabel(waiting > 0 and ('Commandes (' .. waiting .. ')') or 'Commandes')
    if state.mode ~= 'recipes' then
        local results = state.results
        local maxOffset = math.max(0, #results - ROWS)
        if state.offset > maxOffset then state.offset = maxOffset end
        local mine = Quintessence.CanonicalKey(Quintessence.PlayerName() or '')
        for i = 1, ROWS do
            local row, e = frame.rows[i], results[state.offset + i]
            row.entry = e
            if e and state.mode == 'orders' then
                local incoming = Quintessence.CanonicalKey(e.to) == mine
                row.icon:SetTexture((e.item and itemIcon(e.item)) or QUESTION_MARK)
                row.label:SetText((incoming and '|cffffd100← |r' or '|cff9aa4b8→ |r') .. Q.Safe(e.count .. ' × ' .. (e.name or '?')))
                row.cat:SetText(Q.ORDER_STATUSES[e.status] or ''); row.count:SetText('')
                row:SetSelected(state.selected == e); row:Show()
            elseif e then
                row.icon:SetTexture((e.item and itemIcon(e.item)) or QUESTION_MARK)
                row.label:SetText(Q.Safe(e.name)); row.cat:SetText(Q.RECIPE_SOURCES[e.source] or ''); row.count:SetText(e.skill)
                row:SetSelected(state.selected == e); row:Show()
            else row:Hide() end
        end
        frame.slider:SetMinMaxValues(0, maxOffset); frame.slider:SetValue(state.offset); frame.slider:SetShown(maxOffset > 0)
        if state.mode == 'orders' then
            frame.listTitle:SetText('Commandes (' .. #results .. ')')
            frame.empty:SetText('Aucune commande.\nChoisis une recette puis « Commander », ou clic droit sur un artisan.')
        else
            frame.listTitle:SetText((state.profession or 'Choisis un métier') .. ' · manquantes (' .. #results .. ')')
            frame.empty:SetText(state.profession and 'La guilde connaît toutes les recettes de ce métier relevées dans le catalogue.'
                or 'Choisis un métier à gauche pour voir les recettes que personne n\'a.')
        end
        frame.empty:SetShown(#results == 0)
        return
    end
    frame.empty:SetText('Aucune recette.\nOuvre tes fenêtres de métier pour enregistrer les tiennes, puis synchronise avec la guilde.')
    local results = state.results
    local maxOffset = math.max(0, #results - ROWS)
    if state.offset > maxOffset then state.offset = maxOffset end
    for i = 1, ROWS do
        local row, e = frame.rows[i], results[state.offset + i]
        row.entry = e
        if e then
            row.icon:SetTexture(recipeIcon(e))
            row.label:SetText(e.name)
            row.cat:SetText(e.category or '')
            row.count:SetText(#e.crafters)
            row:SetSelected(state.selected == e)
            row:Show()
        else row:Hide() end
    end
    frame.slider:SetMinMaxValues(0, maxOffset)
    frame.slider:SetValue(state.offset)
    frame.slider:SetShown(maxOffset > 0)
    local titlePrefix = state.profession or 'Recettes'
    if state.category then titlePrefix = titlePrefix .. ' · ' .. state.category end
    frame.listTitle:SetText(titlePrefix .. ' (' .. #results .. ')')
    frame.empty:SetShown(#results == 0)
end

local function buildLeftItems(idx)
    local items = {
        {
            kind = 'all',
            profession = nil,
            label = 'Tous les métiers',
            count = #idx.recipes,
            selected = (state.profession == nil),
        }
    }
    for _, p in ipairs(idx.professions) do
        local isExpanded = (state.expandedProf == p.name)
        local isProfSelected = (state.profession == p.name)
        items[#items + 1] = {
            kind = 'prof',
            profession = p.name,
            label = (isExpanded and '[-] ' or '[+] ') .. p.name,
            count = p.recipes,
            expanded = isExpanded,
            selected = isProfSelected and (state.category == nil),
            activeProf = isProfSelected,
        }
        if isExpanded then
            local cats = UI.Categories(p.name)
            for _, c in ipairs(cats) do
                items[#items + 1] = {
                    kind = 'cat',
                    profession = p.name,
                    category = c.value,
                    label = '   · ' .. c.label,
                    count = c.count,
                    selected = isProfSelected and (state.category == c.value),
                }
            end
        end
    end
    return items
end

local function renderProfessions()
    local idx = UI.BuildIndex()
    local items = buildLeftItems(idx)
    state.leftItems = items

    local maxLeftOffset = math.max(0, #items - LEFT_ROWS)
    if state.leftOffset > maxLeftOffset then state.leftOffset = maxLeftOffset end

    for i = 1, LEFT_ROWS do
        local b, item = frame.professions[i], items[state.leftOffset + i]
        b.item = item
        if item then
            b.value = item.profession
            b.label:SetText(item.label)
            b.count:SetText(item.count)
            b:SetSelected(item.selected)
            if item.kind == 'cat' then
                b.label:SetTextColor(unpack(item.selected and S.colors.gold or S.colors.muted))
            elseif item.activeProf or item.selected then
                b.label:SetTextColor(unpack(S.colors.text))
            else
                b.label:SetTextColor(unpack(S.colors.muted))
            end
            b:Show()
        else
            b:Hide()
        end
    end

    if frame.leftSlider then
        frame.leftSlider:SetMinMaxValues(0, maxLeftOffset)
        frame.leftSlider:SetValue(state.leftOffset)
        frame.leftSlider:SetShown(maxLeftOffset > 0)
    end

    local status = Q.sync and Q.sync:Status() or nil
    frame.stats:SetText(idx.characters .. ' personnage' .. (idx.characters > 1 and 's' or '') .. ' · ' .. #idx.recipes .. ' recettes'
        .. '\nSynchro : ' .. (status and (status.enabled and 'active' or 'coupée') or 'indisponible'))
end

function UI.Refresh()
    if not frame or not frame:IsVisible() then return end
    if state.category and state.profession then
        local valid = false
        for _, c in ipairs(UI.Categories(state.profession)) do
            if c.value == state.category then valid = true; break end
        end
        if not valid then state.category = nil end
    elseif not state.profession then
        state.category = nil
    end
    if state.mode == 'orders' then state.results = Q.Orders()
    elseif state.mode == 'missing' then state.results = state.profession and Q.MissingRecipes(state.profession) or {}
    else state.results = UI.Filter(state.profession, state.query, state.category) end
    if state.selected then
        local still = false
        local id = state.selected.key or state.selected.id or state.selected.spell
        for _, e in ipairs(state.results) do if (e.key or e.id or e.spell) == id then state.selected = e; still = true; break end end
        if not still then state.selected = nil end
    end
    renderProfessions(); renderRows(); renderDetails()
end

--- Données modifiées (scan, synchro) : rafraîchissement regroupé si la fenêtre est ouverte.
function UI.OnDataChanged()
    if not frame or not frame:IsVisible() or refreshPending then return end
    refreshPending = true
    C_Timer.After(0.3, function() refreshPending = false; Q.Run('fenêtre', UI.Refresh) end)
end

local function create(parent)
    frame = CreateFrame('Frame', nil, parent)
    frame:SetAllPoints(parent)

    -- Colonne gauche : recherche + liste déroulante des métiers et de leurs catégories en jeu
    local search = S.Input(frame, 180, 'Recette, emplacement, élixir…')
    search:SetPoint('TOPLEFT', 0, 0)
    search:SetMaxLetters(40)
    search:SetScript('OnTextChanged', function(box)
        state.query = box:GetText() or ''
        box.placeholder:SetShown(state.query == '')
        state.offset = 0
        Q.Run('recherche', UI.Refresh)
    end)
    frame.search = search
    local profHeading = S.Heading(frame, 'Métiers · clic pour dérouler'); profHeading:SetPoint('TOPLEFT', 2, -38)

    local leftBox = CreateFrame('Frame', nil, frame)
    leftBox:SetPoint('TOPLEFT', 0, -54)
    leftBox:SetSize(186, LEFT_ROWS * LEFT_ROW_H)
    leftBox:EnableMouseWheel(true)
    leftBox:SetScript('OnMouseWheel', function(_, delta)
        state.leftOffset = math.max(0, state.leftOffset - delta * 2)
        Q.Run('défilement métiers', renderProfessions)
    end)

    frame.professions = {}
    for i = 1, LEFT_ROWS do
        local b = S.Row(leftBox, 174, LEFT_ROW_H - 1)
        b:SetPoint('TOPLEFT', 0, -(i - 1) * LEFT_ROW_H)
        b.label = S.Text(b, 12, S.colors.muted); b.label:SetPoint('LEFT', 10, 0); b.label:SetPoint('RIGHT', -36, 0)
        b.count = S.Text(b, 11, S.colors.muted, 'RIGHT'); b.count:SetPoint('RIGHT', -6, 0)
        b:SetScript('OnClick', function(self)
            local item = self.item
            if not item then return end
            if item.kind == 'all' then
                state.profession = nil
                state.expandedProf = nil
                state.category = nil
                state.leftOffset = 0
            elseif item.kind == 'prof' then
                if state.expandedProf == item.profession then
                    if state.category ~= nil then
                        state.category = nil
                    else
                        state.expandedProf = nil
                    end
                else
                    state.profession = item.profession
                    state.expandedProf = item.profession
                    state.category = nil
                end
            elseif item.kind == 'cat' then
                state.profession = item.profession
                state.expandedProf = item.profession
                state.category = item.category
            end
            state.offset = 0
            Q.Run('filtre', UI.Refresh)
        end)
        frame.professions[i] = b
    end

    local leftSlider = S.Scrollbar(leftBox, LEFT_ROWS * LEFT_ROW_H, function(offset)
        if offset ~= state.leftOffset then state.leftOffset = offset; Q.Run('défilement métiers', renderProfessions) end
    end)
    leftSlider:SetPoint('TOPLEFT', 178, 0)
    frame.leftSlider = leftSlider

    frame.stats = text(frame, 'GameFontDisableSmall')
    frame.stats:SetPoint('BOTTOMLEFT', 2, 4)
    frame.stats:SetWordWrap(true)

    -- Colonne centrale : liste des recettes (pleine hauteur, sans barre de catégories en haut)
    frame.listTitle = text(frame, 'GameFontNormal')
    frame.listTitle:SetPoint('TOPLEFT', 200, -4); frame.listTitle:SetWidth(170)
    local function setMode(mode)
        state.mode = (state.mode == mode) and 'recipes' or mode
        state.selected, state.offset = nil, 0
        Q.Run('mode', UI.Refresh)
    end
    frame.ordersButton = S.Button(frame, 'Commandes', 86, 20, 'ghost'); frame.ordersButton:SetPoint('TOPLEFT', 350, -2)
    frame.ordersButton:SetScript('OnClick', function() setMode('orders') end)
    frame.missingButton = S.Button(frame, 'Manquantes', 86, 20, 'ghost'); frame.missingButton:SetPoint('TOPLEFT', 440, -2)
    frame.missingButton:SetScript('OnClick', function() setMode('missing') end)
    local listBg = S.Box(frame, S.colors.panel, S.colors.line)
    listBg:SetPoint('TOPLEFT', 196, -24); listBg:SetSize(330, ROWS * ROW_H + 12)
    frame.rows = {}
    for i = 1, ROWS do
        local row = S.Row(frame, 310, ROW_H)
        row:SetPoint('TOPLEFT', 198, -30 - (i - 1) * ROW_H)
        row.icon = row:CreateTexture(nil, 'ARTWORK'); row.icon:SetSize(18, 18); row.icon:SetPoint('LEFT', 8, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.label = text(row, 'GameFontHighlightSmall'); row.label:SetPoint('LEFT', 32, 0); row.label:SetPoint('RIGHT', -92, 0)
        row.cat = S.Text(row, 10, S.colors.muted, 'RIGHT'); row.cat:SetPoint('RIGHT', -24, 0); row.cat:SetWidth(64)
        row.count = text(row, 'GameFontDisableSmall', 'RIGHT'); row.count:SetPoint('RIGHT', -4, 0)
        row:SetScript('OnClick', function(self)
            if not self.entry then return end
            if self.entry.item and Quintessence.LinkItem(self.entry.item) then return end
            state.selected = self.entry
            Q.Run('sélection', function() renderRows(); renderDetails() end)
        end)
        row:SetScript('OnEnter', function(self) if self.entry then showTooltip(self, self.entry.spell, self.entry.item) end end)
        row:SetScript('OnLeave', hideTooltip)
        frame.rows[i] = row
    end
    local slider = S.Scrollbar(frame, ROWS * ROW_H, function(offset)
        if offset ~= state.offset then state.offset = offset; Q.Run('défilement', renderRows) end
    end)
    slider:SetPoint('TOPLEFT', 514, -30)
    frame.slider = slider
    frame:EnableMouseWheel(true)
    frame:SetScript('OnMouseWheel', function(_, delta)
        state.offset = math.max(0, state.offset - delta * 3)
        Q.Run('défilement', renderRows)
    end)
    frame.empty = text(frame, 'GameFontDisable', 'CENTER')
    frame.empty:SetPoint('CENTER', listBg, 'CENTER')
    frame.empty:SetWordWrap(true); frame.empty:SetWidth(280)
    frame.empty:SetText('Aucune recette.\nOuvre tes fenêtres de métier pour enregistrer les tiennes, puis synchronise avec la guilde.')

    -- Colonne droite : détail de la recette choisie
    local d = CreateFrame('Frame', nil, frame)
    local detailsBg = S.Box(frame, S.colors.panel, S.colors.line)
    detailsBg:SetPoint('TOPLEFT', 536, -24); detailsBg:SetSize(244, ROWS * ROW_H + 12)
    d:SetPoint('TOPLEFT', 550, -38); d:SetSize(216, 390)
    d.icon = d:CreateTexture(nil, 'ARTWORK'); d.icon:SetSize(36, 36); d.icon:SetPoint('TOPLEFT', 0, 0); d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local iconButton = CreateFrame('Button', nil, d); iconButton:SetAllPoints(d.icon)
    iconButton:SetScript('OnEnter', function(self) if state.selected then showTooltip(self, state.selected.spell, state.selected.item) end end)
    iconButton:SetScript('OnLeave', hideTooltip)
    d.name = text(d, 'GameFontNormal'); d.name:SetPoint('TOPLEFT', 44, -2); d.name:SetPoint('RIGHT', 0, 0); d.name:SetWordWrap(true)
    d.profession = text(d, 'GameFontDisableSmall'); d.profession:SetPoint('TOPLEFT', 44, -24)
    local reagentsTitle = S.Heading(d, 'Composants'); reagentsTitle:SetPoint('TOPLEFT', 0, -56)
    d.noReagents = text(d, 'GameFontDisableSmall'); d.noReagents:SetPoint('TOPLEFT', 0, -76); d.noReagents:SetWidth(216)
    d.noReagents:SetText('Non relevés : survole l\'icône pour l\'infobulle du jeu.')
    d.reagents = {}
    for i = 1, MAX_REAGENTS do
        local line = CreateFrame('Button', nil, d)
        line:SetSize(216, 18); line:SetPoint('TOPLEFT', 0, -76 - (i - 1) * 18)
        line.icon = line:CreateTexture(nil, 'ARTWORK'); line.icon:SetSize(16, 16); line.icon:SetPoint('LEFT', 0, 0)
        line.label = text(line, 'GameFontHighlightSmall'); line.label:SetPoint('LEFT', 22, 0); line.label:SetPoint('RIGHT', 0, 0)
        line:SetScript('OnEnter', function(self) showTooltip(self, nil, self.item) end)
        line:SetScript('OnLeave', hideTooltip)
        -- Composant fabriqué par la guilde : clic pour voir sa recette
        line:SetScript('OnClick', function(self)
            if self.recipe and state.mode == 'recipes' then state.selected = self.recipe; Q.Run('composant', renderDetails) end
        end)
        d.reagents[i] = line
    end
    d.craftersTitle = S.Heading(d, 'Qui sait le fabriquer · clic pour chuchoter')
    d.crafters = {}
    for i = 1, MAX_CRAFTERS do
        local line = CreateFrame('Button', nil, d)
        line:SetSize(216, 18)
        line.dot = line:CreateTexture(nil, 'ARTWORK'); line.dot:SetSize(8, 8); line.dot:SetPoint('LEFT', 2, 0)
        line.label = text(line, 'GameFontHighlightSmall'); line.label:SetPoint('LEFT', 16, 0); line.label:SetPoint('RIGHT', -50, 0)
        line.skill = text(line, 'GameFontDisableSmall', 'RIGHT'); line.skill:SetPoint('RIGHT', 0, 0)
        local hl = flat(line, 'HIGHLIGHT', 1, 1, 1, 0.08); hl:SetAllPoints()
        if line.RegisterForClicks then line:RegisterForClicks('LeftButtonUp', 'RightButtonUp') end
        -- Clic : chuchoter ; clic droit : lui passer commande
        line:SetScript('OnClick', function(self, button)
            if not self.name then return end
            if button == 'RightButton' then UI.Order(self.key) else openWhisper(self.name) end
        end)
        d.crafters[i] = line
    end
    d.moreCrafters = text(d, 'GameFontDisableSmall')
    d.qty = S.Button(d, 'Quantité : 1', 92, 20, 'ghost'); d.qty:SetPoint('BOTTOMLEFT', 0, 0)
    d.qty:SetScript('OnClick', function()
        local nextQty = QUANTITIES[1]
        for i, q in ipairs(QUANTITIES) do if q == state.quantity then nextQty = QUANTITIES[i + 1] or QUANTITIES[1] end end
        state.quantity = nextQty; Q.Run('quantité', renderDetails)
    end)
    d.order = S.Button(d, 'Commander', 118, 20, 'primary'); d.order:SetPoint('BOTTOMRIGHT', 0, 0)
    d.order:SetScript('OnClick', function() UI.Order() end)
    d.orderStatus = text(d, 'GameFontDisableSmall'); d.orderStatus:SetPoint('BOTTOMLEFT', 0, 24); d.orderStatus:SetWidth(216); d.orderStatus:SetWordWrap(true)
    frame.details = d

    -- Détail d'une commande (mode Commandes)
    local od = CreateFrame('Frame', nil, frame)
    od:SetPoint('TOPLEFT', 550, -38); od:SetSize(216, 390)
    od.icon = od:CreateTexture(nil, 'ARTWORK'); od.icon:SetSize(36, 36); od.icon:SetPoint('TOPLEFT', 0, 0)
    od.name = text(od, 'GameFontNormal'); od.name:SetPoint('TOPLEFT', 44, -2); od.name:SetWidth(172); od.name:SetWordWrap(true)
    od.who = text(od, 'GameFontHighlightSmall'); od.who:SetPoint('TOPLEFT', 0, -50); od.who:SetWidth(216)
    od.status = text(od, 'GameFontDisableSmall'); od.status:SetPoint('TOPLEFT', 0, -70); od.status:SetWidth(216); od.status:SetWordWrap(true)
    od.note = text(od, 'GameFontHighlightSmall'); od.note:SetPoint('TOPLEFT', 0, -104); od.note:SetWidth(216); od.note:SetWordWrap(true)
    local function act(status)
        return function()
            if state.selected and Q.SetOrderStatus(state.selected.id, status) then Q.Run('commande', UI.Refresh) end
        end
    end
    od.accept = S.Button(od, 'Accepter', 104, 22, 'primary'); od.accept:SetPoint('TOPLEFT', 0, -150); od.accept:SetScript('OnClick', act('accepted'))
    od.done = S.Button(od, 'Faite', 104, 22, 'ghost'); od.done:SetPoint('TOPLEFT', 112, -150); od.done:SetScript('OnClick', act('done'))
    od.decline = S.Button(od, 'Refuser', 104, 22, 'danger'); od.decline:SetPoint('TOPLEFT', 0, -178); od.decline:SetScript('OnClick', act('declined'))
    od.cancel = S.Button(od, 'Annuler', 104, 22, 'danger'); od.cancel:SetPoint('TOPLEFT', 0, -150); od.cancel:SetScript('OnClick', act('cancelled'))
    od:Hide()
    frame.orderDetails = od
    frame.detailsEmpty = text(frame, 'GameFontDisable', 'CENTER')
    frame.detailsEmpty:SetPoint('TOPLEFT', 550, -180); frame.detailsEmpty:SetWidth(216); frame.detailsEmpty:SetWordWrap(true)
    frame.detailsEmpty:SetText('Choisis une recette pour voir ses composants et qui sait la fabriquer.')

    -- Noms d'objets arrivés du serveur : rafraîchit le détail (uniquement fenêtre ouverte)
    frame:SetScript('OnEvent', function()
        if not refreshPending then
            refreshPending = true
            C_Timer.After(0.3, function() refreshPending = false; Q.Run('noms d\'objets', renderDetails) end)
        end
    end)
    frame:SetScript('OnShow', function(self) Q.Call(self.RegisterEvent, self, 'GET_ITEM_INFO_RECEIVED'); Q.Run('fenêtre', UI.Refresh) end)
    frame:SetScript('OnHide', function(self) Q.Call(self.UnregisterEvent, self, 'GET_ITEM_INFO_RECEIVED') end)
    frame:Hide()
end

function UI.Open(query)
    if not Q.ready and Q.Init then Q.Init() end
    if not Q.ready then return Q.Print('Addon pas encore initialisé : reconnecte-toi ou fais /reload.') end
    if query and query ~= '' then
        state.query = query
        if frame then frame.search:SetText(query) end
    end
    Quintessence.UI.Open('craft')
end

function UI.Toggle() Quintessence.UI.Toggle('craft') end

--- Commande la recette choisie (quantité choisie) à cet artisan, ou au premier artisan en ligne qui n'est pas soi.
function UI.Order(crafterKey)
    local e = state.selected
    if not e or state.mode ~= 'recipes' or not frame then return end
    local target = crafterKey
    if not target then
        for _, c in ipairs(e.crafters) do if not c.self and Q.Online(c.key) then target = c.key; break end end
        if not target then for _, c in ipairs(e.crafters) do if not c.self then target = c.key; break end end end
    end
    if not target then frame.details.orderStatus:SetText('|cffe5545cPersonne d\'autre ne sait la fabriquer.|r'); return end
    local o, err = Q.PlaceOrder(e, target, state.quantity)
    frame.details.orderStatus:SetText(o and ('|cff5cd1a8Commande envoyée à ' .. Q.Safe(Quintessence.DisplayName(target)) .. '.|r'
        .. (Q.Online(target) and '' or ' |cff9aa4b8(hors ligne : elle partira à sa connexion)|r')) or ('|cffe5545c' .. Q.Safe(err) .. '|r'))
    UI.OnDataChanged()
end
--- Ouvre l'onglet Craft sur ce mode ('recipes', 'orders', 'missing').
function UI.ShowMode(mode)
    state.mode = mode or 'recipes'; state.selected = nil; state.offset = 0
    UI.Open()
    UI.Refresh()
end

-- Onglet « Craft » de la fenêtre Quintessence
Quintessence:RegisterModule({
    id = 'craft', title = 'Craft', order = 20, icon = 'Interface\\Icons\\Trade_BlackSmithing', version = Q.version, width = 780, height = 486,
    create = function(parent)
        create(parent)
        if state.query ~= '' then frame.search:SetText(state.query) end
        return frame
    end,
    refresh = function() UI.Refresh() end,
    summary = function()
        if not Q.ready then return nil end
        local idx = UI.BuildIndex()
        return idx.characters .. ' personnage(s) · ' .. #idx.recipes .. ' recette(s) connues de la guilde'
    end,
})
