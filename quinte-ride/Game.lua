local _, A = ...
-- Règles de Ride the Bus (version la plus courante, sources et variantes retenues dans AGENTS.md) et état de la
-- partie. Aucune interface ni réseau ici : l'hôte applique ces fonctions et envoie G.Public(g) à la table.
local G={};A.Game=G
local SUITS={'coeur','carreau','trèfle','pique'}
local NAMES={[11]='valet',[12]='dame',[13]='roi',[14]='as'}
G.REWARD={1,1,1,5}  -- gorgées à donner pour une bonne réponse aux questions 1 à 4
G.PENALTY=1         -- gorgée bue pour une erreur (questions et bus)
G.HAND=4            -- cartes par joueur, et longueur du bus
-- Une carte = 1 à 52 : couleur (1 coeur, 2 carreau, 3 trèfle, 4 pique) × 13 + rang (2 à 14, l'as vaut 14)
function G.Rank(card) return (card-1)%13+2 end
function G.Suit(card) return math.floor((card-1)/13)+1 end
function G.Card(card)
    if not card or card==0 then return '?','carte',false end
    local rank=G.Rank(card)
    return ({[11]='V',[12]='D',[13]='R',[14]='A'})[rank] or tostring(rank),SUITS[G.Suit(card)],G.Suit(card)<3
end
function G.CardName(card)
    if not card or card==0 then return 'une carte' end
    local rank=G.Rank(card);return (NAMES[rank] or tostring(rank))..' de '..SUITS[G.Suit(card)]
end
function G.Deck(random)
    random=random or math.random
    local deck={};for i=1,52 do deck[i]=i end
    for i=52,2,-1 do local j=random(i);deck[i],deck[j]=deck[j],deck[i] end
    return deck
end
function G.Options(step)
    if step==1 then return {{'red','Rouge'},{'black','Noire'}} end
    if step==2 then return {{'higher','Plus haute'},{'lower','Plus basse'}} end
    if step==3 then return {{'inside','Dedans'},{'outside','Dehors'}} end
    return {{'hearts','Coeur'},{'diamonds','Carreau'},{'clubs','Trèfle'},{'spades','Pique'}}
end
G.STEPS={'Rouge ou noire','Plus ou moins','Dedans ou dehors','La famille'}
function G.Question(step)
    return ({'Rouge ou noire ?','Plus haute ou plus basse que la première carte ?',
        'Entre les deux premières cartes, ou en dehors ?','Quelle famille : coeur, carreau, trèfle ou pique ?'})[step]
end
-- L'as est la plus forte carte. Plus haut / plus bas : une carte égale est une erreur. Dedans / dehors : une carte
-- égale à l'une des deux bornes compte « dehors » (une paire ne laisse donc que « dehors »).
function G.Correct(step,choice,card,hand)
    local valid=false;for _,option in ipairs(G.Options(step)) do if choice==option[1] then valid=true end end
    if not valid then return nil end
    local rank=G.Rank(card)
    if step==1 then return (G.Suit(card)<3)==(choice=='red') end
    if step==4 then return G.Suit(card)==({hearts=1,diamonds=2,clubs=3,spades=4})[choice] end
    local first=G.Rank(hand[1])
    if step==2 then return choice=='higher' and rank>first or choice=='lower' and rank<first end
    local second=G.Rank(hand[2]);local lo,hi=math.min(first,second),math.max(first,second)
    if choice=='inside' then return rank>lo and rank<hi end
    return rank<=lo or rank>=hi
end
-- Pyramide de 15 cartes (lignes 1 à 5 de haut en bas, positions 1 à 15), retournée du bas vers le haut : ligne du
-- bas 1 gorgée par carte, puis 2, 3, 4, et 5 pour le sommet.
G.PYRAMID_ORDER={}
for row=5,1,-1 do for col=1,row do G.PYRAMID_ORDER[#G.PYRAMID_ORDER+1]=row*(row-1)/2+col end end
function G.PyramidValue(position)
    local row=1;while row*(row+1)/2<position do row=row+1 end
    return 6-row
end
function G.PyramidCard(s) return s.pyramidPos and s.pyramidPos>0 and s.pyramid[s.pyramidPos] or nil end
function G.Left(player) local n=0;for i=1,G.HAND do if (player.hand[i] or 0)>0 then n=n+1 end end;return n end
-- Gorgées gagnées : le joueur choisit à qui les donner (G.Give), la partie attend
local function owe(g,name,amount) g.gifts[#g.gifts+1]={from=name,amount=amount} end
function G.PendingGift(g,name)
    for i,gift in ipairs(g.gifts or {}) do if A.Same(gift.from,name) then return gift,i end end
end
local function draw(g)
    if #g.deck==0 then g.deck=G.Deck() end
    local card=table.remove(g.deck);g.deckLeft=#g.deck;return card
end
local function fresh(g)
    g.round,g.turn,g.pyramid,g.pyramidIndex,g.pyramidPos,g.pyramidRow,g.plays=1,1,{},0,0,0,{}
    g.busPlayer,g.busWhy,g.busHand,g.busStep,g.attempt,g.gifts,g.result,g.finishedReason=nil,nil,{},1,1,{},nil,nil
    g.deck=nil;g.deckLeft=52
end
function G.New(id,host,demo)
    local g={id=id,host=host,protocol=A.protocol,phase='lobby',seq=0,action=1,reveal=0,games=1,
        players={{name=host,given=0,taken=0,hand={}}},demo=demo or false}
    fresh(g);return g
end
function G.Player(g,name)
    for i,p in ipairs(g.players) do if A.Same(p.name,name) then return p,i end end
end
function G.Add(g,name)
    if g.phase~='lobby' or #g.players>=A.MAX_PLAYERS or G.Player(g,name) then return false end
    g.players[#g.players+1]={name=name,given=0,taken=0,hand={}};g.action=g.action+1;return true
end
function G.Remove(g,name)
    local _,index=G.Player(g,name)
    if g.phase~='lobby' or not index or index==1 then return false end
    table.remove(g.players,index);g.action=g.action+1;return true
end
function G.Start(g)
    if g.phase~='lobby' or #g.players<2 then return false,'Il faut au moins deux joueurs.' end
    fresh(g);g.deck=G.Deck();g.phase='question';g.action=g.action+1
    for _,p in ipairs(g.players) do p.hand={} end;return true
end
function G.Active(g)
    if g.phase=='question' then return g.players[g.turn] end
    if g.phase=='bus' then return g.players[g.busPlayer] end
end
local function finish(g,reason) g.phase='finished';g.finishedReason=reason end
--- Réponse du joueur actif (manches de questions ou bus). pass = l'hôte passe le tour d'un absent (erreur).
function G.Answer(g,name,choice,token,pass)
    if token~=g.action then return false,'Tour déjà joué : synchronise la partie.' end
    local player=G.Active(g)
    if not player or not A.Same(player.name,name) then return false,'Ce n’est pas ton tour.' end
    if g.gifts[1] then return false,g.gifts[1].from..' doit d’abord donner ses gorgées.' end
    local bus=g.phase=='bus';local step=bus and g.busStep or g.round
    local hand=bus and g.busHand or player.hand
    -- Vérifier avant de tirer : une demande invalide ne doit jamais consommer de carte.
    local valid=false;for _,option in ipairs(G.Options(step)) do if option[1]==choice then valid=true end end
    if not valid and not pass then return false,'Choix invalide.' end
    local card=draw(g);local correct=not pass and G.Correct(step,choice,card,hand) or false
    hand[step]=card
    g.reveal=g.reveal+1
    local r={name=player.name,card=card,correct=correct,step=step,bus=bus,choice=choice,passed=pass or false,n=g.reveal,give=0,drink=0}
    g.result=r
    if bus then
        if correct then
            if step==G.HAND then finish(g,player.name..' descend du bus après '..g.attempt..' essai(s).')
            else g.busStep=step+1 end
        else
            player.taken=player.taken+G.PENALTY;r.drink=G.PENALTY
            r.hand={};for i=1,step do r.hand[i]=hand[i] end -- rangée ratée, montrée jusqu'à la réponse suivante
            g.busHand={};g.busStep=1;g.attempt=g.attempt+1
            if #g.deck==0 then finish(g,'Plus de cartes : '..player.name..' descend du bus.') end
        end
    else
        if correct then r.give=G.REWARD[step];owe(g,player.name,G.REWARD[step])
        else player.taken=player.taken+G.PENALTY;r.drink=G.PENALTY end
        g.turn=g.turn+1
        if g.turn>#g.players then
            g.turn=1;g.round=g.round+1
            if g.round>G.HAND then
                g.round=G.HAND;g.phase='pyramid';g.pyramidIndex=0;g.pyramidPos=0
            end
        end
    end
    g.action=g.action+1
    return true
end
-- Passager du bus : le plus de cartes en main. Égalité : la plus haute carte gardée, puis une carte tirée chacun.
local function rider(g)
    local best,tied=-1,{}
    for i,p in ipairs(g.players) do
        local n=G.Left(p)
        if n>best then best,tied=n,{i} elseif n==best then tied[#tied+1]=i end
    end
    local why=best..' carte(s) en main'
    if #tied>1 and best>0 then
        local top,kept=-1,{}
        for _,i in ipairs(tied) do
            local high=0;for _,c in pairs(g.players[i].hand) do if c>0 then high=math.max(high,G.Rank(c)) end end
            if high>top then top,kept=high,{i} elseif high==top then kept[#kept+1]=i end
        end
        tied=kept;why=why..', la plus haute carte'
    end
    local deck=G.Deck();local tries=0
    while #tied>1 and tries<20 do
        tries=tries+1;local top,kept=-1,{}
        for _,i in ipairs(tied) do
            local rank=G.Rank(table.remove(deck))
            if rank>top then top,kept=rank,{i} elseif rank==top then kept[#kept+1]=i end
        end
        tied=kept;if #deck<#g.players then deck=G.Deck() end
        if tries==1 then why=why..', puis une carte tirée' end
    end
    return tied[1],why
end
local function busStart(g)
    local index,why=rider(g)
    g.busPlayer=index;g.busWhy=why;g.busHand={};g.busStep=1;g.attempt=1;g.deck=G.Deck();g.deckLeft=#g.deck;g.phase='bus';g.result=nil
end
--- L'hôte avance la pyramide : carte suivante, puis le bus après la quinzième.
function G.Next(g)
    if g.phase~='pyramid' then return false,'Rien à retourner maintenant.' end
    local waiting=g.gifts[1]
    if waiting then return false,waiting.from..' doit encore donner '..waiting.amount..' gorgée(s).' end
    if g.pyramidIndex==15 then busStart(g)
    else
        g.pyramidIndex=g.pyramidIndex+1;g.plays={}
        g.pyramidPos=G.PYRAMID_ORDER[g.pyramidIndex];g.pyramidRow=G.PyramidValue(g.pyramidPos)
        g.pyramid[g.pyramidPos]=draw(g)
    end
    g.action=g.action+1;return true
end
--- Poser une carte de même valeur que la carte de pyramide retournée : sa valeur est à donner.
function G.Play(g,name,slot,token)
    if g.phase~='pyramid' or token~=g.action or g.pyramidIndex==0 then return false,'Aucune carte de pyramide active.' end
    local player=G.Player(g,name)
    slot=tonumber(slot)
    if not player or not slot or slot%1~=0 or slot<1 or slot>G.HAND then return false,'Carte invalide.' end
    local card=player.hand[slot]
    if not card or card==0 or G.Rank(card)~=G.Rank(G.PyramidCard(g)) then return false,'Il faut une carte de même valeur.' end
    if #g.plays>=8 then return false,'Assez de cartes posées sur celle-ci.' end
    player.hand[slot]=0;owe(g,player.name,g.pyramidRow);g.plays[#g.plays+1]={name=player.name,card=card}
    -- Même jeton d'action : plusieurs joueurs peuvent poser sur la même carte en même temps.
    return true
end
--- Donne des gorgées gagnées à un autre joueur de la table (amount : toutes par défaut, ou une partie).
function G.Give(g,name,target,amount)
    local gift,index=G.PendingGift(g,name)
    if not gift then return false,'Rien à donner pour l’instant.' end
    local receiver=type(target)=='string' and G.Player(g,target)
    if not receiver or A.Same(receiver.name,name) then return false,'Choisis un autre joueur de la table.' end
    amount=tonumber(amount) or gift.amount
    if amount%1~=0 or amount<1 or amount>gift.amount then return false,'Nombre de gorgées invalide.' end
    local giver=G.Player(g,name)
    gift.amount=gift.amount-amount;if gift.amount==0 then table.remove(g.gifts,index) end
    receiver.taken=receiver.taken+amount;if giver then giver.given=giver.given+amount end
    -- Même jeton d'action : d'autres joueurs peuvent donner en même temps.
    return true
end
--- L'hôte débloque la table quand un joueur est absent : dons passés, sinon tour passé, ou bus arrêté.
function G.Pass(g)
    if g.gifts[1] then g.gifts={};g.action=g.action+1;return true end
    if g.phase=='question' then local p=G.Active(g);return G.Answer(g,p.name,'pass',g.action,true) end
    if g.phase=='bus' then finish(g,'Bus arrêté par l’hôte.');g.action=g.action+1;return true end
    return false,'Rien à passer.'
end
--- Nouvelle partie avec la même table (compteurs remis à zéro).
function G.Again(g)
    if g.phase~='finished' then return false,'La partie n’est pas finie.' end
    fresh(g);g.phase='lobby';g.games=g.games+1;g.action=g.action+1
    for _,p in ipairs(g.players) do p.given,p.taken,p.hand=0,0,{} end;return true
end
local function copy(v) if type(v)~='table' then return v end;local t={};for k,x in pairs(v) do t[k]=copy(x) end;return t end
--- État envoyé à la table : une copie (l'état précédent reste intact pour G.Journal).
function G.Public(g)
    local result={}
    for _,key in ipairs({'id','host','protocol','phase','seq','action','reveal','games','players','round','turn','pyramid','pyramidIndex',
        'pyramidPos','pyramidRow','plays','busHand','busStep','busPlayer','busWhy','attempt','deckLeft','gifts','demo','result','finishedReason'}) do
        result[key]=copy(g[key])
    end
    -- Jamais le paquet ni une carte de pyramide pas encore retournée ; pas de journal (chaque client écrit le sien
    -- avec G.Journal : un état de 8 joueurs tient ainsi en 2 trames au lieu de 3).
    return result
end
function G.Valid(s)
    if type(s)~='table' or s.protocol~=A.protocol or type(s.id)~='string' or #s.id>80 or type(s.host)~='string' or #s.host>100 then return false end
    if not ({lobby=true,question=true,pyramid=true,bus=true,finished=true})[s.phase] then return false end
    local function integer(n,lo,hi) return type(n)=='number' and n%1==0 and n>=lo and n<=hi end
    local function name(v) return type(v)=='string' and #v>0 and #v<=100 end
    local function cards(t,max)
        if type(t)~='table' then return false end
        for k,v in pairs(t) do if not integer(k,1,max) or not integer(v,0,52) then return false end end
        return true
    end
    if not integer(s.seq,0,1e9) or not integer(s.action,1,1e9) or not integer(s.reveal,0,1e9) or not integer(s.games,1,1e6) then return false end
    if type(s.players)~='table' or #s.players<1 or #s.players>A.MAX_PLAYERS then return false end
    local names={}
    for k,p in pairs(s.players) do
        if not integer(k,1,#s.players) or type(p)~='table' or not name(p.name) then return false end
        local key=A.Key(p.name);if names[key] then return false end;names[key]=true
        if not integer(p.given,0,100000) or not integer(p.taken,0,100000) or not cards(p.hand,G.HAND) then return false end
    end
    if not A.Same(s.players[1].name,s.host) or not integer(s.turn,1,#s.players) or not integer(s.round,1,G.HAND) then return false end
    if not cards(s.pyramid,15) or not cards(s.busHand,G.HAND) or not integer(s.pyramidIndex,0,15) or not integer(s.pyramidPos,0,15)
        or not integer(s.pyramidRow,0,5) or not integer(s.deckLeft,0,52) then return false end
    if type(s.plays)~='table' or #s.plays>8 then return false end
    for k,play in pairs(s.plays) do
        if not integer(k,1,8) or type(play)~='table' or not name(play.name) or not integer(play.card,1,52) then return false end
    end
    if type(s.gifts)~='table' or #s.gifts>40 then return false end
    for k,gift in pairs(s.gifts) do
        if not integer(k,1,40) or type(gift)~='table' or not name(gift.from) or not integer(gift.amount,1,5) then return false end
    end
    if not integer(s.busStep,1,G.HAND) or not integer(s.attempt,1,100) then return false end
    if s.busPlayer~=nil and not integer(s.busPlayer,1,#s.players) then return false end
    if s.phase=='bus' and not s.busPlayer then return false end
    if s.busWhy~=nil and (type(s.busWhy)~='string' or #s.busWhy>120) then return false end
    if s.finishedReason~=nil and (type(s.finishedReason)~='string' or #s.finishedReason>200) then return false end
    if s.result~=nil then
        local r=s.result
        if type(r)~='table' or not integer(r.card,1,52) or not integer(r.step,1,G.HAND) or type(r.correct)~='boolean' or not name(r.name)
            or not integer(r.n,1,1e9) or not integer(r.give,0,5) or not integer(r.drink,0,5) or (r.hand~=nil and not cards(r.hand,G.HAND)) then return false end
    end
    return true
end
-- Journal de la table, écrit par chaque client en comparant deux états successifs (rien n'est envoyé pour lui).
-- Retourne les lignes nouvelles, de la plus ancienne à la plus récente.
function G.Journal(prev,s)
    local out={}
    local function add(text) out[#out+1]=text end
    if prev and (prev.id~=s.id or prev.games~=s.games) then prev=nil end
    if not prev then add(s.games>1 and 'Nouvelle partie : même table.' or ('Table de '..s.host..'.')) end
    local before=prev or {players={},plays={},gifts={},phase='lobby',pyramidIndex=0}
    for _,p in ipairs(s.players) do if prev and not G.Player(before,p.name) then add(p.name..' rejoint la table.') end end
    if s.phase=='question' and before.phase=='lobby' then add('Première manche : rouge ou noire ?') end
    local r=s.result
    if r and not (before.result and before.result.n==r.n) then
        add(r.name..' : '..G.CardName(r.card)..(r.passed and ' — tour passé, boit '..r.drink..'.'
            or r.correct and (r.bus and ' — gagné.' or ' — gagné, donne '..r.give..'.')
            or ' — raté, boit '..r.drink..(r.bus and ' et recommence.' or '.')))
    end
    if s.phase=='pyramid' and before.phase~='pyramid' then add('La pyramide : 15 cartes, du bas vers le haut.') end
    if s.phase=='pyramid' and s.pyramidIndex>0 and s.pyramidIndex~=before.pyramidIndex then
        add('Pyramide : '..G.CardName(G.PyramidCard(s))..', '..s.pyramidRow..' gorgée(s).')
    end
    local seen=s.pyramidIndex==before.pyramidIndex and #(before.plays or {}) or 0
    for i=seen+1,#(s.plays or {}) do local p=s.plays[i];add(p.name..' pose '..G.CardName(p.card)..' et donne '..s.pyramidRow..'.') end
    -- Dons : le donneur d'après son compteur « donné », le receveur si un seul a bu ce montant
    local given=false
    for _,p in ipairs(s.players) do
        local old=G.Player(before,p.name)
        if old and p.given>old.given then
            given=true;local amount=p.given-old.given;local to
            for _,q in ipairs(s.players) do
                local o=G.Player(before,q.name)
                if o and not A.Same(q.name,p.name) and q.taken-o.taken==amount then to=to==nil and q.name or false end
            end
            add(p.name..' donne '..amount..' gorgée(s)'..(to and (' à '..to) or '')..'.')
        end
    end
    if prev and #before.gifts>0 and #s.gifts==0 and not given and s.phase==before.phase then add('Dons en attente passés par l’hôte.') end
    if s.phase=='bus' and before.phase~='bus' then add(s.players[s.busPlayer].name..' monte dans le bus ('..(s.busWhy or '')..').') end
    if s.phase=='finished' and before.phase~='finished' and s.finishedReason then add(s.finishedReason) end
    return out
end
