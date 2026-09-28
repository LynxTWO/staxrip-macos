# Existing implementation evidence
Version: 0.1 Draft. Date: 2026-09-28.

Baseline: StaxRip Mac ded2ad344d2512877e5a6cdcbd86a1be5fd0d37e. Bounded Anti-Dark-Code Understand mapping, not a whole-repository audit. Scope: native entry, workspace and operation boundaries, current audio path, publication, existing architecture/release/loudness records, build workflow and retained verification records from implementation. SignalForge has a separate source assessment in SIGNALFORGE-REUSE.md.

| Claim | Kind / confidence | Receipt and limit |
| --- | --- | --- |
| Native UI delegates media work to services | source_fact / verified | Sources app entry, WorkspaceModel, NativeExportService, AudioController and Docs/ARCHITECTURE.md |
| Tool execution passes argument arrays and bounds collected output | source_fact / verified | ToolRunner.swift; not a security guarantee for every decoder input |
| Current mastering uses FFmpeg processing | source_fact / verified | AudioEngine, AudioAudit and LOUDNESS-DESIGN.md; manual speech audit does not drive gain |
| Current exports preserve no-overwrite behavior | observed_behavior / verified for tested cases | Previous debug/release test records; not proof for every filesystem failure |
| Current suite passed on local debug and release builds | observed_behavior / verified | Retained mastering-all-tests.log and mastering-release-stress.log; 38 tests, latter includes eight concurrent cancellation cases |
| Native Night-mode walkthrough produced measured audio | observed_behavior / verified for one generated case | Previous 60-second local fixture: input 16.50 LU LRA; output -18.45 LUFS, 3.80 LU LRA, -2.45 dBTP |
| Hosted macOS workflow works after visibility change | observed_behavior / verified | GitHub run 36378725531 rerun succeeded on 2026-09-28; see SIGNING-AND-CI.md |
| Independent meter and dialogue-aware gain can fit the current service boundary | configured design / inferred | Proposed analysis/report seams; no implementation yet |

Local logs are retained outside Git because environment paths may be private. Hosted receipt is publicly reviewable. Earlier source inspection is reused only at its unchanged baseline; this turn read the app entry, ToolRunner, workflow, source inventory and architecture/release/loudness records. No claim that every source line was reread.

Coverage gaps: official standards fixtures for the future meter, automatic speech identification, full films, multichannel mastering, HDR displays, Intel and oldest supported macOS, notarization and clean-machine install. No runtime guarantee follows from a source fact or test declaration. A skipped test is not measurement evidence.

Publication review before public visibility: 135 unique reachable Git blobs and 11 PR descriptions, plus available PR comments. No binary blobs or matches for selected credential/private-home-path patterns. Pattern checks included positive controls. This was a bounded heuristic scan of fetched history and text, not proof that no sensitive material could exist elsewhere. Ignored local media and build outputs were not published.
