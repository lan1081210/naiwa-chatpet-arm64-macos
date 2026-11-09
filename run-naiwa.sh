#!/bin/bash
# 奶蛙桌宠 · macOS 启动脚本（ARM64 原生：MetalSharp Wine 11.20 + arm64 exe，不走 Rosetta）
set -u
BASE="$HOME/Projects/NaiWaChatPet"
WINE="$BASE/wine-arm64/metalsharp-wine-6.0-arm64/bin/wine"
APPDIR="$BASE/Source/NaiWaChatPet"
export WINEPREFIX="$BASE/prefix-arm64"
# 聊天走本机 Hermes 桥（~/.hermes/scripts/naiwa-hermes-bridge.py，默认 8799）
export NAIWA_BASE_URL="${NAIWA_BASE_URL:-http://127.0.0.1:8799}"
export NAIWA_MODEL="${NAIWA_MODEL:-hermes}"
export NAIWA_API_KEY="${NAIWA_API_KEY:-hermes-local-0001}"
if [ "${1:-}" = "-log" ]; then export WINEDEBUG="+loaddll,+seh"; shift; else export WINEDEBUG="-all"; fi
cd "$APPDIR" || { echo "找不到运行目录：$APPDIR"; exit 1; }
[ -x "$WINE" ] || { echo "找不到 wine：$WINE"; exit 1; }
exec "$WINE" NaiWaChatPet.exe "$@"
