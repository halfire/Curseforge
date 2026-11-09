"""Assemble les tuiles Blizzard du miroir Gethe en cartes BLP2 (DXT1).
Les images Blizzard ne sont pas celles de Naowh. PIL/Pillow et lupa requis.
Les sources sont épinglées et toutes les empreintes conservées dans Media/Maps/sources.json.
"""
from pathlib import Path
import urllib.request,json,hashlib,io,struct,concurrent.futures
from PIL import Image
from lupa.lua51 import LuaRuntime
root=Path(__file__).resolve().parents[1]
cache=root/'.cache/map-art';cache.mkdir(parents=True,exist_ok=True)
def get_json(url):
 request=urllib.request.Request(url,headers={'User-Agent':'Quintessence-dungeon-maps'})
 return json.load(urllib.request.urlopen(request,timeout=30))
saved=root/'Media/Maps/sources.json'
previous=json.loads(saved.read_text()) if saved.exists() else None
revision=previous['revision'] if previous else get_json('https://api.github.com/repos/Gethe/wow-ui-textures/branches/classic')['commit']['sha']
folders=get_json('https://api.github.com/repos/Gethe/wow-ui-textures/contents/WorldMap?ref='+revision)
canonical={f['name'].lower():f['name'] for f in folders if f['type']=='dir'}
lua=LuaRuntime(unpack_returned_tuples=True);lua.execute('Q={}');lua.execute('assert(loadstring(...))("quinte-group",Q)',(root/'DungeonMapData.lua').read_text())
requested=set()
for d in lua.globals().Q.DUNGEON_MAPS.values():
 for page in d['floors'].values():requested.add((d['art'],int(page)))
entries={}
for art in sorted({a for a,p in requested if not previous or a+'_'+str(p) not in previous['maps']}):
 folder=canonical.get(art.lower())
 if not folder:print('Dossier absent :',art,flush=True);continue
 listing=get_json('https://api.github.com/repos/Gethe/wow-ui-textures/contents/WorldMap/'+folder+'?ref='+revision)
 names={f['name'].lower():f['name'] for f in listing}
 for a,page in sorted(requested):
  if a!=art:continue
  tiles=[]
  for i in range(1,13):
   name=names.get((folder+str(page)+'_'+str(i)+'.PNG').lower())
   if not name and page==1:name=names.get((folder+str(i)+'.PNG').lower())
   if not name:break
   tiles.append((cache/(folder+'_'+str(page)+'_'+str(i)+'.png'),'https://raw.githubusercontent.com/Gethe/wow-ui-textures/'+revision+'/WorldMap/'+folder+'/'+name))
  if len(tiles)==12:entries[(art,page)]=tiles
  else:print('Étage absent :',art,page,flush=True)
def fetch(item):
 target,url=item
 if not target.exists():
  request=urllib.request.Request(url,headers={'User-Agent':'Quintessence-dungeon-maps'})
  with urllib.request.urlopen(request,timeout=30) as r:data=r.read()
  with Image.open(io.BytesIO(data)) as img:assert img.size==(256,256),url
  target.write_bytes(data)
 return target
all_tiles=[item for tiles in entries.values() for item in tiles]
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
 for i,_ in enumerate(pool.map(fetch,all_tiles),1):
  if i%100==0:print('Tuiles :',i,'/',len(all_tiles),flush=True)
out=root/'Media/Maps';out.mkdir(parents=True,exist_ok=True)
manifest=previous or {'copyright':'World of Warcraft map art: Blizzard Entertainment','source':'https://github.com/Gethe/wow-ui-textures','revision':revision,'maps':{}}
lines=['local _, Q = ...','-- Cartes Blizzard assemblées par scripts/make_dungeon_map_art.py ; voir Media/Maps/sources.json.','Q.DUNGEON_MAP_ASSETS = {']
for (art,page),tiles in sorted(entries.items()):
 image=Image.new('RGB',(1024,1024),(0,0,0))
 for i,(path,url) in enumerate(tiles):
  with Image.open(path) as tile:image.paste(tile.convert('RGB'),((i%4)*256,(i//4)*256))
 dds=io.BytesIO();image.save(dds,format='DDS',pixel_format='DXT1');payload=dds.getvalue()[128:]
 header=struct.pack('<4sI4BII16I16I',b'BLP2',1,2,0,0,0,1024,1024,*([148]+[0]*15),*([len(payload)]+[0]*15))
 name=art+'_'+str(page)+'.blp';target=out/name;target.write_bytes(header+payload)
 with Image.open(target) as verify:verify.load();assert verify.size==(1024,1024)
 key=art+'_'+str(page)
 lines.append('    ['+json.dumps(key)+'] = '+json.dumps('Media\\Maps\\'+name)+',')
 manifest['maps'][key]={'file':name,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'tiles':[{'url':url,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()} for path,url in tiles]}
lines=lines[:3]+['    ['+json.dumps(key)+'] = '+json.dumps('Media\\Maps\\'+info['file'])+',' for key,info in sorted(manifest['maps'].items())]
lines.append('}');(root/'DungeonMapAssets.lua').write_text('\n'.join(lines)+'\n')
(out/'sources.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(len(entries),'cartes et étages assemblés ;',len(all_tiles),'tuiles Blizzard.',flush=True)
