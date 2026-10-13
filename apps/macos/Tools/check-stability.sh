#!/bin/zsh
# Launches every fixture at review sizes and reports whether the app survives.
# Usage: Tools/check-stability.sh [fixture ...]   (Debug build, preview data only)
# Runs an isolated review copy (see review-build.zsh); a running Paloma Morse is left alone.
set -u
cd "${0:A:h}/.."
source Tools/review-build.zsh
SIZES=(${=PALOMA_SIZES:-1000x700 1440x900})
if (( $# )); then FIXTURES=($@); else FIXTURES=(${(f)"$(review_fixtures)"}); fi
trap review_cleanup EXIT INT TERM

review_build || exit 1
failures=0
for fixture in $FIXTURES; do
  for size in $SIZES; do
    review_launch direct -PalomaFixture "$fixture" -PalomaWindowSize "$size" ${=PALOMA_EXTRA_ARGS:-}
    sleep ${PALOMA_SETTLE:-6}
    if kill -0 $REVIEW_PID 2>/dev/null; then echo "ok    $fixture $size"; else echo "CRASH $fixture $size"; failures=$((failures + 1)); fi
    review_terminate
  done
done
echo "failures: $failures"
exit $(( failures > 0 ))
