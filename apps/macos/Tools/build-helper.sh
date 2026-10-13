#!/bin/bash
set -euo pipefail
repo=$(cd "$SRCROOT/../../.." && pwd)
output="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/morze_engine"
mkdir -p "$(dirname "$output")"
# Match the app slices: Release defaults to universal, Debug may be host-only.
arch_flags=()
for arch in ${ARCHS:-$(uname -m)}; do arch_flags+=(-arch "$arch"); done
/usr/bin/clang++ "${arch_flags[@]}" -std=c++17 -O2 -pthread \
  -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET:-26.0}" \
  "$repo/ui/native/morze_engine_v2.cpp" \
  -framework CoreAudio -framework AudioUnit -framework CoreFoundation -o "$output"
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]]; then
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --entitlements "$SRCROOT/Config/Helper.entitlements" "$output"
fi
