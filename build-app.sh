#!/bin/bash
# 把 SPM 构建产物打成 macOS .app bundle（含 AppIcon + Info.plist）
# 用法: ./build-app.sh   生成的 CacheCleaner.app 在当前目录
set -e

APP_NAME="CacheCleaner"
BUNDLE_ID="com.guofengrui.cachecleaner"
VERSION="1.0"
BUILD_DIR=".build/release"
APP_DIR="$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
ICON_PNG="Resources/AppIcon.png"

echo "→ swift build -c release"
swift build --disable-sandbox -c release

echo "→ 准备图标"
mkdir -p Resources
if [ ! -f "$ICON_PNG" ]; then
    # 默认生成「垃圾桶·蓝」图标（与正式图标一致）
    swift build-icon-variants.swift trash "$ICON_PNG"
    sips -z 1024 1024 "$ICON_PNG" --out /tmp/appicon-1024.png > /dev/null
    mv /tmp/appicon-1024.png "$ICON_PNG"
fi

echo "→ 构建 .app bundle"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BUILD_DIR/$APP_NAME" "$CONTENTS/MacOS/"

# 把语言资源（zh-Hans.lproj / en.lproj）从 SPM bundle 复制进 .app bundle
# SPM 把 resources 规范化放在 .build/release/<Module>_<Target>.bundle/，目录名小写
SPM_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"
for LOC in zh-hans en; do
    if [ -d "$SPM_BUNDLE/$LOC.lproj" ]; then
        cp -R "$SPM_BUNDLE/$LOC.lproj" "$CONTENTS/Resources/"
    fi
done

# 生成多尺寸 PNG + .icns
ICONSET="$CONTENTS/Resources/AppIcon.iconset"
mkdir -p "$ICONSET"
sips -z 16 16    "$ICON_PNG" --out "$ICONSET/icon_16x16.png"       > /dev/null
sips -z 32 32    "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png"    > /dev/null
sips -z 32 32    "$ICON_PNG" --out "$ICONSET/icon_32x32.png"       > /dev/null
sips -z 64 64    "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png"    > /dev/null
sips -z 128 128  "$ICON_PNG" --out "$ICONSET/icon_128x128.png"     > /dev/null
sips -z 256 256  "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png"  > /dev/null
sips -z 256 256  "$ICON_PNG" --out "$ICONSET/icon_256x256.png"     > /dev/null
sips -z 512 512  "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png"  > /dev/null
sips -z 512 512  "$ICON_PNG" --out "$ICONSET/icon_512x512.png"     > /dev/null
cp "$ICON_PNG" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Info.plist
cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key>
  <true/>
  <key>NSSupportsSuddenTermination</key>
  <true/>
</dict>
</plist>
EOF

echo ""
echo "✓ 生成 $APP_DIR"
echo "  → open $APP_DIR                # 启动"
echo "  → 替换图标: cp your-1024.png Resources/AppIcon.png && ./build-app.sh"