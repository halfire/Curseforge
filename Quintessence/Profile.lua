local _, Core = ...
-- Intentions déclarées : séparées des talents réellement relevés et du principal du compte.
local P = { revision = 0, LAST_STEP = 11 }  -- dernière étape du parcours (la carte de membre)
Core.Profile = P
P.ACTIVITIES = {{'pex','Pex','X'}, {'dungeon','Donjons','D'}, {'raid','Raids','R'}, {'pvp','PvP','P'},
    {'craft','Artisanat','A'}, {'help','Entraide','E'}, {'social','Vie de guilde','S'}}
P.ROLES = {{'HEAL','Soins','H'}, {'TANK','Tank','T'}, {'DPS','Dégâts','D'}}
P.DAYS = {'Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi','Dimanche'}
P.RAIDS = {{'none','Pas maintenant'}, {'discover','Je veux découvrir'}, {'casual','Occasionnel'}, {'regular','Régulier'}}
-- Noms de branches partagés avec le recensement ; ours/chat explicitement distingués.
-- Amélioration tank n'est pas proposée : rôle non confirmé sur Forever.
P.SPECS = {
 WARRIOR={{'ARMS','Armes','DPS','Armes'},{'FURY','Fureur','DPS','Fureur'},{'PROT','Protection','TANK','Protection'}},
 PALADIN={{'HOLY','Sacré','HEAL','Sacré'},{'PROT','Protection','TANK','Protection'},{'RET','Vindicte','DPS','Vindicte'}},
 HUNTER={{'BM','Maîtrise des bêtes','DPS','Bêtes'},{'MM','Précision','DPS','Précision'},{'SURV','Survie','DPS','Survie'}},
 ROGUE={{'ASSA','Assassinat','DPS','Assassinat'},{'COMBAT','Combat','DPS','Combat'},{'SUB','Finesse','DPS','Finesse'}},
 PRIEST={{'DISC','Discipline','HEAL','Discipline'},{'HOLY','Sacré','HEAL','Sacré'},{'SHADOW','Ombre','DPS','Ombre'}},
 SHAMAN={{'ELEM','Élémentaire','DPS','Élémentaire'},{'ENH','Amélioration','DPS','Amélioration'},{'RESTO','Restauration','HEAL','Restauration'}},
 MAGE={{'ARCANE','Arcanes','DPS','Arcanes'},{'FIRE','Feu','DPS','Feu'},{'FROST','Givre','DPS','Givre'}},
 WARLOCK={{'AFFLI','Affliction','DPS','Affliction'},{'DEMO','Démonologie','DPS','Démonologie'},{'DESTRO','Destruction','DPS','Destruction'}},
 DRUID={{'BALANCE','Équilibre','DPS','Équilibre'},{'BEAR','Combat farouche (ours)','TANK','Ours'},{'CAT','Combat farouche (chat)','DPS','Chat'},{'RESTO','Restauration','HEAL','Restauration'}},
}
local function secret(v) return issecretvalue and issecretvalue(v) end
local function text(v, max) return not secret(v) and type(v)=='string' and #v<=max and not v:find('[%z\1-\31|]') end
local function num(v, max) return not secret(v) and type(v)=='number' and v==v and v>=0 and v<=max and v%1==0 end
local function copy(t) local out={}; for k,v in pairs(t or {}) do out[k]=type(v)=='table' and copy(v) or v end; return out end
P.Copy = copy
local function db()
 if type(QuintessenceDB.profiles)~='table' then QuintessenceDB.profiles={} end
 if type(QuintessenceDB.profileDrafts)~='table' then QuintessenceDB.profileDrafts={} end
 return QuintessenceDB.profiles, QuintessenceDB.profileDrafts
end
local function mine() return Core.CanonicalKey(Core.Key()) end
local function own(key)
 if key==mine() then return true end
 local d=QuintessenceDB.characterProfile
 return d and d.own and d.own[key]~=nil
end
function P.Class()
 local ok, _, class=Core.Call(UnitClass,'player')
 return ok and not secret(class) and P.SPECS[class] and class or nil
end
function P.Spec(class,id)
 if not text(class,20) or not text(id,20) then return nil end
 for _,s in ipairs(P.SPECS[class] or {}) do if s[1]==id then return s end end
end
local function has(rows,id) for _,r in ipairs(rows) do if r[1]==id then return true end end end
local function flags(input, rows)
 if type(input)~='table' then return nil end
 local out={}
 for _,r in ipairs(rows) do local v=input[r[1]]; if secret(v) or v~=nil and type(v)~='boolean' then return nil end; if v then out[r[1]]=true end end
 return out
