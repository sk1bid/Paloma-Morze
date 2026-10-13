#!/bin/bash
set -euo pipefail
dest=${1:?Usage: fetch-sparkle-tools.sh OUTPUT_DIRECTORY}
mkdir -p "$dest"
archive="$dest/Sparkle-2.10.0.tar.xz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 'https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz' -o "$archive"
fi
echo "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c  $archive" | shasum -a 256 -c -
tar -xf "$archive" -C "$dest"
