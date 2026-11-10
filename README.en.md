# NaiWaChatPet — Native Apple Silicon (ARM64, no Rosetta)

[中文说明](README.md)

Upstream NaiWaChatPet is a Windows desktop app (Go + Win32 + GDI layered windows). This repo does three things:

1. **Builds it as a Windows arm64 binary** and runs it under MetalSharp Wine 11.20 (a native arm64 Wine). Nothing in the chain goes through Rosetta.
2. **Removes the online fight mode**: room server, LAN discovery, online lobby and reconnect are all deleted. Single-player challenge and settings stay.
3. **Routes chat to local Hermes**: a small OpenAI-compatible port that answers with `hermes -z`.

Only the adaptation layer lives here — launcher, bridge, patch, docs. The pet itself, its animations and the Wine runtime are large and are produced locally.

## Status

| Item | State |
|---|---|
| Pet itself (animation, expressions, drag, context menu) | Runs on Mac, rendering confirmed by screenshot |
| Stall recovery | Heartbeat file + launcher watchdog; recovered 41 s after a real freeze |
| Keyboard control, walk/jump, fly swat, focus timer | Works |
| Single-player challenge | Kept; smoke report: 3 lifecycle cycles, 479 frames, 12 FPS, no GDI handle leak |
| Online (rooms, LAN, lobby, reconnect) | Removed; the panel keeps only Settings and Advanced |
| Chat to local Hermes | Verified through `-chat-ping`, bridge log shows the request |

## Quick start

```sh
# 1) Install arm64 Wine (MetalSharp 6.0, signed MetalSharp-Wine-6.0-arm64.zip, 1.36 GB)
#    https://github.com/metalsharp/MetalSharp-Wine/releases
#    Extract to ~/Projects/NaiWaChatPet/wine-arm64/ ; single connections are
#    throttled (~200 KB/s), parallel ranges are much faster — see scripts/fetch-wine.sh

# 2) Start the Hermes bridge
python3 scripts/naiwa-hermes-bridge.py &

# 3) Start the pet
./run-naiwa.sh
```

The first launch builds a fresh Wine prefix at `~/Projects/NaiWaChatPet/prefix-arm64` and takes a minute or two.

## Layout

Scripts assume `~/Projects/NaiWaChatPet`:

```
~/Projects/NaiWaChatPet/
  Source/NaiWaChatPet/NaiWaChatPet.exe     <- arm64 build from scripts/build-arm64.sh
  Source/NaiWaChatPet/animations/          <- upstream assets
  wine-arm64/metalsharp-wine-6.0-arm64/    <- arm64 Wine
  prefix-arm64/                            <- new prefix; the x86 one cannot be reused
  run-naiwa.sh
```

## Build

```sh
./scripts/build-arm64.sh /path/to/upstream-source
```

What the patch changes:

- Deletes `fightnet/` (TCP + LAN protocol) and `cmd/fightserver/` (room server)
- Deletes `fight_lan*.go`, `combat_online_probe*.go` and the online tests
- `fight_combat_windows.go`: drops dialling, reconnect and remote-snapshot branches, keeps the local 60 Hz fight
- Lobby loses the online page and keeps settings/advanced; the context menu loses its online entry
- `companion/server.go`: adds `NAIWA_BASE_URL` / `NAIWA_MODEL` / `NAIWA_API_KEY`, pointing the pet at the local bridge on startup
- `main.go`: adds `-chat-ping "text"` to check the chat path in one command

## Stalls: root cause and two layers

MetalSharp's arm64 Wine deadlocks occasionally: the window stays, clicks do nothing, CPU drops to 1%,
and `sample` shows every thread parked on Wine's `msync` locks. The same exe built for x86_64 runs fine
under Wine Staging via Rosetta, so it is a synchronisation defect in the arm64 runtime — both the tar.xz
and the signed `.app` builds show it.

**Primary fix:** the launcher sets `WINEMSYNC=0`, disabling Wine's msync fast path in favour of
server-side synchronisation. With it, one instance ran 11 minutes without a stall (before: every 1–3
minutes). The upstream peer heartbeat (a file write every 200 ms, a directory scan every 140 ms) is also
off by default — set `NAIWA_PEERS=on` to re-enable.

**Fallback:** the app keeps `Source/NaiWaChatPet/.heartbeat` every 2 s; the launcher checks it every 5 s and,
after 40 s of staleness, kills the process, runs `wineserver -k` and restarts (at most 5 times), logging to
`/tmp/naiwa-launcher.log`. An in-process 90 s watchdog calls `os.Exit(3)` as a second line of defence.
Measured recovery: 41 s.

## Bridge

Local OpenAI-compatible port at `http://127.0.0.1:8799`:

| Route | Purpose |
|---|---|
| `POST /chat/completions`, `/v1/chat/completions` | Used by the pet; runs one `hermes -z` turn and returns the text |
| `GET /models`, `GET /health` | Self-check |

Message lists are flattened into a prompt, keeping the system persona and the recent turns. Hermes gets no tools by default. Log: `~/.hermes/logs/naiwa-bridge.log`.

## Verify

```sh
curl -s -X POST http://127.0.0.1:8799/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"hermes","messages":[{"role":"user","content":"hello"}]}'

WINEPREFIX=~/Projects/NaiWaChatPet/prefix-arm64 \
NAIWA_BASE_URL=http://127.0.0.1:8799 NAIWA_MODEL=hermes NAIWA_API_KEY=hermes-local-0001 \
~/Projects/NaiWaChatPet/wine-arm64/metalsharp-wine-6.0-arm64/bin/wine \
~/Projects/NaiWaChatPet/Source/NaiWaChatPet/NaiWaChatPet.exe -chat-ping "reply with one word: ok"
```

## Known limits

- The MetalSharp `tar.xz` build is ad-hoc signed with 16K pages; it runs arm64 and x86_64 only. i386 needs the notarised `.app`.
- Menu and settings screenshots were not fully verified: synthetic mouse/keyboard events into a Win32 layered window are unreliable, so verification went through the app's own logs and `-chat-ping`.
- Desk organizer needs the Windows .NET desktop runtime; screen capture needs Windows GDI. Neither works under Wine.
- Memory sits around 550 MB — decoded animation bitmaps, not Wine.

## Upstream and licence

NaiWaChatPet belongs to its upstream authors, AGPL-3.0. This repo carries only scripts, launcher and patch; no upstream source, animations or binaries.
