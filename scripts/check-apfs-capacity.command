#!/bin/zsh
# Opt-in: fills only a newly created 64 MiB APFS disk image with generated data.
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/staxrip-apfs-capacity.XXXXXX")"
FIXTURE_MOUNT="$FIXTURE_DIR/mount"
FIXTURE_TOKEN="$(uuidgen)"
FIXTURE_ATTACHED=0
cleanup() {
    local result=$?
    trap - EXIT
    if (( FIXTURE_ATTACHED )); then
        if ! hdiutil detach "$FIXTURE_MOUNT"; then
            print -u2 "Fixture could not detach; retained at $FIXTURE_DIR. No cleanup attempted."
            exit 1
        fi
    fi
    rm -rf -- "$FIXTURE_DIR"
    exit "$result"
}
trap cleanup EXIT
mkdir "$FIXTURE_MOUNT"
hdiutil create -size 64m -fs APFS -volname StaxRipAPFSCapacityFixture -type UDIF "$FIXTURE_DIR/fixture.dmg"
FIXTURE_ATTACHED=1
hdiutil attach "$FIXTURE_DIR/fixture.dmg" -mountpoint "$FIXTURE_MOUNT" -nobrowse -owners off
print -r -- "StaxRip disposable APFS fixture v1 $FIXTURE_TOKEN" > "$FIXTURE_MOUNT/.staxrip-apfs-fixture"
STAXRIP_APFS_TEST_MOUNT="$FIXTURE_MOUNT" STAXRIP_APFS_TEST_TOKEN="$FIXTURE_TOKEN" swift test -c release --package-path "$PROJECT_DIR" --filter APFSCapacityTests