end
function P.Validate(v)
 if type(v)~='table' or not text(v.name,100) or v.name=='' or not text(v.class,20) or not P.SPECS[v.class]
   or not num(v.updated,Core.Now()+300) or not has(P.RAIDS,v.raid) then return nil end
 local a,r=flags(v.activities,P.ACTIVITIES),flags(v.roles,P.ROLES)
 if not a or not r or not text(v.favorite,20) or not a[v.favorite] or not P.Spec(v.class,v.primary)
   or v.secondary~=nil and (not P.Spec(v.class,v.secondary) or v.secondary==v.primary) then return nil end
 if type(v.days)~='table' or not text(v.start,5) or not text(v.finish,5) then return nil end
 local function hour(s) local h,m=s:match('^(%d%d):(%d%d)$'); return s=='' or h and tonumber(h)<24 and tonumber(m)<60 end
 if not hour(v.start) or not hour(v.finish) then return nil end
 local days={}; for i=1,7 do if secret(v.days[i]) or v.days[i]~=nil and type(v.days[i])~='boolean' then return nil end; if v.days[i] then days[i]=true end end
 if type(v.orders)~='boolean' or type(v.priority)~='boolean' then return nil end
 return {name=v.name,class=v.class,updated=v.updated,activities=a,favorite=v.favorite,roles=r,primary=v.primary,secondary=v.secondary,
   raid=v.raid,days=days,start=v.start,finish=v.finish,orders=v.orders,priority=v.orders and v.priority or false}
end
function P.Get(name)
 local records=db(); local v=records[Core.CanonicalKey(name or Core.Key())]
 return v and copy(v) or nil
end
function P.Draft()
 local records,drafts=db(); local key=mine()
 if type(drafts[key])~='table' then
  drafts[key]=records[key] and copy(records[key]) or {activities={},roles={},days={},raid='none',start='',finish='',orders=true,priority=false}
  drafts[key].step=records[key] and P.LAST_STEP or 1
  local opts=type(QuintessenceDB.profileOptions)=='table' and QuintessenceDB.profileOptions[key]
  drafts[key].notice=not opts or opts.notice~=false; drafts[key].sound=opts and opts.sound==true or false
 end
 return drafts[key]
end
function P.Inherit()
 local main=Core.Characters and Core.Characters.Main(); local v=main and P.Get(main)
 if not v or Core.SameName(main,Core.Key()) then return false end
 local d=P.Draft()
 for _,k in ipairs({'activities','favorite','raid','days','start','finish','orders','priority'}) do d[k]=type(v[k])=='table' and copy(v[k]) or v[k] end
 return true
end
function P.Options()
 -- Les brouillons ne prennent effet qu'à l'enregistrement.
 local prefs=QuintessenceDB.profileOptions; prefs=type(prefs)=='table' and prefs[mine()] or nil
 return prefs or {notice=true,sound=false}
end
function P.Changed()
 P.revision=P.revision+1
 if P.Refresh then P.Refresh() end
 if Core.OnProfileChanged then Core.Run('préférences artisan',Core.OnProfileChanged) end
end
function P.Save()
 if Core.GuildStatus()~='ok' then return false,'Profil réservé aux membres de Quintessence.' end
 local d=P.Draft(); local raw=copy(d); raw.name=Core.Key(); raw.class=P.Class()
 -- Horaires retirés de l'accueil (T176) : champs gardés vides pour rester lisibles par les anciens clients.
 raw.start,raw.finish='',''
 local old=P.Get(); raw.updated=math.max(Core.Now(),(old and old.updated or 0)+1)
 local v=P.Validate(raw)
 if not v then return false,'Choisis une activité favorite et ta spécialisation.' end
 if not next(v.roles) then v.roles[P.Spec(v.class,v.primary)[3]]=true end
 local records=db(); records[mine()]=v
 if type(QuintessenceDB.profileOptions)~='table' then QuintessenceDB.profileOptions={} end
 QuintessenceDB.profileOptions[mine()]={notice=d.notice~=false,sound=d.sound==true}
 d.step,d.done=P.LAST_STEP,true
 if not P.sync then P.sync=Core:RegisterSync('profile',{},P.Adapter) end
 P.Changed(); if P.sync then P.sync:NotifyLocal() end
 return true,'Profil enregistré et partagé avec la guilde. Les disponibilités ne t’inscrivent à aucun raid.'
