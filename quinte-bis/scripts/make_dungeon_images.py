"""Illustrations officielles du codex de WoW ; aucune image de Naowh.
Pillow requis. Source Gethe/wow-ui-textures Classic, révision épinglée ; assets Blizzard.
Les instances Forever sans illustration identifiée gardent explicitement l'image générique du codex.
"""
from pathlib import Path
import json,urllib.request,hashlib,io
from PIL import Image
root=Path(__file__).resolve().parents[1]
revision='312a6e61bab69370c65ccc0a08f1075d62196294'
images=dict(RFC='RagefireChasm',WC='WailingCaverns',DM='Deadmines',SFK='ShadowFangKeep',STOCKS='TheStockade',BFD='BlackfathomDeeps',GNOMER='Gnomeregan',RFK='RazorfenKraul',RFD='RazorfenDowns',ULDA='Uldaman',ZF='ZulFarrak',MARA='Maraudon',ST='SunkenTemple',BRD='BlackrockDepths',LBRS='BlackrockSpire',UBRS='BlackrockSpire',STRAT='Stratholme',SCHOLO='Scholomance',ONY='Onyxia',MC='MoltenCore',BWL='BlackwingLair',ZG='ZulGurub',AQ20='RuinsofAhnQiraj',AQ40='TempleofAhnQiraj',NAXX='Naxxramas')
for code in ['SM_GY','SM_LIB','SM_ARM','SM_CATH']:images[code]='ScarletMonastery'
for code in ['DME','DMW','DMN']:images[code]='DireMaul'
out=root/'Media/Dungeons';out.mkdir(parents=True,exist_ok=True)
cache=root/'.cache/dungeon-images';cache.mkdir(parents=True,exist_ok=True)
sources={}
for name in sorted(set(images.values())|{'Default'}):
 url=f'https://raw.githubusercontent.com/Gethe/wow-ui-textures/{revision}/EncounterJournal/UI-EJ-DUNGEONBUTTON-{name}.PNG'
 file=cache/(name+'.png')
 if not file.exists():file.write_bytes(urllib.request.urlopen(url,timeout=40).read())
 raw=file.read_bytes();im=Image.open(io.BytesIO(raw)).convert('RGB');im.save(out/(name+'.tga'))
 sources[name]={'url':url,'source_sha256':hashlib.sha256(raw).hexdigest(),'sha256':hashlib.sha256((out/(name+'.tga')).read_bytes()).hexdigest()}
(out/'sources.json').write_text(json.dumps({'copyright':'Blizzard Entertainment','revision':revision,'images':sources,'instances':images},indent=2)+'\n')
lines=['local addonName, Q = ...','-- Illustrations Blizzard, sources et SHA-256 : Media/Dungeons/sources.json.','local images = {']
lines.extend(f' {code} = "{name}",' for code,name in images.items());lines+=['}','function Q.DungeonImage(code)',' return "Interface\\\\AddOns\\\\" .. addonName .. "\\\\Media\\\\Dungeons\\\\" .. (images[code] or "Default") .. ".tga"','end']
(root/'DungeonImages.lua').write_text('\n'.join(lines)+'\n')
print(len(sources),'illustrations enregistrées')
