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
