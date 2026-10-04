# Owned original-companion stage evidence

Date: 2026-10-04. R-059 / Slice 049 / D-103. This is generated development-library
qualification; the native CLI remains read-only and no archive feature is enabled.

## Contract and implementation

The future owner chooses metadata-only or complete original retention and reviews
storage and privacy. The caller must own a precreated empty private 0700 stage.
The synchronous writer pins its immediate parent and stage with no-follow directory
opens; it refuses nonowned, nonprivate, nonempty, missing or unsafe stage paths.
It exclusively creates only fixed regular single-link 0600 component names using
openat with O_CREAT/O_EXCL/O_NOFOLLOW/O_CLOEXEC. The process umask is not changed;
a permission mismatch refuses. No arbitrary output path comes from a manifest.

Created device/inode/mode/owner identities and empty path membership must still agree
before concrete File handles pass to D-102's source-bound producer. After that producer
settles, the writer exclusively creates the unchanged prototype manifest. It rereads
all actual components against producer byte/hash receipts, retains all reopened read
handles through final checks, and requires unchanged membership, directory snapshots,
component descriptor/path snapshots, original created identities and source identity.
Hashing uses a one MiB heap buffer, not an in-memory whole-source or component array.
Existing byte/packet/RPU bounds remain unchanged; manifest bytes are limited to one MiB.
Directory enumeration refuses more than eight entries and propagates readdir failure.

Success returns a StagedReceipt with source-bound and disk component receipts. This
is not a successful published result, semantic verification or a stable importer.
The manifest stays version zero with source_path_identity_bound false. Producer
execution information is in memory only; component presence or a written manifest
cannot substitute for the returned receipt. D-101 independently compares original
track/configuration, packet/index/raw-RPU relationships and optional full-container
bytes against the actual source. That comparison still remains required at integration.

Cancellation is one-way and cooperative at creation, producer I/O, manifest and reread/
final receipt boundaries. Concrete files close at synchronous return or unwinding;
there are no retained writers/tasks or native child processes. Partial or complete-looking
files remain in the caller's stage on refusal. The caller must join its worker before
cleanup. This function never deletes a stage, recursively cleans a directory, publishes
a result or overwrites preexisting entries. Physical I/O and parser CPU are not preempted.

## Generated checks and limits

Seven generated Rust functions exercise real files, fixed-name exclusive creation and
controlled private callback boundaries (no callbacks are exposed by the public entry):

- Both modes: exact disk hashes/sizes/0600/single-link membership, unchanged source,
  original supplemental track payload, negative encoded PTS and duplicate RPUs.
  Metadata-only has six members; full mode has seven including exact source bytes.
- Initial stage refusals: nonempty regular entries, links, subdirectories, FIFO,
  too many entries, unsafe permission/sticky modes, missing/file/symlink stage and
  symlink immediate parent. Prior source/entry bytes are preserved.
- Creation faults: subsequent fixed-name collision, identical-byte path substitution,
  hardlink, permission change, stage replacement and cancellation. No source writes
  reach a substituted/moved component; existing collision bytes remain intact.
- Settled faults: missing/extra/corrupt components, identical-byte inode replacement,
  hardlink/symlink/FIFO/permission changes, changed/replaced stage and replaced/mutated
  source refuse even when a prototype manifest has already been written.
- Immediate parent replacement and replacement of an already-read component refuse.
  Final checks cover read handles and current paths rather than only an earlier hash.
- Pre-cancel writes nothing. Cancel after writes or during actual reread returns no
  staged receipt. A controlled worker is cancelled and joined before caller cleanup.

The independent Python verifier accepts both newly staged generated packages and checks
that package/source bytes stay unchanged, while retaining the manifest's unbound flag.
The fixture is an original wire container with one packet/two RPUs; opaque enhancement
NAL bytes do not establish decodable enhancement residuals or picture reconstruction.
Existing actual HEVC decoder-reference tests remain separate. No owner source scan,
private full-film archive or encode was performed. Initial build-only errors (Darwin C
variadic mode promotion and one moved test PathBuf) were corrected before passing checks.
A mistaken development test module invocation failed before execution and was corrected
without changing the reference tests or assertions.

Trust boundary: supplied stage creation history and its caller are trusted. Immediate
parent/stage observations do not establish a path-ancestry sandbox, immutable snapshot,
same-user adversarial race protection or cryptographic authenticity. Returned receipts
observe the checked boundaries; later changes require another admission check. No fsync,
crash/power-loss durability, archive-specific ENOSPC/volume handling, native lifecycle or
signed-distribution claim follows. The Rust module is conditional on macOS/Linux; only
macOS was exercised here. No dependency, native executable command/protocol, app UI or
session schema changed. No UI walkthrough/VoiceOver claim is appropriate for unused code.

Metadata-only omits original BL/EL pictures and outside-track container information.
Complete mode retains the entire source-sized original container including other streams,
embedded metadata and names. Native review must disclose those different losses/storage/
privacy consequences. Original preservation stays separate from compatible Dolby
conversion, edited-picture statistics, enhancement reconstruction and companion import.

## Qualification and remaining work

Rust 38 tests (15 library, 1 main heap, 15 container, 7 archive) passed with zero
failures/ignored tests; format and warnings-as-errors Clippy passed. Independent
companion suite passed 19 checks in 3.613 s without resource warnings; existing decoder
reference suite passed 15 checks in 1.145 s. Ordinary app regression passed 331 tests/
78 suites in 202.252 s with default scheduling/assertions and existing opt-in skips.
Optimized build and strict ad-hoc app/helper signature checks passed. Actual Mach-O
minimum declarations remain 14.0/11.0, not older-OS runtime or hardened/notarized proof.
Original source descriptor and current recovery journal bytes are unchanged. Scoped
privacy scan of fifteen changed/nonignored-untracked files for three exact owner
path/name/stem identifiers has zero matches and a positive private sentinel. Ignored
binaries/private receipts/owner media are excluded; this is scoped absence, not general
privacy certification. Planning audit has no findings. These are generated checks,
not native archive readiness. Next: a bounded trusted native writer process bridge,
worker cancellation/join, semantic settlement and D-099 exclusive publication. Stable
archive/import, producer execution binding in a persisted format, decoded association,
storage/crash and distribution remain separate gates. D-097 complete-source 120,552
association evidence is retained without repetition; decoder remains unbundled.

PR 77 automatic app/reader both passed without retry. All 331 app tests completed in
526.291 s with preview/icon packaging; reader completed in 1m34s. Prior hosted failure
causes remain unknown. D-090 timing investigation remains completed; no blind rerun,
new historical observer, changed deadline/assertion or claim of causal repair.
