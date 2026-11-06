local _, Q = ...
--[[
  Dungeons.lua : Préférences de donjons, recherche de groupe (LFG Guilde),
  Besoins par donjon et Matrice Anti-Conflit de butin.

  Prend en charge tous les donjons dont les 9 nouveaux donjons exclusifs de WoW Forever.
  Fonctionnalités clés :
    1. Besoins par donjon : Regroupe les membres de la guilde ayant besoin du même donjon
       (via préférences déclarées dans Quinte-group et besoins BiS de QuinteBisDB).
    2. Liste de butin & Détection de conflits (Anti-doublon) : Analyse tous les loots
       convoités dans un donjon et alerte si deux membres convoitent le même objet.
    3. Formation de groupe compatible en 1 clic : Recommande une composition optimale
       sans aucune concurrence sur le butin (0 doublon de loot).
]]

Q.FOREVER_DUNGEONS = {
    -- Donjons de WoW Forever (liste de Wowhead Forever, relevée le 04/11/2026) ; mêmes codes que activities() du site
    -- et Q.DUNGEONS de quinte-bis. Nouveaux donjons de Forever sous leur nom anglais (nom français inconnu).
    -- `short` : nom de la liste de gauche de l'onglet Donjons ; le nom complet reste dans le panneau de droite.
    { code = 'RFC', name = 'Gouffre de Ragefeu', short = 'Ragefeu', minLvl = 13, maxLvl = 18, icon = 'Spell_Fire_Fire' },
    { code = 'THANES', name = 'The Hall of Thanes', short = 'Thanes', minLvl = 13, maxLvl = 18, icon = 'INV_Hammer_20', new = true },
    { code = 'LORDAERON', name = 'Ruins of Lordaeron', short = 'Lordaeron', minLvl = 15, maxLvl = 20, icon = 'Spell_Shadow_RaiseDead', new = true },
    { code = 'WC', name = 'Cavernes des Lamentations', short = 'Lamentations', minLvl = 17, maxLvl = 24, icon = 'Ability_Creature_Poison_05' },
    { code = 'DM', name = 'Les Mortemines', short = 'Mortemines', minLvl = 17, maxLvl = 26, icon = 'Ability_DualWield' },
    { code = 'SFK', name = 'Donjon d\'Ombrecroc', short = 'Ombrecroc', minLvl = 22, maxLvl = 30, icon = 'Spell_Shadow_AntiShadow' },
    { code = 'EXCAV', name = 'Excavation Site: Wetlands', short = 'Wetlands', minLvl = 24, maxLvl = 29, icon = 'INV_Pick_02', new = true },
    { code = 'STOCKS', name = 'La Prison', short = 'Prison', minLvl = 24, maxLvl = 32, icon = 'INV_Misc_Note_01' },
    { code = 'BFD', name = 'Profondeurs de Brassenoire', short = 'Brassenoire', minLvl = 24, maxLvl = 32, icon = 'INV_Misc_Head_Dragon_Black' },
    { code = 'SM_GY', name = 'Monastère — Cimetière', short = 'Cimetière', minLvl = 26, maxLvl = 36, icon = 'INV_Misc_Bone_HumanSkull_01' },
    { code = 'DALARAN', name = 'City of Dalaran', short = 'Dalaran', minLvl = 28, maxLvl = 33, icon = 'Spell_Arcane_PortalDalaran', new = true },
    { code = 'GNOMER', name = 'Gnomeregan', short = 'Gnomeregan', minLvl = 29, maxLvl = 38, icon = 'Trade_BlackSmithing' },
    { code = 'RFK', name = 'Kraal de Tranchebauge', short = 'Tranchebauge', minLvl = 29, maxLvl = 38, icon = 'INV_Chest_Chain' },
    { code = 'SM_LIB', name = 'Monastère — Bibliothèque', short = 'Bibliothèque', minLvl = 29, maxLvl = 39, icon = 'INV_Misc_Book_08' },
    { code = 'SM_ARM', name = 'Monastère — Armurerie', short = 'Armurerie', minLvl = 32, maxLvl = 42, icon = 'INV_Helmet_04' },
    { code = 'DROWNED', name = 'The Drowned City', short = 'Drowned City', minLvl = 35, maxLvl = 40, icon = 'Spell_Frost_SummonWaterElemental', new = true },
    { code = 'SM_CATH', name = 'Monastère — Cathédrale', short = 'Cathédrale', minLvl = 35, maxLvl = 45, icon = 'Spell_Holy_PrayerOfFortitude' },
    { code = 'RFD', name = 'Souilles de Tranchebauge', short = 'Souilles', minLvl = 37, maxLvl = 46, icon = 'INV_Misc_Bone_HumanSkull_01' },
    { code = 'KROLDOK', name = 'Krol\'dok Stronghold', short = 'Krol\'dok', minLvl = 40, maxLvl = 45, icon = 'INV_BannerPVP_02', new = true },
    { code = 'ULDA', name = 'Uldaman', short = 'Uldaman', minLvl = 41, maxLvl = 51, icon = 'INV_Misc_Book_11' },
    { code = 'ZF', name = 'Zul\'Farrak', short = 'Zul\'Farrak', minLvl = 44, maxLvl = 54, icon = 'Ability_DualWield' },
    { code = 'MARA', name = 'Maraudon', short = 'Maraudon', minLvl = 46, maxLvl = 55, icon = 'Spell_Nature_EarthBindTotem' },
    { code = 'ALCAZ', name = 'Alcaz Prison', short = 'Alcaz', minLvl = 48, maxLvl = 53, icon = 'INV_Misc_Key_14', new = true },
    { code = 'ST', name = 'Temple d\'Atal\'Hakkar', short = 'Atal\'Hakkar', minLvl = 50, maxLvl = 60, icon = 'INV_Misc_Head_Dragon_01' },
    { code = 'BRD', name = 'Profondeurs de Rochenoire', short = 'Rochenoire', minLvl = 52, maxLvl = 60, icon = 'INV_Hammer_05' },
    { code = 'BLACKMAW', name = 'Blackmaw Hold', short = 'Blackmaw', minLvl = 55, maxLvl = 60, icon = 'Ability_Hunter_Pet_Bear', new = true },
    { code = 'LBRS', name = 'Pic Rochenoire inférieur', short = 'Pic Rochenoire', minLvl = 55, maxLvl = 60, icon = 'INV_Helmet_04' },
    { code = 'DME', name = 'Hache-Tripes Est', short = 'Hache-Tripes E', minLvl = 55, maxLvl = 60, icon = 'Spell_Nature_EarthBindTotem' },
    { code = 'DMW', name = 'Hache-Tripes Ouest', short = 'Hache-Tripes O', minLvl = 57, maxLvl = 60, icon = 'Spell_Arcane_PortalStormWind' },
    { code = 'DMN', name = 'Hache-Tripes Nord', short = 'Hache-Tripes N', minLvl = 57, maxLvl = 60, icon = 'INV_Chest_Chain' },
    { code = 'SHAPER', name = 'Shaper\'s Terrace', short = 'Shaper', minLvl = 58, maxLvl = 60, icon = 'INV_Misc_Gem_Variety_02', new = true },
    { code = 'STRAT', name = 'Stratholme', short = 'Stratholme', minLvl = 58, maxLvl = 60, icon = 'INV_Misc_Bone_HumanSkull_01' },
    { code = 'SCHOLO', name = 'Scholomance', short = 'Scholomance', minLvl = 58, maxLvl = 60, icon = 'Spell_Shadow_AntiShadow' },
}

