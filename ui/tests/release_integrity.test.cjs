const fs=require('fs'), os=require('os'), path=require('path'), crypto=require('crypto'), yaml=require('js-yaml');
const {verifyRelease}=require('./verify_release.cjs');
describe('release publication gate',()=>{
  let dir;
  beforeEach(()=>{
    dir=fs.mkdtempSync(path.join(os.tmpdir(),'paloma-release-'));
    const content=Buffer.from('release test payload');fs.writeFileSync(path.join(dir,'app.zip'),content);
    const meta=yaml.dump({version:'0.4.20',files:[{url:'app.zip',size:content.length,sha512:crypto.createHash('sha512').update(content).digest('base64')}]});
    for(const name of ['latest.yml','latest-mac.yml','latest-linux.yml'])fs.writeFileSync(path.join(dir,name),meta);
  });
  afterEach(()=>fs.rmSync(dir,{recursive:true,force:true}));
  test('accepts verified artifacts for all platforms',async()=>{await expect(verifyRelease(dir,'0.4.20')).resolves.toBeUndefined();});
  test('rejects corruption with unchanged file size',async()=>{
    const file=path.join(dir,'app.zip'),content=fs.readFileSync(file);content[0]^=1;fs.writeFileSync(file,content);
    await expect(verifyRelease(dir,'0.4.20')).rejects.toThrow('SHA-512 mismatch');
  });
  test('rejects stale version',async()=>{await expect(verifyRelease(dir,'0.4.21')).rejects.toThrow('version');});
  test('rejects missing platform metadata',async()=>{
    fs.unlinkSync(path.join(dir,'latest-linux.yml'));await expect(verifyRelease(dir,'0.4.20')).rejects.toThrow();
  });
});
