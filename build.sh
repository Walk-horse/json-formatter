#!/bin/bash
set -e
cd "$(dirname "$0")"

APP_NAME="JSON格式化工具"
BUNDLE="build/${APP_NAME}.app"
BIN=".build/release/JSONFormatter"

echo "==> 编译 (release)"
# --disable-sandbox：部分环境下 SPM 的沙箱无法 apply（sandbox_apply: Operation not permitted）
swift build -c release --disable-sandbox

echo "==> 打包 ${BUNDLE}"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/JSONFormatter"

# 应用图标（缺失时自动生成）
if [ ! -f "assets/AppIcon.icns" ]; then
    ./tools/make_icns.sh
fi
cp "assets/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>JSONFormatter</string>
    <key>CFBundleIdentifier</key>
    <string>com.ht.jsonformatter</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>JSON格式化工具</string>
    <key>CFBundleDisplayName</key>
    <string>JSON格式化工具</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>JSON</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.json</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$BUNDLE" >/dev/null 2>&1 || true

echo "==> 完成: $BUNDLE"

if [ "$1" = "run" ]; then
    pkill -f "JSON格式化工具.app/Contents/MacOS/JSONFormatter" >/dev/null 2>&1 || true
    open "$BUNDLE"
fi
