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
    if type(value)=='table' and value.b~=nil then
        local recipes=Q.ExpandProfession and Q.ExpandProfession(value)
        if not recipes then Q.catalogueRefused=(Q.catalogueRefused or 0)+1;return nil end
        value={updated=value.updated,skill=value.skill,maxSkill=value.maxSkill,recipes=recipes}
    end
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
-- Index clé normalisée → clé rangée (T137) au lieu de parcourir toutes les fiches pour chaque entrée de manifeste.
-- strict (fusion) : une clé absente relance toujours la recherche complète ; sinon reconstruit au plus toutes les 2 s.
local index,indexedFor,indexedAt={},nil,-100
local function existing(db,remoteKey,strict)
    if db.characters[remoteKey] then return db.characters[remoteKey],remoteKey end
    local canonical=Sync.CanonicalKey(remoteKey)
    local stored=indexedFor==db.characters and index[canonical]
    if stored and db.characters[stored] then return db.characters[stored],stored end
    local clock=GetTime and GetTime() or 0
    if not strict and indexedFor==db.characters and clock-indexedAt<2 then return nil end
    index,indexedFor,indexedAt={},db.characters,clock
    for k in pairs(db.characters) do index[Sync.CanonicalKey(k)]=k end
    stored=index[canonical]
    if stored then return db.characters[stored],stored end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Métiers en cases cochées (T137, protocole 3) : chaque client a le même catalogue (Recipes.lua, ordre fixe, et
-- RecipeReagents.lua tiré de Wowhead Forever). Un métier voyage comme une suite de bits « recette connue », la catégorie
-- en jeu de chaque recette (un caractère), et seulement ce qui diffère du catalogue : composants ou objet différents,
-- recettes hors catalogue (en entier, comme avant). Un métier de 150 recettes : 13 messages avant, 1 à 2 maintenant.
-- L'empreinte H du catalogue de la ligne doit être la même des deux côtés (même pack), sinon le métier est refusé.
-- La fiche rangée garde le format complet (recettes avec composants) : le site lit la même chose qu'avant.
-- ---------------------------------------------------------------------------------------------------------------------
local catalogue={}
local function line(id)
    if catalogue[id]~=nil then return catalogue[id] or nil end
    local data=Q.ALL_RECIPES and Q.ALL_RECIPES[id]
    if type(data)~='table' or type(data.recipes)~='table' then catalogue[id]=false;return nil end
    local parts,pos={},{}
    for i,row in ipairs(data.recipes) do
        local reagents=Q.RECIPE_REAGENTS and Q.RECIPE_REAGENTS[row[1]]
        parts[#parts+1]=row[1]..'/'..(row[2] or 0)..'/'..(reagents and table.concat(reagents,',') or '')
        pos[row[1]]=i
    end
    local entry={id=id,rows=data.recipes,pos=pos,hash=Sync.Fingerprint(table.concat(parts,';'))}
    catalogue[id]=entry
    return entry
end
local lineOf
local function findLine(spell)
    if not lineOf then
        lineOf={}
        for id in pairs(Q.ALL_RECIPES or {}) do
            local l=line(id)
            for spellId in pairs(l and l.pos or {}) do lineOf[spellId]=lineOf[spellId] or id end
        end
    end
    return lineOf[spell]
end
local function catalogueReagents(spell)
    local flat=Q.RECIPE_REAGENTS and Q.RECIPE_REAGENTS[spell]
    if type(flat)~='table' then return nil end
    local out={}
    for i=1,#flat-1,2 do out[#out+1]={item=flat[i],count=flat[i+1]} end
    return #out>0 and out or nil
end
local function sameReagents(a,b)
    if not a or not b or #a~=#b then return false end
    for i,x in ipairs(a) do if x.item~=b[i].item or x.count~=b[i].count then return false end end
    return true
end
local function flatReagents(list)
    local out={}
    for i,r in ipairs(list or {}) do if i>12 then break end;out[#out+1]=r.item;out[#out+1]=r.count end
    return out
end
-- recipes (liste complète) → métier compact, ou nil si rien n'est dans le catalogue
local function encode(recipes)
    local votes,best={},nil
    for _,r in ipairs(recipes) do
        local id=r.spell and findLine(r.spell)
        if id then votes[id]=(votes[id] or 0)+1;if not best or votes[id]>votes[best] then best=id end end
    end
    local l=best and line(best)
    if not l then return nil end
    local bits,cats,catIndex,byPos={},{},{},{}
    local extras,reagents,items
    for _,r in ipairs(recipes) do
        local at=r.spell and l.pos[r.spell]
        if at then byPos[at]=r else
            extras=extras or {}
            extras[#extras+1]={spell=r.spell,item=r.item,category=r.category,reagents=r.reagents}
        end
    end
    local ci={}
    for at=1,#l.rows,8 do
        local byte=0
        for k=0,7 do if byPos[at+k] then byte=byte+2^k end end
        bits[#bits+1]=string.char(byte)
    end
    for at=1,#l.rows do
        local r=byPos[at]
        if r then
            local cat=r.category or ''
            if not catIndex[cat] then
                if #cats>=90 then return nil end
                cats[#cats+1]=cat;catIndex[cat]=#cats
            end
            ci[#ci+1]=string.char(32+catIndex[cat])
            local row=l.rows[at]
            if r.reagents and #r.reagents>0 and not sameReagents(r.reagents,catalogueReagents(row[1])) then
                reagents=reagents or {};reagents[row[1]]=flatReagents(r.reagents)
            end
            if r.item and r.item~=(row[2]~=0 and row[2] or nil) then items=items or {};items[row[1]]=r.item end
        end
    end
    return {L=l.id,H=l.hash,b=table.concat(bits),c=cats,ci=table.concat(ci),r=reagents,it=items,x=extras}
end
-- métier compact → liste complète des recettes, ou nil (catalogue différent, données incohérentes)
local function decode(value)
    local l=type(value.L)=='number' and line(value.L)
    if not l or value.H~=l.hash or type(value.b)~='string' or #value.b~=math.ceil(#l.rows/8) or type(value.ci)~='string'
        or type(value.c)~='table' or #value.c>90 then return nil end
    for _,cat in ipairs(value.c) do if type(cat)~='string' or #cat>100 then return nil end end
    local recipes,n={},0
    for at=1,#l.rows do
        local byte=value.b:byte(math.floor((at-1)/8)+1)
        if math.floor(byte/2^((at-1)%8))%2==1 then
            n=n+1
            local row=l.rows[at]
            local cat=value.c[(value.ci:byte(n) or 0)-32]
            if cat==nil then return nil end
            local override=type(value.r)=='table' and value.r[row[1]]
            local reagents
            if type(override)=='table' then
                if #override>24 then return nil end
                reagents={}
                for i=1,#override-1,2 do reagents[#reagents+1]={item=override[i],count=override[i+1]} end
            else reagents=catalogueReagents(row[1]) end
            local item=type(value.it)=='table' and value.it[row[1]] or (row[2]~=0 and row[2] or nil)
            recipes[#recipes+1]={spell=row[1],item=item,category=cat~='' and cat or nil,reagents=reagents}
        end
    end
    if n~=#value.ci then return nil end
    if value.x~=nil then
        if type(value.x)~='table' or #value.x>1000 then return nil end
        for _,r in ipairs(value.x) do recipes[#recipes+1]=r end
    end
    -- même ordre que chez l'artisan (Professions.lua : par sort, puis objet)
    table.sort(recipes,function(a,b)
        if (tonumber(a.spell) or 0)~=(tonumber(b.spell) or 0) then return (tonumber(a.spell) or 0)<(tonumber(b.spell) or 0) end
        return (tonumber(a.item) or 0)<(tonumber(b.item) or 0)
    end)
    return recipes
end
Q.CompactProfession,Q.ExpandProfession=encode,decode
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
            local out={updated=p.updated,skill=p.skill,maxSkill=p.maxSkill}
            local compact=encode(recipes)
            if compact then for k,v in pairs(compact) do out[k]=v end else out.recipes=recipes end
            parts[#parts+1]={key=request.key,character=base,professions={[name]=out}}
        end
    end
    if #parts==0 then parts[1]={key=request.key,character=base,professions={}} end
    return parts
end
local function merge(db,part,sender,now,request)
    if type(part)~='table' or part.key~=request.key or not Q.sync:Member(part.key) or not bounded(part.professions,MAX_PROFESSIONS) then return false end
    local c,storedKey=existing(db,part.key,true)
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
        if indexedFor==db.characters then index[Sync.CanonicalKey(part.key)]=part.key end
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
