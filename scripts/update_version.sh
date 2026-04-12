#!/bin/bash

# Simple script to sync version from root /VERSION to ui/package.json
# Usage: ./scripts/update_version.sh

# Get directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( dirname "$SCRIPT_DIR" )"
VERSION_FILE="$ROOT_DIR/VERSION"
PACKAGE_JSON="$ROOT_DIR/ui/package.json"

if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: VERSION file not found at $VERSION_FILE"
    exit 1
fi

# Read version, stripping any whitespace
VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')

# Validate version format (e.g. 0.1.2 or 1.2.3-beta.1)
if [[ ! $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo "Error: Invalid version format in VERSION file: '$VERSION'"
    echo "Expected format: X.Y.Z (e.g. 1.0.0)"
    exit 1
fi

echo "Syncing version $VERSION to $PACKAGE_JSON..."

# Use sed to update the version field in package.json
# Optimized for macOS (requires empty string for -i)
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/\"version\": \".*\"/\"version\": \"$VERSION\"/" "$PACKAGE_JSON"
else
    sed -i "s/\"version\": \".*\"/\"version\": \"$VERSION\"/" "$PACKAGE_JSON"
fi

echo "Successfully synced to $VERSION"
