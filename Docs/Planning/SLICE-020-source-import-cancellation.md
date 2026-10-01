# StaxRip Mac Slice 020: Owned source import cancellation
Version: 0.1. Date: 2026-09-30. Status: Done with scoped evidence under D-033 / R-023.

SLICE STATE
Milestone: S20-001 through S20-004 accepted within SOURCE-IMPORT-EVIDENCE.md limits.
Blocked by: None; Slice 019 closed at 5ede61e with hosted run 36796194802.
Evidence so far: Product 1933bee, 184 local/hosted tests, scoped native checks and cancellation negative control; hosted run 36799453765 passed.
Last audit: 2026-09-30.

## 1. What the slice proves

The workspace owns its active source inspection, can cancel native and fallback work, and never applies stale source information. Cancellation leaves the prior workspace intact; returning to demo cancels outstanding reads as well as changing the display.

## 2. The walkthrough

Load generated media and inspect the native preview. Cancel a controlled pending source load and observe the waiting/completed state while the prior source remains. Request a replacement while older work is cancelling; only the latest source is inspected after the prior worker settles. Open a generated unsupported native container through the FFmpeg fallback.

## 3. In scope, with build order

M1: Reject empty/nonregular local source paths before native inspection, then extract a cancellable native/fallback source inspector with nontrapping display formatting for nonfinite or unrepresentable metadata, plus AVAsset.cancelLoading and explicit cancellation propagation before fallback. M2: Own one active worker and one latest pending request in WorkspaceModel, preserving generation and file-panel intent guards. M3: Distinct Cancel source loading control, clear waiting status, deterministic lifecycle tests, generated native/fallback tests and native walkthrough. M4: Regression/build/hosted acceptance.

## 4. Out of scope

Durable bookmarks, guaranteed permission recovery, arbitrary filesystem deadlines, source snapshots, encoding or audio changes, new saved schemas, merge and distribution. This does not diagnose every restored-source delay as an access error.

## 5. Stubs and debts

AVFoundation cancellation is requested through its supported API and fallback process cancellation through ToolRunner. No early completion may imply that a held worker has settled. UI remains responsive while waiting; a pathological I/O wait remains explicit. Returning to demo may update the display immediately, but the old worker remains tracked until settlement.

## 6. Modules touched

New SourceLoader service, WorkspaceModel ownership, WorkspaceView controls/status, focused native-resource/model/fallback tests and scoped evidence.

## 7. Data subset

One active task/asset or fallback process and one replaceable pending source request. Source result contains preview availability and display information. Keep paths transient, retain prior workspace until a current successful result, and never serialize runtime handles or cancellation state.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S20-001 | Native cancellation settles the owned asset without starting fallback | Held AVAssetResourceLoader case and cancellation negative control | import-native-cancel |
| S20-002 | Fallback and stale operations cannot change newer intent | Held model and process tests, latest-only replacement, failure/cancel cases | import-lifecycle |
| S20-003 | Supported native and fallback imports retain current behavior | Generated MP4/MKV, regular-file refusal, invalid display metadata and source-specific setting/reset assertions | import-compatibility |
| S20-004 | Cancellation and waiting state are clear in native controls | Native walkthrough, accessibility tree, regression/build/hosted | import-ui |

## 9. Verification evidence required

Actual held native resource cancellation; no fallback after cancellation; real fallback process settlement; one active/latest pending behavior; stale success/error/cancel rejection; current success and failure; prior source/settings/output retention on cancel; demo reset and session restoration; generated native and unsupported-native formats; native control labels and progress; full local/hosted receipts.

## 10. Guardrails

No untracked source-load worker, overlapping native/fallback inspections, or abandoned subprocess. Await actual settlement before the next request starts. Preserve current settings and prior source on cancelled imports. Retain file-dialog generation checks and source-specific reset rules. Do not convert cancellation into an error alert or fallback attempt.

## 11. Definition of done

S20-001 through S20-004 have scoped local/native/hosted receipts. Audio and durable file access remain separately open.

## 12. What this unlocks

More predictable source replacement and a clear foundation for later access recovery, import progress and bookmark handling.

Approved for build by: Owner autonomous non-audio delegation under D-033 / R-023 after Slice 019 closure.
