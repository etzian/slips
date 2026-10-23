# STATE

STATUS: BLOCKED
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
| P5 | OCR and parser | done |
| P6 | Classification screen, suggestions | done |
| P7 | Checks | done |
| P8 | Outbox scheduler | done |
| P9 | Destinations: iCloud, Files folder, share sheet, naming rule | done (iCloud entitlement waits on membership) |
| P10 | WebDAV destination, probe, App Intent | done |
| P11 | Library, search, export | done |
| P12 | Data map, legal documents, mandatory screens | done except generated legal documents (foundation's `ez legal` missing) |
| P13 | Accessibility, fr-CA review, TestFlight v0.1.0 | blocked (release preconditions are the user's) |

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

### P4 — capture · pass (Linux, xcodebuild not run) · 2026-10-23 · commit 5ab69f2

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

### P5 — OCR and parser · pass (Linux, xcodebuild not run) · 2026-10-23 · commit bb01c8a

Gate steps 1, 3, 4, 5 exit 0 (45 core tests; all 27 fixtures 100 % on required fields; optional fields
≥ 95 %). App sources parse-checked only.

- CHANGED: core `Extraction/` (`OCRLine`, `NormalizedRect`, `OCRRow` row merging, `Extraction` +
  `ExtractedField`, `SlipParser` with one function per field, `Slip.apply`), `CaptureStore.recordExtraction`;
  `Tests/Fixtures/ocr/` 27 synthetic transcripts + expected JSON; `ParserTests.swift`; app
  `Capture/OCRService.swift` (`VNRecognizeTextRequest`, fr-FR + en-US, no language correction), capture
  flow saves → OCR → text-layer PDF (`replacePDF`) → parse; `SlipsTests/OCRServiceTests.swift`
- DECISIONS: Fixture format: one row per line, ` | ` splits observations on a row, ` @0.3` = recogniser confidence, `---page---`. Field confidence = rule confidence × row confidence; < 0.6 is "low" (`ExtractedField.lowConfidence`). Total = largest amount on a TOTAL-like row (tip included), fallback MONTANT/AMOUNT at 0.6. HST present → GST/QST not read. Ambiguous numeric dates: the future reading loses, else 2-digit year → MM/DD/YY, 4-digit → DD/MM/YYYY at 0.5. Currency CAD at 0.7 when none printed. Registration numbers normalised `123456789 RT0001` / `1234567890 TQ0001`. `slips.extracted` = `Extraction` JSON; re-OCR of an edited slip keeps the user's values. Regex helpers are `regexMatches`/`regexFirstMatch` (NSRegularExpression; ICU needs `\x{…}` escapes).
- DEFERRED: none
- MANUAL: OCR quality on a real device with a few real slips (never committed); run `./scripts/gate.sh` on the Mac

### P6 — classification and suggestions · pass (Linux, xcodebuild not run) · 2026-10-23 · commit 0eb1843

Gate steps 1, 3, 4, 5 exit 0 (57 core tests). App sources parse-checked only.

- CHANGED: core `Classification/` (`MerchantName.normalize`, `Suggestions.suggest`, `SlipStore`:
  suggestion, `saveDraft`, `markReady` with memory upsert + deliveries), `Money.minorUnits(from:)`;
  app `Review/ReviewView.swift` (thumbnail, editable fields with low-confidence marks, pickers, Save /
  Save as draft), `Review/ChecksSection.swift` (renders `slips.checks`), capture now opens the review;
  `AppModel.slips`; 36 new catalog keys
- DECISIONS: Pre-fill per field, first consistent source wins: card last four → payment method (+ its default kind/business) → merchant memory → profile's most recent memory row ("last used"); archived rows never suggested; suggestion only applied when the slip has no classification yet. `markReady` requires kind + sub-category (+ business when kind = enterprise) and no blocking check (`SaveError`); it clears the business for non-business kinds; deliveries are created for enabled destinations **except `library`** (the library is the slip itself), never duplicated. Check messages are catalog keys `check.<code>` filled with `Check.values` via `String(format:)`.
- DEFERRED: none
- MANUAL: run `./scripts/gate.sh` on the Mac

### P7 — checks · pass (Linux, xcodebuild not run) · 2026-10-23 · commit 150573d

Gate steps 1, 3, 4, 5 exit 0 (67 core tests; one test per check, firing and not firing). App sources
parse-checked only.

- CHANGED: core `Checks/SlipChecks.swift` (8 rules of plan §5 + `file_missing`, `Context`, `Code`),
  `Check.values` typed (`CheckValue`: money, day, text, number), `SlipStore.checks(for:)` (duplicates
  and known last fours from the database, file on disk), `saveDraft`/`markReady` store fresh checks;
  app: checks re-run on every edit of the review screen, messages formatted per locale, "Create this
  payment method" on `card_unknown`; 9 catalog keys
- DECISIONS: `slips.checks` is recomputed on every save (draft or ready), never trusted from the caller; `markReady` refuses on any blocking check (`total_missing`, `file_missing`). Tax rate: |GST − round(5 % × taxable)| > 1 ¢ or |QST − round(9.975 %)| > 1 ¢ → info; taxable = subtotal, else total − taxes − tip. Duplicate = same profile, day, total and normalised merchant, other id, not archived. Date limit 2 years by default (`Context.maxAgeYears`). Check messages with values use `String(format:)` with `%@`; a message without values is shown raw (so a literal `%` is safe only there).
- DEFERRED: none
- MANUAL: run `./scripts/gate.sh` on the Mac

### P8 — outbox scheduler · pass (Linux, xcodebuild not run) · 2026-10-23 · commit dfd49a5

Gate steps 1, 3, 4, 5 exit 0 (86 core tests; outbox suites run 5× without a flake). App sources
parse-checked only.

- CHANGED: core `Outbox/` (`DestinationAdapter` protocol + `Reachability`, `RemoteRef`, `DeliveryItem`,
  `DeliveryError`, `NetworkConditions`; `Outbox` actor; `DeliveryQueue`: summaries, manual retry,
  backlog on enable, re-queue after edit), `SlipStore.markReady` re-queues; `OutboxTests.swift` with
  `FakeDestination` + `TestClock` (offline→online, 500→201, write-then-timeout, 401, bad vs good
  destination, restart mid-flight, tampered file, Wi-Fi only, concurrency 1/3, concurrent drains);
  app `Outbox/DeliveryScheduler.swift` (foreground, `NWPathMonitor`, `BGAppRefreshTask`
  `com.etzian.slips.outbox`, save, next-due timer), `Outbox/DestinationAdapters.swift` (none yet),
  `Slips/Info.plist` (BGTaskSchedulerPermittedIdentifiers, UIBackgroundModes fetch; excluded from the
  synced group, `INFOPLIST_FILE` set, merged with the generated keys)
- DECISIONS: The protocol is `DestinationAdapter` (the `Destination` name is the record); `exists` returns `RemoteRef?` rather than Bool. Every step is a DB write first: claim (`pending`→`in_flight`, conditional UPDATE so two drains never take the same row) → `exists` → `deliver` → `done` with `remote_ref` + `delivered_sha256`. Errors: `.unauthorized` → `needs_auth` and all pending rows of that destination too; `.permanent` → `failed`; `.transient` → backoff 30 s, 2 min, 10 min, 1 h, 6 h…, `failed` at attempt 20. Probe `.unreachable` costs no attempt. The file is re-hashed before each attempt (`hash_mismatch` → failed). `in_flight` older than 15 min → `pending`. A drain called during a drain loops once more. Wi-Fi-only destinations need Wi-Fi and no Low Data Mode. Destination config `sidecar = "1"` = keeps a JSON sidecar; edits re-queue `done` rows of sidecar destinations or of naming rules with field tokens, keeping `remote_ref` so the adapter gets `previousRef` (the adapter must replace/move the old copy). Enabling a destination should call `enqueueBacklog`.
- DEFERRED: none
- MANUAL: on a device, background refresh only fires after real use; run `./scripts/gate.sh` on the Mac

### P9 — iCloud, Files folder, share sheet, naming · pass except the iCloud entitlement (Linux, xcodebuild not run) · 2026-10-23 · commit f8d1e1e

The Contract says P9 stops BLOCKED without Apple Developer membership. Everything that does not need
the membership is built; the iCloud **entitlement** is not added (a personal team cannot sign an
iCloud container), so `ICloudAdapter.probe()` answers unreachable and iCloud rows wait. Gate steps 1,
3, 4, 5 exit 0 (104 core tests). App sources parse-checked only.

- CHANGED: core `Delivery/NamingRule.swift` (tokens, sanitising, NFC, 120-char parts, `_{id8}`,
  `SlipLabels`), `Delivery/Sidecar.swift`, `Delivery/DirectoryWriter.swift` (exists/deliver for any
  folder, collision, sidecar, move after rename), `Services/DestinationStore.swift`; `DeliveryItem.labels`
  resolved by the outbox; `NamingTests.swift`; `docs/SIDECAR.md`; app `Outbox/FileDestinations.swift`
  (`ICloudAdapter` `iCloud.com.etzian.slips/Documents`, `FolderAdapter` with security-scoped bookmark,
  `NSFileCoordinator`), `Destinations/` (list with state and banner, detail: name, on/off, naming rule
  + preview, Wi-Fi only, sidecar, retry now, pick folder again, remove), Share in the review toolbar;
  `Info.plist` `NSUbiquitousContainers`; 39 catalog keys
- DECISIONS: File names always end `.pdf`; empty folder parts are dropped; values have `/ : \ * ? " < > |` and control characters replaced by `-`; `..` cannot survive; `{total}` is `1234.56` (no grouping), `{date}` the slip's day or the capture day (UTC). A name held by a different file gets `_{id8}`; `exists` = same size and SHA-256 (and, with a sidecar, identical sidecar bytes). Re-delivery after an edit removes the previous copy only if it is still byte-identical. Folder bookmark is base64 in `config.bookmark` (+ `folder_name`); stale/refused → `needs_auth` ("choose the folder again"). The library cannot be turned off or removed. Turning a destination on queues the backlog. Selection sharing lands with the library in P11.
- DEFERRED: iCloud entitlement (`Slips/Slips.entitlements` with `com.apple.developer.icloud-container-identifiers` = `iCloud.com.etzian.slips`, `com.apple.developer.icloud-services` = `CloudDocuments`, `com.apple.developer.ubiquity-container-identifiers`; `CODE_SIGN_ENTITLEMENTS`) once the membership exists
- MANUAL: (user) Apple Developer membership, then the entitlement above and the container in the developer portal; a Folder destination on iCloud Drive and on one File Provider app (Dropbox, OneDrive or Google Drive) on a device, noting whether the bookmark survives a relaunch; run `./scripts/gate.sh` on the Mac

### P10 — WebDAV destination and App Intent · pass (Linux, xcodebuild not run) · 2026-10-23 · commit 8ea264c

Gate steps 1, 3, 4, 5 exit 0 (114 core tests, including the exit scenario "500 for ten minutes, then
201: delivered once, the other destination not held up"). App sources parse-checked only. No localhost
container: the tests use an in-process WebDAV double, so no port was taken from `ez ports`.

- CHANGED: core `Delivery/WebDAV.swift` (`HTTPTransport`, `WebDAVConfig` + HTTPS validation,
  `WebDAVClient` adapter, `PropfindParser`, `URLSessionTransport`), `DeliveryQueue.waitingCount`;
  `WebDAVTests.swift` (`FakeWebDAVServer`); app `Outbox/Keychain.swift`, `Outbox/BackgroundUploads.swift`
  (background `URLSession` for PUT, app delegate re-attach), WebDAV in `DestinationAdapters`,
  `Destinations/WebDAVSetupView.swift` (test connection), `Destinations/AutomationHelpView.swift`,
  `Intents/SendPendingSlipsIntent.swift`; `Info.plist` `NSAllowsLocalNetworking`;
  `NSLocalNetworkUsageDescription` (build setting + InfoPlist catalog); 27 catalog keys
- DECISIONS: `exists` = PROPFIND depth 0 size check **then a GET + SHA-256 compare** when the size matches: two different slips can share a name and size (a test caught that the size alone would have skipped the second slip). Probe = health URL `GET` or `OPTIONS` base, 3 s; 2xx–3xx reachable, 401 needs_auth. MKCOL 201/405/301 ok, 409 → permanent `base_missing`; PUT from the file (background session) 200/201/204. 401 → unauthorized; 403/404/405/409/413/415 → permanent; others and network errors → transient. Plain `http` refused unless the destination has `local_network = "1"`; the ATS exception is `NSAllowsLocalNetworking` only. Password in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, service `com.etzian.slips.destination`, account = destination id), never in config. An upload that finishes while the app is gone is recorded by the next drain's `exists`.
- DEFERRED: none
- MANUAL: on a device against a real LAN WebDAV server (NAS or container): add it, airplane mode, scan, back online, check one copy; the Shortcuts automation from the help page; run `./scripts/gate.sh` on the Mac

### P11 — library, search, export · pass (Linux, xcodebuild not run) · 2026-10-23 · commit 86e4ff0

Gate steps 1, 3, 4, 5 exit 0 (125 core tests; the ZIP also passes `unzip -t`). App sources
parse-checked only.

- CHANGED: core migration `v2_fts` (FTS5 `slips_fts`, external content + triggers, `remove_diacritics 2`),
  `Library/LibraryQuery.swift` (`LibraryFilter`, `LibraryItem` with `DeliveryState`, months),
  `Export/Exporter.swift` (rows, CSV, JSON, ZIP, manifest), `Export/Zip.swift` (stored ZIP + CRC32, no
  dependency); `LibraryExportTests.swift`; `docs/EXPORT.md`; app `Library/` (`LibraryView` by month with
  search, filters, selection share, banner and waiting note; `LibraryFilterView`; `SlipDetailView` with
  PDF view, checks, per-destination state + retry, edit through the review screen; `ExportView`);
  44 catalog keys
- DECISIONS: Search = each word a quoted prefix term, all required; FTS syntax typed by the user is neutralised. The library files a slip under its day, else its capture day (UTC). Delivery state per slip: none → local only, any failed/needs_auth → problem, all done → delivered, else waiting. "With warnings" = a warning or blocking check stored. CSV: BOM + CRLF, formula-looking text prefixed with `'`. Export PDF names use the default naming rule, clashes get `_{id8}`; files are written to a temp folder with complete protection and leave only through the share sheet. Editing a filed slip from its detail goes through `markReady` (re-queues destinations per P8).
- DEFERRED: none
- MANUAL: run `./scripts/gate.sh` on the Mac

### P12 — data map, legal documents, mandatory screens · pass except the generated legal documents (Linux, xcodebuild not run) · 2026-10-23 · commit 96a9003

The foundation clone available here (etzianco/foundation `dbd3fa2`) has no legal layer yet: no
`legal/schema/data-map.schema.yaml`, no `vendors.yaml`, no `ez legal gen` / `ez legal check`. So
`legal/generated/` (privacy policy, terms, EULA, retention schedule, EFVP, Apple worksheet) and
`Slips/Resources/PrivacyInfo.xcprivacy` were **not** produced: they must be generated, never written by
hand. Everything else is in. Gate steps 1, 3, 4, 5 exit 0 (126 core tests). App sources parse-checked only.

- CHANGED: `legal/data-map.yaml` (from the code: archetype standalone, app-store, permissions camera,
  photos, files, local network, Face ID; data, storage, protection, retention; every destination and
  what it receives; erasure); `scripts/gen-company.sh` (`ez profile --json` → `Slips/Generated/Company.swift`
  + copy of `THIRD-PARTY.md`; `--check` diffs), generated files committed; `check-hygiene.sh` fails
  when `Company.swift` is missing; core `Services/Eraser.swift` + test; app `Mandatory/` (first run once,
  About with version, *by Etzian*, copyright, licences and bundled documents when present, Privacy page
  with lock and per-destination "what it receives", Face ID / passcode lock, "Erase all data on this
  iPhone" last in Settings, confirmed); `NSFaceIDUsageDescription`; `SlipsTests/MandatoryTests.swift`
  (first-run flag, erase, file protection, company facts); 41 catalog keys
- DECISIONS: About lists `privacy-policy.<fr-CA|en>.md`, `terms…`, `eula…` only if bundled (drop the generated files into `Slips/Resources/Legal/` when `ez legal gen .` exists). The lock uses `.deviceOwnerAuthentication` (Face ID, else passcode) and engages when the app goes to the background. Erase deletes every row, the `Slips/` folder, Keychain items of every destination and the preferences, vacuums the database, then bootstraps a new profile and shows the first run again. `-uiTesting` starts past the first run (`-firstRun` to test it). App name and version come from the bundle; company facts only from `Company.swift`.
- DEFERRED: `legal/generated/*`, bundling them, `PrivacyInfo.xcprivacy` and `ez legal check .` — waiting on the foundation's legal layer (its P6)
- MANUAL: (user) build the foundation legal layer or run `ez legal gen .` from a foundation that has it; validate `legal/data-map.yaml` against the schema; EFVP transfer assessment for iCloud (Apple, outside Québec); `scripts/gen-company.sh --check` against your local `ez`; run `./scripts/gate.sh` on the Mac

### P13 — accessibility, fr-CA review, v0.1.0 · blocked · 2026-10-23

Accessibility and the fr-CA review are done; the release is not cut. `.claude/rules/release.md`
requires, before a release: `./scripts/gate.sh` green (the xcodebuild step has never run: no Mac in
this session), `ez doctor .` and `ez legal check .` passing, legal documents generated and the
`PrivacyInfo.xcprivacy` verified on a release build (P12: the foundation's legal layer is missing),
and `etzian:legal-compliance` over a release that changes what leaves the device. TestFlight needs the
Apple Developer membership. Tagging `v0.1.0` before those would be a release that skipped its gates.

- CHANGED: library rows stack and never truncate amounts at accessibility sizes; review header switches
  to a vertical layout when it does not fit; 44 pt clear-date control; edit-mode animation honours
  Reduce Motion; accessibility identifiers `review.kind`, `review.subcategory`; debug-only
  "Use a sample page" capture under `-uiTesting`; `SlipsUITests/CaptureFlowUITests.swift` (capture →
  review → save → library, first run once); fr-CA pass over all 320 keys (typographic apostrophes, U+00A0
  before `:` and `%`, Québec terms reçu, commerçant, sous-catégorie, mode de paiement, TPS, TVQ, TVH;
  nothing left in English)
- DECISIONS: `etzian:ui-reviewer`, `etzian:i18n-guardian` and `etzian:legal-compliance` were not available in this session; the reviews above were done by hand against `.claude/rules/swift.md` and the GUIDELINES behaviour contract, and should be re-run with the agents.
- DEFERRED: release v0.1.0 (`etzian:release`: CHANGELOG via git-cliff, local tag), archive and TestFlight upload
- MANUAL: (user) 1. On the Mac: `./scripts/gate.sh` — the first type-check of every app source written in this session; fix what Xcode reports. 2. `ez doctor .`. 3. Apple Developer membership → iCloud entitlement (P9 DEFERRED). 4. Foundation legal layer → `ez legal gen .`, bundle the documents, `PrivacyInfo.xcprivacy`, `ez legal check .`, EFVP iCloud transfer assessment, `etzian:legal-compliance`. 5. `etzian:ui-reviewer` and `etzian:i18n-guardian`. 6. Device exit test: airplane mode, scan three slips, classify, quit; airplane off, open: each slip at each enabled destination exactly once; every fr-CA screen at AX5. 7. Then `etzian:release` v0.1.0, archive, TestFlight.
