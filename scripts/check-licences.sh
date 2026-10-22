#!/usr/bin/env bash
# Every package in Package.resolved is listed in LICENSES/THIRD-PARTY.md with an allowed SPDX id.
set -euo pipefail
cd "$(dirname "$0")/.."
POLICY="${ETZIAN_FOUNDATION:-$HOME/etzian/_foundation}/tech/licences/policy.yaml"
[ -f "$POLICY" ] || { echo "licences: policy not found at $POLICY"; exit 1; }
python3 -I - "$POLICY" <<'PY'
import glob, json, re, sys
policy = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^allow:\s*\n((?:\s+-.*\n)+)", policy, re.M)
allow = {re.sub(r"\s+#.*", "", l.strip()[1:].strip()) for l in m.group(1).splitlines() if l.strip().startswith("-")}
exceptions = ""
try:
    exceptions = open("licence-exceptions.yaml", encoding="utf-8").read()
except FileNotFoundError:
    pass
doc = open("LICENSES/THIRD-PARTY.md", encoding="utf-8").read()
resolved = [f for f in glob.glob("**/Package.resolved", recursive=True)
            if "/.build/" not in f and "DerivedData" not in f and "xcuserdata" not in f]
resolved = [f for f in resolved if not f.startswith(".build")]
pins = {}
for f in resolved:
    data = json.load(open(f, encoding="utf-8"))
    for p in data.get("pins", []):
        pins[p["identity"].lower()] = p["location"]
errors = []
# section per package: "## <name> <version>" followed by a line "SPDX: <id>"
sections = re.split(r"^## ", doc, flags=re.M)[1:]
listed = {}
for s in sections:
    head = s.splitlines()[0].strip()
    spdx = re.search(r"^SPDX:\s*(\S+)", s, re.M)
    listed[head.split()[0].lower()] = spdx.group(1) if spdx else None
for ident in sorted(pins):
    if ident not in listed:
        errors.append(f"{ident}: not listed in LICENSES/THIRD-PARTY.md")
        continue
    spdx = listed[ident]
    if spdx not in allow and ident not in exceptions.lower():
        errors.append(f"{ident}: licence {spdx!r} not in allow list and no dated exception")
if errors:
    print("\n".join(errors)); sys.exit(1)
print(f"licences ok ({len(pins)} package(s))")
PY
