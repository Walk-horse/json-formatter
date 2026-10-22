#!/bin/bash
# 生成应用图标：PNG 母版 -> iconset -> icns
set -e
cd "$(dirname "$0")/.."

MASTER="assets/AppIcon.png"
ICONSET="build/AppIcon.iconset"
OUT="assets/AppIcon.icns"

# 1. 绘制 1024 母版（NSImage 会以 2x 输出 2048，随后统一缩放）
swift tools/make_icon.swift "$MASTER"

# 2. 组装 iconset（iconutil 要求的全部尺寸）
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

gen() { sips -Z "$2" "$MASTER" --out "$ICONSET/$3" >/dev/null; }

gen "$MASTER" 16   icon_16x16.png
gen "$MASTER" 32   icon_16x16@2x.png
gen "$MASTER" 32   icon_32x32.png
gen "$MASTER" 64   icon_32x32@2x.png
gen "$MASTER" 128  icon_128x128.png
gen "$MASTER" 256  icon_128x128@2x.png
gen "$MASTER" 256  icon_256x256.png
gen "$MASTER" 512  icon_256x256@2x.png
gen "$MASTER" 512  icon_512x512.png
gen "$MASTER" 1024 icon_512x512@2x.png

# 3. 打包成 icns
rm -f "$OUT"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "icon -> $OUT"
