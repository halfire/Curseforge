local _,B=...
local C,S=Quintessence,Quintessence.Style
local W=B.White
local function button(p,label,x,y,w,fn)
 local f=S.Button(p,label,w,28,'ghost');f:SetPoint('TOPLEFT',x,y);f:SetScript('OnClick',fn);return f
end
local function when(at) return date and date('%d/%m/%Y',at) or tostring(at) end
-- Les deux listes utilisent le même panneau de consultation et la même navigation.
function W.ListRows(mode,filter)
 local rows={};local d=W.DB()
 if mode=='list' then for _,r in ipairs(W.Players()) do rows[#rows+1]={id=r.key,r=r,summary=true} end
 elseif B.IsOfficer() then
  for id,r in pairs(mode=='review' and d.reports or d.entries) do
   if mode~='review' or not r.result then rows[#rows+1]={id=id,r=r} end
  end
  table.sort(rows,function(a,b) return a.r.at==b.r.at and a.id<b.id or a.r.at>b.r.at end)
 end
 local out={};for _,row in ipairs(rows) do
  local r=row.r;local class=W.Class(r.class)
  if filter=='' or (r.name..' '..(class and class[2] or '')..' '..r.spec):lower():find(filter,1,true) then out[#out+1]=row end
 end;return out
end
function W.Description(r)
 local class=W.Class(r.class);local lines={r.name,(class and class[2] or '')..' · '..(r.spec~='' and r.spec or 'Spécialisation non précisée')..' (déclarée, '..when(r.at)..')'}
 if r.reviews then
  lines[#lines+1]=string.format('%.1f / 5 · %d avis validé(s)',r.average,r.count)
  if B.Get(r.name) then lines[#lines+1]='Attention : ce joueur est aussi sur la liste noire.' end
  for _,v in ipairs(r.reviews) do lines[#lines+1]=v.rating..'/5 · '..C.DisplayName(v.by)..'\n'..v.reason end
 else
  lines[#lines+1]=r.rating..'/5 · '..C.DisplayName(r.by)..'\n'..r.reason
  if r.officer then lines[#lines+1]=(r.status=='removed' and 'Avis retiré' or 'Avis validé')..' par '..C.DisplayName(r.officer)..' : '..r.note end
 end
 return table.concat(lines,'\n\n')
end
local experience={'Expérience difficile','Expérience mitigée','Bonne expérience','Très bonne expérience','Excellente expérience'}
function W.Form(preview)
 local q=W.dialog;local class=q.classIndex and W.CLASSES[q.classIndex]
 q.class:SetLabel(class and class[2] or 'Choisir la classe');q.class:SetEnabled(not q.fixedClass)
 for i,b in ipairs(q.specs) do
  local label=class and class[3][i];b:SetShown(label~=nil)
  if label then
   local width=(336-(#class[3]-1)*8)/#class[3];b:ClearAllPoints();b:SetPoint('TOPLEFT',12+(i-1)*(width+8),-104);b:SetWidth(width)
   b:SetLabel(label:gsub('Combat farouche %(ours%)','Ours'):gsub('Combat farouche %(chat%)','Chat'):gsub('Maîtrise des bêtes','Bêtes'));b:SetActive(q.specIndex==i)
  end
 end
 local n=preview or q.rating
 for i,b in ipairs(q.stars) do
  local color=i<=n and S.colors.gold or S.colors.muted;b.star:SetVertexColor(unpack(color));b:SetActive(i==q.rating)
 end
 q.grade:SetText(n>0 and (n..' / 5 — '..experience[n]) or 'Clique sur les étoiles')
 local comment=q.comment:GetText() or '';local name=q.fixedName or q.name:GetText() or ''
 -- L’envoi reste accessible : les erreurs sont expliquées au clic, jamais un bouton muet.
 q.send:SetEnabled(not q.sent)
end
function W.CreateDialog()
 local q=S.Box(UIParent,S.colors.bg,S.colors.line);B.Dialog(q,360,300);q:SetPoint('CENTER');W.dialog=q
 local title=S.Text(q,16,S.colors.text);title:SetPoint('TOPLEFT',12,-12);title:SetText('Recommander un joueur')
 q.target=S.Text(q,13,S.colors.gold);q.target:SetPoint('TOPLEFT',12,-44);q.target:SetWidth(336)
 q.name=S.Input(q,336,'Prénom et nom complets (Alliance)');q.name:SetPoint('TOPLEFT',12,-36);q.name:SetMaxLetters(100);q.name:SetScript('OnEscapePressed',function() q:Hide() end)
 B.InputChanged(q.name,function() if q.send then W.Form() end end)
 q.class=button(q,'Choisir la classe',12,-68,336,function() if not q.fixedClass then q.classList:SetShown(not q.classList:IsShown()) end end)
 q.classList=S.Box(q,S.colors.panel,S.colors.line);q.classList:SetPoint('TOPLEFT',12,-100);q.classList:SetSize(336,116);q.classList:SetFrameLevel(q:GetFrameLevel()+10);q.classList:EnableMouse(true)
 q.classChoices={};for i,r in ipairs(W.CLASSES) do
  q.classChoices[i]=button(q.classList,r[2],6+((i-1)%3)*110,-6-math.floor((i-1)/3)*36,104,function() q.classIndex=i;q.specIndex=nil;q.classList:Hide();W.Form() end)
 end;q.classList:Hide()
 q.specs={};for i=1,4 do q.specs[i]=button(q,'',12+(i-1)*82,-104,120,function() q.specIndex=i;W.Form() end) end
 q.stars={};for i=1,5 do
  local b=button(q,'',12+(i-1)*22,-138,20,function() q.rating=i;W.Form() end);b:SetHeight(20)
  b.star=b:CreateTexture(nil,'ARTWORK');b.star:SetSize(14,14);b.star:SetPoint('CENTER');b.star:SetTexture('Interface\\AddOns\\'..B.name..'\\Media\\Star.tga')
  b:SetScript('OnEnter',function() W.Form(i) end);b:SetScript('OnLeave',function() W.Form() end);q.stars[i]=b
 end
 q.grade=S.Text(q,12,S.colors.text);q.grade:SetPoint('TOPLEFT',12,-164);q.grade:SetWidth(336)
 local label=S.Text(q,12,S.colors.muted);label:SetPoint('TOPLEFT',12,-182);label:SetText('Commentaire')
 q.comment=B.Comment(q,336,24);q.comment.container:SetPoint('TOPLEFT',12,-198)
 B.InputChanged(q.comment,function() W.Form() end);q.comment:SetScript('OnEscapePressed',function() q:Hide() end)
 q.feedback=S.Text(q,12,S.colors.muted);q.feedback:SetPoint('TOPLEFT',12,-228);q.feedback:SetWidth(336);q.feedback:SetWordWrap(true)
 q.send=button(q,'Envoyer',12,-264,164,function()
  if q.sent then return end
  local class=q.classIndex and W.CLASSES[q.classIndex];local spec=class and q.specIndex and class[3][q.specIndex] or ''
  local name=(q.fixedName or q.name:GetText() or ''):match('^%s*(.-)%s*$');local reason=(q.comment:GetText() or ''):gsub('[\r\n]+',' '):match('^%s*(.-)%s*$')
  local ok,msg
  if not name:find('%S') then msg='Indique le prénom et le nom du joueur.'
  elseif not class then msg='Choisis la classe du joueur.'
  elseif q.rating==0 then msg='Clique sur une étoile pour donner ta note.'
  elseif not reason:find('%S') then msg='Écris un commentaire avant d’envoyer.'
  else ok,msg=W.Submit(name,class[1],spec,q.rating,reason) end
  q.feedback:SetText(ok and 'Avis enregistré pour validation par les officiers.' or msg)
  -- Envoyé : la fenêtre se ferme, confirmation dans le chat (T225)
  if ok then q.sent=true;q.comment:ClearFocus();q:Hide();C.Print('Recommandation de '..C.Safe(C.DisplayName(name))..' envoyée aux officiers.') end
 end)
 q.cancel=button(q,'Annuler',184,-264,164,function() q:Hide() end)
 return q
end
function W.Open(name,unit,capturedClass,manual)
 if not name and not manual then name=B.UnitName('target');if name then unit='target' end end
 if C.GuildStatus()~='ok' then C.Print('Recommandation réservée aux membres de Quintessence.');return end
 if not B.ready then B.Init() end
 local q=W.dialog or W.CreateDialog();q.sent=false;q.fixedName=name;q.fixedClass=nil;q.classIndex=nil;q.specIndex=nil;q.rating=0;q.classList:Hide()
 q.name:SetText(name or '');q.name:SetShown(name==nil);q.target:SetShown(name~=nil);q.target:SetText(C.Safe(name and C.DisplayName(name) or ''));q.comment:SetText('')
 local class=capturedClass or B.UnitClass(unit);q.fixedClass=class~=nil
 local mine=name and W.DB().own[C.CanonicalKey(C.Key())..'>'..C.CanonicalKey(name)]
 if mine then class=class or mine.class;q.rating=mine.rating;q.comment:SetText(mine.reason) end
 for i,r in ipairs(W.CLASSES) do if r[1]==class then q.classIndex=i;if mine then for j,s in ipairs(r[3]) do if s==mine.spec then q.specIndex=j end end end end end
 q.send:Show();q.cancel:SetLabel('Annuler');q.feedback:SetText('Spé facultative. Étoiles et commentaire requis.')
 W.Form();q:Show();q:Raise();if name then q.comment:SetFocus() else q.name:SetFocus() end
end
function W.Render() B.Render() end
