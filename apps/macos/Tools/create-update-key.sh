#!/bin/bash
set -euo pipefail
# Explicit one-time owner setup. Files must be kept outside the repository.
dir=${1:?Usage: create-update-key.sh PRIVATE_DIRECTORY_OUTSIDE_REPOSITORY}
repo=$(cd "$(dirname "$0")/../../.." && pwd)
mkdir -p "$dir"
dir=$(cd "$dir" && pwd)
case "$dir/" in "$repo/"*) echo 'Keep signing keys outside the checkout' >&2; exit 1;; esac
chmod 700 "$dir"
swift "$repo/apps/macos/Tools/update-key.swift" generate "$dir/sparkle-private.key" "$dir/sparkle-public.key"
echo "Created key files in $dir. Private key content is not printed."
echo 'Set GitHub secret SPARKLE_PRIVATE_ED_KEY from sparkle-private.key.'
echo 'Set GitHub variable SPARKLE_PUBLIC_ED_KEY from sparkle-public.key.'
