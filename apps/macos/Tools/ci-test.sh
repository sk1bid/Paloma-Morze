#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$repo"
work=${NATIVE_TEST_DIR:-"${RUNNER_TEMP:-/tmp}/PalomaNativeTests"}
mkdir -p "$work"
npm ci --ignore-scripts --prefix apps/macos/Tools/relay-fixture
module="$repo/apps/macos/Tools/relay-fixture/node_modules/socket.io"
node apps/macos/Tools/local-relay-fixture.cjs "$module" 33071 > "$work/relay.log" 2>&1 & first=$!
node apps/macos/Tools/local-relay-fixture.cjs "$module" 33072 polling > "$work/polling.log" 2>&1 & second=$!
trap 'kill "$first" "$second" 2>/dev/null || true; wait "$first" "$second" 2>/dev/null || true' EXIT
for port in 33071 33072; do
  for attempt in {1..30}; do
    kill -0 "$first" && kill -0 "$second"
    if curl --silent --fail "http://127.0.0.1:$port/api/lobbies" >/dev/null; then break; fi
    sleep .2
  done
  curl --silent --fail "http://127.0.0.1:$port/api/lobbies" >/dev/null
done
set +e
TEST_RUNNER_PALOMA_RUN_NETWORK_TESTS=1 TEST_RUNNER_PALOMA_REQUIRE_NETWORK_TESTS=1 \
 xcodebuild -project apps/macos/PalomaMorse/PalomaMorse.xcodeproj -scheme PalomaMorse \
 -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$work/dd" \
 -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
 -resultBundlePath "$work/Tests.xcresult" test 2>&1 | tee "$work/xcodebuild.log"
build_status=${PIPESTATUS[0]}
set -e
if [[ "$build_status" -ne 0 ]]; then
  # Surface useful public diagnostics in the GitHub check, not just exit code 65.
  python3 - "$work/xcodebuild.log" <<'PYLOG'
import re,sys
from pathlib import Path
lines=Path(sys.argv[1]).read_text(errors='replace').splitlines()
errors=[s for s in lines if 'com.apple.linkd' not in s and re.search(r'error:|recorded an issue|Expectation failed|Testing failed:',s)]
for line in errors[-30:]:
    message=line[:1800].replace('%','%25').replace('\r','%0D')
    print('::error::'+message)
PYLOG
  exit "$build_status"
fi
clang++ -std=c++17 -O2 -pthread ui/native/test_parser.cpp -framework CoreAudio -framework AudioUnit -framework CoreFoundation -o "$work/native-tests"
"$work/native-tests" ui/tests/fixtures/apak-2.12
