# Mac Intel Local AI

A standalone macOS menu bar application for running and comparing local LLM servers on Intel Macs with AMD Radeon GPUs. It manages existing backend executables and models; it is not an inference engine.

**Status:** experimental development pre-release; see [Releases](https://github.com/jirbis/mac-intel-local-ai/releases). The downloadable build is ad-hoc signed, not notarized. No official Hex affiliation or broad hardware compatibility claim.

## Start here
- [Getting Started](Getting-Started) — installation, backends and first generation.
- [Hex Integration](Hex-Integration) — experimental Intel Hex build and optional local text processing.
- [Troubleshooting](Troubleshooting) — GPU, thermal, server and security checks.
- [Benchmarks](https://github.com/jirbis/mac-intel-local-ai/blob/main/docs/benchmarks.md) — measured results on a single reference Mac.
- [Source and issues](https://github.com/jirbis/mac-intel-local-ai) — MIT-licensed application.

Reference: MacBook Pro 16-inch 2019, Intel i9-9880H, Radeon Pro 5500M 8 GB, macOS 15. Qwen2.5 3B Q4_K_M produced approximately 45–48 generated tokens/s over Vulkan/MoltenVK versus 14–15 on CPU in the documented experiments. These are LLM, not ASR, measurements. Other Macs, operating systems and model architectures require separate testing.

Screenshot placeholders intentionally omitted until real, redacted screenshots of the application and Hex integration are available.
