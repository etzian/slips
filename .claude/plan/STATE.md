# STATE

STATUS: RUNNING
<!-- PENDING | RUNNING | DONE | BLOCKED -->

M1 — Standalone MVP. Spec: `.claude/plan/PHASES.md`.
Source docs: `docs/EXECUTION_PLAN.md`, `docs/adr/0001-swiftui-native.md`, `docs/adr/0002-local-storage-grdb.md`.
13 phases (P1–P13), one commit each. Releases as v0.1.0 (TestFlight).

## Roadmap

| # | Milestone | Execution plan | Status |
|---|---|---|---|
| M1 | Standalone MVP | §1–§6, §9, §10 | cut 2026-10-20 |
| M2 | On-device AI and optional endpoint | §7 | planned |
| M3 | Import (share extension, mail) and direct cloud APIs | §6 | planned |
| M4 | fin connector, sign-in with fin credentials (ADR 0003) | §8; needs fin's receipts milestone (`../fin/docs/RECEIPTS_CONNECTOR.md`) with the authorize/token endpoints | planned |
| M5 | Release polish, App Store decision | — | planned |

## Preconditions

The user's steps. `etzian:next-phase` stops while any is unchecked.

- [x] ADR 0001 (SwiftUI) accepted (user, 2026-10-20: iPhone-only, so Swift)
- [x] ADR 0002 (GRDB, MIT) accepted (user, 2026-10-20); ADR 0003 (fin sign-in) accepted the same day
- [x] Xcode 26 installed (26.6, build 17F113); simulator recorded in the Contract below
- [x] iOS 26.5 simulator runtime installed (26.5, 23F77); iPhone 17 on iOS 26.5 available (2026-10-22)
- [x] `git init -b main` done in `~/etzian/slips`
- [x] First commit of these plan files made (`2164337`)
- [x] `ez` on PATH (`~/etzian/_foundation`: `npm link`) and `NODE_AUTH_TOKEN` set, for `ez vendor-ui` in P1

## Contract

Passed verbatim to every `etzian:phase-runner` subagent. Repo rules also apply: `.claude/rules/`.

- Repo root: `.` · `SlipsCore/` Swift package (no UI imports) · `Slips/` app target · iPhone only, iOS 18+, Swift 6
- Foundation: `~/etzian/_foundation`; ADR 0001's table says how each layer applies; Swift rules in `.claude/rules/swift.md`
- Gate: `./scripts/gate.sh` (redirect to a file, read the tail). Simulator: `-destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`
- Storage: GRDB, append-only migrations; amounts in minor units + currency; UUID ids made on device
- Sub-category keys mirror `../fin/packages/shared/src/categories.ts`; kinds are `personal`, `family`,
  `enterprise` (+ `any` for sub-categories)
- Every delivery goes through `deliveries`; capture never waits on the network; retries are idempotent
- Strings in `Localizable.xcstrings`, `en` + `fr-CA` in the same commit; fr-CA terms from the foundation glossary
- Colours and spacing from `EZ.*` tokens (`Slips/DesignSystem/`, managed copy, never edited); SF + Dynamic Type
- Company facts only from `Slips/Generated/Company.swift` (generated from `ez profile`); bundle id `com.etzian.slips`
- No real slip, card number or registration number anywhere in the repo; fixtures are synthetic text
- No user-derived value in logs; secrets in the Keychain only
- No new dependency without naming its licence and asking
- No Apple Developer Program membership yet (user, 2026-10-20): P1–P8 use automatic signing with a
  personal team or none, and no iCloud or background-task entitlement. P9 (iCloud container) and P13
  (TestFlight) stop `BLOCKED` and ask the user if it is still missing
- One commit per phase: `feat(m1): P<n> <slice>`; the orchestrator commits, never pushes

## Phases

| # | Slice | Status |
|---|---|---|
| P1 | Skeleton: package, app, gate, catalogs | done |
| P2 | Storage and migrations | pending |
| P3 | Reference data | pending |
| P4 | Capture: scanner → PDF on disk | pending |
| P5 | OCR and parser | pending |
| P6 | Classification screen, suggestions | pending |
| P7 | Checks | pending |
| P8 | Outbox scheduler | pending |
| P9 | Destinations: iCloud, Files folder, share sheet, naming rule | pending |
| P10 | WebDAV destination, probe, App Intent | pending |
| P11 | Library, search, export | pending |
| P12 | Data map, legal documents, mandatory screens | pending |
| P13 | Accessibility, fr-CA review, TestFlight v0.1.0 | pending |

## Handoff log

### P1 — skeleton · pass · 2026-10-22 · commit HASH

Attempt 1 (sonnet) passed the gate but generated the project with XcodeGen (ADR 0001: "No XcodeGen or
Tuist"); attempt 2 (opus) removed it. Orchestrator re-ran `./scripts/gate.sh` (exit 0), `ez doctor .`
(ok) and `scripts/check-hygiene.sh` (ok).

- CHANGED: `SlipsCore/` package (Swift 6, iOS 18 / macOS 15, GRDB exact 7.11.1, one test);
  `Slips.xcodeproj` hand-maintained (objectVersion 77, 3 synchronised root groups, iPhone only, shared
  `Slips` scheme); `Slips/` placeholder app on `EZ` tokens; `Localizable.xcstrings` + `InfoPlist.xcstrings`
  (en, fr-CA); `Slips/Config/Version.xcconfig` 0.1.0 / 1; `Slips/DesignSystem/` via `ez vendor-ui`
  (@etzianco/ui 2.5.3); `SlipsTests/`, `SlipsUITests/` launch test; the four `scripts/`; `ez-vendor.json`,
  `i18n-exception.json`, `package.json`, `cliff.toml`, `.gitignore` (+ `node_modules/`),
  `LICENSES/THIRD-PARTY.md` (GRDB 7.11.1, MIT)
- DECISIONS: Slips.xcodeproj/project.pbxproj is the source of truth, hand-maintained, with no generator. New files under Slips/, SlipsTests/ and SlipsUITests/ are picked up automatically; edit the pbxproj only for settings and exceptions. SlipsCore is linked into the app only; SlipsTests imports it through the host app (TEST_HOST/BUNDLE_LOADER). The app name is CFBundleDisplayName in Slips/Resources/InfoPlist.xcstrings, so Localizable.xcstrings holds only screen strings (`placeholder.title`). Set SLIPS_SIM_DESTINATION to run the gate on another simulator. THIRD-PARTY.md format: `## <package identity> <version>` then `SPDX: <id>` line (the licence check parses it; new packages need the same).
- DEFERRED: none (attempt 1 noted: no app icon image, empty AppIcon set; Company.swift / gen-company.sh belong to P12)
- MANUAL: none
