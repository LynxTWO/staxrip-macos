# Native complete Dolby metadata inspection
Version: 0.1. Date: 2026-10-03. D-095 / R-059 / Slice 049.
Status: generated, ordinary local regression, optimized build, native cancellation/full private inspection and owner restoration passed. Hosted checks pending at publication.

## Contract and information limits

The source inspector adds a Dolby Vision tab with an explicitly requested complete
read for the bounded Matroska HEVC subset. A fixed app-bundled helper uses pinned
MIT libdovi 3.3.2 for every RPU's syntax/CRC validation. Protocol 3 sends compact
summaries rather than complete source-derived dictionaries to the UI, while
retaining every packet, repeated RPU, association and digest. Mapping families,
MEL/FEL classification, declared scene refresh, content-mapping-version presence
and Level 5 offsets remain metadata facts. No new copy, conversion, picture edit,
HDR10+ authoring or archive-publication admission is introduced.

The native collector bounds each protocol line to 64 KiB, packet/RPU counts to two
million, and distinct active-area declarations to 256. It validates sequence,
association, geometry/container bounds, resource settlement and final counts/hash.
It needs both complete and exit zero; partial/cancelled/failed streams have no result.
An order-sensitive SHA-256 proof covers each packet's signed nanosecond PTS, encoded
byte count and complete payload digest. Independent streamed FFprobe must match
that proof and packet count, and the selected stream's hvcC size/hash must match
the helper. A final SourceFingerprint rehash must match the helper's whole-source
receipt. Integer nanosecond time conversion must be exact; missing reference timing
refuses rather than inventing or rounding it. The native proof does not cover
packet duration equality or decode a POC/frame association.

Container raster, container crop and display dimensions/units are shown separately
from Level 5 luma offsets. Display values can mean a ratio or physical units, not
output pixel dimensions. Odd active-area luma offsets are valid declarations;
chroma-aligned pixel cropping is a different requirement. The schematic uses the
container-declared raster proportions and is not a measured image. Crop/resize can
change coordinates and resulting-picture brightness statistics. Exact geometry,
rounding, frame mapping, new picture measurements and creative-trim treatment
remain required before edited dynamic-HDR admission. Original metadata must remain
separate from a future transformed version. No automatic offset clearing is treated
as proof of correct pixel cropping.

## Task, app and build ownership

An app-owned DolbyInspectionController owns one cancellable task. Replacements and
sheet reset wait for previous work; stale result/progress cannot repopulate the UI.
The source security-scoped lease remains held through the helper, independent
probe and final fingerprint, and ToolRunner joins child exit plus both pipe readers.
Cancel stays visibly stopping until settlement. AppDelegate's existing Quit guard
includes this activity, and the Dock reports inspection until it settles. Closing
or resetting a sheet does not abandon a helper process.

The helper builder verifies and copies all 69 supplied Cargo dependency license
texts from the 37-package inventory. It also includes the active Homebrew Rust
library attribution catalog, license texts, compiler version and notice hashes,
since the standard library is linked but is not in Cargo.lock. The notice inventory
must match every locked package; an actual changed notice and a missing package
in a generated inventory both refuse packaging. That catalog can
list more components than the runtime actually links. The nested helper is signed
before the enclosing app. Local optimized ad-hoc build/signature verification does
not establish Developer ID signing, notarization or production distribution.
The running app downloads nothing; Cargo/Python 3 are development dependencies,
and existing local FFprobe is required for the independent runtime check.

## Generated checks and retained findings

Rust locked tests contain 16 tests: the prior allocator/archive/Matroska cases plus
compact-protocol association/summary/canonical-hash checks. Four actual generated
ten-bit HEVC packets with B-frame presentation reordering and five varying/repeated
synthetic RPUs match independent FFprobe and both full/compact CLI modes. The
explicit generated test export uses exclusive create_new, never a source overwrite.
Corruption, truncation, resource/I/O/source-change failures remain refusing.
Formatting, warnings-denied Clippy and optimized helper build passed.