-- Sources de raid ou hors-donjon exclues de la liste des besoins donjons (phase de pex)
local EXCLUDED_SOURCES = {
    ONY = true, MC = true, BWL = true, ZG = true, AQ20 = true, AQ40 = true, NAXX = true,
    HYJAL = true, HYJAL_D = true, BARROW = true, UBRS = true,
    CRAFT = true, QUEST = true, REP = true, PVP = true, WORLD = true, AUTRE = true,
}

Q.DUNGEON_BY_CODE = {}
for idx, d in ipairs(Q.FOREVER_DUNGEONS) do
    d.order = idx
    Q.DUNGEON_BY_CODE[d.code] = d
end

local DUNGEON_ALIASES = {
    VC = 'DM',
    STOCK = 'STOCKS',
    GNOM = 'GNOMER',
    ULD = 'ULDA',
}

-- Mémo des codes déjà normalisés : appelé des milliers de fois par Q.GetAllDungeonNeeds (32 donjons × préférences ×
-- lignes BiS), upper/gsub créait autant de chaînes à chaque rafraîchissement. Clés bornées (codes et sources vus).
local normalizedCodes = {}
function Q.NormalizeDungeonCode(code)
    if not code then return 'AUTRE' end
    local cached = normalizedCodes[code]
    if cached then return cached end
    local c = tostring(code):upper():gsub('%s+', '')
    c = DUNGEON_ALIASES[c] or c
    if type(code) == 'string' or type(code) == 'number' or type(code) == 'boolean' then normalizedCodes[code] = c end
    return c
