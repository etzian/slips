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
| P2 | Storage and migrations | done |
| P3 | Reference data | done |
| P4 | Capture: scanner → PDF on disk | done |
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

### P1 — skeleton · pass · 2026-10-22 · commit f63b18c

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

### P2 — storage and migrations · pass (Linux, xcodebuild not run) · 2026-10-23 · commit 1e574f0

Run in a Claude Code cloud session (Linux, Swift 6.2.1 from the official `swift:6.2.1-noble` image, no
Xcode). Gate steps 1, 3, 4, 5 exit 0 (`swift test` 18 tests; licences with
`ETZIAN_FOUNDATION=<foundation clone>`); step 2 (`xcodebuild build test`) **not run**: re-run
`./scripts/gate.sh` on the Mac before trusting this phase.

- CHANGED: `SlipsCore/Sources/SlipsCore/Storage/` (`Migrations.swift` v1_initial, `AppDatabase.swift`,
  `Seed.swift`, `FileStore.swift`); `Model/` (`Enums.swift`, `Money.swift`, `CalendarDay.swift`,
  `Records.swift`); `SlipsCoreInfo` marker and its skeleton test removed; `SlipsTests` now checks the
  migration; `Tests/SlipsCoreTests/StorageTests.swift`
- DECISIONS: UUIDs are GRDB's default 16-byte blobs (never compare with a uuid string); dates are GRDB date strings (UTC); `txn_date` is `CalendarDay` stored `YYYY-MM-DD`; amounts are `Int` minor units with the slip's `currency`, `Money` for display. Records conform to `SlipsRecord` (snake_case columns). JSON columns: `destinations.config` is `[String: String]`; `slips.extracted` and `slips.checks` are JSON `String?` until P5/P7 give them types. `merchant_memory` primary key (profile_id, merchant_norm). FKs: profile deletion cascades to everything; enterprises, sub-categories and payment methods used by a slip cannot be deleted (archive). `AppDatabase.createProfile(name:seedNames:)` takes the seeded destination names from the app (translated). `FileStore` paths are relative (`Slips/<profile>/<slip>/slip.pdf`, lowercase uuids); `.complete` for slip PDFs, `.untilFirstUnlock` for outbox staging files; protection only applied `#if os(iOS)`.
- DEFERRED: none
- MANUAL: run `./scripts/gate.sh` on the Mac (xcodebuild step)

### P3 — reference data · pass (Linux, xcodebuild not run) · 2026-10-23 · commit 350c7a6

Same Linux session. Gate steps 1, 3, 4, 5 exit 0 (31 tests). App sources pass `swiftc -parse` only:
**not type-checked**; the first Mac `./scripts/gate.sh` is their first compile.

- CHANGED: `SlipsCore/Services/ReferenceData.swift` (validation, remove = delete-or-archive, observers,
  `ReferenceSnapshot`), `Storage/Observation.swift` (`ValueObservation` → `AsyncThrowingStream`);
  `Slips/App/` (`AppModel` @Observable, `RootView` tab shell), `Slips/Settings/` (Settings root, Profiles,
  Businesses, Sub-categories, Payment methods + editor), `Slips/Support/` (Appearance, Labels, state
  views, `Metrics`), Library and Capture placeholders; `PlaceholderView` removed; 118 catalog keys (en,
  fr-CA) incl. `subcategory.<fin key>` for all 27 seed keys; launch UI test checks the 3 tabs
- DECISIONS: Catalog keys are dotted identifiers (`area.thing`), every key is `extractionState: manual`; dynamic keys (`subcategory.<key>`) are read with `Bundle.main.localizedString`. Active profile id in `UserDefaults` (`activeProfileId`); the app creates a "Personal" profile on first launch. `-uiTesting` launch argument = in-memory database + temp folder. Remove = delete when unused, archive when used; seeded sub-categories always archive; transfer keys refuse. Screens observe through `ReferenceData.observe*` streams (`.task { for try await … }`), never GRDB. Errors logged `privacy: .private`.
- DEFERRED: none
- MANUAL: run `./scripts/gate.sh` on the Mac (first compile of the app target)

### P4 — capture · pass (Linux, xcodebuild not run) · 2026-10-23

Gate steps 1, 3, 4, 5 exit 0 (36 core tests). App sources parse-checked only.

- CHANGED: core `Capture/CaptureStore.swift` (save = file then draft row, `replacePDF` until delivered,
  `sweep`), `Support/SHA256.swift` (CryptoKit; portable fallback compiled only without CryptoKit),
  `Model/Check.swift` (`Check`, `CheckSeverity`, JSON in `slips.checks`); app `Capture/` (`PDFBuilder`
  JPEG 0.7 / 2000 px / invisible text layer, `DocumentScanner`, `CaptureView` with scan + "Import
  images" via PhotosPicker); sweep at launch in `AppModel.bootstrap`; `NSCameraUsageDescription`
  (build setting + `InfoPlist.xcstrings`); `SlipsTests/PDFBuilderTests.swift`
- DECISIONS: Write order is file → row; a failed insert deletes the file. The sweep deletes slip folders with no row and adds the blocking check `file_missing` to rows whose PDF is gone (P7 must keep it). `replacePDF` (for P5's text layer) is refused once a delivery row exists. PDF pages are 842 pt on the long edge. fr-CA uses U+00A0 before `:`. Plurals use catalog plural variations.
- DEFERRED: none
- MANUAL: on a device, scan a two-page slip and check the PDF opens and is a few hundred kB; run `./scripts/gate.sh` on the Mac
