# Slice 049: Measured dynamic HDR conversion
Version: 0.1. Date: 2026-10-03. Status: native encoded inspection, editable HEVC VBV and development base-frame association locally qualified; bounded encoder feasibility recorded; no new Dolby Vision conversion admission.

## Outcome and authority

The owner explicitly prioritizes a proper dynamic-HDR workflow over the parked timing investigation. Existing refusal remains until a conversion path is qualified. Preserve original signal, compatible Dolby Vision re-encoding, HDR10 fallback extraction, enhancement reconstruction and newly authored HDR10+ are separate intents with explicit information consequences. Never silently discard enhancement data or claim metadata equivalence from color tags.

D-091 / R-059 authorizes local read-only complete RPU analysis of the existing private source, owned research outputs, tool feasibility/license review and generated workflow qualification under the owner's standing autonomous development delegation. Private source names/paths/content and credentials stay out of code/public evidence. No owner queue execution or full-film encode, listening, persistent security settings, merge or release. Cancellation/publication limits and source/prior-output protections remain unchanged. D-090 is complete and parked; no further timing observation is included.

Need: the current Profile 7 declaration cannot classify its enhancement processing requirements, and the generic transcode refusal leaves no qualified path. Consequence: user_data if conversion drops picture information or attaches incorrect metadata; read-only analysis itself is local_only. Existing strict refusal and complete packet/header preservation work are controls, not obstacles to bypass.

## Bounded build sequence

M1: Pin tool versions/source identities and licenses. Parse the complete original RPU sequence, checking count, validity, MEL/FEL/subprofile changes, scene/active-area/color metadata and dependencies. Cross-check packet/RPU counts with existing independent full-film evidence. Preserve failures and source/recovery protection. Sampling does not classify the whole film. Outputs stay private; no payload or filename in public evidence.

M2: Evaluate actual macOS enhancement reconstruction before choosing the highest-information re-encode. A developer README claim does not qualify a decoder. For FEL, prove base/enhancement/RPU frame association, expected precision/geometry/chroma, signed residual handling and reference parity. For MEL or compatible single-layer sources, qualify complete RPU alignment and supported x265 integration. Distinguish rendering reconstruction from display-management trims and output metadata authoring. Do not assume original metadata remains correct after arbitrary crop/resize/cadence/trim or tone mapping.

M3: Implement only a measured feasible contract with explicit saved intent and native review. Existing SDR/static HDR10 modes retain their boundaries. Preserve unqualified alternatives as detailed refusals. HEVC Dolby Vision, AV1/HDR10 and newly derived HDR10+ require separate codec/profile/container and metadata acceptance. HDR10+ authoring analyzes resulting pictures; no one-to-one Dolby metadata translation is assumed.

M4: Actual generated queue execution, complete output metadata/frame/timing comparison, refusal mutations, cancellation and exclusive publication, native reviewed walkthrough, ordinary local regression/build. Hosted timing reliability remains a separate recorded open qualification; a new HDR implementation is not a timing repair. Private licensed real-source qualification remains local with owner state restored. Calibrated reference viewing/player validation and parked audio listening remain explicit limits.

## Feasibility candidates

Owner clarification: both original preservation and conversion choices are required. Compatible HEVC uses Profile 8.1; AV1 uses Profile 10, not an HEVC profile label. An optional companion archive must retain original RPU and enhancement data, original frame/timing association, configuration and integrity checks independently of the destination format. A metadata-only file cannot preserve FEL picture residuals. Reattachment after picture/timing edits requires a separately qualified transformation; archiving is not playback or future compatibility certification. Publish the media and archive as an explicit, collision-safe result set; never silently omit a requested companion.

Owner additionally requests editable, prefilled VBV suggestions. Implement a bounded software-HEVC control first: source/output raster and declared cadence choose a candidate HEVC level, with Main tier for compatibility or High tier for more bitrate headroom. Suggested peak and buffer limits remain distinct from manual values, persist through sessions/queue/presets and are applied by the encoder. Report that tight VBV can lower quality. Future Dolby Vision admission must also check its own level limits; generic HEVC suggestions do not certify Dolby Vision conformance. Existing sessions keep unrestricted defaults.

- dovi_tool (MIT, locally installed development tool): complete RPU analysis/conversion, not a FEL picture decoder. Mode 2 removes Profile 7 FEL mapping; discard removes enhancement. These are disclosed transformations, never full-signal preservation.
- x265: documented supported single-layer profiles and RPU input; CLI/API integration must be tested with the installed build rather than assumed from option names.
- libplacebo: applies decoded frame RPU metadata and removes it from output; this does not by itself prove enhancement reconstruction. The installed FFmpeg lacks this filter.
- FelBaker/DoViBaker: evaluate pinned source, license, macOS build, precision, synchronization and reconstruction evidence before integration. No unreviewed executable or new bundled dependency.

## Picture-edit contract

Owner explicitly includes crop and resize. Preserve the untouched original RPU/EL separately. An edit manifest must record coded raster and codec conformance-window removal, decoded raster, container crop/display units, rotation/orientation, original/output sample aspect, chroma siting and resampling, effective pixel crop rectangle with integer coordinates, padding, resize kernel/dimensions and original/output frame mapping/timestamps. Keep decoder, container, user crop and Dolby active-area coordinate systems explicit; do not subtract the same crop twice. RPU Level 5 coordinates must be transformed into the output raster with validated bounds and deliberate rounding consistent with subsampling; reject ambiguous active-area mapping. Actual picture edits may change content statistics (Level 1 and MaxCLL/MaxFALL), while target-display trims represent artistic intent and are not automatically interchangeable with new HDR10+ authoring. Do not blindly reuse the original RPU after crop, scale, color/gamut/tone mapping, deinterlace, cadence edits or trimming. Initially qualify unchanged geometry and cadence; keep edited dynamic HDR refused until actual transformed metadata and picture evidence exists. Retaining an archive does not make the edited media equivalent to the original master.

## Gates

| Gate | Required evidence |
| --- | --- |
| dovi-source | Complete validated source RPU census, independent counts and protected source/journal |
| conversion-feasibility | Pinned capability/license facts plus actual generated and bounded private reconstruction/encoding results; losses explicit |
| conversion-contract | Typed intent, supported profile/metadata/geometry bounds and no silent fallback |
| conversion-output | Complete actual output metadata/frame/timing checks and mutations/refusal/settled cancellation |
| conversion-native | Native reviewed choice and result; correct losses/readiness labels |
| conversion-regression | Appropriate focused, ordinary local/build and explicit hosted-status record |

