# STATE

STATUS: PENDING
<!-- PENDING | RUNNING | DONE | BLOCKED -->

M1 — Standalone MVP. Spec: `.claude/plan/PHASES.md`.
Source docs: `docs/EXECUTION_PLAN.md`, `docs/adr/0001-swiftui-native.md`, `docs/adr/0002-local-storage-grdb.md`.
12 phases (P1–P12), one commit each. Releases as v0.1.0 (TestFlight).

## Roadmap

| # | Milestone | Execution plan | Status |
|---|---|---|---|
| M1 | Standalone MVP | §1–§6, §9 | cut 2026-10-20 |
| M2 | On-device AI and optional endpoint | §7 | planned |
| M3 | Import (share extension, mail) and direct cloud APIs | §6 | planned |
| M4 | fin connector | §8; needs fin's receipts milestone (`../fin/docs/RECEIPTS_CONNECTOR.md`) | planned |
| M5 | Release polish, App Store decision | — | planned |

## Preconditions

The user's steps. `etzian:next-phase` stops while any is unchecked.

- [ ] ADR 0001 (SwiftUI) and ADR 0002 (GRDB, MIT) accepted: change their status to Accepted
- [ ] Xcode 26 installed; record the simulator name to use in the Contract below
- [ ] Apple Developer Program membership (needed from P9: iCloud container, background tasks, TestFlight)
- [ ] `git init -b main` done in `~/etzian/slips` and the first commit of these plan files made

## Contract

Passed verbatim to every `etzian:phase-runner` subagent. Repo rules also apply: `.claude/rules/`.

- Repo root: `.` · `SlipsCore/` Swift package (no UI imports) · `Slips/` app target · iOS 18+, Swift 6
- Gate: `./scripts/gate.sh` (redirect to a file, read the tail). Simulator: `<fill in>`
- Storage: GRDB, append-only migrations; amounts in minor units + currency; UUID ids made on device
- Sub-category keys mirror `../fin/packages/shared/src/categories.ts`; kinds are `personal`, `family`,
  `enterprise` (+ `any` for sub-categories)
- Every delivery goes through `deliveries`; capture never waits on the network; retries are idempotent
- Strings in `Localizable.xcstrings`, `en-CA` + `fr-CA` in the same commit
- No real slip, card number or registration number anywhere in the repo; fixtures are synthetic text
- No user-derived value in logs; secrets in the Keychain only
- No new dependency without naming its licence and asking
- One commit per phase: `feat(m1): P<n> <slice>`; the orchestrator commits, never pushes

## Handoff log

_(empty)_
