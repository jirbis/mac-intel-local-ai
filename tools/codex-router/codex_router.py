#!/usr/bin/env python3
"""Codex / ChatGPT app model router (a companion tool of Mac Intel Local AI).

The Codex desktop app (it ships as "ChatGPT.app") sends every request to one
`openai_base_url`. `ollama launch codex` points that at Ollama's
/api/codex/v1, which sends ":cloud" models to Ollama Cloud and everything else
to OpenAI, so a local model can't be picked there. This router sits in between
and routes by the request's "model":

  * a model listed in local_models    -> the server Mac Intel Local AI runs now
                                          (active.json, its OpenAI /v1 API)
  * "<network prefix><name>"           -> a network LLM (an OpenAI-compatible
                                          gateway such as LiteLLM), as <name>,
                                          with its key from the Keychain
  * anything else                       -> the previous openai_base_url (Ollama's
                                          /api/codex/v1), headers untouched

The ChatGPT/OpenAI token is never sent to the local server or the network LLM.

    codex_router.py install    copy this script to Application Support, start it
                               as a LaunchAgent and apply
    codex_router.py network --name Gateway --url https://gateway.lan/v1
                               set the network LLM (its key: see "key")
    codex_router.py key        store the network LLM's API key in the Keychain
                               (asks for it; it never appears on a command line)
    codex_router.py models --local qwen2.5:3b --network local-long
                               choose the models (comma-separated), then apply
    codex_router.py apply      add the models to the Codex model list and point
                               Codex at the router (backs up both files once)
    codex_router.py status     show what Codex points at
    codex_router.py restore    put the previous openai_base_url back and remove
                               the added models
    codex_router.py uninstall  restore, stop and remove the LaunchAgent
    codex_router.py serve      run the router (the LaunchAgent does this)

Restart the ChatGPT/Codex app after apply/restore. Python 3.9 standard library
only (macOS /usr/bin/python3).
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOME = Path.home()
SUPPORT = HOME / "Library/Application Support/Mac Intel Local AI"
CONFIG = SUPPORT / "codex-router.json"
ACTIVE = SUPPORT / "active.json"
INSTALLED = SUPPORT / "codex_router.py"
LABEL = "com.github.jirbis.mac-intel-local-ai.codex-router"
AGENT = HOME / f"Library/LaunchAgents/{LABEL}.plist"
LOG = HOME / "Library/Logs/Mac Intel Local AI/codex-router.log"
KEYCHAIN_SERVICE = "mac-intel-local-ai"
CODEX_CONFIG = HOME / ".codex/config.toml"
MARK = "Mac Intel Local AI"          # description of the catalog entries we add

DEFAULTS = {
    "port": 11500,
    "fallback": "http://127.0.0.1:11434/api/codex/v1",
    "local_models": [],
    "local_context_window": 32768,
    "network": {"name": "network", "base_url": "", "keychain_account": "network"},
    "network_models": [],
    "network_prefix": "",            # empty: the network LLM's name, lowercased, plus "/"
    "network_context_window": 32768,
    # For local and network models keep only plain function tools: Codex also
    # sends plugin/MCP "namespace" tools and web_search (over 1 MB), which
    # don't fit a local context and that LiteLLM/Ollama can't translate.
    "functions_only": True,
}

ZSTD = next((p for p in ("/usr/local/bin/zstd", "/opt/homebrew/bin/zstd", "/usr/bin/zstd") if os.path.exists(p)), None)


def decode_body(body: bytes, encoding: str | None) -> bytes | None:
    """The request body as sent before compression (Codex uses zstd), or None."""
    enc = (encoding or "").strip().lower()
    if not enc or enc == "identity":
        return body
    if enc == "gzip":
        import gzip
        return gzip.decompress(body)
    if enc == "deflate":
        import zlib
        return zlib.decompress(body)
    if enc == "zstd" and ZSTD:
        r = subprocess.run([ZSTD, "-d", "-c", "-q"], input=body, capture_output=True)
        return r.stdout if r.returncode == 0 else None
    return None


def shape(payload: dict) -> str:
    """Sizes and tool types of a Responses request, without its content."""
    size = lambda v: len(json.dumps(v, ensure_ascii=False))
    tools = payload.get("tools") or []
    kinds: dict[str, int] = {}
    for t in tools:
        kinds[t.get("type", "?")] = kinds.get(t.get("type", "?"), 0) + 1
    inp = payload.get("input")
    return json.dumps({
        "keys": sorted(payload), "instructions_chars": size(payload.get("instructions", "")),
        "input_items": len(inp) if isinstance(inp, list) else 1, "input_chars": size(inp),
        "tools": len(tools), "tool_types": kinds, "tools_chars": size(tools),
        "reasoning": payload.get("reasoning"), "tool_choice": payload.get("tool_choice"),
    })


HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te",
       "trailers", "transfer-encoding", "upgrade", "host", "content-length"}


def load_config() -> dict:
    cfg = dict(DEFAULTS)
    try:
        cfg.update(json.loads(CONFIG.read_text(encoding="utf-8")))
    except (OSError, ValueError):
        pass
    return cfg


def network(cfg: dict | None = None) -> dict:
    """The network LLM: name, base_url, keychain_account."""
    n = dict(DEFAULTS["network"])
    n.update((cfg or load_config()).get("network") or {})
    return n


def network_prefix(cfg: dict) -> str:
    return cfg.get("network_prefix") or network(cfg)["name"].lower().replace(" ", "-") + "/"


def save_config(cfg: dict) -> None:
    SUPPORT.mkdir(parents=True, exist_ok=True)
    CONFIG.write_text(json.dumps(cfg, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def router_url(cfg: dict) -> str:
    return f"http://127.0.0.1:{cfg['port']}/v1"


# ---------------------------------------------------------------- routing

_key_cache: dict[tuple[str, str], str] = {}
_key_lock = threading.Lock()


def keychain_key(service: str, account: str) -> str | None:
    with _key_lock:
        if (service, account) in _key_cache:
            return _key_cache[(service, account)]
        r = subprocess.run(["/usr/bin/security", "find-generic-password", "-s", service, "-a", account, "-w"],
                           capture_output=True, text=True)
        key = r.stdout.strip() if r.returncode == 0 else None
        if key:
            _key_cache[(service, account)] = key
        return key


def active_server() -> tuple[str | None, str | None]:
    """(OpenAI base, key) of the server Mac Intel Local AI has selected."""
    try:
        a = json.loads(ACTIVE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None, None
    key = keychain_key(a.get("keychain_service", KEYCHAIN_SERVICE), a["keychain_account"]) \
        if a.get("keychain_account") else None
    return a.get("openai_base_url"), key


def route(cfg: dict, model: str | None):
    """(base_url, model to send, key or None or "" for missing, keep client auth)."""
    if model and model in cfg["local_models"]:
        base, key = active_server()
        return base, model, key, False
    prefix = network_prefix(cfg)
    if model and cfg["network_models"] and model.startswith(prefix):
        n = network(cfg)
        if not n["base_url"]:
            return None, model, None, False
        key = keychain_key(KEYCHAIN_SERVICE, n["keychain_account"])
        return n["base_url"], model[len(prefix):], key or "", False
    return cfg["fallback"], model, None, True


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"     # close-delimited: streams SSE without re-chunking
    server_version = "mac-intel-local-ai-codex-router"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.log_date_time_string(), fmt % args))

    def do_GET(self):
        # Codex tries a WebSocket first; Ollama answers 426 and Codex falls back to
        # POST. Answer the same right away (the router doesn't proxy WebSockets).
        if (self.headers.get("Upgrade") or "").lower() == "websocket":
            return self.fail(426, "WebSocket not supported; use HTTP")
        self.forward(None)

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        self.forward(self.rfile.read(length) if length else b"")

    def do_DELETE(self):
        self.forward(None)

    def forward(self, body: bytes | None):
        cfg = load_config()
        if not self.path.startswith("/v1"):
            return self.fail(404, "unknown path")
        suffix = self.path[len("/v1"):]
        model = None
        payload = None
        encoding = self.headers.get("Content-Encoding")
        if body:
            plain = decode_body(body, encoding)
            if plain is None:
                return self.fail(415, f"can't read a {encoding} request body"
                                      + (" (install zstd: brew install zstd)" if (encoding or "").lower() == "zstd" else ""))
            try:
                payload = json.loads(plain)
                model = payload.get("model") if isinstance(payload, dict) else None
            except ValueError:
                payload = None
        base, send_model, key, keep_auth = route(cfg, model)
        if not keep_auth and isinstance(payload, dict):
            if cfg.get("functions_only", True) and isinstance(payload.get("tools"), list):
                payload["tools"] = [t for t in payload["tools"] if t.get("type") == "function"]
            # LiteLLM rejects it for Ollama models; Ollama ignores it.
            payload.pop("parallel_tool_calls", None)
            self.log_message("request shape: %s", shape(payload))
        if not keep_auth and payload is not None:
            # Local and network servers get plain JSON.
            body, encoding = json.dumps(payload).encode(), None
        if base is None:
            return self.fail(503, "no server: start one in Mac Intel Local AI, or set the network LLM "
                                  "(codex_router.py network --url ...)")
        if key == "":
            return self.fail(401, "no key for the network LLM in the Keychain (service %s, account %s): "
                             "run codex_router.py key" % (KEYCHAIN_SERVICE, network(cfg)["keychain_account"]))
        if payload is not None and send_model != model:
            payload["model"] = send_model
            body = json.dumps(payload).encode()
            encoding = None
        # Streamed through LiteLLM/Ollama, tool calls arrive as plain text
        # ('{"name": "exec_command", ...}'); unstreamed they are proper
        # function_call items. Ask without streaming and replay it as SSE.
        replay = (not keep_auth and suffix.startswith("/responses") and isinstance(payload, dict)
                  and payload.get("stream") and cfg.get("buffer_stream", True))
        if replay:
            payload["stream"] = False
            body, encoding = json.dumps(payload).encode(), None
        target = urllib.parse.urlsplit(base.rstrip("/") + suffix)
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP}
        if not keep_auth:
            # Never hand the ChatGPT/OpenAI token to a local or network server.
            headers = {k: v for k, v in headers.items()
                       if k.lower() not in ("authorization", "chatgpt-account-id", "openai-organization", "cookie")
                       and not k.lower().startswith("x-codex") and not k.lower().startswith("openai-")}
            if key:
                headers["Authorization"] = "Bearer " + key
        headers = {k: v for k, v in headers.items() if k.lower() != "content-encoding"}
        if encoding and body is not None:
            headers["Content-Encoding"] = encoding
        if body is not None:
            headers["Content-Length"] = str(len(body))
        conn_cls = http.client.HTTPSConnection if target.scheme == "https" else http.client.HTTPConnection
        path = target.path + (("?" + target.query) if target.query else "")
        self.log_message("%s %s model=%s enc=%s upgrade=%s len=%s -> %s://%s%s", self.command, self.path, model,
                         self.headers.get("Content-Encoding"), self.headers.get("Upgrade"),
                         len(body) if body is not None else None, target.scheme, target.netloc, target.path)
        try:
            conn = conn_cls(target.netloc, timeout=600)
            conn.request(self.command, path, body=body, headers=headers)
            resp = conn.getresponse()
        except OSError as exc:
            return self.fail(502, f"upstream {target.netloc} unreachable: {exc}")
        if replay:
            try:
                return self.replay_sse(resp)
            finally:
                conn.close()
        if keep_auth and resp.status == 404 and "/api/codex/" in cfg["fallback"]:
            resp.read()
            conn.close()
            return self.fail(404, "the Ollama on :11434 has no /api/codex/v1, so cloud and GPT models can't "
                                  "pass through it. Select OllamaGPU 0.40+ (or official Ollama) in Mac Intel "
                                  "Local AI; the Momin010 build doesn't have it.")
        self.send_response(resp.status, resp.reason)
        for k, v in resp.getheaders():
            if k.lower() not in HOP:
                self.send_header(k, v)
        self.send_header("Connection", "close")
        self.end_headers()
        try:
            while True:
                chunk = resp.read1(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            conn.close()

    def replay_sse(self, resp):
        """Send a finished Responses object to Codex as the SSE events it expects."""
        raw = resp.read()
        try:
            done = json.loads(raw)
        except ValueError:
            done = None
        if resp.status != 200 or not isinstance(done, dict) or "output" not in done:
            self.send_response(resp.status if resp.status != 200 else 502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        seq = 0

        def event(kind: str, **fields):
            nonlocal seq
            data = {"type": kind, "sequence_number": seq, **fields}
            seq += 1
            self.wfile.write(f"event: {kind}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n".encode())

        try:
            start = dict(done, status="in_progress", output=[])
            event("response.created", response=start)
            event("response.in_progress", response=start)
            for i, item in enumerate(done["output"]):
                kind = item.get("type")
                if kind == "message":
                    event("response.output_item.added", output_index=i, item=dict(item, content=[], status="in_progress"))
                    for j, part in enumerate(item.get("content") or []):
                        if part.get("type") == "output_text":
                            text = part.get("text", "")
                            event("response.content_part.added", item_id=item.get("id"), output_index=i,
                                  content_index=j, part=dict(part, text=""))
                            event("response.output_text.delta", item_id=item.get("id"), output_index=i,
                                  content_index=j, delta=text)
                            event("response.output_text.done", item_id=item.get("id"), output_index=i,
                                  content_index=j, text=text)
                            event("response.content_part.done", item_id=item.get("id"), output_index=i,
                                  content_index=j, part=part)
                elif kind == "function_call":
                    event("response.output_item.added", output_index=i, item=dict(item, arguments="", status="in_progress"))
                    event("response.function_call_arguments.delta", item_id=item.get("id"), output_index=i,
                          delta=item.get("arguments", ""))
                    event("response.function_call_arguments.done", item_id=item.get("id"), output_index=i,
                          arguments=item.get("arguments", ""))
                else:
                    event("response.output_item.added", output_index=i, item=item)
                event("response.output_item.done", output_index=i, item=item)
            event("response.completed", response=dict(done, status=done.get("status") or "completed"))
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def fail(self, status: int, message: str):
        data = json.dumps({"error": {"message": f"[{MARK} router] {message}", "type": "router_error"}}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def serve() -> int:
    cfg = load_config()
    server = ThreadingHTTPServer(("127.0.0.1", int(cfg["port"])), Handler)
    server.daemon_threads = True
    print(f"codex router on {router_url(cfg)}; fallback {cfg['fallback']}", file=sys.stderr, flush=True)
    server.serve_forever()
    return 0


# ---------------------------------------------------------------- Codex files

BASE_URL_RE = re.compile(r'^openai_base_url\s*=\s*"([^"]*)"\s*$', re.M)
CATALOG_RE = re.compile(r'^model_catalog_json\s*=\s*"([^"]*)"\s*$', re.M)


def backup_once(path: Path) -> None:
    bak = path.with_name(path.name + ".bak-mac-intel-local-ai")
    if path.exists() and not bak.exists():
        shutil.copy2(path, bak)


def codex_toml() -> str:
    try:
        return CODEX_CONFIG.read_text(encoding="utf-8")
    except OSError:
        return ""


def catalog_path(toml: str) -> Path | None:
    m = CATALOG_RE.search(toml)
    return Path(m.group(1)).expanduser() if m else None


def entry(template: dict, slug: str, name: str, context: int) -> dict:
    e = json.loads(json.dumps(template))
    e.update({
        "slug": slug, "display_name": name, "description": MARK,
        "context_window": context, "max_context_window": context,
        "supports_reasoning_summaries": False, "supports_reasoning_summary_parameter": False,
        "supports_search_tool": False, "input_modalities": ["text"],
        "priority": 50, "visibility": "list",
    })
    for k in ("default_service_tier", "upgrade", "availability_nux"):
        if k in e:
            e[k] = None
    return e


def apply() -> int:
    cfg = load_config()
    toml = codex_toml()
    if not toml:
        print(f"{CODEX_CONFIG} not found: run Codex/ChatGPT (or `ollama launch codex`) once first", file=sys.stderr)
        return 1
    url = router_url(cfg)
    m = BASE_URL_RE.search(toml)
    if m and m.group(1) != url:
        cfg["fallback"] = m.group(1)          # keep whatever Codex used before as the fallback
        save_config(cfg)
    backup_once(CODEX_CONFIG)
    line = f'openai_base_url = "{url}"'
    toml = BASE_URL_RE.sub(line, toml, count=1) if m else line + "\n" + toml
    CODEX_CONFIG.write_text(toml, encoding="utf-8")

    path = catalog_path(toml)
    if path is None or not path.exists():
        print("no model_catalog_json in config.toml: models can still be typed by name", file=sys.stderr)
        return 0
    backup_once(path)
    catalog = json.loads(path.read_text(encoding="utf-8"))
    models = [x for x in catalog.get("models", []) if x.get("description") != MARK]
    template = next((x for x in models if str(x.get("slug", "")).endswith(":cloud")), models[0] if models else None)
    if template is None:
        print("empty model catalog; nothing to copy fields from", file=sys.stderr)
        return 1
    added = [entry(template, m, f"{m} (local)", int(cfg["local_context_window"])) for m in cfg["local_models"]]
    prefix, name = network_prefix(cfg), network(cfg)["name"]
    added += [entry(template, prefix + m, f"{m} ({name})", int(cfg["network_context_window"]))
              for m in cfg["network_models"]]
    catalog["models"] = added + models
    path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Codex -> {url} (fallback {cfg['fallback']}); added: {', '.join(x['slug'] for x in added) or 'nothing'}")
    print("Restart the ChatGPT/Codex app to see the models.")
    return 0


def restore() -> int:
    cfg = load_config()
    toml = codex_toml()
    if BASE_URL_RE.search(toml):
        toml = BASE_URL_RE.sub(f'openai_base_url = "{cfg["fallback"]}"', toml, count=1)
        CODEX_CONFIG.write_text(toml, encoding="utf-8")
    path = catalog_path(toml)
    if path and path.exists():
        catalog = json.loads(path.read_text(encoding="utf-8"))
        catalog["models"] = [x for x in catalog.get("models", []) if x.get("description") != MARK]
        path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Codex -> {cfg['fallback']}; added models removed")
    return 0


def status() -> int:
    cfg = load_config()
    toml = codex_toml()
    m = BASE_URL_RE.search(toml)
    current = m.group(1) if m else "(not set: OpenAI)"
    path = catalog_path(toml)
    ours = []
    if path and path.exists():
        try:
            ours = [x["slug"] for x in json.loads(path.read_text(encoding="utf-8")).get("models", [])
                    if x.get("description") == MARK]
        except (ValueError, KeyError):
            pass
    n = network(cfg)
    key = bool(keychain_key(KEYCHAIN_SERVICE, n["keychain_account"])) if cfg["network_models"] else None
    print(json.dumps({"codex_base_url": current, "router_url": router_url(cfg),
                      "via_router": current == router_url(cfg), "fallback": cfg["fallback"],
                      "local_models": cfg["local_models"], "network": n["base_url"],
                      "network_models": [network_prefix(cfg) + m for m in cfg["network_models"]],
                      "added_to_codex": ours, "network_key_in_keychain": key,
                      "agent_running": subprocess.run(["/bin/launchctl", "print", f"gui/{os.getuid()}/{LABEL}"],
                                                      capture_output=True).returncode == 0}, indent=2))
    return 0


def agent_xml() -> str:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Codex/ChatGPT app model router (Mac Intel Local AI tools/codex-router). -->
<plist version="1.0">
<dict>
    <key>Label</key><string>{LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string><string>-I</string>
        <string>{INSTALLED}</string><string>serve</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>StandardOutPath</key><string>{LOG}</string>
    <key>StandardErrorPath</key><string>{LOG}</string>
</dict>
</plist>
"""


