local addonName, A = ...
local G,Cards=A.Game,A.Cards
-- Onglet « Ride the Bus » de la fenêtre Quintessence, mis en page pour la zone de contenu du conteneur (1078 × 658
-- depuis 0.7.0, affichée sans réduction : cartes et textes de la même taille qu'avant, table et liste plus grandes). Kit d'interface du conteneur (S.*, deux thèmes) ; seuls les cartes et le tapis sont
-- nos textures (Media/, scripts/make_cards.py). Aucune écriture dans les objets de Blizzard.
local PANEL_W,PANEL_H=1078,658
local LEFT_W,GUILD_ROWS=256,14
local FELT_X,FELT_W,FELT_H=LEFT_W+20,1078-LEFT_W-30,420 -- 792 × 420
local STAGE_W,STAGE_H=554,300 -- question, pyramide, salon : centrés sur le tapis
local U={selected={},guildPage=1,onlineOnly=true}
A.UI=U
local S
local function C() return S.colors end
local function set(fs,value) value=tostring(value or '');if fs.qtext~=value then fs.qtext=value;fs:SetText(value) end end
local function at(region,parent,x,y) region:ClearAllPoints();region:SetPoint('TOPLEFT',parent,'TOPLEFT',x,-y);return region end
local function text(parent,size,color,x,y,w,justify,wrap)
    local fs=S.Text(parent,size,color,justify);at(fs,parent,x,y);if w then fs:SetWidth(w) end
    if wrap then fs:SetWordWrap(true);fs:SetJustifyV('TOP') end
    return fs
end
local function button(parent,label,x,y,w,h,kind,fn)
    local b=S.Button(parent,label,w,h,kind);at(b,parent,x,y);b:SetScript('OnClick',fn);return b
end
local function enable(b,on) if on then b:Enable() else b:Disable() end end
local function gold(s) return '|c'..S.hex.gold..s..'|r' end
local function mint(s) return '|c'..S.hex.mint..s..'|r' end
local function red(s) return '|c'..S.hex.red..s..'|r' end
local function muted(s) return '|c'..S.hex.muted..s..'|r' end
local RULES='1. Quatre manches, chacun son tour, une carte par réponse : rouge ou noire, plus haute ou plus basse que la '
    ..'première, entre les deux premières ou en dehors, puis la famille. Bonne réponse : tu donnes 1 gorgée (5 pour la '
    ..'famille) au joueur de ton choix ; erreur : tu bois 1 gorgée. L’as est la plus forte ; une carte égale est une erreur '
    ..'au plus ou moins, et compte « dehors » au dedans ou dehors.\n\n'
    ..'2. La pyramide : 15 cartes retournées du bas vers le haut. Ligne du bas 1 gorgée, puis 2, 3, 4, et 5 au sommet. '
    ..'Une carte de même valeur dans ta main ? Pose-la et donne la valeur de la ligne. Tu peux garder une carte pour '
    ..'une ligne plus haute, mais chaque carte gardée compte pour le bus.\n\n'
    ..'3. Le bus : celui qui garde le plus de cartes (égalité : la plus haute carte, puis une carte tirée) refait les '
    ..'quatre questions d’affilée avec un paquet neuf. Chaque erreur : 1 gorgée et retour au début. Il descend après '
    ..'quatre bonnes réponses de suite, ou quand le paquet est vide.\n\n'
    ..'Personne n’est obligé de boire : les gorgées peuvent rester des points.'

-- Mise en page ---------------------------------------------------------------------------------------------------
local function header(f)
    U.title=text(f,18,C().gold,14,10);set(U.title,'Ride the Bus')
    U.subtitle=text(f,10,C().muted,14,33,330)
    U.phase=text(f,12,C().text,380,16,300,'CENTER')
    U.rulesButton=button(f,'Règles',PANEL_W-268,10,72,24,'ghost',function() U.showRules=not U.showRules;A.Refresh() end)
    U.sync=button(f,'Synchroniser',PANEL_W-190,10,100,24,'ghost',function() A.Sync() end)
    U.leave=button(f,'Quitter',PANEL_W-84,10,74,24,'danger',function() A.Close() end)
end
local function guildPanel(left)
    local g=CreateFrame('Frame',nil,left);g:SetAllPoints();U.guild=g
    local h=S.Heading(g,'Inviter la guilde');at(h,g,12,10)
    U.guildInfo=text(g,10,C().muted,12,28,LEFT_W-24)
    U.online=button(g,'En ligne',12,46,82,22,'ghost',function() U.onlineOnly=not U.onlineOnly;U.guildPage=1;A.Refresh() end)
    button(g,'Actualiser',LEFT_W-94,46,82,22,'ghost',function() if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end;A.Roster() end)
    U.members={}
    for i=1,GUILD_ROWS do
        local row=S.Row(g,LEFT_W-24,30);at(row,g,12,76+(i-1)*32)
        row.name=text(row,11,C().text,8,3,LEFT_W-36);row.sub=text(row,9,C().muted,8,17,LEFT_W-36)
        row:SetScript('OnClick',function(self)
            if self.member then local key=self.member.key or A.Key(self.member.name);U.selected[key]=not U.selected[key] or nil;A.Refresh() end
        end)
        U.members[i]=row
    end
    button(g,'<',12,82+GUILD_ROWS*32,32,20,'ghost',function() U.guildPage=math.max(1,U.guildPage-1);A.Refresh() end)
    U.guildPageLabel=text(g,10,C().muted,50,86+GUILD_ROWS*32,LEFT_W-100,'CENTER')
    button(g,'>',LEFT_W-44,82+GUILD_ROWS*32,32,20,'ghost',function() U.guildPage=math.min(U.guildPages or 1,U.guildPage+1);A.Refresh() end)
    U.invite=button(g,'Inviter la sélection',12,108+GUILD_ROWS*32,LEFT_W-24,24,'primary',function()
        if not A.state then A.Create(false) end -- pas encore de table : on la crée, puis on invite
        local sent=0
        for _,row in ipairs(A.roster) do
            local key=row.key or A.Key(row.name)
            if U.selected[key] and A.Invite(row.name) then sent=sent+1;U.selected[key]=nil end
        end
        A.Notice(sent..' invitation(s) envoyée(s).')
    end)
end
local function seatsPanel(left)
    local p=CreateFrame('Frame',nil,left);p:SetAllPoints();U.seats=p
    U.seatsTitle=S.Heading(p,'À la table');at(U.seatsTitle,p,12,10)
    U.players={}
    for i=1,8 do
        local row=S.Row(p,LEFT_W-20,38);at(row,p,10,30+(i-1)*40)
        row.name=text(row,12,C().text,8,5,LEFT_W-80);row.sub=text(row,9,C().muted,8,22,LEFT_W-30)
        row.badge=text(row,10,C().gold,LEFT_W-100,6,74,'RIGHT')
        row.give=button(row,'Donner',LEFT_W-80,7,56,22,'primary',function()
            local target=row.player;if not target then return end
            A.Act('give',target,IsShiftKeyDown and IsShiftKeyDown() and 1 or nil)
        end)
        U.players[i]=row
    end
    U.seatsHint=text(p,9,C().muted,12,354,LEFT_W-24,'LEFT',true);U.seatsHint:SetHeight(36)
end
local function questionView(felt)
    local v=CreateFrame('Frame',nil,felt);v:SetAllPoints();U.qview=v
    U.deck2=Cards.New(v,72,100);at(U.deck2,v,24,62);U.deck2:Set('back')
    U.reveal=Cards.New(v,72,100);at(U.reveal,v,20,58)
    U.deckCount=text(v,10,C().muted,10,164,92,'CENTER')
    U.revealText=text(v,10,C().text,10,180,92,'CENTER',true);U.revealText:SetHeight(40)
    U.slots,U.slotLabels={},{}
    for i=1,G.HAND do
        U.slots[i]=Cards.New(v,84,118);at(U.slots[i],v,128+(i-1)*100,56)
        U.slotLabels[i]=text(v,10,C().muted,128+(i-1)*100-8,180,100,'CENTER')
    end
    U.result=text(v,12,C().gold,120,200,420,'CENTER')
    U.choices={}
    for i=1,4 do
        local index=i
        U.choices[i]=button(v,'',0,232,104,28,'primary',function()
            local s=A.state;if not s then return end
            local step=s.phase=='bus' and s.busStep or s.round;local option=G.Options(step)[index]
            if option then A.Act('answer',option[1]) end
        end)
    end
    U.turnHint=text(v,10,C().muted,10,272,534,'CENTER')
end
local function pyramidView(felt)
    local v=CreateFrame('Frame',nil,felt);v:SetAllPoints();U.pview=v
    U.pyramid,U.rowValues={},{}
    local cx,index=180,0
    for row=1,5 do
        local y=50+(row-1)*44
        for col=1,row do
            index=index+1
            U.pyramid[index]=Cards.New(v,40,56);at(U.pyramid[index],v,cx-(row*46-6)/2+(col-1)*46,y)
        end
        U.rowValues[row]=text(v,11,C().gold,cx-(row*46-6)/2-40,y+20,30,'RIGHT');set(U.rowValues[row],'x'..(6-row))
    end
    U.current=Cards.New(v,96,134);at(U.current,v,388,50)
    U.currentText=text(v,11,C().text,330,192,212,'CENTER')
    U.plays=text(v,10,C().muted,330,212,212,'CENTER',true);U.plays:SetHeight(70)
end
local function lobbyView(felt)
    local v=CreateFrame('Frame',nil,felt);v:SetAllPoints();U.lview=v
    U.seatBoxes={}
    for i=1,8 do
        local b=S.Box(v,C().panel,C().line);b:SetSize(236,28);at(b,v,30+((i-1)%2)*258,62+math.floor((i-1)/2)*36)
        b.label=text(b,11,C().text,10,8,216);U.seatBoxes[i]=b
    end
    U.lobbyText=text(v,11,C().muted,30,214,494,'CENTER',true);U.lobbyText:SetHeight(60)
end
local function welcomeView(felt)
    local v=CreateFrame('Frame',nil,felt);v:SetAllPoints();U.wview=v
    local fan={{'back',30,70},{52,92,58},{11+13*0,154,70}}
    for _,c in ipairs(fan) do local card=Cards.New(v,84,118);at(card,v,c[2],c[3]);card:Set(c[1]) end
    local pitch=text(v,14,C().text,280,64,250,'LEFT',true);pitch:SetHeight(60)
    set(pitch,'Le jeu de cartes de la guilde, de 2 à 8 joueurs, synchronisé entre vous.')
    local how=text(v,10,C().muted,280,120,250,'LEFT',true);how:SetHeight(60)
    set(how,'Crée une table, invite des membres connectés (ils doivent avoir Ride the Bus '..A.version..'), puis lance la partie. La démo se joue seule contre deux joueurs automatiques.')
    U.create=button(v,'Créer une table',280,196,150,28,'primary',function() A.Create(false) end)
    U.demo=button(v,'Démo locale',440,196,90,28,'ghost',function() A.Create(true) end)
end
local function finishedView(felt)
    local v=CreateFrame('Frame',nil,felt);v:SetAllPoints();U.fview=v
    U.podium={}
    for i=1,8 do U.podium[i]=text(v,11,C().text,120,74+(i-1)*22,314) end
end
local function bottom(f)
    U.handTitle=S.Heading(f,'Ta main');at(U.handTitle,f,FELT_X,FELT_H+58)
    U.hand={}
    for i=1,G.HAND do
        local slot=i
        U.hand[i]=Cards.New(f,50,70,function() A.PlayFromHand(slot) end);at(U.hand[i],f,FELT_X+(i-1)*56,FELT_H+74)
    end
    U.primary=button(f,'',PANEL_W-330,FELT_H+56,156,26,'primary',function() if U.primary.action then U.primary.action() end end)
    U.secondary=button(f,'',PANEL_W-166,FELT_H+56,156,26,'ghost',function() if U.secondary.action then U.secondary.action() end end)
    U.log=text(f,10,C().muted,PANEL_W-330,FELT_H+90,320,'LEFT',true);U.log:SetHeight(56)
    U.notice=text(f,11,C().gold,FELT_X,PANEL_H-30,FELT_W,'LEFT')
end
local function popup(f)
    local p=S.Box(f,C().bg,C().gold);p:SetSize(380,150);p:SetPoint('CENTER',f,'CENTER',0,20)
    if p.SetFrameStrata then p:SetFrameStrata('DIALOG') end
    U.popup=p
    local h=S.Heading(p,'Invitation à Ride the Bus');at(h,p,18,16)
    U.invitationText=text(p,12,C().text,18,40,344,'LEFT',true);U.invitationText:SetHeight(56)
    button(p,'Accepter',18,108,166,28,'primary',function() A.Accept();A.Refresh() end)
    button(p,'Refuser',196,108,166,28,'ghost',function() A.Decline() end)
    p:Hide()
end
local function create(parent)
    S=Quintessence.Style
    local f=CreateFrame('Frame',nil,parent);f:SetSize(PANEL_W,PANEL_H);U.frame=f
    header(f)
    local left=S.Box(f,C().panel,C().line);left:SetSize(LEFT_W,PANEL_H-58);at(left,f,10,46);U.left=left
    guildPanel(left);seatsPanel(left)
    local felt=S.Box(f,C().panel,C().line);felt:SetSize(FELT_W,FELT_H);at(felt,f,FELT_X,46);U.felt=felt
    local cloth=felt:CreateTexture(nil,'BACKGROUND',nil,1);cloth:SetTexture('Interface\\AddOns\\'..(addonName or 'quinte-ride')..'\\Media\\Felt')
    cloth:SetPoint('TOPLEFT',2,-2);cloth:SetPoint('BOTTOMRIGHT',-2,2)
    -- Scène de 554 × 300 centrée sur le tapis : les cartes gardent leur taille et leur place les unes par rapport aux autres
    local stage=CreateFrame('Frame',nil,felt);stage:SetSize(STAGE_W,STAGE_H)
    at(stage,felt,math.floor((FELT_W-STAGE_W)/2),math.floor((FELT_H-STAGE_H)/2));U.stage=stage
    U.question=text(stage,15,C().text,12,10,530,'CENTER')
    U.sub=text(stage,11,C().muted,12,32,530,'CENTER')
    questionView(stage);pyramidView(stage);lobbyView(stage);welcomeView(stage);finishedView(stage)
    local rules=S.Box(felt,C().bg,C().line);rules:SetPoint('TOPLEFT',2,-2);rules:SetPoint('BOTTOMRIGHT',-2,2);U.rules=rules
    if rules.SetFrameLevel and felt.GetFrameLevel then rules:SetFrameLevel((felt:GetFrameLevel() or 1)+20) end
    local rh=S.Heading(rules,'Les règles');at(rh,rules,16,12)
    local rt=text(rules,11,C().text,16,32,FELT_W-36,'LEFT',true);rt:SetHeight(FELT_H-44);set(rt,RULES)
    rules:Hide()
    bottom(f);popup(f)
    return f
end

-- Actions de l'interface ----------------------------------------------------------------------------------------
--- Clic sur une carte de sa main : la poser sur la carte de pyramide retournée si elle a la même valeur.
function A.PlayFromHand(slot)
    local s=A.state;if not s or s.phase~='pyramid' then return end
    local me=G.Player(s,A.Self());local card=me and me.hand[slot]
    local current=G.PyramidCard(s)
    if not card or card==0 or not current then return end
    if G.Rank(card)~=G.Rank(current) then return A.Notice('Il faut une carte de même valeur que la carte de la pyramide.') end
    A.Act('play',nil,slot)
end

-- Affichage -----------------------------------------------------------------------------------------------------
local function show(frame,on) if on then frame:Show() else frame:Hide() end end
local function action(b,label,fn,on)
    if not label then b:Hide();b.action=nil;return end
    b:SetLabel(label);b.action=fn;enable(b,on~=false);b:Show()
end
local function refreshGuild(s,host)
    local selfKey=A.Key(A.Self())
    local list={}
    for _,row in ipairs(A.roster) do
        if (not U.onlineOnly or row.online) and (row.key or A.Key(A.Name(row.name)))~=selfKey then list[#list+1]=row end
    end
    U.guildPages=math.max(1,math.ceil(#list/GUILD_ROWS));U.guildPage=math.min(U.guildPage,U.guildPages)
    local selected=0;for _ in pairs(U.selected) do selected=selected+1 end
    set(U.guildInfo,#list..' membre(s) · '..selected..' choisi(s) · 8 places')
    U.online:SetLabel(U.onlineOnly and 'En ligne' or 'Tous');set(U.guildPageLabel,U.guildPage..' / '..U.guildPages)
    local now=GetServerTime()
    for i,row in ipairs(U.members) do
        local m=list[(U.guildPage-1)*GUILD_ROWS+i];row.member=m
        if m then
            local key=m.key or A.Key(m.name);local pending=A.invited[key];local seated=s and G.Player(s,m.name)
            row:SetSelected(U.selected[key] and true or false)
            set(row.name,A.Safe(m.name))
            set(row.sub,seated and mint('À la table') or pending and pending.expires>now and gold('Invitation envoyée')
                or m.online and ('En ligne'..(m.class and m.class~='' and ' · '..m.class or '')) or 'Hors ligne')
            row:Show()
        else row:Hide() end
    end
    enable(U.invite,selected>0 and (not s and not A.connection or host and s.phase=='lobby' and not s.demo))
end
local function refreshSeats(s)
    set(U.seatsTitle,S.IsClassic() and ('À la table ('..#s.players..'/8)') or ('À LA TABLE · '..#s.players..'/8'))
    local active=G.Active(s);local mine=G.PendingGift(s,A.Self())
    for i,row in ipairs(U.players) do
        local p=s.players[i];row.player=p and p.name
        if p then
            local me=A.Same(p.name,A.Self());local owing=G.PendingGift(s,p.name)
            row:SetSelected(active and A.Same(active.name,p.name) or false)
            set(row.name,A.Safe(p.name)..(me and muted(' (toi)') or '')..(A.Same(p.name,s.host) and muted(' · hôte') or ''))
            local left=s.phase~='lobby' and s.phase~='finished' and (' · '..G.Left(p)..' carte(s)') or ''
            set(row.sub,'bu '..p.taken..' · donné '..p.given..left)
            set(row.badge,owing and ('+'..owing.amount) or (s.phase=='bus' and s.busPlayer==i and 'BUS') or '')
            local canGive=mine and not me and not A.pendingAction
            show(row.give,canGive);show(row.badge,not canGive)
            row:Show()
        else row:Hide() end
    end
    set(U.seatsHint,mine and gold('Tu as '..mine.amount..' gorgée(s) à donner : bouton Donner. Maj+clic : une seule.')
        or (s.gifts[1] and (A.Safe(s.gifts[1].from)..' choisit à qui donner '..s.gifts[1].amount..' gorgée(s).')) or '')
end
local function refreshQuestion(s,host)
    local bus=s.phase=='bus';local step=bus and s.busStep or s.round
    local active=G.Active(s);local r=s.result
    local mineTurn=active and A.Same(active.name,A.Self())
    set(U.question,G.Question(step))
    set(U.sub,bus and ('Le bus · '..A.Safe(active.name)..' · essai '..s.attempt..' · étape '..step..' / 4')
        or ('Manche '..s.round..' / 4 · '..A.Safe(active.name)..(mineTurn and ' : à toi !' or ' répond')))
    -- Dernière carte tirée, retournée sur le paquet
    local fresh=r and r.n~=U.lastReveal;U.lastReveal=r and r.n
    if r then
        U.reveal:Set(r.card,fresh);U.reveal:SetGlow(r.correct and 'mint' or 'red')
        set(U.revealText,A.Safe(r.name)..'\n'..(r.correct and mint('gagné') or red(r.passed and 'passé' or 'raté')))
    else U.reveal:Set('back');U.reveal:SetGlow(nil);set(U.revealText,'') end
    set(U.deckCount,s.deckLeft..' carte(s)')
    -- Les quatre places du joueur actif (ou la rangée du bus ; rangée ratée montrée jusqu'à la réponse suivante)
    local hand=bus and s.busHand or (active and active.hand) or {}
    local failed=bus and r and r.bus and not r.correct and not hand[1] and r.hand
    for i=1,G.HAND do
        local card=failed and failed[i] or hand[i]
        U.slots[i]:Set(card,fresh and r and r.step==i and A.Same(r.name,active.name) and not failed)
        U.slots[i]:SetDim(failed and true or false)
        if failed and i==r.step then U.slots[i]:SetGlow('red')
        elseif not failed and i==step and not (card and card>0) then U.slots[i]:SetGlow('mint',true)
        else U.slots[i]:SetGlow(nil) end
        set(U.slotLabels[i],i==step and gold(G.STEPS[i]) or G.STEPS[i])
    end
    -- Résultat
    if r then
        local what=A.Safe(r.name)..' : '..G.CardName(r.card)
        if r.correct and r.bus then set(U.result,mint(what..' — gagné !'))
        elseif r.correct then set(U.result,mint(what..' — gagné, donne '..r.give..' gorgée(s).'))
        else set(U.result,red(what..(r.passed and ' — tour passé, boit ' or ' — raté, boit ')..r.drink..(r.bus and ' et recommence.' or '.'))) end
    else set(U.result,bus and muted('Quatre bonnes réponses de suite pour descendre du bus.') or '') end
    -- Choix
    local options=G.Options(step);local can=mineTurn and not s.gifts[1] and not A.pendingAction
    local total=#options*104+(#options-1)*8;local x=(554-total)/2
    for i,b in ipairs(U.choices) do
        local o=options[i]
        if o then b:SetLabel(o[2]);at(b,U.qview,x+(i-1)*112,232);enable(b,can);b:Show() else b:Hide() end
    end
    set(U.turnHint,s.gifts[1] and gold('En attente des dons de '..A.Safe(s.gifts[1].from)..'.')
        or mineTurn and (A.pendingAction and 'Réponse envoyée…' or 'Choisis ta réponse.') or ('Attends : '..A.Safe(active.name)..' réfléchit.'))
    if host then
        if s.gifts[1] then action(U.secondary,'Passer les dons',function() A.Act('pass') end)
        elseif bus then action(U.secondary,'Arrêter le bus',function() A.Act('pass') end)
        else action(U.secondary,'Passer ce tour',function() A.Act('pass') end) end
    end
end
local function refreshPyramid(s,host)
    local current=G.PyramidCard(s)
    local fresh=s.pyramidPos~=U.lastPos;U.lastPos=s.pyramidPos
    set(U.question,s.pyramidIndex==0 and 'La pyramide' or ('Carte '..s.pyramidIndex..' / 15 : '..s.pyramidRow..' gorgée(s) à donner'))
    set(U.sub,s.pyramidIndex==0 and 'Quinze cartes, retournées du bas vers le haut.' or 'Une carte de même valeur dans ta main ? Clique-la pour la poser.')
    for i,card in ipairs(U.pyramid) do
        local value=s.pyramid[i];card:Set(value and value>0 and value or 'back',fresh and i==s.pyramidPos)
        card:SetGlow(i==s.pyramidPos and 'gold' or nil);card:SetDim(value and i~=s.pyramidPos)
    end
    if current then
        U.current:Set(current,fresh);U.current:SetGlow('gold')
        set(U.currentText,G.CardName(current)..' · '..s.pyramidRow..' gorgée(s)')
        local lines={};for _,p in ipairs(s.plays) do lines[#lines+1]=A.Safe(p.name)..' pose '..G.CardName(p.card) end
        set(U.plays,#lines>0 and table.concat(lines,'\n') or 'Personne n’a encore posé.')
    else
        U.current:Set('back');U.current:SetGlow(nil);set(U.currentText,'');set(U.plays,host and 'Retourne la première carte.' or 'L’hôte retourne la première carte.')
    end
    if host then
        action(U.primary,s.pyramidIndex==15 and 'Monter dans le bus' or 'Retourner la carte',function() A.Act('next') end,not s.gifts[1])
        if s.gifts[1] then action(U.secondary,'Passer les dons',function() A.Act('pass') end) end
    end
end
local function refreshLobby(s,host)
    set(U.question,host and 'Invite des membres, puis lance la partie' or 'En attente de l’hôte')
    set(U.sub,(s.games>1 and ('Partie '..s.games..' · ') or '')..#s.players..' / 8 joueurs à la table')
    local now=GetServerTime();local waiting={}
    for _,entry in pairs(A.invited or {}) do if entry.expires>now then waiting[#waiting+1]=entry.name end end
    for i,b in ipairs(U.seatBoxes) do
        local p=s.players[i]
        if p then set(b.label,mint(A.Safe(p.name))..(A.Same(p.name,s.host) and muted(' · hôte') or ''))
        elseif waiting[i-#s.players] then set(b.label,gold('Invité : '..A.Safe(waiting[i-#s.players])))
        else set(b.label,muted('Place libre')) end
    end
    set(U.lobbyText,host and 'Choisis des membres à gauche puis « Inviter la sélection ». Ils doivent accepter dans leur fenêtre (90 s). Deux joueurs au moins.'
        or 'Tu es à la table. La partie commence quand l’hôte la lance.')
    if host then action(U.primary,'Lancer la partie',function() A.Act('start') end,#s.players>=2) end
end
local function refreshFinished(s,host)
    set(U.question,s.finishedReason or 'Partie terminée');set(U.sub,'Bilan de la table')
    local order={};for i,p in ipairs(s.players) do order[i]=p end
    table.sort(order,function(a,b) if a.taken~=b.taken then return a.taken>b.taken end;return a.given>b.given end)
    for i,line in ipairs(U.podium) do
        local p=order[i]
        if p then set(line,(i==1 and gold('A le plus bu  ') or '')..A.Safe(p.name)..muted('  ·  bu '..p.taken..'  ·  donné '..p.given));line:Show()
        else line:Hide() end
    end
    if host then action(U.primary,'Rejouer avec la table',function() A.Act('again') end) end
end
local function refreshHand(s)
    local me=s and G.Player(s,A.Self());local current=s and s.phase=='pyramid' and G.PyramidCard(s)
    for i,card in ipairs(U.hand) do
        local value=me and me.hand[i]
        card:Set(value);card:SetDim(false)
        local match=current and value and value>0 and G.Rank(value)==G.Rank(current) and not A.pendingAction
        card.clickable=match and true or false
        card:SetGlow(match and 'mint' or nil,match)
        show(card,s~=nil and s.phase~='lobby')
    end
    show(U.handTitle,s~=nil and s.phase~='lobby')
end
function A.Visible() return U.frame~=nil and U.frame:IsVisible() end
function A.ShowInvitation() A.Show();if U.popup then U.popup:Show() end end
function A.Refresh()
    if not U.frame or not U.frame:IsVisible() then return end
    if A.rosterDirty then A.Roster();return end -- A.Roster rappelle A.Refresh avec la liste à jour
    local s=A.state;local host=A.IsHost()
    set(U.subtitle,s and ((s.demo and 'Démo locale' or ('Table de '..A.Safe(s.host)))..' · v'..A.version) or ('Jeu de cartes de la guilde · v'..A.version))
    local phases={lobby='Salon',question='Manche '..(s and s.round or 1)..' / 4',pyramid='La pyramide',bus='Le bus',finished='Partie terminée'}
    set(U.phase,s and phases[s.phase] or (A.connection and 'Connexion à la table…' or ''))
    set(U.notice,A.Safe(A.notice or ''))
    enable(U.sync,s~=nil or A.connection~=nil);show(U.leave,s~=nil or A.connection~=nil)
    U.rulesButton:SetActive(U.showRules);show(U.rules,U.showRules)
    -- Panneau de gauche : la guilde (sans table, ou salon de l'hôte), sinon les joueurs
    local guildSide=not s or (host and s.phase=='lobby' and not s.demo)
    show(U.guild,guildSide);show(U.seats,not guildSide)
    if guildSide then refreshGuild(s,host) else refreshSeats(s) end
    for _,v in ipairs({U.qview,U.pview,U.lview,U.wview,U.fview}) do v:Hide() end
    action(U.primary,nil);action(U.secondary,nil)
    if not s then
        set(U.question,A.connection and 'Connexion à la table…' or 'Ride the Bus');set(U.sub,'Rouge ou noire, plus ou moins, dedans ou dehors, la famille… puis la pyramide et le bus.')
        U.wview:Show();enable(U.create,not A.connection);enable(U.demo,not A.connection)
    elseif s.phase=='lobby' then U.lview:Show();refreshLobby(s,host)
    elseif s.phase=='question' or s.phase=='bus' then U.qview:Show();refreshQuestion(s,host)
    elseif s.phase=='pyramid' then U.pview:Show();refreshPyramid(s,host)
    else U.fview:Show();refreshFinished(s,host) end
    refreshHand(s)
    local recent={};if s then for i=1,math.min(4,#(A.journal or {})) do recent[#recent+1]=A.Safe(A.journal[i]) end end
    set(U.log,table.concat(recent,'\n'))
    if A.incoming then
        set(U.invitationText,A.Safe(A.incoming.host)..' t’invite à sa table. Accepte pour jouer ; chacun doit avoir Ride the Bus '..A.version..'.')
        U.popup:Show()
    else U.popup:Hide() end
end
function A.Show() Quintessence.UI.Open('ride') end
Quintessence:RegisterModule({
    id='ride',title='Ride the Bus',order=85,section='guilde',icon='Interface\\Icons\\INV_Drink_05',version=A.version,width=PANEL_W,height=PANEL_H,
    create=function(parent) local f=create(parent);f:Hide();return f end,
    refresh=function() A.Refresh() end,
    summary=function()
        if A.incoming then return '|c'..Quintessence.Style.hex.gold..'Invitation de '..A.Safe(A.incoming.host)..'|r' end
        if A.state then return 'Partie en cours ('..#A.state.players..' joueurs)' end
        return 'Jeu de cartes entre membres de la guilde (2 à 8 joueurs)'
    end,
})
SLASH_QUINTERIDE1='/quinteride';SLASH_QUINTERIDE2='/qride'
SlashCmdList.QUINTERIDE=function(message)
    A.Show()
    message=(message or ''):lower()
    if message=='demo' or message=='démo' then A.Create(true)
    elseif message=='creer' or message=='créer' then A.Create(false)
    elseif message=='quitter' then A.Close()
    elseif message=='sync' then A.Sync()
    elseif message=='regles' or message=='règles' then U.showRules=true;A.Refresh() end
end
