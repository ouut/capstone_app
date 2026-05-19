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

# ── 检测设备 ──────────────────────────
echo -e "${YELLOW}→${NC} 检测已连接的 iPhone..."
DEVICE_INFO=$(xcrun devicectl list devices 2>&1)
DEVICE_ID=$(echo "$DEVICE_INFO" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)
DEVICE_NAME=$(echo "$DEVICE_INFO" | grep "$DEVICE_ID" | awk '{print $1}')

if [ -z "$DEVICE_ID" ]; then
    echo -e "${RED}✗ 未检测到 iPhone。请确认：${NC}"
    echo "  1. USB 已连接"
    echo "  2. iPhone 已解锁（屏幕亮着）"
    echo "  3. 已点击"信任此电脑""
    exit 1
fi
echo -e "${GREEN}✓${NC} 设备: ${DEVICE_NAME} (${DEVICE_ID})"

# ── 生成项目 ──────────────────────────
echo ""
echo -e "${YELLOW}→${NC} 生成 Xcode 项目..."
cd "$SCRIPT_DIR"
xcodegen generate --spec project.yml --quiet
echo -e "${GREEN}✓${NC} 项目已生成"

# ── 构建 ──────────────────────────────
echo ""
echo -e "${YELLOW}→${NC} 编译中（首次可能较慢，约 2-5 分钟）..."

BUILD_LOG=$(mktemp)
xcodebuild \
    -project BodyMotionApp.xcodeproj \
    -scheme BodyMotionApp \
    -sdk iphoneos \
    -configuration Debug \
    -destination "id=${DEVICE_ID}" \
    -allowProvisioningUpdates \
    build 2>&1 | tee "$BUILD_LOG"

if ! grep -q "BUILD SUCCEEDED" "$BUILD_LOG"; then
    echo ""
    echo -e "${RED}✗ 构建失败，请检查上方日志${NC}"
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

xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" 2>&1

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  首次打开: iPhone → 设置 → 通用 → VPN与设备管理"
echo "  → 开发者 App → 点击信任"
echo ""
echo "  然后就可以打开了 📱"
