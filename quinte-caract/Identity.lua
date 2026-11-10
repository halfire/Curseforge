local _, Q = ...
local Core = Quintessence
function Q.IdentityChanged()
    if not Q.ready or not Core.Characters then return end
    local changed = false
    for key, c in pairs(QuinteCaractDB.characters) do
        if c.source == 'self' then
            local m = Core.Characters.Metadata(key)
            if m and (c.family ~= m.family or c.main ~= m.main or c.mainUpdated ~= m.mainUpdated) then
                local copy = {}; for k, v in pairs(c) do copy[k] = v end
                copy.family, copy.main, copy.mainUpdated = m.family, m.main, m.mainUpdated
                copy.updated = math.max(Q.Now(), (c.updated or 0) + 1)
                QuinteCaractDB.characters[key] = copy; changed = true
            end
        end
    end
    if changed then Q.Changed(true) end
end
function Q.IdentityInit()
    if not Core.Characters then return end
    Core.Characters.OnChanged(Q.IdentityChanged)
    Core.Characters.Seed(QuinteCaractDB.characters)
    Q.IdentityChanged()
end
function Q.IdentityMetadata(record)
    if not Core.Characters then return end
    local sixty
    if record.pex and record.pex.levels then
        for _, row in ipairs(record.pex.levels) do if row[1] == 60 then sixty = row[2]; break end end
    end
    Core.Characters.Remember(Q.Key(), record.name, record.realm, record.level, Q.Now(), sixty)
    local m = Core.Characters.Metadata(Q.Key())
    if m then record.family, record.main, record.mainUpdated = m.family, m.main, m.mainUpdated end
end
-- Une ancienne version reste affichée comme principal, sans lien de compte inventé.
function Q.Families()
    local out = {}
    for _, c in pairs(QuinteCaractDB.characters) do
        if c.family and c.main and c.mainUpdated then
            local old = out[c.family]
            if not old or c.mainUpdated > old.at or c.mainUpdated == old.at and c.main < old.main then
                out[c.family] = {main = c.main, at = c.mainUpdated}
            end
        end
    end
    return out
end
function Q.MainOf(key, record, families)
    local own = record.source == 'self' and Core.Characters and Core.Characters.Metadata(key)
    if own then return own.main end
    local family = record.family and (families or Q.Families())[record.family]
    return family and family.main or record.main or key
end
