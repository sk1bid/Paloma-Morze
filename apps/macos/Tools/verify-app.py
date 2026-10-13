#!/usr/bin/env python3
import argparse, plistlib, subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('app',type=Path);p.add_argument('--version',required=True);p.add_argument('--distribution',action='store_true');a=p.parse_args()
info=plistlib.loads((a.app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='com.paloma.morse.native',info['CFBundleIdentifier']
assert info['CFBundleShortVersionString']==a.version
assert info['CFBundleVersion']==a.version.split('-')[0]
assert info['LSMinimumSystemVersion']=='26.0'
assert (a.app/'Contents/Resources/morse.v1.json').is_file()
assert (a.app/'Contents/Frameworks/Sparkle.framework').is_dir()
assert info.get('SUEnableInstallerLauncherService') in [True,'YES']
subprocess.run(['codesign','--verify','--deep','--strict',str(a.app)],check=True)
e=plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',str(a.app)],stderr=subprocess.DEVNULL))
assert e.get('com.apple.security.app-sandbox') is True
assert not e.get('com.apple.security.get-task-allow',False)
assert 'com.paloma.morse.native-spks' in e['com.apple.security.temporary-exception.mach-lookup.global-name']
for binary in [a.app/'Contents/MacOS/PalomaMorse',a.app/'Contents/Helpers/morze_engine']:
    assert set(subprocess.check_output(['lipo','-archs',str(binary)],text=True).split())=={'arm64','x86_64'}
    load=subprocess.check_output(['xcrun','vtool','-show-build',str(binary)],text=True)
    assert load.count('minos 26.0')==2,load
he=plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',str(a.app/'Contents/Helpers/morze_engine')],stderr=subprocess.DEVNULL))
assert he=={'com.apple.security.app-sandbox':True,'com.apple.security.inherit':True},he
if a.distribution:
    import base64,urllib.parse
    assert len(base64.b64decode(info['SUPublicEDKey'],validate=True))==32
    for key in ['SUFeedURL','PalomaRelayURL']:
        u=urllib.parse.urlparse(info[key]);assert u.scheme=='https' and u.hostname and not u.username and not u.password
        assert u.hostname not in ['localhost','127.0.0.1','::1'],key
    details=subprocess.check_output(['codesign','-dv',str(a.app)],stderr=subprocess.STDOUT,text=True)
    assert 'Signature=adhoc' not in details
assert not any(p.name in ['Electron Framework.framework','app.asar','node_modules'] for p in a.app.rglob('*'))
print('PASS: native identity/version, universal app/helper, minimum OS, sandbox, signatures and package contents')
