# Getting Started

## Requirements and installation
Intel macOS (x86_64), with an AMD Radeon GPU for experimental Vulkan acceleration. The reference system uses macOS 15; the build target is 13.0, not proof that macOS 13/14 work. Apple Silicon is outside the initial supported scope.

Download the development ZIP and SHA256SUMS from the same [release](https://github.com/jirbis/mac-intel-local-ai/releases). Verify with `shasum -a 256 -c SHA256SUMS`. Unzip and inspect the app. It is ad-hoc signed, not notarized; only use macOS's per-app approval if you trust the source. Do not disable Gatekeeper globally. Alternatively build from source with Command Line Tools and `./build.sh install`; back up an existing app/settings before replacement.

## Configure a backend
Backends and models are not bundled. Follow the [backend installation guide](https://github.com/jirbis/mac-intel-local-ai/blob/main/docs/backends.md). Verify third-party provenance, checksums and licenses; do not replace an existing Ollama installation inadvertently.

1. Start with a CPU backend and an installed small model, e.g. Qwen2.5 3B.
2. Set binary path, model, port and context; apply settings and start the managed server.
3. Verify an actual short response, not just a health indicator.
4. For Radeon, configure a compatible Vulkan backend and inspect model residency and speed. Keep only one model/server in VRAM where possible.
5. Other clients can use the OpenAI-compatible base URL and actual model ID displayed by the app. The [active.json example](https://github.com/jirbis/mac-intel-local-ai/blob/main/examples/active_server.py) documents discovery.

Default endpoints are loopback. A placeholder API key is not authentication. Do not expose unauthenticated servers to the LAN or internet; advanced extra arguments, environment variables and custom commands can override defaults. Do not enter secrets in launch parameters; settings and generated plists are local files, not a secret store.

See [Troubleshooting](Troubleshooting.md) and [Hex Integration](Hex-Integration.md).
