#!/bin/bash
# 把上游奶蛙做成 macOS 用的 arm64 Windows 程序（去掉联机）
# 用法：./scripts/build-arm64.sh <上游应用目录> [输出 exe]
#   <上游应用目录> 是含 source/ 和 third_party/ 的那一层，
#   也就是上游仓库的 Source/NaiWaChatPet
set -euo pipefail
UPSTREAM="${1:?用法: build-arm64.sh <上游应用目录> [输出 exe]}"
OUT="${2:-$HOME/Projects/NaiWaChatPet/Source/NaiWaChatPet/NaiWaChatPet.exe}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -d "$UPSTREAM/source" ] || { echo "找不到 $UPSTREAM/source（要传 Source/NaiWaChatPet 这一层）"; exit 1; }
mkdir -p "$WORK/app"
cp -R "$UPSTREAM/." "$WORK/app/"
cd "$WORK/app/source"
patch -p1 --no-backup-if-mismatch < "$HERE/patches/naiwa-arm64-no-online.patch"
# patch 删除文件时会把目标留成 0 字节，这里真正删掉
find . -type f -name '*.go' -size 0 -delete
find . -type d -empty -delete

GOOS=windows GOARCH=arm64 go build -trimpath -ldflags '-s -w -H windowsgui' \
    -o "$OUT" ./cmd/codexpet
ls -l "$OUT"
file "$OUT"
echo "完成：$OUT"
