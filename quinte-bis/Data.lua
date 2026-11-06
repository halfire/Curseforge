local _, Q = ...
--[[
  Données : une liste BiS par personnage.
    QuinteBisDB.characters['Nom-Royaume'] = { name, realm, class, level, updated, source = 'self'|'sync', syncedFrom,
        items = { [emplacement] = { item = 12345, source = 'SM_CATH', obtained = true|nil } } }
  « Besoins » = objets non obtenus, regroupés par donjon (source).
]]
Q.SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
Q.SLOT_NAMES = { [1] = 'Tête', [2] = 'Cou', [3] = 'Épaules', [15] = 'Dos', [5] = 'Torse', [9] = 'Poignets', [10] = 'Mains',
    [6] = 'Taille', [7] = 'Jambes', [8] = 'Pieds', [11] = 'Doigt 1', [12] = 'Doigt 2', [13] = 'Bijou 1', [14] = 'Bijou 2',
    [16] = 'Main droite', [17] = 'Main gauche', [18] = 'À distance' }
local VALID_SLOT = {}
for _, slot in ipairs(Q.SLOTS) do VALID_SLOT[slot] = true end
-- Emplacement(s) possibles selon le type d'objet (GetItemInfoInstant)
local EQUIP = { INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CLOAK = { 15 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 } }

local function integer(n, lo, hi) return type(n) == 'number' and n == n and n % 1 == 0 and n >= lo and n <= hi end
local function str(s, max) return type(s) == 'string' and #s > 0 and #s <= max and not s:find('[%z\1-\31]') end
Q.integer = integer

