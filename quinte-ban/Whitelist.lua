local _,B=...
local C=Quintessence
local W={};B.White=W
W.CLASSES={{'WARRIOR','Guerrier',{'Armes','Fureur','Protection'}},{'PALADIN','Paladin',{'Sacré','Protection','Vindicte'}},{'HUNTER','Chasseur',{'Maîtrise des bêtes','Précision','Survie'}},{'ROGUE','Voleur',{'Assassinat','Combat','Finesse'}},{'PRIEST','Prêtre',{'Discipline','Sacré','Ombre'}},{'SHAMAN','Chaman',{'Élémentaire','Amélioration','Restauration'}},{'MAGE','Mage',{'Arcanes','Feu','Givre'}},{'WARLOCK','Démoniste',{'Affliction','Démonologie','Destruction'}},{'DRUID','Druide',{'Équilibre','Combat farouche (ours)','Combat farouche (chat)','Restauration'}}}
local function secret(v) return issecretvalue and issecretvalue(v) end
local function txt(v,n) return not secret(v) and type(v)=='string' and #v>0 and #v<=n and not v:find('[%z\1-\31|]') end
local function key(v) return txt(v,100) and C.CanonicalKey(v) or nil end
local function copy(t) local o={};for k,v in pairs(t) do o[k]=type(v)=='table' and copy(v) or v end;return o end
local function now() return C.Now() end
local function num(v) return not secret(v) and type(v)=='number' and v%1==0 and v>=0 and v<=now()+300 end
function W.DB()
 B.DB();if type(QuinteBanDB.white)~='table' then QuinteBanDB.white={} end
 local d=QuinteBanDB.white
 for _,k in ipairs({'entries','own','reports'}) do if type(d[k])~='table' then d[k]={} end end
 return d
end
function W.Class(id)
 for _,r in ipairs(W.CLASSES) do if r[1]==id then return r end end
end
local function valid(v)
 if type(v)~='table' or not key(v.name) or not key(v.by) or not txt(v.id,220) or v.id~=key(v.by)..'>'..key(v.name)
  or not num(v.at) or not txt(v.reason,600) or not v.reason:find('%S') or not txt(v.class,20) or secret(v.spec) or not (v.spec=='' or txt(v.spec,80))
  or secret(v.rating) or type(v.rating)~='number' or v.rating%1~=0 or v.rating<1 or v.rating>5 then return end
 local class=W.Class(v.class);if not class then return end
 local found=v.spec=='';for _,s in ipairs(class[3]) do if s==v.spec then found=true end end;if not found then return end
 return {id=v.id,name=v.name,by=v.by,at=v.at,reason=v.reason,rating=v.rating,class=v.class,spec=v.spec}
end
local function validEntry(v)
 local out=valid(v);if not out or not key(v.officer) or not num(v.updated) or v.updated<v.at or not txt(v.note,600) or (v.status~='approved' and v.status~='removed') then return end
 out.officer,out.updated,out.note,out.status=v.officer,v.updated,v.note,v.status;return out
end
local function later(a,b)
 return not b or a.updated>b.updated or a.updated==b.updated and a.status..a.officer..a.note..a.rating..a.class..a.spec..a.reason>b.status..b.officer..b.note..b.rating..b.class..b.spec..b.reason
end
local function officers(m)
 for _,name in ipairs(B.OnlineOfficers()) do if not C.SameName(name,C.Key()) then W.comm:Send(m,name) end end
end
function W.Changed() if B.panel and B.panel:IsVisible() then B.Render() end end
function W.Submit(name,class,spec,rating,reason)
 if C.GuildStatus()~='ok' then return false,'Réservé aux membres de Quintessence.' end
 if not key(name) or C.IsRegional() and not name:match('%S+[%s%-]+%S+') then return false,'Indique le prénom et le nom complets.' end
 if B.Get(name) then return false,'Ce joueur est sur la liste noire. Un officier doit d’abord l’en retirer.' end
 local id=C.CanonicalKey(C.Key())..'>'..key(name);local d=W.DB();local old=d.own[id]
 local r=valid({id=id,name=name,by=C.Key(),at=math.max(now(),old and old.at+1 or 0),reason=reason,class=class,spec=spec or '',rating=rating})
 if not r then return false,'Choisis une classe, des étoiles et un commentaire (600 octets maximum).' end
 if not old and C.Count(d.own)>=500 then return false,'Limite de recommandations atteinte.' end
 d.own[id]=r;if B.IsOfficer() then d.reports[id]=copy(r) end
 officers({t='report',r=r});W.Changed();return true,'Recommandation envoyée aux officiers. Ton avis remplace le précédent après validation.'
end
function W.Resolve(id,status,note)
 if C.GuildStatus()~='ok' or not B.IsOfficer() then return false,'Réservé aux officiers.' end
 local d=W.DB();local r=d.reports[id]
 if not r or r.result then return false,'Recommandation déjà traitée ou introuvable.' end
 if (status~='approved' and status~='rejected') or not txt(note,600) then return false,'Indique le motif de la décision.' end
 local old=d.entries[id];local black=B.DB().entries[key(r.name)]
 local at=math.max(now(),old and old.updated+1 or 0,r.at,black and black.at+1 or 0)
 if status=='approved' then
  if B.Get(r.name) then return false,'Validation impossible : ce joueur est sur la liste noire.' end
  if not old and C.Count(d.entries)>=500 then return false,'Limite de fiches atteinte.' end
  local v=copy(r);v.officer,v.updated,v.status,v.note=C.Key(),at,'approved',note
  d.entries[id]=v;W.comm:Send({t='entry',e=v})
 end
 r.result={at=at,by=C.Key(),status=status,note=note,revision=r.at}
 if d.own[id] and d.own[id].at==r.at then d.own[id].result=copy(r.result) end
 W.comm:Send({t='result',id=id,result=r.result},r.by);officers({t='report',r=r,result=r.result});W.Changed()
 return true,status=='approved' and 'Avis validé et partagé.' or 'Avis refusé ; la dernière version validée reste inchangée.'
