#!/bin/bash
# 生成并安装 FlyIsland 本地自签名代码签名证书。
# 目的：签名身份固定后，重编译不会导致 TCC（完全磁盘访问/辅助功能）授权失效。
set -euo pipefail

CN="FlyIsland Development"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORK="$(cd "$(dirname "$0")/.." && pwd)/build/codesign"
mkdir -p "$WORK"
cd "$WORK"

if security find-identity -p codesigning -v | grep -q "$CN"; then
  echo "✓ 已存在签名身份：$CN"
  exit 0
fi

echo "▸ 生成自签名证书（含 codeSigning 用途）"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout flyisland.key -out flyisland.crt \
  -subj "/CN=$CN/O=FlyIsland/C=CN" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

echo "▸ 打包 p12 并导入钥匙串"
PASS="flyisland"
openssl pkcs12 -export -legacy -inkey flyisland.key -in flyisland.crt \
  -out flyisland.p12 -passout "pass:$PASS" 2>/dev/null
security import flyisland.p12 -k "$KEYCHAIN" -P "$PASS" \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "▸ 标记为受信任的代码签名证书"
# 用户域信任，供 codesign --verify / Gatekeeper 校验链
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" flyisland.crt >/dev/null 2>&1 || \
  echo "  (信任设置被跳过，签名仍可用，必要时在 钥匙串访问 → 证书 → 显示简介 → 信任 里手动设为「始终信任」)"

echo "▸ 允许 codesign 免交互使用私钥"
security set-key-partition-list -S apple-tool:,apple: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || \
  echo "  (首次签名时系统可能弹窗询问密钥访问，点「始终允许」即可)"

echo
security find-identity -p codesigning -v | tail -3
