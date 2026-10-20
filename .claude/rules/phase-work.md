# Phase work in Slips

Repo rules for anyone implementing or verifying a plan phase (`etzian:phase-runner`,
`etzian:next-phase`).

## Data that must never be in the repo

- No photo, scan or PDF of a real slip or bill, anywhere (sources, tests, fixtures, plan files, a return
  block). Tests use synthetic OCR transcripts in `SlipsCore/Tests/Fixtures/ocr/`.
- No real card number, account number, GST/QST registration number, merchant address or person's name in
  fixtures. Fake values only, visibly fake.
- A gate never needs the network beyond `localhost`, a real device, a LAN NAS, iCloud or a cloud account.

## Checks on every phase, whatever its gate says

- `scripts/check-hygiene.sh` exits 0.
- `git status --porcelain` shows no file under `DerivedData/`, `xcuserdata/` or `.build/`.

## Commits

One commit per phase on `main`, message `feat(m<milestone>): P<n> <slice>` (for example
`feat(m1): P8 outbox scheduler`). The orchestrator commits; it never pushes.

## Device-only checks

Scanner, OCR quality, Files-provider bookmarks and background uploads cannot be proven on the simulator.
A phase that touches them lists the manual device check in its handoff as a user step; it does not claim
it was done.
