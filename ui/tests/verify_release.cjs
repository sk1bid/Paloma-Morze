const yaml = require('js-yaml');
const fs = require('fs');
const path = require('path');

const releaseDir = path.join(__dirname, '..', 'release');

function verifyMetadata(filename) {
  const yamlPath = path.join(releaseDir, filename);
  if (!fs.existsSync(yamlPath)) {
    // Without it installed apps on that platform cannot find the update
    console.error(`[FAIL] ${filename} not found: auto-update metadata missing from the release`);
    return false;
  }

  try {
    const data = yaml.load(fs.readFileSync(yamlPath, 'utf8'));
    console.log(`Verifying metadata from ${filename}...`);
    
    if (!data.files || !Array.isArray(data.files)) {
      throw new Error(`Invalid ${filename} structure: 'files' array missing.`);
    }

    for (const fileInfo of data.files) {
      const decodedPath = decodeURIComponent(fileInfo.url);
      const filePath = path.join(releaseDir, decodedPath);
      if (!fs.existsSync(filePath)) {
        throw new Error(`CRITICAL: File ${decodedPath} referenced in ${filename} is missing!`);
      }
      console.log(`[OK] Found ${decodedPath}`);
    }
  } catch (err) {
    console.error(`[FAIL] ${filename} validation failed: ${err.message}`);
    return false;
  }
  return true;
}

const ok = ['latest.yml', 'latest-mac.yml', 'latest-linux.yml']
  .map(verifyMetadata)
  .every(Boolean);

if (!ok) {
  process.exit(1);
} else {
  console.log('--- Metadata Verification Passed ---');
}
