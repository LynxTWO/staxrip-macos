#!/bin/zsh
set -euo pipefail
if [[ -z "${STAXRIP_EBU_TEST_SET:-}" || ! -d "$STAXRIP_EBU_TEST_SET" ]]; then
  print -u2 'UNMET: set STAXRIP_EBU_TEST_SET to the locally obtained EBU v5 fixture directory. No conformance test has passed.'
  exit 2
fi
cd "${0:A:h:h}"
swift test -c release --filter AnalysisConformanceTests
