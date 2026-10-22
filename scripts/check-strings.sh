#!/usr/bin/env bash
# Every key of every String Catalog has en + fr-CA, none new/needs_review, no other locale.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -I - <<'PY'
import glob, json, sys
errors = []
files = [f for f in glob.glob("Slips/**/*.xcstrings", recursive=True)]
if not files:
    errors.append("no .xcstrings found")
for f in files:
    cat = json.load(open(f, encoding="utf-8"))
    if cat.get("sourceLanguage") != "en":
        errors.append(f"{f}: sourceLanguage must be en")
    for key, entry in cat.get("strings", {}).items():
        locs = entry.get("localizations", {})
        extra = set(locs) - {"en", "fr-CA"}
        if extra:
            errors.append(f"{f}: {key}: unexpected locale(s) {sorted(extra)}")
        for loc in ("en", "fr-CA"):
            if loc not in locs:
                errors.append(f"{f}: {key}: missing {loc}")
                continue
            def states(node):
                if isinstance(node, dict):
                    if "state" in node:
                        yield node["state"]
                    for v in node.values():
                        yield from states(v)
            for st in states(locs[loc]):
                if st != "translated":
                    errors.append(f"{f}: {key}: {loc} state {st}")
if errors:
    print("\n".join(errors))
    sys.exit(1)
print(f"strings ok ({len(files)} catalog(s))")
PY
