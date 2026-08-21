#!/bin/bash
# 把 CacheCleaner.app 打成 .dmg 安装包，含背景图、图标布局
# 用法: ./make-dmg.sh   输出 CacheCleaner-<version>.dmg
set -e

cd "$(dirname "$0")"

APP_NAME="CacheCleaner"
VERSION="1.0"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
APP_DIR="${APP_NAME}.app"
DMG_STAGING="dmg-staging"
BG_PNG="Resources/dmg-background.png"
APP_ICON="Resources/AppIcon.png"

# 1. 先确保 .app 存在
if [ ! -d "$APP_DIR" ]; then
    echo "→ $APP_DIR 不存在，先构建"
    ./build-app.sh
fi

# 2. 生成 dmg 背景图
if [ ! -f "$BG_PNG" ]; then
    echo "→ 生成 dmg 安装背景图"
    swift build-dmg-background.swift "$BG_PNG" "$APP_ICON"
fi

# 3. 准备 staging 目录（.app + Applications 别名 + 背景图）
echo "→ 准备 staging 目录"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING/.background"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
# 背景图提前放入 staging（attach 失败时 dmg 里也带背景图，Finder 仍会显示）
cp "$BG_PNG" "$DMG_STAGING/.background/background.png"

# 4. 生成临时 dmg 并设置 Finder 窗口布局
echo "→ 生成临时 dmg 设置布局"
TEMP_DMG="temp-${DMG_NAME}"
rm -f "$TEMP_DMG"
hdiutil create -ov -format UDZO -srcfolder "$DMG_STAGING" \
    -volname "$APP_NAME" -fs HFS+ \
    "$TEMP_DMG" > /dev/null

# 用 AppleScript 设置 Finder 窗口：背景图 + 图标位置 + 图标视图
# 这一步若失败也不阻塞 dmg 生成（窗口会按默认布局打开）
DEVICE=$(hdiutil attach -readwrite -noverify "$TEMP_DMG" | grep -o '/dev/disk[0-9]*' | head -1)
if [ -n "$DEVICE" ]; then
    MOUNT_POINT=$(mount | grep "$DEVICE " | awk '{print $3}')
    if [ -n "$MOUNT_POINT" ]; then
        echo "→ 设置 Finder 窗口布局"
        # 背景图已随 staging 进入卷内（.background 是 Finder 约定的隐藏目录），
        # 这里只负责用 AppleScript 设置窗口位置与视图样式
        osascript <<EOF || true
        tell application "Finder"
            tell disk "$APP_NAME"
                open
                delay 1
                set current view of container window to icon view
                set toolbar visible of container window to false
                set statusbar visible of container window to false
                set the bounds of container window to {200, 120, 860, 560}
                set background picture of icon view options of container window to file ".background:background.png"
                set arrangement of icon view options of container window to not arranged
                set icon size of icon view options of container window to 110
                set position of item "$APP_NAME.app" of container window to {160, 220}
                set position of item "Applications" of container window to {500, 220}
                update without registering applications
                delay 1
                close
            end tell
        end tell
EOF

        # 卸载 dmg（.DS_Store 已保存）
        hdiutil detach "$DEVICE" > /dev/null
    fi
fi

# 5. 转为压缩的最终 dmg
echo "→ 压缩为最终 dmg"
rm -f "$DMG_NAME"
hdiutil convert "$TEMP_DMG" -format UDZO -o "$DMG_NAME" > /dev/null
rm -f "$TEMP_DMG"

# 6. 清理 staging
rm -rf "$DMG_STAGING"

DMG_SIZE=$(du -h "$DMG_NAME" | awk '{print $1}')
echo ""
echo "✓ 生成 $DMG_NAME ($DMG_SIZE)"
echo "  → open $DMG_NAME     # 打开查看"
echo "  → 安装：把 CacheCleaner.app 拖到 Applications"