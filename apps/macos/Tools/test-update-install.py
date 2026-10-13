#!/usr/bin/env python3
"""Install fixture v1 -> v2 using the actual Sparkle installer and sandbox.
Only unique temporary apps/preferences and ephemeral update keys are touched.
"""
import functools,http.server,os,plistlib,shutil,subprocess,sys,tempfile,threading,time,uuid
from pathlib import Path
repo=Path(__file__).resolve().parents[3];tool=repo/'apps/macos/Tools'
source,tools=map(Path,sys.argv[1:]);assert (source/'Contents/Helpers/morze_engine').is_file()
work=Path(tempfile.mkdtemp(prefix='paloma-update-test-'));web=work/'web';web.mkdir()
bundleid='com.paloma.morse.updatetest.'+uuid.uuid4().hex
prefs=Path.home()/'Library/Containers'/bundleid/'Data/Library/Preferences'/(bundleid+'.plist')
identity=os.environ.get('MAC_SIGN_IDENTITY','-')
class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*args):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Handler,directory=str(web)))
threading.Thread(target=server.serve_forever,daemon=True).start()
port=server.server_address[1]
def run(args,**kwargs):return subprocess.run([str(a) for a in args],check=True,**kwargs)
process=None
try:
    run(['swift',tool/'update-key.swift','generate',work/'private.key',work/'public.key'])
    public=(work/'public.key').read_text()
    run(['swiftc','-parse-as-library','-F',tools,'-framework','Sparkle','-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks',tool/'UpdateInstallHarness.swift','-o',work/'Fixture'])
    def app(parent,version):
        app=parent/'PalomaUpdateFixture.app';(app/'Contents/MacOS').mkdir(parents=True);(app/'Contents/Helpers').mkdir()
        shutil.copy2(work/'Fixture',app/'Contents/MacOS/Fixture')
        shutil.copy2(source/'Contents/Helpers/morze_engine',app/'Contents/Helpers/morze_engine')
        run(['ditto',tools/'Sparkle.framework',app/'Contents/Frameworks/Sparkle.framework'])
        info={'CFBundleIdentifier':bundleid,'CFBundleName':'PalomaUpdateFixture','CFBundleExecutable':'Fixture','CFBundlePackageType':'APPL','CFBundleVersion':str(version),'CFBundleShortVersionString':str(version)+'.0','LSUIElement':True,'SUFeedURL':f'http://localhost:{port}/appcast.xml','SUPublicEDKey':public,'SUEnableInstallerLauncherService':True,'SUShowReleaseNotes':False,'SUEnableAutomaticChecks':False,'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True,'NSExceptionDomains':{'localhost':{'NSExceptionAllowsInsecureHTTPLoads':True}}}}
        (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        run(['bash',tool/'sign-app.sh',app,identity],stdout=subprocess.DEVNULL)
        return app
    first=app(work/'installed',1);second=app(work/'second',2)
    archive=web/'update.zip';run(['ditto','-c','-k','--sequesterRsrc','--keepParent',second,archive])
    signature=subprocess.check_output([str(tools/'bin/sign_update'),'--ed-key-file',str(work/'private.key'),'-p',str(archive)],text=True).strip()
    run(['swift',tool/'update-key.swift','verify',archive,public,signature])
    bad=work/'corrupt.zip';bad.write_bytes(archive.read_bytes()+b'corruption')
    assert subprocess.run(['swift',str(tool/'update-key.swift'),'verify',str(bad),public,signature],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0
    (web/'appcast.xml').write_text(f'''<?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Isolated update test</title><item><title>Fixture2</title><sparkle:version>2</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString><enclosure url="http://localhost:{port}/update.zip" length="{archive.stat().st_size}" type="application/octet-stream" sparkle:edSignature="{signature}"/></item></channel></rss>''')
    log=(work/'install.log').open('w')
    process=subprocess.Popen([str(first/'Contents/MacOS/Fixture')],stdout=log,stderr=log)
    result=None
    for _ in range(450):
        if prefs.exists():
            try:
                settings=plistlib.loads(prefs.read_bytes());result=settings.get('update-test-result')
                if settings.get('update-test-error'):raise RuntimeError(settings['update-test-error'])
                if result:break
            except plistlib.InvalidFileException:pass
        time.sleep(.2)
    assert result=='PASS',f'Update did not preserve settings: {result}'
    assert plistlib.loads((first/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='2'
    print('PASS: Sparkle installed v1 -> v2, relaunched, preserved settings; corrupted signature rejected')
except Exception:
    if (work/'install.log').exists():print((work/'install.log').read_text(),file=sys.stderr)
    raise
finally:
    server.shutdown()
    if process and process.poll() is None:
        process.terminate()
        try:process.wait(timeout=5)
        except subprocess.TimeoutExpired:process.kill();process.wait()
    subprocess.run(['defaults','delete',str(prefs.with_suffix(''))],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    shutil.rmtree(work)