-- Validation stricte d'une fiche reçue (synchro) : rien d'inattendu n'entre dans la sauvegarde
function Q.ValidCharacter(c, now)
    -- (nom complet sur WoW Forever : « Prénom Nom », jusqu'à 25 lettres, accents sur 2 octets)
    if type(c) ~= 'table' or not str(c.name, 64) or not str(c.realm, 40) or not integer(c.updated, 0, now + 300) then return nil end
    if c.class ~= nil and not (str(c.class, 16) and c.class:match('^%u+$')) then return nil end
    if c.level ~= nil and not integer(c.level, 1, 100) then return nil end
    if type(c.items) ~= 'table' then return nil end
    local items, n = {}, 0
    for slot, row in pairs(c.items) do
        n = n + 1
        if n > 19 or not VALID_SLOT[slot] or type(row) ~= 'table' or not integer(row.item, 1, 9999999) then return nil end
        if row.source ~= nil and not (str(row.source, 16) and row.source:match('^[%u%d_]+$')) then return nil end
        if row.obtained ~= nil and row.obtained ~= true then return nil end
        items[slot] = { item = row.item, source = row.source, obtained = row.obtained }
    end
    -- Butin vu en jeu (Learn.lua) : ligne invalide ignorée, la liste reste bonne
    local seen
    if type(c.seen) == 'table' then
        n = 0
        for id, row in pairs(c.seen) do
            n = n + 1
            if n > 60 then break end
            if integer(id, 1, 9999999) and type(row) == 'table' and str(row.k, 16) and row.k:match('^[%u%d_]+$') and str(row.b, 40) then
                seen = seen or {}
                seen[id] = { k = row.k, b = row.b }
            end
        end
    end
    return { name = c.name, realm = c.realm, class = c.class, level = c.level, updated = c.updated, items = items, seen = seen }
end
function Q.CharKeyOf(c) return c.name .. '-' .. (c.realm:gsub('%s', '')) end

--- Fiche reçue : remplace la nôtre si elle est plus récente. Jamais la fiche du joueur lui-même (source canonique).
function Q.PutCharacter(c, sender)
    local key = Q.CharKeyOf(c)
    if Quintessence.SameName(key, Q.Key()) then return false end
    local mine = QuinteBisDB.characters[key]
    if mine and (mine.updated or 0) >= c.updated then return false end
    c.source, c.syncedFrom = 'sync', sender
    QuinteBisDB.characters[key] = c
    return true
end

-- Le roster de la synchro est indexé par nom canonique (minuscules, sans espaces)
local function canonical(key) return LibStub('LibQuinteSync-1.0').CanonicalKey(key) end
-- Membres partis de la guilde ou fiches sans nouvelles depuis 120 jours : oubliés
function Q.Prune(roster, now)
    local changed = false
    for key, c in pairs(QuinteBisDB.characters) do
        if c.source ~= 'self' and ((roster and not roster[canonical(key)]) or (c.updated or 0) < now - 120 * 86400) then
            QuinteBisDB.characters[key] = nil; changed = true
        end
    end
    if changed then Q.Changed(false) end -- index des infobulles et fenêtre à jour
    return changed
end

--- Fiche du joueur (créée au besoin), avec classe et niveau à jour.
function Q.Mine(level)
    local key, db = Q.Key(), QuinteBisDB.characters
    local c = db[key]
    if not c then
        c = { name = Quintessence.PlayerName(), realm = Q.Realm(), items = {}, source = 'self', updated = Q.Now() }
        db[key] = c
    end
    c.source = 'self'
    local _, class = UnitClass('player')
    local lvl = level or UnitLevel('player')
    if (class and c.class ~= class) or (lvl and c.level ~= lvl) then
        c.class, c.level = class or c.class, lvl or c.level
        c.updated = Q.Tick(c.updated)
        Q.Changed(true)
    end
    return c
end
local function touch(c) c.updated = Q.Tick(c.updated); Q.Changed(true) end
function Q.TouchMine() touch(Q.Mine()) end

--- Identifiant d'objet depuis un nombre, un lien d'objet ou une adresse Wowhead (…/item=12345/…).
function Q.ParseItem(value)
    if type(value) == 'number' then return integer(value, 1, 9999999) and value or nil end
    if type(value) ~= 'string' then return nil end
    local id = value:match('item:(%d+)') or value:match('item=(%d+)') or value:match('^%s*(%d+)%s*$')
    id = tonumber(id)
    return id and integer(id, 1, 9999999) and id or nil
end

local function itemInstant(id)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local ok, _, _, _, equipLoc, icon = Q.Call(fn, id)
    if ok then return equipLoc, icon end
end
function Q.ItemIcon(id) local _, icon = itemInstant(id); return icon or 'Interface\\Icons\\INV_Misc_QuestionMark' end
--- Nom et qualité de l'objet (nil tant que le jeu ne l'a pas en cache : GET_ITEM_INFO_RECEIVED rafraîchit l'onglet).
function Q.ItemName(id)
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok, name, _, quality = Q.Call(fn, id)
    if ok and type(name) == 'string' then return name, quality end
    return nil
end

--- Emplacement pour un objet : celui demandé s'il convient, sinon le premier libre parmi les possibles.
function Q.SlotFor(id, preferred)
    local equipLoc = itemInstant(id)
    local options = equipLoc and EQUIP[equipLoc]
    if not options then return VALID_SLOT[preferred] and preferred or nil end
    for _, slot in ipairs(options) do if slot == preferred then return slot end end
    local items = Q.Mine().items
    for _, slot in ipairs(options) do if not items[slot] then return slot end end
    return options[1]
end

--- Emplacements où se porte un objet des tables de raid (code = suffixe INVTYPE_ de RaidLoot.lua).
function Q.SlotsForCode(code) return EQUIP['INVTYPE_' .. tostring(code)] or {} end
function Q.Fits(code, slot)
    for _, s in ipairs(Q.SlotsForCode(code)) do if s == slot then return true end end
    return false
end
-- Raid ou donjon d'où vient un objet des tables de butin (source proposée d'office)
local RAID_SOURCE = {}
for _, list in ipairs({ Q.RAID_LOOT or {}, Q.DUNGEON_LOOT or {} }) do
    for _, raid in ipairs(list) do
        for _, boss in ipairs(raid.bosses) do for _, it in ipairs(boss.items) do RAID_SOURCE[it[1]] = RAID_SOURCE[it[1]] or raid.key end end
    end
end
--- Code d'emplacement d'un objet des tables (suffixe INVTYPE_) : donné par RaidLoot.lua, lu en jeu pour DungeonLoot.lua
--- (nil pour ce qui ne se porte pas : composants, objets de quête).
function Q.LootCode(it)
    if it[2] then return it[2] end
    local equipLoc = itemInstant(it[1])
    if type(equipLoc) ~= 'string' or not EQUIP[equipLoc] then return nil end
    return (equipLoc:gsub('^INVTYPE_', ''))
end
--- Boss qui laisse cet objet (donjon ou raid) : 'Nom du boss', clé de l'instance.
local BOSS_OF
function Q.BossOf(id)
    if not BOSS_OF then
        BOSS_OF = {}
        for _, list in ipairs({ Q.RAID_LOOT or {}, Q.DUNGEON_LOOT or {} }) do
            for _, raid in ipairs(list) do
                for _, boss in ipairs(raid.bosses) do
                    for _, it in ipairs(boss.items) do if not BOSS_OF[it[1]] then BOSS_OF[it[1]] = { boss.name, raid.key } end end
                end
            end
        end
    end
    local hit = BOSS_OF[tonumber(id) or 0]
    if hit then return hit[1], hit[2] end
    -- Pas dans les tables : ce que la guilde a vu en jeu (Learn.lua)
    for _, c in pairs(QuinteBisDB.characters) do
        local row = type(c.seen) == 'table' and c.seen[tonumber(id) or 0]
        if type(row) == 'table' then return row.b, row.k end
    end
