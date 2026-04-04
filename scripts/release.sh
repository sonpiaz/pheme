#!/bin/bash
set -euo pipefail

# Build & package Pheme.app into a DMG for Homebrew cask distribution.
# Usage: ./scripts/release.sh [version]
# Example: ./scripts/release.sh 0.1.0

VERSION="${1:-$(grep 'MARKETING_VERSION' project.yml | head -1 | sed 's/.*"\(.*\)"/\1/')}"
APP_NAME="Pheme"
BUILD_DIR="build/Release"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="build/${DMG_NAME}"

echo "==> Building ${APP_NAME} v${VERSION}..."

# Generate Xcode project
xcodegen generate

# Build release
xcodebuild -project Pheme.xcodeproj \
  -scheme Pheme \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  SYMROOT="$(pwd)/build" \
  build

# Verify .app exists
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: ${APP_PATH} not found"
  exit 1
fi

# Create DMG
echo "==> Creating DMG..."
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO \
  "$DMG_PATH"

# Compute SHA256
SHA=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo ""
echo "==> ${DMG_NAME} created successfully"
echo "    SHA256: ${SHA}"
echo ""
echo "==> Next steps:"
echo "    1. Create GitHub release: gh release create v${VERSION} ${DMG_PATH} --title 'v${VERSION}'"
echo "    2. Update homebrew-tap/Casks/pheme.rb:"
echo "       - version \"${VERSION}\""
echo "       - sha256 \"${SHA}\""
echo "    3. Push homebrew-tap repo"
