local _, Core = ...
-- Accueil des nouveaux membres : dans sa propre fenêtre, hors de l'addon (T202). Tankeuse, guerrière humaine et tank de
-- la guilde, pose les questions dans une bulle ; on répond avec de grandes cartes illustrées, et la carte de membre se
-- remplit à droite au fil des réponses.
-- Réglages > Profil : mêmes questions et même carte, sans Tankeuse (question écrite simplement), sans l'introduction,
-- l'étape du style ni la fête de fin. Les deux écrans partagent le brouillon.
local P,S=Core.Profile,Core.Style
local panel,mode,selected,page=nil,'mine',nil,0 -- panel : écran en cours de dessin (Réglages ou fenêtre d'accueil)
local settingsPanel,welcomePanel
local I='Interface\\Icons\\'
local CHECK,STAR='Interface\\Buttons\\UI-CheckBox-Check','Interface\\TargetingFrame\\UI-RaidTargetingIcon_1'
-- Icônes du jeu d'origine (talents, objets) ; une icône absente est remplacée et notée dans /quinte debug.
local ICONS={pex='INV_Misc_Map_01',dungeon='INV_Misc_Bone_HumanSkull_01',raid='INV_Misc_Head_Dragon_01',pvp='INV_BannerPVP_02',
 craft='Trade_BlackSmithing',help='Spell_Holy_PrayerOfHealing02',social='INV_Drink_05',
 TANK='Ability_Warrior_DefensiveStance',HEAL='Spell_Holy_Heal',DPS='Ability_DualWield',
 none='Spell_Nature_Sleep',discover='INV_Misc_Spyglass_02',casual='INV_Misc_PocketWatch_01',regular='INV_Misc_Head_Dragon_01'}
local SPEC_ICONS={
 WARRIOR={ARMS='Ability_Warrior_SavageBlow',FURY='Ability_Warrior_InnerRage',PROT='INV_Shield_06'},
 PALADIN={HOLY='Spell_Holy_HolyBolt',PROT='Spell_Holy_DevotionAura',RET='Spell_Holy_AuraOfLight'},
 HUNTER={BM='Ability_Hunter_BeastTaming',MM='Ability_Marksmanship',SURV='Ability_Hunter_SwiftStrike'},
 ROGUE={ASSA='Ability_Rogue_Eviscerate',COMBAT='Ability_BackStab',SUB='Ability_Stealth'},
 PRIEST={DISC='Spell_Holy_WordFortitude',HOLY='Spell_Holy_HolyBolt',SHADOW='Spell_Shadow_ShadowWordPain'},
 SHAMAN={ELEM='Spell_Nature_Lightning',ENH='Spell_Nature_LightningShield',RESTO='Spell_Nature_MagicImmunity'},
 MAGE={ARCANE='Spell_Holy_MagicalSentry',FIRE='Spell_Fire_FireBolt02',FROST='Spell_Frost_FrostBolt02'},
 WARLOCK={AFFLI='Spell_Shadow_DeathCoil',DEMO='Spell_Shadow_Metamorphosis',DESTRO='Spell_Shadow_RainOfFire'},
 DRUID={BALANCE='Spell_Nature_StarFall',BEAR='Ability_Racial_BearForm',CAT='Ability_Druid_CatForm',RESTO='Spell_Nature_HealingTouch'},
}
local HINTS={pex='Monter de niveau, quêter, explorer',dungeon='Groupes de cinq et butin',raid='Les grandes soirées de guilde',
 pvp='Champs de bataille et monde sauvage',craft='Métiers, recettes et commandes',help='Donner un coup de main',social='Discuter, rire, la taverne'}
-- Étapes du parcours ; « days » et « alerts » sont sautées quand elles ne servent à rien, « style » hors de l'accueil
-- (le style se change dans Réglages > Affichage).
P.STEPS={{'likes','Envies'},{'favorite','Favori'},{'spec','Spécialisation'},{'second','Deuxième spé'},{'roles','Rôles'},
 {'raid','Raids'},{'days','Disponibilités'},{'craft','Artisanat'},{'alerts','Alertes'},{'style','Ton style'},{'card','Ta carte'}}
local function skipped(i,d)
 local id=P.STEPS[i][1]
 return id=='days' and d.raid=='none' or id=='alerts' and d.orders==false or id=='style' and not (panel and panel.welcome)
end
-- Style choisi dans l'accueil (1.50.2) : enregistré tout de suite dans QuintessenceDB.theme (réglage du compte, jamais
-- partagé), appliqué à la fin de l'accueil (le changer recharge l'interface).
local STYLE_HINTS={modern='Sombre et épuré, accents or',classic='Les cadres et les boutons du jeu',future='Noir et cyan, crochets et capitales'}
local STYLE_ICONS={modern='Spell_Nature_TimeStop',classic='INV_Misc_Head_Dragon_01',future='Spell_Nature_Lightning'}
local function chosenStyle() return S.ThemeName(QuintessenceDB and QuintessenceDB.theme) or S.theme end
local function nextStep(i,d,dir)
 repeat i=i+dir until i<1 or i>#P.STEPS or not skipped(i,d)
 return math.max(1,math.min(i,#P.STEPS))
end
local function position(d,step)
 local n,pos=0,0
 for i=1,#P.STEPS do if not skipped(i,d) then n=n+1; if i==(step or d.step) then pos=n end end end
 return pos,n
end

local function name() return Core.Safe(Core.DisplayName(Core.Key())) end
local function className()
 local ok,label=Core.Call(UnitClass,'player')
 return ok and type(label)=='string' and not (issecretvalue and issecretvalue(label)) and label or 'personnage'
end
local function icon(tex,file)
 if tex:SetTexture(I..file)==false then S.Missing(I..file); tex:SetTexture(I..'INV_Misc_QuestionMark') end
end

-- Textes, boutons et cartes réutilisés d'un affichage à l'autre (un réservoir par sorte de bouton).
local function label(text,y,size,color,x,width)
 local pool=panel.profileTexts; local i=panel.li+1; panel.li=i
 local f=pool[i]; if not f then f=S.Text(panel,size or 14,color or S.colors.text); f:SetWordWrap(true); pool[i]=f end
 f:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF',size or 14,''); f:SetTextColor(unpack(color or S.colors.text)); f:ClearAllPoints()
 f:SetPoint('TOPLEFT',x or 24,-y); f:SetWidth(width or 1020); f:SetText(text); f:Show(); return f
end
local function button(text,x,y,w,fn,active,kind)
 kind=kind or 'ghost'; local pool=panel.bpool[kind]; if not pool then pool={}; panel.bpool[kind]=pool end
 local i=(panel.bn[kind] or 0)+1; panel.bn[kind]=i; local b=pool[i]
 if not b then b=S.Button(panel,'',w or 230,32,kind); pool[i]=b; panel.buttons[#panel.buttons+1]=b end
 b:SetWidth(w or 230); b:ClearAllPoints(); b:SetPoint('TOPLEFT',x,-y); b:SetLabel(text); b:SetActive(active==true)
 -- Chaque bouton appartient à son écran (Réglages ou accueil) : le clic se calcule sur cet écran
 local owner=panel
 b:SetScript('OnClick',function() panel=owner; Core.Run('profil',fn) end); b:Show(); return b
end
-- Grande carte à cliquer : icône, titre, petite ligne, coche (j'aime) ou étoile (favori).
local function card(text,hint,file,x,y,w,h,fn,state)
 local i=panel.ci+1; panel.ci=i; local c=panel.cards[i]
 if not c then
  c=S.Box(panel,S.colors.panel,S.colors.line,'Button'); panel.cards[i]=c
  c.icon=c:CreateTexture(nil,'ARTWORK'); c.icon:SetSize(40,40)
  c.label=S.Text(c,15,S.colors.text); c.hint=S.Text(c,11,S.colors.muted); c.hint:SetWordWrap(true)
  c.mark=c:CreateTexture(nil,'OVERLAY'); c.mark:SetSize(22,22); c.mark:SetPoint('TOPRIGHT',-6,-6)
  c:SetScript('OnEnter',function(self) self.hover=true; self:Paint() end)
  c:SetScript('OnLeave',function(self) self.hover=false; self:Paint() end)
  function c:Paint()
   self.label:SetTextColor(unpack(self.state and S.colors.gold or S.colors.text))
   if not self.SetBackdropBorderColor then return end
   self:SetBackdropBorderColor(unpack((self.state or self.hover) and S.colors.gold or S.colors.line))
   self:SetBackdropColor(unpack(self.state and S.colors.raised or S.colors.panel))
  end
 end
 c:SetSize(w,h); c:ClearAllPoints(); c:SetPoint('TOPLEFT',x,-y)
 local left=14
 if file then icon(c.icon,file); c.icon:ClearAllPoints(); c.icon:SetPoint('LEFT',12,0); c.icon:Show(); left=64 else c.icon:Hide() end
 c.label:ClearAllPoints(); c.label:SetWidth(w-left-30); c.label:SetText(text)
 if hint and h>=60 then
  local top=math.floor(h/2)
  c.label:SetPoint('TOPLEFT',left,14-top); c.hint:ClearAllPoints()
  c.hint:SetPoint('TOPLEFT',left,-top-4); c.hint:SetWidth(w-left-12); c.hint:SetText(hint); c.hint:Show()
 else c.label:SetPoint('LEFT',left,0); c.hint:Hide() end
 c.state=state
 if state then c.mark:SetTexture(state=='star' and STAR or CHECK); c.mark:Show() else c.mark:Hide() end
 local owner=panel
 c:SetScript('OnClick',function() panel=owner; Core.Run('profil',fn) end); c:Paint(); c:Show(); return c
end
-- Cartes en colonnes dans la zone des réponses (688 px de large, sous la bulle).
local function grid(i,cols,h,top)
 local w=math.floor((688-(cols-1)*16)/cols)
 return 24+(i-1)%cols*(w+16), (top or 226)+math.floor((i-1)/cols)*(h+14), w
end
local function toggle(d,field,key) d[field][key]=not d[field][key] or nil; P.Refresh() end
local function message(s) P.status=s; P.Refresh() end
local function speak(text) panel.npc:Show(); panel.bubble:Show(); panel.bubble.text:SetText(text) end
-- Réglages > Profil : la question écrite simplement, sans Tankeuse
local PLAIN={likes={'Ce qui te plaît dans le jeu','Plusieurs choix possibles ; l’étoile marque ton favori.'},
 favorite={'Ton activité favorite','Celle qui te donne envie de lancer le jeu.'},
 spec={'Ta spécialisation principale','Ton objectif de jeu, même pour le niveau 60 : tes talents ne changent pas.'},
 second={'Ta deuxième spécialisation','Une spé de secours, ou aucune.'},
 roles={'Les rôles que tu acceptes en groupe','Plusieurs choix possibles.'},
 raid={'Les raids','La guilde raide le lundi et le mercredi soir, parfois un troisième soir.'},
 days={'Tes soirs de disponibilité','Indicatif : ça ne t’inscrit à aucun raid.'},
 craft={'Les commandes de la guilde','Dans Craft, un membre choisit une recette, puis un artisan, et clique sur « Commander ».'},
 alerts={'Les alertes de commande','Comment être prévenu quand une commande arrive.'},
 card={'Ta carte de membre','Ce que la guilde voit de toi.'}}
local function ask(id,text)
 if panel.welcome then return speak(text) end
 local q=PLAIN[id] or {P.STEPS[1][2]}
 label(q[1],100,18,S.colors.gold,24,688)
 if q[2] then label(q[2],132,13,S.colors.muted,24,688) end
end

-- Carte de membre : se remplit au fil des réponses.
local function fill(d)
 local m=panel.member; m:Show()
 local function line(i,title,value)
  local row=m.rows[i]; row.title:SetText(title)
  row.value:SetText(value or 'À découvrir…'); row.value:SetTextColor(unpack(value and S.colors.text or S.colors.muted))
 end
 local step=d.done and P.LAST_STEP or tonumber(d.step) or 1
 m.name:SetText(name()); m.class:SetText(className()..' · Quintessence')
 local likes,fav={},nil
 for _,r in ipairs(P.ACTIVITIES) do if d.activities[r[1]] then likes[#likes+1]=r[2]; if r[1]==d.favorite then fav=r[2] end end end
 local class=P.Class(); local s1,s2=P.Spec(class,d.primary),P.Spec(class,d.secondary)
 local roles={}; for _,r in ipairs(P.ROLES) do if d.roles[r[1]] then roles[#roles+1]=r[2] end end
 local raid; for _,r in ipairs(P.RAIDS) do if r[1]==d.raid then raid=r[2] end end
 local days={}; for i,n in ipairs(P.DAYS) do if d.days[i] then days[#days+1]=n:sub(1,3) end end
 if raid and d.raid~='none' and #days>0 then raid=raid..' · '..table.concat(days,', ') end
 local crafted=step>=8
 line(1,'Aime',#likes>0 and table.concat(likes,', ') or nil)
 line(2,'Favori',fav)
 line(3,'Spécialisation',s1 and (s1[2]..(s2 and (' / '..s2[2]) or '')) or nil)
 line(4,'Rôles',#roles>0 and table.concat(roles,', ') or nil)
 line(5,'Raids',step>=6 and raid or nil)
 line(6,'Artisan',crafted and (d.orders and (d.priority and 'Commandes bienvenues, en priorité' or 'Commandes bienvenues') or 'Pas de commandes pour le moment') or nil)
 line(7,'Alertes',crafted and d.orders and ((d.notice~=false and 'Fenêtre' or 'Sans fenêtre')..(d.sound and ' + son' or ', sans son')) or nil)
 local done=0
 for _,v in ipairs({#likes>0,fav~=nil,s1~=nil,#roles>0,step>=7,crafted}) do if v then done=done+1 end end
 m.bar:SetWidth(math.max(1,286*done/6))
 m.stamp:SetShown(d.done==true and P.Get()~=nil)
end

local function guild()
 local rows=P.Rows(); page=math.max(0,math.min(page,math.max(0,math.ceil(#rows/7)-1)))
 label('Profils déclarés par les membres',94,18)
 label('Intentions de jeu ; les talents actuels et les inscriptions aux raids restent indépendants.',126,12,S.colors.muted)
 for i=1,7 do
  local row=rows[page*7+i]
  if row then button(Core.DisplayName(row.profile.name),24,165+(i-1)*40,290,function() selected=row.profile.name; P.Refresh() end,selected==row.profile.name) end
 end
 button('Précédents',24,458,140,function() page=page-1; P.Refresh() end)
 button('Suivants',174,458,140,function() page=page+1; P.Refresh() end)
 if not selected and rows[1] then selected=rows[1].profile.name end
 local v=selected and P.Get(selected)
 if v then label(Core.DisplayName(v.name)..'\n\n'..P.Summary(v),165,13,nil,340,710)
 else label('Les profils apparaîtront ici après leur enregistrement et la synchronisation.',180,13) end
end

local function testNotice(d,y)
 local b=button('Tester la notification artisanat',24,y,330,function()
  if Core.TestCraftNotice then Core.TestCraftNotice(d.sound==true) end
 end)
 if not Core.TestCraftNotice then b:Disable() end
 local s=button('Tester le son',370,y,200,function()
  if Core.TestCraftSound then local _,m=Core.TestCraftSound(); message(m) end
 end)
 if not Core.TestCraftSound then s:Disable() end
end

-- Première page : Tankeuse se présente.
local function intro()
 speak('Bienvenue, '..name()..' ! Moi, c’est Tankeuse, guerrière humaine et tank de Quintessence. '
  ..'Reste derrière mon bouclier, je te fais visiter !')
 label('Ici, tu es chez toi',228,20,S.colors.gold,24,688)
 label('Quintessence est une guilde PvE de l’Alliance, née en 2008. On raide le lundi et le mercredi, '
  ..'on enchaîne les donjons, on pex ensemble et surtout, on s’entraide. Débutant ou vétéran, tout le monde a sa place.',266,14,nil,24,688)
 label('Avant de foncer, j’aimerais te connaître un peu : ce que tu aimes, ce que tu joues et quand tu es là. '
  ..'Deux minutes, quelques clics, et ta carte de membre sera prête à être partagée avec la guilde.',350,14,nil,24,688)
 label('Tes réponses restent en brouillon sur ton ordinateur tant que tu ne les partages pas. Tu peux t’arrêter et reprendre plus tard.',434,12,S.colors.muted,24,688)
 button('Enchanté, Tankeuse !',24,500,300,function() P.welcomeIntro=false; P.Draft().step=1; P.status=nil; P.Refresh() end,false,'primary')
 button('Découvrir plus tard',344,500,240,function() P.welcomeIntro=false; P.HideWelcome() end)
end

-- Fin de l'accueil : la fête, puis où aller ensuite.
local function finale()
 speak('Et voilà, '..name()..' ! Ta carte est partagée : la guilde sait maintenant comment jouer avec toi. '
  ..'Bienvenue chez Quintessence, officiellement !')
 label('Par où commencer ?',228,20,S.colors.gold,24,688)
 label('Ta carte se modifie quand tu veux dans l’addon : Réglages > Profil. Tes disponibilités ne t’inscrivent à aucun raid : '
  ..'inscris-toi à chaque soirée depuis le calendrier.',264,13,nil,24,688)
 local goals={{'home','Faire le tour de l’addon','L’accueil présente chaque onglet','INV_Misc_Book_09'}}
 local mods=Core.modules or {}
 if mods.event then goals[#goals+1]={'event','Voir les prochains raids','Calendrier et inscriptions','INV_Misc_Head_Dragon_01'} end
 if mods.craft then goals[#goals+1]={'craft','Commander un objet','Artisans de la guilde dans Craft','Trade_BlackSmithing'} end
 if mods.group then goals[#goals+1]={'group','Trouver des compagnons','Quêtes et donjons en groupe','INV_Misc_Book_08'} end
 for i,g in ipairs(goals) do
  local x,y,w=grid(i,2,80,330)
  card(g[2],g[3],g[4],x,y,w,80,function() P.celebrate=false; P.HideWelcome(); Core.UI.Open(g[1]) end)
 end
 -- Style choisi pendant l'accueil : l'appliquer recharge l'interface
 local style=chosenStyle()
 if style~=S.theme and S.THEMES[style] then
  button('Appliquer mon style : '..S.THEMES[style].label,736,568,318,function() P.celebrate=false; P.HideWelcome(); Core.SetTheme(style) end,false,'primary')
 end
 button('Fermer',24,568,170,function() P.celebrate=false; P.HideWelcome() end)
end

local function question(d,step)
 local id=P.STEPS[step][1]; local class=P.Class(); local specs=P.SPECS[class] or {}
 local icons=SPEC_ICONS[class] or {}
 if id=='likes' then
  ask(id,'Alors, qu’est-ce qui te plaît dans Azeroth ? Coche tout ce qui te tente. Je ne juge pas… sauf si tu dis que tu détestes les tanks.')
  for i,row in ipairs(P.ACTIVITIES) do local key=row[1]; local x,y,w=grid(i,3,86)
   card(row[2],HINTS[key],ICONS[key],x,y,w,86,function()
    toggle(d,'activities',key); if not d.activities[key] and d.favorite==key then d.favorite=nil end; P.Refresh()
   end,d.activities[key] and (d.favorite==key and 'star' or 'check') or nil)
  end
  button('Reprendre les envies de mon principal',380,500,332,function()
   message(P.Inherit() and 'Envies et disponibilités reprises ; choisis les spécialisations de ce personnage.' or 'Aucun autre principal avec un profil enregistré.')
  end)
 elseif id=='favorite' then
  ask(id,'Et si tu ne devais en garder qu’une ? Choisis ton activité favorite, celle qui te donne envie de lancer le jeu le soir.')
  local n=0
  for _,row in ipairs(P.ACTIVITIES) do local key=row[1]
   if d.activities[key] then n=n+1; local x,y,w=grid(n,3,86)
    card(row[2],d.favorite==key and 'Ton favori !' or 'Clique pour en faire ton favori',ICONS[key],x,y,w,86,function() d.favorite=key; P.Refresh() end,d.favorite==key and 'star' or nil)
   end
  end
 elseif id=='spec' then
  ask(id,'Parlons combat ! Quelle spécialisation veux-tu jouer avec ton personnage ('..className()..') ? '
   ..'Ça ne touche pas à tes talents : c’est ton objectif, même pour le niveau 60.')
  local hints={TANK='Tank : devant, avec moi !',HEAL='Soigneur : tu nous gardes en vie',DPS='Dégâts : tu fais tomber les boss'}
  for i,s in ipairs(specs) do local key=s[1]; local x,y,w=grid(i,2,86)
   card(s[2],hints[s[3]],icons[key],x,y,w,86,function()
    d.primary=key; if d.secondary==key then d.secondary=nil end; d.roles[s[3]]=true; P.Refresh()
   end,d.primary==key and 'star' or nil)
  end
 elseif id=='second' then
  ask(id,'Une deuxième corde à ton arc ? Une spécialisation de secours, c’est toujours pratique en donjon. Sinon, choisis « Aucune », je comprends.')
  local x,y,w=grid(1,2,86)
  card('Aucune','Une seule spé me suffit','Spell_Nature_Sleep',x,y,w,86,function() d.secondary=nil; P.Refresh() end,not d.secondary and 'check' or nil)
  local n=1
  for _,s in ipairs(specs) do local key=s[1]
   if key~=d.primary then n=n+1; x,y,w=grid(n,2,86)
    card(s[2],nil,icons[key],x,y,w,86,function() d.secondary=key; d.roles[s[3]]=true; P.Refresh() end,d.secondary==key and 'check' or nil)
   end
  end
 elseif id=='roles' then
  ask(id,'Quels rôles acceptes-tu de tenir en groupe ? Plusieurs choix possibles. Si tu coches Tank, je t’apprends à prendre les coups avec le sourire.')
  local allowed={}; for _,s in ipairs(specs) do allowed[s[3]]=true end
  local n=0
  for _,r in ipairs(P.ROLES) do if allowed[r[1]] then local key=r[1]; n=n+1; local x,y,w=grid(n,3,86)
   card(r[2],nil,ICONS[key],x,y,w,86,function() toggle(d,'roles',key) end,d.roles[key] and 'check' or nil)
  end end
 elseif id=='raid' then
  ask(id,'Les raids, maintenant ! La guilde raide le lundi et le mercredi soir, parfois un troisième soir pour un raid plus petit. Où en es-tu avec ça ?')
  local hints={none='Pas pour l’instant, peut-être plus tard',discover='Jamais raidé, mais ça me tente',casual='Quand je peux, sans pression',regular='Je veux être là chaque semaine'}
  for i,r in ipairs(P.RAIDS) do local key=r[1]; local x,y,w=grid(i,2,86)
   card(r[2],hints[key],ICONS[key],x,y,w,86,function()
    d.raid=key; if key~='none' then d.activities.raid=true elseif d.favorite~='raid' then d.activities.raid=nil end; P.Refresh()
   end,d.raid==key and 'check' or nil)
  end
 elseif id=='days' then
  ask(id,'Quels soirs es-tu là, en général ? C’est seulement indicatif : ça ne t’inscrit à aucun raid.')
  for i,n in ipairs(P.DAYS) do local x,y,w=grid(i,4,48)
   card(n,nil,nil,x,y,w,48,function() d.days[i]=not d.days[i] or nil; P.Refresh() end,d.days[i] and 'check' or nil)
  end
  label('Lundi et mercredi sont les soirées habituelles de la guilde.',430,12,S.colors.muted,24,300)
 elseif id=='craft' then
  ask(id,'Chez Quintessence, on se rend service ! Dans l’onglet Craft, tu choisis une recette, puis un artisan de la guilde, '
   ..'et tu cliques sur « Commander » : il est prévenu en jeu. Moi, je commande sans arrêt des enchantements d’arme !')
  label('Et toi, veux-tu recevoir des commandes de la guilde ?',226,15,S.colors.gold,24,688)
  local x,y,w=grid(1,2,86,258)
  card('Oui, on peut me commander','Je fabrique pour les copains','INV_Fabric_Moonrag_01',x,y,w,86,function() d.orders=true; P.Refresh() end,d.orders and 'check' or nil)
  x,y,w=grid(2,2,86,258)
  card('Pas pour le moment','Mon savoir-faire reste visible','Spell_Nature_TimeStop',x,y,w,86,function() d.orders=false; d.priority=false; P.Refresh() end,not d.orders and 'check' or nil)
  if d.orders then
   x,y,w=grid(1,1,70,358)
   card('Me proposer en priorité','Les artisans volontaires passent devant les autres dans la liste de Craft','INV_Misc_Coin_02',x,y,w,70,function() d.priority=not d.priority; P.Refresh() end,d.priority and 'star' or nil)
   label('Tu dois connaître la recette : ouvre tes métiers une fois pour que l’addon les relève. C’est toujours le demandeur qui choisit et confirme sa commande.',446,12,S.colors.muted,24,688)
  else
   label('Les nouvelles commandes te seront refusées avec un message clair ; celles déjà reçues restent accessibles dans Craft. Tu peux toujours commander chez les autres.',358,12,S.colors.muted,24,688)
  end
 elseif id=='alerts' then
  ask(id,'Quand une commande arrive, comment je te préviens ? Une petite fenêtre en haut de l’écran, un son, ou les deux. '
   ..'Essaie : ce n’est qu’un exemple, avec ma commande d’enchantement et un sac en étoffe lunaire.')
  local x,y,w=grid(1,2,86)
  card('Fenêtre discrète','En haut au centre, déplaçable','INV_Misc_Note_01',x,y,w,86,function() d.notice=d.notice==false; P.Refresh() end,d.notice~=false and 'check' or nil)
  x,y,w=grid(2,2,86)
  card('Son à la réception','Un seul son par commande','INV_Misc_Horn_01',x,y,w,86,function() d.sound=not d.sound; P.Refresh() end,d.sound and 'check' or nil)
  testNotice(d,330)
  label('Une seule ouverture automatique au plus toutes les 30 minutes ; les essais ici sont libres. Le badge sur l’icône de l’addon compte tes commandes en attente. '
   ..'Ces choix restent sur ton ordinateur et s’appliquent après l’enregistrement.',380,12,S.colors.muted,24,688)
 elseif id=='style' then
  ask(id,'Dernière petite chose avant ta carte : quel style pour la fenêtre de l’addon ? Choisis celui qui te plaît, '
   ..'tu pourras en changer quand tu veux.')
  for i,name in ipairs(S.THEME_ORDER) do local x,y,w=grid(i,3,86)
   card(S.THEMES[name].label,STYLE_HINTS[name],STYLE_ICONS[name] or 'INV_Misc_Note_01',x,y,w,86,function()
    QuintessenceDB.theme=name; P.Refresh()
   end,chosenStyle()==name and 'check' or nil)
  end
  label(chosenStyle()==S.theme and 'C’est le style actuel de la fenêtre.'
   or 'Il s’appliquera à la fin de l’accueil : l’interface se rechargera. Aussi dans Réglages > Affichage.',330,12,S.colors.muted,24,688)
 else
  ask(id,d.done and 'Voici ta carte de membre. Modifie ce que tu veux avec « Précédent », puis mets-la à jour.'
   or 'Et voilà ta carte de membre, juste à droite ! Si elle te plaît, partage-la avec la guilde.')
  label('Qui verra ta carte ?',226,16,S.colors.gold,24,688)
  label('Les membres de Quintessence, dans l’addon (Réglages > Profil > Profils de guilde) : tes envies, spécialisations, rôles, '
   ..'disponibilités et volontariat artisan. Tes brouillons et tes choix de fenêtre et de son restent sur ton ordinateur.',254,13,nil,24,688)
  label('Où est-elle rangée ?',324,16,S.colors.gold,24,688)
  label('Dans le fichier Quintessence.lua du dossier WTF/Account/<compte>/SavedVariables, écrit par le jeu au /reload ou à la déconnexion. '
   ..'Le site de la guilde ne lit pas ces réponses.',352,13,nil,24,688)
  button(d.done and 'Mettre à jour ma carte' or 'Enregistrer et partager',24,440,330,function()
   local welcome=panel.welcome -- P.Save redessine les deux écrans
   local ok,s=P.Save()
   if ok and welcome then P.celebrate=true; P.status=nil; P.Refresh() else message(s) end
  end,false,'primary')
 end
end

local function render()
 for _,f in ipairs(panel.profileTexts) do f:Hide() end
 for _,b in ipairs(panel.buttons) do b:Hide(); b:Enable() end
 for _,c in ipairs(panel.cards) do c:Hide() end
 panel.npc:Hide(); panel.bubble:Hide(); panel.member:Hide(); panel.progress:Hide()
 panel.li,panel.ci,panel.bn=0,0,{}
 local d=P.Draft()
 label(panel.welcome and 'Bienvenue chez Quintessence' or 'Réglages — Profil',12,22,S.colors.gold)
 if panel.welcome and P.welcomeIntro then intro(); fill(d); return end
 if panel.welcome and P.celebrate then finale(); fill(d); return end
 if not panel.welcome then
  button('Mon profil',24,52,200,function() mode='mine'; P.Refresh() end,mode=='mine')
  button('Profils de guilde',236,52,200,function() mode='guild'; P.Refresh() end,mode=='guild')
  if mode=='guild' then guild(); return end
 end
 local step=math.max(1,math.min(tonumber(d.step) or 1,#P.STEPS)); d.step=step
 -- Étape sautée sur cet écran (le style n'existe que dans l'accueil) : l'écran montre la précédente, sans changer le
 -- brouillon commun à l'autre écran ouvert.
 if skipped(step,d) then step=nextStep(step,d,-1); if panel.welcome or not P.WelcomeShown() then d.step=step end end
 local pos,total=position(d,step)
 panel.progress:Show(); panel.progress.text:SetText('Étape '..pos..' sur '..total..' · '..P.STEPS[step][2])
 panel.progress.bar:SetWidth(math.max(1,300*pos/total))
 question(d,step); fill(d)
 label(P.status or 'Tes réponses sont gardées en brouillon : tu peux fermer et reprendre plus tard.',620,11,S.colors.muted)
 if step>1 then button('Précédent',24,568,170,function() d.step=nextStep(step,d,-1); P.status=nil; P.Refresh() end) end
 if step<#P.STEPS then button('Suivant',492,568,220,function()
  local id=P.STEPS[step][1]
  if id=='likes' and not next(d.activities) then return message('Choisis au moins une activité pour continuer.') end
  if id=='favorite' and (not d.favorite or not d.activities[d.favorite]) then return message('Choisis ton activité favorite pour continuer.') end
  if id=='spec' and not P.Spec(P.Class(),d.primary) then return message('Choisis ta spécialisation principale pour continuer.') end
  d.step=nextStep(step,d,1); P.status=nil; P.Refresh()
 end,false,'primary') end
 if d.done and step<#P.STEPS then button('Voir ma carte',736,568,318,function() d.step=#P.STEPS; P.status=nil; P.Refresh() end) end
 if panel.welcome then button('Plus tard',254,568,170,function() P.HideWelcome() end) end
end
function P.Refresh()
 -- Les deux écrans existants (l'un peut manquer : pas d'ipairs sur une liste à trous)
 if settingsPanel then panel=settingsPanel; Core.Run('profil',render) end
 if welcomePanel then panel=welcomePanel; Core.Run('accueil',render) end
 panel=settingsPanel or welcomePanel
end
function P.BeginWelcome()
 P.welcoming=true;P.welcomeIntro=true;P.celebrate=false;P.status=nil
end
local create
-- Fenêtre de l'accueil : la sienne, hors de l'addon ; déplaçable, X et Échap la ferment.
local function welcomeWindow()
 if P.window then return P.window end
 local w=S.Box(UIParent,S.colors.bg,S.colors.gold); S.MakeDialog(w,1078,658)
 w:SetPoint('CENTER',UIParent,'CENTER',0,20)
 w.onClose=function() P.welcoming=false;P.celebrate=false end
 welcomePanel=create(w,true); welcomePanel:SetPoint('TOPLEFT',0,0)
 if w.close and w.close.SetFrameLevel and welcomePanel.GetFrameLevel then w.close:SetFrameLevel((welcomePanel:GetFrameLevel() or 1)+20) end
 P.window=w; w:Hide(); return w
end
--- Ouvre l'accueil des nouveaux membres dans sa fenêtre (première ouverture, ou Réglages > Revoir l'accueil).
function P.ShowWelcome()
 local w=welcomeWindow()
 local pct=Core.UI and Core.UI.ScalePercent and Core.UI.ScalePercent() or 100
 local ok,height=pcall(UIParent.GetHeight,UIParent); local fit=ok and type(height)=='number' and height>0 and (height-40)/658 or 1
 if w.SetScale then w:SetScale(math.max(0.5,math.min(pct/100,fit))) end
 P.BeginWelcome(); w:Show(); P.Refresh(); return true
end
function P.HideWelcome() P.welcomeIntro=false; if P.window then P.window:Hide() end; P.welcoming=false end
function P.WelcomeShown() return P.window~=nil and P.window:IsShown()==true end
function P.ReplayWelcome()
 P.MarkWelcomeSeen();P.ShowWelcome()
end
function P.Open()
 mode='mine';Core.Settings.Open('profile')
end
create=function(parent,welcome)
 panel=CreateFrame('Frame',nil,parent); panel:SetSize(1078,658); panel.welcome=welcome==true
 panel.profileTexts,panel.buttons,panel.bpool,panel.bn,panel.cards={},{},{},{},{}
 -- Tankeuse : portrait et bulle de dialogue.
 local npc=S.Box(panel,S.colors.raised,S.colors.gold); npc:SetSize(92,112); npc:SetPoint('TOPLEFT',24,-92); panel.npc=npc
 npc.icon=npc:CreateTexture(nil,'ARTWORK'); npc.icon:SetSize(72,72); npc.icon:SetPoint('TOP',0,-8)
 if npc.icon:SetTexture(I..'Achievement_Character_Human_Female')==false then icon(npc.icon,'INV_Shield_06') end
 -- Portrait 3D : humaine (race 1, sexe 1 = femme) avec le casque T3 du guerrier (objet 22418).
 -- Repli sur l'icône si le client ne sait pas afficher le modèle.
 local ok,model=false,nil
 if welcome then ok,model=pcall(CreateFrame,'DressUpModel',nil,npc) end
 if ok and model and model.SetCustomRace and model.TryOn then
  model:SetSize(84,84); model:SetPoint('TOP',0,-4); npc.model=model
  local function dress()
   pcall(function()
    model:SetCustomRace(1,1); if model.Undress then model:Undress() end
    model:TryOn('item:22418'); if model.SetPortraitZoom then model:SetPortraitZoom(0.85) end
   end)
  end
  model:SetScript('OnShow',dress); dress(); npc.icon:Hide()
 end
 npc.name=S.Text(npc,12,S.colors.gold,'CENTER'); npc.name:SetPoint('BOTTOM',0,10); npc.name:SetText('Tankeuse')
 local bubble=S.Box(panel,S.colors.panel,S.colors.line); bubble:SetSize(580,112); bubble:SetPoint('TOPLEFT',132,-92); panel.bubble=bubble
 bubble.text=S.Text(bubble,14,S.colors.text); bubble.text:SetWordWrap(true); bubble.text:SetPoint('TOPLEFT',16,-14); bubble.text:SetWidth(548)
 -- Progression du parcours.
 local progress=CreateFrame('Frame',nil,panel); progress:SetSize(318,40); progress:SetPoint('TOPLEFT',736,-44); panel.progress=progress
 progress.text=S.Text(progress,12,S.colors.muted); progress.text:SetPoint('TOPLEFT',0,0)
 local track=S.Fill(progress,'BACKGROUND',S.colors.line); track:SetPoint('TOPLEFT',0,-20); track:SetSize(300,6)
 progress.bar=S.Fill(progress,'ARTWORK',S.colors.gold); progress.bar:SetPoint('TOPLEFT',0,-20); progress.bar:SetSize(1,6)
 -- Carte de membre.
 local m=S.Box(panel,S.colors.panel,S.colors.gold); m:SetSize(318,452); m:SetPoint('TOPLEFT',736,-92); panel.member=m
 local head=S.Text(m,11,S.colors.muted); head:SetPoint('TOPLEFT',16,-14); head:SetText('CARTE DE MEMBRE')
 m.name=S.Text(m,18,S.colors.gold); m.name:SetPoint('TOPLEFT',16,-34); m.name:SetWidth(286)
 m.class=S.Text(m,12,S.colors.text); m.class:SetPoint('TOPLEFT',16,-60); m.class:SetWidth(286)
 local track2=S.Fill(m,'BORDER',S.colors.line); track2:SetPoint('TOPLEFT',16,-84); track2:SetSize(286,4)
 m.bar=S.Fill(m,'ARTWORK',S.colors.gold); m.bar:SetPoint('TOPLEFT',16,-84); m.bar:SetSize(1,4)
 m.rows={}
 for i=1,7 do
  local r={}; r.title=S.Text(m,11,S.colors.gold); r.title:SetPoint('TOPLEFT',16,-104-(i-1)*46)
  r.value=S.Text(m,13,S.colors.text); r.value:SetWordWrap(true); r.value:SetPoint('TOPLEFT',16,-120-(i-1)*46); r.value:SetWidth(286)
  m.rows[i]=r
 end
 m.stamp=S.Text(m,12,S.colors.mint,'CENTER'); m.stamp:SetPoint('BOTTOM',0,10); m.stamp:SetText('Partagée avec la guilde')
 if welcome then P.welcomePanel=panel else settingsPanel=panel; P.panel=panel end
 return panel
end
P.CreatePanel=function(parent) local p=create(parent,false); P.Refresh(); return p end
