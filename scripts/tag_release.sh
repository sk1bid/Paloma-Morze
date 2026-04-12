#!/bin/bash

# Paloma Morse - Automated Tagging Script
# Automates version sync and git tagging for releases.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( dirname "$SCRIPT_DIR" )"
VERSION_FILE="$ROOT_DIR/VERSION"

# 1. Sync version first
bash "$SCRIPT_DIR/update_version.sh"
if [ $? -ne 0 ]; then
    echo "Aborting due to sync error."
    exit 1
fi

VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
TAG_NAME="v$VERSION"

# 2. Check git state
if [ -n "$(git status --porcelain)" ]; then
    echo "Warning: Working directory is not clean. Committing version changes..."
    git add "$VERSION_FILE" "$ROOT_DIR/ui/package.json"
    git commit -m "chore: sync version to $VERSION"
fi

# 3. Create tag
if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
    echo "Error: Tag $TAG_NAME already exists."
    exit 1
fi

echo "Creating tag $TAG_NAME..."
git tag -a "$TAG_NAME" -m "Release $VERSION"

echo "------------------------------------------------"
echo "Tag $TAG_NAME created successfully!"
echo "To trigger the CI/CD release, run:"
echo "git push origin main --tags"
echo "------------------------------------------------"
