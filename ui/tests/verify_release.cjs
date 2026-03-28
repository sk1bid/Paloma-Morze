const yaml = require('js-yaml');
const fs = require('fs');
const path = require('path');

const releaseDir = path.join(__dirname, '..', 'release');

function verifyMetadata(filename) {
  const yamlPath = path.join(releaseDir, filename);
  if (!fs.existsSync(yamlPath)) {
    console.log(`[Skip] ${filename} not found (platform build might be missing)`);
    return true;
  }

  try {
    const data = yaml.load(fs.readFileSync(yamlPath, 'utf8'));
    console.log(`Verifying metadata from ${filename}...`);
    
    if (!data.files || !Array.isArray(data.files)) {
      throw new Error(`Invalid ${filename} structure: 'files' array missing.`);
    }

    for (const fileInfo of data.files) {
      const filePath = path.join(releaseDir, fileInfo.url);
      if (!fs.existsSync(filePath)) {
        throw new Error(`CRITICAL: File ${fileInfo.url} referenced in ${filename} is missing!`);
      }
      console.log(`[OK] Found ${fileInfo.url}`);
    }
  } catch (err) {
    console.error(`[FAIL] ${filename} validation failed: ${err.message}`);
    return false;
  }
  return true;
}

const ok = verifyMetadata('latest.yml') && verifyMetadata('latest-mac.yml');

if (!ok) {
  process.exit(1);
} else {
  console.log('--- Metadata Verification Passed ---');
}
