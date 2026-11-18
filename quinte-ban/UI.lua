local _,B=...
local C,S=Quintessence,Quintessence.Style
local view,selected,offset='list',nil,0
local labels={approved='Validée',rejected='Refusée',removed='Retirée'}
local function dateText(at) return date and date('%d/%m/%Y %H:%M',at) or tostring(at) end
local function button(p,label,x,y,w,fn,style)
 local f=S.Button(p,label,w,28,style or 'ghost');f:SetPoint('TOPLEFT',x,y);f:SetScript('OnClick',fn);return f
end
-- Le signalement ne crée ni n'ouvre la grande fenêtre de l'addon.
function B.Report(name,manual)
 if not name and not manual then name=B.UnitName('target') end
 if C.GuildStatus()~='ok' then C.Print('Signalement réservé aux membres de Quintessence.');return end
 if not B.ready then B.Init() end
 if not B.reportDialog then
  local q=S.Box(UIParent,S.colors.bg,S.colors.line);B.Dialog(q,320,200);q:SetPoint('CENTER')
  local title=S.Text(q,16,S.colors.text);title:SetPoint('TOPLEFT',12,-12);title:SetText('Signaler un joueur')
  q.target=S.Text(q,13,S.colors.gold);q.target:SetPoint('TOPLEFT',12,-44);q.target:SetWidth(296)
  q.name=S.Input(q,296,'Prénom et nom complets du joueur');q.name:SetPoint('TOPLEFT',12,-36);q.name:SetMaxLetters(100);q.name:SetScript('OnEscapePressed',function() q:Hide() end)
  local hint=S.Text(q,12,S.colors.muted);hint:SetPoint('TOPLEFT',12,-66);hint:SetText('Que s’est-il passé ?')
  q.comment=B.Comment(q,296,30);q.comment.container:SetPoint('TOPLEFT',12,-86)
  q.comment:SetScript('OnEscapePressed',function() q:Hide() end)
  q.feedback=S.Text(q,12,S.colors.muted);q.feedback:SetPoint('TOPLEFT',12,-122);q.feedback:SetWidth(296);q.feedback:SetWordWrap(true)
  q.send=button(q,'Envoyer',12,-160,144,function()
   if q.sent then return end
   local name=(q.fixedName or q.name:GetText() or ''):match('^%s*(.-)%s*$')
   local reason=(q.comment:GetText() or ''):gsub('[\r\n]+',' '):match('^%s*(.-)%s*$')
   local ok,msg=B.Submit(name,reason)
   q.feedback:SetText(ok and 'Signalement enregistré. Les officiers vont l’examiner.' or msg)
   -- Envoyé : la fenêtre se ferme, confirmation dans le chat (T225)
   if ok then q.sent=true;q.comment:ClearFocus();q:Hide();C.Print('Signalement de '..C.Safe(C.DisplayName(name))..' envoyé aux officiers.') end
  end,'primary')
  q.cancel=button(q,'Annuler',164,-160,144,function() q:Hide() end)
  B.reportDialog=q
 end
 local q=B.reportDialog;q.sent=false;q.fixedName=name;q.name:SetText(name or '');q.name:SetShown(not name);q.target:SetShown(name~=nil)
 q.target:SetText(C.Safe(name and C.DisplayName(name) or ''));q.comment:SetText('');q.send:Show();q.cancel:SetLabel('Annuler')
 q.feedback:SetText('Commentaire privé, soumis aux officiers.')
 q:Show();q:Raise();if name then q.comment:SetFocus() else q.name:SetFocus() end
