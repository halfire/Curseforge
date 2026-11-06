local _, Q = ...
--[[
  Training.lua : planificateur d'entraînement (vue « Entraînement » de l'onglet Fiches).
  - Pour mon personnage : ce que je peux apprendre maintenant chez mon maître de classe (sorts de mon niveau ou en
    dessous pas encore connus) et ce que ça coûte, puis ce qu'apporte chaque niveau jusqu'au 60 et le coût total.
  - Pour un membre de la guilde (sa fiche) : ce qu'il apprendra aux prochains niveaux, d'après sa classe et son niveau.
  Données : TrainingData.lua (sorts, niveaux et coûts du client de Forever) ; noms des sorts lus en jeu.
]]
local MAX_LEVEL = 60

local function spellName(id)
    local fn = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
    if not fn then return nil end
    local ok, name = pcall(fn, id)
    return ok and type(name) == 'string' and not Q.Secret(name) and name or nil
end
local function known(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, value = pcall(C_SpellBook.IsSpellKnown, id)
        if ok and value ~= nil and not Q.Secret(value) then return value == true end
    end
    if IsPlayerSpell then
        local ok, value = pcall(IsPlayerSpell, id)
        if ok and not Q.Secret(value) then return value == true end
    end
    if IsSpellKnown then
        local ok, value = pcall(IsSpellKnown, id)
        if ok and not Q.Secret(value) then return value == true end
    end
    return false
end

--- Coût en cuivre → texte « 1 po 20 pa 5 pc ».
function Q.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper <= 0 then return 'gratuit' end
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. ' po' end
    if silver > 0 then parts[#parts + 1] = silver .. ' pa' end
    if rest > 0 then parts[#parts + 1] = rest .. ' pc' end
    return table.concat(parts, ' ')
end

--- Plan d'entraînement : { now = { sorts à apprendre maintenant }, nowCost, levels = { { level, spells, cost } }, totalCost }.
--- `mine` : vérifie ce qui est déjà connu (seulement pour son propre personnage).
function Q.TrainingPlan(class, level, mine)
    local list = Q.TRAINING and Q.TRAINING[class or '']
    level = tonumber(level) or 1
    local plan = { now = {}, nowCost = 0, levels = {}, totalCost = 0 }
    if type(list) ~= 'table' then return plan end
    local byLevel = {}
    for _, row in ipairs(list) do
        local lvl, spell, cost, quest = row[1], row[2], row[3], row[4]
        local entry = { level = lvl, spell = spell, cost = cost, quest = quest or nil, name = spellName(spell) or ('Sort #' .. spell) }
        if lvl <= level then
            if mine and not quest and not known(spell) then
                plan.now[#plan.now + 1] = entry; plan.nowCost = plan.nowCost + cost
            end
        elseif lvl <= MAX_LEVEL then
            local bucket = byLevel[lvl]
            if not bucket then bucket = { level = lvl, spells = {}, cost = 0 }; byLevel[lvl] = bucket; plan.levels[#plan.levels + 1] = bucket end
            bucket.spells[#bucket.spells + 1] = entry
            bucket.cost = bucket.cost + cost
            plan.totalCost = plan.totalCost + cost
        end
    end
    table.sort(plan.levels, function(a, b) return a.level < b.level end)
    table.sort(plan.now, function(a, b) if a.level ~= b.level then return a.level < b.level end return a.name < b.name end)
    return plan
end

--- Lignes de texte du plan pour l'affichage (titre, puis une ligne par niveau), au plus `max` lignes.
function Q.TrainingLines(plan, max, mine)
    local lines = {}
    local function add(text) if #lines < max then lines[#lines + 1] = text end end
    if mine then
        if #plan.now > 0 then
            add(string.format('|cffffd100À apprendre maintenant (%d)|r · %s', #plan.now, Q.Money(plan.nowCost)))
            local names = {}
            for _, s in ipairs(plan.now) do names[#names + 1] = s.name end
            add('  ' .. table.concat(names, ', '))
        else add('|cff5cd1a8Rien à apprendre chez ton maître pour l\'instant.|r') end
    end
    add(string.format('|cffffd100Jusqu\'au niveau 60|r · %s au total', Q.Money(plan.totalCost)))
    for _, l in ipairs(plan.levels) do
        local names = {}
        for _, s in ipairs(l.spells) do names[#names + 1] = s.name .. (s.quest and ' (quête)' or '') end
        add(string.format('|cff9aa4b8%d|r  %s  |cff9aa4b8· %s|r', l.level, table.concat(names, ', '), Q.Money(l.cost)))
    end
    return lines
end
