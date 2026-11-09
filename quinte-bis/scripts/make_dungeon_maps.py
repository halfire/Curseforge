"""Importe uniquement les cartes Classic et repères MIT de SimpleDungeonMap ; aucun fichier Naowh.
Usage : python3 scripts/make_dungeon_maps.py /chemin/SimpleDungeonMap
Nécessite lupa ; les images restent celles du client, sans redistribution.
"""
from pathlib import Path
import json,sys,subprocess
from lupa.lua51 import LuaRuntime
root=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1]);lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute((source/'DungeonData.lua').read_text())
g=lua.globals()
revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=source,text=True).strip()
# Codes de la suite et famille/ailes du catalogue Classic de la source.
codes={'RFC':(389,None),'WC':(43,None),'DM':(36,None),'SFK':(33,None),'STOCKS':(34,None),'BFD':(48,None),
 'GNOMER':(90,None),'RFK':(47,None),'RFD':(129,None),'ULDA':(70,None),'ZF':(209,None),'MARA':(349,None),
 'ST':(109,None),'BRD':(230,None),'LBRS':(229,'LowerBlackrockSpire'),
 'SM_GY':(189,'ScarletMonasteryGraveyard'),'SM_LIB':(189,'ScarletMonasteryLibrary'),
 'SM_ARM':(189,'ScarletMonasteryArmory'),'SM_CATH':(189,'ScarletMonasteryCathedral'),
 'DME':(429,'DireMaulEast'),'DMW':(429,'DireMaulWest'),'DMN':(429,'DireMaulNorth'),
 'STRAT':(329,None),'SCHOLO':(289,None)}
def quote(s):return json.dumps(s,ensure_ascii=False)
lines=['local _, Q = ...','-- Généré par scripts/make_dungeon_maps.py ; ne pas modifier à la main.',
 f'-- Source MIT : https://github.com/Babilounet/SimpleDungeonMap/tree/{revision}',
 '-- Textures du client Blizzard ; positions Classic indicatives, non confirmées pour Forever.',
 '-- Licence conservée dans ThirdParty/SimpleDungeonMap-LICENSE.txt.','Q.DUNGEON_MAPS = {']
for code,(mapid,wing) in codes.items():
 art=g.SDM_DungeonByMapID[mapid];src=g.SDM_DungeonBosses[mapid]
 bosses=[]
 if src:
  for row in src['bosses'].values():
   if wing is None or row[5]==wing:
    bosses.append([row[1],row[2]/100,row[3]/100,int(row[4])])
 floors=sorted({r[3] for r in bosses}) if wing else list((g.SDM_DungeonFloors[art] or lua.table_from([1])).values())
 if not floors:floors=[{'SM_GY':1,'SM_LIB':2,'SM_ARM':3,'SM_CATH':4}.get(code,1)]
 lines.append(f'    [{quote(code)}] = {{ art = {quote(art)}, floors = {{ '+', '.join(map(str,floors))+' }, bosses = {')
 for name,x,y,floor in bosses:
  if 0<=x<=1 and 0<=y<=1:lines.append(f'        {{ name = {quote(name)}, x = {x:.5f}, y = {y:.5f}, floor = {floor} }},')
 lines.append('    } },')
lines.append('}')
(root/'DungeonMapData.lua').write_text('\n'.join(lines)+'\n')
(root/'ThirdParty').mkdir(exist_ok=True)
(root/'ThirdParty/SimpleDungeonMap-LICENSE.txt').write_text((source/'LICENSE').read_text())
print(len(codes),'cartes Classic référencées ; positions indicatives, images lues dans le client.')
