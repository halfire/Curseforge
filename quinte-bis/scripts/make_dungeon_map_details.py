"""Portraits et repères liés aux objectifs : Forever prioritaire, référence Classic explicite.
Usage : PYTHONPATH=<lupa> python3 scripts/make_dungeon_map_details.py <ClassicDB.sql.gz> <cache WarcraftDB>
Ne projette jamais de coordonnées extérieures sur un plan intérieur. Les positions viennent exclusivement
DU plan déjà référencé ; les relations de quêtes sont recoupées avec leurs textes Forever existants.
"""
from pathlib import Path
import gzip,re,json,html,hashlib,sys
from lupa.lua51 import LuaRuntime
root=Path(__file__).resolve().parents[1];suite=root.parent;cache=Path(sys.argv[2]);db=Path(sys.argv[1])
sql=gzip.open(db,'rt',errors='replace').read()
token=re.compile(r"'(?:\\.|[^'\\])*'|[^,]+")
row_re=re.compile(r"\((?:'(?:\\.|[^'\\])*'|[^()'])*\)")
def value(s):
 if s=='NULL':return None
 if s.startswith("'"):return s[1:-1].replace("\\'","'").replace('\\n','\n').replace('\\r','\r').replace('\\\\','\\')
 try:return int(s)
 except ValueError:return s

def table(name,fields):
 schema=re.search(r'CREATE TABLE `'+name+r'` \((.*?)\) ENGINE',sql,re.S)
 cols=[s.lower() for s in re.findall(r'^  `([^`]+)`',schema[1],re.M)]
 ix=[cols.index(f.lower()) for f in fields]
 for insert in re.finditer(r'INSERT INTO `'+name+r'` VALUES (.*?);\n',sql,re.S):
  for row in row_re.finditer(insert[1]):
   vals=token.findall(row[0][1:-1]);yield tuple(value(vals[i]) for i in ix)
def norm(s):return re.sub(r'[^a-z0-9]','',html.unescape(s or '').lower())
def quote(s):return json.dumps(s,ensure_ascii=False)

lua=LuaRuntime(unpack_returned_tuples=True);lua.execute('Q={}')
for n in ['DungeonMapData.lua','DungeonQuests.lua','DungeonQuestPlaces.lua']:
 lua.execute('assert(loadstring(...))("quinte-group",Q)',((root if n == 'DungeonMapData.lua' else suite/'quinte-group')/n).read_text())
q=lua.globals().Q
names={}
for row in table('creature_template',['entry','name','modelid1','lootid']):names[int(row[0])]=row
byname={norm(v[1]):v for v in names.values()}
items={int(i):name for i,name in table('item_template',['entry','name'])}
quests={int(row[0]):row for row in table('quest_template',['entry','title',*[f'ReqItemId{i}' for i in range(1,5)]])}
drops={}
for entry,item in table('creature_loot_template',['entry','item']):drops.setdefault(int(entry),set()).add(int(item))
ids={}
for code,entry in json.loads((suite/'quinte-bis/scripts/data/zones_part1.json').read_text()).items():
 for nid,name,_ in entry['bosses']:ids[norm(name)]=int(nid)
for f in (suite/'quinte-bis/scripts/data').glob('bosses_b*.json'):
 for _,name,npcs,_ in json.loads(f.read_text()):
  if npcs:ids[norm(name)]=int(npcs[0])
portraits={};provenance={};boss_items={}
for info in q.DUNGEON_MAPS.values():
 for boss in info['bosses'].values():
  name=boss['name'];legacy=byname.get(norm(name));nid=ids.get(norm(name)) or (legacy and legacy[0])
  display,origin=None,None
  node=cache/f'npc{nid}.json';node_data=json.loads(node.read_text()) if node.exists() else {}
  models=node_data.get('extra',{}).get('models',[])
  if models:display,origin=int(models[0]['id']),'WarcraftDB Forever'
  elif nid in names:display,origin=int(names[nid][2]),'CMaNGOS Classic (référence visuelle)'
  if display and display>0:
   portraits[name]={'npc':nid,'display':display}
   provenance[name]={'npc':nid,'display':display,'source':origin,'url':f'https://forever.warcraftdb.com/data/npc/{nid}' if models else 'https://github.com/cmangos/classic-db/tree/master/Full_DB'}
  if nid in names:boss_items[name]=drops.get(int(names[nid][3]),set())

