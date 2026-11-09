#!/bin/bash
# 下载 MetalSharp Wine 6.0 的 arm64 版本（GitHub 单连接限速，这里并发分段）
# 用法：./scripts/fetch-wine.sh [目标目录]
#   GitHub 单连接约 200 KB/s，8 段并发能到 2-10 MB/s
set -euo pipefail
DEST="${1:-$HOME/Projects/NaiWaChatPet/wine-arm64}"
ASSET_ID=722809637                     # metalsharp-wine-6.0-arm64.tar.xz
TOTAL=962820908
SHA=a728f41ef4cd600ea45bbc1e1fd9bb35fb1a0fa4327ca0cfad311738f93160a6
URL="https://api.github.com/repos/metalsharp/MetalSharp-Wine/releases/assets/$ASSET_ID"
NAME=metalsharp-wine-6.0-arm64.tar.xz
N=8

mkdir -p "$DEST"
cd "$DEST"
if [ -f "$NAME" ] && [ "$(shasum -a 256 "$NAME" | awk '{print $1}')" = "$SHA" ]; then
    echo "已有并校验通过：$DEST/$NAME"
    exit 0
fi

rm -f part.* "$NAME"
CHUNK=$(( (TOTAL + N - 1) / N ))
pids=()
for i in $(seq 0 $((N-1))); do
    start=$(( i * CHUNK )); end=$(( start + CHUNK - 1 ))
    [ "$end" -ge "$TOTAL" ] && end=$(( TOTAL - 1 ))
    curl -sL --retry 5 --retry-delay 2 -r "$start-$end" -H "Accept: application/octet-stream" \
         -o "part.$i" "$URL" &
    pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
cat $(for i in $(seq 0 $((N-1))); do echo "part.$i"; done) > "$NAME"
rm -f part.*

got=$(shasum -a 256 "$NAME" | awk '{print $1}')
if [ "$got" != "$SHA" ]; then
    echo "校验失败：$got"
    exit 1
fi
tar xf "$NAME"
echo "解压完成：$DEST/metalsharp-wine-6.0-arm64/bin/wine"
