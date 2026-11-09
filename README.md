# 奶蛙桌宠 · macOS Apple Silicon 原生版（ARM64，无 Rosetta）

[English](README.en.md)

上游 NaiWaChatPet 是 Windows 桌面程序（Go + Win32 + GDI 分层窗口）。这里做两件事：

1. **编译成 Windows arm64 原生程序**，用 MetalSharp Wine 11.20（原生 arm64 的 Wine）跑，整条链路不经过 Rosetta。
2. **砍掉联机格斗**：房间服务器、局域网发现、联机大厅、重连全部删除，只留单机挑战和设置。
3. **聊天接本机 Hermes**：附一个本地 OpenAI 兼容端口，奶蛙说的话由 Hermes 回答。

本仓库只放适配层的脚本、补丁和说明。奶蛙本体、动画资源、Wine 运行时体积太大，按下面步骤本机生成。

## 现状

| 项 | 状态 |
|---|---|
| 桌宠本体（动画、表情、拖动、右键菜单） | 跑在 Mac 上，已截图确认渲染 |
| 键盘操控、走动跳跃、打苍蝇、专注计时 | 正常 |
| 单机挑战 | 保留 |
| 联机（房间、局域网、大厅、重连） | 已删除 |
| 聊天 → 本机 Hermes | 命令行自检通过（`-chat-ping`），桥的日志有记录 |

## 快速开始

```sh
# 1) 装 arm64 Wine（MetalSharp 6.0，约 918 MB 压缩包）
#    先下 release，解压到 ~/Projects/NaiWaChatPet/wine-arm64/
#    下载地址：https://github.com/metalsharp/MetalSharp-Wine/releases
#    单连接会被限速（~200 KB/s），分包并发下快得多，见 scripts/fetch-wine.sh

# 2) 起 Hermes 桥
python3 scripts/naiwa-hermes-bridge.py &

# 3) 起桌宠（脚本里已经把 NAIWA_BASE_URL 指到桥）
./run-naiwa.sh
```

第一次启动会用新 prefix 建容器（`~/Projects/NaiWaChatPet/prefix-arm64`），一两分钟。

## 目录约定

脚本假设工作目录是 `~/Projects/NaiWaChatPet`：

```
~/Projects/NaiWaChatPet/
  Source/NaiWaChatPet/NaiWaChatPet.exe     ← arm64 版程序（本仓库 build 脚本产出）
  Source/NaiWaChatPet/animations/          ← 上游动画
  wine-arm64/metalsharp-wine-6.0-arm64/    ← arm64 Wine
  prefix-arm64/                            ← 新容器（x86 的旧容器不能复用）
  run-naiwa.sh
```

## 编译

```sh
# 先拿上游源码，应用去联机补丁
./scripts/build-arm64.sh /path/to/upstream-source
```

补丁做的事：

- 删 `fightnet/`（TCP + 局域网协议）和 `cmd/fightserver/`（房间服务器）
- 删 `fight_lan*.go`、`combat_online_probe*.go`、联机相关测试
- `fight_combat_windows.go`：去掉拨号、重连、网络快照分支，只留本地 60 Hz 战斗
- 大厅去掉「联机」页，只留设置和高级；右键菜单去掉「联机大厅」
- `companion/server.go`：加 `NAIWA_BASE_URL` / `NAIWA_MODEL` / `NAIWA_API_KEY` 环境变量，启动时直接指向本机桥
- `main.go`：加 `-chat-ping "文本"`，一条命令验证聊天链路

## Hermes 桥

本地 [OpenAI 兼容端口](scripts/naiwa-hermes-bridge.py)，默认 `http://127.0.0.1:8799`：

| 路由 | 用途 |
|---|---|
| `POST /chat/completions`、`/v1/chat/completions` | 桌宠用这个，`hermes -z` 执行一轮并回正文 |
| `GET /models`、`GET /health` | 自检 |

```sh
python3 scripts/naiwa-hermes-bridge.py            # 前台，端口 8799
python3 scripts/naiwa-hermes-bridge.py --port 8800 --tools ""   # 换端口、不给工具
```

把 messages 压成 prompt 时保留 system（角色设定）和最近对话；默认不给 Hermes 工具，纯聊天。日志在 `~/.hermes/logs/naiwa-bridge.log`。

桌宠启动脚本里这三个变量就是配置口：

```sh
NAIWA_BASE_URL=http://127.0.0.1:8799
NAIWA_MODEL=hermes
NAIWA_API_KEY=hermes-local-0001   # 客户端要求 8 位以上，桥不校验
```

## 验证

```sh
# 桥
curl -s -X POST http://127.0.0.1:8799/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"hermes","messages":[{"role":"user","content":"你在干嘛？"}]}'

# 桌宠 → 桥（走 Wine 里的 arm64 程序）
WINEPREFIX=~/Projects/NaiWaChatPet/prefix-arm64 \
NAIWA_BASE_URL=http://127.0.0.1:8799 NAIWA_MODEL=hermes NAIWA_API_KEY=hermes-local-0001 \
~/Projects/NaiWaChatPet/wine-arm64/metalsharp-wine-6.0-arm64/bin/wine \
~/Projects/NaiWaChatPet/Source/NaiWaChatPet/NaiWaChatPet.exe -chat-ping "只回一句：桥接通了"
```

## 已知限制

- MetalSharp Wine 的 `tar.xz` 是 ad-hoc 签名、16K 页版本，只支持 arm64 和 x86_64；i386 需要签名版 `.app`。
- 设置页和菜单的截图验证没做完整：合成键鼠事件打进 Win32 分层窗口不稳定，功能验证走的是程序自己的日志和 `-chat-ping`。
- 桌面整理（DeskBox）要 Windows 的 .NET 桌面运行时；屏幕感知要 Windows GDI 抓屏，Wine 下都不可用。
- 内存 550 MB 上下，是动画解码的位图缓存，跟 Wine 无关。

## 上游与许可

奶蛙桌宠 NaiWaChatPet 版权归上游作者，AGPL-3.0。本仓库只有适配脚本、启动器和补丁，不含上游源码、动画和二进制。
