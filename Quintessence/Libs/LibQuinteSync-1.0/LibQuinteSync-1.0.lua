-- Quintessence, MIT. LibQuinteSync : synchro de guilde entre addons. Register(prefix, savedData, adapter).
-- v6 (protocole 2) :
--   * Résumés : chaque membre annonce ~30 octets par module (nombre d'entrées + deux empreintes du manifeste) au lieu du
--     manifeste complet ; le détail n'est échangé qu'en cas de différence, en privé, et un état déjà comparé n'est pas
--     redemandé.
--   * Changement local : seul le delta du manifeste part sur GUILD ('U').
--   * Demandes identiques reçues dans la même fenêtre de 2 s : une seule diffusion GUILD au lieu d'un envoi privé par
--     demandeur ; demandes réparties entre les membres qui ont la donnée, jamais deux fois la même.
--   * Deux voies parallèles : GUILD (bridée par le jeu à ~1 message/s par préfixe) et chuchotements (non bridés hors
--     instance) ; les messages temps réel (Ride, ping) passent devant.
--   * Nouveau venu : bonjour + résumé ; deux membres au plus lui envoient leur manifeste en privé, il répartit ses
--     demandes entre eux puis diffuse le delta de ce qu'il apporte.
--   * Noms WoW Forever (« Prénom Nom », sans royaume, uniques dans la région) : clés sans royaume, chuchotements sans
--     royaume, reconnaissance de soi par le GUID de la liste de guilde.
-- v9 : expéditeur « Prénom-Nom » / « Prénom Nom-Royaume » reconnu (clés sans espaces ni tirets, nom remis sous la
--   forme de la liste de guilde), Forever reconnu par l'interface du jeu et non par le seul nom de famille du joueur.
-- Leçons du vrai jeu : ne jamais conditionner un envoi à C_ChatInfo.AreOutgoingAddonChatMessagesRestricted (toujours
-- vrai sur Forever) ; un envoi réussi peut renvoyer nil ; la liste de guilde est vide à la connexion.
local Lib=LibStub:NewLibrary('LibQuinteSync-1.0',9)
if not Lib then return end
local Serializer,Deflate,Guard=LibStub('LibSerialize'),LibStub('LibDeflate'),LibStub('LibQuinteDeflateGuard-1.0')
local MAX_RAW,MAX_ENCODED,MAX_QUEUE=131072,65536,6000
local ROSTER_WAIT,RETRY_LIMIT=30,120 -- attente max de la liste de guilde ; durée max des nouveaux essais d'un message
local PERIOD=900                     -- résumé périodique (15 min, plus un décalage aléatoire)
local GATHER=2                       -- fenêtre de regroupement des demandes identiques
local BROADCAST_FROM=3               -- à partir de 3 demandeurs, une diffusion GUILD coûte moins que des envois privés
local MAX_PENDING,MAX_WANTS,MAX_PARTS=64,512,32
local REMEMBER=45*86400             -- un membre vu dans la liste reste membre 45 jours (hors ligne compris)
local PER_SOURCE=4                   -- demandes en cours par membre interrogé (les autres attendent leur tour)
local ASK_TIMEOUT,ASK_TRIES=90,3     -- sans progrès en 90 s, on redemande (autre membre si possible), 3 fois au plus
local Instance={};Instance.__index=Instance
local function clock() return GetTime() end
local function stamp() return (time or GetServerTime)() end
local function safe(fn,...) if type(fn)=='function' then local ok,a,b=pcall(fn,...);if ok then return a,b end end end
local function secret(v) return type(issecretvalue)=='function' and issecretvalue(v) or false end
local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end

-- ---------------------------------------------------------------------------------------------------------------------
-- Noms
-- ---------------------------------------------------------------------------------------------------------------------
-- WoW Forever : personnages « Prénom Nom », uniques dans la région, royaumes cachés ; UnitName y renvoie le nom de
-- famille en 2e valeur. Les noms n'y ont ni tiret ni apostrophe : un tiret marque toujours un royaume.
local regionalCache
-- Forever reconnu par le jeu lui-même (projet, ou interface 1.6x), pas par le nom du joueur : au chargement le jeu
-- donne « Unknown » sans nom de famille, et un personnage peut ne pas encore en avoir (il l'obtient à la connexion
-- suivante). Une réponse « non » tirée de ce nom-là était gardée toute la session : clés et chuchotements avec royaume,
-- refusés par Forever, et plus aucune donnée ne passait en privé.
local function foreverBuild()
    if WOW_PROJECT_CAMELOT and WOW_PROJECT_ID==WOW_PROJECT_CAMELOT then return true end
    if type(GetBuildInfo)~='function' then return false end
    local ok,_,_,_,toc=pcall(GetBuildInfo)
    return ok and type(toc)=='number' and toc>=16000 and toc<20000
end
local function regional()
    if regionalCache~=nil then return regionalCache end
    if foreverBuild() then regionalCache=true;return true end
    local ok,first,second=pcall(UnitName,'player')
    if not ok or type(first)~='string' or first=='' or first==UNKNOWNOBJECT or first=='Unknown' then return false end -- trop tôt
    regionalCache=type(second)=='string' and second~=''
    return regionalCache
end
-- Royaume au format des noms de la liste de guilde et des messages (sans espaces : « Kirin Tor » → « KirinTor »).
-- Le nom normalisé ne change pas de la session : gardé dès que le jeu le donne (il peut manquer avant la connexion).
local realmCache
local function realm()
    if realmCache then return realmCache end
    local normalized=GetNormalizedRealmName and safe(GetNormalizedRealmName)
    if type(normalized)=='string' and normalized~='' then realmCache=normalized;return normalized end
    return (GetRealmName():gsub('%s',''))
end
-- Nom Forever sans royaume. L'expéditeur d'un message peut arriver en « Prénom Nom », « Prénom Nom-Royaume » ou
-- « Prénom-Nom » (le jeu met parfois un tiret entre prénom et nom) : on retire notre royaume en fin de nom, puis ce
-- qui suit un tiret seulement si le nom a une espace. Couper au premier tiret faisait de « Prénom-Nom » le seul
-- prénom : membre inconnu, ses chuchotements (manifestes, données) étaient jetés.
local function plain(name)
    local r=realm()
    if r~='' and #name>#r+1 and name:sub(-#r-1)=='-'..r then name=name:sub(1,-#r-2) end
    if name:find(' ',1,true) then name=name:match('^([^%-]+)') or name end
    return name
end
-- Clé de comparaison : minuscules, sans espaces ; royaume ajouté (classique) ou retiré (Forever).
-- Appelée à chaque message reçu et par les modules pour chaque enregistrement (nettoyage, fusion) : résultat gardé
-- en mémoire dès qu'il ne peut plus changer (type de noms connu, et royaume connu hors Forever), 2048 noms au plus.
local keyCache,keyCount={},0
local function key(name)
    if type(name)~='string' then return '' end
    local cached=keyCache[name]
    if cached then return cached end
    local isRegional,result=regional(),name
    if isRegional then result=plain(name)
    elseif not name:find('-',1,true) then result=name..'-'..realm() end
    result=(result:gsub(isRegional and '[%s%-]' or '%s',''):gsub('[A-Z]',string.lower))
    if regionalCache~=nil and (isRegional or realmCache) then
        if keyCount>=2048 then keyCache,keyCount={},0 end
        keyCache[name]=result;keyCount=keyCount+1
    end
    return result
end
Lib.CanonicalKey=key
function Lib.Regional() return regional() end
function Lib.Realm() return realm() end
-- Destinataire d'un chuchotement : Forever refuse « Prénom Nom-Royaume » (« aucun joueur nommé… »)
-- (nom écrit comme la liste de guilde quand on la connaît : « Prénom-Nom » reçu → « Prénom Nom »)
function Lib.WhisperTarget(name)
    if type(name)~='string' or not regional() then return name end
    local k=key(name)
    for _,instance in pairs(Lib.instances or {}) do
        local m=instance.roster and instance.roster[k]
        if m and type(m.name)=='string' then return plain(m.name) end
    end
    return plain(name)
end
-- Nom affichable : sans royaume sur Forever
function Lib.DisplayName(name)
    if type(name)~='string' then return '' end
    return regional() and Lib.WhisperTarget(name) or name
end
-- Nom complet d'une unité (Forever : « Prénom Nom » ; ailleurs « Nom » ou « Nom-Royaume » pour un autre royaume)
function Lib.UnitFullName(unit)
    local ok,first,second=pcall(UnitName,unit)
    if not ok or type(first)~='string' then return nil end
    if type(second)=='string' and second~='' then return regional() and (first..' '..second) or (first..'-'..second) end
    return first
end
-- Nom complet du joueur, tel que la liste de guilde l'écrit (le GUID de la liste fait foi, une fois lue)
function Lib.PlayerName()
    if Lib.playerName then return Lib.playerName end
    local ok,first,second=pcall(UnitName,'player')
    if not ok or type(first)~='string' then return nil end
    if regional() and type(second)=='string' and second~='' then return first..' '..second end
    return first
end
function Lib.PlayerKey()
    local name=Lib.PlayerName()
    return name and (name..'-'..realm()) or nil
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Empreintes : texte canonique d'une valeur (clés triées) et deux hachages polynomiaux indépendants
-- ---------------------------------------------------------------------------------------------------------------------
-- Ordre des clés (fonction unique au lieu d'une fermeture créée pour chaque table)
local function before(x,y)
    local tx,ty=type(x),type(y)
    if tx~=ty then return tx<ty end
    if tx=='number' or tx=='string' then return x<y end
    return tostring(x)<tostring(y)
end
local function canon(v,depth)
    local t=type(v)
    if t=='string' then return 's'..#v..':'..v
    elseif t=='number' then return 'n'..string.format('%.17g',v)
    elseif t=='boolean' then return v and 'T' or 'F'
    elseif t=='table' then
        depth=(depth or 0)+1
        if depth>10 then return 'X' end
        local keys={}
        for k in pairs(v) do keys[#keys+1]=k end
        table.sort(keys,before)
        local out={'{'}
        for _,k in ipairs(keys) do out[#out+1]=canon(k,depth);out[#out+1]='=';out[#out+1]=canon(v[k],depth);out[#out+1]=';' end
        out[#out+1]='}'
        return table.concat(out)
    end
    return '?'
end
local function hash(text)
    local h1,h2=5381,7
    for i=1,#text do
        local c=text:byte(i)
        h1=(h1*33+c)%2147483647;h2=(h2*131+c)%2147483629
    end
    return h1,h2
end
local function fingerprint(value) local a,b=hash(canon(value));return a..':'..b end
Lib.Fingerprint=fingerprint

-- ---------------------------------------------------------------------------------------------------------------------
-- Liste de guilde
-- ---------------------------------------------------------------------------------------------------------------------
function Instance:RefreshRoster()
    local members={}
    local n=safe(GetNumGuildMembers) or 0
    local guid=UnitGUID and safe(UnitGUID,'player')
    for i=1,n do
        -- (valeurs lues directement : pas de table temporaire par membre à chaque relecture)
        local ok,name,_,_,level,_,_,_,_,online,_,class,_,_,mobile,_,_,rowGuid=pcall(GetGuildRosterInfo,i)
        -- Noms et GUID de la liste parfois secrets en combat (Forever) : ligne ignorée, relue au prochain passage
        if ok and type(name)=='string' and not secret(name) and not secret(rowGuid) and not secret(online) then
            if regionalCache==false and name:find(' ',1,true) then regionalCache=true;keyCache,keyCount={},0;return self:RefreshRoster() end
            members[key(name)]={name=name,online=(online and not mobile) or false,level=level,class=class}
            if guid and not secret(guid) and rowGuid==guid then Lib.playerName=plain(name) end
        end
    end
    -- Le jeu ne donne souvent que les membres connectés (case « membres hors ligne » décochée, client Forever) :
    -- sans mémoire, la fiche d'un membre déconnecté était effacée au nettoyage et plus jamais relayée.
    -- On se souvient de chaque membre vu (sauvegardé) ; il n'est oublié qu'au bout de 45 jours sans le revoir,
    -- ou tout de suite s'il manque d'une liste complète (membres hors ligne affichés).
    local memory=safe(self.adapter.Memory)
    if type(memory)=='table' and n>0 then
        local now,seen=stamp(),0
        for who,m in pairs(members) do
            local saved=memory[who] -- fiche mise à jour sur place (pas une nouvelle table par membre à chaque relecture)
            if type(saved)=='table' then saved.name,saved.class,saved.level,saved.seen=m.name,m.class,m.level,now
            else memory[who]={name=m.name,class=m.class,level=m.level,seen=now} end
            seen=seen+1
        end
        local complete=GetGuildRosterShowOffline and safe(GetGuildRosterShowOffline) and seen>=n
        for who,m in pairs(memory) do
            if type(m)~='table' or type(m.seen)~='number' or now-m.seen>REMEMBER or (complete and not members[who]) then memory[who]=nil
            elseif not members[who] then members[who]={name=m.name,online=false,level=m.level,class=m.class,remembered=true} end
        end
    end
    self.roster=members;self.rosterAt=clock()
    local known=n>0;local first=known and not self.rosterKnown;self.rosterKnown=known
    if known then safe(self.adapter.Cleanup,self.data,members,stamp()) end
    if first then self:Resume() end -- messages reçus avant la liste de guilde : on les traite maintenant
end
-- GUILD_ROSTER_UPDATE arrive très souvent dans une grande guilde : relecture regroupée (10 s), sauf la première fois.
function Instance:RefreshRosterSoon()
    if not self.rosterKnown then self:RefreshRoster();return end
    if self.rosterPending then return end
    self.rosterPending=true
    self:Later(10,function() self.rosterPending=false;self:RefreshRoster() end)
end
-- Liste pas encore reçue : on garde les messages, mais pas plus de 30 s après le démarrage (si le jeu ne la donne
-- jamais, on traite quand même : le canal GUILD est sûr et les modules vérifient chaque enregistrement).
function Instance:WaitRoster()
    return not self.rosterKnown and clock()-(self.startedAt or self.createdAt)<ROSTER_WAIT
end
-- Membre de la guilde ? Un inconnu peut être un membre arrivé depuis la dernière lecture : on relit (au plus toutes les 5 s).
function Instance:Member(name)
    if self.roster[key(name)]~=nil then return true end
    if clock()-(self.rosterAt or -100)>5 then self:RefreshRoster() end
    return self.roster[key(name)]~=nil
end
-- Nos propres messages GUILD nous reviennent : on se reconnaît par notre nom complet (GUID de la liste sur Forever)
-- (nos deux clés gardées une fois notre nom lu dans la liste de guilde : chaque message reçu passe ici)
function Instance:IsSelf(sender)
    local who=key(sender)
    local name=Lib.playerName
    if not name or self.selfName~=name then
        local mine,player=key(self.adapter.SelfKey and safe(self.adapter.SelfKey) or ''),key(Lib.PlayerKey() or '')
        if not name then return who==mine or who==player end
        self.selfName,self.selfKey,self.selfPlayer=name,mine,player
    end
    return who==self.selfKey or who==self.selfPlayer
end
-- urgent : messages temps réel (Ride, ping), petits, jamais retenus par un raid chargé (seule la grosse synchro l'est)
function Instance:Busy(urgent)
    if not self.enabled or not IsInGuild or not IsInGuild() then return true,'off/guilde' end
    -- Conteneur : guilde pas encore lue ou autre guilde (adapter.Blocked) : rien ne part
    local blocked=self.adapter.Blocked and safe(self.adapter.Blocked)
    if blocked then return true,blocked=='refuse' and 'hors guilde' or 'guilde en lecture' end
    -- En combat, seuls les messages temps réel (SOS, layers, ping) partent : un SOS PvP est lancé en plein combat
    if not urgent and InCombatLockdown and InCombatLockdown() then return true,'combat' end
    if not urgent and IsInRaid and IsInRaid() then
        local ctl=ChatThrottleLib
        if (ctl.bQueueing and not (self.lanes.G.inflight or self.lanes.W.inflight)) or self:Queued()>64 or (GetFramerate and GetFramerate()<30) then return true,'raid chargé' end
    end
    return false,''
end
function Instance:Later(delay,fn)
    if C_Timer and C_Timer.After then C_Timer.After(delay,function() safe(fn) end) end
end
function Instance:SetEnabled(value)
    self.enabled=value and true or false;self.epoch=self.epoch+1
    if not self.enabled then
        for _,lane in pairs(self.lanes) do lane.queue={};lane.urgent={} end
        -- (byId et load aussi : sinon les demandes effacées restaient comptées chez leur membre, qui pouvait ne plus
        -- jamais être choisi après « /quinte sync off » puis « on »)
        self.wants={};self.pending={};self.byId={};self.load={};self.serving={};self.buffers={};self.deferredInput={}
    else self:Announce();self:Pump() end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Transport : sérialisation, compression, découpage en messages de 255 octets, deux voies bridées par ChatThrottleLib
-- ---------------------------------------------------------------------------------------------------------------------
function Instance:Queued()
    local n=0
    for _,lane in pairs(self.lanes) do n=n+#lane.queue+#lane.urgent+(lane.inflight and 1 or 0) end
    return n
end
function Instance:Enqueue(kind,value,target,urgent)
    if not self.enabled then return end
    local ok,raw=pcall(Serializer.Serialize,Serializer,{v=2,k=kind,d=value})
    if not ok or #raw>MAX_RAW then self.rejected=self.rejected+1;return end
    local compressed=safe(Deflate.CompressDeflate,Deflate,raw,{level=5})
    local encoded=compressed and safe(Deflate.EncodeForWoWAddonChannel,Deflate,compressed)
    if not encoded or #encoded>MAX_ENCODED then return end
    local total=math.max(1,math.ceil(#encoded/210))
    if self:Queued()+total>MAX_QUEUE then return end
    self.serial=self.serial+1
    local id=self.nonce..'-'..self.serial
    local lane=target and self.lanes.W or self.lanes.G
    local list=urgent and lane.urgent or lane.queue
    if target then target=Lib.WhisperTarget(target) end
    for part=1,total do
        local text='2:'..id..':'..part..':'..total..':'..encoded:sub((part-1)*210+1,part*210)
        if #text>255 then self.rejected=self.rejected+1;return end
        list[#list+1]={text=text,target=target,channel=target and 'WHISPER' or 'GUILD',epoch=self.epoch,urgent=urgent}
    end
    self.stats.messages[kind]=(self.stats.messages[kind] or 0)+total
    self:Pump()
end
function Instance:Wake()
    if self.wakePending then return end
    self.wakePending=true
    self:Later(1,function() self.wakePending=false;self:Resume() end)
end
function Instance:Pump()
    for _,lane in pairs(self.lanes) do self:PumpLane(lane) end
end
function Instance:PumpLane(lane)
    if lane.inflight or not self.enabled then return end
    if #lane.urgent+#lane.queue==0 then return end
    if self:Busy(#lane.urgent>0) then self:Wake();return end
    local message=table.remove(lane.urgent,1) or table.remove(lane.queue,1)
    local ctl=ChatThrottleLib
    if not ctl or type(ctl.Enqueue)~='function' or not ctl.Prio or not ctl.Prio.BULK then
        self.rejected=self.rejected+1;return
    end
    lane.inflight=message
    local results=Enum.SendAddonMessageResult or {}
    local SUCCESS,THROTTLE,ERROR=results.Success or 0,results.AddonMessageThrottle or 3,results.GeneralError or 9
    -- Bridage du préfixe ou du canal, verrou temporaire (rencontre de raid, M+) : on réessaie, comme CTL le fait pour 3
    local retry={[THROTTLE]=true,[results.ChannelThrottle or 8]=true,[results.AddOnMessageLockdown or 11]=true}
    local queued={self.prefix,message.text,message.channel,message.target}
    queued.n=message.target and 4 or 3;queued.nSize=#message.text+(ctl.MSG_OVERHEAD or 40)
    queued.f=function(...)
        if not self.enabled or message.epoch~=self.epoch then return SUCCESS end
        -- Occupé (combat, raid chargé) : le message revient dans notre file au lieu de bloquer CTL, pour qu'un message
        -- temps réel puisse passer devant ; il repartira à la reprise.
        if self:Busy(message.urgent) then message.returned=true;return SUCCESS end
        local ok,a,b=pcall(C_ChatInfo.SendAddonMessage,...)
        if not ok then return ERROR end
        -- Avant 11.0 le code était en 2e position ; sur Forever un envoi réussi peut ne rien renvoyer (nil)
        local value=b~=nil and b or a
        if value==nil or value==true or value==SUCCESS then return SUCCESS end
        if value==false then return ERROR end
        if retry[value] then
            message.firstTry=message.firstTry or clock();self.stats.retries=self.stats.retries+1;self.stats.lastResult=value
            if clock()-message.firstTry<RETRY_LIMIT then return THROTTLE end
        end
        return value
    end
    queued.callbackFn=function(_,sent,result)
        lane.inflight=nil
        if message.returned then
            message.returned=nil;table.insert(message.urgent and lane.urgent or lane.queue,1,message);self:Wake();return
        end
        local stats=self.stats;stats.lastResult=result
        if sent then stats.sent=stats.sent+1
        else
            stats.failed=stats.failed+1;self.rejected=self.rejected+1
            -- Premier refus de la session : on prévient le joueur une fois (code du jeu), sans inonder le chat
            -- (joueur déconnecté : refus normal, pas d'avertissement)
            if not self.warned and result~=(results.TargetOffline or 12) then self.warned=true;safe(self.adapter.Problem,result,message.channel) end
        end
        self:Later(.02,function() self:PumpLane(lane) end)
    end
    local ok=pcall(ctl.Enqueue,ctl,'BULK',self.prefix..':'..(message.target or 'GUILD'),queued)
    if not ok then lane.inflight=nil;self.rejected=self.rejected+1 end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Manifestes, résumés et deltas
-- ---------------------------------------------------------------------------------------------------------------------
function Instance:Groups()
    local groups=safe(self.adapter.Groups,self.data)
    return type(groups)=='table' and groups or {}
end
-- Lecture du manifeste d'un module : entrées (texte canonique → entrée), résumé, taille des lots du module
function Instance:Scan(group)
    local cached=self.scans[group]
    if cached and clock()-cached.at<10 then return cached end
    local batches=safe(self.adapter.Manifest,self.data,group)
    local set,n,a,b,size={},0,0,0,1
    for _,batch in ipairs(type(batches)=='table' and batches or {}) do
        if type(batch)=='table' then
            if #batch>size then size=#batch end
            for _,entry in ipairs(batch) do
                local text=canon(entry)
                if not set[text] then
                    set[text]=entry;n=n+1
                    local h1,h2=hash(text);a=(a+h1)%4294967296;b=(b+h2)%4294967296
                end
            end
        end
    end
    local scan={set=set,n=n,summary=n..':'..a..':'..b,size=size,at=clock()}
    self.scans[group]=scan
    return scan
end
function Instance:Summaries()
    local out={}
    for _,group in ipairs(self:Groups()) do out[group]=self:Scan(group).summary end
    return out
end
-- Entrées → lots de la taille habituelle du module (ses contrôles bornent la taille d'un lot reçu)
local function batches(entries,size)
    local out,current={},{}
    for _,entry in ipairs(entries) do
        current[#current+1]=entry
        if #current>=size then out[#out+1]=current;current={} end
    end
    if #current>0 then out[#out+1]=current end
    return out
end
function Instance:SendManifest(group,target)
    local scan=self:Scan(group)
    local entries={}
    for _,entry in pairs(scan.set) do entries[#entries+1]=entry end
    local list=batches(entries,scan.size)
    if #list==0 then list={{}} end
    for index,batch in ipairs(list) do self:Enqueue('M',{m=group,b=batch,s=scan.summary,i=index,n=#list},target) end
end
-- État de référence pour les deltas (ce que les autres ont déjà reçu de nous ou ne peuvent pas apprendre de nous)
function Instance:Rebase(group)
    if self.localPending then return end -- un changement local attend son envoi : il ne doit pas disparaître du delta
    self.scans[group]=nil
    self.baseline[group]=self:Scan(group).set
end
-- Diffuse ce qui a changé depuis l'état de référence (changement local, ou apport d'un nouveau venu)
function Instance:Push(group,reference)
    self.scans[group]=nil
    local scan=self:Scan(group)
    local old=reference or self.baseline[group] or {}
    local delta={}
    for text,entry in pairs(scan.set) do if not old[text] then delta[#delta+1]=entry end end
    self.baseline[group]=scan.set
    for _,batch in ipairs(batches(delta,scan.size)) do self:Enqueue('U',{m=group,b=batch}) end
    return #delta
end
function Instance:NotifyLocal()
    if not self.enabled or self.localPending then return end
    self.localPending=true
    -- quelques secondes pour regrouper plusieurs changements faits d'affilée
    self:Later(3,function()
        self.localPending=false
        -- Avant notre bonjour, rien à diffuser : le bonjour porte déjà nos résumés à jour
        if not self.helloSent then return end
        for _,group in ipairs(self:Groups()) do self:Push(group) end
    end)
end
-- Résumé à la guilde (périodique, /quinte sync now, bouton Synchroniser)
function Instance:Announce()
    if not self.enabled then return end
    if self:Busy() then self.announcePending=true;self:Wake();return end
    self:RefreshRoster()
    self:Enqueue('S',{s=self:Summaries()})
end
-- Ping de guilde : chaque membre qui a l'addon répond en privé (diagnostic /quinte test).
function Instance:Ping(info)
    self.pingAt=clock();self:Enqueue('P',{t=stamp(),i=info},nil,true)
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Demandes : regroupées, réparties, sans doublon
-- ---------------------------------------------------------------------------------------------------------------------
function Instance:Want(request,sender)
    if type(request)~='table' then return end
    local h=fingerprint(request)
    local pending=self.pending[h]
    if pending and clock()-pending.at<RETRY_LIMIT then pending.cands[sender]=true;return end
    local want=self.wants[h]
    if not want then
        if count(self.wants)>=MAX_WANTS then return end
        want={request=request,cands={},at=clock()};self.wants[h]=want
    end
    want.cands[sender]=true
    -- une seconde pour réunir les membres qui ont la même donnée, puis on choisit le moins chargé
    if not self.dispatchPending then
        self.dispatchPending=true
        self:Later(1,function() self.dispatchPending=false;self:Dispatch() end)
    end
end
-- Membre le moins chargé parmi ceux qui ont annoncé la donnée (ils viennent de nous écrire : ils sont en ligne),
-- sans dépasser PER_SOURCE demandes en cours chez lui ; except : à éviter si un autre est disponible
function Instance:Choose(cands,except)
    local best,bestLoad,fallback
    for sender in pairs(cands) do
        local load=self.load[key(sender)] or 0
        if load<PER_SOURCE then
            if sender==except then fallback=sender
            elseif not best or load<bestLoad or (load==bestLoad and math.random()<.5) then best,bestLoad=sender,load end
        end
    end
    return best or fallback
end
function Instance:Ask(h,request,sender,cands,tries)
    self.requestSerial=self.requestSerial+1
    local id=self.nonce..'-r'..self.requestSerial
    local pending={h=h,id=id,request=request,sender=sender,senderKey=key(sender),cands=cands,at=clock(),received={},count=0,tries=(tries or 0)+1}
    self.pending[h]=pending;self.byId[id]=pending
    self.load[pending.senderKey]=(self.load[pending.senderKey] or 0)+1
    self:Enqueue('R',{id=id,q=request},sender)
end
function Instance:Dispatch()
    local active=count(self.pending) -- compté une fois (et non à chaque demande en attente)
    for h,want in pairs(self.wants) do
        if active>=MAX_PENDING then break end
        if self.pending[h] then self.wants[h]=nil -- déjà demandé à quelqu'un
        else
            local sender=self:Choose(want.cands,want.avoid)
            if sender then self.wants[h]=nil;self:Ask(h,want.request,sender,want.cands,want.tries);active=active+1
            elseif clock()-want.at>300 then self.wants[h]=nil end -- tous saturés depuis 5 min : le résumé périodique s'en chargera
        end
    end
    if next(self.wants) and not self.dispatchPending then
        self.dispatchPending=true
        self:Later(5,function() self.dispatchPending=false;self:Dispatch() end)
    end
end
function Instance:Finish(pending)
    self.pending[pending.h]=nil;self.byId[pending.id]=nil
    self.load[pending.senderKey]=math.max(0,(self.load[pending.senderKey] or 1)-1)
    if type(pending.request)=='table' and pending.request.m then self:Rebase(pending.request.m) end
    if next(self.wants) then self:Dispatch() end -- une place se libère chez ce membre
    if self.settle then self:Later(3,function() self:Settle() end) end
end
-- Réponse à une demande : les demandes identiques arrivées pendant la fenêtre partent en une seule diffusion GUILD
function Instance:Serve(request,sender,id)
    local h=fingerprint(request)
    local serving=self.serving[h]
    if not serving then
        if count(self.serving)>=64 then return end
        serving={request=request,to={},n=0};self.serving[h]=serving
        self:Later(GATHER,function()
            self.serving[h]=nil
            local parts=safe(self.adapter.Export,self.data,request) or {}
            if #parts==0 or #parts>MAX_PARTS then return end
            if serving.n>=BROADCAST_FROM then
                for index,part in ipairs(parts) do self:Enqueue('D',{h=h,p=part,i=index,n=#parts}) end
            else
                for target,requestId in pairs(serving.to) do
                    for index,part in ipairs(parts) do self:Enqueue('D',{id=requestId,p=part,i=index,n=#parts},target) end
                end
            end
        end)
    end
    if not serving.to[sender] then serving.n=serving.n+1 end
    serving.to[sender]=id
end
-- Manifeste demandé : même regroupement (diffusion GUILD à partir de 3 demandeurs)
function Instance:ServeManifest(group,sender)
    local serving=self.manifests[group]
    if not serving then
        serving={to={},n=0};self.manifests[group]=serving
        self:Later(GATHER,function()
            self.manifests[group]=nil
            if serving.n>=BROADCAST_FROM then self:SendManifest(group)
            else for target in pairs(serving.to) do self:SendManifest(group,target) end end
        end)
    end
    if not serving.to[sender] then serving.n=serving.n+1;serving.to[sender]=true end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Nouveau venu : bonjour, réponses de deux membres au plus, puis diffusion de ce qu'il apporte
-- ---------------------------------------------------------------------------------------------------------------------
function Instance:Different(summaries)
    local groups={}
    if type(summaries)~='table' then return groups end
    for _,group in ipairs(self:Groups()) do
        if summaries[group]~=self:Scan(group).summary then groups[#groups+1]=group end
    end
    return groups
end
function Instance:AnswerHello(sender,groups)
    local who=key(sender)
    self.answers[who]=self.answers[who] or 0
    if self.answering[who] then return end
    self.answering[who]=true
    -- 1 à 5 s, sauf si deux membres ont déjà répondu (leurs manifestes suffisent : les données sont recopiées chez tous).
    -- Un membre encore en train de se mettre à jour ne répond qu'en secours (6 à 12 s) : son manifeste serait incomplet.
    local syncing=self.settle or next(self.pending) or next(self.wants)
    self:Later(syncing and 6+math.random()*6 or 1+math.random()*4,function()
        self.answering[who]=nil
        if (self.answers[who] or 0)>=2 then return end
        self:Enqueue('A',{to=sender},nil,true)
        for _,group in ipairs(groups) do self:SendManifest(group,sender) end
    end)
end
-- Après les demandes faites aux membres qui ont répondu : ce que nous avons et qu'ils n'avaient pas part en delta
function Instance:Settle()
    -- (aucune réponse encore : on attend ; sans réponse en 45 s, Hello abandonne de lui-même)
    if not self.settle or not next(self.settle.references) or next(self.pending) or next(self.wants) then return end
    if clock()-self.settle.at<4 then self:Later(3,function() self:Settle() end);return end
    local references=self.settle.references;self.settle=nil
    for group,reference in pairs(references) do self:Push(group,reference) end
    -- Second bonjour 20 s plus tard : s'il reste une différence (un membre qui a répondu n'était pas à jour), on la
    -- comble tout de suite au lieu d'attendre le résumé périodique ; sinon personne ne répond.
    if (self.helloRound or 1)<2 then
        self.helloRound=2
        self:Later(20,function() self:Hello() end)
    end
end
function Instance:Hello()
    self.settle={at=clock(),references={}};self.helloSent=true
    self:Enqueue('H',{s=self:Summaries()},nil,true)
    self:Later(45,function() if self.settle and not next(self.settle.references) then self.settle=nil end end)
end
function Instance:Start()
    if self.started then return end;self.started=true;self.startedAt=clock()
    safe((C_GuildInfo or {}).GuildRoster or GuildRoster)
    self:RefreshRoster()
    self:Later(ROSTER_WAIT+1,function() self:Resume() end)
    -- Bonjour avec nos résumés après quelques secondes (liste de guilde, données des modules relevées à la connexion)
    self:Later(math.random(5,10),function()
        for _,group in ipairs(self:Groups()) do self.baseline[group]=self:Scan(group).set end
        self:Hello()
    end)
    local function periodic()
        self:Announce();self:Later(PERIOD+math.random(0,120),periodic)
    end
    self:Later(PERIOD+math.random(0,120),periodic)
    local function sweep()
        local now=clock()
        for id,b in pairs(self.buffers) do if now-b.at>60 then self.buffers[id]=nil end end
        -- demande sans progrès depuis 60 s : on la remet en attente pour un autre membre (3 essais), sinon on l'oublie
        for h,pending in pairs(self.pending) do
            if now-pending.at>ASK_TIMEOUT then
                self.pending[h]=nil;self.byId[pending.id]=nil
                self.load[pending.senderKey]=math.max(0,(self.load[pending.senderKey] or 1)-1)
                if pending.tries<ASK_TRIES and not self.wants[h] then
                    self.wants[h]={request=pending.request,cands=pending.cands,at=now,tries=pending.tries,avoid=pending.sender}
                end
            end
        end
        if next(self.wants) then self:Dispatch() end
        if self.settle then self:Settle() end
        for who,at in pairs(self.exchanged) do if now-at>PERIOD then self.exchanged[who]=nil end end
        for rateKey,rate in pairs(self.rates) do if now-rate.at>60 then self.rates[rateKey]=nil end end -- compteurs échus
        if self.rosterKnown then safe(self.adapter.Cleanup,self.data,self.roster,stamp()) end
        self:Resume();self:Later(30,sweep)
    end
    self:Later(30,sweep)
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Réception
-- ---------------------------------------------------------------------------------------------------------------------
function Instance:Allow(sender,kind,limit)
    local rateKey=key(sender)..':'..kind
    local rate=self.rates[rateKey]
    if not rate or clock()-rate.at>60 then rate={at=clock(),n=0};self.rates[rateKey]=rate end
    rate.n=rate.n+1
    return rate.n<=limit
end
-- Lot de manifeste (ou delta) reçu : ce qui nous manque devient une demande
function Instance:Consider(wrapper,sender)
    local requests=safe(self.adapter.Need,self.data,wrapper,sender) or {}
    for _,request in ipairs(requests) do self:Want(request,sender) end
end
function Instance:Dispatch2(envelope,sender,channel)
    if type(envelope)~='table' or envelope.v~=2 or type(envelope.d)~='table' then return end
    local kind,data=envelope.k,envelope.d
    local guild=channel=='GUILD'
    if kind=='H' and guild then
        -- Nouveau venu : réponse seulement si nos données diffèrent des siennes
        self.answers[key(sender)]=0
        local groups=self:Different(data.s)
        if #groups>0 then self:AnswerHello(sender,groups) end
    elseif kind=='A' and guild and type(data.to)=='string' then
        local who=key(data.to);self.answers[who]=(self.answers[who] or 0)+1
    elseif kind=='S' and guild then
        -- Résumé périodique : on ne demande le manifeste que pour un état pas encore comparé
        if type(data.s)~='table' then return end
        local wanted={}
        for _,group in ipairs(self:Groups()) do
            local theirs=data.s[group]
            if type(theirs)=='string' and theirs~=self:Scan(group).summary and self.known[key(sender)..'|'..group]~=theirs then wanted[#wanted+1]=group end
        end
        local who=key(sender)
        if #wanted>0 and not self.exchanged[who] then
            self.exchanged[who]=clock()
            self:Later(1+math.random()*7,function() self:Enqueue('W',{g=wanted},sender) end)
        end
    elseif kind=='W' and not guild then
        if type(data.g)~='table' or not self:Allow(sender,'W',20) then return end
        local valid={};for _,group in ipairs(self:Groups()) do valid[group]=true end
        for i,group in ipairs(data.g) do if i<=16 and valid[group] then self:ServeManifest(group,sender) end end
    elseif (kind=='M' or kind=='U') and type(data.m)=='string' and type(data.b)=='table' then
        if not self:Allow(sender,kind,600) then return end
        local wrapper={m=data.m,b=data.b}
        if kind=='M' then
            -- Manifeste complet : sert de référence pour le delta du nouveau venu, puis état comparé
            if self.settle and not guild then
                local reference=self.settle.references[data.m] or {}
                for _,entry in ipairs(data.b) do reference[canon(entry)]=true end
                self.settle.references[data.m]=reference;self.settle.at=clock()
                self:Later(5,function() self:Settle() end)
            end
            if data.i==data.n and type(data.s)=='string' then self.known[key(sender)..'|'..data.m]=data.s end
        end
        self:Consider(wrapper,sender)
    elseif kind=='R' and not guild then
        if type(data.id)~='string' or #data.id>100 or type(data.q)~='table' or not self:Allow(sender,'R',64) then return end
        self:Serve(data.q,sender,data.id)
    elseif kind=='D' then
        local pending
        if guild then
            pending=type(data.h)=='string' and self.pending[data.h]
            if pending and pending.senderKey~=key(sender) then pending=nil end
        else
            pending=type(data.id)=='string' and self.byId[data.id]
            if pending and pending.senderKey~=key(sender) then pending=nil end
        end
        if not pending then return end
        if type(data.i)~='number' or type(data.n)~='number' or data.i%1~=0 or data.n%1~=0
            or data.i<1 or data.i>data.n or data.n>MAX_PARTS then return end
        if pending.total and pending.total~=data.n then return end
        pending.total=data.n
        if pending.received[data.i] then return end
        pending.received[data.i]=true;pending.count=pending.count+1;pending.at=clock()
        if safe(self.adapter.Merge,self.data,data.p,sender,stamp(),pending.request) then safe(self.adapter.Changed,false) end
        if pending.count==data.n then self:Finish(pending) end
    elseif kind=='P' and guild then
        local who=key(sender);local last=self.pongs[who]
        if last and clock()-last<10 then return end
        self.pongs[who]=clock()
        self:Enqueue('O',{t=data.t,i=safe(self.adapter.Info)},sender,true)
    elseif kind=='O' and not guild then
        if self.pingAt and clock()-self.pingAt<30 then safe(self.adapter.Pong,sender,data.i) end
    elseif kind=='X' and type(data.c)=='string' then
        local handler=self.channels[data.c]
        if handler then safe(handler,data.d,sender,channel) end
    end
end
-- realtimeOnly : en combat, seul un message temps réel ('X') est traité ; renvoie false pour un autre (gardé pour après)
function Instance:Payload(encoded,sender,channel,realtimeOnly)
    local compressed=safe(Deflate.DecodeForWoWAddonChannel,Deflate,encoded)
    if not compressed or #compressed>MAX_ENCODED or not Guard:Size(compressed,MAX_RAW) then self.rejected=self.rejected+1;return true end
    local raw=safe(Deflate.DecompressDeflate,Deflate,compressed)
    if not raw or #raw>MAX_RAW then self.rejected=self.rejected+1;return true end
    local ok,success,envelope=pcall(Serializer.Deserialize,Serializer,raw)
    if not ok or not success then self.rejected=self.rejected+1;return true end
    if realtimeOnly and (type(envelope)~='table' or envelope.k~='X') then return false end
    -- Forever : expéditeur remis sous la forme de la liste de guilde (« Prénom-Nom » → « Prénom Nom ») pour les modules
    if regional() then sender=Lib.DisplayName(sender) end
    self:Dispatch2(envelope,sender,channel)
    return true
end
function Instance:Receive(prefix,text,channel,sender)
    if not self.enabled or prefix~=self.prefix or (channel~='GUILD' and channel~='WHISPER') then return end
    if type(text)~='string' or #text>255 or type(sender)~='string' or #sender>100 then return end
    if self:IsSelf(sender) then return end
    -- Autre guilde que celle de l'addon (conteneur) : rien n'est lu
    if self.adapter.Blocked and safe(self.adapter.Blocked)=='refuse' then return end
    -- Le canal GUILD n'arrive que des membres (le serveur s'en charge) ; un chuchotement doit venir d'un membre.
    if channel=='WHISPER' and self.rosterKnown and not self:Member(sender) then self.stats.strangers=self.stats.strangers+1;return end
    local id,part,total,chunk=text:match('^2:([%w%-]+):(%d+):(%d+):(.*)$')
    if not id or #id>60 or #part>4 or #total>4 or #chunk>210 then self.rejected=self.rejected+1;return end
    part,total=tonumber(part),tonumber(total)
    if part<1 or total<1 or part>total or total>320 then return end
    local bufferKey=key(sender)..':'..channel..':'..id
    local buffer=self.buffers[bufferKey]
    if not buffer then
        if count(self.buffers)>=24 then return end
        buffer={parts={},count=0,total=total,size=0,at=clock()};self.buffers[bufferKey]=buffer
        local current=buffer
        self:Later(60,function() if self.buffers[bufferKey]==current then self.buffers[bufferKey]=nil end end)
    end
    if clock()-buffer.at>60 or buffer.total~=total then self.buffers[bufferKey]=nil;return end
    if not buffer.parts[part] then buffer.parts[part]=chunk;buffer.count=buffer.count+1;buffer.size=buffer.size+#chunk end
    if buffer.size>MAX_ENCODED then self.buffers[bufferKey]=nil;return end
    if buffer.count==total then
        self.buffers[bufferKey]=nil
        local encoded=table.concat(buffer.parts)
        self.stats.received=self.stats.received+1;self.stats.lastFrom=sender
        if not self.rosterKnown then self:RefreshRoster() end
        -- Sans liste de guilde, les modules ne peuvent pas vérifier les membres : on garde le message pour plus tard.
        -- En raid chargé, seuls les gros messages (plusieurs parties) attendent ; un message court passe tout de suite.
        local busy,reason=self:Busy()
        if (busy and (reason~='raid chargé' or total>1)) or self:WaitRoster() then
            -- En combat, un message temps réel (SOS, alerte levée, layer) est livré tout de suite ; la synchro attend
            if reason=='combat' and not self:WaitRoster() and self:Payload(encoded,sender,channel,true) then return end
            if #self.deferredInput<64 then self.deferredInput[#self.deferredInput+1]={encoded=encoded,sender=sender,channel=channel,at=clock()} end
        else self:Payload(encoded,sender,channel) end
    end
end
function Instance:Resume()
    if self:Busy() then
        -- Toujours occupé (combat, raid chargé) : on revérifie dans 1 s tant qu'il reste quelque chose à envoyer.
        -- Les messages temps réel passent quand même si seul le raid chargé retient la synchro.
        self:Pump()
        if self:Queued()>0 or self.announcePending then self:Wake() end
        return
    end
    if self.announcePending then self.announcePending=false;self:Announce() end
    local deferred=self.deferredInput;self.deferredInput={}
    if self:WaitRoster() then self.deferredInput=deferred;self:Pump();return end
    for _,entry in ipairs(deferred) do
        -- (liste toujours inconnue : même règle qu'à la réception directe, on accepte)
        if clock()-entry.at<=120 and (entry.channel=='GUILD' or not self.rosterKnown or self:Member(entry.sender)) then
            self:Payload(entry.encoded,entry.sender,entry.channel)
        end
    end
    self:Pump()
end
-- Message temps réel d'un module (ex. Ride) : priorité sur la synchro, livré au gestionnaire Listen(channel).
function Instance:Message(channel,data,target)
    if type(channel)~='string' or #channel>24 then return end
    self:Enqueue('X',{c=channel,d=data},target,true)
end
function Instance:Listen(channel,handler) self.channels[channel]=handler end
function Instance:Status()
    local busy,reason=self:Busy()
    return {enabled=self.enabled,queued=self:Queued(),buffers=count(self.buffers),
        deferred=busy and reason or 'non',rejected=self.rejected,roster=count(self.roster),rosterKnown=self.rosterKnown,
        waiting=#self.deferredInput,sent=self.stats.sent,failed=self.stats.failed,lastResult=self.stats.lastResult,
        received=self.stats.received,lastFrom=self.stats.lastFrom,strangers=self.stats.strangers,prefix=self.prefixResult,
        retries=self.stats.retries,pending=count(self.pending),wants=count(self.wants),messages=self.stats.messages,
        ctl=ChatThrottleLib and ChatThrottleLib.version,regional=regional(),player=Lib.PlayerName()}
end
function Lib:Register(prefix,data,adapter)
    assert(type(prefix)=='string' and #prefix>0 and #prefix<=16 and type(data)=='table' and type(adapter)=='table')
    self.instances=self.instances or {}
    if self.instances[prefix] then return self.instances[prefix] end
    local object=setmetatable({prefix=prefix,data=data,adapter=adapter,enabled=true,channels={},buffers={},roster={},rates={},
        lanes={G={queue={},urgent={}},W={queue={},urgent={}}},
        scans={},baseline={},known={},exchanged={},wants={},pending={},byId={},load={},serving={},manifests={},answers={},answering={},
        pongs={},stats={sent=0,failed=0,retries=0,received=0,strangers=0,messages={}},createdAt=clock(),
        deferredInput={},serial=0,requestSerial=0,rejected=0,epoch=1,nonce=tostring(stamp())..'-'..math.random(100000,999999)},Instance)
    self.instances[prefix]=object
    object.prefixResult=safe(C_ChatInfo.RegisterAddonMessagePrefix,prefix)
    local frame=CreateFrame('Frame');object.frame=frame
    for _,event in ipairs({'CHAT_MSG_ADDON','PLAYER_REGEN_ENABLED','GUILD_ROSTER_UPDATE','GROUP_ROSTER_UPDATE','PLAYER_ENTERING_WORLD'}) do safe(frame.RegisterEvent,frame,event) end
    frame:SetScript('OnEvent',function(_,event,...)
        if event=='CHAT_MSG_ADDON' then safe(object.Receive,object,...)
        elseif event=='GUILD_ROSTER_UPDATE' then safe(object.RefreshRosterSoon,object)
        else safe(object.Resume,object) end
    end)
    return object
end
