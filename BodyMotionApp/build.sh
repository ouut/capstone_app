#!/bin/bash
set -euo pipefail

# ============================================
# BodyMotion App — CLI build (no Xcode GUI)
# Prerequisites: Xcode installed + Apple ID
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
PROJECT_FILE="$PROJECT_DIR/BodyMotionApp.xcodeproj"
SCHEME="BodyMotionApp"
ARCHIVE_PATH="$BUILD_DIR/BodyMotionApp.xcarchive"
IPA_DIR="$BUILD_DIR/ipa"
EXPORT_PLIST="$PROJECT_DIR/exportOptions.plist"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  BodyMotion App — CLI Build${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ── 1. Check Xcode ──────────────────────
if ! xcode-select -p &>/dev/null; then
    echo -e "${RED}✗ Xcode not found. Install from Mac App Store first.${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Xcode: $(xcodebuild -version | head -1)"

# ── 2. Check / install xcodegen ──────────
if ! command -v xcodegen &>/dev/null; then
    echo -e "${YELLOW}! xcodegen not found, installing via Homebrew...${NC}"
    if ! command -v brew &>/dev/null; then
        echo -e "${RED}✗ Homebrew not found. Install it first:${NC}"
        echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
    brew install xcodegen
fi
echo -e "${GREEN}✓${NC} xcodegen: $(xcodegen --version)"

# ── 3. Generate .xcodeproj ───────────────
echo ""
echo -e "${YELLOW}→${NC} Generating Xcode project from project.yml..."
cd "$PROJECT_DIR"
xcodegen generate --spec project.yml --quiet
echo -e "${GREEN}✓${NC} Project generated: $PROJECT_FILE"

# ── 4. Detect signing team ───────────────
TEAM_ID=""
if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
    TEAM_ID="$DEVELOPMENT_TEAM"
else
    # Try to auto-detect from existing profiles
    TEAM_ID=$(security find-identity -v -p codesigning 2>/dev/null | \
              grep -oE '\([A-Z0-9]{10}\)' | head -1 | tr -d '()' || echo "")
    if [ -z "$TEAM_ID" ]; then
        echo ""
        echo -e "${YELLOW}⚠ No signing team found.${NC}"
        echo "  Option A: Set your Team ID:  DEVELOPMENT_TEAM=XXXXXXXXXX ./build.sh"
        echo "  Option B: Run 'xcodebuild' interactively once to create a profile."
        echo "  Option C: Build for simulator only:  ./build.sh --simulator"
        echo ""
        echo -e "${YELLOW}→${NC} Trying simulator build..."
        SIMULATOR_ONLY=true
    fi
fi

# ── 5. Build ─────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

if [ "${SIMULATOR_ONLY:-false}" = true ]; then
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
    echo "  Run on simulator:  xcrun simctl boot 'iPhone 15' && open -a Simulator"
    echo "  Install on simulator: xcrun simctl install booted '$APP_PATH'"
else
    echo ""
    echo -e "${YELLOW}→${NC} Building archive (team: ${TEAM_ID})..."

    # Update project with team ID
    if [ -n "$TEAM_ID" ]; then
        /usr/libexec/PlistBuddy -c "Set :teamID $TEAM_ID" "$EXPORT_PLIST" 2>/dev/null || true
    fi

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

    # ── 6. Export .ipa ────────────────────
    echo ""
    echo -e "${YELLOW}→${NC} Exporting .ipa..."

    xcodebuild \
        -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$IPA_DIR" \
        -exportOptionsPlist "$EXPORT_PLIST" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        -allowProvisioningUpdates

    IPA_PATH=$(find "$IPA_DIR" -name "*.ipa" -type f | head -1)
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Build Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "  IPA: $IPA_PATH"
    echo "  Size: $(du -sh "$IPA_PATH" | cut -f1)"
    echo ""
    echo "  Install on device:"
    echo "    - Use Apple Configurator (free)"
    echo "    - Or: xcrun devicectl device install app --device <UDID> '$IPA_PATH'"
    echo ""
fi
