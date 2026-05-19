#!/bin/bash
set -euo pipefail

# ============================================
# game_client_app — 命令行构建 + 安装到设备
# ============================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

PROJECT_FILE="$SCRIPT_DIR/game_client_app.xcodeproj"
SCHEME="game_client_app"
TEAM_ID="${DEVELOPMENT_TEAM:-ZWG49Y3378}"
DEVICE_NAME="${1:-}"

# ── 检测设备 ──────────────────────────
echo -e "${YELLOW}→${NC} 检测已连接的 iPhone..."

if [ -n "$DEVICE_NAME" ]; then
    echo -e "${GREEN}✓${NC} 使用指定设备: ${DEVICE_NAME}"
else
    DEVICE_INFO=$(xcodebuild -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -showdestinations 2>&1 | grep "platform:iOS" | grep -v "placeholder" | head -1)

    if [ -z "$DEVICE_INFO" ]; then
        echo -e "${RED}✗ 未检测到 iPhone。请确认：${NC}"
        echo "  1. USB 已连接"
        echo "  2. iPhone 已解锁"
        echo "  3. 已点击"信任此电脑""
        echo ""
        echo "  或手动指定设备:  ./install.sh '设备名'"
        exit 1
    fi

    DEVICE_NAME=$(echo "$DEVICE_INFO" | grep -oE 'name:[^,}]+' | cut -d: -f2)
    DEVICE_ID=$(echo "$DEVICE_INFO" | grep -oE 'id:[^,}]+' | cut -d: -f2)
    echo -e "${GREEN}✓${NC} 设备: ${DEVICE_NAME} (${DEVICE_ID})"
fi

# ── 构建目标 ──────────────────────────
if [ -n "${DEVICE_ID:-}" ]; then
    DEST="id=${DEVICE_ID}"
elif [ -n "$DEVICE_NAME" ]; then
    DEST="name=${DEVICE_NAME}"
else
    echo -e "${RED}✗ 无法确定设备${NC}"
    exit 1
fi

# ── 构建 ──────────────────────────────
echo ""
echo -e "${YELLOW}→${NC} 编译中（首次较慢，约 2-5 分钟）..."

BUILD_LOG=$(mktemp)
xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -sdk iphoneos \
    -configuration Debug \
    -destination "$DEST" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    -allowProvisioningUpdates \
    build 2>&1 | tee "$BUILD_LOG"

if ! grep -q "BUILD SUCCEEDED" "$BUILD_LOG"; then
    echo ""
    echo -e "${RED}✗ 构建失败${NC}"

    if grep -q "errSecInternalComponent" "$BUILD_LOG"; then
        echo -e "${YELLOW}签名失败。尝试解锁钥匙串或重启 Mac。${NC}"
    elif grep -q "No Accounts" "$BUILD_LOG"; then
        echo -e "${YELLOW}Xcode 未登录 Apple ID。${NC}"
    elif grep -q "device is locked" "$BUILD_LOG"; then
        echo -e "${YELLOW}iPhone 处于锁屏状态，请解锁后再试${NC}"
    fi

    rm "$BUILD_LOG"
    exit 1
fi
rm "$BUILD_LOG"
echo -e "${GREEN}✓${NC} 编译完成"

# ── 查找 .app ─────────────────────────
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/game_client_app-*/Build/Products/Debug-iphoneos \
    -name "game_client_app.app" -type d 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo -e "${RED}✗ 找不到 .app 文件${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} App: ${APP_PATH}"

# ── 安装到设备 ───────────────────────
echo ""
echo -e "${YELLOW}→${NC} 安装到 ${DEVICE_NAME}..."

if command -v ios-deploy &>/dev/null; then
    if ios-deploy --bundle "$APP_PATH" 2>&1; then
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}  安装完成！${NC}"
        echo -e "${GREEN}========================================${NC}"
        exit 0
    fi
    echo -e "${YELLOW}⚠ ios-deploy 失败，尝试 devicectl...${NC}"
fi

CORE_DEVICE_ID=$(xcrun devicectl list devices 2>&1 | grep "$DEVICE_NAME" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)

if [ -n "$CORE_DEVICE_ID" ]; then
    xcrun devicectl device install app --device "$CORE_DEVICE_ID" "$APP_PATH" 2>&1
else
    echo -e "${RED}✗ 无法自动安装。${NC}"
    echo "  手动: Xcode → Devices → 拖入 ${APP_PATH}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  首次打开需信任: 设置 → 通用 → VPN与设备管理 → 信任"
