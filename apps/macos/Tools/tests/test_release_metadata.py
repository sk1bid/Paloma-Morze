import base64,importlib.util,json,tempfile,unittest,zipfile,xml.etree.ElementTree as ET
from pathlib import Path

def module(name):
    s=importlib.util.spec_from_file_location(name,Path(__file__).resolve().parents[1]/(name+'.py'));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
metadata=module('release-metadata');feed=module('publish-feed')
class ReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        self.key=base64.b64encode(bytes(32)).decode();self.sig=base64.b64encode(bytes(64)).decode()
        self.make('0.4.21')
    def tearDown(self):self.temp.cleanup()
    def make(self,v):
        name=f'Paloma-Morse-Native-{v}-universal'
        with zipfile.ZipFile(self.root/(name+'.zip'),'w') as z:
            z.writestr('PalomaMorse.app/Contents/Info.plist','fixture')
            z.writestr('PalomaMorse.app/Contents/Helpers/morze_engine','fixture')
        (self.root/(name+'.dmg')).write_bytes(b'fixture-dmg')
        metadata.generate(self.root,v,'https://example.org/download/v'+v,self.sig,self.key)
    def test_valid_pair(self):metadata.verify(self.root,'0.4.21')
    def test_corruption_is_rejected(self):
        p=self.root/'Paloma-Morse-Native-0.4.21-universal.dmg';p.write_bytes(b'changed-dmg')
        with self.assertRaises(AssertionError):metadata.verify(self.root,'0.4.21')
    def test_stale_version_is_rejected(self):
        with self.assertRaises(AssertionError):metadata.verify(self.root,'0.4.22')
    def test_bad_archive_path_is_rejected(self):
        p=self.root/'native-manifest.json';d=json.loads(p.read_text());d['files'][0]['name']='../archive.zip';p.write_text(json.dumps(d))
        with self.assertRaises(AssertionError):metadata.verify(self.root,'0.4.21')
    def test_archive_traversal_is_rejected(self):
        p=self.root/'Paloma-Morse-Native-0.4.21-universal.zip'
        with zipfile.ZipFile(p,'a') as z:z.writestr('../outside','invalid')
        metadata.generate(self.root,'0.4.21','https://example.org/download/v0.4.21',self.sig,self.key)
        with self.assertRaises(AssertionError):metadata.verify(self.root,'0.4.21')
    def test_feed_retains_history_and_rejects_downgrade(self):
        old=self.root/'old.xml';old.write_bytes((self.root/'appcast.xml').read_bytes())
        self.make('0.4.22');out=self.root/'merged.xml';feed.merge(self.root/'appcast.xml',old,out)
        self.assertEqual(len(ET.parse(out).findall('./channel/item')),2)
        with self.assertRaises(AssertionError):feed.merge(old,out,self.root/'invalid.xml')
    def test_feed_update_is_idempotent_with_history(self):
        old=self.root/'old.xml';old.write_bytes((self.root/'appcast.xml').read_bytes())
        self.make('0.4.22');out=self.root/'merged.xml';feed.merge(self.root/'appcast.xml',old,out)
        feed.merge(self.root/'appcast.xml',out,self.root/'again.xml')
        self.assertEqual(out.read_bytes(),(self.root/'again.xml').read_bytes())
    def test_published_version_cannot_be_replaced(self):
        old=self.root/'old.xml';old.write_bytes((self.root/'appcast.xml').read_bytes())
        tree=ET.parse(self.root/'appcast.xml');tree.find('./channel/item/title').text='replacement';tree.write(self.root/'appcast.xml')
        with self.assertRaises(AssertionError):feed.merge(self.root/'appcast.xml',old,self.root/'bad.xml')