wh=json.loads((suite/'quinte-group/scripts/data/wowhead_forever_quests.json').read_text());wd=json.loads((suite/'quinte-group/scripts/data/warcraftdb_objectives.json').read_text())
lines=['local _, Q = ...','-- Généré par scripts/make_dungeon_map_details.py ; sources et SHA-256 dans scripts/data/dungeon_map_details_sources.json.',
 '-- Modèles : WarcraftDB Forever, sinon CMaNGOS Classic GPL-3.0 (référence visuelle). API et visuels du client prioritaires.',
 '-- Positions : plan Classic déjà embarqué, indicatif sur Forever. Aucune position inconnue ou extérieure projetée.', 'Q.DUNGEON_BOSS_PORTRAITS = {']
for name,meta in sorted(portraits.items()):lines.append(f' [{quote(name)}] = {{ npc = {meta["npc"]}, display = {meta["display"]} }},')
lines+=['}','Q.DUNGEON_MAP_QUEST_DETAILS = {']
relations={};pin_count=0
for code,rows in sorted(q.DUNGEON_QUESTS.items()):
 lines.append(f' [{quote(code)}] = {{')
 map_info=q.DUNGEON_MAPS[code]
 for row in rows.values():
  quest_id=int(row[1]);w=wh.get(str(quest_id),{});o=wd.get(str(quest_id),{});facts=w.get('facts',[])
  def fact(tag):
   try:return facts[facts.index(tag)+1]
   except (ValueError,IndexError):return ''
  node_path=cache/f'quest{quest_id}.json'
  node=json.loads(node_path.read_text()).get('data',{}) if node_path.exists() else {}
  def endpoint(field):
   text=node.get(field) or ''
   return html.unescape(re.sub('<[^>]+>','',text)).strip()
  start,end=fact('Start:') or endpoint('starts'),fact('End:') or endpoint('ends');text=html.unescape(w.get('obj') or o.get('log',''));text_key=norm(text)
  objnames=' '.join(o.get('objectives',[]));sourceq=quests.get(quest_id)
  verified_items=[]
  if sourceq and norm(sourceq[1])==norm(row[3]):
   verified_items=[i for i in sourceq[2:] if i and norm(items.get(i,'')) and norm(items[i]) in norm(objnames+' '+text)]
  start_items={i for i,name in items.items() if norm(start) and norm(name)==norm(start)}
  pins=[]
  if map_info:
   for boss in map_info['bosses'].values():
    bname=boss['name'];bkey=norm(bname);kind=None
    if bkey and bkey==norm(start):kind='start'
    elif bkey and bkey==norm(end):kind='finish'
    elif any(i in boss_items.get(bname,set()) for i in start_items):kind='start'
    elif bkey and bkey in text_key:kind='objective'
    elif any(i in boss_items.get(bname,set()) for i in verified_items):kind='objective'
    if kind:pins.append({'target':bname,'kind':kind,'floor':int(boss['floor']),'x':round(boss['x'],5),'y':round(boss['y'],5)})
  bits=[]
  for label,val in [('title',row[3]),('start',start),('finish',end),('objective',text)]:
   if val:bits.append(label+' = '+quote(val))
  bits.append('pins = { '+', '.join('{ target = '+quote(p['target'])+', kind = '+quote(p['kind'])+f', floor = {p["floor"]}, x = {p["x"]}, y = {p["y"]}'+' }' for p in pins)+' }')
  lines.append(f'  [{quest_id}] = {{ '+', '.join(bits)+' },')
  if pins:relations.setdefault(code,{})[str(quest_id)]=pins;pin_count+=len(pins)
 lines.append(' },')
lines.append('}')
(root/'DungeonMapDetails.lua').write_text('\n'.join(lines)+'\n')
summary={'generated':'2026-11-09','classic_db':{'url':'https://github.com/cmangos/classic-db/blob/master/Full_DB/ClassicDB_1_12_1_z2815.sql.gz','sha256':hashlib.sha256(db.read_bytes()).hexdigest(),'license':'GPL-3.0'},'portraits':provenance,'quest_relations':relations,'quest_sources':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [suite/'quinte-group/scripts/data/wowhead_forever_quests.json',suite/'quinte-group/scripts/data/warcraftdb_objectives.json']},'limitations':'Positions intérieures non connues omises ; aucune coordonnée extérieure convertie. Référence Classic indiquée.'}
(root/'scripts/data/dungeon_map_details_sources.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print(len(portraits),'portraits,',pin_count,'relations positionnées,',sum(len(v) for v in relations.values()),'quêtes positionnées')