end
function B.ActiveList() return view=='review' and (B.reviewKind or 'black') or B.list end
function B.Rows()
 local d=B.DB();local rows={};local off=B.IsOfficer()
 local source=view=='review' and off and d.reports or d.entries
 local filter=B.panel and (B.panel.search:GetText() or ''):lower() or ''
 if B.ActiveList()=='white' then return B.White.ListRows(view,filter) end
 for id,r in pairs(source) do
  local show=view=='review' and off and not r.result or view=='history' and off or view=='list' and B.Get(r.name)
  if show and (filter=='' or (r.name..' '..r.reason):lower():find(filter,1,true)) then rows[#rows+1]={id=id,r=r} end
 end
 table.sort(rows,function(a,b) return a.r.at==b.r.at and a.id<b.id or a.r.at>b.r.at end);return rows
end
function B.Render()
 local p=B.panel;if not p then return end
 local off=B.IsOfficer();if not off and view~='list' then view='list';selected=nil end
 p.review:SetShown(off);p.history:SetShown(off)
 local white=B.ActiveList()=='white';local review=off and view=='review'
 p.black:SetActive(view~='review' and not white);p.white:SetActive(view~='review' and white);
 p.reviewBlack:SetShown(review);p.reviewWhite:SetShown(review)
 local function pending(records) local n=0;for _,r in pairs(records) do if not r.result then n=n+1 end end;return n end
 p.reviewBlack:SetLabel('Signalements ('..pending(B.DB().reports)..')');p.reviewWhite:SetLabel('Recommandations ('..pending(B.White.DB().reports)..')')
 p.reviewBlack:SetActive(not white);p.reviewWhite:SetActive(white)
 p.search:ClearAllPoints();p.search:SetPoint('TOPLEFT',0,review and -86 or -48)
 p.count:ClearAllPoints();p.count:SetPoint('TOPLEFT',0,review and -122 or -85)
 for i,f in ipairs(p.rows) do f:ClearAllPoints();f:SetPoint('TOPLEFT',0,(review and -148 or -112)-(i-1)*39) end
 p.review:SetActive(view=='review');p.history:SetActive(view=='history')
 local rows=B.Rows();offset=math.max(0,math.min(offset,math.max(0,#rows-12)));p.current=nil
 for i,f in ipairs(p.rows) do
  local row=rows[offset+i];f.item=row;f:SetShown(row~=nil)
  if row then f.title:SetText(white and S.ClassText and S.ClassText(C.Safe(row.r.name),row.r.class) or C.Safe(row.r.name));f.sub:SetText(white and (row.summary and string.format('%.1f / 5',row.r.average) or row.r.rating..' / 5') or '');f:SetSelected(selected==row.id) end
 end
 for _,row in ipairs(rows) do if row.id==selected then p.current=row.r end end
 local r=p.current;local reviewing=off and view=='review' and r~=nil
 p.actionReason:SetShown(off and r~=nil and (not white or view~='list'));p.approve:SetShown(reviewing);p.approve:SetEnabled(not (white and r and B.Get(r.name)));p.reject:SetShown(reviewing);p.duration:SetShown(reviewing and not white)
 p.remove:SetShown(off and view~='review' and r~=nil and r.status=='approved')
 p.remove:SetLabel(white and 'Retirer cet avis' or 'Retirer de la liste noire')
 local lines={}
 if r then
  if white then lines={B.White.Description(r)} else
  lines={r.name,r.reason}
  if view=='review' then lines[#lines+1]='Signalé par '..C.DisplayName(r.by)..' · '..dateText(r.at)
  else
   lines[#lines+1]='Validation : '..C.DisplayName(r.by)..' · '..dateText(r.at)
   if off then for _,h in ipairs(r.history or {}) do lines[#lines+1]=dateText(h.at)..' · '..C.DisplayName(h.by)..' · '..labels[h.status]..' : '..h.reason end end
  end
  end
 else lines={view=='review' and (#rows==0 and 'Aucun dossier dans cette catégorie.' or 'Choisis un dossier pour le valider ou le refuser.') or (#rows==0 and 'Aucun joueur sur la liste noire.' or 'Choisis un joueur pour lire le motif validé par les officiers.'), 'Pour signaler : clic droit sur le portrait du joueur, puis « Signaler à Quintessence ».'} end
 if not r and white and view=='list' then lines={#rows==0 and 'Aucun joueur recommandé pour le moment.' or 'Choisis un joueur pour voir ses étoiles et les avis validés.','Pour recommander : clic droit portrait → Recommander à Quintessence.'} end
 if white and r and view=='review' and B.Get(r.name) then lines[#lines+1]='Validation impossible : joueur en liste noire. Le refus reste disponible.' end
 -- Vue affichée dans l’en-tête du conteneur (1.50.0) : « Listes joueurs › Liste blanche », « › À examiner »…
 if C.UI and C.UI.SetCrumb then C.UI.SetCrumb('noire',view=='review' and 'À examiner' or view=='history' and 'Historique' or (white and 'Liste blanche' or 'Liste noire')) end
 p.detail:SetText(C.Safe(table.concat(lines,'\n\n')));p.count:SetText(#rows..(view=='review' and (white and ' recommandation(s) à examiner' or ' signalement(s) à examiner') or ' joueur(s)'))
end
function B.Create(parent)
 B.DB();local p=CreateFrame('Frame',nil,parent);p:SetSize(1078,658);B.panel=p
 local function tab(mode) return function() if mode~='list' and not B.IsOfficer() then return end;view=mode;if mode=='review' then B.reviewKind=B.reviewKind or B.list or 'black' end;selected=nil;offset=0;B.Render() end end
 p.black=button(p,'Liste noire',0,0,135,function() B.SelectList('black') end)
 p.white=button(p,'Liste blanche',145,0,145,function() B.SelectList('white') end)
 p.review=button(p,'À examiner',310,0,160,tab('review'));p.history=button(p,'Historique',480,0,130,tab('history'))
 local function category(kind) return function() if not B.IsOfficer() then return end;B.reviewKind=kind;selected=nil;offset=0;p.search:SetText('');B.Render() end end
 p.reviewBlack=button(p,'Signalements',0,-48,160,category('black'))
 p.reviewWhite=button(p,'Recommandations',168,-48,162,category('white'))
 p.report=button(p,'Signaler un joueur',632,0,200,function() B.Report() end)
 p.recommend=button(p,'Recommander un joueur',842,0,210,function() B.White.Open() end)
 p.search=S.Input(p,330,'Rechercher un joueur');p.search:SetPoint('TOPLEFT',0,-48);B.InputChanged(p.search,function() offset=0;B.Render() end)
 p.count=S.Text(p,12,S.colors.muted);p.count:SetPoint('TOPLEFT',0,-85)
 p.rows={};for i=1,12 do
  local f=S.Row(p,330,34);f:SetPoint('TOPLEFT',0,-112-(i-1)*39);f.title=S.Text(f,12,S.colors.text);f.title:SetPoint('LEFT',10,0);f.title:SetWidth(246);f.sub=S.Text(f,11,S.colors.gold,'RIGHT');f.sub:SetPoint('RIGHT',-8,0);f.sub:SetWidth(70)
  f:SetScript('OnClick',function() if f.item then selected=f.item.id;p.actionReason:SetText(f.item.r.reason or '');B.Render() end end);p.rows[i]=f
 end
 p:EnableMouseWheel(true);p:SetScript('OnMouseWheel',function(_,d) offset=offset-d;B.Render() end)
 local box=S.Box(p,S.colors.panel,S.colors.line);box:SetPoint('TOPLEFT',350,-48);box:SetSize(702,440)
 local scroll=CreateFrame('ScrollFrame',nil,box);scroll:SetPoint('TOPLEFT',14,-14);scroll:SetSize(674,410)
 local body=CreateFrame('Frame',nil,scroll);body:SetSize(650,410);scroll:SetScrollChild(body)
 p.detail=S.Text(body,13,S.colors.text);p.detail:SetPoint('TOPLEFT');p.detail:SetWidth(648);p.detail:SetWordWrap(true)
 scroll:EnableMouseWheel(true);scroll:SetScript('OnMouseWheel',function(_,d) local h=p.detail:GetStringHeight();body:SetHeight(math.max(410,h+12));scroll:SetVerticalScroll(math.max(0,math.min(math.max(0,h-396),scroll:GetVerticalScroll()-d*36))) end)
 p.actionReason=S.Input(p,702,'Motif de la décision');p.actionReason:SetPoint('TOPLEFT',350,-506);p.actionReason:SetMaxLetters(600)
 p.days=0;p.duration=button(p,'Durée : permanente',350,-547,210,function() p.days=({[0]=7,[7]=30,[30]=90,[90]=0})[p.days];p.duration:SetLabel('Durée : '..(p.days==0 and 'permanente' or p.days..' jours')) end)
 local function decide(status) if not B.IsOfficer() then return end;local _,msg;if B.ActiveList()=='white' then _,msg=B.White.Resolve(selected,status,p.actionReason:GetText()) else _,msg=B.Resolve(selected,status,p.actionReason:GetText(),p.days) end;p.message:SetText(msg);B.Render() end
 p.approve=button(p,'Valider',570,-547,170,function() decide('approved') end,'primary')
 p.reject=button(p,'Refuser',750,-547,170,function() decide('rejected') end,'danger')
 p.remove=button(p,'Retirer de la liste noire',350,-547,270,function() if p.current and B.IsOfficer() then local _,msg;if B.list=='white' then _,msg=B.White.Remove(selected,p.actionReason:GetText()) else _,msg=B.Remove(p.current.name,p.actionReason:GetText()) end;p.message:SetText(msg);B.Render() end end,'danger')
 p.message=S.Text(p,12,S.colors.muted);p.message:SetPoint('TOPLEFT',350,-604);p.message:SetWidth(700);p.message:SetWordWrap(true)
 p.message:SetText('Seuls les officiers peuvent valider une inscription sur la liste noire.')
 B.Render();return p
end
function B.SelectList(kind,name)
 B.list=kind;view='list';selected=name and C.CanonicalKey(name) or nil;offset=0
 if B.panel then B.panel.search:SetText('');B.panel.message:SetText('Les avis et signalements sont validés par les officiers.');B.Render() end
end
function B.Open(name)
 if not B.ready then B.Init() end
 C.UI.Open('noire');B.SelectList('black',name)
end
-- Petite fenêtre en haut au milieu de l'écran (0.6.0, T225) : un ou plusieurs joueurs du groupe, fermée toute seule
-- après une minute. Jamais en plein écran, ne prend pas le clavier.
local ALERT_SECONDS=60
function B.ShowAlert(v,kind)
 if not B.alert then
  local f=S.Box(UIParent,S.colors.panel,S.colors.red);f:SetSize(380,112);f:SetPoint('TOP',UIParent,'TOP',0,-80);f:SetFrameStrata('DIALOG')
  f:SetFrameLevel(400);f:EnableMouse(true);f:SetMovable(true);f:SetClampedToScreen(true);f:RegisterForDrag('LeftButton')
  f:SetScript('OnDragStart',function() f:StartMoving() end);f:SetScript('OnDragStop',function() f:StopMovingOrSizing() end)
  f.title=S.Text(f,14,S.colors.red);f.title:SetPoint('TOPLEFT',12,-10);f.title:SetWidth(320)
  f.close=S.Button(f,'X',22,22,'ghost');f.close:SetPoint('TOPRIGHT',-6,-6);f.close:SetScript('OnClick',function() f:Hide() end)
  f.message=S.Text(f,12,S.colors.text);f.message:SetPoint('TOPLEFT',12,-32);f.message:SetWidth(356);f.message:SetHeight(42);f.message:SetWordWrap(true);f.message:SetMaxLines(3)
  f.open=button(f,'Voir la fiche',12,-78,170,function() B.Open(f.name);f:Hide() end,'primary')
  f.dismiss=button(f,'Fermer',198,-78,170,function() f:Hide() end)
  f:SetScript('OnUpdate',function(self,dt) self.left=(self.left or 0)-(tonumber(dt) or 0);if self.left<=0 then self:Hide() end end)
  B.alert=f
 end
 local f=B.alert
 local line=C.Safe(C.DisplayName(v.name))..' — '..C.Safe(v.reason)
 -- Plusieurs joueurs du même groupe : ajoutés sous le premier
 if f:IsShown() and f.lines and #f.lines<3 and f.name~=v.name then f.lines[#f.lines+1]=line else f.lines={line};f.name=v.name end
 f.title:SetText(kind=='pending' and 'Joueur signalé dans ton groupe' or 'Liste noire : joueur dans ton groupe')
 f.message:SetText(table.concat(f.lines,'\n'));f.left=ALERT_SECONDS;f:Show();if f.Raise then f:Raise() end
end

-- Accueil du conteneur (1.49.0) : décisions qui attendent un officier, en lignes « À faire » seulement.
-- Jamais de tuile pour la Liste noire (demande du GM : l'alerte de groupe suffit). Rien pour un membre, rien d'enregistré.
local function waiting(reports)
 local n=0;for _,r in pairs(reports) do if type(r)=='table' and not r.result then n=n+1 end end;return n
end
function B.OpenReview(kind)
 if not B.ready then B.Init() end
 C.UI.Open('noire');B.SelectList(kind=='white' and 'white' or 'black')
 if B.IsOfficer() then B.reviewKind=kind=='white' and 'white' or 'black';view='review';B.Render() end
end
function B.Home()
 if not B.ready or C.GuildStatus()~='ok' or not B.IsOfficer() then return nil end
 local todo={}
 local black=waiting(B.DB().reports)
 if black>0 then todo[#todo+1]={text=black..' signalement'..(black>1 and 's' or '')..' de la liste noire à examiner',tone='gold',order=40,action=function() B.OpenReview('black') end} end
 local white=B.White and B.White.DB and waiting(B.White.DB().reports) or 0
 if white>0 then todo[#todo+1]={text=white..' avis de la liste blanche à valider',tone='gold',order=45,action=function() B.OpenReview('white') end} end
 if #todo>0 then return {todo=todo} end
end

C:RegisterModule({id='noire',title='Listes joueurs',order=75,icon='Interface\\Icons\\Ability_Creature_Cursed_02',version=B.version,width=1078,height=658,
 create=B.Create,refresh=B.Refresh,home=B.Home,summary=function() return 'Joueurs validés et signalement simple par clic droit.' end})
SLASH_QUINTEBAN1='/qban'
SlashCmdList.QUINTEBAN=function() B.Open() end
