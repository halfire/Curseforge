local _, Core = ...
-- Registre du compte WoW local, commun à tous les modules. Aucun identifiant Battle.net.
local C, listeners = {}, {}
Core.Characters = C
local loggedIn, updating = false, false
local function text(v)
    return not (issecretvalue and issecretvalue(v)) and type(v) == 'string' and #v > 0 and #v <= 100
        and not v:find('[%z\1-\31|]')
end
local function number(v, max)
    return not (issecretvalue and issecretvalue(v)) and type(v) == 'number' and v == v and v >= 0 and v <= max and v % 1 == 0
end
local function db()
    if not QuintessenceDB then return nil end
    if type(QuintessenceDB.characterProfile) ~= 'table' then QuintessenceDB.characterProfile = {own = {}, revision = 0} end
    local d = QuintessenceDB.characterProfile
    if type(d.own) ~= 'table' then d.own = {} end
    return d
end
local function id(key) return text(key) and Core.CanonicalKey(key) end
local function makeFamily(key)
    local h = 0
    for i = 1, #key do h = (h * 31 + key:byte(i)) % 2147483647 end
    return string.format('c:%x:%x:%x', Core.Now(), math.random(1, 2147483646), h)
end
local function choose(d)
    local manual = id(d.manual) and d.own[id(d.manual)]
    if manual and manual.level >= 60 then return manual.key end
    if d.manual then d.manual = nil end
    local best
    for _, c in pairs(d.own) do
        if not best or c.level >= 60 and best.level < 60
            or c.level >= 60 and best.level >= 60 and ((c.sixty or c.seen) < (best.sixty or best.seen)
                or (c.sixty or c.seen) == (best.sixty or best.seen) and (Core.SameName(c.key, d.main or '')
                    or not Core.SameName(best.key, d.main or '') and c.key < best.key))
            or c.level < 60 and best.level < 60 and (c.level > best.level
                or c.level == best.level and (Core.SameName(c.key, d.main or '')
                    or not Core.SameName(best.key, d.main or '') and c.key < best.key)) then best = c end
    end
    return best and best.key
end
local function changed(d, force)
    local main = choose(d)
    if main and (force or not d.main or not Core.SameName(main, d.main)) then
        d.main = main
        d.revision = math.max(Core.Now(), (tonumber(d.revision) or 0) + 1)
        if not updating then
            updating = true
            for _, fn in ipairs(listeners) do Core.Run('personnage principal', fn) end
            updating = false
        end
    end
end
function C.Remember(key, name, realm, level, at, sixty, quiet)
    local d = db()
    if not d or not text(key) or not text(name) or not text(realm) or not number(level, 1000) or level < 1
        or not Core.SameName(key, name .. '-' .. realm) or name == 'Unknown' or name == UNKNOWNOBJECT then return false end
    at = number(at, Core.Now() + 300) and at or Core.Now()
    local k, c = id(key), d.own[id(key)]
    if not c then
        local n = 0; for _ in pairs(d.own) do n = n + 1 end
        if n >= 128 then return false end
        c = {key = key, name = name, realm = realm, level = level, seen = at, observed = at}
        d.own[k] = c
    elseif level > c.level or at >= (c.observed or 0) then
        c.level, c.observed = math.max(c.level, level), math.max(c.observed or 0, at)
    end
    if level >= 60 then
        local reached = number(sixty, Core.Now() + 300) and sixty or at
        c.sixty = math.min(c.sixty or reached, reached)
    end
    if not text(d.family) then d.family = makeFamily(key) end
    if not quiet then changed(d); if C.RefreshSettings then C.RefreshSettings() end end
    return true
end
function C.Seed(records)
    local d = db()
    if not d or type(records) ~= 'table' then return end
    local rows = {}
    for key, c in pairs(records) do
        if type(c) == 'table' and c.source == 'self' and text(key) then rows[#rows + 1] = {key = key, c = c} end
    end
    table.sort(rows, function(a, b)
        local aa, bb = tonumber(a.c.updated) or 0, tonumber(b.c.updated) or 0
        if aa ~= bb then return aa < bb end
        return a.key < b.key
    end)
    for _, row in ipairs(rows) do
        local c, sixty = row.c
        local existing = d.own[id(row.key)]
        -- La date d'une fiche peut avancer pour un changement de principal sans nouveau relevé de niveau.
        local level = number(c.level, 1000) and math.max(c.level, existing and existing.level or 0) or c.level
        if type(c.pex) == 'table' and type(c.pex.levels) == 'table' then
            for _, level in ipairs(c.pex.levels) do
                if type(level) == 'table' and level[1] == 60 and number(level[2], Core.Now() + 300) then sixty = level[2]; break end
            end
        end
        C.Remember(row.key, c.name, c.realm, level, c.updated, sixty, true)
    end
    changed(d)
end
function C.Main()
    local d = db()
    return d and d.main
end
function C.Metadata(key)
    local d, k = db(), id(key or Core.Key())
    if d and d.own[k] and d.main then return {family = d.family, main = d.main, mainUpdated = d.revision} end
end
function C.IsMain(key)
    key = key or Core.Key()
    local m = C.Metadata(key)
    return m and Core.SameName(key, m.main) or false
end
function C.Own()
    local d, out = db(), {}
    if not d then return out end
    for _, c in pairs(d.own) do
        out[#out + 1] = {key = c.key, name = c.name, realm = c.realm, level = c.level,
            main = d.main and Core.SameName(c.key, d.main) or false, sixty = c.sixty}
    end
    table.sort(out, function(a, b)
        if a.main ~= b.main then return a.main end
        if a.level ~= b.level then return a.level > b.level end
        return a.key < b.key
    end)
    return out
end
function C.Select(key)
    local d, k = db(), id(key)
    local c = d and k and d.own[k]
    if not c or c.level < 60 then return false, 'Choisis un de tes personnages de niveau 60.' end
    d.manual = c.key; changed(d, true)
    if C.RefreshSettings then C.RefreshSettings() end
    return true, 'Personnage principal : ' .. Core.DisplayName(c.key) .. '.'
end
function C.Automatic()
    local d = db(); if not d then return end
    d.manual = nil; changed(d, true)
    if C.RefreshSettings then C.RefreshSettings() end
end
function C.OnChanged(fn) listeners[#listeners + 1] = fn end
function C.Capture(level)
    if not loggedIn or not Core.ready then return end
    local ok, actual = pcall(UnitLevel or function() end, 'player')
    level = number(level, 1000) and level or (ok and actual)
    if not number(level, 1000) then return end
    local name, realm = Core.PlayerName(), Core.Realm()
    C.Remember(Core.Key(), name, realm, level, Core.Now())
end
local frame = CreateFrame('Frame')
for _, e in ipairs({'PLAYER_LOGIN', 'PLAYER_LEVEL_UP'}) do Core.Call(frame.RegisterEvent, frame, e) end
frame:SetScript('OnEvent', function(_, event, level)
    if event == 'PLAYER_LOGIN' then loggedIn = true end
    Core.Run('identité du compte', C.Capture, event == 'PLAYER_LEVEL_UP' and level or nil)
end)
