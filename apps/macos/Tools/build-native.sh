#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../../.." && pwd)
derived=${1:-/tmp/PalomaMorseNativeBuild}
xcodebuild -project "$repo/apps/macos/PalomaMorse/PalomaMorse.xcodeproj" -scheme PalomaMorse -configuration Debug -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO build
bundle="$derived/Build/Products/Debug/PalomaMorse.app"
codesign --force --sign - --entitlements "$repo/apps/macos/PalomaMorse/Config/Helper.entitlements" "$bundle/Contents/Helpers/morze_engine"
codesign --force --sign - --entitlements "$repo/apps/macos/PalomaMorse/Config/App.entitlements" "$bundle"
echo "$bundle"
