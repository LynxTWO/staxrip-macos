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
