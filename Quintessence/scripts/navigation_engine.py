"""Archive officielle du moteur : version et SHA-256 épinglés, fichiers tiers laissés intacts."""
import hashlib
import json
import os
from pathlib import Path
import urllib.request
import zipfile


def engine_archive(root):
    metadata=json.loads((root/'Navigation/engine.json').read_text(encoding='utf-8'))
    supplied=os.environ.get('QUINTE_NAV_ENGINE_ZIP')
    target=Path(supplied).expanduser() if supplied else root/'.cache'/metadata['url'].rsplit('/',1)[1]
    if not target.exists():
        if supplied:raise SystemExit('Archive du moteur introuvable : '+str(target))
        target.parent.mkdir(parents=True,exist_ok=True)
        request=urllib.request.Request(metadata['url'],headers={'User-Agent':'Quintessence-build'})
        with urllib.request.urlopen(request,timeout=120) as response:
            content=response.read(64*1024*1024+1)
        if len(content)>64*1024*1024:raise SystemExit('Archive du moteur trop volumineuse')
        if hashlib.sha256(content).hexdigest()!=metadata['sha256']:raise SystemExit('Empreinte du moteur incorrecte')
        target.write_bytes(content)
    if hashlib.sha256(target.read_bytes()).hexdigest()!=metadata['sha256']:
        raise SystemExit('Empreinte du moteur incorrecte : '+str(target))
    with zipfile.ZipFile(target) as archive:
        names=archive.namelist()
        prefix=metadata['name']+'/'
        for name in names:
            path=Path(name)
            if not name.startswith(prefix) or path.is_absolute() or '..' in path.parts:
                raise SystemExit('Chemin inattendu dans le moteur : '+name)
        for required in ['ShortestPathForever.toc','LICENSE','THIRD_PARTY.md','Core/API.lua','Routing/Path.lua','Nav/Nav.xml']:
            if prefix+required not in names:raise SystemExit('Moteur incomplet : '+required)
        if archive.testzip():raise SystemExit('Archive du moteur corrompue')
    return metadata['name'],metadata['version'],target
