# Original companion development verification

Read-only verifier for the version-zero components from the development Rust producer.
This is not a stable archive importer, native app feature or decoded-picture check.
It opens only the explicitly supplied source and package; it never creates an archive,
rewrites a manifest, publishes a result or enables Dolby conversion.

Run the generated actual-package and adversarial checks:

```sh
python3 Tools/DolbyCompanionCheck/test_check.py -v
```

The tests compile the locked Rust reader and export operation-owned synthetic
fixtures through an opt-in Rust test environment variable. No downloaded test media,
owner session or queue is used. The existing reader CI includes these checks.

For a separately created development fixture, supply a trusted local reader explicitly:

```sh
python3 Tools/DolbyCompanionCheck/check.py \
  --source "$GENERATED_SOURCE" --package "$GENERATED_PACKAGE" \
  --audit-helper Tools/DolbyMetadataAudit/target/release/staxrip-dolby-metadata-audit
```

The helper is operator-supplied development tooling. A package cannot select a helper;
this tool does not establish its signature or qualify native execution. Native work
must use the app's fixed trusted helper and establish its own process/resource policy.

Exact expected package membership, regular single-link component files, actual hashes,
original selected TrackEntry/hvcC, fresh source packet audit and every RPU/index/source
byte relationship must agree. Duplicate RPUs and signed, repeated, nonmonotonic PTS
remain in encoded order. This checker intentionally does not apply the decoder
reference's unique-timestamp or one-RPU-per-frame admission rules to original archives.

Package entries use descriptor-relative, no-follow opens. The final source content,
descriptor/path identity, package directory and each component are checked again.
These are before/after observations, not an immutable snapshot or a guarantee against
same-user adversarial mutation. Intermediate path ancestors are not a security sandbox.
The original manifest's unbound producer-path flag is retained; separate JSON output
describes the narrower validator result. Refusals have generic path-free CLI diagnostics.

Metadata-only retains original selected track metadata/RPUs/encoded association and
excludes BL/EL pictures and outside-track data. Complete mode retains the entire original
container byte-for-byte, with source-sized storage and embedded metadata/name consequences.
Neither mode establishes EL reconstruction, decoded-frame correspondence, physical
picture-edit statistics, future importer/carriage or playback support.

The source/full-container bound is 1 TiB, track/configuration 1 MiB, RPU/index 512 MiB,
audit 1 GiB, JSON row 64 KiB, packet/RPU count 2 million, manifest 1 MiB. Hashing reads
1 MiB chunks and rows stream without an in-memory index. The independent EBML walker
bounds child counts and selected track payload. The trusted helper has its existing
64 MiB Rust heap policy; a separate 120-second generated-development helper deadline
kills the owned group and joins the direct child on refusal, timeout or interruption.
This is not a full-file validation wall-clock, whole-process memory or physical I/O
deadline guarantee. No historical timing test assertion/deadline is changed.


Generated checks also export both retention modes from the source-bound core and from
the fixed-name stage writer, then independently validate their original semantics.
The writer's in-memory receipt and disk hash check do not replace this comparison.
The version-zero manifest remains unchanged, including its false producer-path flag;
no persisted provenance or stable import format is inferred from these tests.


## Unbundled writer process qualification

`test_writer.py` builds the separate feature-gated Rust executable and checks both
retention modes through `writer.py`'s explicit trusted development process caller.
It independently validates generated packages with this read-only semantic checker.

```sh
python3 Tools/DolbyCompanionCheck/test_writer.py -v
```

The caller pins a supplied source and empty owned0700 stage, passes their captured
file IDs, correlates a bounded ready/start/staged protocol, requires exit zero and
rereads exact disk members/source identity. Cancellation/deadline terminates its
owned group and joins/closes its direct child/pipes; per-chunk disk verification also
checks cancellation. The caller never cleans up or publishes a directory. Its stage
receipt remains separate from independent semantic admission and D-099 publication.
The unchanged prototype manifest is not persisted producer-execution binding.

The executable must be supplied explicitly and trusted by the operator, not selected
by an archive. This is not native signature/tool provenance, lease or resource policy.
Generated lifecycle checks include real ready-wait cancellation, interruption, deadline,
late-result cancellation, malformed/stale/nonzero/trailing receipts and a pipe-holding
child. Active physical-copy interruption and archive-specific storage/crash behavior
remain unqualified. Process deadline covers the owned process, not subsequent physical
rereads or semantic verification; no physical I/O preemption guarantee is claimed.


## Generated native transaction integration

The Swift OriginalCompanionTransactionTests call native_transaction_fixture.py only
as an explicit test adapter. It invokes the actual development writer or independent
checker and returns bounded observations to the internal Swift stage coordinator.
The checker now returns actual source/stage file IDs, source size/digest/counts and disk
member hashes including the manifest, without changing that manifest. This transient
receipt is not stable import or persisted producer provenance. The native app neither
packages nor calls this adapter, Python validator or optional writer.

With the standard locked release reader built (as in the app workflow), run the
generated native sequencing and end-to-end checks with:

```sh
cargo build --locked --release --manifest-path Tools/DolbyMetadataAudit/Cargo.toml
swift test --filter OriginalCompanionTransactionTests
```

The real both-mode fixture preserves duplicate raw RPU/signed encoded associations;
separate opaque-component phase tests qualify sequencing and cleanup only. Source
observations are not immutable snapshots. Trusted settled callbacks and a read-only
precommit source guard are necessary; callbacks cannot prove their own authenticity.