end

function Q.GetDungeonInfo(code)
    local norm = Q.NormalizeDungeonCode(code)
    local d = Q.DUNGEON_BY_CODE[norm]
    if d then return d end

    -- Vérifier dans quinte-bis si disponible
    local bisDungeons = _G.Quintessence and _G.Quintessence.DUNGEONS
    if bisDungeons then
        for _, bd in ipairs(bisDungeons) do
            if bd.key == norm or DUNGEON_ALIASES[bd.key] == norm then
                return {
                    code = norm,
                    name = bd.name,
                    minLvl = bd.min or 50,
                    maxLvl = bd.max or 60,
                    icon = 'INV_Misc_QuestionMark'
                }
            end
        end
    end

    return {
        code = norm,
        name = tostring(code),
        minLvl = 50,
        maxLvl = 60,
        icon = 'INV_Misc_QuestionMark'
    }
end

local lastPrefBroadcast = 0

-- Enregistrer ses préférences de donjon et ses loots ciblés
function Q.SaveMyDungeonPreferences(role, dungeons, status, note, targetLoots)
    if not QuinteGroupDB.myPreferences then QuinteGroupDB.myPreferences = {} end
    local p = QuinteGroupDB.myPreferences

    p.role = role or p.role or 'DAMAGER'
    p.dungeons = dungeons or p.dungeons or {}
    p.status = status or p.status or 'active'
    p.note = note or p.note or ''
    p.targetLoots = targetLoots or p.targetLoots or {}
    p.updated = Q.Now()

    Q.BroadcastMyDungeonPreferences(true)
    if Q.UI and Q.UI.RefreshDungeons then Q.UI.RefreshDungeons() end
end

-- Donjons choisis, toujours sous la forme { [CODE] = true } (anciens formats : chaîne seule ou liste de codes)
local function dungeonSet(value)
    local set = {}
    if type(value) == 'string' then
        set[Q.NormalizeDungeonCode(value)] = true
    elseif type(value) == 'table' then
        for k, v in pairs(value) do
            if v == true then set[Q.NormalizeDungeonCode(k)] = true
            elseif type(v) == 'string' then set[Q.NormalizeDungeonCode(v)] = true end
        end
    end
    return set
end

--- Inscrit sur ce donjon ?
function Q.IsSignedUp(dungeonCode)
    local p = QuinteGroupDB.myPreferences
    if not p or p.status ~= 'active' then return false end
    return dungeonSet(p.dungeons)[Q.NormalizeDungeonCode(dungeonCode)] == true
end

