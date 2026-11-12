import importlib.util
import tempfile
import unittest
from pathlib import Path

spec=importlib.util.spec_from_file_location('upload',Path(__file__).resolve().parents[1]/'.github/scripts/curseforge_upload.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class Upload(unittest.TestCase):
    def test_members_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); rows=[[a,'1.2.3'] for a in sorted(m.MEMBER_ADDONS)]
            for a,_ in rows:
                (root/a).mkdir();(root/a/f'{a}.toc').write_text('## Version: 1.2.3')
            self.assertTrue(m.build_zip(root,rows).startswith(b'PK'))
            with self.assertRaises(SystemExit):m.build_zip(root,rows+[['quinte-recrut','1.0.0']])
            (root/'Quintessence/Officers.lua').write_text('interdit')
            with self.assertRaises(SystemExit):m.build_zip(root,rows)
if __name__=='__main__':unittest.main()
