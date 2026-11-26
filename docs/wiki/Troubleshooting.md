# Troubleshooting

- **App blocked by macOS:** the development build is not notarized. Verify checksum/source, use only per-app approval if trusted, or build locally. Do not bypass Gatekeeper globally.
- **Backend missing:** install separately from a verified source, configure its executable and model; the app does not bundle them.
- **Port conflict:** check for an already-running server before starting another. Do not stop an unrelated process or replace its app without consent.
- **Slow model:** compare CPU and full Vulkan offload with the same GGUF, context and thermals; inspect real GPU residency. The tested Radeon Metal full-offload path hung; this is not a universal statement about all versions or GPUs. Partial offload was not beneficial on the reference machine. External displays consume VRAM.
- **Thermal throttling:** record `pmset -g therm`, alternate benchmark order and allow the system to cool. Generation throughput is not end-to-end latency.
- **Hex not using model:** verify a compatible fork build, endpoint, model, actual response, and restart after configuration changes. Avoid interrupting recording. The integration indicator reflects settings, not proof of successful text processing.
- **Uninstall:** follow the current README; ensure only app-owned launch agents are removed and check persisted Hex variables. Preserve models and other clients' settings. A safer automated disconnect/restore flow is a planned fix.
- **Security:** local endpoints are generally unauthenticated; never expose them without a separate authenticated access design. Redact logs, settings, launch parameters and screenshots before sharing. Do not add API secrets in extra arguments or environment fields.

For reports, include app/backend versions, macOS, hardware, model/quantization, reproducible steps, expected/actual behavior and redacted logs. Do not attach raw personal dictations.
