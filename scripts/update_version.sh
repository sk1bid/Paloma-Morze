#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
node - "$SCRIPT_DIR/.." <<'JS'
const fs = require('fs');
const path = require('path');
const root = process.argv[2];
const version = fs.readFileSync(path.join(root, 'VERSION'), 'utf8').trim();
if (!/^\d+\.\d+\.\d+(?:-[a-zA-Z0-9.]+)?$/.test(version)) throw new Error(`Invalid VERSION: ${version}`);
for (const name of ['package.json', 'package-lock.json']) {
  const file = path.join(root, 'ui', name);
  const data = JSON.parse(fs.readFileSync(file, 'utf8'));
  data.version = version;
  if (name === 'package-lock.json') data.packages[''].version = version;
  fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
}
const native = path.join(root, 'apps/macos/PalomaMorse/Config/NativeVersion.xcconfig');
if (fs.existsSync(native)) {
  const build = version.split('-')[0];
  fs.writeFileSync(native, `// Generated from /VERSION by scripts/update_version.sh; never bump separately.\nMARKETING_VERSION = ${version}\nCURRENT_PROJECT_VERSION = ${build}\n`);
}
console.log(`Synchronized package, lockfile and native versions to ${version}`);
JS
