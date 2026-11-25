# Benchmarks

MacBook Pro 16" 2019: i9-9880H, AMD Radeon Pro 5500M 8 GB, macOS 15. Model: qwen2.5:3b Q4_K_M (1.8 GiB), the same GGUF file for every row.

## Servers (2026-11-25)

Each server generated 200 tokens at temperature 0. Each value is the median of 3 runs; each server ran two rounds. Every run was taken with `pmset -g therm` reporting `CPU_Speed_Limit = 100`.

| Server | Generation tok/s |
|---|---|
| OllamaGPU 0.40.10 | 46.7 / 44.8 |
| Ollama Vulkan (Momin010) v0.32.3-vulkan.1 | 45.9 / 45.4 (44.0 in a later check) |
| llama.cpp Vulkan | 45.9 / 47.8 |
| llama.cpp CPU (`-dev none -ngl 0`) | 14.6 |

The three GPU servers are equally fast within noise. They all run llama.cpp's Vulkan backend.

## llama.cpp backends (llama-bench)

Prompt 128, generation 128, batch/ubatch 128, 8 threads, flash attention off, median of 3, machine load under 3.

| Backend | GPU layers | Prompt t/s | Generation t/s |
|---|---|---|---|
| CPU (BLAS) | 0 | 85.7 / 94.8 | 13.7 / 14.2 |
| Metal | 0 | 93.1 | 14.5 |
| Metal | 4 | 34.4 | 7.3 |
| Metal | 99 | fails (GPU timeout / hang) | – |
| Vulkan Radeon | 0 | 36.4 | 13.4 |
| Vulkan Radeon | 4 | 38.8 | 12.0 |
| Vulkan Radeon | 12 | 50.1 | 14.8 |
| **Vulkan Radeon** | **99 (all)** | **373.6 / 374.7** | **47.4 / 46.8** |
| Vulkan Intel UHD 630 | 99 | 6.7 | 4.2 |

- **Full offload is what makes the GPU worth it.** It is about 3.3x the CPU on generation and 4x on prompt processing.
- **Partial offload doesn't help.** Use either 0 layers or all of them.

## Caveats

- **Throttling.** This laptop throttles hard. With `CPU_Speed_Limit` at 22–35, the GPU fell to 15–35 tok/s, and whichever server ran first "won". Only compare runs taken at 100.
- **Flash attention.** It isn't supported by Vulkan through MoltenVK on this GPU. With `auto`, llama.cpp reports "Flash Attention not supported, set to disabled", and attention still runs on the GPU the regular way.
- **One model at a time.** Each loaded 3B model holds about 2.2 GB of VRAM, so run only one server with a model loaded. The app enforces that by running every backend under one LaunchAgent.
