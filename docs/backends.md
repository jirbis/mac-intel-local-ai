# Installing the backends

You need at least one. The app shows "not installed" next to an option whose binary is missing. You can set every path in the app, so the locations below are only the defaults.

## OllamaGPU

[baksogen/ollama_GPU](https://github.com/baksogen/ollama_GPU) is Ollama with the Vulkan backend and MoltenVK bundled.

1. Download the release.
2. Move `OllamaGPU.app` to `/Applications/Ollama.app`.
3. Open it once, then quit it.

The app runs `/Applications/Ollama.app/Contents/Resources/ollama serve` itself. Don't keep Ollama.app open at the same time, because it starts its own server on the same port. The app warns you when it is open.

This build isn't signed, and it has no visible CI or updates.

## Ollama Vulkan (Momin010)

[Momin010/ollama-vulkan-macos](https://github.com/Momin010/ollama-vulkan-macos) is a maintained Vulkan fork for Intel Macs with AMD GPUs. The app uses the standalone release tarball, not the installer that patches the official Ollama.app.

```sh
mkdir -p ~/Library/"Application Support/Mac Intel Local AI/backends"
tar -xzf ollama-vulkan-macos-*-x86_64.tar.gz -C ~/Library/"Application Support/Mac Intel Local AI/backends"
# → .../backends/ollama-vulkan-macos/ollama
```

Check the tarball against the release's `checksums.txt` first. The app sets `OLLAMA_VULKAN=1` for this option.

## Ollama (Homebrew)

```sh
brew install ollama        # → /usr/local/opt/ollama/bin/ollama
```

This one runs on the CPU only (about 14 tok/s on a 3B model). It is useful as a baseline.

## llama.cpp with Vulkan

```sh
brew install molten-vk vulkan-loader vulkan-headers glslang shaderc cmake
git clone https://github.com/ggml-org/llama.cpp ~/llama.cpp
cd ~/llama.cpp
VULKAN_SDK=/usr/local cmake -B build-vulkan -DGGML_VULKAN=ON -DGGML_METAL=OFF -DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=OFF
cmake --build build-vulkan -j8 --target llama-server
# → ~/llama.cpp/build-vulkan/bin/llama-server
```

The app sets `VK_ICD_FILENAMES=/usr/local/etc/vulkan/icd.d/MoltenVK_icd.json` so the Vulkan loader finds MoltenVK. Device `Vulkan0` is the Radeon. With an iGPU you also get the Intel UHD 630, which is much slower.

llama.cpp doesn't download models. Pick any model you already pulled with Ollama (the app reads `~/.ollama`), or any GGUF file.

## llama.cpp on the CPU

Any `llama-server` build works, for example the default one:

```sh
cd ~/llama.cpp && cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j8 --target llama-server
```

The app runs it with `-dev none -ngl 0`. Don't set all layers on the GPU with a Metal build: Metal on these Radeon GPUs times out or hangs once the whole model is offloaded.

## Custom

Any command that serves either:
- the Ollama API (`/api/chat`, `/api/version`), or
- the OpenAI API (`/v1/chat/completions`, `/v1/models`).

Arguments are split on spaces. Variables are given as `KEY=VALUE` separated by spaces.
