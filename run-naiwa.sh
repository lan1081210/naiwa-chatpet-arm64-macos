#!/bin/bash
# 奶蛙桌宠 · macOS 启动脚本（ARM64 原生 + 卡死自恢复）
# 卡死判定：程序每 2 秒写 Source/NaiWaChatPet/.heartbeat，超过 40 秒没更新就杀掉重开。
set -u
BASE="$HOME/Projects/NaiWaChatPet"
APPDIR="$BASE/Source/NaiWaChatPet"
BEAT="$APPDIR/.heartbeat"
LOG=/tmp/naiwa-launcher.log

if [ -x "$BASE/wine-arm64/MetalSharp-Wine.app/Contents/MacOS/wine" ]; then
    WINE="$BASE/wine-arm64/MetalSharp-Wine.app/Contents/MacOS/wine"
    WINESERVER="$BASE/wine-arm64/MetalSharp-Wine.app/Contents/MacOS/wineserver"
else
    WINE="$BASE/wine-arm64/metalsharp-wine-6.0-arm64/bin/wine"
    WINESERVER="$BASE/wine-arm64/metalsharp-wine-6.0-arm64/bin/wineserver"
fi

export WINEMSYNC=0
export WINEPREFIX="$BASE/prefix-arm64"
# 聊天走本机 Hermes 桥（~/.hermes/scripts/naiwa-hermes-bridge.py，默认 8799）
export NAIWA_BASE_URL="${NAIWA_BASE_URL:-http://127.0.0.1:8799}"
export NAIWA_MODEL="${NAIWA_MODEL:-hermes}"
export NAIWA_API_KEY="${NAIWA_API_KEY:-hermes-local-0001}"
if [ "${1:-}" = "-log" ]; then export WINEDEBUG="+loaddll,+seh"; shift; else export WINEDEBUG="-all"; fi

cd "$APPDIR" || { echo "找不到运行目录：$APPDIR"; exit 1; }
[ -x "$WINE" ] || { echo "找不到 wine：$WINE"; exit 1; }

if ! curl -s -m 1 -o /dev/null "http://127.0.0.1:8799/health"; then
    /usr/bin/python3 "$HOME/.hermes/scripts/naiwa-hermes-bridge.py" >> /tmp/naiwa-bridge.out 2>&1 &
fi

restarts=0
while :; do
    : > "$BEAT" 2>/dev/null || true
    "$WINE" NaiWaChatPet.exe -no-shortcut "$@" &
    child=$!
    (
        while kill -0 "$child" 2>/dev/null; do
            sleep 5
            [ -f "$BEAT" ] || continue
            age=$(( $(date +%s) - $(stat -f %m "$BEAT") ))
            if [ "$age" -gt 40 ]; then
                echo "[$(date '+%H:%M:%S')] 心跳停了 ${age}s，杀掉重开" >> "$LOG"
                kill -9 "$child" 2>/dev/null
                "$WINESERVER" -k 2>/dev/null
                break
            fi
        done
    ) &
    watchdog=$!
    wait "$child"
    code=$?
    kill "$watchdog" 2>/dev/null
    if [ "$code" -ne 0 ] && [ "$restarts" -lt 5 ]; then
        restarts=$((restarts+1))
        echo "[$(date '+%H:%M:%S')] 程序退出码 ${code}，重启第 ${restarts} 次" >> "$LOG"
        sleep 2
        continue
    fi
    break
done
exit "$code"
