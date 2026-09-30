# StaxRip Mac Slice 011: Verify retained chapters and attachments
Version: 0.1. Date: 2026-09-30. Status: Planned.

SLICE STATE
Milestone: Activated after Slice 010 hosted success at 087adcc.
Blocked by: None external.
Evidence so far: Generated MKV preserved chapter gaps and attachment SHA-256; MP4 changed chapter gaps and timestamp precision. Explicit limits are recorded in the local feasibility note.
Last audit: 2026-09-30.

## 1. What the slice proves

An advanced queue job checks the flat chapter titles/times and attachment bytes that its existing mapping intends to retain before publishing. A tool reporting success is insufficient if a chapter or attachment was lost or altered. Unsupported source metadata gets a clear refusal before encoding where detectable.

## 2. The walkthrough

1. Queue generated video containing chapters and an attachment, using MKV and embedded subtitles retained.
2. Check queue validates source metadata needed for the contract. Start queue encodes, then compares staged chapter title/times and attachment names/types/sizes/hashes before publication.
3. Completed detail states the scoped counts verified. Inspector can show the output's reported contents separately.
4. MP4 retains compatible chapters but omits attachments under the existing mapping. Nonzero first chapter or gaps require MKV rather than silent MP4 modification.
5. Trimmed jobs retain the existing rule of removing chapters; removing subtitles retains the existing rule of not mapping attachment streams. Unexpected output entries or mismatches refuse publication.

## 3. In scope, with build order

M1: Add optional extra-data size/hash fields and request SHA-256 in the bounded probe. Add a typed ephemeral container contract from the source and existing configuration.
M2: Bind the contract to EncodePlan, validate staged metadata before exclusive publication, and record verification counts. Keep the existing map_chapters and attachment mapping rules.
M3: Pure mismatch/bounds cases, generated actual MKV/MP4/trim/removal exports, deliberate staged mismatch refusing publication, source/prior-output/owned-staging checks, native generated encode and output inspection, regression and hosted validation.

## 4. Out of scope

New chapter controls/editor, arbitrary chapter tags or Matroska editions, exact player-navigation equivalence, cover-art preservation, remux UI, attachment extraction/font loading, audio processing/listening, new saved fields, merge and release.

## 5. Stubs and debts

Only the explicitly retained flat chapter title/time subset and attachment payload/name/type/size are verified. Other container metadata remains outside this claim. Unretained categories must be absent in output. Missing/empty titles both mean untitled; other title content is compared exactly. MP4 chapter sets must start at zero and be contiguous. Timing comparison allows one output chapter tick plus 0.1 microsecond arithmetic slack; refuse output tick sizes over 1 millisecond. A mismatch fails with nothing published.

## 6. Modules touched

MediaProbe in ToolRunner.swift, new ContainerPreservation contract, EncodePlan, BatchController verification/result detail, targeted tests and documentation. Queue preflight consumes the existing plan and therefore source contract validation without writing output.

## 7. Data subset

Process-local contract only: at most 10000 flat chapters and 1000 retained attachment streams. Positive finite rational time bases, nonnegative ordered chapter ranges, title/name text bounded to 4096 UTF-8 bytes and MIME type to 1024 bytes and valid SHA-256 plus nonnegative byte size at most Int32.max for retained attachments. Source chapter extent capped at 1 billion seconds to keep arithmetic well bounded; output chapter ticks must be no coarser than one millisecond. Never interpret filename metadata as a filesystem path. No recovery/session migration.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S11-001 | Actual retained MKV chapters and attachment bytes match the source contract before publication | Generated real queue export and independent attachment digest | container-preservation-mkv |
| S11-002 | MP4 time-base/ID changes are handled without accepting changed chapter meaning; unsupported gaps are refused | Quantization fixtures and real MP4 export | container-preservation-mp4 |
| S11-003 | Existing trim/subtitle-removal policies produce the expected absent categories | Actual trimmed and removal exports | container-preservation-routing |
| S11-004 | Missing/malformed hashes, timing, excessive counts or staged mismatches cannot produce a published success | Pure bounds/mismatch tests and deliberate encoder-wrapper alteration | container-preservation-refusal |
| S11-005 | Native successful queue result explains verified scope and output inspection shows retained contents | Generated native encode and inspector walkthrough | container-preservation-ui |

## 9. Verification evidence required

Focused contract tests plus real generated-media integration, independent byte digest, staged mismatch rejection/cleanup, source and prior-output preservation, regression, optimized build, native walkthrough and hosted check. No general metadata conformance campaign or new audio evaluation.

## 10. Guardrails

No publishing before comparison passes. No source or prior-output replacement. Keep completed output safe if later cleanup/journal operations fail. Preserve mapping rules and make limits explicit. Never claim all container metadata, cover art, chapter editions or fonts are verified. No automatic attachment loading or metadata-derived path use.

## 11. Definition of done

S11-001 through S11-005 have bounded local evidence and hosted status; remaining metadata/platform limits are recorded. No production-complete or listening acceptance claim.

## 12. What this unlocks

Future explicit chapter editing and attachment policies can supply the same verifier with a transformed expected contract. A remux workflow still needs separate packet/timing guarantees.

Approved for build by: Owner autonomous non-audio delegation on 2026-09-29, reaffirmed 2026-09-30; activate under D-024 after Slice 010 closure.
