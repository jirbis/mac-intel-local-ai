# BACKLOG — Mac Intel Local AI

## M1 — release evidence and standalone product listing (2026-11-25)
- [x] Confirm existing merged PR #2, successful build/publish run 45681423489 and dev pre-release dev-45681423489 with ZIP and SHA256SUMS assets. No new binary or release published.
- [x] Document reference hardware, unverified configurations, separate backend prerequisites and release smoke-test checklist; expand benchmark reproduction protocol with provenance/thermal/coverage limits.
- [x] MIT declared in repository; distinguish third-party backend/model rights, versions and provenance.
- [ ] Verify the exact downloaded artifact on physical Intel Radeon Mac: checksum, signature, launch, CPU/Vulkan inference, actual residency, switching and local endpoint. Record raw timings and OS/version, no unsupported claims.
- [ ] Owner review of docs; stable release only through approved existing workflow. No merge without owner decision.

## Public readiness — 2026-11-26
- [x] Review current repository, CI and release metadata; prepare [Wiki-ready documentation](docs/wiki/Home.md) and [readiness findings](docs/public-readiness.md).
- [ ] P0: safe Hex login-agent arguments, explicit restart/disconnect/restore, truthful error handling; loopback and config privacy protections.
- [ ] P0: full history/release secret scan and exact downloadable artifact/physical Hex acceptance.
- [ ] P1: real redacted screenshots, native Wiki publication, safe backend install instructions, SECURITY.md and issue templates, regression tests.
- [ ] Owner review before merge or stable publication. Upstream comment attempt to Hex #953 returned 403; manual posting required.
