# Local and network models in the Codex / ChatGPT app

The Codex desktop app (it installs as `ChatGPT.app`, bundle `com.openai.codex`) sends every request to one
`openai_base_url` in `~/.codex/config.toml`. `ollama launch codex` (Ollama 0.40+) points it at Ollama's
`/api/codex/v1` and writes the model list to `model_catalog_json`. That endpoint forwards models ending in `:cloud`
(GLM, Kimi, DeepSeek, …) to Ollama Cloud and everything else to OpenAI, so a local model can't be used there.

`tools/codex-router/codex_router.py` (a separate tool, not part of the app) is a small router on `127.0.0.1:11500`,
run by the LaunchAgent `com.github.jirbis.mac-intel-local-ai.codex-router`. It routes by the requested model:

| Model in Codex | Goes to | Auth sent |
|---|---|---|
| a model in `local_models` | the server Mac Intel Local AI has selected (`active.json`) | none |
| `<prefix><name>` for a name in `network_models` | the network LLM set with `network --url` (e.g. a LiteLLM gateway) as `<name>` | its key from the Keychain |
| anything else (`:cloud`, GPT) | the previous `openai_base_url` (Ollama `/api/codex/v1`) | Codex's own headers, unchanged |

Codex's ChatGPT token is only ever passed to the endpoint it was already going to. The network LLM is optional and belongs to the
router only (the app manages just the local server); the prefix defaults to its name in lower case plus `/`.

```sh
python3 tools/codex-router/codex_router.py install                       # copy to Application Support, start, apply
python3 ~/Library/"Application Support/Mac Intel Local AI"/codex_router.py network --name Gateway --url https://gateway.lan/v1
python3 ~/Library/"Application Support/Mac Intel Local AI"/codex_router.py key       # asks for the API key, stores it in the Keychain
python3 ~/Library/"Application Support/Mac Intel Local AI"/codex_router.py models --local qwen2.5:3b --network local-long
python3 ~/Library/"Application Support/Mac Intel Local AI"/codex_router.py status
python3 ~/Library/"Application Support/Mac Intel Local AI"/codex_router.py restore     # Codex back as it was
python3 ~/Library/"Application Support/Mac Intel Local AI"/codex_router.py uninstall   # restore and remove the router
```

`apply` (also run by `install` and `models`) sets `openai_base_url` to the router and adds the models to the catalog
(entries marked `"description": "Mac Intel Local AI"`); both Codex files are backed up once as `*.bak-mac-intel-local-ai`.
Settings: `~/Library/Application Support/Mac Intel Local AI/codex-router.json`; log: `~/Library/Logs/Mac Intel Local AI/codex-router.log`.

Notes:
- **Cloud and GPT models need an Ollama with `/api/codex/v1`** on :11434: OllamaGPU 0.40+ or the official Ollama. The Momin010 build (v0.32.3) doesn't have it, so with that backend selected only the local and network models work, and the router says so.
- **What the router changes for local and network models.** It keeps only plain `function` tools (Codex also sends over 1 MB of plugin/MCP tools and `web_search`), drops `parallel_tool_calls` (LiteLLM rejects it for Ollama models) and asks without streaming, then replays the answer to Codex as SSE: streamed through LiteLLM/Ollama, tool calls come back as plain text instead of `function_call` items. Set `"functions_only": false` or `"buffer_stream": false` in `codex-router.json` to turn these off.
- **Compressed requests.** Codex compresses request bodies with zstd; the router unpacks them with the `zstd` command (`brew install zstd`) to read the model, and sends plain JSON to the local and network servers. It answers WebSocket attempts with 426, as Ollama does, so Codex uses HTTP.
- **Restart the ChatGPT/Codex app** after `apply`, `restore` or `models`.
- **If `ollama launch codex` rewrites the config,** run `apply` again; `status` shows `"via_router": false`.
- **Codex prompts are large.** Give the local server a context of 32768 or more (Ollama: *Context* in the backend parameters).
- **Small models struggle.** 3B–8B models are weak at agent work; a 30B model on a gateway is the practical minimum.
- **Use a restricted key.** The network LLM key should only allow the models you want, for example no cloud models.
