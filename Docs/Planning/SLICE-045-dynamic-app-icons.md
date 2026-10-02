# StaxRip Mac Slice 045: Native identity and live Dock status
Version: 0.1. Date: 2026-10-01. Status: Approved for build under D-083 / R-055.

SLICE STATE
Milestone: Layered source, native default/dark/mono previews and modern compilation are implemented after owner license approval. Product 6b549ae has final modern bundle and local/hosted regression receipts; visible Dock qualification remains open.
Blocked by: Visible Dock badge/menu and closed-window navigation cannot be inspected by the current native automation surface. Icon Composer license approval was given explicitly and accepted.
Evidence: DYNAMIC-ICON-EVIDENCE.md records original fallback artwork, corrected native Light/Dark sidebar and Finder icon, real export, ten focused checks and 285-test local/hosted regression. Native layered compilation and Composer variants now pass; visual Dock checks remain open.
Last audit: 2026-10-01.

## 1. What the slice proves

StaxRip has a recognizable original app icon in Finder, Dock and its workspace, with native appearance support and truthful Dock work/attention status. This directly implements the owner's dynamic-icon request after Slice 044 acceptance.

## 2. The walkthrough

Open the built app from Finder. Its clapperboard/frame identity appears in the Dock and workspace. Supported modern macOS appearances render native layered variants; older supported systems receive a complete multi-resolution fallback. During actual work, a short native badge reports measured progress only when meaningful, otherwise indeterminate work. An attention badge denotes a current failure or cleanup warning. The Dock menu explains the activity and returns to the appropriate app view. Success/cancellation/cleared work returns to idle without implying a pending job has run. Multiple independent operations do not invent aggregate progress.

## 3. In scope, with build order

M1: Author original editable vector artwork inspired by the official clapperboard, with no copied upstream bitmap. Establish Icon Composer source, default/dark/mono previews and real asset compilation on the installed modern toolchain. Establish a deterministic ICNS fallback from the same source for macOS 14 and older build toolchains. Inspect large and small renders before product integration. If the modern pipeline cannot be qualified, record that limit before choosing a narrower implementation.

M2: Independent status work and the verified fallback may proceed while modern-tool license consent is pending; full artwork acceptance still requires M1. Package icon resources through the shared build.command/package.command helper without committing binaries. Add a shared brand treatment in the sidebar. Derive a small immutable Dock presentation from existing observable controller state, retaining system-rendered artwork and badges. Add native Dock navigation/status menu. Keep all operation/publication/cancellation owners unchanged; read audio activity only without DSP changes.

M3: Focused state-transition checks for known/unknown progress, preparation/finishing, failure/cleanup, success/reset and multiple owners; actual optimized native export/settlement and menu navigation; asset/bundle verification; full ordinary local/hosted regression and selected planning audit. Use existing generated fixtures and preserve owner recovery state.

## 4. Out of scope

Rebranding the product name, copying Windows code/artwork, choosing the project's software license, audio algorithms/listening, alternate icon packs, notification services, animation timers, progress estimates, new persisted session fields, encoding behavior, merge and release.

## 5. Stubs and debts

No fake progress. Native modern appearance remains dependent on the OS and compiler; older fallback is explicitly static artwork with live system badges. Broad platform/accessibility qualification stays open.

## 6. Modules touched

Resources and build scripts; a brand view; process-local Dock presentation/coordinator; StaxRipMacApp/AppDelegate integration with existing published state; focused tests and documentation. Existing processing controllers remain authoritative.

## 7. Data subset

Read-only activity booleans, typed outcomes, phase/progress and current queue IDs. No media paths in the Dock, no new file reads or processing, no saved credentials or recovery changes. Native menu actions only navigate or show existing windows.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S45-001 | Original icon has coherent native variants and complete fallback | Editable provenance, real compiler output, default/dark/mono preview and small-size inspection | icon-artwork |
| S45-002 | Built bundle contains and advertises the intended icon | Modern and fallback build paths, Finder/Dock native inspection | icon-bundle |
| S45-003 | Live status is truthful and navigation is safe | State-transition checks, actual native operation and settled badge/menu observation | icon-status |
| S45-004 | Existing app remains qualified | Optimized build, ordinary local/hosted regression, protected owner files and selected audit | icon-regression |

## 9. Verification evidence required

R-055 authorizes one bounded native icon/render feasibility exercise using Apple's installed tools, generated artwork and existing export fixtures. Consequence class: local_only visual/status presentation; export safety remains under existing contracts. State tests target misleading status outcomes rather than pixel snapshots or private OS internals. No new observer service or scheduling/deadline changes. Record results and limits in DYNAMIC-ICON-EVIDENCE.md.

## 10. Guardrails

Preserve system icon appearances by using native badges rather than replacing the icon with a flattened screenshot. Unknown/finishing work cannot show complete. Stale queue history cannot label unrelated work. Avoid color-only state and intrusive bouncing. No permanent Dock or security preference changes. Preserve failed evidence; historical hosted mastering cancellation recurrence reopens qualification without blind retries or diagnostic expansion.

## 11. Definition of done

All four scoped gates recorded, with exact product identity and platform limits. The new identity is installed by the ordinary app build, not a manual Finder override.

## 12. What this unlocks

A recognizable native identity and useful progress at a glance while the encoder is in the background. Remaining media, accessibility and release gates stay separate.

Approved for build by: Owner explicit dynamic-icon request and standing autonomous non-audio completion delegation, 2026-10-01; D-083 / R-055. Delegated to AI recommendation.
