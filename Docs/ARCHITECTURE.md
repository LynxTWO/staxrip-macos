# Native media workstation architecture

## Current boundaries

The SwiftUI application owns three separate concerns. WorkspaceModel describes intent: source, configuration and queue. SessionDocument serializes validated intent without running it. ExportController and NativeExportService execute one explicitly requested Apple preset export. Quick Export captures its source and preset at launch; it never interprets the advanced queue as an executable plan.

The AppKit player is a view bridge, not an encoding backend. Previewing a source does not apply workspace filters. Temporary export files live beside the requested output so publication stays on one filesystem. A successful hard link is the commit point. Failed publication leaves the old destination alone, and cleanup removes only the operation's temporary directory.

## Advanced backend boundary

EncodePlan is immutable and produced from a probed source, a user configuration and a capability catalog. Validation must return either a complete plan or actionable unsupported-setting reasons. No silently dropped flags or automatic software/hardware substitution. Current plans include argument arrays, track counts, rate control, filters and expected codecs/duration. Tool version is displayed by the controller; stronger input identity and provenance records remain future work.

A backend reports capabilities and executes a validated plan. AVFoundation stays one backend; optional trusted external tools become another. ToolRunner passes arguments directly through Process, not a shell, drains stdout/stderr concurrently, bounds diagnostics, propagates cancellation and records exit status. Tool discovery and provenance remain separate from job execution.

BatchController owns pending/inspecting/encoding/verifying/completed/failed/cancelled states and executes one copied configuration at a time. Completed outputs are verified with ffprobe before exclusive publication. BatchJournal checkpoints intent and state transitions atomically to a local file; UI progress ticks are not journal writes. A process-held advisory lock serializes batch writers. Recovery is explicit and converts previously active states to Interrupted. Limit concurrency according to actual CPU/GPU/memory pressure, not a universal fixed job count. Publication and journal completion are separate commits; interrupted restoration never assumes an existing output is safe to replace. On restart, interrupted work becomes reviewable and does not silently resume or overwrite outputs.

## Privacy and recovery

No telemetry or media uploads are implemented. Source paths occur in local sessions by design; diagnostic export should redact them by default. Media checks use synthetic fixtures. Existing media is never an encoding destination to replace. More complete crash recovery should record owned temporary paths and verify ownership before any cleanup. Do not clean arbitrary directory prefixes.

## Audio Lab boundary

AudioController owns an independent source, selected stream index, output recipe and operation task. AudioEngine maps exactly that stream and verifies codec, channel count, sample rate and duration before publication. The first export contract is mono/stereo input; multichannel export is rejected until speaker routing is explicitly modeled. Integer FLAC/WAV output is 24-bit with an explicit sample rate, not a bit-perfect preservation claim. Tags/artwork/chapters are excluded. Source loudness uses FFmpeg loudnorm input statistics; optional normalization measures the converted channel/sample-rate signal, performs a second loudnorm pass, and measures the encoded result before publication. Failed loudness or peak verification removes staging and leaves the destination unpublished. The UI prevents concurrent native, batch and audio exports. Audio Lab intent is not serialized in video sessions yet.

## Ordered caption capture

An EncodeConfiguration exposes a canonical list of up to eight external SRT references, backed by the original first-reference field and an optional additional list. Session version 8 and journal version 7 reject old-envelope/new-field ambiguity. The plan requires snapshots matching every reference in order; it never truncates unmatched lists. Batch execution captures each file again, writes operation-owned SRT and literal title argument files, then independently verifies every added output stream before publication. Native picker callbacks must still match the source and full caption list they opened for. Per-track language/title edits, reorder, replacement and removal retain explicit user intent.

Titles use FFmpeg's file-loaded option argument (`-/metadata:s:s:N`) because Foundation.Process can normalize Unicode argument bytes. Each private, exclusive title file contains at most 1030 bytes of literal UTF-8, including `title=`, without a terminating newline or FFmetadata escaping. The writer settles before cancellation returns and owned staging is removed. Existing automatic retained-stream metadata copying remains unchanged; added-track verification does not certify every embedded track label or player behavior.


