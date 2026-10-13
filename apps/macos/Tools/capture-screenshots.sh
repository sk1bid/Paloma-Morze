#!/bin/zsh
# Captures review screenshots of fixture states (Debug build, preview data only).
# Usage: Tools/capture-screenshots.sh [output-dir] [fixture ...]
# Requires Screen Recording permission for the terminal running it. Runs an
# isolated review copy (see review-build.zsh); a running Paloma Morse is left alone.
set -u
cd "${0:A:h}/.."
source Tools/review-build.zsh
OUT=${1:-../../design/macos/screenshots}
shift 2>/dev/null
if (( $# )); then FIXTURES=($@); else FIXTURES=(${(f)"$(review_fixtures)"}); fi
SIZES=(${=PALOMA_SIZES:-1000x700 1440x900})
APPEARANCES=(${=PALOMA_APPEARANCES:-light dark})
trap review_cleanup EXIT INT TERM

review_build || exit 1
swiftc -O -o "$REVIEW_BUILD/window-bounds" Tools/window-bounds.swift || exit 1
mkdir -p "$OUT"
failures=0

for fixture in $FIXTURES; do
  for size in $SIZES; do
    for appearance in $APPEARANCES; do
      review_launch open -PalomaFixture "$fixture" ${=PALOMA_EXTRA_ARGS:-} \
        -PalomaAppearance "$appearance" -PalomaWindowSize "$size"
      # Wait (up to 15 s) for the main window at the requested width, then let it settle.
      windows=()
      want_width=${size%x*}
      for attempt in {1..60}; do
        [[ -z $REVIEW_PID ]] && break
        windows=("${(@f)$("$REVIEW_BUILD/window-bounds" "$REVIEW_PID" | sort -k4 -n -r)}")
        read _ _ _ top_width _ <<< "${windows[1]:-}"
        [[ ${top_width:-0} -ge $want_width ]] && break
        sleep 0.25
      done
      sleep 1.5
      [[ -n $REVIEW_PID ]] && windows=("${(@f)$("$REVIEW_BUILD/window-bounds" "$REVIEW_PID" | sort -k4 -n -r)}")
      if [[ -z ${windows[1]:-} ]]; then
        echo "NOT CAPTURED: $fixture $size $appearance (no window)"; failures=$((failures + 1))
        review_terminate; continue
      fi
      index=0
      for line in $windows; do
        read id x y w h name <<< "$line"
        suffix=$([[ $index -eq 0 ]] && echo "" || echo "-$index")
        file="$OUT/${fixture}_${size}_${appearance}${suffix}.png"
        # Window capture: settings windows and sheets are saved as -1, -2…
        if screencapture -o -x -l "$id" "$file"; then
          echo "$file  window ${w}x${h}"
        else
          echo "NOT CAPTURED: $file"; failures=$((failures + 1))
        fi
        index=$((index + 1))
      done
      review_terminate
    done
  done
done
echo "not captured: $failures"
exit $(( failures > 0 ))
