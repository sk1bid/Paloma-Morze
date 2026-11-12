#!/usr/bin/env bash
# Debian 10 baseline: python3 python3-websocket binutils pulseaudio
# pulseaudio-utils xvfb xauth and Electron shared libraries; no FUSE required.
set -euo pipefail
exec python3 "$(dirname "$0")/test-linux-appimage-audio.py" "$@"