Primary references: [dovi_tool](https://github.com/quietvoid/dovi_tool), [x265 options](https://x265.readthedocs.io/en/master/cli.html), [FFmpeg libplacebo](https://ffmpeg.org/ffmpeg-filters.html#libplacebo), [FelBaker](https://github.com/bbeny123/felbaker), [DoViBaker](https://github.com/erazortt/DoViBaker).

## Companion package detail

Provide a lightweight original-metadata archive and a complete original-video archive with explicit storage estimates and information differences. When enhancement residuals are present, RPU plus EL alone is not a complete master: the residual belongs to its matching original base picture, and a newly compressed base cannot be assumed interchangeable. Complete preservation therefore retains the matching original encoded BL as well, plus EL/RPU/configuration and packet/frame timeline. For unsupported destination carriage, an archive saves recoverable source material; it does not turn that destination into a Dolby Vision bitstream. Never mark an HDR-only video as Dolby Vision just because a companion exists.

A result directory containing media, companion and manifest can be published with one exclusive directory operation; two independent file renames cannot be advertised as an atomic set. Design the destination review around this package when archival is requested, retain existing flat-file behavior otherwise, preflight space for original-video plus staged media, and verify all requested components before publication. Collision, cancellation or verification failure must leave no partial success claim or overwrite. Original and transformed metadata belong in separately identified components with independent integrity checks.

Source/encoder research: DYNAMIC-HDR-FEASIBILITY-EVIDENCE.md. Implemented VBV prerequisite: HEVC-BUFFER-LIMITS-EVIDENCE.md. Source metadata counts and bounded semantic preservation do not close complete runtime conversion, original preservation, companion publication, picture edits or calibrated rendering gates.

D-093 adds a locally qualified development-only bounded RPU archive reader. BOUNDED-DOLBY-READER-EVIDENCE.md records generated failures and the full original archive comparison. This closes an archive-read prerequisite only; native integration, container extraction completeness, frame mapping and edited-picture qualification remain open.


D-094 adds a development-only bounded Matroska HEVC packet reader with signed timestamps, duplicate-preserving RPU association and strict read failure boundaries. BOUNDED-MATROSKA-DOLBY-EVIDENCE.md records generated FFprobe comparisons and complete private source agreement. This is an extraction/association prerequisite, not native admission, decoded-frame/POC qualification, crop/resize validity or rendering. Presentation-order archives and decoding-order packets must remain distinct in edit manifests.


D-095 admits a fixed bundled read-only native Matroska HEVC inspector with protocol 3,
complete encoded-packet/hash/timestamp proof, selected configuration agreement and a
final source fingerprint. The active-area UI explicitly separates container crop,
display units and Level 5 luma offsets. Generated protocol/lifecycle/actual helper
checks, ordinary regression, licensed nested-helper build and a focused native
walkthrough are the required boundary; evidence is recorded separately. This does
not close conversion, decoded-picture/POC, brightness, archive publication,
crop/resize, rendering or hosted timing-reliability gates.

D-096 adds a separate unbundled installed-FFmpeg base-picture reference with raw RPU
digests, original packet provenance and unapplied codec conformance cropping. A
bounded on-disk checker requires packet/raw-buffer agreement and complete one-to-one
coverage, rather than infer it from PTS sorting or opaque propagation alone. Generated
codec cropping, B-frame reorder, surplus/missing RPU and CRA/nonoutput cases precede
private complete-source verification. DECODED-DOLBY-ASSOCIATION-EVIDENCE.md records
the outcome and scope; original EL pairing, general POC mapping and runtime conversion
remain separate gates.

## Edited-picture analysis prerequisites

D-097 qualifies a compatible development dependency before native decoded-frame
integration. The first private dependency inherited a macOS 27 minimum; the rebuilt
candidate and development reference explicitly target macOS 14. Generated and
relocated development checks pass. Complete compatible source association passed;
Developer ID hardened loading and native resource/ownership integration stay open.
MINIMAL-DECODER-RUNTIME-EVIDENCE.md records the bounded effect and failures. No native
conversion, edit or new dependency is admitted by these observations.

Dolby's creation guidance specifies the active image before analysis, permits it to
vary by shot and distinguishes measured L1 analysis from artistic target trims.
MaxCLL/MaxFALL normally require separate calculation. Therefore removing only verified
blanking might preserve the analyzed picture region, but removing active content or
resampling it cannot be assumed to preserve those values. That distinction is a
design inference requiring resulting-picture checks, not a generic metadata rewrite.
See [Dolby active-image guidance](https://professionalsupport.dolby.com/s/article/Dolby-Vision-Content-Creation-Best-Practices-Guide?language=en_US)
and [metadata levels](https://professionalsupport.dolby.com/s/article/Dolby-Vision-Metadata-Levels?language=en_US).

For a later edited workflow, declare the source active-area coordinate basis before
transforming it. Bind every per-picture/shot region to the verified timeline; intersect
it with the effective crop, translate, then apply the same rational scale/padding and
explicit integer-edge rounding used by the picture pipeline. Refuse empty/ambiguous
regions, unresolved orientation and changing geometry. Odd luma metadata coordinates
remain valid; chroma sample alignment and the actual pixel crop/resampling policy are
separate decisions. Container display ratios do not substitute for sample dimensions.

The edit record must retain kernel, chroma siting, border treatment, sample aspect,
bit depth and color/transfer/range. Verify active-area bounds and sample actual edited
pictures with correct transfer/color handling; resampling can change peaks and mix
blanking near boundaries. Do not multiply brightness by the area ratio or relabel
original L1 as newly measured HDR10+ statistics. Burned-in subtitles/graphics are
picture edits too; variable aspect scenes cannot be collapsed to one global crop.
Preserve original metadata and matching original BL/EL independently of all transformed
results. Decoder conformance cropping, crop-only blanking removal, active-picture crop,
down/upscale, padding, subtitle overlays and variable-aspect sequences need separate
generated/output/reference tests before a native edited-Dolby choice is enabled.


D-098 implements only an internal geometry proposal seam. Explicit coded/codec/
container/decoder bases, composite crop, rational scale/padding and sample shape are
validated. Integer proposals refuse fractional edges; clipping/resizing facts do not
qualify original analysis values. Generated actual luma-grid and ordinary app checks
are required. Per-picture association, physical color/chroma/brightness, general
rounding/resampling and metadata authoring still precede any native edited admission.
See DOLBY-EDIT-GEOMETRY-EVIDENCE.md. Source/session/queue and parked listening remain
protected; no conversion/archive or signed-distribution qualification is inferred.


D-099 selects the original-companion publication prerequisite: a private owned result
stage, exact requested member size/hash checks and one same-parent exclusive directory
rename. Generated refusal/cancel/cleanup/competition checks plus ordinary regression
and build qualify the primitive only. Existing flat exports and dynamic-HDR refusal
remain unchanged. Archive writers, original BL/EL/RPU/configuration/timeline semantics,
space estimates, result review and signed distribution remain unimplemented gates.

Approved for build by: owner standing autonomous delegation, 2026-10-04, limited to
D-099's generated internal publication prerequisite. No owner archive write or native
companion execution is authorized by this build checkpoint.


D-099's internal publication prerequisite passed focused generated filesystem cases,
331-test ordinary local regression and optimized development build/signature checks.
RESULT-SET-PUBLICATION-EVIDENCE.md scopes the observed content/ownership outcomes. No
archive writer, native choice, HDR semantic admission or production completion follows.


D-100 selects a generated development producer for exact original RPU/configuration
and encoded packet association components. Metadata-only excludes picture residuals;
complete retention preserves the entire original container, explicitly including other
tracks/metadata. The native CLI stays read-only, protocol unchanged. Content recheck
and writer receipts precede a development manifest; source path identity, native consent,
decoded associations, importer and publication integration stay open.
Approved for build by: owner standing autonomous delegation, 2026-10-04, D-100's
generated development-only original component producer. No owner archive write.


D-100's generated producer passed exact original component/association checks, 24 Rust
and 15 decoded-reference tests, ordinary 331-test app regression and optimized bundle
checks. ORIGINAL-COMPANION-PRODUCER-EVIDENCE.md states metadata-only losses and whole-
container retention costs. Native source identity/cancellation/review, semantic reread,
result publication/import integration and signed distribution remain open. No native
archive choice or dynamic-HDR conversion is admitted by this library prerequisite.


## D-101: Independently validate original companion components against source
Date: 2026-10-04
Status: Confirmed

Authority: original archival request, standing autonomous delegation and R-059 /
Slice 049. Generated development fixtures only, no owner archive/encode/queue, native
choice/importer, stable public format, listening, signing retry, merge or release.
Choice delegated to AI. Historical timing investigation remains completed and parked.

Need: producer hashes cannot establish that a manifest, raw TrackEntry/configuration,
RPU archive and packet index describe the same source. Build a standalone development
validator that safely opens an exact prototype component set, checks actual size/hash,
locates the selected original TrackEntry independently, and compares a fresh fixed
reader audit with the stored ordered source audit/index/RPU bytes. Preserve duplicates
and signed PTS; no uniqueness or one-RPU-per-frame assumption.

Bind original regular-file path/descriptor/content identity at before/after boundaries;
recheck package identities after semantic verification. Do not advertise an immutable
snapshot or protection from adversarial same-user writers. Full container bytes must
match the original content identity. Keep manifest pathname/decoded flags unchanged;
a separate verification result records its narrower observed identity binding.

Acceptance: both retention modes, actual generated packages, component corruption and
self-consistent forged manifest/index/configuration/track/count/flags/timing refusals;
unsafe paths/links/special entries, source replacement/mutation and failed/incomplete/
bounded helper settlement refuse. Source and prior outputs stay unchanged. A new
120-second generated-development helper bound and owned process cleanup are limited
to this semantic validator, not a historical cancellation observer or relaxed deadline.
No native admission follows; original BL/EL reconstruction, decoded mapping, storage
review, stable importer and D-099 publication integration remain later prerequisites.

Approved for build by: owner standing autonomous delegation, 2026-10-04; bounded generated development prerequisite only.


D-101 outcome: final generated companion suite passed 17 checks in 2.025 s without
resource warnings; 24 Rust tests, format and Clippy plus 15 existing decoder-reference
checks passed. Ordinary app regression passed 331 tests/78 suites in 202.422 s.
Optimized build and strict ad-hoc app/helper signatures passed; actual minimum
macOS declarations remain 14.0/11.0, not older-OS execution qualification. Independent
configuration location, fresh source audit, exact duplicate-preserving encoded RPU
relationships and observed source/package identity checks are qualified in generated
scope. ORIGINAL-COMPANION-VALIDATION-EVIDENCE.md retains limits and cleanup repair.
Source/current recovery unchanged; scoped privacy scan has zero owner identifier hits.
No owner archive, native command/protocol/UI admission, listening, dependency bundling,
signing retry, merge or release. PR 75 automatic AV1 deadline failure retained.
Native producer ownership/cancellation, semantic settlement and D-099 publication
integration remain the next prerequisites; prototype import/reconstruction is open.


## D-102: Own a source-bound cancellable companion producer
Date: 2026-10-04
Status: Confirmed

Authority: owner original preservation/companion request, standing autonomous
delegation and R-059 / Slice 049. Build a generated-development prerequisite only;
no owner archive/queue/full-film encode, native command/UI or stable importer,
listening, decoder integration, signing retry, merge or release.

Product contract: the future owner chooses metadata-only or complete retention and
reviews its storage/privacy consequences. Before any result can be published, the
producer must bind the opened original source, preserve its bytes and settle all
owned writes when cancelled or refused. This unit tests that core on disposable
files; consequence local_only for execution, user_data for future native integration.
The authoritative outcome is a returned source-bound receipt, not a partial audit's
complete row or the mere presence of component files.

Choice delegated to AI. Alternatives: add a native writer command now, rely only on
caller-owned writers, or first add an internal source-bound producer owning File
handles. Select owned handles first: closes actual writes at return and permits
source/cancel qualification without changing the read-only bundled CLI or exposing
an unreviewed prototype format. Cost: caller must create exclusive staged files and
later validate their path identity/semantics before D-099 publication.

Scope: no-follow/nonblocking regular source open, length and descriptor/path identity
before/after the existing streamed content recheck. Consume concrete File outputs;
refuse nonempty, linked, duplicate, nonregular, read/write or source-alias descriptors
before writing. A one-way cancellation token checks read/seek/write/flush boundaries
and the final receipt boundary. Owned source/component handles close on every return.
No shell, new dependency, executable or API/session schema is added. Original producer
manifest flags remain unmodified; a separate receipt records narrower source binding.

Acceptance: generated both-mode bytes pass existing independent semantic verifier;
real source replacement/mutation and symlink/FIFO/directory/empty/oversize refuse;
cancellation before work and during actual producer/recheck/write/flush refuses with
no source-bound receipt. A generated owned worker cancels and joins before cleanup.
Output descriptor errors/aliases/collisions preserve existing data. No hard physical
I/O/CPU deadline, immutable snapshot, durability, source ancestry sandbox or protection
from a malicious caller cloning descriptors is claimed. Native process ownership,
output path binding, semantic settlement, publication and storage/crash review remain
next gates. Historical D-090 timing assertions/observation remain unchanged.

Approved for build by: owner standing autonomous delegation, 2026-10-04; this bounded
source-bound producer prerequisite falls inside the authorized archival work.


D-102 outcome: source-bound generated producer checks and descriptor settlement
passed. Final Rust run passed 31 tests with zero failures/ignored tests; format/Clippy
passed. Eighteen independent companion checks passed in 3.032 s and fifteen existing
decoder-reference checks passed in 1.107 s. Ordinary regression passed 331 tests/
78 suites in 203.087 s; optimized build/strict ad-hoc app/helper signatures passed.
Actual app/helper minimum declarations remain 14.0/11.0, not older-OS execution or
notarization. SOURCE-BOUND-COMPANION-EVIDENCE.md records scoped source identity,
cooperative cancellation, unsafe descriptor refusals, partial-component behavior and
ownership limits. Original source/current recovery unchanged; privacy scan of eleven
changed/nonignored files has zero owner identifier matches and a positive sentinel.
No native command/protocol/UI/session or dependency changed; no owner archive/queue/
encode/listening, signing retry, merge or release. PR 76 automatic reader/app passed
without retry; prior timing failure causes remain unknown. Native stage/path ownership,
semantic settlement, worker/process integration and D-099 publication remain next.


## D-103: Bind exclusive companion component creation to an owned stage
Date: 2026-10-04
Status: Confirmed

Authority: owner original preservation/companion request, standing autonomous
delegation and R-059 / Slice 049. Generated development operation only; no owner
archive/queue/full-film encode, native command/UI/importer, decoder integration,
listening, signing retry, merge or release.

Need/product contract: the future owner chooses retention and reviews storage/privacy.
Source-bound File ownership alone cannot establish that components belong to the
caller-owned stage or that their settled disk bytes match the producer receipts.
Before independent semantic verification and publication, exclusive fixed-name files,
stage/parent identity and actual content must agree. Partial components never become
success from file presence. Consequence local_only for generated execution; user_data
for later native integration. Caller owns cleanup only after producers settle.

Choice delegated to AI. Alternatives: expose a writer command now; duplicate native
stage creation/cleanup in Rust; or first add descriptor-relative production inside a
trusted caller's existing stage. Select the last option. The native D-099 factory
already owns stage creation, and delaying a command avoids exposing a prototype before
its stage binding is qualified. Cost: this core does not prove caller creation history
or create/remove/publish a directory; native process and stage ownership remain later.

Scope: pin a caller-supplied empty private 0700 regular directory and its parent with
no-follow opens. Create only fixed components with descriptor-relative exclusive 0600
regular-file opens. Record created identities; pass consumed File handles to D-102.
Write the unchanged prototype manifest exclusively after producer settlement. Reopen
all actual components read-only/no-follow, check membership, identities, bounds/hashes
and final path/descriptor/source-receipt observations. Return a staged receipt, never
publication. Cancellation checks stage/file creation, manifest write and disk reread;
no hard physical I/O deadline or immutable snapshot is claimed.

Acceptance: generated both-mode packages pass the independent semantic verifier;
preexisting directories/components remain untouched on refusal; unsafe stage paths/
permissions/entries, partial creation, links/substitutions, extra/missing/corrupt
components, source change and cancellation refuse. A bounded generated worker joins
before caller cleanup. Errors leave staged files for caller review and close owned handles.
No recursive or automatic cleanup, arbitrary manifest-directed paths, stable importer,
future carriage, decoded/EL reconstruction or archive-specific crash/durability claim.
Historical D-090 timing work stays completed without retry/observer/deadline change.

Approved for build by: owner standing autonomous delegation, 2026-10-04; bounded
stage/path prerequisite inside the authorized original archival work.


D-103 outcome: generated stage ownership and settled disk receipt checks passed.
Rust passed 38 tests with zero failures/ignored; format/Clippy passed. Independent
companion verification passed 19 checks in 3.613 s; existing decoder reference passed
15 checks in 1.145 s. Ordinary app regression passed 331 tests/78 suites in 202.252 s;
optimized build/strict ad-hoc app/helper signatures passed. Actual minimum declarations
remain 14.0/11.0, not older-OS execution or hardened/notarized evidence. Source/current
recovery unchanged; fifteen-file scoped privacy scan has zero owner identifier matches
and a positive sentinel; planning audit has no findings. Evidence is recorded in
OWNED-COMPANION-STAGE-EVIDENCE.md. The stage writer is development-library-only and
returns no receipt for generated collision/link/substitution/corruption/source-change/
cancellation faults. The prototype manifest is unchanged and unbound; caller stage
creation history, worker join and semantic/publication integration remain obligations.
No native command/protocol/UI/session/dependency changed, owner queue/archive/encode/
listening, signing retry, merge or release. PR 77 automatic reader/app both passed
without retry; prior hosted failure causes remain unknown. Next bounded prerequisite:
trusted native writer process/worker lifecycle, then semantic settlement and D-099
exclusive result-set publication. Native storage/privacy review, stable importer,
archive-specific ENOSPC/volume/crash and decoded association remain separate gates.


## D-104: Qualify a separate development companion writer process
Date: 2026-10-04
Status: Confirmed

Authority: owner original preservation/companion request and standing autonomous
R-059 / Slice 049 delegation. Generated execution only; no owner archive/queue/full-film
encode, native caller/UI, merge/release, signing retry or parked listening.

Need/product contract: a future native operation must own actual writer execution,
reject late/partial completion and settle processes before caller cleanup. Library
ownership cannot establish that boundary across a process. Consequence local_only for
this generated development unit, user_data for later native integration. Retention
loss/storage/privacy review remains required before exposing a native archive action.

Choice delegated to AI. Alternatives: add a writing command to the bundled read-only
reader now; launch Rust through a shell; or first qualify a separate feature-gated
unbundled development executable and an explicit trusted development process caller.
Select the last option. No shell, dependency or bundled helper command change. Cost:
this does not qualify native signing, security-scope leases or controller integration.

Scope: fixed metadata/full choices, opaque operation correlation ID, bounded ready/
start/staged protocol and existing tracked Rust heap limit. Start is an internal
controller handshake, not an owner approval flow. Invoke D-103; completion describes
actual staged members and source/stage file identities, not semantic/import approval.
Prototype manifest remains unchanged. Parent pins source/stage, validates correlation,
strict schema/limits and exit zero, rereads actual members and final identity boundaries.
Parent cancellation/deadline kills its owned group and joins/closes direct process and
pipes before return; no automatic directory cleanup/publication. In-process core
cancellation remains cooperative; cross-process interruption is termination, with
partial files allowed and no receipt admitted after cancellation. No physical I/O
preemption or portable join of orphan descendants is claimed.

Acceptance: both real executable modes pass independent semantic verification on
generated sources. Wrong/oversize start, EOF, invalid mode/ID/args and unsafe/preexisting
stage/source refuse; no source/old entry replacement. Controlled ready-wait cancellation
settles actual child before cleanup. Nonzero exit, stale/malformed/extra/duplicate/
unbounded receipts, deadline/pipe-holding child and interruption refuse and settle.
Current read-only CLI/default build remains unchanged; no automatic fixture pause hook.
Historical D-090 timing remains completed with no observer/retry/assertion change.

Approved for build by: owner standing autonomous delegation, 2026-10-04; bounded
writer-process prerequisite within authorized original archival development.


D-104 outcome: separate unbundled development writer/process checks passed. All-feature
Rust passed 40 tests with zero failures/ignored; format/Clippy passed. Eleven actual/
surrogate process checks passed in 2.338 s, nineteen independent companion checks in
14.369 s and fifteen existing decoder-reference checks in 1.216 s, without resource
warnings. Ordinary app regression passed 331 tests/78 suites in 204.552 s; optimized
build and strict ad-hoc app/helper signatures passed. Actual minimum declarations remain
14.0/11.0; the writer is absent from the native bundle. No older-OS/hardened/notarized
claim follows. COMPANION-WRITER-PROCESS-EVIDENCE.md records before-write caller IDs,
bounded protocol/heap, strict disk/result admission, cancelled/late/nonzero refusal,
monitor/reaping ordering repair and joined direct children/pipes. Ready-wait and late
cancellation were observed; active physical-copy interruption remains unqualified.
Original source/current recovery unchanged; scoped privacy/planning checks passed.
No native command/UI/session/dependency, owner queue/archive/encode/listening, signing
retry, merge or release. PR 78 automatic reader passed; app failed the retained existing
AV1 deadline 132.370 s against 120 s, with no rerun/observer/assertion change. Next:
independent semantic settlement and D-099 exclusive publication joined to writer/native
worker ownership. Native review/lease/resource/signing, persisted execution binding,
stable import, storage/crash and decoded association remain separate qualification.


## D-105: Settle original companion phases before exclusive publication
Date: 2026-10-04
Status: Confirmed

Authority: owner original-preservation/companion request, R-059 / Slice 049 and standing
autonomous delegation. Generated native internal ownership unit only; no owner archive/
queue/full-film encode, native action or writer packaging, signing retry, merge/release
or parked listening. Consequence local_only now, user_data for later native exposure.

Need/product contract: the future owner chooses retention and reviews storage/privacy.
A stage must remain private until its producer and independent semantic verifier have
settled and agree about actual source, retention and disk members. Cancellation must
join phases before cleanup; an admitted publication reports the actual syscall outcome.
A failed cleanup needs an explicit retained-stage error, not silent success or recursion.

Choice delegated to AI. Alternatives: expose the archive UI now; duplicate a Python
publication primitive; or add an internal Swift transaction coordinator using D-099
and trusted settled producer/verifier phases. Select the last option. The generated
end-to-end test invokes the actual unbundled writer and independent semantic checker;
no runtime Python dependency or bundled/native writer action is implied. Cost: trusted
phase implementations must settle all their writers/processes before returning; callbacks
cannot prove their own truth. Native phase provenance/lease/resource/signing is later.

Scope: pin regular source identity, own a unique private ResultSetStaging, validate
bounded fixed-name typed producer and independent semantic receipts, require agreement
of source/stage IDs, size/hash, retention/counts and every member. Check source identity
between phases and through a trusted D-099 precommit callback after content verification.
Publish only after independent settlement. Cancel/refusal joins trusted phases before
explicit owned-stage discard; substitution/cleanup failure retains a reviewable error.
Keep manifests unchanged and no stable importer, immutable snapshot or decoded claim.

Acceptance: generated both-mode actual writer/semantic/native publication preserves
source and encoded duplicates/signed association. Writer/verifier failures, forged or
mismatched receipts, changed source/stage, cancellation while a worker is outstanding,
late destination collision and cleanup refusal leave prior results intact and no new
published result. Cancellation after commit reports committed success without deletion.
No untrusted session/script extension selects phase callbacks. Native UI and live owner
session stay unchanged. Historical D-090 work remains completed without observer/retry/
assertion changes. Archive crash/ENOSPC/volume and stable import remain separate gates.

Approved for build by: owner standing autonomous delegation, 2026-10-04; bounded
transaction prerequisite inside authorized original archival development.

D-105 outcome: nine focused Swift transaction tests passed, including actual generated
writer/independent semantic/native publication in both retention modes. Ordinary regression
passed 340 tests / 79 suites in 205.719 s with unchanged assertions/default scheduling.
All-feature Rust40/format/Clippy, independent companion19, writer11 and reference15 passed.
No new native action, runtime validator or writer packaging follows. Trusted phase
implementations must settle all workers before cleanup; callbacks cannot prove their own
truth. Next prerequisite is a fixed trusted native writer process/worker bridge and actual
cancellation ownership, then independent native semantic admission; the Python test adapter
is not that bridge. Stable import/persisted binding, active physical-copy interruption,
lease/resource/signing, storage/crash and decoded association remain gates. PR79 automatic
reader passed; app failed unchanged Fresh analysis6.702383vs5 and AV1125.935vs120,
331tests487.092s2issues. Private failure log retained and PR updated without retry,
historical observer or relaxed assertions/deadlines. See
COMPANION-TRANSACTION-SETTLEMENT-EVIDENCE.md for actual scope and final settlement.

## D-106: Admit the companion writer protocol natively before process integration
Date: 2026-10-04
Status: Confirmed

Authority: owner original-companion/autonomous development, R-059 / Slice049. Bounded
internal generated protocol prerequisite only. No owner media/queue/archive/encode,
app action, writer packaging, signing retry, merge/release or listening. Consequence
local_only now; future production parser influences user_data admission.

Need/product contract: successful writer process completion must describe the requested
original retention and captured source/stage, not stale or forged protocol rows. A ready
row permits only one finite start response, not archive success. The native reader CLI
stays read-only. Receipt admission cannot replace semantic/disk checks or process joining.

Choice delegated to AI. Alternatives: parse through permissive JSONDecoder and ignore
unknown/duplicate fields; extend the general ToolRunner before defining its handshake;
or first qualify a bounded strict native protocol state machine. Select the last: existing
ToolRunner supplies null stdin and no finite bidirectional handshake. A small private
ASCII JSON protocol reader supports exactly the writer's emitted strings/unsigned decimal
integers/booleans, rejects duplicate/unknown fields, limits depth/collections/rows, and
requires operation/mode/IDs/size/count/member/resource agreement. Narrow accepted syntax
is explicit, not a general JSON importer. Native process control follows separately.

Scope: internal parser, ready/start/staged/EOF and exit-zero state admission; fixed
component limits from D105, stable correlation and captured source/stage identities.
No source path/payload/error-detail retention. Ready precedes one authorized start;
completion requires one staged row and EOF plus zero status. Invalid/trailing/partial,
nonzero, reordered/extra/stale/unknown/duplicate/oversized/type/bound failures refuse
and invalidate prior partial state. Generic diagnostics preserve data privacy.

Acceptance: parser admits actual both-mode generated writer stdout and exact start
response; hashed component/source observations agree with generated disk files. Every
chunk partition yields same admission. Malformed/forged protocol, staged-before-start,
repeat-start, nonzero/partial/trailing records and forged semantic claims refuse. Generated
Python transport is test-only, not native bridge/cancellation ownership. No original
semantic, decoded, stable importer, immutable snapshot, native provenance/lease/resource/
signing or physical I/O claim. Existing D090 investigation remains completed unchanged.

Approved for build by: owner standing autonomous delegation, 2026-10-04.

D-106 outcome: eight focused protocol tests passed in0.701s including actual generated
writer rows and source/component disk agreement in both modes. Ordinary regression348tests/
80suites passed203.731s with unchanged assertions/default scheduling. Optimized build and
strict ad-hoc app/read-only helper signatures passed; actual minimum declarations14.0/11.0,
writer absent. Source stat/current recovery bytes unchanged; ten-file scoped privacy scan
with three exact identifiers and positive sentinel has zero matches; planning no findings.
Unchanged Rust/semantic/process/reference sources retain their D105 passing receipts, not
new execution claims. Native writer/group/handshake/cancellation ownership is next, then
independent native semantics and D105 integration. No app action or production archive claim.
See NATIVE-COMPANION-PROTOCOL-EVIDENCE.md. PR80 automatic reader passed; app failed unchanged
Fresh analysis5.133918vs5,340tests401.731s1issue; transaction tests passed58.066s. Retained
without rerun, historical observer or relaxed assertion/deadline; causes unknown.

## D-107: Own the actual native companion writer process and pipes
Date: 2026-10-04
Status: Confirmed

Authority: owner original companion/autonomous development, R-059 / Slice049. Internal
unbundled generated process prerequisite; no owner media/queue/archive/encode/action,
writer packaging, DeveloperID retry, merge/release or listening. Consequence local_only
now; future production ownership affects user_data. D106 protocol remains authoritative.

Need/product contract: a ready/staged row is not completion until the owned actual
writer and its pipes settle. Cancellation/deadline must prevent late receipt admission
and complete before trusted caller cleanup. The future owner chooses retention/reviews
losses, storage and privacy; no UI or production trust capability is added in this unit.

Choice delegated to AI. Alternatives: retain nested Python transport; add bidirectional
state to shared ToolRunner; or own a specialized POSIX spawn group and dedicated native
worker with bounded nonblocking pipes. Select the last. Existing ToolRunner is unchanged,
D090 timing work not reopened. One worker owns PID/group, handshake, drains, signals and
waitpid; no monitor can signal a reaped/reused PID. Keep direct child unreaped until pipe
EOF or abort so group identity remains anchored. Native production executable/signature/
lease/resource policy remains gated; DEBUG generated capability binds fixed binary name
and explicit trusted digest/file observations, never paths from untrusted sessions.

Scope: pin regular source/private empty stage; captured expected IDs passed to actual
writer; explicit bounded generated executable capability; sanitized environment/no shell;
separate group, CLOEXEC descriptors, bounded finite stdin after parsed ready, nonblocking
stdout/stderr and strict D106 schema. Dedicated worker checks task cancellation/deadline;
abort signals owned group, closes pipes and joins direct child before returning. No
automatic stage deletion/publication. Success requires joined zero exit/EOF, source/stage/
executable identity observations and no cancellation. Receipt still needs disk/original
semantic settlement; observations are not immutable content versions/authentication.

Acceptance: actual generated writer both modes with native handshake, IDs/disk receipt
agreement; pre-cancel/no launch, ready/active/late cancellation, deadline, early EOF/nonzero/
malformed/trailing/pipe-holder results refuse and direct child/pipes settle. Fixed trusted
writer does not fork; orphan descendants cannot be portably joined, physical I/O cannot be
preempted. Group signal refusal/identity substitution must remain explicit retained-stage
ownership errors, not permission to delete. No new timing observer/assertion relaxation.
Independent native semantic admission and D105 transaction integration remain next.

Approved for build by: owner standing autonomous delegation, 2026-10-04.

D-107 outcome: actual unbundled Rust writer passes native group/stdin/pipe execution in
both modes; generated ready/partial128MiBcopy/late-zero-exit cancellation refuses receipts
and joins direct child. Seven focused tests passed3.695s; after immutable test capture
warning cleanup, final7tests3.850s with no new warnings. Ordinary355tests/81suites passed
203.526s; optimized build and strict ad-hoc app/read-only helper signatures passed,
minimum14.0/11.0, writer absent. Source stat/current recovery bytes unchanged; nine-file
scoped privacy scan has zero matches/positive sentinel; planning findings empty. No
release tool capability/action/native semantic admission, disk settlement or publication
integration follows. Next qualify independent native semantic/disk checks and D105 joining,
with explicit stage retention on OwnershipFailure. Resource/lease/signing, stable import/
persisted binding, ENOSPC/volume/crash/blocked-I/O/decoded gates remain. PR81 hostedreader
passed; appfailed unchanged cancellation6.648579vs5 and two copy matrices130.882vs120,
348tests468.176s3issues; protocolsuite79.448s passed, no retry/observer/assertion changes.
See NATIVE-COMPANION-PROCESS-EVIDENCE.md for actual coverage and limitations.

## D-108: Retain unsettled ownership and verify native companion disk receipts
Date: 2026-10-04
Status: Confirmed

Authority: owner original-companion/autonomous development, R059 / Slice049. Bounded
internal generated prerequisite, no owner media/queue/archive/full-film encode/action,
writer packaging/signing retry/listening/merge/release. Consequence local_only now,
future user_data for original archival. Preserve source/current journal/prior outputs.

Need/product contract: actual native writer execution is insufficient to admit claimed
component/source hashes. Reread source and exclusive stage files independently, retain
all file descriptors through final observations, and refuse cancellation or mutations.
An unsettled phase is never permission for transaction cleanup. The future owner must
review mode/storage/privacy; no archive UI or native original-semantic claim follows.

Choice delegated to AI. Alternatives: trust parsed writer receipts; expose archive UI;
or qualify native descriptor-relative disk settlement plus transaction ownership refusal.
Select the last. Original metadata/configuration/index semantic validation is larger and
remains separate; hashes alone do not establish it. Reuse D106 fixed component bounds
and D105 publication; do not duplicate a publisher or use Python as native writer bridge.

Scope: shared internal unsettled-ownership error marker, native process conformance,
transaction retained-stage refusal before discard for that marker; worker-owned native
source/stage/component descriptors, strict membership/mode/single-link bounds, independent
chunked SHA256 and exact source/full-container bytes when selected, before/after identity
observations, cancellation and source/retention receipt matching. No file writes/deletion,
semantic receipt fabrication, immutable snapshot/stable import/persisted binding claim.
A generated transaction integration uses actual native writer and disk check, then the
existing independent Python checker only as an explicit test semantic phase; that is
not native original semantic integration or an application runtime dependency.

Acceptance: both actual native producer modes independently match disk/source and exact
whole-container bytes; forged source/member/retention receipts, unsafe/extra/missing/link/
permissions, source/stage/component mutation and cancellation refuse after readers settle.
Unsettled marker retains stage even with pending generated worker; ordinary settled errors
still allow owned cleanup. Actual generated writer/disk/test-only independent semantic/
native exclusive publication preserves source/prior results. Native original semantic,
lease/resource/signature/import/storage/crash/decoded gates remain next. Existing D090
investigation stays completed; no blind rerun/historical observer/assertion change.

Approved for build by: owner standing autonomous delegation, 2026-10-04.

D-108 focused outcome: native actual writer/disk checks plus independent test-only
original semantic oracle reach exclusive publication in both generated modes. Nineteen
focused tests in two suites passed4.569s. Source/component reread hashes and exact whole-
container bytes agree, including a later-chunk corruption refusal despite a matching
forged component hash. Forged receipts, unsafe membership/link/mode/bytes and final
source/component/stage mutations refuse. Read/late/pre-cancellation refuses after worker
unwind. Explicit descriptor lifetime covers final settlement. Unsettled producer/verifier
errors and a pending generated worker retain stage for review; ordinary settled cleanup
remains. No forced OS signal-denial or native original-semantic claim. Baseline364tests
passed204.365s before explicit lifetime and multichunk qualification; final regression
and optimized build settlement follow. Native original semantic admission, release fixed
capability/packaging/lease/resource/signing/import/storage/decoded gates remain.
See NATIVE-COMPANION-DISK-EVIDENCE.md for actual scope and limitations.

D-108 final ordinary regression:365tests/82suites passed205.194s after descriptor lifetime and multichunk qualification. No product assertion/deadline or ordinary scheduling change.

Final optimized development build and strict ad-hoc app/read-only helper signatures passed.
Actual minimum declarations remain14.0/11.0; default bundle excludes writer. No hardened
DeveloperID/notarization/older-OS runtime qualification. Source metadata/current recovery
bytes unchanged. Ten changed/nonignored-untracked public files scanned for three exact
private source path/name/stem patterns: zero matches with a positive private sentinel;
private media/receipts/ignored binaries excluded. Scoped absence, not certification.
Planning audit findings empty. No native UI change or owner session/queue execution.

## D-109: Independently admit original track and HEVC configuration natively
Date: 2026-10-04
Status: Confirmed

Authority: standing owner original-companion/autonomous development, R059 / Slice049.
Bounded unused native original-track semantic prerequisite on generated fixtures only.
No owner media/queue/full-film archive/encode, app action, writer packaging, signing retry,
listening, merge or release. Consequence local_only now, future user_data. Source/session/
current journal/prior outputs protected. Choice delegated to AI recommendation.

Need/product contract: matching producer/component hashes do not prove that retained
TrackEntry/hvcC came from the selected original video stream. Independently locate that
track in bounded original EBML bytes and compare exact original payload/configuration.
The native result is partial; it cannot assert originalComponentsMatchSource or admit a
transaction until RPU/index/audit relationships are independently checked natively.

Alternatives: trust component hashes, port every original semantic/process surface at
once, or qualify an independent native original track/configuration reader with existing
native disk settlement first. Select the last to isolate real source parsing/refusal,
not another generic receipt wrapper. No executable/Python runtime bridge is introduced.

Scope: D108 read worker retains its source/stage/component descriptors through final
settlement and gives a synchronous read-only bounded capability to a native EBML walker.
Bounded finite EBML IDs/sizes/children, unknown size only for Segment, single Tracks and
single selected HEVC video, unique critical fields/track numbers, bounded exact TrackEntry/
hvcC bytes, native structural hvcC NAL-array validation and selected-track receipts.
No packet/NAL/RPU temporal association, metadata interpretation, stable manifest/import,
persisted producer binding or immutable snapshot. Existing disk API remains integrity-only;
new entry explicitly returns a partial original-track result and no full semantic claim.

Acceptance: actual generated Rust writer both modes matches independent native selection
and exact original TrackEntry/hvcC, with independent Python original checker retained as
explicit test oracle. Rehashed substituted track/configuration refuses despite valid disk
receipts. EBML parent overflow/truncation/unknown child, duplicate critical fields/Tracks/
video/track number, unsupported selected codec and malformed hvcC arrays/NAL headers refuse.
Native cancellation/source/stage/component mutation refuses after owned read worker unwind;
no stage writes/deletion/publication. Descriptor and final observations retain D108 contract.
Full native original RPU/index/audit semantic admission and D105 integration remain next.
No D090 rerun/historical observer/assertion/deadline/scheduling workaround.

Approved for build by: owner standing autonomous delegation, 2026-10-04.

D-109 focused outcome: thirty tests in three suites passed4.439s after empty-array
compatibility qualification. Actual native writer both modes matches independently
located original TrackEntry/hvcC and independent test-only Python original checker.
Rehashed substituted components pass integrity-only checks but refuse original matching;
a matching partial result cannot admit D105 full semantics. Actual native read cancellation
and final source/stage/component changes refuse after owned reader unwind. EBML ambiguity/
framing/count/payload and hvcC framing/header/array faults refuse; empty type62 arrays and
all1...4 NAL length widths match existing reader semantics. No full native RPU/index/audit/
manifest or decoded claim. Earlier375tests/83suites passed206.025s before empty-array
compatibility change; final regression/build/protection settlement follows. See
NATIVE-ORIGINAL-TRACK-EVIDENCE.md.

D-109 final ordinary regression:376tests/83suites passed204.602s after empty-array compatibility qualification. Earlier375-test baseline206.025s is retained separately, not reused as final acceptance. Final thirty-test focused compile had no new warnings; existing older async-main-thread/optional-Bool macro warnings were observed separately. No legacy assertion/deadline/default scheduling change.

Final optimized development build and strict ad-hoc app/read-only helper signatures passed.
Minimum declarations remain14.0/11.0, writer absent; no hardened DeveloperID/notarization/
older-OS runtime qualification. Actual both-mode native original track case0.674s and
partial transaction refusal0.182s passed. Source metadata/current recovery bytes unchanged.
Eight changed public/nonignored-untracked files scanned for three exact private source
path/name/stem patterns: zero matches with positive private sentinel; private media/logs/
receipts/ignored binaries excluded. Scoped absence, not certification. Planning findings
empty. No native UI action or owner session/queue execution.


D-110 active bounded prerequisite: independent native encoded packet and raw-RPU
source reconstruction under the existing owned read worker. Reuse exact track/hvcC
matching and bounded EBML framing, stream original packet hashes and preserve signed
encoded order, then compare escaped raw RPU bytes and archive delimiters. Generated
fixtures only. Stored index/source-audit/manifest and metadata decoding remain gates;
full native semantic flags must stay false and no archive UI or publication action
is enabled. Acceptance and limits are recorded in D-110.

Approved for build by: owner standing autonomous delegation, 2026-10-04.


D-110 focused outcome:42tests in4suites passed4.573s after receipt field clarification.
The earlier focused run passed42tests4.411s and the earlier ordinary baseline passed
388tests/84suites207.319s before field clarification; those are retained separately.
Actual native writer both modes and independent test oracle match source packet/RPU
observations. Rehashed raw forgery and independent count disagreement refuse. Signed
extremes/duplicates/nonmonotonic order, all NAL widths, BlockGroup duration, other-track
skipping and >2MiB packet hashing with maximum65536-byte escaped RPU pass. Thirty-nine
malformed/unsupported source/raw cases refuse. Actual packet-read cancellation and late
raw-member mutation unwind the read worker before refusal. Matching partial packet/raw
results cannot admit D105 transaction; rehashed index/manifest remains explicitly
unqualified and full semantic flags false. Final ordinary/build settlement follows.


D-110 final ordinary regression:388tests in84suites passed205.711s after receipt field
clarification. Earlier207.319s baseline remains separately recorded. Final42focused
checks passed4.573s; actual both-mode source/oracle case0.718s, partial D105 refusal
0.196s and actual packet-read cancellation0.196s. No new compile warnings in final
focused/regression logs. No legacy assertion/deadline/default scheduling change.


Final optimized development build and strict ad-hoc app/read-only helper signatures
passed. Minimum declarations remain14.0/11.0; development writer absent. No hardened
DeveloperID/notarization or older-OS runtime qualification. Source metadata/current
recovery bytes unchanged. Nine changed public/nonignored-untracked files scanned for
three exact private source path/name/stem patterns: zero matches, positive decoded
private source-field sentinel. Private owner media/logs/receipts/ignored binaries
excluded; scoped absence only. Planning findings empty. No native UI/action or owner
session/queue execution. PR84 automatic three timing failures retained without retry;
HDR10/Fresh-analysis cancellation and AV1 deadline causes remain unknown.


D-111 active bounded prerequisite: match fixed original rpu-index and manifest claims
to D110 native source observations and D108 settled actual disk contents. Exact emitted
JSON integer/type/schema admission, signed encoded order, original offsets, source/
component relations and complete bounded index consumption are required. Generated
fixtures only; source-audit semantics and RPU metadata validity remain gates. Full
semantic flags stay false and D105 publication remains unavailable. Acceptance and
limits recorded in D-111.

Approved for build by: owner standing autonomous delegation, 2026-10-04.


D-111 focused outcome:53tests in5suites passed12.500s. Actual native writer both modes
and independent test-only original oracle pass0.792s; actual signed-extreme source writer/
index admission pass0.415s. Matching partial D105 refusal passes0.191s. Rehashed manifest
27-case and index20-case forgeries pass narrower integrity/packet checks but refuse
actual native source admission. Cancellation during manifest/index reads and late
source/stage/index/manifest changes refuse after worker unwind. Fixed chunk/row bounds,
integer/type grammar and permitted whitespace/component order pass. A repaired audit
forgery remains explicitly outside partial semantic admission; full flags stay false.
Earlier51-focused12.106s receipt before signed-extreme/whitespace qualification retained
separately. Final ordinary/build/protection/privacy/planning settlement follows.


D-111 final ordinary regression:399tests in85suites passed204.805s. Native original
index suite passed20.427s in that unchanged ordinary run; focused53tests/5suites passed
12.500s. No new compile warnings in final focused/regression logs and no legacy
assertion/deadline/default scheduling change. Full source-audit/metadata/geometry
semantics and publication remain unavailable. Final optimized build settlement follows.


Final optimized development build and strict ad-hoc app/read-only helper signatures
passed. Minimum declarations remain14.0/11.0; development writer absent. No hardened
DeveloperID/notarization or older-OS runtime qualification. Source metadata/current
recovery bytes unchanged. Nine changed public/nonignored-untracked files scanned for
three exact private source path/name/stem patterns: zero matches, positive decoded
private source-field sentinel. Private owner media/logs/receipts/ignored binaries
excluded; scoped absence only. Planning findings empty. No native UI/action or owner
session/queue execution. PR85 automatic two unchanged AV1/ten-bit timing failures
retained without retry; causes remain unknown.


## D-112: Match stored source-audit framing to independent native source facts

Status: Confirmed

Need/product contract: hash-correct source-audit rows can still contradict original
geometry, timing, packet flags, encoded RPU order or completion claims. Independently
reconstruct these facts on the existing pinned native disk worker, consuming the
fixed stored audit in source order alongside index validation.

Alternatives: trust producer summaries, integrate metadata decoding and every archive
gate at once, or admit actual audit framing/source relationships first. Select the
last bounded prerequisite; no generic receipt wrapper or Python runtime bridge.

Scope: original declared pixel/crop/display/default-duration values, actual Info
scale/Segment size mode, exact version-three begin/packet/RPU/complete schema and
source associations, typed nullable audit fields, bounded fixed streaming rows and
compact-summary shape checks. Nullable grammar is audit-only; index/manifest retain
previous refusals. Existing narrower APIs remain narrower. Compact metadata values
are NOT independently decoded or verified; full semantic flags remain false and the
matching partial result must still refuse D105 publication. Declared geometry is
not decoded parameter-set geometry or an edited-picture conversion qualification.

Acceptance: actual generated native writer both modes matches the independent
original test oracle. Rehashed audit substitutions pass index/manifest integrity
but refuse native source audit comparison; signed duplicate/nonmonotonic order,
null/boolean/integer distinctions, missing/extra/reordered/unfinished rows and
source geometry boundaries are checked. Actual audit-read cancellation and late
mutation refuse after worker unwind. A plausible substituted compact summary must
remain explicitly unqualified, not turn full flags true. Ordinary regression,
optimized development build, protection/privacy/planning checks required. No D090
retry or deadline/assertion/scheduling change, native archive UI, owner queue or
private full-film operation.

Approved for build by: owner standing autonomous delegation, 2026-10-04.


D-112 focused outcome:52tests in5suites passed12.602s; new audit suite3.011s.
Actual native writer both modes and independent test-only oracle pass0.780s;
actual generated signed Int64.min/max audit sources with unknown-size Segment,
nonzero crop/display and UInt64.max default duration pass0.450s. Matching partial
D105 transaction refuses0.213s. Repaired audit forgeries pass index/manifest source
admission then fail audit-source comparison. Geometry bounds/duplicates/overflow,
nullable type grammar, bounded fixed audit chunks/LF, active audit-read cancellation
and final source/stage/audit mutation refuse after reader unwind. A plausible changed
compact summary intentionally remains shape-only/unverified; full semantic flags false.
Final ordinary regression and optimized development bundle settlement follows.


D-112 final ordinary regression:409tests in86suites passed206.948s. Native audit
suite11.006s passed in that ordinary run. Focused52tests/5suites12.602s receipt retained;
54 repaired audit-forgery cases and25 malformed geometry cases checked. No new compile
warnings in final focus/regression and no legacy assertion/deadline/scheduling change.
PR86 automatic all399 tests471.151s and preview passed without retry; prior hosted
unknown-cause failures retained. Full metadata semantics/publication remain unavailable.


Final optimized development build and strict ad-hoc app/read-only helper signatures
passed; minimum declarations14.0/11.0 and development writer absent. No DeveloperID,
notarization or older-OS runtime qualification. No native UI/action, owner session/
queue/archive/encode or listening operation. Owner source metadata/current journal
unchanged. Eleven changed public/nonignored-untracked files scanned against three
exact private source path/name/stem patterns: zero matches with positive decoded
private source-field sentinel; private media/logs/receipts/ignored binaries excluded.
Planning findings empty. Next: qualify an actual fixed trusted owned native metadata
reader/library and compare fresh compact RPU metadata to stored summaries before
complete semantic transaction admission. Existing ToolRunner drains/joins direct
child and readers but does not qualify group/descendant ownership for this archive
bridge; do not treat a test oracle or current summaries as native metadata proof.


## D-113: Own fixed native metadata reader execution and bounded stream settlement

Status: Confirmed

Need/product contract: archive metadata comparison needs freshly decoded compact RPU
metadata from a known owned reader, with no late/partial result or live child/pipe
left for transaction cleanup. Existing general ToolRunner lacks process-group ownership.

Alternatives: trust stored summaries, use test-only Python as runtime bridge, change
all ToolRunner users, or qualify a fixed internal read-only native controller. Select
the last. This is an actual executable/process prerequisite, not generic receipt wrapping.

Scope: development-only explicitly trusted fixed helper digest/observed identity,
fixed mkv-summary argv/environment, source pin/content observations, one dedicated
worker owns PID/group/EOF/status, bounded typed exact-schema stdout rows and stderr,
finite configured deadline and cancellation/group termination/direct-child reaping.
No arbitrary executable action, stage writes/publication/UI or release capability.
Full original semantic flags remain false: no package/audit comparison is inferred
from a fresh stream. Source observations are not immutable snapshots or executable
signature authentication. Descendants are signalled in the owned group; non-child
orphans cannot be portably joined, blocked I/O cannot be preempted.

Acceptance: actual generated Rust read-only helper stream yields original counts/hash
and source unchanged. Strict row schema/order/count/nullable/int bounds and partial,
malformed/nonzero/stderr overflow/EOF-live-child/pipe-holder outcomes refuse. Actual
prelaunch/row/late cancellation and post-result path/content changes refuse after
owned child/pipes settle. Generated native surrogates establish process cases, never
metadata authenticity. Unsettled signal/join errors retain shared ownership marker.
Ordinary regression, optimized development bundle/signatures and protection/privacy/
planning checks required. No D090 rerun/timing/assertion/scheduling changes, owner queue,
private film read/archive/encode or audio listening.

Approved for build by: owner standing autonomous delegation, 2026-10-04.


D-113 focused settlement:25tests in3suites passed4.651s; new metadata process
suite4.650s. Actual fixed Rust reader/source report0.451s; generated signed Int64
extremes with unsigned scale/duration0.386s; observed live repeated-cluster reader
cancellation/direct-child join0.181s;24 repaired protocol refusal cases0.193s. Nine
native C surrogate process cases cover deadline/silence, EOF-live-child, malformed,
stderr/row overflow, pipe-holding descendant and complete output from live/nonzero
process. Prelaunch/row/late cancellation and source/executable mutation refuse.

Initial22-focused3.906s and one-case discriminator0.862s failed the new test's
CancellationError-only expectation at begin/complete: group SIGKILL returned EPERM
while direct-child join succeeded. Keep this typed CompanionUnsettledOwnership
refusal; never translate uncertain group settlement into success or ordinary stage
cleanup. New test accepts exactly cancellation or observed EPERM/joined marker before
reap, still requires refusal/direct-child join/source unchanged; late after-join
cancellation remains ordinary cancellation. This is a new process case/spec correction,
not D090 deadline/assertion relaxation. Earlier24-focused4.557s passed but retained
new captured-variable warnings; final fixture uses locked state, no new final warnings.
Final ordinary regression follows; no package metadata comparison/full flags/UI added.


D-113 final ordinary regression:417tests in87suites passed206.698s; native metadata
process suite13.000s, actual live cancellation0.360s in that run. Focused25tests/
3suites4.651s retained. No new warnings in final focused/regression logs. Optimized
development build/strict ad-hoc app/read-only helper signatures passed; minima14.0/
11.0, writer absent. No DeveloperID/notarization/older-OS runtime qualification.
Ten changed public/nonignored-untracked files scanned against three exact private
source path/name/stem patterns: zero matches with positive decoded private source-field
sentinel; private media/logs/receipts/ignored binaries excluded. Source metadata/current
journal unchanged; planning findings empty. No native UI/action, owner queue/source
processing/private film archive/encode/listening, merge or release. Stored audit/fresh
summary comparison and complete semantic transaction admission remain next; no full
semantic flags or release reader capability claimed.


## D-114: Compare original companion summaries with fresh owned native metadata

Status: Confirmed

Need/product contract: a plausible forged compact summary passes D112 shape-only
admission. Require an actual fresh owned libdovi stream to match the entire stored
audit after independent native source/raw/index/manifest validation, then settle
final source/stage/member observations before returning semantic success.

Alternatives: trust summary shape/hash claims, reuse Python test oracle at runtime,
queue full arrays/nested async adapters, or compose actual owned reader on D108's
pinned worker with streaming fixed-member comparison. Select the last.

Scope: invoke D113 owned synchronous process core on existing pinned read worker,
propagating external cooperative cancellation/shared unsettled ownership. Exact native
JSON types/value relationships (field order/whitespace irrelevant), every non-resource
fresh row and exact stored EOF. Record mismatch, drain bounded reader to joined exit,
then refuse; cancellation/I/O ownership errors still unwind truthfully. D112 source
framing/declared geometry, D111 manifest/index and D108 actual disk/source checks remain
mandatory. Only complete settled composition can report original component metadata
matching source; narrower receipts stay partial. Generated actual writer/native verifier/
D105 exclusive publication may exercise both retention modes internally, no native UI.

No release tool authentication/capability, portable importer/immutable snapshot/persisted
producer provenance, codec-parameter/picture/decoded-frame/edit conversion qualification,
owner source processing, writer packaging, queue/film archive/encode or listening work.

Acceptance: both generated modes fresh metadata/source match; repaired plausible summary
forgeries pass partial framing then fail full native comparison. Exact nullable/boolean/
integer types, row order/EOF, source hash/count/resource settlement and independent
source relationships required. Actual integrated row-read/child cancellation and late
source/stage/component mutation refuse after unwind; shared unsettled group/phase error
retains stage. Actual generated native writer/validator/exclusive transaction publishes
once, refuses prior destination, preserves source/prior bytes. Ordinary regression,
optimized ad-hoc bundle/protection/privacy/planning checks. Inspect automatic PR88 without
retry; retain historical failures/no D090 observer/assertion/deadline/scheduling change.

Approved for build by: owner standing autonomous delegation, 2026-10-04.


D-114 focused native composition:36tests/4suites passed4.663s; new comparison suite
3.756s. Both-mode source admission0.796s, six repaired plausible summary forgeries
0.360s, actual native writer/validator/exclusive publication0.644s and actual transaction
cancellation0.296s passed. Final source/stage/audit mutation and exact typed/whitespace
comparison pass. Full source-dependent composed metadata flag only follows pinned final
settlement; narrower APIs stay false, decoded/import/immutable/provenance remain separate.
Initial compile failures repaired (escaping checkpoint closure and test Published member),
logs retained. First ordinary424tests/88suites208.896s failed one missing generated writer
artifact in an existing index fixture. New fixture target ownership is isolated; existing
suite concurrency/deadlines remain unchanged. Changed focused/regression follows, no
D090 scheduling workaround or historical timing causal claim. PR88 automatic compiled
changed fixture, then failed unchanged AV1 deadline:417tests537.172s one issue, native
reader suite66.047s passed, preview skipped. Private log retained/PR updated; no retry.


D-114 changed-fixture focus:7tests/1suite passed13.632s including cold owned Cargo
target compilation; prior36tests/4suites4.663s retained. Intermediate ordinary424tests/
88suites209.223s passed; new metadata comparison suite12.762s, actual both-mode native
publication1.699s, transaction cancellation0.537s. Existing index fixture also passed;
no global scheduling/deadline/assertion change. Initial failed424test log retained.
Full original component admission remains source-dependent version-zero development
verification, not portable import/immutable/persisted provenance/decoded qualification.
No new warnings in final focused or ordinary logs. Optimized build/protection follow.


The first optimized build exposed Swift6 captured mutable state warnings because the
synchronous worker callback was unnecessarily typed Sendable. The synchronous core
now accepts an ordinary callback; the async entry still requires Sendable across its
worker boundary. No execution ownership/scheduling changes. That focused run passed
new metadata checks but two existing test-only oracle phases refused while D113's
reader fixture still rebuilt shared release artifacts. A new discriminator verified
the same generated source/package with both settled default and isolated readers;
no persistent metadata disagreement was found, and the precise transient refusal
cause is not claimed. D113's serialized reader fixture now also owns a separate Cargo
target, leaving app/writer/oracle release output untouched. Failed logs retained;
changed ownership focus/ordinary/build settlement follows. No global concurrency,
assertion/deadline or D090 observer/scheduling changes.


D-114 final owned-fixture/synchronous-callback focus:36tests/4suites passed14.562s
including cold isolated reader compilation; comparison suite4.242s. Final ordinary
424tests/88suites207.288s passed with no new warnings; comparison suite11.786s,
actual native publication both modes2.463s and transaction cancellation0.577s.
The intermediate209.223s pass and failed208.896s/4.873s receipts are retained as
separate states. Existing assertions/concurrency/deadlines unchanged. No owner source
body read or film archive; final optimized bundle and protection settlement follows.


D-114 optimized development build passed without new warnings; strict ad-hoc app and
read-only helper signatures passed, minimum versions14.0/11.0, writer absent. No
DeveloperID/notarization/older-OS runtime qualification. Twelve changed public/nonignored
untracked files checked against three private source path/name/stem patterns: zero
matches with positive decoded private source-field sentinel. Source metadata/current
recovery journal unchanged; planning findings empty. No native action/owner queue/film
archive/encode/listening, merge or release. Resource/access ownership, release helper
provenance/packaging and owner-review gates remain before any archive UI; source-dependent
prototype semantic matching does not qualify stable import, decoded association or edit
conversion. Historical hosted timing failures remain retained/unknown, no retry.


## D-115: Qualify native original companion ENOSPC settlement on owned APFS

Status: Confirmed

Need trace/product contract: R-059's original companion cannot publish complete-looking
partial files when its destination fills. D114 generated semantic success does not
establish storage failure behavior. Use the actual writer/native validator/D105/D099
pipeline with generated media and a uniquely owned bounded APFS image. Owner source,
volumes, session and prior results remain protected. No app archive UI or release action.

Alternatives: mock writes/errno, fill an existing destination, reuse the generic queue
capacity result as archive proof, or qualify actual archive production in an owned image.
Select the last; the existing queue/APFS assertions and D090 timings remain unchanged.

Scope: opt-in generated fixture/harness, fixed64MiB image with image/mount/marker/device
identity observations before filling and detach. Generated original container with32MiB
Void padding, an admitted prior metadata result, bounded filler and2MiB reservation.
Observe actual ENOSPC then release only reservation so stage/producer can start. Require
actual partial original-container bytes, joined writer refusal, no verifier/publication,
source/prior bytes unchanged, settled owned-stage cleanup. Reclaim only filler and retry
actual full native validation/exclusive publication. No private film archive or queue.

Harness owns direct test process/group and image receipt; timeout/interruption or unknown
worker ownership retains mounted fixture for review, never forced detach/deletion. Ordinary
settled failure can detach after image/mount identity revalidation and retain its image.
No owner or unrelated device detach. Configured bounds do not establish general resource,
crash/durability/volume-loss/blocked-I/O or universal descendant supervision guarantees.
No native writer protocol/production helper capabilities or runtime controller changes.

Acceptance: actual APFS filesystem/device/capacity/unique marker, ENOSPC write/fsync
observation and distinct active partial-copy refusal before phase cleanup. Source/hash/
prior result/absence/fixed membership and joined child assertions. Actual native retry
succeeds with source-matching semantic receipt and whole-container original bytes; prior
destination refuses. Owned detach and protection/privacy/planning plus ordinary regression/
optimized ad-hoc build checks. Inspect automatic PR89 without retry; retain all failures.

Approved for build by: owner standing autonomous generated non-audio delegation, 2026-10-04.


D-115 acceptance correction before further build: initial actual APFS test produced an
incomplete container and settled refusal, but its4096byte post-writer probe succeeded.
The actual initial fill ENOSPC does not establish the later writer's errno. Do not
accept or weaken that assertion. The unbundled writer currently collapses all producer
I/O errors, so retain a sanitized first actual output write/flush ENOSPC classification
in the source-bound core, propagate it through the existing stage error, and reserve
nonzero development writer exit28 for that classification. Native controller returns
a typed storage-full refusal only after EOF/child/pin settlement. stdout ready/start/
staged protocol and archive schema remain unchanged; status28 is never success. No
private errno detail/path/payload is emitted. Cancellation keeps precedence. Source
reads, unrelated I/O, metadata-open failures and capacity estimates must not acquire
this output-full classification. This is an internal development error contract, not
a new public/native UI API or release capability. Actual APFS test will require that
classification plus matching partial original bytes instead of inferring writer errno
from a later probe. Failed probe log and safely detached image remain retained.


D-115 actual changed APFS case passed4.664s: bounded filesystem67067904bytes,
generated source33555889bytes/filler62193664bytes/partial container2162688bytes,
actual component ENOSPC typed refusal after writer join, no verifier/publication,
source/prior bytes preserved and full native verified retry. Direct test child joined,
phase settlement observed, image/mount identity revalidated and non-forced detach
confirmed; successful image removed. Initial failed probe image remains safely detached.
Rust41all-feature tests/format/Clippy and three no-disk harness ownership guards passed.
Initial Checked test-field compile failure retained/repaired. Focused26tests/4suites
8.357s passed, new opt-in case skipped in that ordinary focus and executed separately.
Final ordinary425reported tests/89suites207.903s passed;26 opt-in tests skipped (same
previous25 plus new APFS), no new warnings. Actual new APFS receipt remains separate.
Independent companion30tests6.482s passed. Frame/build/protection settlement follows.
No D090 timing observer/assertion/deadline/global scheduling changes. PR89 automatic
nine unchanged60/120second timing failures retained/PR updated,424tests566.001s;
metadata192.150s/reader188.686s passed, preview skipped, no rerun/causal claim.


Independent frame-reference15tests1.568s passed. Its installed Homebrew FFmpeg dylibs
reported macOS27 minimum-version linker warnings against the generated14.0 compile;
this is current-runtime generated reference evidence, not older-OS qualification or
bundling of the separate minimal LGPL decoder. No complete owner-source run repeated.


D-115 final optimized development build passed without warnings; strict ad-hoc app/
read-only helper signatures passed, minima14.0/11.0, writer absent. No DeveloperID/
notarization/older-OS runtime proof. Twelve changed public/nonignored untracked files
scanned against three private source path/name/stem patterns: zero matches with positive
decoded source-field sentinel. Source metadata/current recovery journal unchanged,
planning findings empty. Successful owned APFS image removed after verified detach;
first failed image remains detached with private receipt/log. No owner queue/source
body/film archive/encode/listening/merge/release. Native access/resource ownership,
release capability/packaging/hardened loading and owner review remain before archive UI;
stable import/persisted binding/decoded edits/crash/volume-loss remain separate gates.


## D-116: Own native companion access and temporary export activity

Status: Confirmed

Need trace: R-059 requires source/destination access through actual writer, complete
native source-dependent verification, exclusive publication and settled cleanup. D115
storage evidence does not establish this lifetime. Reuse Foundation security-scoped
access and ExportActivity's idle-system-sleep-only request. Connect concrete D107,
D114 and D105/D099 phases; no arbitrary producer/verifier admission in the new bridge.

Scope: unused internal native operation with explicit trusted development tool
capabilities, source/parent no-follow descriptor pins and balanced scope acquisitions.
An unscoped ordinary URL may return false from startAccessing; that is not a permission
failure. Actual descriptor opening/type/path checks and owned stage creation must still
succeed. Reject pre-cancel/unsafe inputs before acquiring activity. Acquire scopes before
opening source/parent; ordinary return closes pins and ends only successful scopes and
activity after all phases/cleanup return. No source paths in activity names.

On shared unsettled ownership or typed cleanup refusal, retain source/parent access and
pins in a process-local review registry, even if the caller drops the error. Retain the
activity only for a bounded additional120seconds, then end its idle-sleep request while
keeping access retained. This cap is energy-policy expiry, NOT ownership settlement or
permission to clean files. No production release-from-review API is admitted without a
settlement design. DEBUG generated tests alone may release controlled injected review
states after proving their owned phase has returned. No persistent security/sleep setting,
manual-lock override, archive UI, release provenance capability or packaging is added.

Acceptance: actual generated writer/full native verifier/publication both modes, source
and prior output unchanged, activity/access present at writer/reader/publication/cleanup
boundaries. Pre-cancel, real source/parent refusal, injected acquisition rollback, positive
scope balance (explicit fake provider), real unscoped behavior, cancellation join and typed
review retention/expiry. Observe actual PID-specific Foundation OS request independently;
fake provider lifecycle checks do not prove sandbox grants or revocation behavior. Native
lease scope counts are process-local observations, not a sandbox platform qualification.
No resource peak/throughput/power guarantee. Reuse unchanged D115 Rust/reference evidence.
Ordinary regression, optimized ad-hoc signatures, privacy/protection/planning checks and
PR90 automatic outcome inspection without retry remain required.

Approved for build by: owner standing autonomous generated non-audio delegation, 2026-10-04.


D-116 final qualification: expanded ordinary433reported tests/90suites205.588s passed,
26 opt-in skips unchanged; new access suite8tests14.273s including actual non-root
POSIX read/write denials. No new warnings. Focused26tests/3suites3.807s passed before
final generated permission-restoration cleanup adjustment; expanded ordinary run covers
that final test code. Debug development build/strict ad-hoc app/read-only helper
signatures passed without warnings, minima14.0/11.0; writer absent. Optimized Swift
app qualification was initially reported incorrectly and is corrected in D117. Actual live-reader
PID-specific idle-sleep assertion present during ownership and absent after settled release,
source/parent descriptor FileIDs held through phases and retained review. Positive scope
counts are explicitly fake-provider lifecycle evidence; sandbox grants/revocation remain
unqualified. Controlled retention persists across dropped errors and energy expiry; real
joined-writer stage substitution retains cleanup review. Only one run/pending review is
admitted. No production recovery-from-review API, release tool trust, archive UI or writer
packaging follows. Rust/reference/APFS unchanged D115 evidence reused, not re-executed.
PR90 reader passed; app three unchanged timing failures retained/PR updated; no retry or
D090 observer/assertion/deadline/global scheduling change. Protection/privacy final below.


Final seven-file public/nonignored change scan: three private source path/name/stem
patterns have zero matches with positive decoded source-field sentinel. Owner source
metadata and current recovery journal unchanged; full planning audit findings empty.
No source-body read, owner queue, private film archive/encode/listening, merge or release.
Initial missing-index planning finding retained and corrected. Existing bounded awake
PID32011 exact command/start inspected; expiry16:01:07UTC, no renewal/security changes.


## D-117: Qualify fixed Rust helper signatures before release admission

Status: Confirmed

Need trace: R-059 native archive access ownership does not authenticate its executables.
D097 DeveloperID attempt on relocated FFmpeg is interrupted/incomplete. Read its receipt,
existing helper notice/build contracts and Apple static-code/requirements guidance first.
Choose a fixed source-built Rust reader/writer signature and hardened execution
prerequisite, rather than retry FFmpeg signing, bless paths/hashes as release trust,
change library-validation policy or expose an archive action.

Scope: unused native Security static signature admission of fixed helper roles under an
owned bundle layout, bounded no-follow/pinned path observations before/after, exact role
identifier, runtime flag, no entitlements, explicit trusted requirement. DEBUG ad-hoc
fixture policy is distinct from DeveloperID Apple-anchor/Team/leaf/intermediate policy;
no production Tool constructor or untrusted requirement/policy deserialization. Qualify
real copied Rust helpers with generated source and actual existing native owned processes,
plus altered/unsigned/wrong-role/wrong-policy fixtures. Not a universal hostile same-user
or per-universal-slice execution proof. Pin and refuse unsuitable architecture/layout.

A genuinely new bounded DeveloperID discriminator may sign a newly owned standalone
Rust helper (no relocated dylibs) using the already configured local identity, after
receipt inspection. No private key/password arguments or logging; no notarization upload,
credential changes, release, disabled library validation or broadened entitlements.
Own signing process/group with timeout/reaping and retain incomplete output on refusal.
No blind retry. If Keychain interaction blocks it, retain evidence and qualify independent
ad-hoc/refusal paths without claiming DeveloperID readiness.

Correct prior D116 optimized-app claim: d116-release-build.log says Building for debugging.
Rust helper was release, Swift app was debug. Preserve original receipt and add explicit
correction to docs/PR91; run STAXRIP_CONFIGURATION=release for genuine optimized product
qualification. D115 production build receipt remains valid. No source/previous-output
or current journal changes. Generated media only; no full-source rerun/archive/queue.

Acceptance: fixed-role signature/identifier/runtime/entitlement and pinned-layout checks,
actual hardened Rust execution/source-dependent validation on generated inputs where
qualified, exact refusal of ad-hoc under DeveloperID policy, mutation/unsigned/wrong role
or parent substitution. Match scope of signing evidence honestly. Ordinary regression,
explicit optimized build/strict ad-hoc development bundle, privacy/protection/planning;
inspect automatic PR91 without rerun. Release provenance/packaging/notarization/review
recovery/owner losses-storage-privacy remain gates before archive UI.

Approved for build by: owner standing autonomous generated non-audio delegation, 2026-10-04.


D117 scoped local outcome: fixed native static signature/refusal prerequisite and actual
ad-hoc hardened Rust reader/writer source-dependent publication both modes pass. DeveloperID
positive admission remains UNQUALIFIED: new owned standalone Rust reader signing did not
settle in20s, stopped/joined with incomplete output retained; prior FFmpeg attempt untouched,
cause unknown, no blind retry. Policy keeps anchored DeveloperID and DEBUG known-CDHash
ad-hoc trust separate. No release Tool factory, writer packaging or archive UI. Initial
Data hex compile error/hash-syntax parse failure/competing app-slot fixture refusal logs
retained. Corrected independent native transaction fixture preserves single-operation
guard/global scheduling/deadlines. Ordinary438reported tests/91suites207.134s passed with26
unchanged opt-in skips; one test-only unnecessary try warning later removed. Final
focused13tests/2suites2.507s and explicit release product build passed without new warnings;
strict ad-hoc app/read-only helper signatures/minima14.0/11.0, writer absent. D116 debug
receipt/incorrect optimized claim corrected in docs/PR91, original retained; D115 genuine
optimized receipt untouched. Source/static observations are not hostile-race/immutable/live
capability/outer-seal/notarization guarantees. PR91 automatic21 unchanged timing failures
retained/PR updated; access135.829s passed; no retry or D090 causal claim. Final protection/
privacy/planning checks follow.


Final seven-file public/nonignored scan: zero private source path/name/stem matches,
positive decoded source-field sentinel; original source metadata/current recovery journal
unchanged, full planning findings empty. No owner source body/queue/film archive/encode/
listening, merge or release. Prior awake32011 exact command/start and receipt revalidated;
replaced only that owned assertion with bounded55829 -diu -t7200, expiry17:46:06UTC,
for continuing authorized scheduled development. No persistent security/locking change
or manual-lock override. Incomplete D097/D117 signing artifacts and detached D115 failed
image stay retained. No blanket signing/production/archive acceptance follows.

## D-118: Qualify abrupt native coordinator loss around exclusive companion commit
Date: 2026-10-04
Status: Confirmed

Authority: owner standing autonomous generated non-audio development, R059 / Slice049.
Need trace: D105 owns cleanup only while its process lives. A lost coordinator cannot
report success or discard its stage. D099 exclusive rename must be observed separately
from a returned receipt. Consequence local_only for this generated qualification;
future user_data recovery remains gated. Preserve owner source/session/journal/outputs.

Choice delegated to AI: test actual native writer/full verifier/publication at explicit
before/after commit boundaries in a separately owned generated Swift test coordinator.
Alternatives are fabricated filesystem state or exposing recovery adoption/deletion now.
Select observed process-loss evidence without adding an archive action or recovery API.

Scope: test-only native coordinator reexecution, finite trusted fixture paths/digests,
exclusive generated root, joined actual writer/reader before boundary acknowledgment,
parent-gated immediate POSIX exit (no arbitrary external PID signaling), child/pipe settlement,
read-only native semantic revalidation of surviving stage/result and original/prior bytes.
The handshake is test instrumentation, not a persisted journal or application bridge.
Retain fixture on uncertain ownership/failure; delete only successful owned generated
fixtures after settled direct child and all assertions. No disk image or owner volume.

Acceptance: both retention modes at both boundaries, direct immediate coordinator exit without Swift unwinding,
acknowledged helper joins, exact surviving directory identity/content/membership,
precommit stage with absent destination, postcommit destination with absent old stage,
unchanged generated source/prior output, full source-dependent native semantic reread.
No power-loss durability, immutable snapshot, persisted producer provenance, portable
importer, production recovery release or orphan/blocked-I/O settlement follows.
Ordinary regression, privacy/protection/planning and PR92 automatic observation without
retry. Product unchanged; reuse explicit D117 release signature/build receipt if so.

Approved for build by: owner standing autonomous generated non-audio delegation, 2026-10-04.

D118 fixture specification correction: the initial four SIGKILL cases passed in isolation,
but ordinary regression observed raise returning in one generated child. Its cause is
unknown; the child error ran ordinary cleanup, so that case is not abrupt-loss evidence.
Retain the failed generated fixture/log. Select explicit POSIX _exit86 at every boundary,
not an optional success fallback: it ends the process without Swift/defer/atexit cleanup.
Parent must observe normal exit86 and joined coordinator. This qualifies abrupt native
coordinator loss without claiming signal-delivery or power-loss behavior. No D090 test,
assertion, timing limit, concurrency policy or scheduling rule changes.

D118 final outcome: actual immediate coordinator exit86 bypasses Swift cleanup at both
exclusive commit boundaries in both retention modes. Source/prior bytes and pinned
surviving stage/result identities remain equal; fresh full native source-dependent
semantic verification passes. Final focused1test/1suite1.800s and ordinary439reported
tests/92suites207.798s passed with26 unchanged opt-in skips and no new warnings. New loss
suite passed4.577s within ordinary. The earlier Foundation stall and returned SIGKILL
ordinary failure439tests206.791s remain retained, not retroactively passed. Exact owned
stalled runner stopped; failed fixtures retained outside Git. No D090 causal claim or
historical assertion/deadline/concurrency/scheduling change. Product sources unchanged
since D117; explicit optimized build reused, current strict ad-hoc app/read-only helper
signatures passed, writer absent. Five-file privacy scan zero matches/positive sentinel,
owner source metadata/current journal unchanged, full planning findings empty. PR92
automatic16 unchanged timing issues438tests618.883s retained/PR updated; signature suite
passed246.881s, preview skipped, no reader workflow. No archive action, release capability,
persisted recovery/adoption/deletion API or power-loss durability follows. Next qualify
read-only native source-dependent candidate review without the lost coordinator's test
frame. Packaging/signing, production review recovery and owner mode/privacy remain gates.
See NATIVE-COMPANION-COORDINATOR-LOSS-EVIDENCE.md for actual coverage and limits.

## D-119: Review original companion candidates without a producer receipt
Date: 2026-10-04
Status: Confirmed

Authority: owner standing autonomous generated non-audio development, R059 / Slice049.
Need trace: after D118 process loss only original source and surviving files remain.
Requiring a transient producer/test acknowledgment prevents real read-only examination.
Consequence local_only in this unused generated scope, future user_data review gated.
Preserve original media/session/current journal/outputs. No archive action or recovery
adoption/deletion/republication, owner queue, film archive/encode, signing retry or release.

Choice delegated to AI: extend the concrete D108 pinned read worker with explicit original
source/candidate directory/retention and trusted fixed reader, instead of a receipt wrapper,
Python app bridge, automatic stage discovery or stable importer claims. Hash original
source and fixed components from pinned descriptors; bootstrap only bounded unsigned
count claims from the existing version-zero manifest. Require existing full D109-D114
source reconstruction/manifest/index/audit/fresh metadata checks to establish those claims.
Persisted claims are untrusted until this complete composition/final observations passes.

Scope: unused read-only candidate API sharing disk worker/read capabilities. No path or
executable comes from a manifest. Fixed membership/permissions/single links/resource bounds,
source/candidate identity and cooperative cancellation stay required. Ordinary returns
join reader/worker and close descriptors; unsettled ownership propagates its typed marker.
No stable import, immutable snapshot, persisted producer binding, decoded/edit association,
access-release/discard/adoption authority or release provenance follows from review findings.

Acceptance: actual generated before/after-loss candidates in both modes with no test-frame
argument; full native reread from files/source only. Repaired plausible summary/count/hash/
manifest forgeries and malformed/partial/missing/unsafe candidates refuse read-only. Active
read cancellation and final source/candidate/member mutation refuse after owned settlement;
source/prior/candidate unchanged on ordinary review/refusal. Existing receipt APIs preserve
their narrower guarantees. Ordinary regression, explicit optimized build/strict ad-hoc
signatures, protection/privacy/planning and automatic PR93 observation without retry.

Approved for build by: owner standing autonomous generated non-audio delegation, 2026-10-04.

D119 final local outcome: receiptless read-only review derives pinned source/component
observations and admits bounded manifest count claims only after full D109-D114 native
source-dependent reconstruction. Actual D118 before/after-loss candidates pass both modes
after deleting the test acknowledgment files; no receipt/frame enters the API. Nineteen
manifest forgeries, four malformed/oversized cases, repaired plausible metadata forgery,
unsafe/missing/extra members, wrong retention, active cancellation and final mutations
refuse. Fresh reader joins before semantic refusal; actual group EPERM/direct-child-joined
ownership marker propagates with generated candidate retained, no cleanup authority.
Initial focus15tests/3suites13.106s and expanded22tests/4suites4.175s passed; redundant test
is-type warning removed before ordinary445reported tests/93suites206.832s passed with26
unchanged opt-in skips and no new warnings. Candidate suite12.051s and receiptless loss
suite4.603s passed ordinary. Explicit optimized product build and strict ad-hoc app/read-
only helper signatures passed without warnings, minima14.0/11.0, writer absent. API unused,
no UI walkthrough implied. Original version-zero archive schema unchanged; no importer,
persisted producer binding, decoded association, adoption/delete/access-release/action or
release Tool follows. PR93 automatic439tests765.145s13issues retained/PR updated; loss
suite295.425s passed. One motion CancellationError/message mismatch recorded without
root-cause claim; historical D090 timing causes unknown, no rerun/assertion/scheduling
change. Protection/privacy/planning receipts follow before publication. Next qualify
concrete original source/candidate access/activity ownership through read-only review,
reusing D116 facilities and distinguishing candidate-folder grants from parent grants.
See NATIVE-COMPANION-CANDIDATE-REVIEW-EVIDENCE.md for scope and remaining gates.

Final seven-file privacy scan has zero private source path/name/stem matches and a
positive sentinel. Source metadata/current recovery journal remain unchanged; full
planning findings empty. Current owned55829 bounded awake command/start matches receipt,
expiry17:46:06UTC, no persistent locking/security change. No owner media body/queue/film
archive/encode/listening, signing retry, merge or release. Controlled generated candidate
fixtures with typed unsettled group ownership remain retained outside Git.

## D-120: Own source and candidate access through read-only native review
Date: 2026-10-04
Status: Confirmed

Authority: owner standing autonomous generated non-audio implementation, R059 / Slice049.
Approved for build by that delegation. Extend the concrete D116 operation with D119
read-only review using explicit original source/candidate folder and fixed trusted reader.
Acquire only source/candidate scopes, never infer a parent grant. Pin actual no-follow
descriptors before activity; false Foundation scope acquisition on ordinary URLs is
not denial. Share executing/retained-review exclusion with preservation operations.
Ordinary return must join native worker/helper before reverse scope/pin/activity release.
Unsettled ownership or loss of outer source/folder identity retains access after dropped
error; the existing bounded energy expiry ends activity only. No production recovery
release, stage creation, publication, deletion, directory search, archive action or UI.

Acceptance: generated actual native both-mode review preserving source/candidate/prior
bytes; scopes target exactly source and candidate (not parent), real descriptor and
POSIX denial, live-reader OS idle-sleep assertion and absence after ordinary settlement,
pre/active cancellation, acquisition rollback, joined semantic refusal, final substitution
and controlled typed retained-review/drop/expiry/conflict tests. Fake scope balancing
is not actual sandbox grant/revocation evidence. Retain any actual unsettled fixture;
DEBUG access release only after separately proved controlled generated settlement.
Ordinary regression, explicit optimized build/ad-hoc signatures, privacy/protection and
planning checks; observe PR94 automatic failure without retry. Signing/packaging, owner
mode review, stable import/binding and physical I/O/volume/power durability remain open.

D120 final local outcome: unused concrete reviewCandidate holds only source/candidate
scopes and no-follow pins across D119 native worker/fresh-reader settlement. Shared
preservation/review exclusion and retained-access policy propagate typed unsettled
ownership or outer source/candidate identity loss; dropped errors and bounded energy
expiry do not release access or authorize cleanup. Actual both-mode review preserves
source/candidate/prior bytes. Six added generated checks cover exact grant URLs/reverse
balancing, real descriptor/POSIX refusal, acquisition rollback/pre-cancel, repaired compact
metadata forgery with joined reader, current-PID OS activity/cancellation/conflicts,
controlled retained review after expiry and final directory substitution after join.
Focused14tests/1suite4.989s and ordinary451reported tests/93suites210.803s passed with26
unchanged opt-in skips/no warnings; access suite17.603s ordinary. Explicit optimized
product build and strict ad-hoc app/read-only helper signatures passed without warnings,
minima14.0/11.0, writer absent. Unused backend, no UI walkthrough/release inference.
Seven-file privacy zero matches/positive sentinel, owner source metadata/current journal
unchanged and planning findings empty. PR94 automatic445tests734.974s47issues retained
and PR updated, no rerun or causal claim; D090 timing causes remain unknown.
Next qualify a separately owned relocated hardened generated bundle hosting fixed Rust
reader/writer roles and native operations, with static role admission, actual child loading,
outer seal/notice checks and refusal on substitution. This is ad-hoc generated packaging
evidence, not Developer ID positive trust or release capability. Do not touch Preview
writer packaging or retry D097/D117 signing without changed condition/new discriminator.
See NATIVE-CANDIDATE-ACCESS-EVIDENCE.md.

## D-121: Relocated sealed generated Rust reader-host bundle
Date: 2026-10-04
Status: Confirmed

Authority/Approved for build: owner standing autonomous generated non-audio delegation,
R059 / Slice049. Need: D117 verified individual hardened helper signatures/execution but
not a sealed relocated outer bundle or its notices. Assess host feasibility concretely: a
generated bundle uses the actual read-only Rust reader as its main executable, with fixed
reader/writer helper roles and complete locked dependency/toolchain notices. This avoids
a wrapper or changes to app startup. It is NOT hardened SwiftUI host qualification.

Scope: test-only owned generated bundle, ad-hoc runtime signatures/no entitlements, creator-
captured hashes and fixed role identifiers, actual outer nested/strict seal, relocation and
notice inventory. Actual D116/D120 native operations execute writer helper and reader main
against generated source/candidates. Default Preview remains unchanged/read-only. No
release factory, Developer ID retry, library-validation bypass, unsigned fallback, broadened
entitlements, app action/UI, owner media/queue/archive/encode, merge or release.

Acceptance: relocated outer/role admission and unchanged notices, actual both-mode native
preservation then read-only review with joined workers/children and preserved source/prior
bytes. Outer resource/helper/role substitution refuse before execution. Actual reader-host
active cancellation settles or retains typed ownership/access/fixture. Fake scope providers
are not sandbox grants. Ordinary regression, existing optimized product/signature reuse
(product unchanged), final privacy/protection/planning and PR95 observation without retry.

D121 final local outcome: test-only owned ad-hoc/runtime Rust reader-host bundle has a
strict nested outer seal, fixed D117 helper-role admission, exact repository lock/license
text hashes and active Rust toolchain library notices. Moving it to an owned folder with
spaces preserves admission and actual D116 preservation/D120 read-only review in both
retention modes with source/prior/candidate bytes preserved and native direct children
joined. Notice/Info/helper-role substitutions refuse before capability use. Actual hardened
reader-host cancellation settled ordinarily in all new runs; its typed-retention branch
is not a newly observed OS fault (D120 retention evidence reused). This is not hardened
SwiftUI host, Developer ID or release capability qualification. Product/default Preview
unchanged and read-only; no UI walkthrough. Initial new fixture compilation and test-only
redundant nested require warning retained/corrected without assertion/policy changes.
Expanded focus22tests17.725s passed with that warning; ordinary454reported tests/93suites
210.177s passed26 unchanged skips/no new emitted warnings, then final22tests/2suites5.701s
passed without warnings covering exact local-unwrapping correction. Ordinary native both-
mode pipeline0.749s, substitution2.363s and cancellation0.498s passed. Reuse D120 explicit
optimized product build, current strict ad-hoc app/read-only helper signatures verified,
minima14.0/11.0, writer absent. Original protection/privacy/planning receipts follow before
publication. PR95 automatic451tests799.399s35issues retained/PR updated without retry;
access320.347s passed, causes unknown.
Next assess an actually hardened owned Swift native host/test-module loading fixture,
using existing D118 POSIX caller and fixed helpers, before claiming app-host qualification.
Inspect host/test Mach-O dependencies and signatures first. If same-team/library-validation
requirements refuse ad-hoc test-module loading, retain that discrimination; do not disable
validation, broaden entitlements, fall back unsigned or blindly retry Developer ID. Static
Rust reader-host success is not SwiftUI loading/provenance. A refused host qualification
does not block independent generated edited-picture or stable-archive prerequisites.
See RELOCATED-HARDENED-READER-BUNDLE-EVIDENCE.md for actual checks and limitations.

Final seven-file privacy scan has zero private source path/name/stem matches and a
positive sentinel. Owner source metadata/current recovery journal remain unchanged;
full planning findings empty. Prior owned55829 was stopped only after exact receipt/
command/start inspection; current owned84530 temporary capped assertion expires19:37UTC
and exact command/start matches receipt. No persistent locking/security changes.

## D-122: Discriminate hardened Swift host/test-module loading
Date: 2026-10-04
Status: Confirmed

Authority/Approved for build: owner standing autonomous generated non-audio delegation,
R059 / Slice049. D121 Rust reader-host success is not Swift loading. Local inspection
shows SwiftPM's installed host has get-task-allow, while the ad-hoc test module needs
XCTest/Testing SDK frameworks. Qualify only owned COPIES: remove existing signatures,
explicit ad-hoc runtime signing without any entitlements, fixed installed SDK test-framework
rpath if needed (no DYLD override), sealed owned bundle/fixed helpers and selected native
test entry. No original tool/module edits, app startup/Preview change or redistribution.

Use D118-style sole-owner POSIX caller, exclusive generated root, bounded log/deadline,
owned PID/group and direct join. If module actually loads, require actual D116/D120 both-
mode native operation/semantics, fixed helper joins and source/prior preservation before
finite test-only completion marker. If loader refuses, require its concrete library/team/
signature or missing-dependency diagnostic, joined host, absent entry/completion/candidates
and unchanged source/prior. Unknown crashes/timeouts are failed qualification with retained
fixture, never expected success. No generic runtime bridge or source-selected executable.

Do not disable library validation, broaden entitlements, unsigned fallback, Developer ID
retry, repurpose HOME/CODEX_HOME, owner media/queue/archive/encode/listening, merge/release
or D090 observer/assertion/deadline/concurrency change. A refused new fixture establishes
only scoped loading limitation, not the whole program blocked. Full ordinary/focused
checks, unchanged product optimized receipt/signature reuse, privacy/protection/planning
and PR96 automatic observation without retry.

Outcome: concrete copied hardened Swift host/test-module loading refused with different
Team IDs. Native Security outer/module/helper admission passed, but no native entry or
helper ran; sole host joined, source/prior/root identities preserved. Signed copied
artifacts and diagnostics retained. Initial compilation and first too-narrow diagnostic
classification failures retained/corrected within this new fixture. Ordinary455tests/
94suites208.327s passed26unchanged skips; final focused1test1.300s passed without warnings
after test-only post-join check sequencing. Native success branch remains unexercised.
Product unchanged; D120 explicit optimized build reused, current strict ad-hoc app/read-only
helper signatures/minima14.0/11.0 pass, writer absent. PR96 automatic454tests732.817s27issues
retained/PR updated; timing/phase causes unknown, no rerun or historical change.
Next assess a separately compiled statically linked hardened Swift native host using real
native implementations and fixed generated helpers, independent of XCTest/plugin loading.
This scoped harness limitation is not a statically linked app failure or whole-program
blocker. See HARDENED-SWIFT-HOST-LOADING-EVIDENCE.md for limits.

Final five-file privacy scan has zero private source path/name/stem matches and a
positive sentinel. Owner source metadata/current recovery journal remain unchanged;
full planning findings empty. Current owned84530 bounded awake assertion exact command/
start matches receipt and expires19:37UTC; no persistent locking/security changes.

## D-123: Qualify a statically linked hardened native Swift host
Date: 2026-10-04
Status: Confirmed

Authority/Approved for build: owner standing autonomous generated non-audio delegation,
R059 / Slice049. D122's actual dynamic test-module Team-ID refusal does not establish
statically linked native app failure. Use a separately compiled TEST-ONLY entry linked
with unchanged actual product Swift sources, excluding StaxRipMacApp.swift (the only main).
The non-entry target closure avoids test stubs or copied product implementations; unused
UI/controller definitions may link, but no app, owner workspace/session or queue is created.
Compile installed Swift5 language mode/DEBUG generated capabilities for native macOS14,
then explicitly sign the owned host/bundle ad-hoc runtime/no entitlements and admit fixed
helpers/notices/outer identity. No XCTest/plugin loading or owner-session entry.

Use exclusive generated source/prior/root and fixed finite parameters. Require actual
D116 preservation and D120 review both modes with full native source-dependent semantics,
helper direct-child joins, source/prior preservation and read-only parent review. Qualify
cancellation of a real launched metadata reader in a separately acknowledged generated
boundary; distinguish ordinary cancellation from typed unresolved group ownership and
retain any uncertain fixture/access. One sole POSIX caller owns compiler and native host
PID/groups/logs/deadlines/reaping; unknown failures retain evidence, never native success.
No generic receipt/runtime adapter, Python oracle bridge, app startup/Preview/helper
packaging change, unsigned fallback, widened entitlements, library-validation disablement
or blind Developer ID retry. No owner media body/queue/film archive/encode/listening,
merge/release or D090 historical observer/assertion/deadline/concurrency adjustment.

Acceptance: actual static host loading and native operations after strict ad-hoc outer/
helper/resource admission; truthful host/helper/worker settlement or typed retained review,
source/prior/candidate protection, focused and ordinary tests, unchanged product optimized
build reuse/current signatures, privacy/planning and automatic PR97 observation without retry.
This is not SwiftUI host interaction, positive Developer ID, sandbox grant/revocation,
stable importer/producer binding, decoded/edit association or distribution qualification.

Outcome: owned statically linked hardened Swift native host actually executed D116
preservation/D120 review both modes, six joined helper children and full original native
semantics. A separate live actual packet-stream reader cancelled ordinarily and joined
a seventh child; source/prior/root/notices/signatures preserved. Parent independently
reviewed both outputs. Initial focused1test26.276s, ordinary456tests/95suites212.376s
(26unchanged skips, static host32.018s), final focused1test14.311s passed without warnings.
Final focus covers added thin arm64/system-only dependency checks after ordinary began;
no global concurrency/assertion/deadline change. Product sources/Preview/writer packaging
unchanged; D120 explicit optimized build reused, current strict ad-hoc app/helper signatures
minima14.0/11.0 pass. Actual ad-hoc native code execution is not SwiftUI interaction,
positive Developer ID, sandbox grant/revocation, release packaging or distribution proof.
See STATIC-HARDENED-NATIVE-HOST-EVIDENCE.md. D097 already records ad-hoc hardened decoder
library Team-ID refusal; no redundant retry follows. Next inspect actual C decoder contracts
and qualify a development-only owned native process/frame protocol/resource bridge using
frozen artifacts/generated fixtures. Explicitly ordinary ad-hoc, unbundled and not release
authentication; no validation bypass/certificate retry or PR73 full-source repetition.

PR97 automatic37224662640 failed455reported tests795.389s37issues:15unchanged60-second,
15unchanged120-second and one180-second deadline, three motion message/mutation expectations,
Fresh-analysis cancellation7.004178vs5, measuring-candidate phase EOF, plus NEW fixed module
name mismatch. Hosted SwiftPM uses StaxRipMacPackageTests. Failure/log retained and PR97
updated without retry; historical timing/phase/motion causes unknown. The new fixture fix
admits exactly StaxRipMacTests or StaxRipMacPackageTests and exercises both actual copied
binary/Info layouts with unchanged original module hashes. Both generated layouts retain
concrete Team-ID refusal; no positive dynamic loading follows. Compatibility focused2tests/
2suites12.497s passed (static12.497s, two-layout refusal2.302s), no warnings. This is a scoped
new fixture format correction, not a D090 historical assertion/deadline relaxation.

Post-compatibility ordinary456reported tests/95suites208.749s passed with26unchanged
opt-in skips/no new warnings. Actual static host29.196s and two-layout dynamic-refusal
suite13.211s passed; ordinary cancellation observed. Final focused execution follows
for native-architecture conditional (local arm64 flags/header unchanged).
The changed hosted SwiftPM input correction remains pending automatic qualification.

Final focused2tests/2suites13.015s passed without warnings with native-architecture
selection and both copied SwiftPM layouts. Static native case13.015s cancelled ordinarily
and joined seven helper children; dynamic refusal suite2.324s retained both signed fixtures.
No positive dynamic plugin/Intel/Developer ID/SwiftUI claim follows. Two hygiene findings
in the new planning outcome were retained and corrected; final planning findings empty.

Final seven-file privacy scan has zero private source path/name/stem matches and a
positive sentinel. Owner source metadata/current recovery journal remain unchanged;
full planning findings empty. Current owned84530 temporary awake assertion exact command/
start matches its receipt, expires19:37UTC; no persistent locking/security changes.

## Owner-observed crash notices and routine-test correction

The owner reported repeated crash notices. Read-only recent macOS diagnostic metadata
matched both final copied SwiftNativeHost PIDs to SIGTRAP reports. Their retained logs
show the installed SwiftPM helper's fatal trap after the concrete Team-ID dlopen refusal;
waitStatus5 and joined host are recorded. These are real copied test-helper crashes,
not ordinary exit messages. The actual static native host passed and is a different entry.

Known-crashing dynamic-module qualification is now explicit opt-in through
STAXRIP_TEST_HARDENED_MODULE_LOADING=1. Ordinary tests no longer launch it. Two-layout
refusal evidence remains retained; no opt-in rerun is needed for this guard-only change.
This is a scoped desktop side-effect correction in response to the owner's observation,
not a D090 timing workaround, global scheduling change or silent assertion relaxation.
No macOS crash reporting, library validation, locking or persistent security setting
is altered. Routine-check skip and unchanged actual static execution are verified below.

Final default focused2tests/2suites15.243s passed without warnings: known-crashing dynamic
fixture explicitly skipped once, actual static native case15.242s passed with ordinary
cancellation/seven joined helpers. No copied SwiftPM host launched and no new
SwiftNativeHost diagnostic report appeared. Prior full ordinary456tests208.749s/26skips
evidence predates this guard-only change; the final default focus checks changed behavior.
No known-refusal opt-in rerun or new positive dynamic-loading claim follows.


## D-124: Native development decoder ownership
Status: Confirmed. Approved for build by: owner standing autonomous generated non-audio
delegation, 2026-10-04, R-059.

Build an unused fixed-reference controller and native bounded JSONL stream. Pin explicit
generated source, fixed executable and three sibling libraries by identity/content;
launch only finite source/threads arguments with null stdin/minimal environment.
Strict begin/packet/frame/complete types, counts, geometry, framing/EOF/exit and late
refusal; one owning worker with cancellation/deadline and truthful PID/group/direct-child/
pipe settlement. Unresolved ownership retains needed access through the existing marker.
No all-picture/all-row capture or unqualified original/decoded association flags.

Acceptance: generated byte-chunk grammar/forgery checks, native C surrogate errors/
deadlines/pipe-holder and direct-child join, actual compatible frozen decoder both
thread choices and finite generated conformance/group inputs, actual cancellation/final
source/tool refusal, focused/ordinary regression, optimized build/current signatures,
privacy/planning and automatic PR98 observation without rerun. Record configured caps
separately from measured peaks, and test-only small retained rows from runtime streaming.

Only ordinary ad-hoc DEVELOPMENT; no shipped dependency/UI/queue/archive action,
unsigned fallback, library-validation disablement, signing retry, owner media body or
film run, listening, merge/release or D090 timing observer/assertion/deadline adjustment.
Keep known-crashing dynamic module fixture opt-in disabled. Source/RPU association spool,
release packaging, original/edited picture semantics and total resource limits stay open.

D124 regression dependency corrections remain inside this generated prerequisite.
First ordinary462tests221.225s failed only static host source inventory90 versus actual92;
exact guard updated to92 plus both named decoder files, preserving source/hash compilation.
Second ordinary462tests214.630s passed static host32.488s but one writer fixture could not
copy the helper from shared Cargo release output after a successful build. Its exact
removal cause is unknown. Give the concrete writer-process suite its own target directory
for both generation/build and copy; no global concurrency, deadline or assertion changes.
Retain both failed logs and first owned partial static fixture; focused writer and final
ordinary checks qualify the changed artifact ownership. No product writer/protocol change.

Third ordinary462tests214.567s reproduced shared helper ENOENT in a different original
packet fixture. Extend the artifact ownership correction to the seven remaining shared
writer owners, including their explicit independent test-reader builds/oracle paths.
No changes to actual assertion/phase/deadline/concurrency behavior. Focus71tests/7suites
52.431s passed; compiler emitted existing optional-require/trailing-closure warnings in
recompiled old tests, with no new decoder warnings. Final ordinary qualification follows.

Final ordinary462reported tests/97suites215.532s passed with28 explicit opt-in skips and
no emitted warnings. Actual frozen decoder was separately exercised above; its private
fixture and known-crashing dynamic module remain skipped in normal runs. New decoder
suite6.015s, isolated writer suite14.410s and actual92-source static host32.310s passed.
Optimized product/signature checks remain valid because subsequent changes only affect
test artifact ownership/docs. Sixteen-file privacy scan has zero owner-path/name/stem
matches and a positive sentinel; source metadata/current journal unchanged. Temporary
owned awake assertion renewed only after exact receipt/command/start inspection; no
persistent locking/security changes. Independent native packet/frame/RPU association
and resource/access/signing gates remain open; no UI action/release completion claim.


## D-125: Native bounded association storage prerequisite
Status: Confirmed. Approved for build by: owner standing autonomous generated non-audio
delegation, 2026-10-04, R-059.

Build unused native fixed SQLite packet/RPU spool in an explicit empty private owned
folder, exclusively create its fixed component and pin folder/file descriptors. Record
D110 observations without timestamp uniqueness or RPU deduplication. Enforce finite
pages/rows/cache and cancellation at concrete operations; match source-pass counts and
close statements/database before caller cleanup. Refusals invalidate the pass. No source
path, media payload, helper execution or successful association receipt is persisted.

Acceptance: generated actual D110 source observations, signed duplicate/nonmonotonic
extremes and multiple RPUs, exclusive/mode/link/path substitution, actual configured
SQLite-full/cancellation/refusal settlement, focused and ordinary tests, optimized build,
privacy/planning and automatic PR99 outcome without rerun. Configured storage bounds are
not OS heap measurements or physical ENOSPC qualification. Full native composition,
clock equality/frame coverage and access/resource/signature/UI remain separate gates.

D125 observed prerequisite corrections are retained: recursive new Testing macro
compile refusal, APFS directory link count changing after own component creation,
SQLite no-follow alias refusal resolved by descriptor F_GETPATH, requested OFF journal
not established so checked MEMORY/autocommit selected, and one throwing Boolean compile
expression corrected. Numeric descriptor-only test observation was inconclusive after
close; final checks use actual owned close return values. No automatic partial-file
cleanup, SQLite defensive-policy bypass or crash durability claim. Focus8tests13.144s
plus measured six-test storage focus0.022s pass; actual page cap refuses after194rows
at32768bytes with owned closes successful. Keep all partial/failed logs.

First ordinary468tests/98suites222.982s failed two preceding decoder surrogate child/
join assertions. PR99 automatic separately shows seven absent positive PIDs. Its
new diagnostic could call waitpid(0) and observe another same-group fixture child.
Guard that syscall without accepting missing launch, relaxing its assertion/deadline
or changing product behavior. Changed focus13tests/4suites3.512s passed (one explicit
private frozen-decoder skip). Changed ordinary qualification follows; no blind hosted
rerun or claim about D090 historical causes.

Changed ordinary468tests/98suites213.595s passed with28 unchanged explicit opt-in
skips and no emitted warnings. The original failed468tests222.982s/two issues is
retained. The changed run verifies the guarded diagnostic with current code; it does
not identify why prior surrogate launches were absent or fix hosted deadline reliability.
No known-crashing dynamic loader or private frozen decoder was enabled. Remaining
source/spool/decoder composition and full association flags stay unqualified.

Explicit release build observed Building for production and completed52.63s with no
warnings. Current strict ad-hoc app/read-only helper signatures pass; minima14.0/11.0.
Writer and decoder remain absent. Nine-file privacy scan has zero owner path/name/stem
matches with positive sentinel; source metadata/current recovery journal unchanged,
no owner media body read. Planning findings empty. Owned19716 temporary awake receipt/
command/start remain matched, expires21:30:44UTC. No persistent security setting change,
UI walkthrough, positive certificate loading, distribution or full association claim.


## D-126: Native source-only facts and owned spool pass
Status: Confirmed. Approved for build by: owner standing autonomous generated non-audio
delegation, 2026-10-04, R-059.

Extend concrete D109/D110 source walkers with source-only reads that never request
companion files. Derive selected TrackEntry/hvcC and original packet/raw-RPU facts from
source; component-match flags stay false. Existing original-component checks remain
required in their current APIs. Join one actual D108 source owning worker and D125
exclusive private spool, checking full initial/final source content and identity and
all worker/spool closure before success. No decoder execution or association claim.

Acceptance: generated native source walker facts versus existing source/component
checks and independent test-only Rust/Python oracle, signed duplicate/extreme timing,
multiple RPUs and malformed framing, actual cancellation/source/spool/final refusal,
configured SQLite-full, focused/ordinary regression, optimized build/signatures,
privacy/planning and PR100 automatic observation without retry. Only generated fixtures;
no owner body, helper selected by source, audio listening, UI, signing retry or release.


D126 evidence: NATIVE-SOURCE-SPOOL-EVIDENCE.md records actual source-only4packet/
5RPU/1EL both-mode rows matched against native original facts and test-only oracle,
all widths/Segment modes/signed extremes/unsigned duration, malformed sources,
actual read/final cancellation and source/spool mutation, configured SQLite-full.
Focus46tests5suites13.306s and ordinary474tests98suites210.730s pass with28 unchanged
skips/no warnings. Source-frame/edit and companion-match flags stay false for the
source-only result; old companion APIs remain stricter. PR100 automatic failed
468tests1141.409s98issues; retained without retry or historical policy changes.

Explicit optimized build observed Building for production and completed19.74s, no
warnings. Current strict ad-hoc app/read-only helper signatures pass, deployment
minima14.0/11.0. Writer and decoder remain absent. Ten changed files pass privacy
scan with zero owner path/name/stem matches and positive sentinel. Owner source
metadata and recovery journal remain unchanged; planning hygiene has no findings.
These checks do not qualify signing provenance, native archive action or frame edits.


## D-127: Native independently reconstructed source/frame association
Status: Confirmed. Approved for build by: owner standing autonomous generated non-audio
delegation,2026-10-04,R059.

Bind D124 actual native development decoder on the existing D126 pinned source
worker to the still-open D125 spool. Reuse independent source-only TrackEntry/hvcC,
original encoded packets and raw escaped RPUs. Add fixed bounded packet/frame
coverage and overflow-safe exact rational timing. Refuse missing/surplus/nonoutput/
ambiguous records, never deduplicate. Completion requires all source/table/decoder
counts, source/config/raw/packet equality, final source/tool/spool observations and
actual worker/helper/database/source settlement. Source-only/process APIs stay partial.

Acceptance and effects follow D127 decision: generated frozen both1/four-thread
actual trials, plausible row forgeries and coverage/storage/cancellation/late refusal,
focused/ordinary/optimized build/privacy/planning; no owner body/action/packaging/
film/listening/certificate retry. Complete source-frame result remains distinct from
rendering, EL, edits, immutable snapshots, production provenance and distribution.

D127 evidence: NATIVE-SOURCE-FRAME-ASSOCIATION-EVIDENCE.md. Actual opt-in2.479s
passes ten generated both-thread associations,15 joined helpers including final
mutation/after-join/live cancellation refusals. Twelve schema-valid plausible
forgeries fail native source/coverage binding, exact clock overflow/fraction tests
pass. Focus36tests13.072s/ordinary479tests210.792s pass29skips/no warnings; explicit
optimized19.56s/current strict ad-hoc signatures pass, no decoder/writer bundled.
Source-frame flag is true only in settled composition; source-only/process flags
and all edited-picture flags remain false. Owner metadata/journal/privacy/planning
checks pass. No production/rendering/EL/edit/hardened-loading claim. PR101 automatic
failed68issues, retained without retry or timing policy changes.


## D-128: Concrete source/frame association access ownership
Status: Confirmed. Approved for build by: owner standing autonomous generated non-audio
delegation,2026-10-04,R059.

Extend the existing concrete operation with only explicit original-source/spool-folder
access and activity around D127. Reuse exclusion and retained review policy. Actual
no-follow opens precede activity. Scopes/pins remain needed until source/database/
worker/helper settlement and final observations. Ordinary release balances in reverse;
uncertain ownership/close or outer substitution retains access after dropped errors.
Do not remove the caller-owned folder or infer parent grants. Acceptance follows D128
with generated real permission/cancel/substitution and frozen actual decoder trials,
focused/ordinary/optimized/privacy/planning checks. No owner body, action, signing,
release, known-crashing dynamic loader or completed full-source repeat.


D128 acceptance: final composed22tests8.913s includes actual frozen both-thread
association2.272s/six joined helpers and ordinary live cancellation. Generated grant/
activity/read-write refusal/source cancellation/controlled close and retained review
checks pass. Final ordinary485tests/98suites210.801s passes30explicit opt-in skips/no
warnings. New actor-trait/error-type/finite-Segment/gate/descriptor-number fixture
failures retained with scoped corrections, no global policy change. PR102 automatic
479tests1218.685s129issues retained/PR updated without retry; causes unknown. See
NATIVE-SOURCE-FRAME-ACCESS-EVIDENCE.md for concrete scope and remaining gates.


## D-129: Actual base-picture sample prerequisite
Status: Confirmed. Approved for build by: owner standing autonomous generated non-audio
delegation,2026-10-04,R059.

Build the separate DEVELOPMENT C plane-measurement/sample probe in D129, bounded
coded versus codec-visible10-bit420 views. Qualification uses actual generated planes
and row-streaming test-only oracle, no full-picture parent capture. Never change five
frozen D097 objects or original metadata protocol. No native sample/edited admission,
colorimetric/HDR conversion, EL, resampling or app action follows. Acceptance/effects
match D129; preserve source/session/journal/prior outputs and retained artifacts.


D129 acceptance: generated five-group installed sample suite4.958s and compatible
minimal LGPL-prefix suite17.034s pass, including ten actual both-thread coded/codec-
visible plane trials, sanitizer bounds/maximum arithmetic, live cancel/path substitution
and exclusive builder refusal. Separate sample artifact min14.0 and original-prefix
libraries observed; frozen five objects unchanged. Ordinary485tests/98suites211.948s
failed one existing writer-surrogate child-settlement assertion,30 unchanged opt-in
skips, no warnings; retained without retry/relaxation/cause claim. Product unchanged,
D128 explicit optimized receipt reused and current strict ad-hoc signatures pass.
PR103 automatic113issues retained/PR updated, no retry. Source metadata/current
journal/privacy/planning checks pass. See DECODED-BASE-SAMPLE-EVIDENCE.md; native
sample/source binding, rendering/color/EL/resize/edited flags remain unqualified.


## D-130: Native base-sample ownership prerequisite
Status: Confirmed. Approved for build by: owner standing autonomous generated non-audio
delegation,2026-10-04,R059.

Use the existing concrete decoder worker with a separate fixed sample role/profile,
strict bounded typed plane admission and actual generated process qualification as
D130. Default metadata parser/schema/role remain unchanged. No independent original
sample-source proof, color/EL/rendering/edited qualification, archive action or release
capability follows. D127 open-source/spool binding and D128 access remain later gates.
Preserve original/frozen objects and owner state, keep generated artifacts private.


D130 acceptance: final composed15tests/5suites12.996s passes, actual native ten
generated sample trials/13helper joins and ordinary live cancellation. Deliberate
consumer refusal propagated group-1-joined-true and retained files. New26-key count
correction and release-only missing boundary argument failure retained; corrected
production build/signatures/minima14.0/11.0 pass. Ordinary492tests/100suites210.495s
passes31opt-in skips/no warnings before release-only fix; final default14tests3.803s
passes after it, DEBUG behavior unchanged. Fixed role/profile remains development-
only; source-frame/sample-source and edited flags stay false. PR104 reader
passed/app105issues failed; retained without retry or timing policy changes. See
NATIVE-BASE-SAMPLE-PROCESS-EVIDENCE.md for actual scope/limits and next source binding.


## D-131: Native original source/sample association
Status: Confirmed. Approved for build by: owner standing autonomous generated non-audio
delegation,2026-10-04,R059.

Use distinct sample entry on the existing pinned source/open SQLite owning worker.
Explicit sample coverage accepts typed summaries and raw original frame relationships;
no metadata normalization, closed-store adoption, second worker or Python runtime bridge.
Require original source/config/packet/hash/escaped-RPU/timing/one-picture coverage and
complete sample counts, joined helper/EOF/zero result/final observations/checked spool
and source closes before returning source-dependent sample agreement. Fixed decoder
statistics are not independently remeasured pixels, linear luminance, rendering, EL,
container/user crop, resize or edited metadata; all edited/value-proof flags stay false.

Acceptance: actual generated compatible sample tool both threads/source variants,
repaired plausible source/coverage/summary forgeries, reordered/duplicate/missing/surplus
and invisible records, resource/storage/cancel/late/substitution refusal and settled
worker/database/helper ownership. Preserve typed unsettled retention and owner/frozen/
artifact/session/journal/prior bytes. No action/UI/release/default packaging/signing/movie/
listening work; focused/ordinary/optimized/privacy/planning checks, automatic outcomes
without rerun. Resource/access integration and every rendered/edit gate stay separate.


D131 acceptance: final focus28tests/5suites3.451s passes, actual native ten generated
source/sample trials/15helper joins with ordinary observed live cancellation. Short
fault3 group-1-joined-true uncertainty propagates and retains generated files. Twelve
plausible source forgeries, both-profile missing/ambiguous/invisible coverage and typed
sample coverage refusals close the open store. Initial new macro compile/status-format
failures retained with exact scoped corrections. Ordinary496tests/100suites209.636s
passes32opt-in skips/no warnings; explicit production/current strict signatures/minima
14.0/11.0 pass with sample/decoder/writer absent. Seven-file privacy/owner metadata/
journal/old sample-prefix-frozen-runtime/planning checks pass. PR105 automatic80issues
retained/PR updated without retry or historical timing policy change. See
NATIVE-SOURCE-SAMPLE-ASSOCIATION-EVIDENCE.md. Source agreement true only on the new
complete composition; independent sample values/rendering/edited flags remain false.
Resource/access/checked helper close and release qualification remain separate gates.
