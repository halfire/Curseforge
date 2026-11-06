local _, Q = ...
local Sync = LibStub('LibQuinteSync-1.0')
local MAX_PROFESSIONS,MAX_CHARACTERS = 24,1000
local function integer(n,lo,hi) return type(n)=='number' and n==n and n%1==0 and n>=lo and n<=hi end
local function string100(s) return type(s)=='string' and #s>0 and #s<=100 and not s:find('[%z\1-\31]') end
local function bounded(t,maximum)
    if type(t)~='table' then return false end
    local n=0;for _ in pairs(t) do n=n+1;if n>maximum then return false end end;return true
end
local function timestamp(t,now) return integer(t,0,now+300) end
-- Personnage pas connecté depuis un mois : son craft est retiré, sauf au niveau maximum (60 sur Forever). La date
-- d'un enregistrement avance au moins une fois par semaine tant que le joueur se connecte (Q.Identity). Les fiches
-- retirées sont notées dans db.purged (clé normalisée → date) pour ne pas être redemandées à un autre membre.
local INACTIVE,MAX_LEVEL,PURGE_MEMORY=30*86400,60,60*86400
local function inactive(c,now)
    if now>=1793808000 and (tonumber(c.updated) or 0)<1793808000 then return true end -- relevé de la bêta (RESET_AT)
    return (tonumber(c.level) or 0)<MAX_LEVEL and (tonumber(c.updated) or 0)<now-INACTIVE
