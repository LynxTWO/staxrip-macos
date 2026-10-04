# Fixed Rust helper signature prerequisite
Date: 2026-10-04. Scope: D-117 / R-059 / Slice 049.

## Policy and actual need

D116's access ownership does not authenticate the writer or metadata reader. Existing
Tool constructors qualify explicit DEBUG hashes only. HelperSignatureAdmission is an
unused native Security prerequisite for two fixed role identifiers and basenames under
Contents/Helpers. No release Tool factory, arbitrary requirement deserialization, signing
API, writer packaging or archive action is added.

Apple documents static signature validation against an additional requirement and warns
that the result remains valid only while code is unchanged. This implementation uses
strict validation/all-architecture checks but deliberately admits only a thin executable
for the current native CPU; it makes no universal-slice signer or Rosetta claim.
[Apple static validation](https://developer.apple.com/documentation/security/secstaticcodecheckvalidity(_:_:_:))
and [Apple requirements guidance](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

DeveloperID policy requires Apple generic anchor, DeveloperID intermediate/leaf markers,
exact fixed-role identifier and a caller's explicit trusted ten-character Team ID. It
also checks signing-info Team equality, refuses ad-hoc, requires runtime hardening and
requires absence of any entitlement blob/dictionary. Trusted Team must come from release
configuration, never a candidate, archive or media. No successful DeveloperID artifact
was admitted in this unit; negative checks do not establish a deployable release policy.

DEBUG development policy instead requires the creator's captured code-directory hash,
exact identifier and ad-hoc/no-Team signing. These policies cannot fall back to one
another. A valid ad-hoc helper is refused by DeveloperID policy. Actual native parsing
of both requirement forms succeeded; ad-hoc validity0 and DeveloperID refusal-67050 were
observed in a private discriminator. The first development form incorrectly quoted a
plain hash; parsing failed-67052. Correct H-prefixed hash syntax restored the positive
check. Initial failure logs remain retained; no refusal assertion was weakened.

## Pinned layout and static limitation

Bundle/Contents/Helpers descriptors are opened relative to their pinned parents without
following links. Candidate is regular, singly linked, executable, not group/world
writable, owned by root/current user and32bytes...256MiB. The directory path/descriptor
identities/modes/owners agree before/after; file size/link/mtime/ctime observations and
full SHA256 agree across static validation. Native thin64bit Mach-O CPU type is required.
A1MiB hashing buffer and cooperative checkpoints bound each read, not native Security
heap, filesystem latency or a preemptive deadline. Work belongs on an owning worker.

A returned receipt describes static observations, not a live executable capability,
notarization, immutable snapshot, hostile same-user protection or outer app seal. Signature
checks cannot eliminate all path/time races; existing owned process pins/hash/checks remain
necessary at launch/settlement. Revocation/network/older-platform execution is unqualified.
No disabled library validation or broadened runtime entitlement was used for execution.
An inert signed fixture with user-selected-read-only entitlement was inspected/refused,
never executed. No anonymous candidate-derived production trust is inferred.

## Actual hardened execution and refusal cases

Actual source-built Rust reader/writer copies are ad-hoc signed with runtime hardening,
constant role identifiers, no entitlements and no timestamp. The captured known generated
hash policy admits each. Their admitted full SHA256s drive existing DEBUG Tool capabilities
for actual owned native writer, complete source-dependent native metadata verification
and D105/D099 exclusive publication in both retention modes. Whole-container bytes match
the generated original and source stays unchanged. This proves current-runtime ad-hoc
hardened Rust execution; it does not qualify relocated FFmpeg library loading, DeveloperID,
notarization, real release capability, packaging or production archive action.

The independent signature fixture uses the lower-level transaction rather than contending
for the app's single-operation admission slot. A preceding combined fixture correctly
refused the competing app operation; its log is retained and the test isolation was
corrected. No application guard, default global test concurrency, historical timing
observer or deadline changed. Scope/activity ownership remains separately qualified by
D116 and its existing generated tests.

Wrong role/identifier/hash, valid ad-hoc under DeveloperID policy, missing runtime,
unsigned candidate, any entitlement blob, writable or multiply linked file, symlink,
FIFO, wrong native CPU and substituted Helpers path refuse. Actual post-signature
member mutation and pre-check cancellation refuse before a successful static receipt.
Five signature tests and eight unchanged access tests comprise the final focused run.

## New bounded DeveloperID discriminator

D097's FFmpeg signing attempt remains interrupted/incomplete, including its unknown wait
cause and separate ad-hoc library-validation failure. It was not retried. This unit made
a genuinely new check on one freshly owned standalone Rust reader, without relocated
libraries. One valid configured local DeveloperID identity was observed. Codesign used
its public certificate selector, runtime option, fixed role identifier and secure timestamp;
no private key/password was exported or placed in arguments/logs/Git. Identity/name output
and signing log remain private; no notarization upload occurred.

That exact owned codesign process/group did not settle within20seconds. It was stopped
and its direct child joined; incomplete copied output remains retained with a receipt.
The original Rust binary, previous candidate and app were not signed by this attempt.
Its remaining code signature was the compiler's ad-hoc one without runtime flag or Team,
not DeveloperID success. Cause remains unknown; no Keychain/password/network diagnosis or
owner-action claim follows from waiting alone. Do not blindly retry this or D097. A changed
condition or new discriminating scope is required. Other generated prerequisites remain
useful, so whole-program blocking is not claimed.

## Build evidence correction and final checks

D116's log named release actually says Building for debugging: Swift app debug, Rust helper
release. Its initial optimized-app claim was wrong. Docs/PR91 are corrected, original
receipt preserved with a separate correction record. D115 log says Building for production
and remains valid. D117 explicitly sets STAXRIP_CONFIGURATION=release; final log says
Building for production, compiled the new product code and emitted no warnings. Strict
ad-hoc optimized app/read-only helper signatures pass; minima14.0/11.0; writer absent.
This restores optimized development evidence, not DeveloperID/notarization claims.

Ordinary438reported tests/91suites207.134s passed with26 unchanged opt-in skips; signature
suite5.990s. A new test-only unnecessary try warning was subsequently removed; final
focused13tests/2suites2.507s passed without new warnings (signature suite0.987s, actual
both-mode signed helper pipeline0.343s). No product behavior changed after ordinary
qualification; final focus covers the corrected test marker. First Data-to-digest compile
mistake, hash requirement parsing failure and single-operation fixture refusal are retained.
Unchanged Rust41/format/Clippy, companion30/frame15 and APFS D115 receipts are reused,
not newly executed. No owner media-body read, queue, film archive/encode or listening.

PR91 automatic app37211675808 failed21 unchanged120-second cases,433reported tests494.174s,
new access suite135.829s passed, preview skipped. No reader run triggered by that Swift-only
change. Failed log retained/PR updated; D090 runtime causes unknown, no rerun or causal claim.

Remaining gates: actual DeveloperID helper admission/loading, outer bundle sealing,
trusted release configuration/provenance/packaging/distribution, retained review recovery,
owner losses/storage/privacy review, actual sandbox grants/revocation, source-dependent
prototype import/persisted binding, crash/volume-loss/blocked-I/O and decoded/edit picture
association. The separate LGPL decoder remains unbundled. No archive UI, merge or release.


Final seven-file public/nonignored scan: zero private source path/name/stem matches,
positive decoded source-field sentinel; original source metadata/current recovery journal
unchanged, full planning findings empty. No owner source body/queue/film archive/encode/
listening, merge or release. Prior awake32011 exact command/start and receipt revalidated;
replaced only that owned assertion with bounded55829 -diu -t7200, expiry17:46:06UTC,
for continuing authorized scheduled development. No persistent security/locking change
or manual-lock override. Incomplete D097/D117 signing artifacts and detached D115 failed
image stay retained. No blanket signing/production/archive acceptance follows.
