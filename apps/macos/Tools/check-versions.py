#!/usr/bin/env python3
import json,re
from pathlib import Path
root=Path(__file__).resolve().parents[3]
v=(root/'VERSION').read_text().strip()
assert re.fullmatch(r'\d+\.\d+\.\d+',v),'Native distribution currently supports stable tags only'
for name in ['package.json','package-lock.json']:
    p=json.loads((root/'ui'/name).read_text());assert p['version']==v
    if name=='package-lock.json':assert p['packages']['']['version']==v
config=(root/'apps/macos/PalomaMorse/Config/NativeVersion.xcconfig').read_text()
assert f'MARKETING_VERSION = {v}\n' in config
assert f'CURRENT_PROJECT_VERSION = {v}\n' in config
print('PASS: one version across native macOS and legacy Windows/Linux/macOS')