end
local function purgedAt(db,key) return type(db.purged)=='table' and db.purged[Sync.CanonicalKey(key)] or nil end
Q.INACTIVE,Q.MAX_LEVEL=INACTIVE,MAX_LEVEL
-- Sortie de WoW Forever (4 novembre 2026) : tout relevé d'avant le 04/11/2026 16:00 UTC (bêta) est effacé une fois
-- (Q.ResetBeforeLaunch, appelé à l'initialisation) et refusé ensuite par la synchro. Le site fait de même (v16).
local RESET_AT=1793808000
Q.RESET_AT=RESET_AT
-- (seulement une fois l'heure passée : un client à l'heure d'avant n'efface rien, il le fera au chargement suivant)
local function launched(now) return (now or Q.Now())>=RESET_AT end
function Q.ResetBeforeLaunch(db)
    if (tonumber(db.resetAt) or 0)>=RESET_AT or not launched() then return 0 end
    local n=0
    for key,c in pairs(db.characters) do
        if type(c)~='table' or (tonumber(c.updated) or 0)<RESET_AT then db.characters[key]=nil;n=n+1 end
    end
    db.purged,db.resetAt=nil,RESET_AT
    return n
end
function Q.SpellName(id)
    if not id then return nil end
    local ok,name=Q.Call((C_Spell or {}).GetSpellName or GetSpellInfo,id)
    if ok and type(name)=='string' then return name end
end
local function identity(record,recordKey,now)
    if type(record)~='table' or not string100(recordKey) or not string100(record.name) or not string100(record.realm) then return nil end
    if Sync.CanonicalKey(record.name..'-'..record.realm:gsub('%s',''))~=Sync.CanonicalKey(recordKey) then return nil end
    if record.class~=nil and (not string100(record.class) or not record.class:match('^[A-Z_]+$')) then return nil end
    if record.level~=nil and not integer(record.level,1,1000) then return nil end
    if not timestamp(record.updated,now) then return nil end
    return {name=record.name,realm=record.realm,class=record.class,level=record.level,updated=record.updated}
end
local function profession(value,now)
    if type(value)~='table' or not timestamp(value.updated,now) or not bounded(value.recipes,1000) then return nil end
    if value.skill~=nil and not integer(value.skill,0,10000) then return nil end
    if value.maxSkill~=nil and not integer(value.maxSkill,0,10000) then return nil end
    if value.skill and value.maxSkill and value.skill>value.maxSkill then return nil end
    local result={skill=value.skill,maxSkill=value.maxSkill,updated=value.updated,recipes={}}
    local n=0
    for k,row in pairs(value.recipes) do
        n=n+1;if not integer(k,1,#value.recipes) or type(row)~='table' then return nil end
        if row.spell~=nil and not integer(row.spell,1,1e9) then return nil end
        if row.item~=nil and not integer(row.item,1,1e9) then return nil end
        if row.category~=nil and not string100(row.category) then return nil end
        if row.reagents~=nil then
            if not bounded(row.reagents,12) then return nil end
            local m=0
            for i,reagent in pairs(row.reagents) do
                m=m+1
                if not integer(i,1,#row.reagents) or type(reagent)~='table' or not integer(reagent.item,1,1e9)
                    or not integer(reagent.count,1,10000) then return nil end
            end
            if m~=#row.reagents then return nil end
        end
    end
    if n~=#value.recipes then return nil end
    for _,row in ipairs(value.recipes) do
        local reagents
        if row.reagents and #row.reagents>0 then
            reagents={};for i,reagent in ipairs(row.reagents) do reagents[i]={item=reagent.item,count=reagent.count} end
        end
        result.recipes[#result.recipes+1]={spell=row.spell,item=row.item,name=Q.SpellName(row.spell),category=row.category,reagents=reagents}
    end
    return result
end
local function cleanup(db,roster,now)
    local changed=false
    local mine=Q.Key()
    for key,c in pairs(db.characters) do
        if type(c)~='table' then
            db.characters[key]=nil;changed=true
        elseif key~=mine and inactive(c,now) then
            -- (aussi nos propres autres personnages : le perso connecté n'est jamais retiré)
            db.purged=db.purged or {}
            db.purged[Sync.CanonicalKey(key)]=tonumber(c.updated) or 0
            db.characters[key]=nil;changed=true
        elseif c.source~='self' and (not roster[Sync.CanonicalKey(key)] or not timestamp(c.updated or 0,now) or c.updated<now-60*86400) then
            db.characters[key]=nil;changed=true
        end
    end
    for key,at in pairs(db.purged or {}) do
        if type(at)~='number' or at<now-PURGE_MEMORY then db.purged[key]=nil end
    end
    if changed then Q.Changed(false) end
end
local function existing(db,remoteKey)
    local canonical=Sync.CanonicalKey(remoteKey)
    for storedKey,c in pairs(db.characters) do
        if Sync.CanonicalKey(storedKey)==canonical then return c,storedKey end
    end
end
local function canRelay(c)
    return type(c)=='table' and type(c.professions)=='table' and (c.source=='self' or c.source=='sync')
end
local function manifest(db)
    local batches,current={},{}
    for recordKey,c in pairs(db.characters) do if canRelay(c) and c.updated then
        local versions={}
        local n=0
        for name,p in pairs(c.professions) do
            if string100(name) and bounded(p.recipes,1000) and p.updated then versions[name]=p.updated;n=n+1 end
        end
        if n<=MAX_PROFESSIONS then
            current[#current+1]={key=recordKey,updated=c.updated,professions=versions}
            if #current==20 then batches[#batches+1]=current;current={} end
        end
    end end
    if #current>0 then batches[#batches+1]=current end
    return batches
end
local function need(db,remote)
    if not bounded(remote,20) then return {} end
    local requests,now={},Q.Now()
    for k,m in pairs(remote) do
        if not integer(k,1,#remote) or type(m)~='table' or not string100(m.key) or not timestamp(m.updated,now) or not bounded(m.professions,MAX_PROFESSIONS) then return {} end
        for name,updated in pairs(m.professions) do if not string100(name) or not timestamp(updated,now) then return {} end end
    end
    for _,m in ipairs(remote) do
        local c=existing(db,m.key)
        local gone=purgedAt(db,m.key)
        if m.updated>=now-60*86400 and (m.updated>=RESET_AT or not launched(now)) and Q.sync:Member(m.key) and (not c or c.source~='self') and not (gone and m.updated<=gone) then
            local names={}
            for name,updated in pairs(m.professions) do
                local p=c and c.professions[name]
                if not p or updated>p.updated then names[#names+1]=name end
            end
            if not c or m.updated>c.updated or #names>0 then requests[#requests+1]={key=m.key,professions=names,identity=not c or m.updated>c.updated} end
        end
    end
    return requests
end
local function export(db,request)
    if not string100(request.key) or not bounded(request.professions,MAX_PROFESSIONS) then return {} end
    local c=db.characters[request.key];if not canRelay(c) then return {} end
    local base=identity(c,request.key,Q.Now());if not base then return {} end
    -- Chaque partie de métier porte déjà l'identité : la partie « identité seule » n'est envoyée que s'il n'y a aucun
    -- métier à joindre (un message D de moins par demande ; les anciennes versions fusionnent l'identité de chaque partie).
    local parts={}
    for _,name in ipairs(request.professions) do
        if not string100(name) then return {} end
        local p=c.professions[name]
        if p and bounded(p.recipes,1000) then
            local recipes={}
            for _,r in ipairs(p.recipes) do
                local reagents
                if type(r.reagents)=='table' and #r.reagents>0 then
                    reagents={};for i,reagent in ipairs(r.reagents) do if i>12 then break end;reagents[i]={item=reagent.item,count=reagent.count} end
                end
                recipes[#recipes+1]={spell=r.spell,item=r.item,category=r.category,reagents=reagents}
            end
            parts[#parts+1]={key=request.key,character=base,professions={[name]={updated=p.updated,skill=p.skill,maxSkill=p.maxSkill,recipes=recipes}}}
        end
    end
    if #parts==0 then parts[1]={key=request.key,character=base,professions={}} end
    return parts
end
local function merge(db,part,sender,now,request)
    if type(part)~='table' or part.key~=request.key or not Q.sync:Member(part.key) or not bounded(part.professions,MAX_PROFESSIONS) then return false end
    local c,storedKey=existing(db,part.key)
    if c and c.source=='self' then return false end
    if not c and not bounded(db.characters,MAX_CHARACTERS-1) then return false end
    local clean=identity(part.character,part.key,now);if not clean then return false end
    -- Retiré pour inactivité : seulement une version plus récente (le joueur s'est reconnecté), et pas déjà inactive
    local gone=purgedAt(db,part.key)
    if not c and ((gone and clean.updated<=gone) or inactive(clean,now)) then return false end
    local allowed={};for _,name in ipairs(request.professions or {}) do allowed[name]=true end
    local cleaned={}
    for name,p in pairs(part.professions) do
        if not string100(name) or not allowed[name] then return false end
        local validated=profession(p,now);if not validated then return false end
        if validated.updated>clean.updated then return false end
        cleaned[name]=validated
    end
    local changed=false
    if not c then
        c={source='sync',professions={}};db.characters[storedKey or part.key]=c;changed=true
    end
    if not c.updated or clean.updated>c.updated then
        c.name,c.realm,c.class,c.level=clean.name,clean.realm,clean.class,clean.level
        c.updated=clean.updated;changed=true
    end
    for name,p in pairs(cleaned) do
        local old=c.professions[name]
        if not old or p.updated>old.updated then c.professions[name]=p;changed=true end
    end
    if changed then c.source='sync';c.syncedFrom=sender;c.syncedAt=now end
    return changed
end
function Q.SyncInit()
    -- La synchro de guilde est gérée par le conteneur Quintessence (canal unique pour tous les modules)
    Q.sync=Quintessence:RegisterSync('craft',QuinteCraftDB,{Manifest=manifest,Need=need,Export=export,Merge=merge,
        Cleanup=cleanup,Changed=Q.Changed})
end
Q.SyncAdapter={Manifest=manifest,Need=need,Export=export,Merge=merge,Cleanup=cleanup,ValidateProfession=profession}
