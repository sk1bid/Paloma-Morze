#!/usr/bin/env bash
# Ubuntu 22.04: python3 binutils pulseaudio pulseaudio-utils; no FUSE required.
set -euo pipefail
exec python3 "$(dirname "$0")/test-linux-appimage-audio.py" "$@"