def launchctl(*args: str) -> int:
    return subprocess.run(["/bin/launchctl", *args], capture_output=True).returncode


def install() -> int:
    SUPPORT.mkdir(parents=True, exist_ok=True)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    if Path(__file__).resolve() != INSTALLED.resolve():
        shutil.copy2(__file__, INSTALLED)
    AGENT.write_text(agent_xml(), encoding="utf-8")
    domain = f"gui/{os.getuid()}"
    launchctl("bootout", f"{domain}/{LABEL}")
    if launchctl("bootstrap", domain, str(AGENT)) != 0:
        print(f"launchctl bootstrap {AGENT} failed", file=sys.stderr)
        return 1
    print(f"router installed: {INSTALLED}, LaunchAgent {LABEL}")
    return apply()


def uninstall() -> int:
    restore()
    launchctl("bootout", f"gui/{os.getuid()}/{LABEL}")
    for path in (AGENT, INSTALLED):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
    print("router removed")
    return 0


def set_network(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="codex_router.py network")
    parser.add_argument("--name", help="shown in Codex; its lower-case form is the default model prefix")
    parser.add_argument("--url", help="OpenAI-compatible base, e.g. https://gateway.lan/v1")
    parser.add_argument("--keychain-account", help="Keychain account of the key (service %s)" % KEYCHAIN_SERVICE)
    args = parser.parse_args(argv)
    cfg = load_config()
    n = network(cfg)
    for field, value in (("name", args.name), ("base_url", args.url), ("keychain_account", args.keychain_account)):
        if value is not None:
            n[field] = value.rstrip("/") if field == "base_url" else value
    cfg["network"] = n
    save_config({k: v for k, v in cfg.items() if k in DEFAULTS})
    print(json.dumps(n, indent=2))
    return 0


