# Generated conversion trial and isolated native inspection

D173 advances the working Dolby Vision conversion journey. A generated P7 input now passes the native inspector, and a separate HDR10 base-layer copy trial passes bounded output checks. **The app cannot yet queue this conversion.** P8.1, HDR10 fallback and tone-mapped SDR remain unqualified product routes. This is not a conversion-workflow or milestone completion claim.

## Native demonstration isolation

A DEBUG build accepts `STAXRIP_DEMO_JOURNAL_ROOT` only for an existing, current-user-owned, private generated directory named `staxrip-demo-<UUID>`. It derives `demo-batch.json`, refuses path aliases and existing journal/lock files, and creates no directory during selection. An invalid request selects no journal and blocks Start before lease, checkpoint, activity or task creation. A requested demonstration never falls back to normal recovery. The queue displays a separate-journal label. Release behavior and saved-session/recovery schemas are unchanged.

The integration owner created a fresh private root and a distinct ad-hoc demonstration bundle. Actual accessibility actions opened its Queue and observed the isolation label, selected only the generated source, and opened the media inspector. The app reported 3840×2160 Main10, 24000/1001, PQ/BT.2020, Dolby profile 7, level 6 and compatibility ID 6. The full metadata action completed: eight RPUs, mapping family 7/minimal enhancement metadata, independently checked encoded packets. Native preview was unavailable for this MKV. No conversion was queued or output published by the app.

The normal recovery journal matched the owner's explicitly authorized current baseline before and after. The earlier mismatch record remains false with its writer unknown; this observation does not rewrite it. No owner queue or movie was processed. The demo did not start a batch, so it created no demo journal; generated controller tests separately exercised checkpointing. Path/attribute checks are first-launch checks, not pinned-directory or hostile-substitution guarantees. Existing records are never adopted for a repeat demo launch.

The owned app was closed using its inspector Done and ordinary Quit actions, followed by actual process absence. An earlier programmatic termination request did not produce absence while the inspector was open; no force signal was used. Accessibility evidence is retained privately. Capturing the owned inspector window failed, so there is no screenshot claim.

## Bounded generated backend trial

Pinned installed FFmpeg/FFprobe 9.0.2 and dovi_tool 2.3.4 were used, without rebuilding or replacing frozen evaluation runtimes. Eight 3840×2160 Main10 PQ gradient pictures at nominal 24000/1001 were generated with static mastering and content-light metadata; a synthetic half-resolution enhancement stream and generated CM2.9/MEL RPUs were muxed. This is a generated codec/metadata fixture, not Dolby-certified enhancement reconstruction or calibrated display evidence.

The initial Matroska fixture lacked a Dolby configuration record and was retained as an unqualified initial artifact. Fresh bounded fixture assembly added the intended P7/L6/CCID6 declaration. Its earlier assertion was explained by the generated TrackEntry's existing zero MaxBlockAdditionID; the corrected assembly replaced that generated value, added the mapping, and removed optional offset indices/affected CRC. Original fixture bytes were preserved. This generator is not a product importer or runtime bridge.

The candidate copy used `dovi_split=mode=bl,dovi_rpu=strip=1` with video stream copy, no audio, subtitles or data. Actual checks on all eight packets/frames found:

- Output NALs equal the source's ordered retained base-layer NAL bytes; eight RPU units and twenty enhancement wrapper units were removed. Output contained neither type 62 nor 63.
- Packet PTS, DTS and durations matched exactly in the 1/1000 container time base. Nominal rate remained 24000/1001; millisecond quantization is not exact per-frame rational timestamps.
- The output had no Dolby configuration or per-frame Dolby metadata, and retained static mastering/content-light metadata on every decoded frame.
- Geometry, Main10/PQ/BT.2020/limited range and actual top-left chroma remained. Every decoded YUV420p10 frame checksum matched using the same installed decoder. This is not an independent decoder or vendor Dolby rendering oracle.

This establishes a finite **HDR10 base-layer copy with Dolby Vision loss**, not re-encoding, P8.1 conversion, SDR tone mapping, full-film coverage or native queue admission. The future product route requires explicit loss acknowledgement and complete native verification before exclusive publication. The general HDR guard is unchanged.

## Checks and retained limits

Three new recovery tests cover private-root selection, invalid/existing/alias refusals, no-start/no-checkpoint behavior, and an intentionally refused demo job recorded only in its generated journal. Initial test compilation attempted to mutate an immutable fixture field; corrected construction preserves the model. A new full-job equality assertion then exposed the fixture's subsecond timestamp versus ISO8601 journal precision; a whole-second fixture preserved the full assertion. Both logs remain. Recompilation emitted two existing async-main-thread warning sites, no new site. Source review strengthened only the new test's timeout path to retain its fixture unless the task actually settled.

The final product ordinary run passed **670 reported tests in 105 suites, 217.989 seconds**, with forty unchanged opt-in skip identities and no emitted warnings. It precedes the sole later new-test cleanup guard; the final three-test focus passed in 0.020 seconds. No ordinary retry. The debug app build reported 0.15 seconds; the explicit optimized build reported 23.33 seconds. Current strict ad-hoc app/read-only-helper signature and minimum-version checks are separate from Developer ID or release trust. The static 94-source host runs prior preservation/review, not this native app journey or a conversion verifier.

Parent PR145's exact automatic run compiled and failed 667 tests after 769.445 seconds with fifteen issues: two unchanged 60-second bounds, two 120-second bounds, nine child/close assertions and two mastering EOF expectations. Seven of 32 historical instrumented decoder calls refused before launch; their categorical stages are retained. The other 25 launches do not settle older failures. The forty-second shared-fixture preparation passed. Full log retained without manual rerun, deadline changes or a common-cause inference. The approved live-work cancellation repair remains to be implemented; the ChapterPlan queue proposal stays on hold.

## Next acceptance

Add one distinct HDR10 base-layer-copy intent and explicit Dolby-loss acknowledgement to the existing configuration/queue path. Fresh source admission and a dedicated filtered-packet/configuration/frame/timing verifier must precede exclusive publication. Surface the verified outcome and actual destination in Completed. Keep P8.1 and genuine tone-mapped SDR visibly unavailable until their separate contracts pass. Continue the native journey in a fresh isolated journal root. All five milestones and existing ownership, recovery, signing and media restrictions remain open and preserved.