D-101 adds a read-only generated-development verifier for prototype original companion
packages. An independent bounded EBML walk locates the original selected TrackEntry;
actual track/configuration, fresh trusted reader audit, ordered packet/RPU index and
archived payload bytes must agree with the supplied source. Before/after content and
filesystem identity checks are observations, not an immutable snapshot. Refusal,
interruption and a bounded helper deadline settle owned processes before returning.
The producer manifest remains unmodified and unbound; a separate result records the
validator boundary. No stable importer, native archive feature, publication, decoded
picture/EL reconstruction, future carriage or signed-distribution admission follows.


D-102 adds a generated-development source-bound companion producer core. It owns
concrete File handles, opens the original source read-only/no-follow, validates
empty distinct regular write-only output descriptors before writing, and compares
source descriptor/path identity after the existing streamed content recheck. One-way
cooperative cancellation checks I/O and final receipt boundaries. Owned handles close
on return; partial files remain owned by the staging caller for settled cleanup.
Source-bound receipts remain separate from unmodified prototype manifests. Trusted
caller exclusive creation, output pathname ownership, semantic disk reread, native
worker/process policy and D-099 publication integration remain required. No new
native CLI command, UI/session schema, decoded/EL admission or dependency follows.


D-103 adds a generated-development writer into a trusted caller's precreated empty
private stage. It pins the immediate parent/stage, creates fixed regular 0600 components
with descriptor-relative exclusive no-follow opens, consumes them through D-102 and
exclusively writes the unchanged prototype manifest after the producer settles. It then
rereads exact disk membership, original created identities and content hashes, retains
read descriptors through final path checks and checks the source identity receipt again.
A staged receipt does not establish independent semantic verification or publication.
The caller creates/owns the stage, joins its worker before cleanup and later supplies
native process/resource policy plus D-101 semantic settlement and D-099 publication.
No directory creation/deletion, native command/UI/session change, decoded/EL conversion,
stable importer, crash durability or hard physical I/O deadline is added. MacOS generated
execution is exercised; Linux conditional compilation is not qualification. See
OWNED-COMPANION-STAGE-EVIDENCE.md.


D-104 adds a separate feature-gated, unbundled development companion writer executable
and an explicit trusted development process caller. The bounded ready/start/staged
protocol correlates an operation; controller-provided source/stage file identities
must match before source component writes. The caller pins source/stage, requires
strict receipt bounds and successful exit, rereads disk members and final identities,
and terminates/joins its owned process before return on refusal/cancellation/deadline.
It never deletes or publishes the stage. Independent D-101 semantic verification and
D-099 exclusive publication remain required. No native caller, bundled reader command,
UI/session change or dependency is added. Process cancellation terminates rather than
cooperatively signalling the core; partial files remain owned by the caller. Generated
checks establish ready-wait cancellation and late-completion refusal, not active physical
copy interruption or native resource/signing/lease policy. See
COMPANION-WRITER-PROCESS-EVIDENCE.md.


D-105 adds an unused internal Swift original-companion transaction coordinator. It pins
source identity, owns a unique private stage, awaits trusted settled producer and
independent semantic phases, validates matching bounded source/stage/member receipts,
and rechecks source identity immediately before exclusive publication. Cancel/refusal
awaits phase settlement before owned cleanup; a substituted stage yields a reviewable
cleanup error without recursive deletion. An admitted commit reports its actual outcome
including late cancellation. Trusted callbacks must settle their workers and supply true
receipts; no runtime validator or native writer is installed. A test-only adapter runs
the actual development writer and independent checker on generated fixtures through
native publication. Native lease/provenance/resource/signing, owner review, stable import,
crash/storage and decoded association remain gates. See
COMPANION-TRANSACTION-SETTLEMENT-EVIDENCE.md.


D-106 adds an unused strict native CompanionWriterProtocol parser before process
integration. Single-owner bounded ready/start/staged state requires expected operation,
retention, captured source/stage IDs and source size, fixed component limits, resource
bounds and no claimed semantic verification. Its private ASCII JSON subset rejects
duplicate/unknown keys, escapes, unsupported numbers, oversized/deep collections and
trailing/incomplete/nonzero results. The controller declares joined EOF/status through
finish; this parser cannot establish process/pipe settlement, executable provenance,
source/disk hashes or original semantics. Generated tests admit actual unbundled writer
stdout in both modes and compare receipt observations with disk; Python capture is
explicitly test-only. No app writer action/packaging or native bridge exists. See
NATIVE-COMPANION-PROTOCOL-EVIDENCE.md.
