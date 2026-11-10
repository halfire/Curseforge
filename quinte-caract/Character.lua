local _, Q = ...
local function ns(value) return type(value) == 'table' and value or {} end
local function optional(tableValue) if next(tableValue) then return tableValue end end
local function number(label, fn, ...)
    return Q.Number((Q.Read(label, fn, ...)))
end
local function talents()
    local specialization = ns(C_SpecializationInfo)
    local index = Q.Number(Q.Read('GetSpecialization', specialization.GetSpecialization or GetSpecialization), 1, 100, true)
    local spec
    if index then
        local _, name = Q.Read('GetSpecializationInfo', specialization.GetSpecializationInfo or GetSpecializationInfo, index)
        spec = Q.String(name)
    end
    local config = Q.Number(Q.Read('GetActiveConfigID', ns(C_ClassTalents).GetActiveConfigID), 1, 1e9, true)
    if config then
        local export = Q.String(Q.Read('GenerateImportString', ns(C_Traits).GenerateImportString, config), 2048)
        if export then return export, spec end
    end
    local count = Q.Number(Q.Read('GetNumTalentTabs', GetNumTalentTabs), 1, 10, true)
    if count then
        local values, bestPoints, bestName = {}, -1, nil
        for tab = 1, count do
            local a, b, c, d, e, _, g
            if type(GetTalentTabInfo) == 'function' then
                a, b, c, d, e = Q.Read('GetTalentTabInfo.' .. tab, GetTalentTabInfo, tab)
            else
                a, b, c, d, e, _, g = Q.Read('GetTalentTabInfo.' .. tab, specialization.GetSpecializationInfo, tab)
            end
            local name, spent
            if type(a) == 'string' then
                name, spent = a, Q.Number(c, 0, 1000, true) or Q.Number(d, 0, 1000, true)
            else
                name = Q.String(b)
                spent = Q.Number(type(GetTalentTabInfo) == 'function' and e or g, 0, 1000, true)
            end
            if spent == nil then return nil, spec end
            values[#values + 1] = tostring(spent)
            if spent > bestPoints then bestPoints, bestName = spent, Q.String(name) end
        end
        return table.concat(values, '/'), spec or (bestPoints > 0 and bestName or nil)
    end
    return nil, spec
end
local function professions()
    local indices = {Q.Read('GetProfessions', GetProfessions)}
    local result, seen = {}, {}
    if type(GetProfessions) == 'function' and type(GetProfessionInfo) == 'function' and Q.api.GetProfessions.state == 'ok' then
        for i = 1, 6 do
            local index = Q.Number(indices[i], 1, 10000, true)
            if index then
                local name, _, skill, maximum = Q.Read('GetProfessionInfo.' .. i, GetProfessionInfo, index)
                name = Q.String(name)
                if name and not seen[name] then
                    result[#result + 1] = {name = name, skill = Q.Number(skill, 0, 10000), maxSkill = Q.Number(maximum, 0, 10000)}
                    seen[name] = true
                end
            end
        end
    else
        -- Resolve skill names from game spell IDs, never from a French/English label.
        local knownNames = {}
        for _, spell in ipairs({2259, 2018, 7411, 4036, 2366, 2108, 2575, 8613, 3908, 2550, 3273, 7620, 25229, 45357, 78670}) do
            local name = Q.String(Q.Read('professionSpell.' .. spell, (C_Spell or {}).GetSpellName or GetSpellInfo, spell), 100)
            if name then knownNames[name] = true end
        end
        local n = Q.Number(Q.Read('GetNumSkillLines', GetNumSkillLines), 0, 1000, true)
        if not n or type(GetSkillLineInfo) ~= 'function' then return nil end
        for i = 1, n do
            local name, header, _, rank, _, _, maximum, abandonable = Q.Read('GetSkillLineInfo.' .. i, GetSkillLineInfo, i)
            name = Q.String(name)
            if not header and name and not seen[name] and (abandonable == true or abandonable == 1 or knownNames[name]) then
                result[#result + 1] = {name = name, skill = Q.Number(rank, 0, 10000), maxSkill = Q.Number(maximum, 0, 10000)}
                seen[name] = true
            end
            if #result >= 16 then break end
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end
local function stats()
    local s = {health = number('UnitHealthMax', UnitHealthMax, 'player'), power = number('UnitPowerMax', UnitPowerMax, 'player')}
    for index, name in ipairs({'strength', 'agility', 'stamina', 'intellect', 'spirit'}) do
        local base, effective = Q.Read('UnitStat.' .. index, UnitStat, 'player', index)
        s[name] = Q.Number(effective) or Q.Number(base)
    end
    local baseArmor, effectiveArmor = Q.Read('UnitArmor', UnitArmor, 'player')
    s.armor = Q.Number(effectiveArmor) or Q.Number(baseArmor)
    local base, positive, negative = Q.Read('UnitAttackPower', UnitAttackPower, 'player')
    if Q.Number(base, -1e12) and Q.Number(positive, -1e12) and Q.Number(negative, -1e12) then
        s.attackPower = math.max(0, base + positive + negative)
    end
    local highest
    for school = 2, 7 do
        local power = number('GetSpellBonusDamage.' .. school, GetSpellBonusDamage, school)
        if power then highest = math.max(highest or 0, power) end
    end
    s.spellPower = highest
    local resistances = {}
    for name, school in pairs({fire = 2, frost = 4, nature = 3, shadow = 5, arcane = 6}) do
        local baseResistance, total = Q.Read('UnitResistance.' .. name, UnitResistance, 'player', school)
        resistances[name] = Q.Number(total, -100000, 100000) or Q.Number(baseResistance, -100000, 100000)
    end
    s.resistances = optional(resistances)
    return optional(s)
end
local function pvp()
    local rank = Q.Number(Q.Read('UnitPVPRank', UnitPVPRank, 'player'), 0, 100, true)
    local name
    if rank then name = Q.String(Q.Read('GetPVPRankInfo', GetPVPRankInfo, rank, 'player'), 100) end
    local kills = Q.Number(Q.Read('GetPVPLifetimeStats', GetPVPLifetimeStats), 0, 1e10, true)
    return optional({rank = rank, rankName = name, honorableKills = kills})
end
-- Raids verrouillés cette semaine (GetSavedInstanceInfo) : { CLÉ = fin du verrou }, clés du site (RAID_EVENTS), fin
-- arrondie à l'heure pour qu'un relevé suivant ne change pas la fiche à chaque seconde. Identifiants des cartes
-- d'instance : ceux du client (Onyxia 249… ; Hyjal 2981 et Terriers 3052 propres à Forever).
Q.RAID_MAPS = { [249] = 'ONY', [2981] = 'HYJAL', [3052] = 'BARROW', [409] = 'MC', [469] = 'BWL', [309] = 'ZG',
    [509] = 'AQ20', [531] = 'AQ40', [533] = 'NAXX' }
function Q.CollectLockouts(now)
    if type(GetNumSavedInstances) ~= 'function' or type(GetSavedInstanceInfo) ~= 'function' then return nil end
    now = now or Q.Now()
    local ok, count = pcall(GetNumSavedInstances)
    if not ok or type(count) ~= 'number' then return nil end
    local out = {}
    for i = 1, math.min(count, 50) do
        local good, _, _, reset, _, locked, extended, _, isRaid, _, _, _, _, _, mapID = pcall(GetSavedInstanceInfo, i)
        local key = good and Q.RAID_MAPS[tonumber(mapID) or 0]
        if key and (locked or extended) and type(reset) == 'number' and reset > 0 and not Q.Secret(reset) then
            out[key] = math.floor((now + reset) / 3600 + 0.5) * 3600
        end
    end
    return optional(out)
end

function Q.CollectCharacter()
    local name = Q.String(Quintessence.PlayerName(), 100)
    local realm = Q.String(Q.Read('GetRealmName', GetRealmName), 100)
    if not name or not realm then return nil end
    local _, class = Q.Read('UnitClass', UnitClass, 'player')
    local _, race = Q.Read('UnitRace', UnitRace, 'player')
    local faction = Q.Read('UnitFactionGroup', UnitFactionGroup, 'player')
    local guild, guildRank = Q.Read('GetGuildInfo', GetGuildInfo, 'player')
    local build, spec = talents()
    local equipment, itemLevel = Q.CollectEquipment()
    local attunements = Q.CollectAttunements and Q.CollectAttunements()
    return {name = name, realm = realm, class = Q.String(class), race = Q.String(race),
        sex = Q.Number(Q.Read('UnitSex', UnitSex, 'player'), 1, 3, true), faction = Q.String(faction),
        level = Q.Number(Q.Read('UnitLevel', UnitLevel, 'player'), 1, 1000, true),
        guild = Q.String(guild), guildRank = Q.String(guildRank), itemLevel = itemLevel,
        talents = build, spec = spec, stats = stats(), pvp = pvp(), professions = professions(),
        equipment = equipment, attunements = attunements, lockouts = Q.CollectLockouts(),
        pex = Q.PexForRecord and Q.PexForRecord() or nil,
        gameStats = Q.CollectGameStatistics and Q.CollectGameStatistics() or nil}
end
Q.Talents, Q.Professions = talents, professions
