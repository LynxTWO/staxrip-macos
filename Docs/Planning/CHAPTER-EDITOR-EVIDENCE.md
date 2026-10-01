# Chapter editor evidence

Date: 2026-10-01. Slice 030 under D-044 / R-034. Scoped acceptance complete at product head 0105d5c plus diagnostic-only ded74f6. Final release regression passed 222 tests / 46 suites in 38.389 seconds; native rebuild/walkthrough passed; final hosted run 36824096245 passed. The earlier intermittent destination-review timeout remains a recorded reliability debt, not a claimed repair.

## S30-001 through S30-003: bounded authoring and actual exports

Chapter edits are optional source-specific intent. Nil retains the previous preservation policy; Remove maps no chapters; Custom supplies validated flat source-timeline ranges with stable IDs. Validation refuses empty/excessive lists, duplicate IDs, negative/zero/overlapping/unordered/over-seven-day ranges, empty/excessive/control-character titles and ambiguous time text. Custom source compatibility requires video start_pts zero and a known duration up to seven days.

Generated tests export seven variants in each of MKV and MP4: authored, exact-boundary trim, fractional trim, excluded list, removed list, source preservation and legacy trim omission. Literal titles include Unicode, backslashes, metadata punctuation, section-like text and leading/trailing spaces. The serializer escapes spaces as well as ffmetadata delimiters. Source bytes remain unchanged. Exact trim boundaries discard nonoverlapping entries before FFmpeg can introduce zero-length chapters; microsecond metadata retains supported fractional offsets. MP4 gap/late-start lists refuse; MKV retains gaps.

Expected output titles/ranges are derived before encoding and checked through an independent output probe. Counterexamples reject changed titles, bounds, count, zero-length ranges, coarse timing and ambiguous title tags. The existing tolerance remains actual chapter tick plus 0.0000001 seconds, with output ticks no greater than one millisecond. No tolerance or existing deadline was relaxed.

Review added a negative control for canonically equivalent but byte-distinct Unicode chapter titles. Before repair it failed seven checks: draft/configuration/queue change detection, undo history/restoration, changed-output detection and ambiguous tags. Chapter entries and drafts now compare title UTF-8 bytes, output chapter verification does the same, and conflicting metadata tags use byte-distinct values. The failing log is retained locally. This prevents a visually identical edit from leaving stale intent or silently accepting altered title bytes.

## S30-004 and S30-005: documents and operation ownership

Session version 7 and recovery version 6 retain edits and reject nonnil chapter edits labelled with earlier schemas. Nil legacy documents remain valid. Unknown modes, malformed intervals and future versions refuse. Presets exclude chapter lists and retain the current source's list when applied. New source imports clear it; saved-source review retains it. Undo/redo and queue value copies preserve independent source intent.

Aggregate chapter count is bounded to 10000 across a document. Session saving now enforces the same 5 MB boundary as reading; the existing recovery boundary stays in place. Oversized generated writes preserve prior session/journal bytes.

The app owns source chapter reads until they settle, even after editor cancellation. Controlled readers cover cancellation, failure, late results, draft mutation, overlapping begin calls and changed source/settings at Apply. The isolated draft supports add, remove, split and sort; invalid text cannot apply. Source import explicitly replaces the draft and reports millisecond rounding. Closing cancels the read, and app termination is refused while that owned read is settling.

## S30-006: native generated walkthrough

The macOS 27.0.1 ad-hoc app opened generated six-second H.264 media. Option-Command-5 selected the fifth chapter recipe section. Explicit source import populated three labelled title/start/end rows and a timeline. Editing then cancelling left Preserve source chapters selected; reopening presented an empty draft, proving no cancelled list had leaked.

A second import retained literal punctuation and Japanese titles. Typing 1e3 into a time field disabled Apply and explained decimal input. Repairing it and splitting the first chapter produced four contiguous ranges and a readable four-segment timeline. Removing the second segment produced an MP4 gap and a specific refusal; extending the first range to two seconds restored Apply. The sheet screenshot showed readable labels, timeline, rows, status and both footer actions; keyboard Tab moved between fields.

Applying created a three-chapter recipe. Native session saving retained exact IDs, millisecond ranges and Unicode titles in schema 7. After changing the workspace to Remove, the queued copy still opened the custom three-entry draft in its nested editor. Cancelling both editors retained the queued configuration. Reopening the saved session required explicit replacement and did not start work.

The restored queue then reviewed its exact output folder and completed. The app reported verified three chapter titles/times and an unchanged source fingerprint. Independent ffprobe inspection confirmed the edited literal titles and ranges 0-2, 2-4 and 4-6 seconds. Source/session/prior-file hashes stayed identical, no owned staging remained, and the completed generated journal was retained locally. The original recovery journal was restored byte-for-byte only after app exit.

Native review found an old trim-help sentence that contradicted custom chapter behavior; it was corrected to explain default omission versus custom clipping. Native input simulation initially omitted Japanese characters when typing; clipboard insertion and independent saved/output byte checks verified the intended text. No product encoding defect is inferred from that input-tool limitation.

