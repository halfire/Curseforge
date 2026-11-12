#!/usr/bin/env python3
"""Import reproductible du dossier fourni par le GM : faits, plans et portraits FDJ 2.0.
Aucun code d'interface FDJ n'est chargé dans WoW ; les données sont normalisées pour nos composants.
"""
import argparse, hashlib, json, re, shutil
from datetime import date
from pathlib import Path
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
GROUP=ROOT.parent/'quinte-group'
NAMES={'Hall of Thanes':'THANES','Ruins of Lordaeron':'LORDAERON','Excavation Site: Wetlands':'EXCAV','City of Dalaran':'DALARAN','The Drowned City':'DROWNED',"Krol'dok Stronghold":'KROLDOK','Alcaz Prison':'ALCAZ','Blackmaw Hold':'BLACKMAW',"Shaper's Terrace":'SHAPER','Ragefire Chasm':'RFC','Wailing Caverns':'WC','The Deadmines':'DM','Shadowfang Keep':'SFK','The Stockade':'STOCKS','Blackfathom Deeps':'BFD','Gnomeregan':'GNOMER','Razorfen Kraul':'RFK','Razorfen Downs':'RFD','Uldaman':'ULDA',"Zul'Farrak":'ZF','Maraudon':'MARA','Sunken Temple':'ST','Blackrock Depths':'BRD','Lower Blackrock Spire':'LBRS','Upper Blackrock Spire':'UBRS','Dire Maul: East':'DME','Dire Maul: West':'DMW','Dire Maul: North':'DMN','Scarlet Monastery: Graveyard':'SM_GY','Scarlet Monastery: Library':'SM_LIB','Scarlet Monastery: Armory':'SM_ARM','Scarlet Monastery: Cathedral':'SM_CATH','Stratholme: Living':'STRAT','Stratholme: Undead':'STRAT','Scholomance':'SCHOLO'}
def literal(source,assignment):
    start=source.index('{',source.index(assignment)); i=start; depth=0
    # Les commentaires et chaînes sont ignorés pour compter les accolades de la table.
    token=re.compile(r'--\[\[.*?\]\]|--[^\n]*|\[\[.*?\]\]|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{}]',re.S)
    for m in token.finditer(source,start):
        t=m.group()
        if t=='{':depth+=1
        elif t=='}':
            depth-=1
            if depth==0:return source[start:m.end()]
    raise ValueError(assignment)
def native(value):
    if hasattr(value,'items'):
        d={k:native(v) for k,v in value.items() if not (callable(v) and not hasattr(v,'items'))}
        if d and set(d)==set(range(1,len(d)+1)):return [d[i] for i in range(1,len(d)+1)]
        return d
    return value

def lua(v):
    if v is None:return 'nil'
    if v is True:return 'true'
    if v is False:return 'false'
    if isinstance(v,str):return '"'+v.replace('\\','\\\\').replace('"','\\"').replace('\n','\\n').replace('\r','\\r')+'"'
    if isinstance(v,(int,float)):return str(v)
    if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
    return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in sorted(v.items(),key=lambda kv:str(kv[0])))+'}'
def write(path,fields,source="ForeverDungeonJournal 2.0 (10/11/2026)"):
    path.write_text('-- Généré par scripts/import_fdj.py ; référence fournie '+source+'.\nlocal _, Q = ...\n'+'\n'.join('Q.'+k+' = '+lua(v) for k,v in sorted(fields.items()))+'\n')
