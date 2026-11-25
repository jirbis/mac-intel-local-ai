# Compatibility and release verification

Status: development pre-release, not stable or notarized. Mac Intel Local AI is a standalone local inference server controller. It does not require any specific chat client, cloud service or other Jirbis product. The app does not bundle backend executables or models.

## Compatibility matrix (2026-11-25)

| Environment | Evidence | Status |
| --- | --- | --- |
| MacBook Pro 16-inch 2019, Intel i9-9880H, AMD Radeon Pro 5500M 8 GB, macOS 15 | Repository benchmark record: Qwen2.5 3B Q4_K_M; Vulkan via MoltenVK and CPU | Reference measurement on one machine; exact downloaded release still needs physical smoke test |
| macOS 15 Intel hosted runner | CI run 45681423489: x86_64 build, plist and ad-hoc signature, packaged checksum and publication | Build verified; no Radeon or GUI inference verification |
| Other Intel Radeon Macs (including other GPU/VRAM combinations) | No representative test record in this repository | Candidate only; verify driver, backend, model fit and thermal behavior |
| macOS 13/14 Intel | Deployment target 13.0 in build.sh, not hardware test evidence | Not validated; backend OS requirements can be stricter |
| Intel integrated graphics | Intel UHD 630 measured much slower than CPU in existing benchmark | Prefer CPU baseline; no GPU acceleration claim |
| Apple Silicon | x86_64 build, not native arm64 | Outside supported product scope |

## Published artifact

- [Development pre-release dev-45681423489](https://github.com/jirbis/mac-intel-local-ai/releases/tag/dev-45681423489), 2026-11-25.
- Built from merged main revision `33e3d7744121bbca6b611864cf0b83971707f4e6`, [PR #2](https://github.com/jirbis/mac-intel-local-ai/pull/2).
- [CI run](https://github.com/jirbis/mac-intel-local-ai/actions/runs/45681423489): build and publish jobs success; build step checked x86_64, plist, bundle version and ad-hoc signature; publication checked SHA-256 manifest and ZIP.
- Published ZIP SHA-256 (GitHub asset metadata): `959d26b3f24eeb05463d4f0354a53003be6ad581de2eecd651a9183f2fe45c4d`.
- Artifact exists; no independent download/hash or target-Mac launch was performed in this M1 documentation review. Ad-hoc signature is not Developer ID signing or notarization.

## Test the exact download on the reference Mac

Use the official repository release, check the source and both assets before opening. Do not disable Gatekeeper globally; if you elect to use an unnotarized release, use the per-app approval described in the README. Back up settings before replacing an installed copy. Do not overwrite models or an unrelated server configuration.

1. Download ZIP and SHA256SUMS from the same release. In that directory run `shasum -a 256 -c SHA256SUMS`; stop on mismatch. Unzip; check `lipo -archs "Mac Intel Local AI.app/Contents/MacOS/MacIntelLocalAI"` and `codesign --verify --deep --strict "Mac Intel Local AI.app"`. Expected x86_64 and successful verification.
2. Record hardware and OS (`sw_vers`, `uname -m`, `system_profiler SPDisplaysDataType`), exact app release and backend versions, chosen model digest/quantization, free VRAM, displays and thermal state.
3. Follow [backend setup](backends.md) after reviewing third-party source, provenance, checksum and compatibility. Backends/models are separately installed; no implied endorsement or redistribution. Select a CPU backend first, confirm server status and an actual short generation. Keep server bound to loopback unless explicitly configuring authenticated network access; do not assume an exposed endpoint has authentication.
4. Select a compatible Vulkan Radeon backend; verify actual GPU residency and short generation, inspect logs and VRAM. Confirm CPU fallback and switching between managed servers, persistence of settings, stop/start and unload behavior. Check that no unintended external server is running; do not terminate unrelated processes.
5. For local endpoint smoke test, inspect active.json, verify its URL is the intended loopback address, then run `python3 examples/active_server.py` from the repo and check advertised model ID. This example checks endpoint availability, not authentication or successful inference. Submit a non-sensitive test prompt through the configured local API. If offline use is required, repeat with network disabled after dependencies/models are available.
6. Run the [benchmark protocol](benchmarks.md) and record actual values, not expectations; record pass/fail/unknown for each step. Optional login restart test only with user approval. Do not claim other hardware, production uptime or speech-recognition acceleration from these tests.

Acceptance evidence: release tag and ZIP hash, OS/GPU/backend/model identifiers, successful CPU and Radeon inference, switching/stop behavior and documented caveats. Any untested step stays UNKNOWN. No stable release until owner approval.
