#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."
version="$(tr -d '[:space:]' < VERSION)"
tag="v$version"
bash "$SCRIPT_DIR/update_version.sh"
# Never silently commit an incomplete feature or publish every historical tag.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo 'Commit the reviewed changes and version files before tagging.' >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "Tag $tag already exists." >&2
  exit 1
fi
git tag -a "$tag" -m "Release $version"
printf 'Created %s. After CI passes, publish this tag with: git push origin %s\n' "$tag" "$tag"
