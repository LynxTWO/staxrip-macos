#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
FIXTURE_TARGET="$PROJECT_DIR/Tools/DolbyMetadataAudit/target/native-development-fixtures"
MANIFEST="$PROJECT_DIR/Tools/DolbyMetadataAudit/Cargo.toml"
# Before Swift tests: exact fixed DEVELOPMENT profiles used by RustFixtureBuild.
# App/read-only default artifacts remain separate. Cargo protects compilation;
# the test coordinator additionally holds fixture-build.lock through generation/copy.
/usr/bin/swift "$PROJECT_DIR/scripts/prepare-native-test-fixtures.swift" "$FIXTURE_TARGET" "$MANIFEST"
