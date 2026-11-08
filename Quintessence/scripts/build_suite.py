"""Deux packs prêts à dézipper dans Interface/AddOns : le pack complet (conteneur et tous les modules, réservé aux officiers)
et le pack du site, pour les membres (MEMBER_ADDONS).

Les projets doivent être des dossiers frères (Quintessence/, quinte-craft/, …). Chaque addon est d'abord construit avec
son propre scripts/build.py, à la version lue dans son code, puis les ZIP sont fusionnés.
Usage : python3 scripts/build_suite.py
Copiés dans le site, avec chacun leur pack.json, et en ligne au prochain déploiement : pack des membres dans
../site/site/telechargements/, pack complet dans ../site/site/storage/pack-complet/ (servi aux officiers connectés).
"""
import re,subprocess,sys,zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
workspace=root.parent
# (dossier, fichier qui porte la version)
ADDONS=[
    ('Quintessence','Core.lua'),
    ('quinte-craft','Core.lua'),
    ('quinte-caract','Core.lua'),
    ('quinte-event','Core.lua'),
    ('quinte-raid','Core.lua'),
    ('quinte-layer','Core.lua'),
    ('quinte-map','Core.lua'),
    ('quinte-group','Core.lua'),
    ('quinte-bis','Core.lua'),
    ('quinte-ride','Protocol.lua'),
    ('quinte-recrut','Core.lua')
]
# Pack du site et dépôt CurseForge : Craft, Fiches, BiS, Donjons & Quêtes, SOS et Camp
MEMBER_ADDONS=['Quintessence','quinte-craft','quinte-caract','quinte-bis','quinte-group','quinte-map']
README="""Quintessence - {title}
===========================

Contenu : {contents}

Installation
1. Fermer le jeu.
2. Dézipper ce fichier dans le dossier Interface/AddOns de World of Warcraft
   (les dossiers doivent garder exactement ces noms, sans "-main" à la fin).
3. Lancer le jeu, puis /quinte (ou le bouton dans le menu des addons).

Quintessence est obligatoire, les modules sont facultatifs : supprime le dossier d'un module pour t'en passer.
Le moteur de voyage est intégré dans Quintessence. Réglages > Voyages permet de choisir son affichage.
Si une ancienne version du pack a installé ShortestPathForever, retirer son ancien dossier après avoir fermé le jeu.
Crédits, sources et licences : Quintessence/THIRD_PARTY.md et Quintessence/COPYING.
La page Aide de la fenêtre explique chaque onglet.
"""

def version_of(folder,source):
    text=(workspace/folder/source).read_text(encoding='utf-8')
    match=re.search(r"\.version\b[^\n]*?'(\d+\.\d+\.\d+)'",text)
    if not match:raise SystemExit(f'Version introuvable dans {folder}/{source}')
    return match.group(1)

built=[]
for folder,source in ADDONS:
    if not (workspace/folder).is_dir():raise SystemExit(f'Projet manquant : {workspace/folder}')
    version=version_of(folder,source)
    output=subprocess.run([sys.executable,'scripts/build.py','v'+version],cwd=workspace/folder,check=True,capture_output=True,text=True).stdout.strip().splitlines()[-1]
    built.append((folder,version,Path(output)))


core_version=built[0][1]
dist=root/'dist';dist.mkdir(exist_ok=True)
EDITION_OLD,EDITION_NEW=b'## Version:',b'## X-Quinte-Edition: site\n## Version:'
def write_pack(target,title,rows,edition=False):
    seen=set()
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as out:
        for folder,version,path in rows:
            with zipfile.ZipFile(path) as z:
                for info in z.infolist():
                    if info.is_dir():continue
                    if info.filename in seen:raise SystemExit(f'Fichier en double : {info.filename}')
                    if not info.filename.startswith(folder+'/'):raise SystemExit(f'Chemin inattendu dans {path.name} : {info.filename}')
                    seen.add(info.filename)
                    content=z.read(info)
                    if edition and info.filename=='Quintessence/Quintessence.toc':
                        content=content.replace(EDITION_OLD,EDITION_NEW,1)
                        if b'X-Quinte-Edition' not in content:raise SystemExit('Edition absente du .toc')
                    out.writestr(info.filename,content)
        names=', '.join(f'{folder} {version}' for folder,version,_ in rows)
        out.writestr('LISEZMOI.txt',README.format(title=title,contents=names))
        assert out.testzip() is None
    return names
target=dist/f'Quintessence-pack-complet-v{core_version}.zip'
contents=write_pack(target,'pack complet',built)
members=[row for row in built if row[0] in MEMBER_ADDONS]
member_target=dist/f'Quintessence-pack-v{core_version}.zip'
write_pack(member_target,'pack de la guilde',members,edition=True)
# Packs servis par le site (dépôt frère site/) : page Addons, mis en ligne par « quintessence-maj » sans rien téléverser.
# Seul le dernier pack de chaque sorte est gardé ; pack.json décrit son contenu pour la page.
site_dir=workspace/'site'/'site'
if site_dir.is_dir():
    import datetime,json
    def publish(folder,zip_path,pattern,rows):
        folder.mkdir(parents=True,exist_ok=True)
        for old in folder.glob(pattern):
            if old.name!=zip_path.name:old.unlink()
        (folder/zip_path.name).write_bytes(zip_path.read_bytes())
        (folder/'pack.json').write_text(json.dumps({'file':zip_path.name,'version':core_version,'size':zip_path.stat().st_size,
            'built':datetime.date.today().isoformat(),'addons':[[f,v] for f,v,_ in rows]},ensure_ascii=False,indent=1)+'\n',encoding='utf-8')
        print(folder/zip_path.name)
    downloads=site_dir/'telechargements'
    for old in downloads.glob('Quintessence-pack-complet-v*.zip'):old.unlink()
    publish(downloads,member_target,'Quintessence-pack-v*.zip',members)
    publish(site_dir/'storage'/'pack-complet',target,'Quintessence-pack-complet-v*.zip',built)
# Dépôt CurseForge (dossier frère Curseforge/, poussé à la main) : seulement les addons montrés aux membres, sans les
# README ni CHANGELOG, qui parlent des autres modules. Le .toc du conteneur porte l'édition : les onglets en plus sont cachés.
CURSEFORGE=MEMBER_ADDONS
cf_dir=workspace/'Curseforge'
if cf_dir.is_dir():
    import json,shutil
    versions={folder:(version,path) for folder,version,path in built}
    # Migration : le moteur fait désormais partie du conteneur.
    shutil.rmtree(cf_dir/'ShortestPathForever',ignore_errors=True)
    for folder in CURSEFORGE:
        shutil.rmtree(cf_dir/folder,ignore_errors=True)
        with zipfile.ZipFile(versions[folder][1]) as z:
            for info in z.infolist():
                name=info.filename
                if info.is_dir() or name.endswith(('/README.md','/CHANGELOG.md')):continue
                content=z.read(info)
                if name=='Quintessence/Quintessence.toc':
                    content=content.replace(b'## Version:',b'## X-Quinte-Edition: curseforge\n## Version:',1)
                    if b'X-Quinte-Edition' not in content:raise SystemExit('Edition absente du .toc')
                out_file=cf_dir/name;out_file.parent.mkdir(parents=True,exist_ok=True);out_file.write_bytes(content)
    (cf_dir/'pack.json').write_text(json.dumps({'version':core_version,'addons':[[f,versions[f][0]] for f in CURSEFORGE]},ensure_ascii=False,indent=1)+'\n',encoding='utf-8')
    print(cf_dir)
print(target)
print(contents)