Native tests cover three chunk sizes, signed/reordered packet proof, repeated and
missing RPU counts, odd active areas, display-ratio units, missing/nonzero/trailing/
oversize output, wrong protocol/crop/ordinal/size/association/area/count/digest/source
receipt, timestamp multiplication overflow and reorder mismatch. Actual helper,
FFprobe and final hash complete on the generated fixture; failed reference probe,
source mutation just before final rehash and truncated Matroska cannot complete.
Held-reader tests prove replacement joins, latest-only start, cancellation settlement,
rejected late progress/success and sheet-reset Quit guarding until the worker joins.
The focused final ownership/Dock run passed nine tests in three suites in 0.977 s.

Retained development failures: the compact test initially expected zero offsets
although its existing fixture declares [1, 3, 5, 7]; expected values were corrected
without changing metadata or assertions. An initial Swift actor assertion combined
a waited property with an unawaited one; separate awaited assertions corrected the
compile error. A native walkthrough found unnamed disclosure controls in the
AppleScript accessibility interface; stable identifiers, explicit labels/help and
combined metric text were added. Applying a label to the whole disclosure then
overrode every child value in the native accessibility tree; moving the label/help
to its explicit heading restored individual content. The final generated native
check reads the actual raster, crop, display ratio and all four odd-offset areas,
plus the verification-scope paragraphs. Metrics expose expanded reference-picture
metadata wording and correct four-packet/five-record counts. Reviewing app
ownership then found Quit did not include the new sheet-owned operation; the
controller was moved to app ownership and an actual held-worker guard test added.
Git initially normalized one supplied CRLF license text, breaking its inventoried
byte hash. A scoped -text attribute now preserves all 69 committed notice byte
hashes; the full committed blob set was checked before publication.

The first ordinary local run passed 310 tests in 76 suites in 203.217 s. App lifecycle
changes after that justify the final ordinary regression, rather than treating the
earlier result as coverage of the new Quit/Dock behavior. No deadlines, assertions
or existing opt-in skip declarations were relaxed. Final ordinary regression passed
311 tests in 76 suites in 203.950 s; the final optimized development bundle rebuilt.

## Remaining acceptance

The final generated native walkthrough uses the bundled helper and reads four
packets/five validated RPUs/five declared refreshes, four odd-offset active-area
entries, container crop [0,0,1,0], raster 160×96 and display ratio 16×9. Both
stable-identifier disclosures open and preserve their individual text. The
expanded metric label is observable in the actual native accessibility interface.

An actual long private-source read disables Done. Cancellation settles the helper,
shows cancelled, enables Done and leaves no verified badge. A Quit request was
rejected with the native sheet open; the explicit app-owned Quit guard's retention
through a closing/reset sheet is separately proved by the held-worker test. The
native test does not claim an observed AppDelegate modal alert, since the system's
modal sheet can reject Quit before the delegate. Retry completes all 120,552 video
packets and RPUs, with 1,372 scene-refresh declarations and P7 MEL classification,
after independent packet/configuration checks and final source rehash. Geometry
and verification-scope disclosures remain individually readable on this source.

The original saved workspace/configuration/source/output/queue snapshot is restored
exactly, including the prior Failed status. Source descriptor and the current
recovery journal bytes are unchanged. No owner encode, source edit or publication
occurred. Native evidence and all source-derived content remain private.
Accessibility text/control inspection does not establish heard VoiceOver or pixel
review. Actual rendering, decoded-picture/POC mapping, FEL reconstruction, edited
geometry/brightness, other containers/AV1 framing, original companion publication
and conversion remain open. Subjective audio listening remains parked.

Hosted qualification is recorded by exact run and scope. Prior PR 69 Swift run
37167658006 passed 303 tests in 426.186 s and its preview/icon build; reader run
37167657999 passed. Those runs predate this native unit. The earlier PR 68 docs-head
AV1 deadline failure remains retained in HOSTED-QUALIFICATION-REFRAME.md. Neither
new implementation success nor native inspection diagnoses that historical timing
failure. No blind diagnostic rerun, merge or release is included.