end
function Q.RaidSourceOf(id) return RAID_SOURCE[id] end
-- Emplacement pour un objet choisi dans les raids ou au Maj+clic : celui demandé s'il est libre, sinon un emplacement
-- libre qui convient (deuxième anneau, deuxième bijou), sinon celui demandé
local function freeSlotFor(id, preferred)
    local equipLoc = itemInstant(id)
    local options = equipLoc and EQUIP[equipLoc]
    if not options then return preferred end
    local items = Q.Mine().items
    local fits = false
    for _, slot in ipairs(options) do if slot == preferred then fits = true end end
    if fits and (not items[preferred] or items[preferred].item == id) then return preferred end
    for _, slot in ipairs(options) do if not items[slot] then return slot end end
    return fits and preferred or options[1]
end
--- Objet choisi dans les tables de butin (ou Maj+clic) : dans la liste, avec le raid pour source. Retourne ok, emplacement ou message.
function Q.PickRaidItem(id, raidKey, preferred)
    id = Q.ParseItem(id)
    if not id then return false, 'Objet non reconnu.' end
    raidKey = raidKey or RAID_SOURCE[id]
    local ok, result = Q.SetItem(freeSlotFor(id, preferred), id)
    if ok and raidKey then
        local row = Q.Mine().items[result]
        if row and row.source ~= raidKey then row.source = raidKey; touch(Q.Mine()) end
    end
    return ok, result
end
--- Objets de la liste qui viennent d'une table de butin (pour les marquer dans le navigateur des raids).
function Q.InMyList(id)
    for slot, row in pairs(Q.Mine().items) do if row.item == id then return slot end end
end

