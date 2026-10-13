#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$repo"
version=$(tr -d '[:space:]' < VERSION)
work=${NATIVE_BUILD_DIR:-"${RUNNER_TEMP:-/tmp}/PalomaNativeRelease"}
out=${NATIVE_OUTPUT_DIR:-"$repo/apps/macos/artifacts"}
identity=${MAC_SIGN_IDENTITY:--}
distribution=${NATIVE_DISTRIBUTION:-0}
if [[ "$distribution" == 1 ]]; then
  [[ "$identity" != - && -n "$identity" ]] || { echo 'Distribution requires the persistent signing certificate' >&2; exit 1; }
  : "${PALOMA_UPDATE_PUBLIC_KEY:?Missing update public key}"
  : "${PALOMA_UPDATE_FEED_URL:?Missing HTTPS native appcast URL}"
  : "${PALOMA_RELAY_URL:?Missing HTTPS relay URL}"
fi
mkdir -p "$out"
xcodebuild -project apps/macos/PalomaMorse/PalomaMorse.xcodeproj -scheme PalomaMorse \
 -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$work" \
 -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
 CODE_SIGNING_ALLOWED=NO ARCHS='arm64 x86_64' \
 PALOMA_UPDATE_PUBLIC_KEY="${PALOMA_UPDATE_PUBLIC_KEY:-}" \
 PALOMA_UPDATE_FEED_URL="${PALOMA_UPDATE_FEED_URL:-}" PALOMA_RELAY_URL="${PALOMA_RELAY_URL:-http://127.0.0.1:3001}" build
app="$work/Build/Products/Release/PalomaMorse.app"
bash apps/macos/Tools/sign-app.sh "$app" "$identity"
verify=(); [[ "$distribution" == 1 ]] && verify=(--distribution)
python3 apps/macos/Tools/verify-app.py "$app" --version "$version" "${verify[@]}"
name="Paloma-Morse-Native-$version-universal"
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/$name.zip"
dmg_stage=$(mktemp -d)
trap 'rm -rf "$dmg_stage"' EXIT
ditto "$app" "$dmg_stage/PalomaMorse.app"
ln -s /Applications "$dmg_stage/Applications"
hdiutil create -volname "Paloma Morse $version" -srcfolder "$dmg_stage" -ov -format UDZO "$out/$name.dmg"
if [[ "$distribution" == 1 ]]; then
  : "${SPARKLE_PRIVATE_KEY_FILE:?Missing Ed25519 signing key file}"
  : "${SPARKLE_TOOLS_DIR:?Missing verified Sparkle tools directory}"
  : "${NATIVE_DOWNLOAD_BASE_URL:?Missing immutable release download URL}"
  signature=$("$SPARKLE_TOOLS_DIR/bin/sign_update" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" -p "$out/$name.zip")
  # Verify with the PUBLIC key embedded in the app, not only the signing key.
  swift apps/macos/Tools/update-key.swift verify "$out/$name.zip" "$PALOMA_UPDATE_PUBLIC_KEY" "$signature"
  python3 apps/macos/Tools/release-metadata.py generate "$out" "$version" \
    --base-url "$NATIVE_DOWNLOAD_BASE_URL" --signature "$signature" --public-key "$PALOMA_UPDATE_PUBLIC_KEY"
fi
printf 'Native packages: %s\n' "$out"
