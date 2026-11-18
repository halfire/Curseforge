local _, B = ...
local Core = Quintessence
-- Liste communautaire : attentes privées, décisions reçues directement d'un officier.
local MAX = 500
local function secret(v) return issecretvalue and issecretvalue(v) end
local function text(v,n) return not secret(v) and type(v)=='string' and #v<=n and not v:find('[%z\1-\31|]') end
local function validName(v) return text(v,100) and v:find('%S') and v~='Unknown' and v~=UNKNOWNOBJECT end
local function key(v) return validName(v) and Core.CanonicalKey(v) or nil end
local function copy(t) local o={};for k,v in pairs(t) do o[k]=type(v)=='table' and copy(v) or v end;return o end
local function now() return Core.Now() end
local function db()
 if type(QuinteBanDB)~='table' then QuinteBanDB={} end
 local d=QuinteBanDB
 for _,k in ipairs({'entries','reports','own','options'}) do if type(d[k])~='table' then d[k]={} end end
 return d
end
B.DB=db
local function roster()
 local ranks,online={},{}
 local ok,n=Core.Call(GetNumGuildMembers)
 if not ok or secret(n) or type(n)~='number' then return ranks,online end
 for i=1,math.min(n,2000) do
  local success,name,_,rank,_,_,_,_,_,on=Core.Call(GetGuildRosterInfo,i)
  if success and key(name) and not secret(rank) and type(rank)=='number' then
   ranks[key(name)]=rank
   if rank<=1 and not secret(on) and on then online[#online+1]=name end
  end
 end
 return ranks,online
end
function B.OnlineOfficers() local _,online=roster();return online end
function B.IsOfficer(name)
 if not name then
  local ok,_,_,rank=Core.Call(GetGuildInfo,'player')
  if ok and not secret(rank) and type(rank)=='number' then return rank<=1 end
  name=Core.PlayerName()
 end
 local ranks=roster();local r=ranks[key(name)];return r~=nil and r<=1
end
local function allowed() return Core.GuildStatus()=='ok' end
local function stamp(v) return not secret(v) and type(v)=='number' and v%1==0 and v>=0 and v<=now()+300 end
local function report(v)
 if type(v)~='table' or not text(v.id,160) or not validName(v.name) or not validName(v.by) or not text(v.reason,600) or not v.reason:find('%S') or not stamp(v.at) then return nil end
 if v.id~=key(v.by)..':'..v.at..':'..key(v.name) then return nil end
 return {id=v.id,name=v.name,by=v.by,reason=v.reason,at=v.at}
end
local function decision(v)
 if type(v)~='table' or not validName(v.name) or not validName(v.by) or not text(v.reason,600) or not v.reason:find('%S') or not stamp(v.at)
  or secret(v.expires) or type(v.expires)~='number' or v.expires%1~=0 or v.expires<0 or v.expires>now()+90*86400+300 or v.expires~=0 and v.expires<=v.at or (v.status~='approved' and v.status~='removed') then return nil end
 local out={name=v.name,by=v.by,reason=v.reason,at=v.at,expires=v.expires,status=v.status,history={}}
 if type(v.history)~='table' or #v.history>20 then return nil end
 for _,h in ipairs(v.history) do
  if type(h)~='table' or not validName(h.by) or not text(h.reason,600) or not stamp(h.at) or (h.status~='approved' and h.status~='removed') then return nil end
  out.history[#out.history+1]={by=h.by,reason=h.reason,at=h.at,status=h.status}
 end
 return out
end
local function newer(a,b)
 if not b then return true end
 if a.at~=b.at then return a.at>b.at end
 -- Égalité déterministe : retrait prioritaire, puis auteur et motif.
 return a.status..a.by..a.reason..a.expires>b.status..b.by..b.reason..b.expires
end
function B.Get(name)
 local v=db().entries[key(name)]
 if v and v.status=='approved' and (v.expires==0 or v.expires>now()) then return copy(v) end
end
-- Joueur à signaler en groupe (0.6.0, T225) : décision validée pour tous ; signalement en attente pour les officiers et
-- pour son auteur seulement (jamais montré aux autres membres). Renvoie la fiche et 'approved' ou 'pending'.
function B.Watch(name)
 local v=B.Get(name);if v then return v,'approved' end
 local k=key(name);if not k then return end
 local d=db()
 if B.IsOfficer() then
  for _,r in pairs(d.reports) do if type(r)=='table' and not r.result and key(r.name)==k then return copy(r),'pending' end end
 end
 for _,r in pairs(d.own) do
  if type(r)=='table' and not r.result and key(r.name)==k and Core.SameName(r.by,Core.Key()) then return copy(r),'pending' end
 end
end
function B.Refresh()
 if B.panel and B.panel:IsVisible() and B.Render then B.Render() end
 B.ScanGroup()
end
local function sendOfficers(payload)
 local _,online=roster()
 for _,name in ipairs(online) do if not Core.SameName(name,Core.PlayerName()) then B.comm:Send(payload,name) end end
end
function B.Submit(name,reason)
 if not allowed() then return false,'Réservé aux membres de Quintessence.' end
 if not validName(name) or Core.IsRegional() and not name:match('%S+[%s%-]+%S+') then return false,'Indique le prénom et le nom complets du joueur.' end
 if not text(reason,600) or not reason:find('%S') then return false,'Écris un motif (600 octets maximum, sans lien de chat).' end
 local d=db();if Core.Count(d.own)>=MAX then return false,'Limite de signalements atteinte.' end
 -- Un même joueur ne peut être signalé qu'une fois par minute par ce personnage.
 for _,r in pairs(d.own) do if key(r.name)==key(name) and key(r.by)==key(Core.PlayerName()) and now()-r.at<60 then return false,'Ce joueur vient déjà d’être signalé.' end end
 local r={name=name,by=Core.Key(),reason=reason,at=now()};r.id=key(r.by)..':'..r.at..':'..key(name)
 d.own[r.id]=r
 if B.IsOfficer() then d.reports[r.id]=copy(r) end
 sendOfficers({t='report',r=r});B.Refresh()
 return true,'Signalement enregistré, en attente de validation. Il sera renvoyé aux officiers connectés.'
end
function B.Resolve(id,status,reason,days)
 if not allowed() or not B.IsOfficer() then return false,'Réservé aux officiers.' end
 local d=db();local r=d.reports[id]
 if not r or r.result then return false,'Ce signalement a déjà été traité ou est introuvable.' end
 if status~='approved' and status~='rejected' then return false,'Décision invalide.' end
 if not text(reason,600) or not reason:find('%S') then return false,'Indique le motif de la décision.' end
 if days~=0 and days~=7 and days~=30 and days~=90 then return false,'Durée invalide.' end
 if status=='approved' then
  local old=d.entries[key(r.name)];local at=math.max(now(),old and old.at+1 or 0)
  local v={name=r.name,by=Core.Key(),reason=reason,at=at,expires=days==0 and 0 or at+days*86400,status='approved',history=old and copy(old.history) or {}}
  v.history[#v.history+1]={by=v.by,reason=reason,at=at,status='approved'}
  while #v.history>20 do table.remove(v.history,1) end
  if not old and Core.Count(d.entries)>=MAX then return false,'Limite de fiches atteinte.' end
  d.entries[key(v.name)]=v;if B.White then B.White.BlacklistChanged(v.name) end;B.comm:Send({t='entry',e=v})
 end
 r.result={status=status,reason=reason,by=Core.Key(),at=now()}
 if d.own[id] then d.own[id].result=copy(r.result) end
 B.comm:Send({t='result',id=id,result=r.result},r.by)
 sendOfficers({t='report',r=r,result=r.result});B.Refresh()
 return true,status=='approved' and 'Entrée validée et partagée.' or 'Signalement refusé.'
end
function B.Remove(name,reason)
 if not allowed() or not B.IsOfficer() then return false,'Réservé aux officiers.' end
 local d=db();local old=d.entries[key(name)]
 if not old then return false,'Fiche introuvable.' end
 if not text(reason,600) or not reason:find('%S') then return false,'Indique la raison du retrait.' end
 local v=copy(old);v.status='removed';v.by=Core.Key();v.reason=reason;v.at=math.max(now(),old.at+1);v.expires=0
 v.history[#v.history+1]={by=v.by,reason=reason,at=v.at,status=v.status};while #v.history>20 do table.remove(v.history,1) end
 d.entries[key(name)]=v;B.comm:Send({t='entry',e=v});B.Refresh();return true,'Joueur retiré de la liste noire.'
end
local function result(v)
 if type(v)=='table' and (v.status=='approved' or v.status=='rejected') and text(v.reason,600) and validName(v.by) and stamp(v.at) then return copy(v) end
end
function B.Receive(m,sender,channel)
 if not allowed() or type(m)~='table' or not key(sender) then return end
 local officer=B.IsOfficer(sender);local d=db()
 if m.t=='entry' and officer then
  local v=decision(m.e)
  if v and (d.entries[key(v.name)] or Core.Count(d.entries)<MAX) and newer(v,d.entries[key(v.name)]) then d.entries[key(v.name)]=v;if B.White then B.White.BlacklistChanged(v.name) end;B.Refresh() end
 elseif m.t=='report' and channel=='WHISPER' and B.IsOfficer() then
  local r=report(m.r);if not r or not (Core.SameName(sender,r.by) or officer) then return end
  local old=d.reports[r.id]
  if not old and Core.Count(d.reports)>=MAX then return end
  if not old then d.reports[r.id]=r;Core.Print('Liste noire : nouveau signalement à examiner.');old=r end
  if old.result then B.comm:Send({t='result',id=old.id,result=old.result},old.by) end
  if officer then local res=result(m.result);if res and (not old.result or res.at>old.result.at or res.at==old.result.at and res.by>old.result.by) then old.result=res end end
  B.Refresh()
 elseif m.t=='result' and channel=='WHISPER' and officer and text(m.id,160) and d.own[m.id] then
  local res=result(m.result);if res then d.own[m.id].result=res;B.Refresh() end
 elseif m.t=='ask' and B.IsOfficer() then
  local k=key(sender);B.asked=B.asked or {};if B.asked[k] and now()-B.asked[k]<120 then return end;B.asked[k]=now()
  if m.h~=B.Fingerprint() then for _,v in pairs(d.entries) do B.comm:Send({t='entry',e=v},sender) end end
  if officer then for _,r in pairs(d.reports) do B.comm:Send({t='report',r=r,result=r.result},sender) end end
 end
end
B.comm=Core:RegisterChannel('qblack',function(...) Core.Run('liste noire reçue',B.Receive,...) end)
function B.Fingerprint()
 local parts={}
 for k,v in pairs(db().entries) do parts[#parts+1]=k..':'..v.at..':'..v.by..':'..v.status..':'..v.reason..':'..v.expires end
 table.sort(parts);local h=0
 for _,v in ipairs(parts) do for i=1,#v do h=(h*33+v:byte(i))%2147483647 end end
 return tostring(#parts)..':'..h
end
function B.Tick()
 if allowed() then
  B.comm:Send({t='ask',h=B.Fingerprint()})
  for _,r in pairs(db().own) do
   if not r.result and Core.SameName(r.by,Core.Key()) then
    if B.IsOfficer() and not db().reports[r.id] and Core.Count(db().reports)<MAX then db().reports[r.id]=copy(r) end
    sendOfficers({t='report',r=r})
   end
  end
  -- Un officier garde les décisions reçues et les transmet au prochain officier connecté.
  B.ScanGroup()
 end
end
function B.ScanGroup()
 if not allowed() then return end
 local seen={}
 local ok,raid=Core.Call(IsInRaid);if not ok or secret(raid) then return end
 local success,n=Core.Call(GetNumGroupMembers)
 if not success or secret(n) or type(n)~='number' or n<0 then return end
 n=math.min(n,40)
 for i=1,n do
  local unit=raid and ('raid'..i) or (i==n and 'player' or 'party'..i)
  local got,name=Core.Call(Core.UnitFullName,unit)
  if got and key(name) then
   local k=key(name);seen[k]=true;local v,kind=B.Watch(name)
   if v and not B.alerted[k] and not Core.SameName(name,Core.PlayerName()) then
    B.alerted[k]=true
    local red=Core.Style and Core.Style.hex and Core.Style.hex.red or 'ffff4040'
    Core.Print('|c'..red..'Liste noire :|r '..Core.Safe(Core.DisplayName(v.name))..(kind=='pending' and ' a été signalé (en attente des officiers). ' or ' est dans ton groupe. ')
     ..Core.Safe(v.reason)..' — /quinte noire')
    if B.ShowAlert then B.ShowAlert(v,kind) end
    if db().options.sound~=false then Core.Call((C_Sound and C_Sound.PlaySound) or PlaySound,8959,'Master') end
   end
  end
 end
 -- Une lecture secrète ne prouve pas le départ d'un joueur : attendre une lecture complète.
 if Core.Count(seen)==n then for k in pairs(B.alerted) do if not seen[k] then B.alerted[k]=nil end end end
end
function B.UnitName(unit)
 if not text(unit,40) then return end
 local ok,isPlayer=Core.Call(UnitIsPlayer,unit);if not ok or secret(isPlayer) or not isPlayer then return end
 local success,faction=Core.Call(UnitFactionGroup,unit);if not success or secret(faction) or faction~='Alliance' then return end
 local got,name=Core.Call(Core.UnitFullName,unit);if got and validName(name) and not Core.SameName(name,Core.PlayerName()) then return name end
end
-- Nom cliqué dans le chat (0.5.1, T201) : le menu du jeu ne donne pas d'unité, seulement context.name (« Nom » ou
-- « Nom-Royaume », royaume parfois à part dans context.server). Jamais un ami Battle.net (pseudo du compte), jamais soi.
function B.ChatName(context)
 if type(context)~='table' or secret(context.name) or secret(context.server) then return end
 if context.bnetIDAccount or context.accountInfo or context.isMobile then return end
 local name=context.name
 if not validName(name) then return end
 if not name:find('-',1,true) and text(context.server,60) and context.server:find('%S') then name=name..'-'..context.server end
 if not validName(name) or Core.SameName(name,Core.PlayerName()) then return end
 return name
end
function B.InstallMenu()
 if B.menu=='actif' or not (Menu and type(Menu.ModifyMenu)=='function') then return end
 -- FRIEND : nom du chat (canaux, guilde, chuchotements) ; CHAT_ROSTER : liste des membres d'un canal
 for _,tag in ipairs({'PLAYER','PARTY','RAID_PLAYER','RAID','FRIEND','FRIEND_OFFLINE','CHAT_ROSTER','TARGET'}) do
  local ok=Core.Call(Menu.ModifyMenu,'MENU_UNIT_'..tag,function(_,root,context)
   if not allowed() or type(context)~='table' then return end
   local unit=context.unit
   local name=unit and B.UnitName(unit) or (not unit and B.ChatName(context))
   if not name then return end
   local class=B.UnitClass(unit)
   root:CreateDivider()
   root:CreateButton('Signaler à Quintessence',function() B.Report(name) end)
   if B.Get(name) then root:CreateButton('Quintessence : voir la fiche',function() B.Open(name) end) end
   if B.White and B.White.Open then root:CreateButton('Recommander à Quintessence',function() B.White.Open(name,nil,class) end) end
  end)
  if not ok then B.menu='erreur';return end
 end
 B.menu='actif'
end
function B.Init()
 if B.ready then return end
 local d=db()
 -- T154 n'a pas été publiée ; garder tout de même les sauvegardes d'un éventuel essai local.
 if not d.migratedFromCore then
  local legacy=type(QuintessenceDB)=='table' and QuintessenceDB.blacklist
  if type(legacy)=='table' then
   for _,kind in ipairs({'entries','reports','own','options'}) do
    if type(legacy[kind])=='table' then
     for k,v in pairs(legacy[kind]) do if d[kind][k]==nil then d[kind][k]=type(v)=='table' and copy(v) or v end end
    end
   end
  end
  d.migratedFromCore=true
 end
 d.format=1;B.ready=true;B.InstallMenu()
 local function tick()
  Core.Run('liste noire périodique',B.Tick)
  if C_Timer and C_Timer.After then C_Timer.After(300,tick) end
 end
 if C_Timer and C_Timer.After then C_Timer.After(45,tick) end
end
local f=CreateFrame('Frame')
for _,e in ipairs({'PLAYER_LOGIN','ADDON_LOADED','GROUP_ROSTER_UPDATE','PLAYER_REGEN_ENABLED'}) do f:RegisterEvent(e) end
f:SetScript('OnEvent',function(_,e,arg)
 Core.Run('liste noire',function()
  if e=='PLAYER_LOGIN' or e=='ADDON_LOADED' and arg==B.name then B.Init() end
  if not B.ready then return end
  B.InstallMenu();B.ScanGroup()
 end)
end)
