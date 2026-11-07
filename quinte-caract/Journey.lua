local _, Q = ...
--[[
  Journey.lua : journal de pex de chaque joueur, pour de futures statistiques de guilde sur le site.

  Rien d'instantané ni de lourd :
  - niveau : noté une fois, à l'événement du jeu (PLAYER_LEVEL_UP), avec la date et la zone ;
  - zones : un relevé de la zone toutes les 5 minutes, sans rien compter si le joueur est absent (AFK) ;
  - arrivée dans la guilde : première fois que l'addon voit le joueur dans la guilde.
  Chacun ne note que lui-même, personne n'observe les autres. Le journal voyage avec la fiche (champ `pex`), par la synchro
  habituelle : pas de nouveau message, et il n'est copié dans la fiche qu'au passage d'un niveau, une fois par heure et à la
  déconnexion. Le site le lit pour la page /statistiques (docs/STATS_PEX.md du dépôt du site).

  QuinteCaractDB.pex[clé du perso] = {
    since = arrivée vue dans la guilde, start = niveau au premier relevé, min = minutes de jeu comptées,
    levels = { { niveau, date, carte, minutes comptées à ce moment }, ... }, zones = { [carte] = minutes },
  }
  `carte` : numéro du jeu (C_Map), le même quelle que soit la langue du client.
]]
local TICK, SNAPSHOT = 300, 3600
local MAX_LEVELS, MAX_ZONES, MAX_MINUTES = 80, 64, 5000000

local function secret(v) return type(issecretvalue) == 'function' and issecretvalue(v) end
local function journal()
    if not QuinteCaractDB then return nil end
    if type(QuinteCaractDB.pex) ~= 'table' then QuinteCaractDB.pex = {} end
    local key = Q.Key()
    local j = QuinteCaractDB.pex[key]
    if type(j) ~= 'table' then
        j = { min = 0, levels = {}, zones = {} }
        QuinteCaractDB.pex[key] = j
    end
    return j
end
Q.PexJournal = journal
local function currentMap()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, map = pcall(C_Map.GetBestMapForUnit, 'player')
    if ok and type(map) == 'number' and not secret(map) then return map end
    return nil
end
local function currentLevel()
    local ok, level = pcall(UnitLevel, 'player')
    if ok and type(level) == 'number' and not secret(level) then return level end
    return nil
end
local function inGuild()
    if not GetGuildInfo then return false end
    local ok, name = pcall(GetGuildInfo, 'player')
    return ok and type(name) == 'string' and not secret(name) and name == Quintessence.GUILD
end
--- Note un niveau, une seule fois par niveau (level : celui donné par l'événement du jeu).
function Q.PexLevel(level, at)
    local j = journal()
    level = level or currentLevel()
    if not (j and type(level) == 'number' and level >= 1) then return false end
    for _, row in ipairs(j.levels) do if row[1] == level then return false end end
    if #j.levels >= MAX_LEVELS then return false end
    j.levels[#j.levels + 1] = { level, at or Q.Now(), currentMap() or 0, j.min }
    return true
end
--- Relevé toutes les 5 minutes : la zone du moment reçoit ces minutes, sauf si le joueur est absent.
function Q.PexTick(at)
    local j = journal()
    if not j then return false end
    at = at or Q.Now()
    if not j.since and inGuild() then j.since = at end
    if not j.start then
        j.start = currentLevel()
        if j.start then Q.PexLevel(j.start, at) end
    end
    if UnitIsAFK then
        local ok, afk = pcall(UnitIsAFK, 'player')
        if ok and afk and not secret(afk) then return false end
    end
    local map, minutes = currentMap(), TICK / 60
    j.min = math.min(j.min + minutes, MAX_MINUTES)
    if map then
        if j.zones[map] or Q.Count(j.zones) < MAX_ZONES then j.zones[map] = (j.zones[map] or 0) + minutes end
    end
    return true
end
function Q.Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
--- Copie que porte la fiche : figée entre deux copies, pour ne pas diffuser une fiche à chaque relevé.
function Q.PexSnapshot()
    local j = journal()
    if not j then return nil end
    local copy = { since = j.since, start = j.start, min = j.min, levels = {}, zones = {} }
    for i, row in ipairs(j.levels) do copy.levels[i] = { row[1], row[2], row[3], row[4] } end
    for map, minutes in pairs(j.zones) do copy.zones[map] = minutes end
    Q.pexCopy = copy
    return copy
end
--- Copie à mettre dans la fiche relevée (la dernière figée, ou l'ancienne de la fiche après un rechargement).
function Q.PexForRecord()
    if Q.pexCopy then return Q.pexCopy end
    local old = QuinteCaractDB and QuinteCaractDB.characters[Q.Key()]
    if old and type(old.pex) == 'table' then Q.pexCopy = old.pex; return old.pex end
    return Q.PexSnapshot()
end
local function loop()
    Q.Run('journal de pex', Q.PexTick)
    C_Timer.After(TICK, loop)
end
local function hourly()
    Q.Run('journal de pex', function() Q.PexSnapshot(); Q.Schedule() end)
    C_Timer.After(SNAPSHOT, hourly)
end
local frame = CreateFrame('Frame')
pcall(frame.RegisterEvent, frame, 'PLAYER_LOGIN')
pcall(frame.RegisterEvent, frame, 'PLAYER_LEVEL_UP')
pcall(frame.RegisterEvent, frame, 'PLAYER_LOGOUT')
frame:SetScript('OnEvent', function(_, event, arg)
    Q.Run('journal de pex', function()
        if not Q.ready or Q.disabled then return end
        if event == 'PLAYER_LEVEL_UP' then
            Q.PexLevel(tonumber(arg))
            Q.PexSnapshot()
        elseif event == 'PLAYER_LOGOUT' then
            Q.PexSnapshot()
        elseif not Q.pexStarted then
            Q.pexStarted = true
            if C_Timer and C_Timer.After then
                C_Timer.After(30, loop)      -- la guilde est connue quelques secondes après la connexion
                C_Timer.After(SNAPSHOT, hourly)
            end
        end
    end)
end)
