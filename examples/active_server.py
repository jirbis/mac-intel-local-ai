#!/usr/bin/env python3
"""Find the local LLM server that Mac Intel Local AI is running.

The app writes ~/Library/Application Support/Mac Intel Local AI/active.json
whenever its settings are saved and when it starts:

    {
      "api": "ollama",                       # or "openai"
      "backend": "ollamaGPU",
      "base_url": "http://127.0.0.1:11434",
      "chat_endpoint": "http://127.0.0.1:11434/api/chat",
      "model": "qwen2.5:3b",
      "openai_base_url": "http://127.0.0.1:11434/v1",
      "title": "OllamaGPU"
    }

Every backend (Ollama and llama-server) also speaks the OpenAI-compatible API
under openai_base_url, so most clients only need that and "model".

    python3 active_server.py          # print the server and check it answers
"""

from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

ACTIVE_FILE = Path.home() / "Library/Application Support/Mac Intel Local AI/active.json"


def active_server(path: Path = ACTIVE_FILE) -> dict | None:
    """The active.json contents, or None if the app hasn't written it."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or not data.get("openai_base_url") or not data.get("model"):
        return None
    return data


def main() -> int:
    server = active_server()
    if server is None:
        print(f"no active server: {ACTIVE_FILE} is missing or invalid", file=sys.stderr)
        return 1
    print(f"{server['title']}: {server['openai_base_url']} model={server['model']}")
    try:
        with urllib.request.urlopen(server["openai_base_url"] + "/models", timeout=3) as response:
            ids = [m.get("id") for m in json.load(response).get("data", [])]
    except OSError as exc:
        print(f"not answering: {exc}", file=sys.stderr)
        return 2
    print("answering; models:", ", ".join(map(str, ids)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
