#!/bin/bash
set -euo pipefail

# ============================================
# collection_app — CLI build
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_FILE="$PROJECT_DIR/collection_app.xcodeproj"
SCHEME="collection_app"
BUILD_DIR="$PROJECT_DIR/build"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  collection_app — CLI Build${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ── 1. Check Xcode ──────────────────────
if ! xcode-select -p &>/dev/null; then
    echo -e "${RED}✗ Xcode not found.${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Xcode: $(xcodebuild -version | head -1)"

# ── 2. Generate project ─────────────────
echo -e "${YELLOW}→${NC} Generating Xcode project..."
xcodegen generate --spec "$PROJECT_DIR/project.yml" --quiet
echo -e "${GREEN}✓${NC} Project generated"

# ── 3. Detect signing team ───────────────
TEAM_ID="${DEVELOPMENT_TEAM:-ZWG49Y3378}"
MODE="${1:-device}"

if [ "$MODE" = "--simulator" ] || [ "$MODE" = "-s" ]; then
    SIMULATOR_ONLY=true
else
    SIMULATOR_ONLY=false
fi

# ── 4. Build ─────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

if [ "$SIMULATOR_ONLY" = true ]; then
    echo ""
    echo -e "${YELLOW}→${NC} Building for iOS Simulator (no signing needed)..."
    xcodebuild \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -sdk iphonesimulator \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        build \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO

    APP_PATH=$(find "$BUILD_DIR/DerivedData/Build/Products" -name "*.app" -type d | head -1)
    echo ""
    echo -e "${GREEN}✓ Build complete${NC}"
    echo "  App bundle: $APP_PATH"
    echo "  Run on simulator: xcrun simctl install booted '$APP_PATH'"
else
    echo ""
    echo -e "${YELLOW}→${NC} Building for device (team: ${TEAM_ID})..."

    ARCHIVE_PATH="$BUILD_DIR/collection_app.xcarchive"
    IPA_DIR="$BUILD_DIR/ipa"

    xcodebuild \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -sdk iphoneos \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        archive \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        -allowProvisioningUpdates

    echo -e "${GREEN}✓${NC} Archive created: $ARCHIVE_PATH"

    # Export .ipa
    echo ""
    echo -e "${YELLOW}→${NC} Exporting .ipa..."

    xcodebuild \
        -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$IPA_DIR" \
        -exportOptionsPlist <(cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>teamID</key>
    <string>ZWG49Y3378</string>
</dict>
</plist>
PLIST
        ) \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        -allowProvisioningUpdates

    IPA_PATH=$(find "$IPA_DIR" -name "*.ipa" -type f | head -1)
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Build Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "  IPA: $IPA_PATH"
    echo "  Size: $(du -sh "$IPA_PATH" | cut -f1)"
fi
