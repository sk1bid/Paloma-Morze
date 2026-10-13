#!/bin/bash
set -euo pipefail
app=${1:?Usage: sign-app.sh APP IDENTITY}
identity=${2:?Missing signing identity}
repo=$(cd "$(dirname "$0")/../../.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
sign=(codesign --force --sign "$identity")
[[ -n ${MAC_SIGN_KEYCHAIN:-} ]] && sign+=(--keychain "$MAC_SIGN_KEYCHAIN")
# Sign nested components individually. --deep is for verification, never signing.
framework="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
[[ -d "$framework" ]] || { echo 'Sparkle is not embedded' >&2; exit 1; }
for item in "$framework/XPCServices/Installer.xpc" "$framework/XPCServices/Downloader.xpc" "$framework/Autoupdate" "$framework/Updater.app"; do
  [[ -e "$item" ]] || continue
  "${sign[@]}" --options runtime "$item"
done
"${sign[@]}" "$app/Contents/Frameworks/Sparkle.framework"
"${sign[@]}" --entitlements "$repo/apps/macos/PalomaMorse/Config/Helper.entitlements" "$app/Contents/Helpers/morze_engine"
python3 - "$app" "$repo" "$temp/app.plist" <<'PY'
import plistlib,sys
from pathlib import Path
app,root,out=map(Path,sys.argv[1:])
id=plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleIdentifier']
s=(root/'apps/macos/PalomaMorse/Config/App.entitlements').read_text().replace('$(PRODUCT_BUNDLE_IDENTIFIER)',id)
e=plistlib.loads(s.encode());e.pop('com.apple.security.get-task-allow',None)
out.write_bytes(plistlib.dumps(e))
PY
# Self-signed distribution stays sandboxed. Hardened Runtime + notarization is a
# separate Developer ID mode; do not weaken library validation with an exception.
"${sign[@]}" --entitlements "$temp/app.plist" "$app"
codesign --verify --deep --strict "$app"
