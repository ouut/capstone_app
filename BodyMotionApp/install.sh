#!/bin/bash
set -euo pipefail

# ============================================
# BodyMotion App — 命令行构建 + 安装
# 前提: Xcode 已安装（无需打开 GUI），iPhone USB 连接并解锁
# 工具: xcodebuild + ios-deploy
# ============================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

DEVICE_NAME="${1:-}"
DEVICE_ID=""

# ── 解锁钥匙串 ──────────────────────────
echo -e "${YELLOW}→${NC} 检查钥匙串..."
if security show-keychain-info ~/Library/Keychains/login.keychain-db 2>&1 | grep -q "locked"; then
    echo -e "${YELLOW}⚠ 钥匙串已锁定，请输入 Mac 登录密码解锁：${NC}"
    security unlock-keychain ~/Library/Keychains/login.keychain-db 2>/dev/null || {
        echo -e "${RED}✗ 解锁失败，请手动运行: security unlock-keychain ~/Library/Keychains/login.keychain-db${NC}"
        exit 1
    }
fi

# ── 检测设备 ──────────────────────────
echo -e "${YELLOW}→${NC} 检测已连接的 iPhone..."

cd "$SCRIPT_DIR"
xcodegen generate --spec project.yml --quiet 2>/dev/null

if [ -n "$DEVICE_NAME" ]; then
    echo -e "${GREEN}✓${NC} 使用指定设备: ${DEVICE_NAME}"
else
    DEVICE_INFO=$(xcodebuild -project BodyMotionApp.xcodeproj \
        -scheme BodyMotionApp \
        -showdestinations 2>&1 | grep "platform:iOS" | grep -v "placeholder" | head -1)

    if [ -z "$DEVICE_INFO" ]; then
        echo -e "${RED}✗ 未检测到 iPhone。请确认：${NC}"
        echo "  1. USB 已连接"
        echo "  2. iPhone 已解锁（屏幕亮着）"
        echo "  3. 已点击"信任此电脑""
        echo ""
        echo "  或手动指定设备:  ./install.sh 'C_C'"
        exit 1
    fi

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
echo -e "${YELLOW}→${NC} 编译中（首次较慢，约 2-5 分钟）..."

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
    echo -e "${RED}✗ 构建失败${NC}"

    # 常见错误提示
    if grep -q "errSecInternalComponent" "$BUILD_LOG"; then
        echo ""
        echo -e "${YELLOW}签名失败（errSecInternalComponent）。尝试：${NC}"
        echo "  1. 打开钥匙串访问 → 登录 → 锁定再解锁"
        echo "  2. 或重启 Mac"
        echo "  3. Xcode → Settings → Accounts → 重新登录 Apple ID"
    elif grep -q "No Accounts" "$BUILD_LOG"; then
        echo ""
        echo -e "${YELLOW}Xcode 未登录 Apple ID。请打开一次 Xcode：${NC}"
        echo "  Xcode → Settings → Accounts → 添加你的 Apple ID"
        echo "  （之后不再需要打开 Xcode）"
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

# ── 安装到设备（优先 ios-deploy，回退 devicectl）─
echo ""
echo -e "${YELLOW}→${NC} 安装到 ${DEVICE_NAME}..."

if command -v ios-deploy &>/dev/null; then
    # ios-deploy: 直接安装，无需额外配置
    if ios-deploy --bundle "$APP_PATH" 2>&1; then
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}  安装完成！（ios-deploy）${NC}"
        echo -e "${GREEN}========================================${NC}"
        exit 0
    fi
    echo -e "${YELLOW}⚠ ios-deploy 失败，尝试 devicectl...${NC}"
fi

# 回退: devicectl (Xcode 15+)
CORE_DEVICE_ID=$(xcrun devicectl list devices 2>&1 | grep "$DEVICE_NAME" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)

if [ -n "$CORE_DEVICE_ID" ]; then
    xcrun devicectl device install app --device "$CORE_DEVICE_ID" "$APP_PATH" 2>&1
else
    echo -e "${RED}✗ 无法安装。手动方式：${NC}"
    echo "  打开 Xcode → Window → Devices and Simulators"
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
echo ""
echo "  以后只需:  ./install.sh"
