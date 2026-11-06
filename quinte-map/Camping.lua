local _, Q = ...
--[[
  Camping.lua : Carte des Feux de Camp de la Guilde (Mécanique de Camping WoW Forever).
  Quand un membre pose un campement social (buffs de repos, crafts de campement),
  sa position apparaît sur la carte tactique de tous les membres avec le numéro de Layer.
]]

local CAMP_DURATION = 1800 -- 30 minutes
local CAMP_BUFF_KEYWORDS = { 'campement', 'camping', 'feu de camp', 'campfire', 'repis du voyageur' }
-- Forever : aura « Welcoming Campfire » (1229739, et 1289723 sa variante d'artisanat), présente seulement assis au feu
-- de camp. « Campfire Nearby » (1283391, simple passage près d'un feu) et les autres auras de camp contiennent aussi
-- « camp » dans leur nom : avec un identifiant lisible, on ne se fie plus au nom (fausses annonces de campement).
local CAMP_SEATED_SPELLS = { [1229739] = true, [1289723] = true }

local function isSecret(v)
    return type(issecretvalue) == 'function' and issecretvalue(v)
end

local function matchCampBuff(name)
    if not name or isSecret(name) or type(name) ~= 'string' then return false end
    local lower = name:lower()
    for _, kw in ipairs(CAMP_BUFF_KEYWORDS) do
        if lower:find(kw, 1, true) then return true end
    end
    return false
end

-- Aura de C_UnitAuras (table) : identifiant si lisible, sinon nom (anciens clients)
local function isCampAura(d)
    if type(d) ~= 'table' then return false end
    local id = d.spellId
    if type(id) == 'number' and not isSecret(id) then return CAMP_SEATED_SPELLS[id] == true end
    return matchCampBuff(d.name)
end

-- Installer ou déclarer un campement de guilde à sa position
function Q.DeployCamp()
    local x, y, mapID = Q.GetPlayerCoordinates()
    local zone = (GetZoneText and GetZoneText()) or 'Inconnue'
    local subzone = (GetSubZoneText and GetSubZoneText()) or ''
    local layer = Q.DetectCurrentLayer and Q.DetectCurrentLayer()
    local _, class = UnitClass and UnitClass('player')
    local myName = Q.PlayerName()
    local now = Q.Now()

    local camp = {
        owner = myName,
        class = class or 'WARRIOR',
        zone = zone,
        subzone = subzone,
        mapID = mapID,
        x = x,
        y = y,
        layer = layer,
        zid = Q.CurrentZid(), -- identifiant brut du layer : chacun le traduit dans sa numérotation (quinte-layer 0.3.0)
        deployedAt = now,
        expiresAt = now + CAMP_DURATION,
    }

    if not QuinteMapDB.camps then QuinteMapDB.camps = {} end
    QuinteMapDB.camps[Q.Who(myName)] = camp

    -- Diffusion à la guilde
    if Q.comm and Q.comm.Send then
        Q.comm:Send({
            t = 'camp',
            camp = camp
        })
    end

    Q.Print(string.format('|cffffa500[CAMPEMENT]|r Campement installé à %s%s (%.1f, %.1f - |cff38bdf8%s|r) pour 30 minutes !',
        zone, subzone ~= '' and (' - ' .. subzone) or '', x, y, Q.LayerLabel(layer)))

    if Q.UI and Q.UI.RefreshCamps then Q.UI.RefreshCamps() end
    return camp
end

-- Lever son campement
function Q.RemoveCamp()
    local myName = Q.PlayerName()
    if QuinteMapDB.camps then
        QuinteMapDB.camps[Q.Who(myName)] = nil
        QuinteMapDB.camps[myName] = nil -- ancienne clé (0.2.0)
    end

    if Q.comm and Q.comm.Send then
        Q.comm:Send({
            t = 'camp_remove',
            owner = myName
        })
    end

    Q.Print('Campement replié.')
    if Q.UI and Q.UI.RefreshCamps then Q.UI.RefreshCamps() end
end

-- Réception d'un campement depuis la guilde
function Q.OnReceiveCamp(data, sender)
    if not data or type(data.camp) ~= 'table' or not sender then return end
    local c = data.camp
    c.owner = Q.DisplayName(sender)
    -- Durée restante recalculée sur notre horloge (celles des joueurs diffèrent)
    local left = math.max(0, math.min(1800, (tonumber(c.expiresAt) or 0) - (tonumber(c.deployedAt) or tonumber(c.expiresAt) or 0)))
    if left == 0 then left = 1800 end
    c.deployedAt, c.expiresAt = Q.Now(), Q.Now() + left

    if not QuinteMapDB.camps then QuinteMapDB.camps = {} end
    QuinteMapDB.camps[Q.Who(sender)] = c

    Q.Print(string.format('|cffffa500[Campement]|r |cffffffff%s|r a posé un campement à %s%s (|cff38bdf8%s|r). Venez vous reposer et discuter autour du feu !',
        Q.Safe(c.owner), Q.Safe(c.zone or 'Inconnue'), (c.subzone and c.subzone ~= '') and (' - ' .. c.subzone) or '', Q.LayerLabel(Q.LayerFor(c))))

    if Q.UI and Q.UI.RefreshCamps then Q.UI.RefreshCamps() end
end

function Q.OnReceiveCampRemove(_, sender)
    local who = sender and Q.Who(sender)
    if who and QuinteMapDB.camps and QuinteMapDB.camps[who] then
        QuinteMapDB.camps[who] = nil
        if Q.UI and Q.UI.RefreshCamps then Q.UI.RefreshCamps() end
    end
end

-- Liste des campements actifs
function Q.GetActiveCamps()
    local list = {}
    local now = Q.Now()
    if not QuinteMapDB.camps then return list end

    for owner, c in pairs(QuinteMapDB.camps) do
        if type(c) == 'table' and (c.expiresAt or 0) > now and not Q.IsOffline(c.owner or owner)
            and owner == Q.Who(c.owner or owner) then
            list[#list + 1] = c
        else
            QuinteMapDB.camps[owner] = nil
        end
    end

    table.sort(list, function(a, b) return (a.deployedAt or 0) > (b.deployedAt or 0) end)
    return list
end

function Q.GetActiveCampCount()
    return #Q.GetActiveCamps()
end

-- Détection automatique de campement via les auras du joueur
-- updateInfo (UNIT_AURA du client moderne) : seules les auras ajoutées sont examinées. Avant, chaque UNIT_AURA
-- (des dizaines par minute en combat) relisait jusqu'à 30 auras et leurs noms, même pour un simple rafraîchissement.
local lastAutoDetected = 0
function Q.CheckPlayerAurasForCamp(updateInfo)
    local now = Q.Now()
    if (now - lastAutoDetected) < 300 then return end -- Au max toutes les 5 min

    local hasBuff = false
    if type(updateInfo) == 'table' and not updateInfo.isFullUpdate then
        if type(updateInfo.addedAuras) ~= 'table' then return end -- auras mises à jour ou retirées seulement
        for _, d in ipairs(updateInfo.addedAuras) do
            if type(d) == 'table' and d.isHelpful ~= false and isCampAura(d) then hasBuff = true; break end
        end
    elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 30 do
            local d = C_UnitAuras.GetAuraDataByIndex('player', i, 'HELPFUL')
            if not d then break end
            if isCampAura(d) then hasBuff = true; break end
        end
    elseif UnitAura then
        for i = 1, 30 do
            local name = UnitAura('player', i, 'HELPFUL')
            if not name then break end
            if matchCampBuff(name) then hasBuff = true; break end
        end
    end

    if hasBuff then
        lastAutoDetected = now
        -- Notre campement est encore annoncé pour plus de 5 min : pas de nouvelle annonce à toute la guilde
        local mine = QuinteMapDB.camps and QuinteMapDB.camps[Q.Who(Q.PlayerName())]
        if mine and (mine.expiresAt or 0) - now > 300 then return end
        Q.DeployCamp()
    end
end

function Q.InitCamping()
    local frame = CreateFrame('Frame')
    -- Seulement les auras du joueur : UNIT_AURA arrive pour chaque membre du raid et chaque plaque de nom
    if not (frame.RegisterUnitEvent and Q.Call(frame.RegisterUnitEvent, frame, 'UNIT_AURA', 'player')) then
        Q.Call(frame.RegisterEvent, frame, 'UNIT_AURA')
    end
    frame:SetScript('OnEvent', function(_, event, unit, updateInfo)
        if event == 'UNIT_AURA' and unit == 'player' then
            Q.Run('aura_camp', Q.CheckPlayerAurasForCamp, updateInfo)
        end
    end)
end
