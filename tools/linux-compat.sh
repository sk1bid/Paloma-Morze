#!/usr/bin/env bash
# Build the helper and verify the AppImage on the same glibc 2.28 baseline.
# Node/Electron packaging runs on the host, never in this archived toolchain.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
image=paloma-linux-compat:buster
case "${1:-}" in
  build|test) operation=$1; shift ;;
  *) echo "Usage: $0 build | test path/to/package.AppImage" >&2; exit 2 ;;
esac

docker build --platform linux/amd64 -t "$image" "$root/tools/linux-compat"
# Compilation preserves checkout ownership. Smoke uses a named, unprivileged
# account because PulseAudio resolves its uid through the container's passwd.
container_user="$(id -u):$(id -g)"
if [[ "$operation" == test ]]; then container_user=1000:1000; fi
runtime=(docker run --rm --platform linux/amd64 --network none
  --user "$container_user" -e HOME=/tmp -e LC_ALL=C
  --mount "type=bind,source=$root,target=/workspace" -w /workspace "$image")
if [[ "$operation" == build ]]; then
  [[ $# == 0 ]] || { echo 'build does not take arguments' >&2; exit 2; }
  "${runtime[@]}" bash -euc '
    flags=(-std=c++17 -O3 -pthread)
    g++ ui/native/test_parser.cpp -I ui/native -o /tmp/native_audio_tests "${flags[@]}" -lasound -lm -ldl
    /tmp/native_audio_tests
    g++ ui/native/morze_engine_v2.cpp -I ui/native -o ui/native/morze_app "${flags[@]}" -lasound -lm -ldl
    chmod 755 ui/native/morze_app
    cp ui/native/morze_app ui/native/morze_app_linux
    readelf --version-info ui/native/morze_app
  '
else
  [[ $# == 1 ]] || { echo 'test requires exactly one AppImage' >&2; exit 2; }
  # Resolve the artifact in the mounted checkout, including absolute arguments.
  artifact=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve().relative_to(pathlib.Path(sys.argv[2]).resolve()))' "$1" "$root")
  "${runtime[@]}" bash tools/test-linux-appimage-audio.sh --no-sandbox "$artifact"
fi