end
function W.Remove(id,note)
 if C.GuildStatus()~='ok' or not B.IsOfficer() then return false,'Réservé aux officiers.' end
 local d=W.DB();local r=d.entries[id];if not r or not txt(note,600) then return false,'Sélectionne un avis et indique le motif du retrait.' end
 local v=copy(r);v.officer,v.updated,v.status,v.note=C.Key(),math.max(now(),r.updated+1),'removed',note
 d.entries[id]=v;W.comm:Send({t='entry',e=v});W.Changed();return true,'Avis retiré de la liste blanche.'
end
-- La liste noire gagne, quel que soit l’ordre de réception des deux canaux.
function W.Excluded(v)
 if B.Get(v.name) then return true end
 local black=B.DB().entries[key(v.name)]
 if black then
  if black.at>=v.updated then return true end
  for _,h in ipairs(black.history or {}) do if h.status=='approved' and h.at>=v.updated then return true end end
 end
 return false
end
function W.BlacklistChanged(name)
 if C.GuildStatus()~='ok' or not B.IsOfficer() then return end
 local ids={}
 for id,v in pairs(W.DB().entries) do
  if v.status=='approved' and (not name or key(name)==key(v.name)) and W.Excluded(v) then ids[#ids+1]=id end
 end
 for _,id in ipairs(ids) do W.Remove(id,'Retrait automatique : inscription en liste noire.') end
end
local function result(v)
 if type(v)=='table' and num(v.at) and num(v.revision) and key(v.by) and txt(v.note,600) and (v.status=='approved' or v.status=='rejected') then return copy(v) end
end
function W.Hash()
 local p={};for id,v in pairs(W.DB().entries) do p[#p+1]=id..':'..v.updated..':'..v.status..':'..v.rating..':'..v.class..':'..v.spec..':'..v.reason..':'..v.officer..':'..v.note end
 table.sort(p);local h=0;for _,s in ipairs(p) do for i=1,#s do h=(h*33+s:byte(i))%2147483647 end end;return #p..':'..h
end
function W.Receive(m,sender,ch)
 if C.GuildStatus()~='ok' or type(m)~='table' or not key(sender) then return end
 local d=W.DB();local off=B.IsOfficer(sender)
 if m.t=='entry' and off then
  local v=validEntry(m.e);if v and (d.entries[v.id] or C.Count(d.entries)<500) and later(v,d.entries[v.id]) then d.entries[v.id]=v;W.BlacklistChanged(v.name);W.Changed() end
 elseif m.t=='report' and ch=='WHISPER' and B.IsOfficer() then
  local r=valid(m.r);if not r or not (off or C.SameName(sender,r.by)) then return end
  local old=d.reports[r.id];if not old and C.Count(d.reports)>=500 then return end
  if not old or r.at>old.at then d.reports[r.id]=r;old=r;C.Print('Liste blanche : une recommandation attend la validation des officiers.') end
  local res=off and result(m.result)
  if res and res.revision==old.at and (not old.result or res.at>old.result.at or res.at==old.result.at and res.by>old.result.by) then old.result=res end
  if old.result then W.comm:Send({t='result',id=old.id,result=old.result},old.by) end
  W.Changed()
 elseif m.t=='result' and ch=='WHISPER' and off and txt(m.id,220) and d.own[m.id] then
  local res=result(m.result);local r=d.own[m.id]
  if res and res.revision==r.at and (not r.result or res.at>=r.result.at) then r.result=res;W.Changed() end
 elseif m.t=='ask' and B.IsOfficer() then
  W.asked=W.asked or {};local k=key(sender);if W.asked[k] and now()-W.asked[k]<120 then return end;W.asked[k]=now()
  if m.h~=W.Hash() then for _,v in pairs(d.entries) do W.comm:Send({t='entry',e=v},sender) end end
  if off then for _,r in pairs(d.reports) do W.comm:Send({t='report',r=r,result=r.result},sender) end end
 end
end
W.comm=C:RegisterChannel('qwhite',function(...) C.Run('liste blanche reçue',W.Receive,...) end)
function W.Tick()
 if C.GuildStatus()~='ok' then return end
 W.BlacklistChanged()
 W.comm:Send({t='ask',h=W.Hash()})
 for _,r in pairs(W.DB().own) do if not r.result and C.SameName(r.by,C.Key()) then
  if B.IsOfficer() and not W.DB().reports[r.id] and C.Count(W.DB().reports)<500 then W.DB().reports[r.id]=copy(r) end
  officers({t='report',r=r})
 end end
end
function W.Players()
 local out={}
 for _,v in pairs(W.DB().entries) do if v.status=='approved' and not W.Excluded(v) then
  local k=key(v.name);local r=out[k] or {name=v.name,key=k,total=0,count=0,at=0,reviews={}}
  r.total,r.count=r.total+v.rating,r.count+1;r.reviews[#r.reviews+1]=copy(v)
  if v.at>=r.at then r.class,r.spec,r.at=v.class,v.spec,v.at end
  out[k]=r
 end end
 local rows={};for _,r in pairs(out) do r.average=r.total/r.count;table.sort(r.reviews,function(a,b) return a.by<b.by end);rows[#rows+1]=r end
 table.sort(rows,function(a,b) return a.name<b.name end);return rows
end
local tick=B.Tick
B.Tick=function() tick();W.Tick() end