def main():
    ap=argparse.ArgumentParser();ap.add_argument('source',type=Path)
    ap.add_argument('--quests-only', action='store_true', help='Mettre à jour seulement les quêtes et leurs repères')
    args=ap.parse_args();src=args.source
    version=re.search(r'^## Version:\s*(.+)$',(src/'ForeverDungeonJournal.toc').read_text(),re.M).group(1)
    source=f'ForeverDungeonJournal {version}, dossier fourni le {date.today().isoformat()}'
    vm=LuaRuntime(unpack_returned_tuples=True,register_eval=False,register_builtins=False)
    vm.execute("os=nil;io=nil;package=nil;require=nil;dofile=nil;loadfile=nil;python=nil;FDJ={Constants={ALBA_FAIRMOON_LOCATION='Alba Fairmoon'},FOREVER_QUEST_XP_FALLBACK={}};_G.ForeverDungeonJournal_NS=FDJ;CreateFrame=function() return {RegisterEvent=function()end,SetScript=function()end} end")
    used={}
    for filename in ('ForeverDungeonJournal.toc', 'Localization/Content_frFR.lua'):
        used[filename]=hashlib.sha256((src/filename).read_bytes()).hexdigest()
    previous={}
    if args.quests_only:
        vm.execute('PREVIOUS={}')
        vm.execute('assert(loadstring(...))("bis",PREVIOUS)',(ROOT/'DungeonReference.lua').read_text())
        previous=native(vm.globals().PREVIOUS)
    # Les mises à jour tierces choisissent parfois le donneur selon la faction.
    vm.execute('UnitFactionGroup=function() return "Alliance" end')
    vm.execute('assert(loadstring(...))("ForeverDungeonJournal",FDJ)',(src/'Localization/Content_frFR.lua').read_text())
    vm.execute('BASE={}')
    vm.execute('assert(loadstring(...))("bis",BASE)',(ROOT/'DungeonMapQuestInfo.lua').read_text())
    baseline=native(vm.globals().BASE.DUNGEON_MAP_QUEST_INFO)
    vm.execute('assert(loadstring(...))("bis",BASE)',(ROOT/'DungeonMapQuests.lua').read_text())
    vm.execute('assert(loadstring(...))("group",BASE)',(GROUP/'DungeonQuests.lua').read_text())
    known_lists=native(vm.globals().BASE.DUNGEON_QUESTS)
    known_rows={(q[0] if isinstance(q,list) else q[1]):q for rows in known_lists.values() for q in rows}
    known_names={(q[2] if isinstance(q,list) else q[3]):(q[0] if isinstance(q,list) else q[1]) for rows in known_lists.values() for q in rows}
    vm.execute('assert(loadstring(...))("bis",BASE)',(GROUP/'DungeonQuestPlaces.lua').read_text())
    known_places=native(vm.globals().BASE.DUNGEON_QUEST_PLACES)
    zones={p['map']:p.get('zone') for p in known_places.values() if p.get('map') and p.get('zone')}

    new_content=src/'Localization/Content_NewDungeons.lua'
    if new_content.exists():
        used['Localization/Content_NewDungeons.lua']=hashlib.sha256(new_content.read_bytes()).hexdigest()
        vm.execute('assert(loadstring(...))("ForeverDungeonJournal",FDJ)',new_content.read_text())

    for f in ['Data/Dungeons.lua','Data/SharedLoot.lua','Data/Bosses.lua','Data/QuestMaps.lua','Data/QuestChains.lua','Data/QuestRewards.lua','Data/QuestShareability.lua','Data/QuestUpdates.lua']:
        text=(src/f).read_text();used[f]=hashlib.sha256((src/f).read_bytes()).hexdigest()
        vm.execute('assert(loadstring(...))("ForeverDungeonJournal",FDJ)',text)
    verified=src/'Localization/Content_Verified.lua'
    if verified.exists():
        used['Localization/Content_Verified.lua']=hashlib.sha256(verified.read_bytes()).hexdigest()
        vm.execute('assert(loadstring(...))("ForeverDungeonJournal",FDJ)',verified.read_text())
    expr=literal((src/'Core/Journal.lua').read_text(),'FDJ.DUNGEON_MAPS =')
    maps=native(vm.execute('return '+expr));fdj=vm.globals().FDJ
    db=native(fdj.DB);chains=native(fdj.QUEST_PREREQ_CHAINS);details=native(fdj.QUEST_PREREQ_DETAILS)
    starts=native(fdj.QUEST_START_MAPS);pins=native(fdj.MAP_QUEST_PINS);displays=native(fdj.STATIC_DISPLAY_IDS)
    used['Core/Journal.lua']=hashlib.sha256((src/'Core/Journal.lua').read_bytes()).hexdigest()
    zones.update({1416:'Alterac Mountains',1424:'Hillsbrad Foothills',1418:'Badlands',1443:'Desolace',1440:'Ashenvale',1444:'Feralas',1449:"Un'Goro Crater",1422:'Western Plaguelands',1423:'Eastern Plaguelands',1446:'Tanaris',1427:'Searing Gorge',1428:'Burning Steppes'})
    outmaps={};quests={};questmeta={};places={};portraits={};loot={};assets={};equipment={};owners={};turnins={}
    frq=native(fdj.ContentLocales.frFR.quests)
    translations=ROOT/'scripts/data/fdj_quest_fr.json'
    for key, fields in json.loads(translations.read_text()).items():
        frq.setdefault(int(key),{}).update(fields)
    used['Localization/Content_frFR.lua']=hashlib.sha256((src/'Localization/Content_frFR.lua').read_bytes()).hexdigest()
    def asset(path):
        if not isinstance(path,str) or 'ForeverDungeonJournal\\Media\\' not in path:return path
        rel='Media/'+path.split('ForeverDungeonJournal\\Media\\',1)[1].replace('\\','/')
        if not Path(rel).suffix:rel+='.tga'
        dest=ROOT/'Media/FDJ'/Path(rel).relative_to('Media');dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(src/rel,dest);assets[str(dest.relative_to(ROOT))]=hashlib.sha256(dest.read_bytes()).hexdigest()
        return str(dest.relative_to(ROOT)).replace('/','\\')
    def point(p):
        if not isinstance(p,dict) or not p.get('mapID') or p.get('x') is None or p.get('y') is None:return None
        return {'map':p['mapID'],'x':p['x']*100,'y':p['y']*100,'start':p.get('targetName') or p.get('label'),'patrol':p.get('patrol'),'zone':zones.get(p['mapID'],'Carte '+str(p['mapID']))}
    for name,code in NAMES.items():
        d=db.get(name,{})
        bosses=d.get('bosses',[])
        for b in bosses:
            if not isinstance(b,dict) or not b.get('name'):continue
            npc=b.get('npcID') or b.get('portraitNpcID');display=b.get('displayID') or displays.get(npc)
            if display and not args.quests_only:
                portrait=src/f'Media/Portraits/{display}.tga'
                portraits[b['name']]={'display':display}
                if portrait.exists():portraits[b['name']]['image']=asset('Interface\\AddOns\\ForeverDungeonJournal\\Media\\Portraits\\'+str(display))
            if b.get('customIcon') and not args.quests_only:
                custom=b['customIcon']
                portraits[b['name']]={'image':asset(custom)} if 'ForeverDungeonJournal' in custom else {'icon':custom}
            items=b.get('loot',[])
            loot.setdefault(code,[]).append({'name':b['name'],'items':items})
            if not b.get('trash'):
                portable=[]
                slotnames={'Head':'HEAD','Neck':'NECK','Shoulder':'SHOULDER','Back':'CLOAK','Chest':'CHEST','Wrist':'WRIST','Hands':'HAND','Waist':'WAIST','Legs':'LEGS','Feet':'FEET','Finger':'FINGER','Trinket':'TRINKET','Two-Hand':'2HWEAPON','One-Hand':'WEAPON','Main Hand':'WEAPONMAINHAND','Off Hand':'HOLDABLE','Shield':'SHIELD','Ranged':'RANGED','Relic':'RELIC','Thrown':'THROWN'}
                for item in items:
                    def field(index):return item[index-1] if isinstance(item,list) and len(item)>=index else item.get(index) if isinstance(item,dict) else None
                    iid,title,kind,quality=field(1),field(2),field(3),field(4)
                    slot='SHIELD' if isinstance(kind,str) and 'Shield' in kind else slotnames.get((kind or '').split(',')[0])
                    if isinstance(iid,(int,float)) and iid>0 and slot and isinstance(quality,(int,float)) and quality>=2:portable.append([iid,slot,title])
                equipment.setdefault(code,[]).append({'name':b['name'],'items':portable})
        if name in maps:
            m=maps[name];floors=m.get('floors',[]);bossmap=m.get('bosses',[])
            for f in floors:
                if 'texture' in f and not args.quests_only:f['image']=asset(f.pop('texture'))
                if not args.quests_only:
                    for patch in f.get('patches',[]):patch['image']=asset(patch.pop('tex'))
            base=len(outmaps.get(code,{}).get('floors',[]))
            for b in bossmap:b['floor']=b.get('floor',1)+base
            for p in m.get('entrances',[]):p['floor']=p.get('floor',1)+base
            if code in outmaps:
                outmaps[code]['floors']+=floors;outmaps[code]['bosses']+=bossmap
            else:outmaps[code]=m
        for q in d.get('quests',[]):
            if not isinstance(q,dict) or not q.get('id') or q.get('faction')=='Horde':continue
            # Récolte extérieure seulement : pas de quête de donjon démontrée pour ce numéro.
            if q['id']==92067:continue
            sourceid=q['id']
            if sourceid <= 0:
                if q.get('name') not in known_names:continue
                q={**q,'id':known_names[q['name']]}
            qid=q['id'];chain=chains.get(sourceid,chains.get(qid,[]))
            # FDJ choisit parfois la récompense hors donjon comme tête de chaîne ; le GM veut l'étape du donjon.
            replacement={1806:1654,92819:92753,2948:2945,98824:95810,98423:96393,96016:96264,1782:1701,2361:2201,2439:2278,95263:95262,96337:96335}.get(qid)
            if replacement:
                target=replacement
                q=next((candidate for candidate in d.get('quests',[]) if candidate.get('id')==target),{'id':target,'name':baseline.get(target,{}).get('title') or next((st['name'] for st in chain if st.get('id')==target),q['name']),'level':q.get('level'),'requires':q.get('requires'),'classOnly':q.get('classOnly')})
                q={**q,**details.get(target,{}),'hideFromMainList':False};qid=target
            prereqs=[];seen=set()
            for step in chain:
                sid=step.get('id')
                if sid==qid:break
                if sid and sid>0 and sid not in seen:prereqs.append({'id':sid,'title':step.get('name')});seen.add(sid)
            owners[sourceid]=qid
            info=details.get(qid,{})
            combined={**info,**q}
            # La fiche de référence distingue déjà les étapes masquées de la vraie quête du donjon.
            if not q.get('hideFromMainList'):
                quests.setdefault(code,[])
                if not any(x[0]==qid for x in quests[code]):quests[code].append([qid,(known_rows[qid][1] if isinstance(known_rows[qid],list) else known_rows[qid][2]) if qid in known_rows else q.get('level') or 1,q['name'],(known_rows[qid][3] if isinstance(known_rows[qid],list) else known_rows[qid][4]) if qid in known_rows else q.get('requires') or 1])
                current=next(row for row in quests[code] if row[0]==qid)
                # Correction explicite dans cette mise à jour ; autres niveaux déjà recoupés conservés.
                if qid == 92457:
                    current[3]=max(current[3] or 1,combined.get('requires') or 1)
            questmeta[qid]={'title':q['name'],'prereqs':prereqs,'class':{'WARRIOR':1,'PALADIN':2,'HUNTER':4,'ROGUE':8,'PRIEST':16,'SHAMAN':64,'MAGE':128,'WARLOCK':256,'DRUID':1024}.get(q.get('classOnly'),baseline.get(qid,{}).get('class')),'start':combined.get('pickup'),'finish':combined.get('turnin'),'objective':combined.get('objective'),'note':combined.get('note'),'description':combined.get('description')}
            for sid,meta in [(qid,{**info,**q})]+[(s['id'],details.get(s['id'],{})) for s in prereqs]:
                p=point(meta.get('startMap') or meta.get('map') or starts.get(sourceid if sid==qid else sid))
                destination=point(meta.get('turninMap'))
                if destination:turnins[sid]=destination
                if p:places[sid]=p
                elif meta.get('pickup'):places.setdefault(sid,{'start':meta['pickup'],'at':'inside' if meta.get('startsInDungeon') else None})
                if sid not in questmeta:questmeta[sid]={'title':next((s['title'] for s in prereqs if s['id']==sid),'quête '+str(sid)),'start':meta.get('pickup'),'finish':meta.get('turnin'),'objective':meta.get('objective'),'note':meta.get('note'),'description':meta.get('description')}
    mentioned={q.get('id') for d in db.values() for q in d.get('quests',[]) if isinstance(q,dict)}
    for chain in chains.values():
        for step in chain:
            if isinstance(step,dict):mentioned.add(step.get('id'))
    # Une absence du dossier de référence n'invalide pas une quête Forever déjà vérifiée.
    for code,rows in known_lists.items():
        for raw in rows:
            field=lambda i:(raw[i-1] if len(raw)>=i else None) if isinstance(raw,list) else raw.get(i)
            qid=field(1)
            if qid in mentioned or baseline.get(qid,{}).get('outside') or any(r[0]==qid for r in quests.get(code,[])):continue
            quests.setdefault(code,[]).append([qid,field(2),field(3),field(4)])
            questmeta[qid]={'title':field(3),'prereqs':[],'class':field(6) or baseline.get(qid,{}).get('class')}
            if qid in known_places:places[qid]=known_places[qid]
    interior={}
    for name,points in pins.items():
        code=NAMES.get(name)
        if not code:continue
        base=1 if name=='Stratholme: Undead' else 0
        for p in points:
            for spot in p.get('spots',[]):
                for q in spot.get('quests',[]):
                    for act in q.get('acts',[]):
                        ids={q['id'],owners.get(q.get('main',q['id']),q.get('main',q['id']))}
                        for qid in ids:
                            if qid>0:interior.setdefault(code,{}).setdefault(qid,[]).append({'x':p['x'],'y':p['y'],'floor':p.get('floor',1)+base,'target':spot.get('name') or spot.get('npc') or 'Objectif','kind':{'start':'start','end':'finish'}.get(act,'objective'),'reference':True})

    for qid, meta in questmeta.items():
        translated=frq.get(qid,{})
        if translated.get('name'):meta['title']=translated['name']
        for target,field in [('start','pickup'),('finish','turnin'),('objective','objective'),('note','note'),('description','description')]:
            if translated.get(field):meta[target]=translated[field]
        meta['objectiveFR']=translated.get('objective')
        meta['noteFR']=translated.get('note')
        if qid in places and not places[qid].get('map') and translated.get('pickup'):
            places[qid]['start']=translated['pickup']
        for step in meta.get('prereqs',[]):
            step['title']=frq.get(step['id'],{}).get('name',step['title'])
    for rows in quests.values():
        for row in rows:row[2]=questmeta[row[0]]['title']
    fields={'REFERENCE_QUESTS':quests,'REFERENCE_QUEST_INFO':questmeta,'REFERENCE_QUEST_PLACES':places,
            'REFERENCE_QUEST_TURNINS':turnins,'REFERENCE_QUEST_PINS':interior}
    if args.quests_only:
        # Une absence dans la nouvelle référence ne supprime pas un fait déjà connu.
        for key in ('REFERENCE_QUEST_INFO','REFERENCE_QUEST_PLACES','REFERENCE_QUEST_TURNINS'):
            merged=dict(previous.get(key,{}))
            for qid, value in fields[key].items():
                merged[qid]={**merged.get(qid,{}),**{k:v for k,v in value.items() if v is not None}}
            fields[key]=merged
        for code, rows in previous['REFERENCE_QUESTS'].items():
            current=quests.setdefault(code,[])
            seen={row[0] for row in current}
            for row in rows:
                if row[0] not in seen:current.append(row)
        for code, old in previous['REFERENCE_QUEST_PINS'].items():
            target=interior.setdefault(code,{})
            for qid, points in old.items():
                if qid not in target:target[qid]=points
        previous.update(fields)
        write(ROOT/'DungeonReference.lua',previous,source)
    else:
        fields.update({'REFERENCE_MAPS':outmaps,'REFERENCE_PORTRAITS':portraits,'REFERENCE_EQUIPMENT':equipment})
        write(ROOT/'DungeonReference.lua',fields,source)
    write(GROUP/'DungeonReference.lua',{key:fields[key] for key in (
        'REFERENCE_QUESTS','REFERENCE_QUEST_INFO','REFERENCE_QUEST_PLACES','REFERENCE_QUEST_TURNINS')},source)
    if args.quests_only:
        report={'source':source,'files':used}
        (GROUP/'ThirdParty/FDJ-quest-update.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        (ROOT/'scripts/data/fdj_quest_update.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        print({'source':source,'quests':sum(len(rows) for rows in quests.values()),'places':len(fields['REFERENCE_QUEST_PLACES'])})
        return
    vm.execute('assert(loadstring(...))("bis",BASE)',(ROOT/'DungeonLoot.lua').read_text())
    existing=native(vm.globals().BASE.DUNGEON_LOOT)
    prior={}
    for row in existing:
        for boss in row['bosses']:
            for item in boss['items']:
                iid=item[0] if isinstance(item,list) else item[1]
                prior.setdefault(row['key'],{}).setdefault(iid,[]).append(boss['name'])
    audit=[]
    for code,bosses in equipment.items():
        for boss in bosses:
            for iid,slot,title in boss['items']:
                previous=prior.get(code,{}).get(iid,[])
                if boss['name'] not in previous:audit.append({'instance':code,'boss_reference':boss['name'],'item':iid,'title':title,'boss_precedent':previous,'type':'rencontre partagée ou groupée' if previous else 'complément'})
    (ROOT/'scripts/data/fdj_loot_audit.json').write_text(json.dumps({'differences':audit,'note':'Absence dans FDJ non considérée comme preuve de retrait. Objets probableLoot exclus, identifiants manquants ignorés.'},ensure_ascii=False,indent=2)+'\n')
    manifest={'source':'ForeverDungeonJournal 2.0, dossier fourni par le GM le 10/11/2026','files':used,'assets':assets,'maps':len(outmaps),'quests':sum(len(x) for x in quests.values()),'places':len(places)}
    (GROUP/'ThirdParty').mkdir(exist_ok=True)
    (GROUP/'ThirdParty/FDJ-sources.json').write_text(json.dumps({'source':manifest['source'],'files':used},ensure_ascii=False,indent=2)+'\n')
    (ROOT/'scripts/data/fdj_sources.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print({k:v for k,v in manifest.items() if k not in ['files','assets']})
if __name__=='__main__':main()
