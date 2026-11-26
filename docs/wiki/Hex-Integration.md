# Hex Integration (experimental)

The owner reports that the local LLM integration works with their own Intel Hex build. This is not official upstream support or an independent acceptance test of every feature or downloadable artifact.

- Upstream discussion: [anomalyco/hex#953](https://github.com/anomalyco/hex/issues/953).
- Intel local text processing experiment: [jirbis/hex#4](https://github.com/jirbis/hex/pull/4).
- Speech recognition remains a separate Hex component. The GPU benchmark is for local text generation only.
- The experimental Cleanup and Neutral Voice modes can call an independent Ollama or OpenAI-compatible text server instead of Apple Intelligence. No Vulkan runtime needs to be bundled in Hex for that path.

## Setup on the owner's compatible build
1. Start a known-working local model in Mac Intel Local AI; confirm it responds.
2. Finish any active Hex dictation/meeting before clicking Connect Hex, since it attempts to restart a running Hex or Hex Test instance.
3. Connect Hex sets the endpoint and model in the user launch environment and writes login persistence. Inspect the selected values; restart Hex if necessary. Examples of expected endpoint forms are `http://127.0.0.1:11434/api/chat` and `http://127.0.0.1:8080/v1/chat/completions`.
4. Enable the appropriate local AI Labs feature in the compatible Intel build, try a non-sensitive short dictation, and compare the meaning, numbers and negations with the raw transcript. A configuration indicator alone does not demonstrate end-to-end inference.
5. After changing backend/model, recheck and reconnect. No claim that upstream stock Hex recognizes these variables.

## Known limitations
The current integration needs more robust status reporting, safe login persistence and a disconnect/restore workflow before stable release. The application's API server must stay local. Do not enter unusual/untrusted model names or import arbitrary settings into the current experimental version; use ordinary known model identifiers. Full RU/DE/EN acceptance, failure/fallback and login tests remain open.

Screenshot evidence: not yet available for publication; capture actual backend and Hex Labs screens with personal data, user paths, tokens, private addresses and unrelated windows removed.
