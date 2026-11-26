# Public repository readiness — 2026-11-26

## Verdict
Already public (GitHub metadata), MIT license, development pre-release and basic build/release documentation exist. Suitable for clearly labeled experimental source availability and technical feedback; **not ready for a stable general-user release**. Existing PR #3 contains compatibility and evidence documentation. Keep it open for owner review.

## Evidence reviewed
- Main revision 33e3d7744121bbca6b611864cf0b83971707f4e6: tracked tree, README, backend and benchmark docs, Swift source, build script, CI and license.
- Published dev-45681423489: ZIP and SHA256SUMS present; no independent downloaded binary/physical Mac test in this review.
- Eight main-history commit summaries and initial tree; old Codex router remains in history, though removed from main. A limited pattern scan of the historical router found no obvious credential/private-IP/user-path candidates; **not a complete history secret scan**.
- Wiki enabled in repository metadata; native wiki content/creation unavailable through this connector. Wiki-ready pages are staged under docs/wiki, not published to GitHub Wiki.
- Upstream Hex #953 prior discussions and owner-reported working integration with their Intel build. No fresh physical test, no real screenshots in current tracked tree.

## P0 — before recommending stable binaries or wider promotion
- Safely construct Hex login persistence without interpolating model values into shell code; prefer structured arguments/independent launch commands. Validate arbitrary settings and propagate errors from launchctl, file writes and app restart. Add tests for whitespace/metacharacters and failed writes. Source: useInHex, Swift lines 799–835 at reviewed main.
- Explicit opt-in restart of Hex; never disrupt active dictation or meetings without warning. Implement disconnect/restore of previous environment and remove the app-owned login agent. Check stale values after backend changes, logout/login and uninstall. Report actual success versus configured state.
- Enforce loopback defaults (Ollama extraEnv and llama.cpp extraArgs may override host; custom backend unrestricted by design); warn/block unexpected binds in normal mode and document advanced configuration. Never treat the dummy API key as authentication.
- Prevent secrets in generated plist comments for inactive backends, settings, logs and command preview; avoid treating config as a secret store; use explicit file permissions and redact diagnostic output. Review handling of user-configured executable paths and network redirects/proxies. Do not use imported/untrusted configurations.
- Run full Git history/release/CI secret and privacy scan (e.g. Gitleaks), including deleted Codex integration, archives, tags and release assets. If any credential is found, rotate it and decide remediation separately; deletion from main is not removal from history.
- On physical Intel Mac verify exact downloadable ZIP, checksum, launch, backend switching, actual GPU residency, CPU fallback, Hex end-to-end short dictation, restart/login/disconnect/uninstall and offline behavior. Record exact versions and pass/fail results.

## P1 — public project usability
- Publish the Wiki-ready pages after owner review; add real app and Hex Labs screenshots only after redaction. No fabricated screenshot.
- Clarify this is a controller, not an LLM/ASR engine; narrow claims to reference hardware. The current readme's general Metal/CPU claims are too broad; PR #3 improves the headline; qualify remaining backend claims, API authentication/override warning and Hex fork-only scope.
- Backend docs currently suggest moving OllamaGPU into /Applications/Ollama.app. Prefer distinct install path and configure executable explicitly; avoid overwriting the official app. Recommend verified build provenance and checksums, pin tested revisions, distinguish unsupported third-party binaries.
- Add SECURITY.md, issue templates, contribution policy, expanded .gitignore for local logs/build outputs/credentials, documented supported OS/backend versions; review license notices for every redistributed component (models/backends not currently bundled).
- Add small automated tests for settings/plist/argument parsing and lifecycle/error handling. Preserve merge-only heavy CI policy; separate safe lightweight checks before merge if owner agrees. Verify actual rulesets/permissions, not inferred from workflow. CI source currently pins actions, checks the merged revision and artifact digest, and isolates release write permission.
- Developer ID signing/notarization and stable versioning after real hardware acceptance; document user-specific install and uninstall carefully.

## Scope limits
No claim of vulnerability exploitation, secret-free history, independent release testing, live GPU testing or verified wiki publication. No source changes, merge, stable publication or visibility changes in this documentation review. Owner decides remediation order and release.