## S30-007 and S30-008: coexistence and regression

Real production batches combine custom chapters with an external SRT in both containers, verify added caption cues and chapter titles, refuse a later output collision and preserve source/caption/output bytes. Preflight leaves the directory unchanged. The static HDR10 production fixture with content-light metadata now also carries two authored chapters while retaining its existing full-frame HDR audit. The no-content-light path retains its previous default behavior.

The initial focused combined run passed 16 test declarations across five suites in 0.966 seconds. One earlier expected summary word was wrong: the product reports external caption cues, not captions. That assertion wording was corrected; actual exports and checks were retained. Initial full release passed 221 tests / 46 suites in 38.165 seconds; the app build passed in 15.99 seconds. Subsequent whitespace-title export checks passed both containers. Final Unicode-repair regression, final native rebuild and hosted gate are recorded at closure.

Local receipts remain in ignored chapter logs, chapter-discovery and chapter-native directories. No generated media, binary, personal path or credential is committed. Audio listening is parked. Broader player seek behavior, nested editions, nonzero source origins, external chapter files, other machines/OS versions and heard VoiceOver remain outside this evidence. No merge or release is performed.

Final local checkpoint: 222 tests / 46 suites passed in 38.555 seconds after the Unicode repair. The final ad-hoc build reopened successfully; the revised trim guidance was visible, Option-Command-5 selected Chapters, and the dark draft sheet retained readable controls/timeline/footer with source import disabled for demo media. Escape discarded the draft. The original light appearance was restored and the app exited. Hosted acceptance remains pending.

A second serialization negative control attached combining marks to metadata delimiters. Both actual MKV/MP4 tests refused changed output titles under the character-based serializer. Escaping now iterates Unicode scalars, so an ASCII delimiter remains escaped even when Swift groups it with a combining mark. The negative log is retained. Final scalar-repair regression/build/hosted checks supersede the earlier product head.

Final scalar-repair local regression: 222 tests / 46 suites passed in 38.389 seconds, including both actual combining-delimiter outputs. No assertions or tolerances were relaxed.

Hosted interim checkpoint: run 36822641744 passed at e6b6f82 on Swift 6.1.2, 222 tests in 404.174 seconds. Chapter suites passed (export suite 47.388 seconds); queue destination review passed in 47.541 seconds. This predates the combining-delimiter repair. Final product head 0105d5c requires its own run 36823007963; that result remains pending. Final scalar-repair ad-hoc build passed in 16.40 seconds.

The final 0105d5c bundle reopened natively. A draft title with surrounding spaces, accented text, punctuation carrying combining marks and Japanese text applied and reopened visibly intact. This checks final native input/state retention; actual serialized MKV/MP4 byte verification is supplied by the final regression. The app then exited.

Final hosted failure: run 36823007963 at 0105d5c passed chapter tests but failed matchingFoldersStartOneRealBatchAndSkipCompletedDestinations at its unchanged 60-second limit. The whole run reported 222 tests with one issue in 442.969 seconds. The failing log lacked destination phase timing, so no stuck phase or root cause is established. A diagnostic-only follow-up adds elapsed fixture, batch phase and independent-probe timestamps without changing scheduling, assertions, fixtures or deadlines. A focused local debug oversized-document test passed in 0.279 seconds; that does not explain hosted timing. Full local debug destination trace finished all assertions 4.733 seconds after entering its body (6.098 seconds reported by Testing), with all three jobs completed. Final full debug and hosted diagnostic results remain pending.

The full local diagnostic debug run passed all 222 tests / 46 suites in 200.628 seconds. Destination-review assertions and the one-minute bound stayed unchanged. Hosted diagnostic run 36824096245 at ded74f6 is still required; the earlier hosted timeout is not called fixed by this local pass.

## Closure and retained timing uncertainty

Hosted diagnostic run [36824096245](https://github.com/LynxTWO/staxrip-macos/actions/runs/36824096245) at ded74f6 passed all 222 tests in 497.428 seconds on Swift 6.1.2. Destination review passed in 54.314 seconds. Its monotonic trace entered the body at zero, completed source creation at 10.503 seconds, started the batch at 10.505, finished the first job by 19.347, reached the second encode at 47.193, settled the batch at 52.717 and finished all independent probes/assertions at 52.986. The largest observed interval was the second inspection, but the failed prior run had no trace; this does not establish its cause. Buffered hosted log timestamps are not phase timing.

Classification: verified observed behavior for S30-001 through S30-008 on the recorded generated local/native/hosted paths; user_data consequence applies to saved intent and derived outputs. Source identity is 0105d5c with unchanged product code at ded74f6. The existing test remains enabled with its original one-minute deadline, assertions and fixture. The intermittent hosted timeout is unresolved; one later pass does not prove it fixed. Reopen if it recurs, using the retained phase diagnostics. Broader performance and scheduling guarantees are excluded from chapter acceptance. No merge or release occurred.
