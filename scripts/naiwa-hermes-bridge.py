#!/usr/bin/env python3
"""奶蛙桌宠 ↔ Hermes 桥（本地 OpenAI 兼容端口）。

桌宠的聊天设置里把 BaseURL 指到 http://127.0.0.1:8799，
模型名随便填（比如 hermes），之后奶蛙说的每句话都由本机的 Hermes 回答。

端点：
  POST /chat/completions      OpenAI 兼容（桌宠用这个）
  POST /v1/chat/completions   同上，兼容带 /v1 的客户端
  GET  /models                模型列表，让客户端不报错
  GET  /health                自检

用法：
  python3 ~/.hermes/scripts/naiwa-hermes-bridge.py            # 前台跑
  python3 ~/.hermes/scripts/naiwa-hermes-bridge.py --port 8800 --tools ""  # 换端口/不给工具
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG_PATH = os.path.expanduser("~/.hermes/logs/naiwa-bridge.log")
HERMES = shutil.which("hermes") or os.path.expanduser("~/.hermes/hermes-agent/.hermes/bin/hermes")
ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")

ARGS: argparse.Namespace
LOCK = threading.Semaphore(2)


def log(line: str) -> None:
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    with open(LOG_PATH, "a", encoding="utf-8") as fh:
        fh.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {line}\n")


def flatten(messages) -> str:
    """把 OpenAI 的 messages 压成一段给 hermes -z 的文本。"""
    system, turns = [], []
    for m in messages or []:
        role = str(m.get("role", "user"))
        content = m.get("content")
        if isinstance(content, list):  # 多段内容
            content = "".join(part.get("text", "") for part in content if isinstance(part, dict))
        text = (content or "").strip() if isinstance(content, str) else ""
        if not text:
            continue
        if role == "system":
            system.append(text)
        elif role == "assistant":
            turns.append("你之前说过：" + text)
        else:
            turns.append(text)
    prompt = ""
    if system:
        prompt += "【角色设定，必须遵守】\n" + "\n".join(system) + "\n\n"
    if len(turns) > 1:
        prompt += "【对话记录】\n" + "\n".join(turns[:-1]) + "\n\n"
    prompt += "【现在回答】\n" + (turns[-1] if turns else "你好")
    return prompt


def ask_hermes(prompt: str) -> str:
    cmd = [HERMES, "-z", prompt]
    if ARGS.tools:
        cmd += ["-t", ARGS.tools]
    env = dict(os.environ)
    env.setdefault("NO_COLOR", "1")
    env.setdefault("TERM", "dumb")
    started = time.time()
    try:
        out = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=ARGS.timeout,
            env=env,
            cwd=os.path.expanduser("~"),
        )
    except subprocess.TimeoutExpired:
        log(f"timeout after {ARGS.timeout}s  prompt={prompt[:80]!r}")
        return "……我想太久了，等我缓一下。"
    text = ANSI.sub("", out.stdout or "").strip()
    if not text:
        tail = ANSI.sub("", (out.stderr or "").strip())[-400:]
        log(f"empty reply rc={out.returncode} stderr={tail!r}")
        return "我这边脑子卡了一下，再说一遍？"
    log(f"ok {time.time() - started:.1f}s len={len(text)} prompt={prompt[:80]!r}")
    return text


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # 安静一点，日志自己写
        pass

    def _json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/health", "/healthz"):
            self._json(200, {"ok": True, "backend": HERMES, "tools": ARGS.tools})
        elif path.rstrip("/").endswith("/models"):
            self._json(200, {"object": "list", "data": [{"id": "hermes", "object": "model", "owned_by": "local"}]})
        else:
            self._json(404, {"error": {"message": "not found"}})

    def do_POST(self):
        path = self.path.split("?")[0]
        if not path.rstrip("/").endswith("/chat/completions"):
            self._json(404, {"error": {"message": "not found"}})
            return
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw.decode("utf-8", "replace"))
        except json.JSONDecodeError:
            self._json(400, {"error": {"message": "invalid json"}})
            return
        messages = payload.get("messages") or []
        prompt = flatten(messages)
        with LOCK:
            text = ask_hermes(prompt) if prompt else ""
        self._json(200, {
            "id": "chatcmpl-" + uuid.uuid4().hex[:24],
            "object": "chat.completion",
            "created": int(time.time()),
            "model": payload.get("model") or "hermes",
            "choices": [{"index": 0, "message": {"role": "assistant", "content": text}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": len(prompt), "completion_tokens": len(text), "total_tokens": len(prompt) + len(text)},
        })


def main() -> None:
    global ARGS
    ap = argparse.ArgumentParser(description="奶蛙桌宠 ↔ Hermes 本地桥")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8799)
    ap.add_argument("--hermes", default=HERMES, help="hermes 可执行文件")
    ap.add_argument("--timeout", type=float, default=180, help="单次回答超时（秒）")
    ap.add_argument("--tools", default="", help="给 Hermes 的工具集，默认不给（纯聊天）")
    ARGS = ap.parse_args()
    if not os.path.exists(ARGS.hermes):
        sys.exit(f"找不到 hermes：{ARGS.hermes}")
    server = ThreadingHTTPServer((ARGS.host, ARGS.port), Handler)
    print(f"奶蛙桥已启动：http://{ARGS.host}:{ARGS.port}/chat/completions  →  {ARGS.hermes}", flush=True)
    log(f"bridge start on {ARGS.host}:{ARGS.port} hermes={ARGS.hermes} tools={ARGS.tools!r}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止", flush=True)


if __name__ == "__main__":
    main()
