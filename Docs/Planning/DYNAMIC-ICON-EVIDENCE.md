# Dynamic native icon evidence
Date: 2026-10-01. Scope: Slice 045 / D-083 / R-055. Partial; modern layered artwork remains blocked.

## Baseline and artwork

Plan 25dc9e1 precedes implementation. Accepted baseline 446107b has no bundle icon. The original geometry in scripts/IconArtwork.swift produces a teal clapperboard above stacked frames, with a continuous S ribbon. Upstream StaxRip's clapperboard was a visual reference only; no bitmap/vector was copied. Resources/IconArtwork/README.md records the inspected upstream revision and license distinction.

Actual AppKit/CoreGraphics renders were inspected at 512, 256, 32 and 16 pixels. Light, dark and grayscale preview palettes are generated from the same geometry, along with full-canvas editable SVG layers. The fallback ICNS round-tripped through Apple's iconutil with all ten standard 16-through-1024-pixel representations. Binaries stay in private build output. Both development build and local archive use one resource helper. This adds no downloaded dependency.

## Native findings

The first sidebar experiment read NSImage.applicationIconName and displayed the old generic placeholder in the running app, despite a valid bundle resource. It was replaced with explicit bundled artwork lookup. The corrected optimized native app displayed the new identity in both Light and Dark app appearances; the original Light preference was restored. Finder Get Info displayed the actual bundle icon and large preview. No Finder icon override or cache clearing was used. The temporary Finder windows were closed without changing the owner's existing window.

A generated silent 90-second 1920-by-1080 60-fps video completed actual H.264 Quick Export while the new system was loaded. Independent ffprobe counted all 5,400 frames at exactly 90.000 seconds, no audio, output 176039401 bytes. Whole-source/prior-output hashes and the owner's recovery journal remained unchanged, and owned staging was absent. The app quit normally. Private receipts: work/dynamic-icons/native/before.json and verified.json. This is a native export coexistence check, not visual confirmation of the Dock badge.

The native automation surface timed out twice when binding com.apple.dock; its app inventory does not expose Dock. No system settings, accessibility bypass or injected events were used. Visual Dock badge/menu and heard VoiceOver qualification remain open. The real AppKit API integration is separately tested below.

## Status contract and focused checks

DockPresentation uses only current queue IDs, known phases and published controller state. Known encoding progress is rounded down and cannot claim 100 percent before settlement. Preparation, verification, finishing, Audio Lab and multiple concurrent operations remain indeterminate. Pending/completed/cancelled jobs alone do not imply work or failure. Current failures, preflight issues and cleanup warnings remain in menu text; attention survives settlement. No paths, error details, fake totals or animation timer are introduced. The system keeps ownership of the icon itself.

Ten tests in three suites passed in 0.047 seconds: new state policies, actual NSDockTile/NSMenu integration and existing queue presentation. The API integration starts with a stale badge and verifies initialization clears it; published changes reach the real badge without calling the menu; progress becomes indeterminate at writer completion, failures become attention, clearing restores idle. The native menu action dispatches navigation only, and private failure text is absent. This is an API result in the test process, not a screenshot of the user's Dock. Private log: work/dynamic-icons/focused-integrated.log. The existing asynchronous Thread.isMainThread compiler warning remains.

Window navigation obtains OpenWindowAction from the main window's view environment, following Apple's documented context: https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow . This avoids relying on a default App-level environment action. Closed-window Dock navigation still needs a visible native walkthrough.

## Explicit hold

Apple Icon Composer presented a first-run legal agreement EA1954, dated April 16, 2025. Owner confirmation was requested through the pending approval question; it has not been accepted. No Icon Composer project, native material/appearance compilation or automatic default/dark/mono OS behavior is claimed. Generated dark/mono previews are not proof of that behavior. The static ICNS and app-specific sidebar appearances are working independently.

Full local regression passed 285 tests across 70 suites in 209.695 seconds, with 25 existing opt-in/tool-dependent skips. The optimized Swift build completed in 19.10 seconds; subsequent archive assembly reused that compiled product, regenerated all icon resources and passed strict ad-hoc signature verification. The private archive remains local and is not a release. Hosted regression is pending. All four slice gates remain unaccepted until the modern pipeline and outstanding native checks are resolved. The historical hosted mastering cancellation recurrence reopens qualification without blind retries or diagnostic expansion. Audio algorithms/listening, merge and release remain outside scope.
