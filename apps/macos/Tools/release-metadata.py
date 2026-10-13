#!/usr/bin/env python3
"""Immutable archive manifest + Sparkle feed. Also validates downloaded release artifacts."""
import argparse,base64,hashlib,json,re,sys,urllib.parse,xml.etree.ElementTree as ET,zipfile
from pathlib import Path
NS='http://www.andymatuschak.org/xml-namespaces/sparkle';ET.register_namespace('sparkle',NS)
def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
    return h.hexdigest()
def generate(folder,version,base_url,signature,public_key):
    assert re.fullmatch(r'\d+\.\d+\.\d+',version),'Native stable feed only accepts stable release versions'
    u=urllib.parse.urlparse(base_url);assert u.scheme=='https' and u.hostname and not u.username and not u.password
    assert len(base64.b64decode(signature,validate=True))==64
    assert len(base64.b64decode(public_key,validate=True))==32
    stem=f'Paloma-Morse-Native-{version}-universal'
    files=[folder/f'{stem}.zip',folder/f'{stem}.dmg']
    manifest={'version':version,'bundleID':'com.paloma.morse.native','minimumSystemVersion':'26.0','publicKey':public_key,'files':[{'name':p.name,'size':p.stat().st_size,'sha256':digest(p)} for p in files]}
    (folder/'native-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (folder/'native-SHA256SUMS.txt').write_text(''.join(f'{f["sha256"]}  {f["name"]}\n' for f in manifest['files']))
    root=ET.Element('rss',version='2.0');channel=ET.SubElement(root,'channel');ET.SubElement(channel,'title').text='Paloma Morse for macOS'
    item=ET.SubElement(channel,'item');ET.SubElement(item,'title').text=f'Paloma Morse {version}'
    ET.SubElement(item,f'{{{NS}}}version').text=version
    ET.SubElement(item,f'{{{NS}}}shortVersionString').text=version
    ET.SubElement(item,f'{{{NS}}}minimumSystemVersion').text='26.0'
    ET.SubElement(item,'enclosure',{'url':base_url.rstrip('/')+'/'+urllib.parse.quote(files[0].name),'length':str(files[0].stat().st_size),'type':'application/octet-stream',f'{{{NS}}}edSignature':signature})
    ET.indent(root);ET.ElementTree(root).write(folder/'appcast.xml',encoding='utf-8',xml_declaration=True)
def verify(folder,version):
    m=json.loads((folder/'native-manifest.json').read_text());assert m['version']==version
    assert m['bundleID']=='com.paloma.morse.native' and m['minimumSystemVersion']=='26.0'
    assert len(base64.b64decode(m['publicKey'],validate=True))==32
    expected={f'Paloma-Morse-Native-{version}-universal.{ext}' for ext in ['zip','dmg']}
    assert {f['name'] for f in m['files']}==expected
    for f in m['files']:
        assert Path(f['name']).name==f['name']
        p=folder/f['name'];assert p.stat().st_size==f['size'] and f['size']>0;assert digest(p)==f['sha256']
    xml=ET.parse(folder/'appcast.xml');items=xml.findall('./channel/item');assert len(items)==1
    i=items[0];assert i.findtext(f'{{{NS}}}version')==version
    assert i.findtext(f'{{{NS}}}minimumSystemVersion')=='26.0'
    e=i.find('enclosure');url=urllib.parse.urlparse(e.attrib['url']);assert url.scheme=='https'
    name=urllib.parse.unquote(Path(url.path).name);assert name in expected and name.endswith('.zip')
    assert int(e.attrib['length'])==(folder/name).stat().st_size
    assert len(base64.b64decode(e.attrib[f'{{{NS}}}edSignature'],validate=True))==64
    with zipfile.ZipFile(folder/name) as z:
        names=z.namelist();assert 'PalomaMorse.app/Contents/Info.plist' in names
        assert 'PalomaMorse.app/Contents/Helpers/morze_engine' in names
        assert not any(n.startswith('/') or '..' in Path(n).parts for n in names)
    print('PASS: native release archive manifest and appcast references')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=['generate','verify']);p.add_argument('folder',type=Path);p.add_argument('version');p.add_argument('--base-url');p.add_argument('--signature');p.add_argument('--public-key');a=p.parse_args()
    if a.action=='generate':generate(a.folder,a.version,a.base_url,a.signature,a.public_key)
    verify(a.folder,a.version)
