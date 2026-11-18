local addonName, A = ...
local G=A.Game
-- Réseau de Ride the Bus : messages temps réel via le conteneur Quintessence (canal « ride », file prioritaire
-- et bridée commune à tous les modules). Les états de partie sont envoyés en privé à chaque joueur de la table.
A.roster,A.invited={}, {}
local comm
local function refresh() if A.Refresh then A.Refresh() end end
function A.Notice(text) A.notice=text;refresh() end
function A.IsHost() return A.state and A.Same(A.state.host,A.Self()) end
-- Clé de chaque ligne calculée une fois (le tri en recalculait deux par comparaison : ~9 000 pour 500 membres)
-- et index par clé pour retrouver un membre sans reparcourir toute la liste.
function A.Roster()
    local rows={}
    for i=1,GetNumGuildMembers() do
        local name,_,_,level,class,_,_,_,online,_,_,_,_,mobile=GetGuildRosterInfo(i)
        if name then local n=A.Name(name);rows[#rows+1]={name=n,key=A.Key(n),online=online and not mobile,level=level,class=class} end
    end
    table.sort(rows,function(a,b) if a.online~=b.online then return a.online end;return a.key<b.key end)
    local index={};for _,row in ipairs(rows) do if not index[row.key] then index[row.key]=row end end
    A.roster,A.rosterIndex,A.rosterIndexFor=rows,index,rows;A.rosterAt=GetTime();A.rosterDirty=false;refresh();return rows
end
local function find(name)
    local key=A.Key(A.Name(name))
    if A.rosterIndexFor==A.roster then return A.rosterIndex[key] end
    for _,row in ipairs(A.roster) do if (row.key or A.Key(A.Name(row.name)))==key then return row end end
end
-- Membre de la guilde ? La liste est souvent vide juste après la connexion, ou ne connaît pas encore un membre
-- qui vient d'arriver : on la relit (au plus toutes les 5 s) avant de répondre non. Relue aussi si elle a changé
-- pendant que la fenêtre était fermée (relecture différée, voir GUILD_ROSTER_UPDATE).
function A.Member(name,online)
    if A.rosterDirty then A.Roster() end
    local row=find(name)
    if not row and GetTime()-(A.rosterAt or -100)>5 then A.Roster();row=find(name) end
    return row~=nil and (not online or row.online)
end
--- Envoie un message de jeu. Retourne true si le message est parti, false sinon (avec un avertissement).
function A.Send(kind,sid,value,target)
    if not comm then A.Notice('Addon Quintessence absent : le jeu en réseau est indisponible.');return false end
    local state=Quintessence.sync and Quintessence.sync:Status()
    if not state or not state.enabled then A.Notice('La synchro Quintessence est coupée (/quinte sync on) : le jeu en réseau est indisponible.');return false end
    return comm:Send({k=kind,s=sid,v=value},target)~=false
end
-- Message à tous les autres joueurs de la table, en privé
local function toTable(kind,sid,value)
    for _,player in ipairs(A.game and A.game.players or {}) do
        if not A.Same(player.name,A.Self()) then A.Send(kind,sid,value,player.name) end
    end
end
-- Journal local (6 lignes) : écrit d'après les changements de l'état, jamais envoyé
local function record(state)
    A.journal=A.journal or {}
    for _,line in ipairs(G.Journal(A.state,state)) do table.insert(A.journal,1,line) end
    while #A.journal>6 do table.remove(A.journal) end
    A.state=state
end
function A.Broadcast()
    if not A.game then return end
    A.game.seq=A.game.seq+1;record(G.Public(A.game));refresh()
    if A.game.demo then A.DemoTick() else toTable('S',A.game.id,A.state) end
end
function A.Create(demo)
    if A.state or A.connection then return A.Notice('Quitte le salon actuel avant d’en créer un autre.') end
    if not demo and not IsInGuild() then return A.Notice('Il faut être dans une guilde. La démo locale reste disponible.') end
    local id=tostring(GetServerTime())..'-'..tostring(math.random(100000,999999))
    A.game=G.New(id,A.Self(),demo);A.state=nil;A.journal={};record(G.Public(A.game));A.invited={};A.notice=nil
    if demo then G.Add(A.game,'Azur Demo');G.Add(A.game,'Nacre Demo') end
    A.Broadcast()
end
function A.Invite(name)
    if not A.IsHost() or not A.game or A.game.demo or A.game.phase~='lobby' then return false end
    name=A.Name(name)
    -- Le statut « en ligne » de la liste peut dater : on invite tout membre, sans réponse l'invitation expire.
    if not A.Member(name) or A.Same(name,A.Self()) or G.Player(A.game,name) then return false end
    local now=GetServerTime();local count=#A.game.players
    for key,entry in pairs(A.invited) do
        if entry.expires>now then count=count+1 else A.invited[key]=nil end
    end
    local key=A.Key(name)
    if A.invited[key] and A.invited[key].expires>now then return false end
    if count>=A.MAX_PLAYERS then A.Notice('Huit places au maximum, invitations en attente comprises.');return false end
    local token=tostring(math.random(10000000,99999999))
    local entry={name=name,token=token,expires=now+90}
    A.invited[key]=entry
    if not A.Send('I',A.game.id,{token=token,expires=now+90,protocol=A.protocol,version=A.version},name) then A.invited[key]=nil;return false end
    -- Sans réponse ni arrivée au bout de 90 s : on le dit, avec la piste la plus probable
    C_Timer.After(91,function()
        if A.invited[key]==entry then
            A.invited[key]=nil
            A.Notice('Pas de réponse de '..name..' : vérifie qu’il est en ligne avec Quinte-ride '..A.version..' (/quinte test pour voir qui reçoit).')
        end
    end)
    A.Notice('Invitation envoyée à '..name..' (90 secondes).');return true
end
-- Salon que l'on a créé et où l'on est seul : il ne compte pas, une invitation peut le remplacer
local function aloneInLobby()
    return A.IsHost() and A.game and A.game.phase=='lobby' and #A.game.players<=1 and not next(A.invited)
end
function A.Accept()
    local invite=A.incoming
    if not invite or invite.expires<GetServerTime() then A.incoming=nil;return A.Notice('Invitation expirée.') end
    if aloneInLobby() then A.game,A.state=nil,nil end
    if A.state or A.connection then return A.Notice('Quitte d’abord la partie actuelle.') end
    A.connection={host=invite.host,id=invite.id,accepted=false,token=invite.token};A.incoming=nil;A.journal={}
    A.Send('J',invite.id,{token=invite.token},invite.host)
    A.Notice('Connexion au salon…')
end
function A.Decline()
    if A.incoming then A.Send('N',A.incoming.id,{},A.incoming.host) end
    A.incoming=nil;refresh()
end
function A.Close(reason)
    if A.IsHost() and A.game and not A.game.demo then
        toTable('E',A.game.id,{reason=reason or 'L’hôte a fermé le salon.'})
    elseif A.connection then A.Send('L',A.connection.id,{},A.connection.host) end
    A.game,A.state,A.connection,A.pendingAction,A.demoPending=nil,nil,nil,nil,nil;A.invited={}
    A.Notice(reason or 'Tu as quitté le salon.')
end
function A.Apply(sender,request)
    local g=A.game
    if not g or type(request)~='table' or type(request.kind)~='string' then return false end
    local host=A.Same(sender,g.host);local kind=request.kind;local ok,err=false,'Action refusée.'
    if kind=='start' and host then ok,err=G.Start(g)
    elseif kind=='next' and host then ok,err=G.Next(g)
    elseif kind=='pass' and host then ok,err=G.Pass(g)
    elseif kind=='again' and host then ok,err=G.Again(g)
    elseif kind=='answer' then ok,err=G.Answer(g,sender,request.choice,request.token)
    elseif kind=='play' then ok,err=G.Play(g,sender,request.slot,request.token)
    elseif kind=='give' then ok,err=G.Give(g,sender,request.choice,request.slot) end
    if ok then A.Broadcast()
    elseif A.Same(sender,A.Self()) then A.Notice(err or 'Action refusée.')
    elseif not g.demo then A.Send('F',g.id,{reason=err or 'Action refusée.'},sender) end
    return ok
end
--- Action du joueur : appliquée tout de suite chez l'hôte, sinon envoyée à l'hôte (une à la fois, 12 s au plus).
--- give : choice = joueur qui reçoit, slot = nombre de gorgées (toutes si nil). play : slot = carte de la main.
function A.Act(kind,choice,slot)
    local s=A.state;if not s then return end
    if A.IsHost() then return A.Apply(A.Self(),{kind=kind,choice=choice,slot=slot,token=s.action}) end
    if not A.connection or A.pendingAction then return end
    local marker={seq=s.seq};A.pendingAction=marker
    A.Send('A',s.id,{kind=kind,choice=choice,slot=slot,token=s.action},A.connection.host);refresh()
    C_Timer.After(12,function()
        if A.pendingAction==marker then A.pendingAction=nil;A.Notice('Réponse non confirmée : utilise Synchroniser avant de rejouer.') end
    end)
end
-- Démo locale : les deux joueurs de démonstration jouent seuls (réponse, cartes posées, dons), une action par seconde.
local function bot(g,name) return g.demo and not A.Same(name,g.host) end
local function guess(step,hand)
    if step==2 then return G.Rank(hand[1])<8 and 'higher' or 'lower' end
    if step==3 then return math.abs(G.Rank(hand[1])-G.Rank(hand[2]))>6 and 'inside' or 'outside' end
    local options=G.Options(step);return options[math.random(#options)][1]
end
function A.DemoTick()
    local g=A.game;if not g or not g.demo or A.demoPending then return end
    local function later(fn)
        local marker={};A.demoPending=marker
        C_Timer.After(1.1,function()
            if A.demoPending~=marker then return end
            A.demoPending=nil;if A.game==g then fn();A.DemoTick() end
        end)
    end
    for _,gift in ipairs(g.gifts) do
        if bot(g,gift.from) then
            return later(function()
                local others={};for _,p in ipairs(g.players) do if not A.Same(p.name,gift.from) then others[#others+1]=p.name end end
                A.Apply(gift.from,{kind='give',choice=others[math.random(#others)]})
            end)
        end
    end
    if g.phase=='pyramid' and g.pyramidIndex>0 then
        local rank=G.Rank(G.PyramidCard(g))
        for _,p in ipairs(g.players) do
            for slot=1,G.HAND do
                local card=p.hand[slot]
                if bot(g,p.name) and card and card>0 and G.Rank(card)==rank then
                    return later(function() A.Apply(p.name,{kind='play',slot=slot,token=g.action}) end)
                end
            end
        end
    end
    local active=G.Active(g)
    if active and bot(g,active.name) and not g.gifts[1] then
        return later(function()
            local now=G.Active(g);if not now or now~=active then return end
            local step=g.phase=='bus' and g.busStep or g.round
            A.Apply(active.name,{kind='answer',choice=guess(step,g.phase=='bus' and g.busHand or active.hand),token=g.action})
        end)
    end
end
function A.Sync()
    if A.IsHost() then A.Broadcast()
    elseif A.connection then
        A.Send(A.connection.accepted and 'Q' or 'J',A.connection.id,A.connection.accepted and {} or {token=A.connection.token},A.connection.host)
        A.Notice('Synchronisation demandée…') end
end
local function receive(kind,sid,data,sender)
    if kind=='I' then
        if type(data)~='table' then return end
        -- Refus expliqués à l'hôte (au lieu d'une invitation perdue sans rien dire)
        if data.protocol~=A.protocol then
            A.Notice('Invitation de '..sender..' ignorée : il a Quinte-ride '..A.Safe(tostring(data.version or '?'):sub(1,12))..', toi '..A.version..'. Il faut la même version.')
            A.Send('N',sid,{reason='version',version=A.version,protocol=A.protocol},sender);return
        end
        if A.connection or (A.state and not aloneInLobby()) then
            A.Notice('Invitation de '..sender..' refusée : tu es déjà dans une partie.')
            A.Send('N',sid,{reason='busy'},sender);return
        end
        if type(data.token)~='string' or #data.token>40 or type(data.expires)~='number' then return end
        local now=GetServerTime();if data.expires<now or data.expires>now+120 then return end
        A.incoming={host=sender,id=sid,token=data.token,expires=data.expires}
        local current=A.incoming
        -- Aussi dans le chat, au cas où la fenêtre ne s'ouvre pas (combat, écran de chargement…)
        if Quintessence.Print then Quintessence.Print('Ride the Bus : '..A.Safe(sender)..' t’invite à une partie (90 s). /qride pour répondre.') end
        if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound,SOUNDKIT.READY_CHECK) end
        C_Timer.After(math.max(0,data.expires-now),function() if A.incoming==current then A.incoming=nil;refresh() end end)
        if A.ShowInvitation then A.ShowInvitation() end;refresh();return
    end
    if kind=='S' and A.connection and sid==A.connection.id and A.Same(sender,A.connection.host) then
        if not G.Valid(data) or data.id~=sid or not A.Same(data.host,sender) or not G.Player(data,A.Self()) then return end
        if A.state and data.seq<=A.state.seq then return end
        record(data);A.connection.accepted=true;A.pendingAction=nil;A.notice=nil;refresh();return
    end
    if kind=='E' and A.connection and sid==A.connection.id and A.Same(sender,A.connection.host) then
        A.game,A.state,A.connection,A.pendingAction=nil,nil,nil,nil
        A.Notice(type(data.reason)=='string' and data.reason:sub(1,200) or 'Salon fermé.');return
    end
    if kind=='F' and A.connection and sid==A.connection.id and A.Same(sender,A.connection.host) then
        A.pendingAction=nil;A.Notice(type(data.reason)=='string' and data.reason:sub(1,200) or 'Action refusée.');return
    end
    local g=A.game
    if not g or not A.IsHost() or sid~=g.id then return end
    if kind=='J' then
        if G.Player(g,sender) then A.Broadcast();return end -- Join acknowledgement may have been lost.
        local pending=A.invited[A.Key(sender)]
        if not pending or pending.expires<GetServerTime() or pending.token~=data.token or not A.Member(sender) then return end
        if G.Add(g,sender) then A.invited[A.Key(sender)]=nil;A.Broadcast()
        else A.Send('E',g.id,{reason='Le salon a déjà démarré ou est complet.'},sender) end
    elseif kind=='N' or kind=='L' and not G.Player(g,sender) then
        A.invited[A.Key(sender)]=nil
        local reason=type(data)=='table' and data.reason
        if reason=='version' then A.Notice(sender..' a Quinte-ride '..A.Safe(tostring(data.version or '?'):sub(1,12))..', toi '..A.version..' : il faut la même version pour jouer.')
        elseif reason=='busy' then A.Notice(sender..' est déjà dans une autre partie.')
        elseif kind=='N' then A.Notice(sender..' a refusé l’invitation.')
        else refresh() end
    elseif G.Player(g,sender) then
        if kind=='A' then A.Apply(sender,data)
        elseif kind=='Q' then A.Broadcast()
        elseif kind=='L' then
            if g.phase=='lobby' then G.Remove(g,sender);A.Broadcast()
            else A.Close('Partie interrompue : '..sender..' a quitté le salon.') end
        end
    end
end
-- Message reçu du canal « ride » (déjà décodé par le conteneur, expéditeur membre de la guilde)
function A.OnMessage(data,sender,channel)
    if type(data)~='table' or type(data.k)~='string' or #data.k~=1 or type(data.s)~='string' or #data.s>80 or type(data.v)~='table' then return end
    sender=A.Name(sender);if not sender or A.Same(sender,A.Self()) then return end
    local kind,sid=data.k,data.s
    -- Admission : invitations de la guilde, notre hôte, ou les invités/joueurs de notre propre salon
    local allowed=(kind=='I' and channel=='WHISPER' and A.Member(sender))
        or (A.connection and sid==A.connection.id and A.Same(sender,A.connection.host) and (kind=='S' or kind=='E' or kind=='F'))
        or (A.game and sid==A.game.id and channel=='WHISPER' and (A.invited[A.Key(sender)] or G.Player(A.game,sender)))
    if allowed then receive(kind,sid,data.v,sender) end
end
comm=Quintessence:RegisterChannel('ride',function(data,sender,channel) A.OnMessage(data,sender,channel) end)
local rosterPending=false
local frame=CreateFrame('Frame')
for _,event in ipairs({'ADDON_LOADED','PLAYER_LOGIN','GUILD_ROSTER_UPDATE'}) do frame:RegisterEvent(event) end
frame:SetScript('OnEvent',function(_,event,name)
    if event=='ADDON_LOADED' then
        if name~=addonName then return end
        if type(QuinteRideDB)~='table' then QuinteRideDB={} end
        QuinteRideDB.version=1
    elseif event=='PLAYER_LOGIN' then if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end;A.Roster()
    elseif event=='GUILD_ROSTER_UPDATE' and not rosterPending then
        -- Fenêtre fermée et aucune partie : la liste n'est relue qu'au besoin (ouverture, invitation reçue…) au lieu de
        -- reconstruire et trier toute la guilde à chaque mise à jour, toute la session
        if not (A.Visible and A.Visible()) and not A.game and not A.connection and not A.incoming then A.rosterDirty=true;return end
        -- Relecture regroupée : l'événement arrive très souvent dans une grande guilde
        rosterPending=true
        C_Timer.After(2,function() rosterPending=false;A.Roster() end)
    end
end)
