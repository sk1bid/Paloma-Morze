#!/usr/bin/env python3
"""Merge a verified release feed into the dedicated native-updates branch content."""
import argparse,copy,re,xml.etree.ElementTree as ET
from pathlib import Path
NS='http://www.andymatuschak.org/xml-namespaces/sparkle';ET.register_namespace('sparkle',NS)
def version(item):
    text=item.findtext(f'{{{NS}}}version') or ''
    assert re.fullmatch(r'\d+\.\d+\.\d+',text),'Invalid stable version'
    return tuple(map(int,text.split('.')))
def canonical(item):
    return (item.tag,tuple(sorted(item.attrib.items())),(item.text or '').strip(),tuple(canonical(c) for c in item))
def merge(new,old,out):
    tree=ET.parse(new);channel=tree.getroot().find('channel');item=channel.find('item');v=version(item)
    if old.exists():
        prior=ET.parse(old).findall('./channel/item')
        assert all(version(i)<=v for i in prior),'Refusing to downgrade update feed'
        for previous in prior:
            if version(previous)==v:
                assert canonical(previous)==canonical(item),'Published version is immutable'
            else:channel.append(copy.deepcopy(previous))
    ET.indent(tree);tree.write(out,encoding='utf-8',xml_declaration=True)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('new',type=Path);p.add_argument('old',type=Path);p.add_argument('out',type=Path);a=p.parse_args();merge(a.new,a.old,a.out)
