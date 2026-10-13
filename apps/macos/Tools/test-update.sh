#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../../.." && pwd)
app=${NATIVE_APP_BUNDLE:-"${RUNNER_TEMP:-/tmp}/native-preview/Build/Products/Release/PalomaMorse.app"}
tools=${SPARKLE_TOOLS_DIR:-"${RUNNER_TEMP:-/tmp}/paloma-sparkle-tools"}
[[ -x "$tools/bin/sign_update" ]] || bash "$repo/apps/macos/Tools/fetch-sparkle-tools.sh" "$tools"
python3 "$repo/apps/macos/Tools/test-update-install.py" "$app" "$tools"
