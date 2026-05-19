#!/bin/bash
set -euo pipefail

# ============================================
# BodyMotion App — 真机构建 + 安装
# 前提: Xcode 已安装，iPhone USB 连接并解锁
# ============================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

# ── 允许覆盖设备名称/ID ─────────────
DEVICE_NAME="${1:-}"
DEVICE_ID=""

# ── 检测设备 ──────────────────────────
echo -e "${YELLOW}→${NC} 检测已连接的 iPhone..."

if [ -n "$DEVICE_NAME" ]; then
    echo -e "${GREEN}✓${NC} 使用指定设备: ${DEVICE_NAME}"
else
    # 通过 xcodebuild 获取可用设备列表
    cd "$SCRIPT_DIR"
    xcodegen generate --spec project.yml --quiet

    DEVICE_INFO=$(xcodebuild -project BodyMotionApp.xcodeproj \
        -scheme BodyMotionApp \
        -showdestinations 2>&1 | grep "platform:iOS" | grep -v "placeholder" | head -1)

    if [ -z "$DEVICE_INFO" ]; then
        echo -e "${RED}✗ 未检测到 iPhone。请确认：${NC}"
        echo "  1. USB 已连接"
        echo "  2. iPhone 已解锁（屏幕亮着）"
        echo "  3. 已点击"信任此电脑""
        echo ""
        echo "  或手动指定设备名:  ./install.sh C_C"
        exit 1
    fi

    # 提取设备名 (e.g. "name:C_C")
    DEVICE_NAME=$(echo "$DEVICE_INFO" | grep -oE 'name:[^,}]+' | cut -d: -f2)
    DEVICE_ID=$(echo "$DEVICE_INFO" | grep -oE 'id:[^,}]+' | cut -d: -f2)
    echo -e "${GREEN}✓${NC} 设备: ${DEVICE_NAME} (${DEVICE_ID})"
fi

# ── 构建目标 ──────────────────────────
DEST=""
if [ -n "$DEVICE_ID" ]; then
    DEST="id=${DEVICE_ID}"
elif [ -n "$DEVICE_NAME" ]; then
    DEST="name=${DEVICE_NAME}"
else
    echo -e "${RED}✗ 无法确定设备${NC}"
    exit 1
fi

# ── 构建 ──────────────────────────────
echo ""
echo -e "${YELLOW}→${NC} 编译中（首次可能较慢，约 2-5 分钟）..."

BUILD_LOG=$(mktemp)
xcodebuild \
    -project BodyMotionApp.xcodeproj \
    -scheme BodyMotionApp \
    -sdk iphoneos \
    -configuration Debug \
    -destination "$DEST" \
    -allowProvisioningUpdates \
    build 2>&1 | tee "$BUILD_LOG"

if ! grep -q "BUILD SUCCEEDED" "$BUILD_LOG"; then
    echo ""
    echo -e "${RED}✗ 构建失败，请检查上方日志${NC}"

    # 常见错误提示
    if grep -q "Signing for.*requires a development team" "$BUILD_LOG"; then
        echo -e "${YELLOW}提示: 需要在 project.yml 中设置 DEVELOPMENT_TEAM${NC}"
    elif grep -q "errSecInternalComponent" "$BUILD_LOG"; then
        echo -e "${YELLOW}提示: 可能是钥匙串锁定，请尝试先解锁:${NC}"
        echo "  security unlock-keychain ~/Library/Keychains/login.keychain-db"
    elif grep -q "device is locked" "$BUILD_LOG"; then
        echo -e "${YELLOW}提示: iPhone 处于锁屏状态，请解锁后再试${NC}"
    fi

    rm "$BUILD_LOG"
    exit 1
fi
rm "$BUILD_LOG"
echo -e "${GREEN}✓${NC} 编译完成"

# ── 查找 .app ─────────────────────────
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/BodyMotionApp-*/Build/Products/Debug-iphoneos \
    -name "BodyMotionApp.app" -type d 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo -e "${RED}✗ 找不到 .app 文件${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} App: ${APP_PATH}"

# ── 安装 ──────────────────────────────
echo ""
echo -e "${YELLOW}→${NC} 安装到 ${DEVICE_NAME}..."

# devicectl install 需要 CoreDevice identifier，不是 UDID
CORE_DEVICE_ID=$(xcrun devicectl list devices 2>&1 | grep "$DEVICE_NAME" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)

if [ -n "$CORE_DEVICE_ID" ]; then
    xcrun devicectl device install app --device "$CORE_DEVICE_ID" "$APP_PATH" 2>&1
else
    echo -e "${YELLOW}⚠ devicectl 未检测到设备，尝试通过 Xcode 安装${NC}"
    echo ""
    echo "  手动安装: 打开 Xcode → Window → Devices and Simulators"
    echo "  选择你的 iPhone → 拖入 ${APP_PATH}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  首次打开: iPhone → 设置 → 通用 → VPN与设备管理"
echo "  → 开发者 App → 点击信任 → 即可打开 📱"
