# Owned source import cancellation evidence

Date: 2026-09-30. Slice 020, D-033 / R-023. Status: focused and full local regression passed; native/hosted gates pending.

## Behavior and ownership

SourceLoader owns asynchronous native property loading with AVAsset.cancelLoading, checks task cancellation between native requests and before FFprobe fallback, and propagates cancellation without a fallback or error alert. The fallback uses the existing ToolRunner process/pipe lifecycle. Source metadata display uses failable integer conversions and explicit unknown fields for unavailable or unrepresentable dimensions, frame rate and duration.

WorkspaceModel retains one current source task and one latest pending replacement. A replacement cancels current work but waits for its actual result before starting the latest request. Cancel source loading clears pending intent, reports waiting, and retains the existing source, settings, output name and settings history. A late success or failure cannot update the workspace. Return to demo also cancels owned work while changing the displayed source. Saved-session restoration retains its source-specific settings and output name. No saved formats change.

The source row exposes a named Cancel source loading button and accessible loading status. The footer distinguishes reading from waiting for cancellation. It does not report cancellation complete while an owned worker is still active.

## Focused checks and negative control

An initial 16-function focused run (ten new functions plus six existing file-dialog functions) passed in 0.179 seconds. Cases cover:

- Held AVAssetResourceLoader request, actual native cancellation and no fallback invocation; already-cancelled reads do not start work.
- Controlled fallback process cancellation, awaited process exit and no remaining PID.
- Generated H.264 MP4 native import and FFV1 MKV fallback with unchanged source bytes; unreadable sources and non-file URLs refuse.
- Nonfinite and unrepresentable display metadata, normal dimension/rate formatting and long-duration display without trapping integer conversion.
- One active worker and latest-only replacement; late success/failure rejection; cancellation before task start; saved-session restoration following demo/reset while old work settles; current failure followed by explicit retry.

Negative control: temporarily omitting SourceLoader's asset.cancelLoading made the held-native test fail after 31.989 seconds. Its independent watchdog recorded a failure and called native cancellation to release the test fixture; Task.cancel alone had not settled it. The product cancellation call was restored before full regression/build. This is a native framework request test, not a guarantee for arbitrary filesystems.

The final model test also cancels a pending replacement while the old worker is held, requiring that replacement never start. The final release regression passed 183 tests in 36 suites in 36.620 seconds; the ad-hoc app built in 13.68 seconds. Native and hosted receipts remain pending. Local logs and generated fixtures are ignored work/import-cancellation; no user media is used.

## Limits

No timeout abandons native work or a fallback process. Unusual filesystem/framework delays may still require waiting for cancellation to settle; the UI remains available and state remains owned. Persistent bookmarks and permission recovery remain separate. Native preview capability is still bounded by AVFoundation and may differ by platform. Keyboard/spoken VoiceOver and broader platform acceptance remain separate from automated accessibility inspection. Audio, encoding behavior, signing, merge and distribution are outside this slice.
