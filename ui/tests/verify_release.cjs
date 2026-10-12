const yaml = require('js-yaml');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
async function verifyMetadata(directory, filename, version) {
  const data = yaml.load(fs.readFileSync(path.join(directory, filename), 'utf8'));
  if (data.version !== version) throw new Error(`${filename}: version ${data.version} != ${version}`);
  if (!Array.isArray(data.files) || !data.files.length) throw new Error(`${filename}: no files`);
  for (const file of data.files) {
    const name = decodeURIComponent(file.url);
    if (path.basename(name) !== name || name.includes('\\')) throw new Error(`${filename}: invalid artifact path`);
    const target = path.join(directory, name), stat = fs.statSync(target);
    if (!stat.isFile() || !stat.size) throw new Error(`${name}: empty artifact`);
    if (file.size !== undefined && file.size !== stat.size) throw new Error(`${name}: size mismatch`);
    const hash = crypto.createHash('sha512');
    for await (const chunk of fs.createReadStream(target)) hash.update(chunk);
    if (hash.digest('base64') !== file.sha512) throw new Error(`${name}: SHA-512 mismatch`);
    console.log(`[OK] ${name}: version, size and SHA-512 verified`);
  }
}
async function verifyRelease(directory, version) {
  for (const name of ['latest.yml', 'latest-mac.yml', 'latest-linux.yml']) await verifyMetadata(directory, name, version);
}
if (require.main === module) {
  const version = fs.readFileSync(path.join(__dirname, '..', '..', 'VERSION'), 'utf8').trim();
  verifyRelease(path.join(__dirname, '..', 'release'), version)
    .then(() => console.log('--- Release integrity verification passed ---'))
    .catch(error => { console.error(`[FAIL] ${error.message}`); process.exitCode = 1; });
}
module.exports = { verifyMetadata, verifyRelease };
