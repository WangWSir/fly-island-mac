#!/bin/bash
# 构建 Fly Island for Mac
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/FlyIsland.app"
MEDIA="$APP/Contents/Resources/media"

echo "▸ 清理"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$MEDIA"

echo "▸ 编译 MediaRemote 适配库"
clang -dynamiclib -fobjc-arc -O2 \
  -mmacosx-version-min=14.0 \
  -framework Foundation -framework CoreFoundation \
  -o "$MEDIA/libislandmedia.dylib" \
  "$ROOT/Native/island_media.m"

echo "▸ 拷贝适配脚本"
cp "$ROOT/Resources/media/mediaremote.pl" "$MEDIA/mediaremote.pl"
chmod +x "$MEDIA/mediaremote.pl"

echo "▸ 拷贝图标"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▸ 编译 Swift"
SOURCES=$(find "$ROOT/Sources" -name '*.swift' | sort | tr '\n' ' ')
ARCH="$(uname -m)"
swiftc -swift-version 5 -O -whole-module-optimization \
  -disable-sandbox \
  -target "${ARCH}-apple-macosx14.0" \
  -framework AppKit -framework SwiftUI -lsqlite3 \
  -o "$APP/Contents/MacOS/FlyIsland" \
  $SOURCES

echo "▸ 写入 Info.plist"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

echo "▸ 签名"
SIGN_ID="FlyIsland Development"
if security find-identity -p codesigning -v 2>/dev/null | grep -q "$SIGN_ID"; then
  # 自签名证书：指定要求绑定 bundle id + 证书根，重编译后 TCC 授权不会失效
  codesign --force --deep --sign "$SIGN_ID" --identifier com.flyisland.mac "$APP" >/dev/null
  echo "  identity: $SIGN_ID"
else
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  echo "  identity: ad-hoc（未找到自签名证书，可运行 Tools/make_signing_cert.sh 生成）"
fi

echo "✓ 构建完成：$APP"
