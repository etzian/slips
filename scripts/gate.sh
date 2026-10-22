#!/usr/bin/env bash
# The one gate. Fails on the first error. Redirect the output to a file and read the tail.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${SLIPS_SIM_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=26.5}"

echo "== 1/5 swift test (SlipsCore)"
swift test --package-path SlipsCore

echo "== 2/5 xcodebuild build test"
xcodebuild -project Slips.xcodeproj -scheme Slips -destination "$SIM" -quiet build test

echo "== 3/5 strings"
scripts/check-strings.sh

echo "== 4/5 hygiene"
scripts/check-hygiene.sh

echo "== 5/5 licences"
scripts/check-licences.sh

echo "GATE OK"
