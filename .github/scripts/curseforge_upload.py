#!/usr/bin/env python3
"""Envoie sur CurseForge les addons de ce dépôt (écrits par Quintessence/scripts/build_suite.py).

Usage : curseforge_upload.py <dossier de pack.json>
Environnement :
  CF_API_KEY        jeton d'API de l'auteur (secret GitHub, jamais affiché)
  CF_PROJECT_ID     numéro du projet CurseForge (variable ou secret)
  CF_GAME_VERSIONS  facultatif : noms exacts des versions du jeu, séparés par des virgules.
                    Sans lui, on prend la version la plus récente dont le nom ou le type contient « forever ».
  CF_API_BASE       facultatif, pour les tests (https://wow.curseforge.com par défaut)
Sans jeton ou sans projet, l'envoi échoue en disant lequel manque (avant il restait vert sans rien envoyer).
"""
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request
import uuid
import zipfile
from pathlib import Path

MEMBER_ADDONS = {'Quintessence', 'quinte-craft', 'quinte-caract', 'quinte-bis', 'quinte-group', 'quinte-map'}
OFFICER_FILES = {'Announce.lua', 'Officers.lua', 'GuildLog.lua', 'PvPLog.lua'}

USER_AGENT = 'quintessence-pack-upload'


def request(base, token, path, data=None, content_type=None):
    headers = {'X-Api-Token': token, 'User-Agent': USER_AGENT, 'Accept': 'application/json'}
    if content_type:
        headers['Content-Type'] = content_type
    req = urllib.request.Request(base + path, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        body = 'Consulte le tableau de bord CurseForge (contenu masqué pour protéger le jeton).'
        print(f'::error title=CurseForge::Réponse {error.code} sur {path} : ' + body.replace('\n', ' '))
        raise SystemExit(1)


def build_zip(folder, addons):
    """ZIP des seuls dossiers d'addons listés dans pack.json."""
    if {name for name, _ in addons} != MEMBER_ADDONS or len(addons) != len(MEMBER_ADDONS):
        raise SystemExit('CurseForge accepte uniquement les six addons membres.')
    out = io.BytesIO()
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as target:
        for name, _ in addons:
            base = folder / name
            if not (base / f'{name}.toc').is_file():
                raise SystemExit(f'.toc manquant : {name}')
            for file in sorted(base.rglob('*')):
                if file.is_file():
                    if file.is_symlink() or file.name in OFFICER_FILES:
                        raise SystemExit('Fichier officier ou lien interdit dans CurseForge : ' + file.name)
                    target.write(file, file.relative_to(folder).as_posix())
    return out.getvalue()


def game_versions(base, token):
    versions = request(base, token, '/api/game/versions')
    wanted = [n.strip() for n in os.environ.get('CF_GAME_VERSIONS', '').split(',') if n.strip()]
    if wanted:
        ids = [v['id'] for v in versions if v.get('name') in wanted]
        if len(ids) != len(wanted):
            raise SystemExit(f'Versions introuvables parmi {wanted} : ' + ', '.join(sorted(str(v.get('name')) for v in versions))[-1500:])
        return ids
    types = request(base, token, '/api/game/version-types')
    forever_types = {t['id'] for t in types if 'forever' in str(t.get('name', '')).lower() or 'forever' in str(t.get('slug', '')).lower()}
    found = [v for v in versions if v.get('gameVersionTypeID') in forever_types or 'forever' in str(v.get('name', '')).lower()]
    if not found:
        names = ', '.join(f"{t.get('name')} ({t.get('id')})" for t in types)
        raise SystemExit('Aucune version « Forever » trouvée : donner le nom exact dans la variable CF_GAME_VERSIONS.\n'
                         f'Types : {names}\nDernières versions : ' + ', '.join(str(v.get('name')) for v in versions[-40:]))
    best = max(found, key=lambda v: v['id'])
    print(f"::notice title=CurseForge::Version du jeu choisie : {best.get('name')} ({best['id']})")
    return [best['id']]


def multipart(metadata, name, content):
    boundary = uuid.uuid4().hex
    parts = [
        f'--{boundary}\r\nContent-Disposition: form-data; name="metadata"\r\nContent-Type: application/json\r\n\r\n'.encode(),
        json.dumps(metadata, ensure_ascii=False).encode('utf-8'),
        f'\r\n--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{name}"\r\nContent-Type: application/zip\r\n\r\n'.encode(),
        content,
        f'\r\n--{boundary}--\r\n'.encode(),
    ]
    return b''.join(parts), f'multipart/form-data; boundary={boundary}'


def main():
    folder = Path(sys.argv[1])
    token = os.environ.get('CF_API_KEY', '').strip()
    project = os.environ.get('CF_PROJECT_ID', '').strip()
    missing = [name for name, value in (('secret CF_API_KEY', token), ('variable CF_PROJECT_ID', project)) if not value]
    if missing:
        # En échec (croix rouge et courriel de GitHub) : avant, l'envoi restait vert sans rien envoyer.
        print('::error title=CurseForge::Rien envoyé, absent de ce dépôt : ' + ' et '.join(missing)
              + '. Settings → Secrets and variables → Actions, onglets Secrets et Variables du dépôt halfire/Curseforge '
              "(pas un secret d'environnement, ni un autre dépôt).")
        raise SystemExit(1)
    if not project.isdigit():
        raise SystemExit('CF_PROJECT_ID doit être un numéro.')
    base = os.environ.get('CF_API_BASE', 'https://wow.curseforge.com').rstrip('/')
    pack = json.loads((folder / 'pack.json').read_text(encoding='utf-8'))
    if pack.get('channel') != 'release' or not re.fullmatch(r'[a-f0-9]{64}', str(pack.get('validated_beta_sha256', ''))):
        raise SystemExit('Seule une Release promue depuis une bêta validée peut être envoyée.')
    content = build_zip(folder, pack['addons'])
    changelog = '\n'.join(f'- {name} {version}' for name, version in pack['addons'])
    metadata = {
        'changelog': changelog,
        'changelogType': 'markdown',
        'displayName': f"Quintessence {pack['version']}",
        'gameVersions': game_versions(base, token),
        'releaseType': 'release',
    }
    body, content_type = multipart(metadata, f"Quintessence-{pack['version']}.zip", content)
    result = request(base, token, f'/api/projects/{project}/upload-file', body, content_type)
    print(f"::notice title=CurseForge::Version {pack['version']} envoyée, fichier n° {result.get('id')}, jeu {metadata['gameVersions']}.")


if __name__ == '__main__':
    main()
