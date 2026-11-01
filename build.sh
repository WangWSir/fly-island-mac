#!/bin/bash
# 构建 Fly Island for Mac
#
#   ./build.sh                      本地构建（arm64/当前架构，自签名证书优先）
#   UNIVERSAL=1 ./build.sh          通用二进制（arm64 + x86_64），发布用
#   SIGN_ID=- ./build.sh            ad-hoc 签名（分发用，不依赖本机证书）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/FlyIsland.app"
MEDIA="$APP/Contents/Resources/media"
TMP="$ROOT/build/.obj"
UNIVERSAL="${UNIVERSAL:-0}"

echo "▸ 清理"
rm -rf "$APP" "$TMP"
mkdir -p "$APP/Contents/MacOS" "$MEDIA" "$TMP"

if [ "$UNIVERSAL" = "1" ]; then
  echo "▸ 编译 MediaRemote 适配库（arm64 + x86_64）"
  clang -dynamiclib -fobjc-arc -O2 -arch arm64 -arch x86_64 \
    -mmacosx-version-min=14.0 \
    -framework Foundation -framework CoreFoundation \
    -o "$MEDIA/libislandmedia.dylib" \
    "$ROOT/Native/island_media.m"
else
  echo "▸ 编译 MediaRemote 适配库"
  clang -dynamiclib -fobjc-arc -O2 \
    -mmacosx-version-min=14.0 \
    -framework Foundation -framework CoreFoundation \
    -o "$MEDIA/libislandmedia.dylib" \
    "$ROOT/Native/island_media.m"
fi

echo "▸ 拷贝适配脚本"
cp "$ROOT/Resources/media/mediaremote.pl" "$MEDIA/mediaremote.pl"
chmod +x "$MEDIA/mediaremote.pl"

echo "▸ 拷贝图标"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▸ 编译 Swift"
SOURCES=$(find "$ROOT/Sources" -name '*.swift' | sort | tr '\n' ' ')

build_swift() { # $1=arch  $2=输出文件
  swiftc -swift-version 5 -O -whole-module-optimization \
    -disable-sandbox \
    -target "$1-apple-macosx14.0" \
    -framework AppKit -framework SwiftUI -lsqlite3 \
    -o "$2" \
    $SOURCES
}

if [ "$UNIVERSAL" = "1" ]; then
  build_swift arm64 "$TMP/FlyIsland-arm64"
  build_swift x86_64 "$TMP/FlyIsland-x86_64"
  lipo -create "$TMP/FlyIsland-arm64" "$TMP/FlyIsland-x86_64" \
    -output "$APP/Contents/MacOS/FlyIsland"
else
  build_swift "$(uname -m)" "$APP/Contents/MacOS/FlyIsland"
fi

echo "▸ 写入 Info.plist"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

echo "▸ 签名"
# 默认用本机自签名证书（重编译后 TCC 授权不失效）；SIGN_ID=- 表示 ad-hoc
SIGN_ID="${SIGN_ID:-FlyIsland Development}"
if [ "$SIGN_ID" = "-" ]; then
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  echo "  identity: ad-hoc"
  # ad-hoc 签名的二进制改了内容，顺手清掉扩展属性免得影响校验
  xattr -cr "$APP" 2>/dev/null || true
elif security find-identity -p codesigning -v 2>/dev/null | grep -q "$SIGN_ID"; then
  # 自签名证书：指定要求绑定 bundle id + 证书根，重编译后 TCC 授权不会失效
  codesign --force --deep --sign "$SIGN_ID" --identifier com.flyisland.mac "$APP" >/dev/null
  echo "  identity: $SIGN_ID"
else
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  echo "  identity: ad-hoc（未找到自签名证书，可运行 Tools/make_signing_cert.sh 生成）"
fi

echo "✓ 构建完成：$APP"
