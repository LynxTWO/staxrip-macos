# Native media workstation architecture

## Current boundaries

The SwiftUI application owns three separate concerns. WorkspaceModel describes intent: source, configuration and queue. SessionDocument serializes validated intent without running it. ExportController and NativeExportService execute one explicitly requested Apple preset export. Quick Export captures its source and preset at launch; it never interprets the advanced queue as an executable plan.

The AppKit player is a view bridge, not an encoding backend. Previewing a source does not apply workspace filters. Temporary export files live beside the requested output so publication stays on one filesystem. A successful hard link is the commit point. Failed publication leaves the old destination alone, and cleanup removes only the operation's temporary directory.

## Next backend boundary

Introduce an immutable EncodePlan produced from a probed source, a user configuration and a capability catalog. Validation must return either a complete plan or actionable unsupported-setting reasons. No silently dropped flags or automatic software/hardware substitution. Each plan includes input identities, selected tracks, filters, rate control, output/container constraints, tool versions and expected verification.

A backend reports capabilities and executes a validated plan. AVFoundation stays one backend; optional trusted external tools become another. A future process runner passes arguments directly through Process, not a shell, drains stdout/stderr concurrently, bounds diagnostics, propagates cancellation and records exit status. Tool discovery and provenance remain separate from job execution.

The queue runner will own explicit pending/running/completed/failed/cancelled/interrupted states. Limit concurrency according to actual CPU/GPU/memory pressure, not a universal fixed job count. Persist transitions transactionally. On restart, interrupted work becomes reviewable and does not silently resume or overwrite outputs.

## Privacy and recovery

No telemetry or media uploads are implemented. Source paths occur in local sessions by design; diagnostic export should redact them by default. Media checks use synthetic fixtures. Existing media is never an encoding destination to replace. More complete crash recovery should record owned temporary paths and verify ownership before any cleanup. Do not clean arbitrary directory prefixes.
