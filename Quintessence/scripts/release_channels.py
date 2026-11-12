"""Promotion locale d'une bêta validée, sans relire ni reconstruire les sources des addons."""
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

MEMBERS = {'Quintessence', 'quinte-craft', 'quinte-caract', 'quinte-bis', 'quinte-group', 'quinte-map'}
OFFICER_FILES = {'Quintessence/Announce.lua', 'Quintessence/Officers.lua', 'Quintessence/GuildLog.lua', 'quinte-map/PvPLog.lua'}


def checked(folder):
    info = json.loads((folder / 'pack.json').read_text())
    name = info['file']
    if Path(name).name != name or info.get('channel') != 'beta':
        raise ValueError('Manifeste bêta invalide')
    archive = folder / name
    if archive.stat().st_size != info['size'] or hashlib.sha256(archive.read_bytes()).hexdigest() != info['sha256']:
        raise ValueError('La bêta a changé : taille ou empreinte incorrecte')
    with zipfile.ZipFile(archive) as z:
        if z.testzip(): raise ValueError('Archive bêta corrompue')
        for n in z.namelist():
            if n.startswith('/') or '\\' in n or '..' in Path(n).parts:
                raise ValueError('Chemin dangereux dans la bêta')
    return info, archive


def promote(workspace, validated_sha256=None):
    site = workspace / 'site' / 'site'
    destinations = [site / 'telechargements', site / 'storage' / 'pack-complet']
    packs = [checked(d / 'beta') for d in destinations]
    if packs[0][0]['version'] != packs[1][0]['version']:
        raise ValueError('Les deux bêtas doivent avoir la même version')
    info, archive = packs[0]
    if info.get('full_sha256') != packs[1][0]['sha256']:
        raise ValueError('Le pack complet ne correspond pas à la bêta membres validée')
    if validated_sha256 is not None and validated_sha256 != info['sha256']:
        raise ValueError('La bêta disponible diffère de celle validée')
    if {a[0] for a in info['addons']} != MEMBERS:
        raise ValueError('Composition membres inattendue')
    # Préparer CurseForge avant de remplacer les manifestes stables.
    cf = workspace / 'Curseforge'
    with zipfile.ZipFile(archive) as z:
        files = {}
        for name in z.namelist():
            if name == 'LISEZMOI.txt' or name.endswith('/') or name in OFFICER_FILES or name.endswith(('/README.md', '/CHANGELOG.md')): continue
            if name.split('/')[0] not in MEMBERS: raise ValueError('Addon non membre dans CurseForge')
            content = z.read(name)
            if name == 'quinte-caract/StatisticsPrivacy.lua':
                content = content.replace(b'function Q.StatisticsOfficer(name)\n', b'function Q.StatisticsOfficer(name)\n    if not name then return false end -- Edition membres : envoi seulement.\n', 1)
            if name.endswith('.toc'):
                lines = content.decode().splitlines()
                parent = name.split('/')[0]
                lines = [line for line in lines if parent + '/' + line.strip() not in OFFICER_FILES]
                if name == 'Quintessence/Quintessence.toc': lines.insert(lines.index('Versions.lua') + 1 if 'Versions.lua' in lines else len(lines), 'Members.lua')
                content = ('\n'.join(lines) + '\n').encode().replace(b'X-Quinte-Edition: site', b'X-Quinte-Edition: curseforge')
            files[name] = content
        files['Quintessence/Members.lua'] = (Path(__file__).parent / 'member_runtime.lua').read_bytes()
        for addon in MEMBERS: shutil.rmtree(cf / addon, ignore_errors=True)
        for name, content in files.items():
            dest = cf / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(content)
    (cf / 'pack.json').write_text(json.dumps({'version': info['version'], 'channel': 'release', 'addons': info['addons'], 'validated_beta_sha256': info['sha256']}, ensure_ascii=False, indent=1) + '\n')
    for dest, (manifest, source) in zip(destinations, packs):
        dest.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, dest / source.name)
        stable = dict(manifest, channel='release')
        (dest / 'pack.json').write_text(json.dumps(stable, ensure_ascii=False, indent=1) + '\n')
        for old in dest.glob('Quintessence-pack-*.zip'):
            if old.name != source.name: old.unlink()
    print('Release préparée depuis la bêta validée ; aucun push ni envoi réseau effectué.')