--- Source déjà connue dans la guilde pour cet objet (le premier qui l'a renseignée aide tous les autres).
function Q.KnownSource(id)
    local counts, best, bestCount = {}, nil, 0
    for _, c in pairs(QuinteBisDB.characters) do
        for _, row in pairs(c.items or {}) do
            if row.item == id and row.source then
                counts[row.source] = (counts[row.source] or 0) + 1
                if counts[row.source] > bestCount then best, bestCount = row.source, counts[row.source] end
            end
        end
    end
    return best
end

function Q.SetItem(slot, value)
    local id = Q.ParseItem(value)
    if not id then return false, 'Objet non reconnu : donne son numéro, son lien ou son adresse Wowhead.' end
    slot = Q.SlotFor(id, slot)
    if not slot then return false, 'Cet objet ne se porte pas.' end
    local c = Q.Mine()
    local old = c.items[slot]
    c.items[slot] = { item = id, source = (old and old.item == id and old.source) or Q.KnownSource(id) or RAID_SOURCE[id], obtained = Q.Owns(id) or nil }
    touch(c)
    return true, slot
end
function Q.SetSource(slot, key)
    local row = Q.Mine().items[slot]
    if not row or (key ~= nil and not (type(key) == 'string' and key:match('^[%u%d_]+$'))) then return false end
    row.source = key; touch(Q.Mine()); return true
end
function Q.SetObtained(slot, value)
    local row = Q.Mine().items[slot]
    if not row then return false end
    row.obtained = value and true or nil; touch(Q.Mine()); return true
end
function Q.ClearSlot(slot)
    local c = Q.Mine()
    if not c.items[slot] then return false end
    c.items[slot] = nil; touch(c); return true
end

-- Objets portés (19 emplacements), lus une fois par relevé
local function equippedSet()
    local set = {}
    for slot = 1, 19 do
        local ok, equipped = Q.Call(GetInventoryItemID, 'player', slot)
        if ok and equipped then set[equipped] = true end
    end
    return set
end
--- Le joueur possède-t-il l'objet (porté, dans les sacs ou la banque) ?
function Q.Owns(id, equipped)
    if (equipped or equippedSet())[id] then return true end
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    local ok, n = Q.Call(count, id, true)
    return ok and type(n) == 'number' and n > 0 or false
end
-- Marque automatiquement les objets obtenus (jamais l'inverse : un objet vendu ou détruit reste « obtenu »).
-- Relancé après chaque BAG_UPDATE_DELAYED : l'équipement est lu une seule fois (17 × 19 appels auparavant).
function Q.ScanOwned()
    local c, changed, equipped = Q.Mine(), false, nil
    for _, row in pairs(c.items) do
        if not row.obtained then
            equipped = equipped or equippedSet()
            if Q.Owns(row.item, equipped) then row.obtained = true; changed = true end
        end
    end
    if changed then touch(c) end
end

--- Qui est en ligne ? Roster de la synchro (classe, niveau, en ligne), le joueur lui-même l'est toujours.
function Q.Online(key)
    if key == Q.Key() then return true end
    local member = Q.sync and Q.sync.roster and Q.sync.roster[canonical(key)]
    return member and member.online or false
end

--- Besoins regroupés par donjon : { key, name, levels, members = { {key, name, class, level, online, items = {…}} }, count, online }
function Q.Needs(onlineOnly)
    local groups = {}
    for key, c in pairs(QuinteBisDB.characters) do
        local online = Q.Online(key)
        if not onlineOnly or online then
            for _, slot in ipairs(Q.SLOTS) do
                local row = c.items and c.items[slot]
                local dInfo = row and row.source and Q.DUNGEON_BY_KEY[row.source]
                if row and not row.obtained and row.source and not (dInfo and dInfo.raid) then
                    local g = groups[row.source]
                    if not g then g = { key = row.source, members = {}, byKey = {}, count = 0, online = 0 }; groups[row.source] = g end
                    local m = g.byKey[key]
                    if not m then
                        m = { key = key, name = c.name, class = c.class, level = c.level, online = online, items = {} }
                        g.byKey[key] = m; g.members[#g.members + 1] = m
                        if online then g.online = g.online + 1 end
                    end
                    m.items[#m.items + 1] = { slot = slot, item = row.item }
                    g.count = g.count + 1
                end
            end
        end
    end
    local list = {}
    for _, g in pairs(groups) do
        g.byKey = nil
        local d = Q.DUNGEON_BY_KEY[g.key]
        g.name, g.levels, g.order, g.other = Q.DungeonName(g.key), Q.DungeonLevels(g.key), d and d.order or 999, d and d.other
        table.sort(g.members, function(a, b)
            if a.online ~= b.online then return a.online end
            if #a.items ~= #b.items then return #a.items > #b.items end
            return a.name < b.name
        end)
        list[#list + 1] = g
    end
    -- Les vrais donjons d'abord, puis par nombre de membres concernés (en ligne d'abord)
    table.sort(list, function(a, b)
        if (a.other or false) ~= (b.other or false) then return not a.other end
        if a.online ~= b.online then return a.online > b.online end
        if #a.members ~= #b.members then return #a.members > #b.members end
        return a.order < b.order
    end)
    return list
end

--- Qui a cet objet dans sa liste BiS sans l'avoir encore (infobulles).
-- Index objet → noms, refait une fois par révision des données : l'infobulle (chaque objet survolé) parcourait toutes
-- les listes de la guilde et triait à chaque survol.
local needIndex, needRevision
local EMPTY = {}
function Q.WhoNeeds(id)
    if needRevision ~= Q.revision then
        needIndex, needRevision = {}, Q.revision
        for _, c in pairs(QuinteBisDB.characters) do
            local seen = {}
            for _, row in pairs(c.items or EMPTY) do
                local item = row.item
                if item and not row.obtained and not seen[item] then
                    seen[item] = true
                    local names = needIndex[item]
                    if not names then names = {}; needIndex[item] = names end
                    names[#names + 1] = c.name
                end
            end
        end
        for _, names in pairs(needIndex) do table.sort(names) end
    end
    return needIndex[id] or EMPTY
end

function Q.ClassHex(class)
    local color = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[class or '']
    local hex = color and color.colorStr
    return (type(hex) == 'string' and hex:match('^%x%x%x%x%x%x%x%x$')) and hex or 'ffffffff'
end

function Q.Summary()
    local c, total, done = Q.Mine(), 0, 0
    for _, row in pairs(c.items) do total = total + 1; if row.obtained then done = done + 1 end end
    local needs = Q.Needs(false)
    Q.Print('Ta liste BiS : ' .. done .. ' / ' .. total .. ' objet(s) obtenus · ' .. #needs .. ' source(s) utiles pour la guilde.')
    for i = 1, math.min(3, #needs) do
        Q.Print('  ' .. Q.Safe(needs[i].name) .. ' : ' .. #needs[i].members .. ' membre(s), ' .. needs[i].count .. ' objet(s)')
    end
end

function Q.Debug()
    local characters = 0
    for _ in pairs(QuinteBisDB.characters) do characters = characters + 1 end
    Q.Print('Addon : dossier=' .. Q.Safe(Q.name) .. ', version=' .. Q.version .. ', listes=' .. characters)
    if Q.sync then
        local state = Q.sync:Status()
        Q.Print('Synchro : ' .. (state.enabled and 'on' or 'off') .. ', file=' .. state.queued .. ', réassemblages=' .. state.buffers
            .. ', report=' .. state.deferred .. ', refus=' .. state.rejected)
    else Q.Print('Synchro : non démarrée') end
    for context, ms in pairs(Q.debug.slow) do Q.Print('Traitement lent : ' .. Q.Safe(context) .. ' ' .. ms .. ' ms') end
    for _, errorText in ipairs(Q.debug.errors) do Q.Print(Q.Safe(errorText)) end
end
