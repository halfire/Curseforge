"""Build an installable ZIP, without network access or external packaging tools."""
import os,re,sys,zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
version=sys.argv[1] if len(sys.argv)>1 else os.environ.get('CI_COMMIT_TAG','v0.1.0')
if not re.fullmatch(r'v\d+\.\d+\.\d+',version):raise SystemExit('Expected version vX.Y.Z')
dist=root/'dist';dist.mkdir(exist_ok=True)
output=dist/f'Quintessence-{version}.zip'
files=[*root.glob('*.lua'),root/'Quintessence.toc',root/'README.md',root/'CHANGELOG.md',root/'LICENSE',root/'COPYING',root/'THIRD_PARTY.md',root/'Navigation/engine.json',*list((root/'Libs').rglob('*')),*list((root/'Navigation').rglob('*')),*list((root/'scripts').glob('*.py'))]
with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as z:
    for file in sorted(set(files)):
        if file.is_dir():continue
        if not file.is_file():raise SystemExit(f'Missing required file: {file}')
        content=file.read_bytes()
        if file.suffix=='.toc':content=content.replace(b'@project-version@',version.removeprefix('v').encode())
        z.writestr('Quintessence/'+str(file.relative_to(root)),content)
    assert z.testzip() is None
(dist/'build.env').write_text('PACKAGE_JOB_ID='+os.environ.get('CI_JOB_ID','local')+'\n')
print(output)
