local _, Q = ...
--[[
  Rares.lua : monstre rare repéré. Quand un membre voit un rare (cible, survol ou plaque de nom), la guilde reçoit son
  nom, la zone, la position du membre et le layer, comme pour le SOS (canal qmap, message `rare`).
  Le rare se reconnaît par UnitClassification ('rare' ou 'rareelite') : aucune liste de monstres à tenir à jour.
  Un même rare n'est annoncé qu'une fois toutes les 10 minutes (chez soi et chez les autres) ; il reste affiché 30 min.
]]
local RARE_TTL, RARE_REPEAT = 1800, 600
local RARE_CLASSES = { rare = true, rareelite = true }

local function isSecret(v) return type(issecretvalue) == 'function' and issecretvalue(v) end
local function plain(v) return v ~= nil and not isSecret(v) end
local function rares()
    QuinteMapDB.rares = type(QuinteMapDB.rares) == 'table' and QuinteMapDB.rares or {}
    return QuinteMapDB.rares
end

-- Numéro du PNJ (6e partie du GUID « Creature-0-serveur-instance-zone-PNJ-apparition »)
local function npcOf(unit)
    if not UnitGUID then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or type(guid) ~= 'string' or isSecret(guid) then return nil end
    local npc = guid:match('^Creature%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-')
    return tonumber(npc)
end

--- Ce PNJ est-il un rare vivant, pas un joueur ? Retourne son numéro et son nom.
function Q.RareOf(unit)
    if not unit or not UnitExists or not UnitClassification then return nil end
    local ok, exists = pcall(UnitExists, unit)
    if not ok or not plain(exists) or not exists then return nil end
    if UnitIsPlayer then local okP, isPlayer = pcall(UnitIsPlayer, unit); if not okP or not plain(isPlayer) or isPlayer then return nil end end
    if UnitIsDead then local okD, dead = pcall(UnitIsDead, unit); if not okD or not plain(dead) or dead then return nil end end
    local okC, classification = pcall(UnitClassification, unit)
    if not okC or not plain(classification) or not RARE_CLASSES[classification] then return nil end
    local npc = npcOf(unit)
    local okN, name = pcall(UnitName, unit)
    if not npc or not okN or type(name) ~= 'string' or isSecret(name) or name == '' then return nil end
    return npc, name:sub(1, 60), classification == 'rareelite'
end

--- Rare vu : enregistré et annoncé à la guilde (une fois par 10 min pour un même rare).
function Q.SpotRare(unit)
    local npc, name, elite = Q.RareOf(unit)
    if not npc then return nil end
    local now, known = Q.Now(), rares()[npc]
    if known and now - (known.time or 0) < RARE_REPEAT then return nil end
    local x, y, mapID = Q.GetPlayerCoordinates()
    local zone = GetZoneText and GetZoneText() or nil
    local r = { npc = npc, name = name, elite = elite or nil, mapID = mapID, zone = zone, x = x, y = y,
        layer = Q.DetectCurrentLayer and Q.DetectCurrentLayer() or 0, zid = Q.CurrentZid and Q.CurrentZid() or nil,
        by = Q.PlayerName(), time = now }
    rares()[npc] = r
    if Q.comm and Q.comm.Send then
        Q.comm:Send({ t = 'rare', r = { npc = npc, name = name, elite = r.elite, mapID = mapID, zone = zone, x = x, y = y, layer = r.layer, zid = r.zid } })
    end
    if Q.UI and Q.UI.Refresh then Q.UI.Refresh() end
    return r
end

function Q.OnReceiveRare(data, sender)
    local r = type(data) == 'table' and data.r
    if type(r) ~= 'table' then return end
    local npc = tonumber(r.npc)
    if not npc or npc < 1 or npc > 1e8 or npc % 1 ~= 0 or type(r.name) ~= 'string' or r.name == '' or #r.name > 60 then return end
    if r.name:find('[%z\1-\31|]') then return end
    local now, known = Q.Now(), rares()[npc]
    if known and now - (known.time or 0) < RARE_REPEAT then return end
    local x, y = tonumber(r.x), tonumber(r.y)
    rares()[npc] = { npc = npc, name = r.name, elite = r.elite == true or nil, mapID = tonumber(r.mapID),
        zone = type(r.zone) == 'string' and r.zone:sub(1, 60) or nil, x = x and math.max(0, math.min(100, x)) or 0,
        y = y and math.max(0, math.min(100, y)) or 0, layer = tonumber(r.layer) or 0, zid = tonumber(r.zid),
        by = type(sender) == 'string' and sender:sub(1, 60) or nil, time = now }
    local rare = rares()[npc]
    if QuinteMapDB.settings.rareAlert ~= false then
        Q.Print('|cffffd100[Rare]|r ' .. Q.Safe(rare.name) .. (rare.elite and ' (élite)' or '') .. ' repéré par '
            .. Q.Safe(Q.DisplayName(sender)) .. ' · ' .. Q.Safe(rare.zone or '?') .. string.format(' (%.1f, %.1f)', rare.x, rare.y)
            .. ' · ' .. Q.LayerLabel(Q.LayerFor(rare)))
        if QuinteMapDB.settings.soundAlert and PlaySound then pcall(PlaySound, 8959) end
    end
    if Q.UI and Q.UI.Refresh then Q.UI.Refresh() end
end

--- Rares vus depuis moins de 30 min, les plus récents d'abord.
function Q.GetActiveRares()
    local list, now = {}, Q.Now()
    for npc, r in pairs(rares()) do
        if type(r) ~= 'table' or now - (r.time or 0) > RARE_TTL then rares()[npc] = nil else list[#list + 1] = r end
    end
    table.sort(list, function(a, b) return (a.time or 0) > (b.time or 0) end)
    return list
end

function Q.InitRares()
    local f = CreateFrame('Frame')
    for _, ev in ipairs({ 'PLAYER_TARGET_CHANGED', 'UPDATE_MOUSEOVER_UNIT', 'NAME_PLATE_UNIT_ADDED' }) do Q.Call(f.RegisterEvent, f, ev) end
    f:SetScript('OnEvent', function(_, event, unit)
        if event == 'PLAYER_TARGET_CHANGED' then unit = 'target' elseif event == 'UPDATE_MOUSEOVER_UNIT' then unit = 'mouseover' end
        if type(unit) ~= 'string' or isSecret(unit) then return end
        Q.Run('rare', Q.SpotRare, unit)
    end)
end
