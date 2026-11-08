"""Reconstruit le moteur embarqué depuis le ZIP officiel vérifié (QUINTE_NAV_ENGINE_ZIP pour hors réseau)."""
from pathlib import Path
import shutil,json,hashlib
root=Path(__file__).resolve().parents[1]
from navigation_engine import engine_archive
import tempfile,zipfile
_,_,archive=engine_archive(root)
temporary=tempfile.TemporaryDirectory()
with zipfile.ZipFile(archive) as z: z.extractall(temporary.name)
up=Path(temporary.name)/'ShortestPathForever';out=root/'Navigation/Engine'
if out.exists():shutil.rmtree(out)
shutil.copytree(up,out,dirs_exist_ok=True)
exclude={'UI/Settings.lua','UI/WhatsNew.lua','Core/Way.lua','Core/TomTom.lua','Core/RestedXP.lua','UI/FamilyHints.lua','Transport/Sync.lua','Core/PeerStats.lua','Core/LeaderboardsData.lua','UI/Leaderboards.lua','Core/Progress.lua','UI/Nearby.lua'}
entries=[]
for line in (up/'ShortestPathForever.toc').read_text().splitlines():
 line=line.strip().replace('\\','/')
 if line.endswith(('.lua','.xml')) and line not in exclude:entries.append(line)
for p in out.rglob('*'):
 if not p.is_file() or p.suffix not in ('.lua','.xml'):continue
 rel=p.relative_to(out).as_posix()
 if rel in exclude or rel=='Bindings.xml':p.unlink();continue
 text=p.read_text().replace('ShortestPathForever','QuintessenceTravel').replace('SHORTESTPATHFOREVER','QUINTESSENCETRAVEL')
 text=text.replace('Interface\\\\AddOns\\\\QuintessenceTravel\\\\','Interface\\\\AddOns\\\\Quintessence\\\\Navigation\\\\Engine\\\\')
 if rel=='Core/Core.lua':
  text=text.replace('QuintessenceTravelDB = QuintessenceTravelDB or {}\n\tns.db = QuintessenceTravelDB','QuintessenceDB = QuintessenceDB or {}\n\tif type(QuintessenceDB.travelEngine) ~= \"table\" then QuintessenceDB.travelEngine = {} end\n\tns.db = QuintessenceDB.travelEngine\n\tif ns.ConfigureDefaults then ns.ConfigureDefaults(DEFAULTS) end')
  text=text.replace('print(NORMAL_FONT_COLOR:WrapTextInColorCode("Shortest Path Forever:") .. " " .. message)','QC.Print(message)')
 if rel=='Transport/Taxi.lua':text=text.replace('QuintessenceTravelCharDB = QuintessenceTravelCharDB or {}\n\tns.charDB = QuintessenceTravelCharDB','ns.charDB = ns.CharacterDB()')
 if rel=='Core/API.lua':text=text.replace('QuintessenceTravel.API = API','QuintessenceTravel.API = API\nns.API = API')
 if rel=='Core/SafeCall.lua':text=text.replace('local rawMessage = tostring(message)','local rawMessage = tostring(message)\n\tif QC.Error then QC.Error("voyages : " .. tostring(label), rawMessage) end')
 if rel=='Journey/JourneyInput.lua':text=text[:text.index('ns.Init(function()')]+'-- Quintessence : les gestes carte/minicarte et menus autonomes sont remplacés par le service commun.\n'
 if rel=='Journey/JourneyGuide.lua':text+='\nfunction ns.OwnsWaypoint(point)\n return guide ~= nil and SameWaypoint(point, guide.expectedWaypoint) == true\nend\n'
 if rel=='UI/Route.lua':
  text=text.replace('if not (map:GetMapID() and map:IsVisible() and goal','if not (ns.db.quinteWorldMap ~= false and map:GetMapID() and map:IsVisible() and goal')
  text=text.replace('if not (mapID and map:IsVisible() and ns.db.journey and goal)','if not (ns.db.quinteWorldMap ~= false and mapID and map:IsVisible() and ns.db.journey and goal)')
  text=text.replace('if not (goal and (ns.db.journey or goal.corpse)) then','if not (ns.db.quinteMinimap ~= false and goal and (ns.db.journey or goal.corpse)) then')
  text=text.replace('if destination then\n\t\t\tminimap:Show()','if destination and ns.db.quinteMinimap ~= false then\n\t\t\tminimap:Show()')
  text+='\n-- Quintessence : changements de visibilité sans relancer le trajet.\nfunction ns.RefreshQuinteRoute()\n geometryRevision = geometryRevision + 1\n if provider then provider:RefreshAllData() end\n if minimap then\n  minimap.revision = nil\n  if goal and ns.db.journey and ns.db.quinteMinimap ~= false then minimap:Show(); DrawMinimap(minimap); WakeMinimap(minimap)\n  else minimap.Goal:Hide(); minimap:Hide(); ns.SetAreaBlob(false) end\n end\nend\n'
 if p.suffix=='.lua':text='-- Adaptation embarquée Quintessence ; origine GPL-3.0-or-later dans LICENSE et THIRD_PARTY.md.\nlocal _, QC = ...\nlocal function Embedded(...)\n'+text+'\nend\nEmbedded(select(1, ...), QC.TravelEngine)\n'
 p.write_text(text)
(out/'ShortestPathForever.toc').unlink()
(root/'Navigation/Engine.xml').write_text('<Ui xmlns="http://www.blizzard.com/wow/ui/">\n'+''.join(' <'+('Include' if e.endswith('.xml') else 'Script')+' file="Engine/'+e+'"/>\n' for e in entries)+'</Ui>\n')
shutil.copy2(up/'LICENSE',root/'COPYING')
(root/'Navigation/Engine/UPSTREAM.json').write_text(json.dumps({'upstream':json.loads((root/'Navigation/engine.json').read_text()),'adaptations':['Isolated Quintessence engine namespace and frame names','Embedded media paths and XML load order','Settings and character storage in QuintessenceDB','Settings replaced by Quintessence controls; no standalone slash commands or integrations','Independent world map and minimap route visibility'],'excluded_entrypoints':sorted(exclude),'original_files_sha256':{str(p.relative_to(up)):hashlib.sha256(p.read_bytes()).hexdigest() for p in up.rglob('*') if p.is_file()}},indent=2)+'\n')
