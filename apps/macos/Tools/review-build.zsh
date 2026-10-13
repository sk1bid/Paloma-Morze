# Shared by capture-screenshots.sh and check-stability.sh (sourced, zsh).
# Builds a Debug copy under its own bundle identifier, so review runs keep their
# own defaults domain and never touch the settings, saved state or process of a
# copy of Paloma Morse the developer is running. Only the PID started here is
# ever terminated.
REVIEW_BUNDLE_ID=${PALOMA_REVIEW_BUNDLE_ID:-com.paloma.morse.native-review}
REVIEW_BUILD=$(mktemp -d)
REVIEW_BUILD=${REVIEW_BUILD:A}   # /private/var/…, the path pgrep sees
REVIEW_PID=""
# The app is sandboxed: its defaults live in the review container.
REVIEW_PREFS="$HOME/Library/Containers/$REVIEW_BUNDLE_ID/Data/Library/Preferences/$REVIEW_BUNDLE_ID"

review_forget_defaults() {
  defaults delete "$REVIEW_PREFS" 2>/dev/null
  defaults delete "$REVIEW_BUNDLE_ID" 2>/dev/null
}

review_build() {
  xcodebuild -project PalomaMorse/PalomaMorse.xcodeproj -scheme PalomaMorse -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$REVIEW_BUILD/dd" -quiet build \
    PRODUCT_BUNDLE_IDENTIFIER="$REVIEW_BUNDLE_ID" || return 1
  REVIEW_APP="$REVIEW_BUILD/dd/Build/Products/Debug/PalomaMorse.app"
  REVIEW_EXEC="$REVIEW_APP/Contents/MacOS/PalomaMorse"
}

# review_launch <open|direct> args… — sets REVIEW_PID.
review_launch() {
  local how=$1; shift
  # The review domain belongs to these scripts alone: forget its autosaved window
  # frame so -PalomaWindowSize applies.
  review_forget_defaults
  if [[ $how == open ]]; then
    open -n "$REVIEW_APP" --args -ApplePersistenceIgnoreState YES "$@"
    local tries=0
    REVIEW_PID=""
    while [[ -z $REVIEW_PID && $tries -lt 50 ]]; do
      REVIEW_PID=$(pgrep -f "^$REVIEW_EXEC" | head -1)
      sleep 0.1; tries=$((tries + 1))
    done
  else
    "$REVIEW_EXEC" -ApplePersistenceIgnoreState YES "$@" > /dev/null 2>&1 &
    REVIEW_PID=$!
  fi
}

review_terminate() {
  [[ -z $REVIEW_PID ]] && return
  kill "$REVIEW_PID" 2>/dev/null
  local tries=0
  while kill -0 "$REVIEW_PID" 2>/dev/null && [[ $tries -lt 30 ]]; do sleep 0.1; tries=$((tries + 1)); done
  REVIEW_PID=""
}

review_cleanup() {
  review_terminate
  # Anything still running from this run's private build folder is ours alone.
  [[ -n ${REVIEW_EXEC:-} ]] && pkill -f "^$REVIEW_EXEC" 2>/dev/null
  review_forget_defaults
  rm -rf "$REVIEW_BUILD"
}

review_fixtures() {
  grep -oE '"[a-z]+\.[a-z-]+"' PalomaMorse/PalomaMorse/PreviewSupport/PreviewFixtures.swift | tr -d '"' | awk '!seen[$0]++'
}
