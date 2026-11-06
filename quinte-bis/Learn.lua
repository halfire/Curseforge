local _, Q = ...
--[[
  Learn.lua : butin vu en jeu. Les tables générées (DungeonLoot.lua, RaidLoot.lua) ne connaissent pas tout WoW Forever :
  quand un membre ouvre le corps d'un boss qui vient de mourir, un objet portable absent de la table de l'instance est
  noté dans sa fiche (`seen[id] = { k = clé d'instance, b = boss }`, 60 objets au plus) et partagé par la synchro des listes.
  L'onglet Butin des boss les montre sous « Vu en jeu par la guilde ». Rien d'autre n'est noté (ni le corps des autres
  monstres, ni qui a reçu l'objet). Événements de fin de boss et noms d'instance à confirmer sur Forever.
]]
local SEEN_MAX, BOSS_WINDOW = 60, 180
local lastBoss

local function plain(text) return tostring(text or ''):lower():gsub('[%s%p]', '') end
local function readable(v) return type(v) == 'string' and v ~= '' and not (issecretvalue and issecretvalue(v)) end

-- Clé par nom d'instance ; ailes du Monastère et de Hache-Tripes par le mot qui les distingue
local WINGS = {
    { 'monast', { cimet = 'SM_GY', bibli = 'SM_LIB', armur = 'SM_ARM', cath = 'SM_CATH' } },
    { 'hachetripes', { est = 'DME', ouest = 'DMW', nord = 'DMN' } },
}
function Q.InstanceKey(name)
    if not readable(name) then return nil end
    local wanted = plain(name)
    for _, d in ipairs(Q.DUNGEONS or {}) do
        if not d.other and plain(d.name) == wanted then return d.key end
    end
    for _, group in ipairs(WINGS) do
        if wanted:find(group[1], 1, true) then
            for word, key in pairs(group[2]) do
                if wanted:find(word, 1, true) then return key end
            end
        end
    end
    return nil
end

-- Objets des tables, par instance, et boss des tables -> instance
local tableItems, bossKeys
local function buildTables()
    tableItems, bossKeys = {}, {}
    for _, list in ipairs({ Q.DUNGEON_LOOT or {}, Q.RAID_LOOT or {} }) do
        for _, raid in ipairs(list) do
            local items = {}
            tableItems[raid.key] = items
            for _, boss in ipairs(raid.bosses) do
                bossKeys[plain(boss.name)] = raid.key
                for _, it in ipairs(boss.items) do items[it[1]] = true end
            end
        end
    end
end
local function inTable(key, id)
    if not tableItems then buildTables() end
    return tableItems[key] and tableItems[key][id] or false
end

--- Nom du boss tout juste tué, nil sinon : fin de rencontre, ou cible morte connue des tables.
local function currentBoss()
    if lastBoss and Q.Now() - lastBoss.at <= BOSS_WINDOW then return lastBoss.name end
    if UnitExists and UnitIsDead and UnitName and UnitExists('target') and UnitIsDead('target') then
        local name = UnitName('target')
        if not tableItems then buildTables() end
        if readable(name) and bossKeys[plain(name)] then return name end
    end
    return nil
end

function Q.OnBossKilled(name) if readable(name) then lastBoss = { name = name:sub(1, 40), at = Q.Now() } end end

--- Objet vu chez ce boss : true s'il est nouveau et noté.
function Q.LearnLoot(id, key, boss)
    id = Q.integer(id, 1, 9999999) and id or nil
    if not id or not key or not readable(boss) or inTable(key, id) or not Q.LootCode({ id }) then return false end
    for _, c in pairs(QuinteBisDB.characters) do
        if type(c.seen) == 'table' and type(c.seen[id]) == 'table' and c.seen[id].k == key then return false end
    end
    local me = Q.Mine()
    me.seen = type(me.seen) == 'table' and me.seen or {}
    local n = 0
    for _ in pairs(me.seen) do n = n + 1 end
    if n >= SEEN_MAX then return false end
    me.seen[id] = { k = key, b = boss:sub(1, 40) }
    Q.TouchMine()
    return true
end

--- Fenêtre de butin ouverte dans une instance, sur un boss tout juste tué.
function Q.OnLootOpened()
    if not GetInstanceInfo or not GetNumLootItems or not GetLootSlotLink then return end
    local name, kind = GetInstanceInfo()
    if kind ~= 'party' and kind ~= 'raid' then return end
    local boss = currentBoss()
    if not boss then return end
    if not tableItems then buildTables() end
    local key = Q.InstanceKey(name) or bossKeys[plain(boss)]
    if not key then return end
    for slot = 1, GetNumLootItems() do
        local ok, link = pcall(GetLootSlotLink, slot)
        local id = ok and readable(link) and tonumber(link:match('|Hitem:(%d+)'))
        if id and Q.LearnLoot(id, key, boss) then
            Q.Print('Butin ajouté pour la guilde : ' .. link .. ' (' .. Q.Safe(boss) .. ').')
        end
    end
end

--- Objets vus par la guilde pour cette instance : liste triée { id, nil, nil, boss = nom }.
function Q.SeenFor(key)
    local out, done = {}, {}
    for _, c in pairs(QuinteBisDB and QuinteBisDB.characters or {}) do
        if type(c.seen) == 'table' then
            for id, row in pairs(c.seen) do
                if type(row) == 'table' and row.k == key and not done[id] and not inTable(key, id) then
                    done[id] = true
                    out[#out + 1] = { id, boss = row.b }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    return out
end

--- Boss d'une instance pour l'affichage : ceux de la table, puis ce que la guilde a vu en plus.
function Q.LootBosses(raid)
    local seen = Q.SeenFor(raid.key)
    if #seen == 0 then return raid.bosses end
    local out = {}
    for i, boss in ipairs(raid.bosses) do out[i] = boss end
    out[#out + 1] = { name = 'Vu en jeu par la guilde', items = seen }
    return out
end

local frame = CreateFrame('Frame')
for _, event in ipairs({ 'LOOT_OPENED', 'ENCOUNTER_END', 'BOSS_KILL' }) do Q.Call(frame.RegisterEvent, frame, event) end
frame:SetScript('OnEvent', function(_, event, a, b, _, _, e)
    if not Q.ready then return end
    Q.Run('butin vu', function()
        if event == 'LOOT_OPENED' then Q.OnLootOpened()
        elseif event == 'ENCOUNTER_END' then if e == 1 then Q.OnBossKilled(b) end
        else Q.OnBossKilled(b) end
    end)
end)
