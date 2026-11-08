#!/usr/bin/env python3
"""Vérifie (et régénère) la documentation des addons pour les agents IA.

    python3 Quintessence/scripts/check_docs.py          # vérifie : code de sortie 1 s'il y a un problème
    python3 Quintessence/scripts/check_docs.py --write  # réécrit la section automatique de chaque AGENTS.md

Pour chaque addon (dossier frère de Quintessence) :
  - section automatique de AGENTS.md entre <!-- auto:debut --> et <!-- auto:fin --> : version lue dans le code,
    SavedVariables, fichiers dans l'ordre du .toc avec leurs fonctions publiques, API C_* appelées, événements écoutés,
    commandes, canaux de synchro. Elle est toujours tirée du code : ne pas l'éditer à la main.
  - vérification du reste du texte : tout fichier `X.lua` et toute fonction `Q.X` / `UI.X` / `A.X` / `Core.X` /
    `Quintessence.X` cités doivent exister dans le code (sinon un agent chercherait du code qui n'existe plus) ;
    une mention « version `x.y.z` » doit être la version du code.
À lancer avant chaque publication (étape de « Publier une version » dans ../AGENTS.md).
"""
import re
import sys
from pathlib import Path

SUITE = Path(__file__).resolve().parents[2]
MODULES = ['Quintessence', 'quinte-craft', 'quinte-caract', 'quinte-event', 'quinte-raid', 'quinte-layer',
           'quinte-map', 'quinte-group', 'quinte-bis', 'quinte-ride', 'quinte-recrut']
BEGIN, END = '<!-- auto:debut -->', '<!-- auto:fin -->'
NOT_EVENTS = ('INVTYPE_', 'ANCHOR_', 'RAID_CLASS', 'SOUNDKIT', 'ITEM_QUALITY', 'LE_', 'ERR_', 'WOW_PROJECT')
LAYOUT = {'TOPLEFT', 'TOPRIGHT', 'BOTTOMLEFT', 'BOTTOMRIGHT', 'CENTER', 'ARTWORK', 'BACKGROUND', 'OVERLAY',
          'HIGHLIGHT', 'OUTLINE', 'BORDER', 'TOOLTIP', 'DIALOG', 'MEDIUM', 'VERTICAL', 'HORIZONTAL', 'CHATLINK',
          'HELPFUL', 'HARMFUL', 'WHISPER', 'GUILD', 'RAID_WARNING', 'PARTY', 'INSTANCE_CHAT', 'MONOCHROME'}


def lua_files(folder):
    toc = next(folder.glob('*.toc'))
    files = [line.strip() for line in toc.read_text(encoding='utf-8').splitlines() if line.strip().endswith('.lua')]
    return toc, files


def version_of(folder):
    for name, pattern in (('Core.lua', r"^(?:Q|Core)\.name,\s*(?:Q|Core)\.version[^\n]*?'(\d+\.\d+\.\d+)'"),
                          ('Protocol.lua', r"A\.version\s*,\s*A\.protocol\s*=\s*'(\d+\.\d+\.\d+)'")):
        path = folder / name
        if path.exists():
            match = re.search(pattern, path.read_text(encoding='utf-8'), re.M)
            if match:
                return match.group(1)
    return '?'


def facts(module):
    folder = SUITE / module
    toc, files = lua_files(folder)
    sources = {}
    for f in files:
        path = folder / f
        if path.exists():
            sources[f] = path.read_text(encoding='utf-8', errors='ignore')
    own = {f: c for f, c in sources.items() if not f.startswith('Libs/')}
    code = '\n'.join(own.values())
    toc_text = toc.read_text(encoding='utf-8')
    saved = re.search(r'^## SavedVariables:\s*(.+)$', toc_text, re.M)
    functions = {}
    for f, c in own.items():
        functions[f] = re.findall(r'^\s*function\s+((?:Q|UI|A|V|Core|Q\.UI)[.:][A-Za-z_][\w]*)', c, re.M)
    apis = sorted(set(re.findall(r'\b(C_[A-Za-z]+\.[A-Za-z]+)\b', code)))
    events = set()
    for chunk in re.findall(r"(?:RegisterEvent|RegisterUnitEvent)\s*,?\s*[^)]*?'([A-Z][A-Z_]+)'", code):
        events.add(chunk)
    for block in re.findall(r"\{\s*('[A-Z][A-Z_]+'(?:\s*,\s*'[A-Z][A-Z_]+')+)\s*,?\s*\}", code):
        events.update(re.findall(r"'([A-Z][A-Z_]+)'", block))
    events = sorted(e for e in events if '_' in e and e not in LAYOUT and not e.startswith(NOT_EVENTS))
    slash = sorted({cmd for line in code.splitlines() if 'SLASH_' in line for cmd in re.findall(r"'(/[a-z][\w-]*)'", line)})
    channels = sorted(set(re.findall(r"RegisterChannel\('(\w+)'", code)))
    syncs = sorted(set(re.findall(r"RegisterSync\('(\w+)'", code)))
    return {'folder': folder, 'files': files, 'own': own, 'code': code, 'version': version_of(folder),
            'saved': saved.group(1).strip() if saved else '—', 'functions': functions, 'apis': apis,
            'events': events, 'slash': slash, 'channels': channels, 'syncs': syncs}