def store_key() -> int:
    account = network()["keychain_account"]
    print(f"API key for the network LLM (Keychain service {KEYCHAIN_SERVICE}, account {account}):")
    # With -w last and no value, security asks for the password itself.
    return subprocess.run(["/usr/bin/security", "add-generic-password", "-U", "-s", KEYCHAIN_SERVICE,
                           "-a", account, "-l", f"{MARK}: network LLM key ({account})", "-w"]).returncode


def models(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="codex_router.py models")
    parser.add_argument("--local", help="local models, comma-separated (empty string: none)")
    parser.add_argument("--network", help="network LLM models, comma-separated (empty string: none)")
    parser.add_argument("--prefix", help="prefix for the network models in Codex (default: name/)")
    args = parser.parse_args(argv)
    cfg = load_config()
    split = lambda v: [x.strip() for x in v.split(",") if x.strip()]
    if args.local is not None:
        cfg["local_models"] = split(args.local)
    if args.network is not None:
        cfg["network_models"] = split(args.network)
    if args.prefix is not None:
        cfg["network_prefix"] = args.prefix
    save_config({k: v for k, v in cfg.items() if k in DEFAULTS})
    return apply()


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd in ("models", "network"):
        raise SystemExit((models if cmd == "models" else set_network)(sys.argv[2:]))
    commands = {"serve": serve, "apply": apply, "restore": restore, "status": status,
                "install": install, "uninstall": uninstall, "key": store_key}
    if cmd not in commands:
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(commands[cmd]())