--- Inscription ou désinscription sur UN donjon, sans toucher aux autres (avant, s'inscrire sur un donjon remplaçait
--- toute la liste : impossible d'être inscrit sur plusieurs donjons à la fois). Renvoie true si inscrit.
function Q.ToggleDungeonSignup(dungeonCode, role, note)
    local p = QuinteGroupDB.myPreferences or {}
    QuinteGroupDB.myPreferences = p
    local set = dungeonSet(p.status == 'active' and p.dungeons or nil)
    local code = Q.NormalizeDungeonCode(dungeonCode)
    local signed = not set[code]
    set[code] = signed or nil
    Q.SaveMyDungeonPreferences(role, set, next(set) and 'active' or 'inactive', note)
    return signed
end

--- Liste triée des donjons où l'on est inscrit
function Q.MySignups()
    local p = QuinteGroupDB.myPreferences
    local out = {}
    if p and p.status == 'active' then
        for code in pairs(dungeonSet(p.dungeons)) do out[#out + 1] = code end
    end
    table.sort(out)
    return out
end

--- Ce membre est-il déjà dans notre groupe ou raid ? (plus de bouton Inviter pour lui)
function Q.InMyGroup(name)
    if type(name) ~= 'string' or not (GetNumGroupMembers and IsInGroup and IsInGroup()) then return false end
    local raid = IsInRaid and IsInRaid()
    local count = GetNumGroupMembers() or 0
    for i = 1, count do
        local unit = raid and ('raid' .. i) or ('party' .. i)
        local full = Quintessence.UnitFullName and Quintessence.UnitFullName(unit)
        if full and Quintessence.SameName(full, name) then return true end
    end
    return false
end

-- Ajouter un loot ciblé pour un donjon donné
function Q.AddMyTargetLoot(dungeonCode, itemID, itemName)
    if not QuinteGroupDB.myPreferences then QuinteGroupDB.myPreferences = {} end
    local p = QuinteGroupDB.myPreferences
    if not p.targetLoots then p.targetLoots = {} end

    local norm = Q.NormalizeDungeonCode(dungeonCode)
    p.targetLoots[itemID] = {
        id = itemID,
        dungeon = norm,
        name = itemName or ('Objet #' .. itemID)
    }
    p.updated = Q.Now()
    Q.BroadcastMyDungeonPreferences(true)
    if Q.UI and Q.UI.RefreshDungeons then Q.UI.RefreshDungeons() end
end

-- Retirer un loot ciblé
function Q.RemoveMyTargetLoot(itemID)
    if QuinteGroupDB.myPreferences and QuinteGroupDB.myPreferences.targetLoots then
        QuinteGroupDB.myPreferences.targetLoots[itemID] = nil
        QuinteGroupDB.myPreferences.updated = Q.Now()
        Q.BroadcastMyDungeonPreferences(true)
        if Q.UI and Q.UI.RefreshDungeons then Q.UI.RefreshDungeons() end
    end
end

-- Diffuser ses préférences à la guilde
-- target : réponse privée à un membre qui arrive (r = 1 : il ne répond pas à son tour)
function Q.BroadcastMyDungeonPreferences(force, target)
    local now = Q.Now()
    if not target then
        if not force and (now - lastPrefBroadcast) < 60 then return end
        lastPrefBroadcast = now
    end

    local p = QuinteGroupDB.myPreferences or {}
    local myLevel = UnitLevel and UnitLevel('player') or 60
    local _, class = UnitClass and UnitClass('player')

    if Q.comm and Q.comm.Send then
        Q.comm:Send({
            t = 'dungeon_pref',
            role = p.role or 'DAMAGER',
            dungeons = p.dungeons or {},
            targetLoots = p.targetLoots or {},
            status = p.status or 'active',
            note = p.note or '',
            level = myLevel,
            class = class or 'WARRIOR',
            r = target and 1 or nil
        }, target)
    end
end

-- Réception des préférences d'un membre
local prefReplied = {}
local function prefKey(name)
    if Quintessence.CanonicalKey then return Quintessence.CanonicalKey(name) end
    return (tostring(name or ''):gsub('%s', ''):lower())
end
function Q.OnReceiveDungeonPref(data, sender)
    if not sender or not data then return end
    if not QuinteGroupDB.memberPreferences then QuinteGroupDB.memberPreferences = {} end
    local key, now = prefKey(sender), Q.Now()

    -- Membre qui arrive (ou revient) : on lui envoie nos inscriptions en privé, s'il y en a
    local previous = QuinteGroupDB.memberPreferences[key]
    local mine = QuinteGroupDB.myPreferences
    if not data.r and mine and mine.status == 'active' and (not previous or now - (previous.updated or 0) >= 3600)
        and now - (prefReplied[key] or 0) >= 300 and C_Timer and C_Timer.After then
        prefReplied[key] = now
        C_Timer.After(1 + math.random() * 4, function()
            Q.Run('inscriptions', Q.BroadcastMyDungeonPreferences, true, sender)
        end)
    end

    QuinteGroupDB.memberPreferences[key] = {
        name = Quintessence.DisplayName and Quintessence.DisplayName(sender) or sender,
        class = data.class or 'WARRIOR',
        level = data.level or 60,
        role = data.role or 'DAMAGER',
        dungeons = data.dungeons or {},
        targetLoots = data.targetLoots or {},
        status = data.status or 'active',
        note = data.note or '',
        updated = Q.Now()
    }

    if Q.UI and Q.UI.RefreshDungeons then Q.UI.RefreshDungeons() end
end

-- Vérifier si un membre est en ligne
-- La liste de guilde est relue une seule fois par période de 10 s (et chaque nom résolu mémorisé) : avant, chaque
-- membre de chaque donjon relisait toute la liste (Q.GetAllDungeonNeeds : ~8 000 appels à GetGuildRosterInfo).
local ONLINE_CACHE_TTL = 10
local onlineCache, rosterNames, rosterOnline, onlineCacheAt = {}, {}, {}, nil
local function onlineNow()
    return (GetTime and GetTime()) or Q.Now()
end
local function readRoster()
    onlineCache, rosterNames, rosterOnline = {}, {}, {}
    if GetNumGuildMembers and GetGuildRosterInfo then
        local count = GetNumGuildMembers() or 0
        for i = 1, count do
            local fullName, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            if fullName and rosterOnline[fullName] == nil then
                rosterNames[#rosterNames + 1] = fullName
                rosterOnline[fullName] = not not online
            end
        end
    end
end
function Q.IsOnline(name)
    if not name then return false end
    local myName = Q.PlayerName and Q.PlayerName()
    if myName and (name == myName or (Quintessence and Quintessence.SameName and Quintessence.SameName(name, myName))) then
        return true
    end
    local now = onlineNow()
    if not onlineCacheAt or now - onlineCacheAt >= ONLINE_CACHE_TTL or now < onlineCacheAt then
        onlineCacheAt = now
        readRoster()
    end
    local cached = onlineCache[name]
    if cached ~= nil then return cached end
    local result = false
    if UnitIsConnected and UnitIsConnected(name) then
        result = true
    elseif rosterOnline[name] ~= nil then
        result = rosterOnline[name]
    elseif Quintessence and Quintessence.SameName then
        for _, fullName in ipairs(rosterNames) do
            if Quintessence.SameName(fullName, name) then result = rosterOnline[fullName]; break end
        end
    end
    onlineCache[name] = result
    return result
end

-- Obtenir le nom et l'icône d'un objet
-- Réponses complètes du jeu mémorisées (une info d'objet ne change pas) ; un objet pas encore en cache est redemandé.
local itemInfoCache = {}
function Q.GetItemDisplayInfo(itemID)
    if not itemID then return 'Objet inconnu', 'Interface\\Icons\\INV_Misc_QuestionMark', 1, nil end
    local known = itemInfoCache[itemID]
    if known then return known[1], known[2], known[3], known[4] end
    local name, link, quality, _, _, _, _, _, _, texture = nil, nil, 1, nil, nil, nil, nil, nil, nil, nil
    if GetItemInfo then
        name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(itemID)
    end
    if not name and C_Item and C_Item.GetItemInfo then
        name, link, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(itemID)
    end
    if not name and C_Item and C_Item.GetItemNameByID then
        name = C_Item.GetItemNameByID(itemID)
    end
    if name and texture and link then itemInfoCache[itemID] = { name, texture, quality or 1, link } end
    return name or ('Objet #' .. itemID), texture or 'Interface\\Icons\\INV_Misc_QuestionMark', quality or 1, link
end

-- Rôle par défaut selon la classe
local CLASS_DEFAULT_ROLES = {
    WARRIOR = 'TANK',
    PALADIN = 'TANK',
    PRIEST = 'HEALER',
    DRUID = 'HEALER',
    SHAMAN = 'HEALER',
    ROGUE = 'DAMAGER',
    MAGE = 'DAMAGER',
    WARLOCK = 'DAMAGER',
    HUNTER = 'DAMAGER',
}

-- Analyse des besoins pour un donjon spécifique
function Q.GetDungeonNeeds(dungeonCode)
    local norm = Q.NormalizeDungeonCode(dungeonCode)
    local dInfo = Q.GetDungeonInfo(norm)
    local now = Q.Now()
    local myName = Q.PlayerName and Q.PlayerName()

    local membersMap = {}
    local lootsMap = {}

    local function getOrCreateMember(name, class, level, role, isPlayer, note, source)
        if not membersMap[name] then
            membersMap[name] = {
                name = name,
                class = class or 'WARRIOR',
                level = level or 60,
                role = role or CLASS_DEFAULT_ROLES[class] or 'DAMAGER',
                isPlayer = not not isPlayer,
                online = isPlayer or Q.IsOnline(name),
                inGroup = not isPlayer and Q.InMyGroup(name),
                note = note or '',
                source = source or 'lfg',
                items = {}
            }
        end
        return membersMap[name]
    end

    local function addLootNeed(itemID, itemName, member)
        if not itemID then return end
        if not lootsMap[itemID] then
            local displayName, texture, quality = Q.GetItemDisplayInfo(itemID)
            lootsMap[itemID] = {
                id = itemID,
                name = itemName or displayName,
                icon = texture,
                quality = quality,
                members = {}
            }
        end

        local loot = lootsMap[itemID]
        -- Vérifier si le membre est déjà listé sur ce loot
        local already = false
        for _, m in ipairs(loot.members) do
            if m.name == member.name then already = true; break end
        end
        if not already then
            loot.members[#loot.members + 1] = {
                name = member.name,
                role = member.role,
                class = member.class,
                isPlayer = member.isPlayer
            }
        end

        -- Ajouter à la liste d'objets du membre
        local itemAlready = false
        for _, it in ipairs(member.items) do
            if it.id == itemID then itemAlready = true; break end
        end
        if not itemAlready then
            member.items[#member.items + 1] = {
                id = itemID,
                name = loot.name,
                icon = loot.icon,
                quality = loot.quality
            }
        end
    end

    -- 1. Vérifier les préférences locales
    local myP = QuinteGroupDB.myPreferences
    if myP and myP.status == 'active' and myName then
        local matches = false
        if type(myP.dungeons) == 'table' then
            for k, v in pairs(myP.dungeons) do
                if (v == true and Q.NormalizeDungeonCode(k) == norm) or (Q.NormalizeDungeonCode(v) == norm) then
                    matches = true; break
                end
            end
        elseif type(myP.dungeons) == 'string' and Q.NormalizeDungeonCode(myP.dungeons) == norm then
            matches = true
        end

        if not matches and type(myP.targetLoots) == 'table' then
            for _, lt in pairs(myP.targetLoots) do
                if Q.NormalizeDungeonCode(lt.dungeon) == norm then
                    matches = true; break
                end
            end
        end

        if matches then
            local _, class = UnitClass and UnitClass('player')
            local m = getOrCreateMember(myName, class or 'WARRIOR', UnitLevel and UnitLevel('player') or 60, myP.role, true, myP.note, 'lfg')
            if myP.targetLoots then
                for id, lt in pairs(myP.targetLoots) do
                    if Q.NormalizeDungeonCode(lt.dungeon) == norm then
                        addLootNeed(id, lt.name, m)
                    end
                end
            end
        end
    end

    -- 2. Vérifier les préférences des membres reçues via réseau (clé normalisée, nom affichable dans p.name)
    if QuinteGroupDB.memberPreferences then
        local myKey = prefKey(myName or '')
        for key, p in pairs(QuinteGroupDB.memberPreferences) do
            local name = type(p) == 'table' and p.name or key
            if key ~= myKey and type(p) == 'table' and p.status == 'active' and (now - (p.updated or 0)) < 7200
                and not (Quintessence.IsOnline and Quintessence.IsOnline(name) == false) then
                local matches = false
                if type(p.dungeons) == 'table' then
                    for k, v in pairs(p.dungeons) do
                        if (v == true and Q.NormalizeDungeonCode(k) == norm) or (Q.NormalizeDungeonCode(v) == norm) then
                            matches = true; break
                        end
                    end
                elseif type(p.dungeons) == 'string' and Q.NormalizeDungeonCode(p.dungeons) == norm then
                    matches = true
                end

                if not matches and type(p.targetLoots) == 'table' then
                    for _, lt in pairs(p.targetLoots) do
                        if Q.NormalizeDungeonCode(lt.dungeon) == norm then
                            matches = true; break
                        end
                    end
                end

                if matches then
                    local m = getOrCreateMember(name, p.class, p.level, p.role, false, p.note, 'lfg')
                    if p.targetLoots then
                        for id, lt in pairs(p.targetLoots) do
                            if Q.NormalizeDungeonCode(lt.dungeon) == norm then
                                addLootNeed(id, lt.name, m)
                            end
                        end
                    end
                end
            end
        end
    end

    -- 3. Vérifier les besoins BiS dans QuinteBisDB si présent
    local bisDB = _G.QuinteBisDB
    if bisDB and bisDB.characters then
        for charKey, c in pairs(bisDB.characters) do
            local cName = c.name or charKey:match('^([^-]+)')
            if c.items and type(c.items) == 'table' then
                for _, row in pairs(c.items) do
                    if row and not row.obtained and row.source and row.item then
                        if Q.NormalizeDungeonCode(row.source) == norm then
                            local isPlayer = myName and (cName == myName or (Quintessence and Quintessence.SameName and Quintessence.SameName(cName, myName)))
                            local m = getOrCreateMember(cName, c.class, c.level, nil, isPlayer, nil, 'bis')
                            addLootNeed(row.item, nil, m)
                        end
                    end
                end
            end
        end
    end

    -- Construction des listes et analyse des conflits
    local memberList = {}
    for _, m in pairs(membersMap) do
        memberList[#memberList + 1] = m
    end

    local roleWeight = { TANK = 1, HEALER = 2, DAMAGER = 3 }
    table.sort(memberList, function(a, b)
        local wa = roleWeight[a.role] or 4
        local wb = roleWeight[b.role] or 4
        if wa ~= wb then return wa < wb end
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)

    local lootList = {}
    local conflictList = {}
    local uniqueList = {}

    for _, loot in pairs(lootsMap) do
        loot.hasConflict = (#loot.members > 1)
        if loot.hasConflict then
            conflictList[#conflictList + 1] = loot
        else
            uniqueList[#uniqueList + 1] = loot
        end
        lootList[#lootList + 1] = loot
    end

    -- Trier les loots : conflits d'abord, puis par nombre de membres
    table.sort(lootList, function(a, b)
        if a.hasConflict ~= b.hasConflict then return a.hasConflict end
        if #a.members ~= #b.members then return #a.members > #b.members end
        return a.name < b.name
    end)
    table.sort(conflictList, function(a, b)
        if #a.members ~= #b.members then return #a.members > #b.members end
        return a.name < b.name
    end)

    return {
        dungeon = dInfo,
        code = dInfo.code,
        name = dInfo.name,
        short = dInfo.short,
        minLvl = dInfo.minLvl,
        maxLvl = dInfo.maxLvl,
        order = dInfo.order or 999,
        icon = dInfo.icon,
        new = dInfo.new,
        members = memberList,
        totalMembers = #memberList,
        loots = lootList,
        totalLoots = #lootList,
        conflicts = conflictList,
        conflictCount = #conflictList,
        hasConflicts = (#conflictList > 0),
        uniqueLoots = uniqueList,
    }
end

-- Récapitulatif de tous les donjons (niveau 1 à 60, hors raids)
function Q.GetAllDungeonNeeds()
    local list = {}
    local processed = {}

    -- Parcourir tous les donjons 1-60
    for _, d in ipairs(Q.FOREVER_DUNGEONS) do
        local needs = Q.GetDungeonNeeds(d.code)
        list[#list + 1] = needs
        processed[d.code] = true
    end

    -- Ajouter les autres donjons 5 joueurs issus de QuinteBisDB s'ils ont des besoins (en excluant les raids)
    local bisDB = _G.QuinteBisDB
    if bisDB and bisDB.characters then
        for _, c in pairs(bisDB.characters) do
            for _, row in pairs(c.items or {}) do
                if row and not row.obtained and row.source then
                    local norm = Q.NormalizeDungeonCode(row.source)
                    if not processed[norm] and not EXCLUDED_SOURCES[norm] then
                        local needs = Q.GetDungeonNeeds(norm)
                        if needs.totalMembers > 0 then
                            list[#list + 1] = needs
                            processed[norm] = true
                        end
                    end
                end
            end
        end
    end

    -- Tri : donjons avec des besoins actifs d'abord, puis par niveau croissant (1 à 60)
    table.sort(list, function(a, b)
        local hasA = a.totalMembers > 0
        local hasB = b.totalMembers > 0
        if hasA ~= hasB then return hasA end
        if hasA and a.totalMembers ~= b.totalMembers then return a.totalMembers > b.totalMembers end
        if (a.minLvl or 50) ~= (b.minLvl or 50) then return (a.minLvl or 50) < (b.minLvl or 50) end
        if (a.maxLvl or 60) ~= (b.maxLvl or 60) then return (a.maxLvl or 60) < (b.maxLvl or 60) end
        return (a.order or 999) < (b.order or 999)
    end)

    return list
end

-- Algorithme de composition de groupe compatible (Anti-doublon de loot)
function Q.GetCompatibleGroup(dungeonCode)
    local needs = Q.GetDungeonNeeds(dungeonCode)
    local members = needs.members

    local selected = {}
    local excluded = {}
    local claimedItems = {} -- itemID -> memberName

    local tanks = {}
    local healers = {}
    local dps = {}

    for _, m in ipairs(members) do
        if m.role == 'TANK' then
            tanks[#tanks + 1] = m
        elseif m.role == 'HEALER' then
            healers[#healers + 1] = m
        else
            dps[#dps + 1] = m
        end
    end

    local function tryAddMember(m, maxRoleCount, currentList)
        if #currentList >= maxRoleCount then return false end

        -- Vérifier si l'un de ses objets est déjà revendiqué
        local conflictItem = nil
        local conflictWith = nil
        for _, it in ipairs(m.items) do
            if claimedItems[it.id] then
                conflictItem = it
                conflictWith = claimedItems[it.id]
                break
            end
        end

        if conflictItem then
            excluded[#excluded + 1] = {
                member = m,
                conflictItem = conflictItem,
                conflictWith = conflictWith
            }
            return false
        end

        -- Valider l'ajout
        selected[#selected + 1] = m
        currentList[#currentList + 1] = m
        for _, it in ipairs(m.items) do
            claimedItems[it.id] = m.name
        end
        return true
    end

    local pickedTanks = {}
    local pickedHealers = {}
    local pickedDPS = {}

    -- 1 Tank max
    for _, t in ipairs(tanks) do tryAddMember(t, 1, pickedTanks) end
    -- 1 Healer max
    for _, h in ipairs(healers) do tryAddMember(h, 1, pickedHealers) end
    -- 3 DPS max
    for _, d in ipairs(dps) do tryAddMember(d, 3, pickedDPS) end

    -- Si manque de DPS et qu'il reste d'autres rôles non retenus sans conflit
    if #pickedDPS < 3 then
        for _, t in ipairs(tanks) do
            if #selected < 5 and not t.inGroup then tryAddMember(t, 2, pickedTanks) end
        end
    end

    return {
        selected = selected,
        excluded = excluded,
        claimedItems = claimedItems,
        needs = needs
    }
end

-- Inviter en un clic le groupe optimal sans conflit
function Q.InviteCompatibleGroup(dungeonCode)
    local comp = Q.GetCompatibleGroup(dungeonCode)
    local myName = Q.PlayerName and Q.PlayerName()
    local count = 0

    for _, m in ipairs(comp.selected) do
        if m.name ~= myName and not Q.InMyGroup(m.name) then
            if C_PartyInfo and C_PartyInfo.InviteUnit then
                C_PartyInfo.InviteUnit(m.name)
            elseif InviteUnit then
                InviteUnit(m.name)
            end
            count = count + 1
        end
    end

    if count > 0 then
        Q.Print(string.format('Groupe sans conflit de loot formé : %d invitation(s) envoyée(s) !', count))
    else
        Q.Print('Aucun membre supplémentaire à inviter pour ce donjon.')
    end

    if #comp.excluded > 0 then
        local firstEx = comp.excluded[1]
        Q.Print(string.format('|cffff7070Attention :|r %s a été mis en réserve (conflit avec %s sur %s). Créez un 2e groupe pour maximiser les loots !',
            firstEx.member.name, firstEx.conflictWith, firstEx.conflictItem.name))
    end
end

-- Liste des membres en recherche de donjon (rétro-compatibilité LFG)
function Q.GetLFGMembers()
    local list = {}
    local now = Q.Now()
    local myName = Q.PlayerName and Q.PlayerName()

    local myP = QuinteGroupDB.myPreferences
    if myP and myP.status == 'active' and myName then
        local _, class = UnitClass and UnitClass('player')
        list[#list + 1] = {
            name = myName,
            class = class or 'WARRIOR',
            level = UnitLevel and UnitLevel('player') or 60,
            role = myP.role or 'DAMAGER',
            dungeons = myP.dungeons or {},
            status = myP.status,
            note = myP.note or '',
            updated = myP.updated or now,
            isPlayer = true
        }
    end

    if QuinteGroupDB.memberPreferences then
        local myKey = prefKey(myName or '')
        for key, p in pairs(QuinteGroupDB.memberPreferences) do
            if key ~= myKey and type(p) == 'table' and p.status == 'active' and (now - (p.updated or 0)) < 7200 then
                list[#list + 1] = p
            end
        end
    end

    local roleWeight = { TANK = 1, HEALER = 2, DAMAGER = 3 }
    table.sort(list, function(a, b)
        local wa = roleWeight[a.role] or 4
        local wb = roleWeight[b.role] or 4
        if wa ~= wb then return wa < wb end
        return a.name < b.name
    end)

    return list
end

function Q.InitDungeons()
    -- Anciennes clés (expéditeur brut) remplacées à la prochaine réception
    for key, p in pairs(QuinteGroupDB.memberPreferences or {}) do
        if type(p) ~= 'table' or key ~= prefKey(p.name or key) then QuinteGroupDB.memberPreferences[key] = nil end
    end
    -- Quelqu'un rejoint ou quitte le groupe : boutons Inviter mis à jour (onglets ouverts seulement)
    local frame = CreateFrame('Frame')
    Q.Call(frame.RegisterEvent, frame, 'GROUP_ROSTER_UPDATE')
    frame:SetScript('OnEvent', function()
        if Q.UI and Q.UI.RefreshDungeons then Q.Run('groupe', Q.UI.RefreshDungeons) end
        if Q.UI and Q.UI.RefreshLeveling then Q.Run('groupe', Q.UI.RefreshLeveling) end
    end)
    -- Rappel toutes les 20 min tant qu'on est inscrit (les autres gardent une inscription 2 h)
    if C_Timer and C_Timer.After then
        local function keepalive()
            local p = QuinteGroupDB.myPreferences
            if p and p.status == 'active' and next(dungeonSet(p.dungeons)) then
                Q.Run('inscriptions', Q.BroadcastMyDungeonPreferences, true)
            end
            C_Timer.After(1200, keepalive)
        end
        C_Timer.After(1200, keepalive)
    end
end