def auto_block(module, f):
    lines = [BEGIN,
             '<!-- Section générée par Quintessence/scripts/check_docs.py --write : ne pas éditer à la main. -->',
             '',
             f'- **Version du code** : `{f["version"]}` · **SavedVariables** : `{f["saved"]}`'
             + (f' · **Synchro** : `{", ".join(f["syncs"])}`' if f['syncs'] else '')
             + (f' · **Canaux temps réel** : `{", ".join(f["channels"])}`' if f['channels'] else '')
             + (f' · **Commandes** : `{"`, `".join(f["slash"])}`' if f['slash'] else ''),
             '',
             '| Fichier (ordre du .toc) | Lignes | Fonctions publiques |',
             '|---|---|---|']
    for name in f['files']:
        if name.startswith('Libs/'):
            continue
        source = f['own'].get(name, '')
        names = ', '.join(f'`{fn}`' for fn in f['functions'].get(name, [])) or '— (fonctions locales ou données)'
        lines.append(f'| `{name}` | {len(source.splitlines())} | {names} |')
    lines += ['',
              '**API `C_*` appelées** : ' + (', '.join(f'`{a}`' for a in f['apis']) or 'aucune'),
              '',
              '**Événements écoutés** : ' + (', '.join(f'`{e}`' for e in f['events']) or 'aucun'),
              END]
    return '\n'.join(lines)


def check_text(module, f, text):
    problems = []
    outside = re.sub(re.escape(BEGIN) + r'.*?' + re.escape(END), '', text, flags=re.S)
    known_files = {Path(n).name for n in f['files']} | {p.name for p in f['folder'].rglob('*.lua')}
    container = facts('Quintessence')['code'] if module != 'Quintessence' else f['code']
    saved_files = {m + '.lua' for m in MODULES}  # fichiers de SavedVariables (WTF/…/SavedVariables/quinte-x.lua)
    for name in sorted(set(re.findall(r'`([\w\-]+\.lua)`', outside))):
        if name not in known_files and name not in saved_files:
            problems.append(f'fichier cité absent : {name}')
    for ref in sorted(set(re.findall(r'`((?:Q|UI|A|V|Core|Quintessence)[.:][A-Za-z_]\w*)', outside))):
        prefix, name = re.split(r'[.:]', ref, maxsplit=1)
        if name == 'lua':  # nom de fichier (`UI.lua`), pas une fonction
            continue
        # (`Quintessence.X` : fonction du conteneur, ou pont posé par le module lui-même, ex. Quintessence.ShowBossLoot)
        haystack = (container + f['code']) if prefix in ('Core', 'Quintessence') else f['code']
        if not re.search(r'\b' + re.escape(name) + r'\b', haystack):
            problems.append(f'fonction citée absente du code : {ref}')
    for cited in set(re.findall(r'version `(\d+\.\d+\.\d+)`', outside)):
        if cited != f['version']:
            problems.append(f'version citée {cited} ≠ code {f["version"]}')
    return problems


def main():
    write = '--write' in sys.argv
    failed = False
    for module in MODULES:
        f = facts(module)
        path = f['folder'] / 'AGENTS.md'
        text = path.read_text(encoding='utf-8') if path.exists() else ''
        block = auto_block(module, f)
        if BEGIN in text and END in text:
            updated = re.sub(re.escape(BEGIN) + r'.*?' + re.escape(END), lambda _: block, text, flags=re.S)
        else:
            updated = text.rstrip() + '\n\n## Inventaire du code (automatique)\n\n' + block + '\n'
        problems = check_text(module, f, updated)
        stale = updated != text
        if write and stale:
            path.write_text(updated, encoding='utf-8')
            stale = False
        if stale:
            problems.insert(0, 'section automatique périmée : lancer check_docs.py --write')
        status = 'OK' if not problems else '; '.join(problems)
        print(f'{module} {f["version"]}: {status}')
        failed = failed or bool(problems)
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
