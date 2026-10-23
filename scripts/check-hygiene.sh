#!/usr/bin/env bash
# Repo hygiene checks (see .claude/plan/PHASES.md, gate step 4).
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
report() { echo "hygiene: $1"; fail=1; }

SRC_DIRS=()
for d in Slips SlipsCore/Sources SlipsTests SlipsUITests SlipsCore/Tests; do [ -d "$d" ] && SRC_DIRS+=("$d"); done

# 1. no print( in app or core sources
hits=$(grep -rnE '(^|[^A-Za-z_.])print\(' --include=*.swift Slips SlipsCore/Sources 2>/dev/null | grep -v '^Slips/DesignSystem/')
[ -n "$hits" ] && report "print( found:
$hits"

# 2. SlipsCore stays pure
hits=$(grep -rnE '^\s*(@_exported\s+)?import\s+(UIKit|SwiftUI|VisionKit)\b' --include=*.swift SlipsCore/Sources 2>/dev/null)
[ -n "$hits" ] && report "UI import in SlipsCore:
$hits"

# 3. no image or PDF fixtures
if [ -d SlipsCore/Tests/Fixtures ]; then
  hits=$(find SlipsCore/Tests/Fixtures -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.heic' -o -iname '*.pdf' -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.gif' \))
  [ -n "$hits" ] && report "image or PDF under fixtures:
$hits"
fi

# 4. no 13-19 digit run (card numbers), separators allowed
hits=$(grep -rnE '(^|[^0-9])([0-9][ -]?){13,19}([^0-9]|$)' --include=*.swift --include=*.txt --include=*.json --include=*.md \
  Slips SlipsCore/Sources SlipsCore/Tests 2>/dev/null | grep -v '^Slips/DesignSystem/' | grep -v 'Package.resolved' | grep -v 'Slips/Assets.xcassets')
[ -n "$hits" ] && report "13-19 digit run:
$hits"

# 5. no colour literal outside the design system
hits=$(grep -rnE 'Color\(red:|#colorLiteral|#[0-9A-Fa-f]{6}\b|0x[0-9A-Fa-f]{6}\b' --include=*.swift Slips 2>/dev/null | grep -v '^Slips/DesignSystem/')
[ -n "$hits" ] && report "colour literal outside Slips/DesignSystem:
$hits"

# 6. no build products tracked or pending
hits=$(git status --porcelain 2>/dev/null | grep -E '(DerivedData/|xcuserdata/|\.build/)')
[ -n "$hits" ] && report "build products in git status:
$hits"

# 7. company facts come from the generated file (the gate never calls ez)
[ -f Slips/Generated/Company.swift ] || report "Slips/Generated/Company.swift missing: run scripts/gen-company.sh"

[ $fail -eq 0 ] && echo "hygiene ok"
exit $fail
