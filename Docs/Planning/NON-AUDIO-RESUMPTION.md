# Non-audio resumption checkpoint

Date: 2026-09-29. Owner request: pause listening review while headphones are unavailable and pivot to the rest of StaxRip.

## Preserved audio state

Slice 002 is paused, not complete or accepted. Keep the independently verified v2 local listening pack, blank owner ratings, full-master receipts and concealed comparison key. Resume from LISTENING-MANIFEST.md when headphones are available. Wider comparison settings do not close the stricter real-film failures or establish 3 LU performance. No DSP settings, defaults or tolerances changed for this pivot.

## First priority: existing native export reliability

The latest hosted run at 8fc901a failed one existing cancellation test on macOS 15.7.9: cancellationOfActiveSessionCleansItsStagingDirectory, iteration 5, ExportTests.swift:94. A .staxrip-export- directory remained after return. Run: https://github.com/LynxTWO/staxrip-macos/actions/runs/36480653924/job/109125167447

A fresh local `swift test --filter ExportTests` on 2026-09-29 passed all five tests, including eight active-cancellation cases and three native presets, in 0.586 seconds after build. This does not clear the hosted failure. Root cause is unknown. NativeExportService currently waits for the AVFoundation completion callback but silently ignores staging removal errors. Next investigation should capture the actual cleanup error and directory state, distinguish callback/writer timing from filesystem failure, and retain the no-publication invariant. Do not suppress the test or claim the race fixed from a local pass.

## Next capability: explicit video color information

Source inspection shows MediaProbe currently retains transfer and pixel format, but not primaries, matrix, range, frame timing or sample aspect ratio. MediaInspectorView only displays transfer when present. EncodePlan accepts yuv420p/nv12 and rejects PQ/HLG; this is an SDR restriction, not HDR support. A focused next brief should expose known and unknown color/timing information with understandable VoiceOver labels, then define an explicit output color verification contract.

Keep actual HDR preservation and SDR tone mapping as separate follow-on contracts. Synthetic metadata checks alone cannot establish correct HDR pictures. Dynamic HDR metadata, calibrated visual evaluation and supported hardware coverage require explicit boundaries before implementation. Existing Quick Export uses Apple presets and needs a separate assessment; advanced-pipeline restrictions must not be described as universal app guarantees.

## Following priorities

Filtered preview and frame stepping; rotation and timestamp/remux handling; per-track recipes and subtitle/chapter handling; session persistence, custom presets and undo; production qualification. RELEASE-SCOPE.md remains the acceptance ledger. This order is a working priority, not a claim of completed implementation or an expansion of the parked audio brief.

No merge, signing submission or public release was performed as part of this pivot.
