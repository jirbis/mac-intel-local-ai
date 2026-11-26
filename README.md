# Mac Intel Local AI

A macOS menu bar app that runs a local LLM server on an **Intel Mac with an AMD Radeon GPU** and lets you switch between the ways of running one: Ollama builds with Vulkan, Ollama from Homebrew, llama.cpp with Vulkan or on the CPU, or any command of your own. Every option keeps its own parameters, and the window shows the exact command it will run.

On the reference Intel Mac, full Metal offload in the tested builds hung or timed out. Vulkan through MoltenVK worked and delivered about 3x the CPU generation throughput for the tested 3B model. Other hardware and backend versions need separate verification. This app makes those Vulkan builds easy to run, compare and keep running.

Developed and measured on a MacBook Pro 16" 2019 (i9-9880H, Radeon Pro 5500M 8 GB, macOS 15). The interface is in English by default; switch it to Russian under *Language / Язык* in the settings window.

## What it does

- **Pick a backend**:

  | Option | What runs | API |
  |---|---|---|
  | OllamaGPU | [baksogen/ollama_GPU](https://github.com/baksogen/ollama_GPU) installed as `/Applications/Ollama.app` | Ollama, :11434 |
  | Ollama Vulkan (Momin010) | [Momin010/ollama-vulkan-macos](https://github.com/Momin010/ollama-vulkan-macos) release tarball | Ollama, :11434 |
  | Ollama (brew) | `brew install ollama` (CPU only) | Ollama, :11434 |
  | llama.cpp Vulkan | `llama-server` built with `GGML_VULKAN=ON` | OpenAI, :8080 |
  | llama.cpp CPU | `llama-server -dev none -ngl 0` | OpenAI, :8080 |
  | Custom | any command | Ollama or OpenAI |

- **Edit its parameters.**
  - Ollama: model, `OLLAMA_KEEP_ALIVE`, `OLLAMA_MAX_LOADED_MODELS`, `OLLAMA_CONTEXT_LENGTH`, `OLLAMA_NUM_PARALLEL`, `OLLAMA_FLASH_ATTENTION`, port, binary, models folder and extra variables.
  - llama.cpp: model (any Ollama model from `~/.ollama` or any GGUF), API name (`-a`), device (`-dev`, from `--list-devices`), GPU layers, context, flash attention, port, binary, `VK_ICD_FILENAMES` and extra arguments.
- **One server at a time.** Every option runs under one LaunchAgent, so switching stops the previous server and only one model sits in VRAM.
- **Start at login** (optional), with a restart if the server crashes.
- **Status.** The window shows what is loaded in memory and whether it is fully on the GPU (Ollama `/api/ps`), with an unload button. It also warns you when Ollama.app's own server is open as well.
- **Video memory.** Free and total VRAM of the Radeon, how much the loaded model holds and how much macOS and the displays take (each external display uses some), so you can see what size of model still fits fully on the GPU. `MacIntelLocalAI --vram` prints it in the terminal.
- **Speed test.** Generated and prompt tokens per second.
- **Other tools can find the server.** The app writes `~/Library/Application Support/Mac Intel Local AI/active.json`; see [`examples/active_server.py`](examples/active_server.py).
- **Chat apps.** The window shows the OpenAI-compatible Base URL (`http://127.0.0.1:<port>/v1`), the model name and an API key (any value works) with copy buttons, for Jan, Open WebUI, Msty and similar apps. With a llama.cpp backend it also opens llama-server's built-in chat page.
- **[Hex](https://github.com/jirbis/hex) integration.** Optional: it sets `HEX_LOCAL_AI_ENDPOINT` and `HEX_LOCAL_AI_MODEL` now and at every login.

## Compatibility and release status

The first [development pre-release](https://github.com/jirbis/mac-intel-local-ai/releases/tag/dev-45681423489) is available; it is not a stable or notarized release. The hosted Intel build and package integrity checks passed, while the exact downloadable app still needs a target-Mac smoke test. See [compatibility matrix and release verification](docs/compatibility.md) for tested scope and a reproducible acceptance checklist.

## Documentation

- [Getting started](docs/wiki/Getting-Started.md)
- [Experimental Hex integration](docs/wiki/Hex-Integration.md) — reported working with the owner's Intel fork build, not stock upstream Hex.
- [Troubleshooting](docs/wiki/Troubleshooting.md)
- [Documentation home](docs/wiki/Home.md) (Wiki-ready pages).

The server defaults to loopback; its placeholder API key is not authentication. Custom commands, extra environment variables and arguments can override defaults. Do not expose unauthenticated endpoints or put secrets in launch settings.

## Install

You need the Command Line Tools (`xcode-select --install`). Xcode isn't needed.

```sh
git clone https://github.com/jirbis/mac-intel-local-ai.git
cd mac-intel-local-ai
./build.sh install        # builds and copies "Mac Intel Local AI.app" to ~/Applications and opens it
```

The app is signed ad hoc on your machine. Then install at least one backend: see [docs/backends.md](docs/backends.md).

## CI/CD and releases

GitHub Actions builds the Intel (x86_64) app on macOS 15 using the same `build.sh` as local installations. Heavy jobs run only after a pull request is merged into `main`, not on individual feature-branch commits or unmerged PRs. Direct pushes do not trigger a build.

- **Automatic dev builds:** after a merge, the workflow checks the merged revision, compiles, checks the architecture, validates the bundle and its ad-hoc signature, and publishes a ZIP and SHA-256 checksum as a GitHub pre-release (`dev-<run-id>`).
- **Manual check:** Actions → Intel macOS CI/CD → Run workflow on `main` → `check`. Builds and uploads an artifact without publishing.
- **Stable release:** use the same manual workflow on `main`, select `stable` and enter a new version (`X.Y.Z`). The resulting release uses tag `vX.Y.Z`. Existing tags are not overwritten.

Build and publication are separate jobs: only publication has repository write permission. The ZIP is verified before publication. Build artifacts are retained for seven days; releases remain available under [Releases](https://github.com/jirbis/mac-intel-local-ai/releases).

### Opening a downloaded release

The app is ad-hoc signed, not Apple Developer ID signed or notarized, so macOS blocks the first launch of a downloaded copy ("Apple could not verify ..."). On macOS 15 Control-click → Open no longer bypasses this. To open it:

1. Optionally check the download: run `shasum -a 256 -c SHA256SUMS` in the folder with both files.
2. Unzip `MacIntelLocalAI-macos-x86_64.zip` and move `Mac Intel Local AI.app` to `~/Applications`.
3. Open the app once. When macOS refuses, click **Done**.
4. Open **System Settings → Privacy & Security**, scroll to **Security** and click **Open Anyway** next to "Mac Intel Local AI" (it is listed for about an hour after the attempt). Confirm with your password.

macOS remembers the choice for this copy, so later launches open normally. A newly downloaded release needs the same steps once. If you'd rather not do this, build the app yourself with `./build.sh install`: a locally built app isn't quarantined.

The hosted runner verifies the bundle but cannot validate Vulkan/Radeon performance; test the downloaded app on the target Intel Mac. Local backends and models are not bundled.

## Files it uses

| Path | What |
|---|---|
| `~/Library/Application Support/Mac Intel Local AI/settings.json` | parameters of every backend and the selected one |
| `~/Library/Application Support/Mac Intel Local AI/active.json` | the selected server, for other tools |
| `~/Library/LaunchAgents/com.github.jirbis.mac-intel-local-ai.server.plist` | the server agent (with autostart off it lives in Application Support instead) |
| `~/Library/LaunchAgents/com.github.jirbis.mac-intel-local-ai.hex-env.plist` | Hex variables at login, only after "Connect Hex" |
| `~/Library/Logs/Mac Intel Local AI/server.log` | server output |

The agent plist is generated from the selected backend. It lists the other backends' commands in an XML comment, so you can read every option in one file. To print what the current settings would produce without changing anything, run:

```sh
~/Applications/Mac\ Intel\ Local\ AI.app/Contents/MacOS/MacIntelLocalAI --print-plist
```

## Measured speed

On the Radeon Pro 5500M, qwen2.5:3b Q4_K_M, 200 generated tokens:

| Backend | Generation tok/s |
|---|---|
| OllamaGPU 0.40.10 | 44.8–46.7 |
| Ollama Vulkan (Momin010) v0.32.3-vulkan.1 | 44.0–45.9 |
| llama.cpp Vulkan | 45.9–47.8 |
| llama.cpp CPU / Ollama (brew) | ~14 |

All the GPU options are llama.cpp's Vulkan backend underneath, so they end up equally fast. Details and the throttling caveat: [docs/benchmarks.md](docs/benchmarks.md).

## Uninstall

1. If you installed the Codex router from an earlier version, remove it first, while its copy is still in Application Support. This puts the Codex / ChatGPT app's settings back; without it the app keeps pointing at `127.0.0.1:11500` and none of its models work once the router is gone. Then restart that app.

   ```sh
   /usr/bin/python3 ~/Library/"Application Support/Mac Intel Local AI"/codex_router.py uninstall
   ```

2. In the app, stop the server and turn off "start at login". Then:

   ```sh
   rm -rf ~/Applications/"Mac Intel Local AI.app" ~/Library/"Application Support/Mac Intel Local AI" ~/Library/Logs/"Mac Intel Local AI"
   rm -f ~/Library/LaunchAgents/com.github.jirbis.mac-intel-local-ai.*.plist
   ```

3. The backends (Ollama, llama.cpp) and your models in `~/.ollama` are untouched. Remove them separately if you want.

## License

MIT