end
function P.Rows()
 local records=db(); local out={}
 for key,v in pairs(records) do if P.Validate(v) then out[#out+1]={key=key,profile=copy(v)} end end
 table.sort(out,function(a,b) return a.profile.name<b.profile.name end); return out
end
function P.Priority(name) local v=P.Get(name); return v and v.orders and v.priority or false end
function P.OrderRank(name) local v=P.Get(name); return v and (not v.orders and 2 or v.priority and 0 or 1) or 1 end
function P.Summary(v)
 if not v then return 'Profil non renseigné.' end
 local activities,roles,days={},{},{}
 for _,r in ipairs(P.ACTIVITIES) do if v.activities[r[1]] then activities[#activities+1]=r[2]..(v.favorite==r[1] and ' (favori)' or '') end end
 for _,r in ipairs(P.ROLES) do if v.roles[r[1]] then roles[#roles+1]=r[2] end end
 for i,n in ipairs(P.DAYS) do if v.days[i] then days[#days+1]=n end end
 local s,t=P.Spec(v.class,v.primary),P.Spec(v.class,v.secondary)
 local raid=''; for _,r in ipairs(P.RAIDS) do if r[1]==v.raid then raid=r[2] end end
 return table.concat(activities,', ')..'\nSpécialisation souhaitée : '..(s and s[2] or 'À choisir')..(t and (' / '..t[2]) or '')
  ..'\nRôles volontaires : '..table.concat(roles,', ')..'\nRaids : '..raid..'\nDisponibilités : '..(#days>0 and table.concat(days,', ') or 'À préciser')
  ..'\nCommandes artisan : '..(v.orders and (v.priority and 'volontaire en priorité' or 'oui') or 'non souhaitées')
end
-- Un groupe de synchro borné ; pas de notifications ni de brouillons sur le réseau.
local A={}
function A.Manifest()
 local batches,batch={},{}
 for _,row in ipairs(P.Rows()) do
  batch[#batch+1]={k=row.key,u=row.profile.updated}
  if #batch==20 then batches[#batches+1]=batch; batch={} end
 end
 if #batch>0 then batches[#batches+1]=batch end; return batches
end
function A.Need(_,remote)
 if type(remote)~='table' or #remote>20 then return {} end
 local records=db(); local requests={}
 for _,r in ipairs(remote) do
  if type(r)=='table' and text(r.k,100) and num(r.u,Core.Now()+300) and r.u>=Core.Now()-45*86400 and not own(r.k) then
   local old=records[r.k]; if not old or old.updated<r.u then requests[#requests+1]={key=r.k} end
  end
 end
 return requests
end
function A.Export(_,req)
 if type(req)~='table' or not text(req.key,100) then return {} end
 local records=db(); local v=P.Validate(records[req.key]); return v and {{key=req.key,profile=v}} or {}
end
function A.Merge(_,part,_,_,req)
 if type(part)~='table' or type(req)~='table' or not text(part.key,100) or part.key~=req.key or own(part.key) then return false end
 local v=P.Validate(part.profile); if not v or v.updated<Core.Now()-45*86400 or Core.CanonicalKey(v.name)~=part.key then return false end
 local records=db(); local old=records[part.key]
 if old and old.updated>=v.updated or not old and Core.Count(records)>=2000 then return false end
 records[part.key]=v; return true
end
function A.Cleanup(_,_,now)
 local records=db(); for key,v in pairs(records) do if not own(key) and (not P.Validate(v) or v.updated<now-45*86400) then records[key]=nil end end
end
A.Changed=P.Changed
P.Adapter=A
P.sync=Core:RegisterSync('profile',{},A)
-- Aucun lancement à la connexion : accueil unique à la première ouverture principale.
-- Accueil vu : par personnage (QuintessenceDB est commun au compte). L'ancien booléen welcomeSeen (1.47–1.49.2)
-- empêchait tout reroll du compte de voir l'accueil : il est ignoré et laissé tel quel.
function P.WelcomeSeen() local t=QuintessenceDB.welcomeSeenBy; return type(t)=='table' and t[mine()]==true end
function P.MarkWelcomeSeen()
 if type(QuintessenceDB.welcomeSeenBy)~='table' then QuintessenceDB.welcomeSeenBy={} end
 QuintessenceDB.welcomeSeenBy[mine()]=true
end
function P.ShouldWelcome()
 if P.WelcomeSeen() or Core.GuildStatus()~='ok' or not P.Class() then return false end
 if InCombatLockdown and InCombatLockdown() then return false end
 -- Personnage qui a déjà un profil enregistré : ne pas lui reproposer l'accueil.
 if P.Validate(db()[mine()]) then P.MarkWelcomeSeen(); return false end
 return true
end
