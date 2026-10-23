# Plan — M1 Standalone MVP — 13 phases (P1–P13)

Spec file. Never edited by the loop. Every phase ends in a gate that exits 0/non-zero; that exit code is
what the orchestrator surfaces to the `/goal` evaluator.

Source docs (read before any phase):
- `docs/EXECUTION_PLAN.md` — §2 architecture, §3 data model, §4 extraction, §5 checks, §6 outbox,
  §9 privacy, §10 foundation alignment and mandatory screens.
- `docs/adr/0001-swiftui-native.md` (its table maps each foundation layer), `docs/adr/0002-local-storage-grdb.md`.
- `.claude/rules/swift.md` for every Swift source.
- `.claude/plan/STATE.md` — Contract block + Handoff log.

Milestone in one line: on an iPhone with no server at all, a slip is scanned, read, classified and
checked in under a minute, kept in a searchable library, and delivered to iCloud, a chosen Files folder
and a WebDAV server, with deliveries that survive being offline and never duplicate. Releases as
**v0.1.0** on TestFlight.

Exit test:
- `./scripts/gate.sh` passes on a clean clone.
- On a real device (by hand, recorded in P13's handoff): airplane mode on, scan three slips, classify them,
  quit the app; airplane mode off, open the app: each slip is at each enabled destination exactly once.
- A WebDAV server that answers 500 for ten minutes, then 201: the slip arrives once, the others were not
  held up.
- Every screen in fr-CA has no English string and no truncation at the largest Dynamic Type size.
- `ez doctor .` passes; `ez legal check .` passes except for the lawyer review it reports as pending.

Execution model: one commit per phase on `main`, message `feat(m1): P<n> <slice>`. The orchestrator
commits and never pushes. Keep each phase in a fresh context.

## Model per phase

- `sonnet` — default.
- `opus` — P8 (outbox scheduler: a quiet slip loses or duplicates evidence) and P5 (parser: the rest of
  the app trusts its fields).

| # | Slice | Model | Size | Retry risk |
|---|---|---|---|---|
| P1 | Skeleton: package, app, gate, catalogs | sonnet | M | medium (xcodebuild flags) |
| P2 | Storage and migrations | sonnet | M | low |
| P3 | Reference data: profiles, businesses, sub-categories, payment methods | sonnet | M | low |
| P4 | Capture: scanner → PDF on disk | sonnet | M | medium (device-only API) |
| P5 | OCR and parser | opus | L | medium (fixture breadth) |
| P6 | Classification screen, suggestions | sonnet | M | low |
| P7 | Checks | sonnet | S | low |
| P8 | Outbox scheduler | opus | M | medium (concurrency) |
| P9 | Destinations: iCloud, Files folder, share sheet, naming rule | sonnet | M | medium (bookmarks) |
| P10 | WebDAV destination, probe, App Intent | sonnet | M | medium (background) |
| P11 | Library, search, export | sonnet | M | low |
| P12 | Data map, legal documents, mandatory screens | sonnet | M | low |
| P13 | Accessibility, fr-CA review, TestFlight v0.1.0 | sonnet | M | low |

## Gate commands (canonical)

- `./scripts/gate.sh` runs, in order, and fails on the first error:
  1. `swift test --package-path SlipsCore` (macOS host, no simulator)
  2. `xcodebuild -scheme Slips -destination 'platform=iOS Simulator,name=<sim from STATE>' build test`
     with `-quiet`
  3. `scripts/check-strings.sh`: every key in `Localizable.xcstrings` has `en` and `fr-CA`, no state
     `new` or `needs_review`, no other locale code (`en-CA`, `fr`, `en-US` fail, as in `ez i18n-check`)
  4. `scripts/check-hygiene.sh`: no `print(` in app or core sources; no `import UIKit|SwiftUI|VisionKit`
     under `SlipsCore/Sources`; no image or PDF under `SlipsCore/Tests/Fixtures`; no 13–19 digit run in
     sources or fixtures (card numbers); no colour literal (`Color(red:`, `#colorLiteral`, hex) in
     `Slips/` outside `Slips/DesignSystem/`
  5. `scripts/check-licences.sh`: every package in `Package.resolved` is in `LICENSES/THIRD-PARTY.md` with
     an SPDX id from the `allow` list of `../_foundation/tech/licences/policy.yaml` (or a dated
     entry in `licence-exceptions.yaml`); it reads the foundation's file, never a copy, and fails if it
     is missing
- No gate contacts the network except `localhost`. P10's WebDAV tests run against an in-process test
  server (`SlipsCore` test target) or a localhost container started by the gate if Docker is present;
  the gate never requires Docker.

Rules for every phase:
- Logic goes in `SlipsCore` with tests; the app target holds views, platform adapters and wiring.
- Every user-visible string is in the String Catalog with both locales (`en`, `fr-CA`) in the same commit.
- Company facts are never typed: they come from `ez profile` through `scripts/gen-company.sh`.
- Migrations are append-only (`v1_initial`, `v2_…`).
- No new Swift package beyond GRDB without naming its licence and asking.

## P1 — skeleton

**Model:** sonnet. **Size:** M.

- `SlipsCore/Package.swift` (Swift 6, platforms iOS 18 / macOS 15), targets `SlipsCore` and
  `SlipsCoreTests`, GRDB pinned to an exact version.
- `Slips.xcodeproj` with folder-synchronised groups, app target `Slips` (bundle `com.etzian.slips`, iOS 18,
  iPhone only), depends on the local package. A `SlipsTests` unit target and a `SlipsUITests` target with
  one launch test.
- `Slips/Resources/Localizable.xcstrings` with `en` (development language) and `fr-CA`; app name and one
  placeholder screen string.
- `Slips/Config/Version.xcconfig` (`MARKETING_VERSION = 0.1.0`, `CURRENT_PROJECT_VERSION = 1`), used by
  the app target (`.claude/rules/release.md`).
- `scripts/gate.sh`, `scripts/check-strings.sh`, `scripts/check-hygiene.sh`, `scripts/check-licences.sh`
  as above.
- Foundation hooks: `i18n-exception.json` (`{"system": "xcstrings", "locales": ["en", "fr-CA"], "adr":
  "docs/adr/0001-swiftui-native.md", "check": "npm run i18n:check"}`) and a `package.json` with
  `"private": true`, no `"version"`, no dependencies, and the one script `"i18n:check":
  "scripts/check-strings.sh"`. `ez-vendor.json` (`source` = the current `@etzianco/ui` release, `target`
  `Slips/DesignSystem`, `map` `{"EtzianTokens.swift": "src/platforms/swift/EtzianTokens.swift"}`), then
  `ez vendor-ui .` writes the file and its `VENDOR.json`.
- `.gitignore` (DerivedData, `xcuserdata`, `.build`, `.DS_Store`), `cliff.toml` copied from
  `~/etzian/_foundation/claude-plugin/skills/release/cliff.toml`.
- `LICENSES/THIRD-PARTY.md` listing GRDB (version, `MIT`, licence text).
- **Gate:** `./scripts/gate.sh`, then `ez doctor .` (managed copy and i18n declaration ok).

## P2 — storage and migrations

**Model:** sonnet. **Size:** M.

- `SlipsCore/Sources/SlipsCore/Storage/`: `AppDatabase` (DatabasePool in WAL, in-memory queue for tests),
  migration `v1_initial` creating every table of plan §3 with foreign keys, CHECK constraints on the enum
  columns, and indexes `deliveries(status, next_attempt_at)`, `slips(profile_id, txn_date)`,
  `merchant_memory(profile_id, merchant_norm)`.
- Records as value types (`Profile`, `Enterprise`, `Subcategory`, `PaymentMethod`, `Slip`, `Destination`,
  `Delivery`, `MerchantMemory`); `Money` = minor units + currency.
- Seeding: a new profile gets the sub-category keys of fin's `categories.ts` (list copied into
  `Seed.swift` with a comment naming the source file and date) and destinations `library` (enabled) and
  `icloud` (disabled).
- `FileStore`: paths `Slips/<profile>/<slip-id>/slip.pdf`, atomic writes, file protection classes per
  plan §9.
- Tests: migration from empty, constraint violations rejected, seeding, file store round trip.
- **Gate:** `./scripts/gate.sh`.

## P3 — reference data

**Model:** sonnet. **Size:** M.

- Screens: Profiles (list, create, rename, switch active), and per profile: Businesses, Sub-categories
  (grouped by kind, seeded keys shown with their translated name, custom names allowed, archive not
  delete when used), Payment methods (name, type, last four, currency, default kind and business).
- Settings root in the order of `docs/EXECUTION_PLAN.md` §10: General, Appearance (theme), Profiles and
  reference data, Destinations (placeholder rows until P9), Privacy, About, Danger zone (placeholders
  until P12).
- `SlipsCore` services with validation (last four = exactly 4 digits; name not blank; archive refused
  for `any.transfer`, `any.card_payment` as in fin).
- **Gate:** `./scripts/gate.sh`.

## P4 — capture

**Model:** sonnet. **Size:** M.

- Capture button presents `VNDocumentCameraViewController`; the simulator path (no camera) offers
  "Import images" from the photo picker so the flow is testable.
- Pages → JPEG (plan §4) → PDF (PDFKit) → `FileStore`; a `slips` row in `draft` with `pdf_sha256`,
  `page_count`, `captured_at`. Written before any UI moves on.
- Interrupted capture (app killed between file and row): a startup sweep removes orphan files and marks
  rows whose file is missing.
- Tests: PDF builder (page count, size bound), sweep.
- **Gate:** `./scripts/gate.sh`. Handoff records a manual device scan.

## P5 — OCR and parser

**Model:** opus. **Size:** L. Split into P5a (OCR adapter + line model) and P5b (parser) if it grows.

- App: `OCRService` runs `VNRecognizeTextRequest` per page, returns `[OCRLine(text, box, page)]`; the
  PDF is rebuilt with an invisible text layer.
- Core: `SlipParser.parse([OCRLine]) -> Extraction` with field, value, confidence, source line, for every
  field of plan §4. Pure functions per field, composed.
- Fixtures: at least 25 synthetic transcripts under `SlipsCore/Tests/Fixtures/ocr/` covering grocery,
  restaurant with tip, gas station, hardware store, online invoice, a bilingual slip, HST (Ontario), a
  USD slip, a slip with no tax, a faded total (low confidence), each with an expected JSON.
- Card and registration numbers in fixtures are made up and visibly fake (`****0000`–`****0099`,
  `100000000 RT0001`-style).
- **Gate:** `./scripts/gate.sh`; parser fixtures 100 % on the fields marked required in each expected file.

## P6 — classification and suggestions

**Model:** sonnet. **Size:** M.

- After capture: a review screen with the PDF thumbnail, the extracted fields (editable, low confidence
  highlighted), and the pickers: profile, kind, business (only when kind = enterprise), sub-category
  (filtered by kind + `any`), payment method.
- Pre-fill order: card last four → payment method → its default kind/business; then `merchant_memory`
  for the normalised merchant; then the profile's last used values.
- Save sets `ready`, updates `merchant_memory`, creates `deliveries` rows for enabled destinations.
  "Save as draft" keeps `draft` (no deliveries).
- Tests: suggestion ranking, merchant normalisation (case, accents, store numbers stripped).
- **Gate:** `./scripts/gate.sh`.

## P7 — checks

**Model:** sonnet. **Size:** S.

- `SlipChecks.run(slip, context) -> [Check]` implementing plan §5, each with a code, severity and
  translated message; shown inline on the review screen; blocking checks disable Save.
- Stored in `slips.checks`; re-run on every edit.
- **Gate:** `./scripts/gate.sh`; one unit test per check, both outcomes.

## P8 — outbox scheduler

**Model:** opus. **Size:** M.

- Core: `Outbox` actor. `drain()` selects due rows for reachable destinations, marks `in_flight`
  (crash-safe: `in_flight` older than 15 min returns to `pending`), calls `exists` then `deliver`,
  records `done` + `remote_ref` + `delivered_sha256`, or schedules the next attempt per plan §6, or
  `needs_auth`. Per-destination concurrency 1, global 3.
- A slip edited after delivery (fields or classification) re-queues destinations that keep a JSON
  sidecar or use the classification in the path; the PDF itself is immutable.
- Tests with `FakeDestination` (scripted outcomes, reachability toggles, clock injection): offline then
  online, 500 then 201, timeout after a successful write (no duplicate), 401 → `needs_auth`, one bad
  destination does not block another, app restart mid-flight.
- App: triggers from plan §6 (foreground, `NWPathMonitor`, `BGAppRefreshTask` registered in Info.plist).
- **Gate:** `./scripts/gate.sh`.

## P9 — iCloud, Files folder, share sheet, naming

**Model:** sonnet. **Size:** M.

- `NamingRule` in core: tokens and sanitising per plan §6, collision suffix; tests for every token and
  forbidden character, NFC, length cap.
- `ICloudDestination`: ubiquity container `iCloud.com.etzian.slips`, `Documents/` so it shows in Files;
  writes the PDF and `<name>.json` sidecar (schema in `docs/SIDECAR.md`, written in this phase).
- `FolderDestination`: folder picked with `UIDocumentPickerViewController` (open folder), stored as a
  security-scoped bookmark; stale bookmark → `needs_auth` ("pick the folder again").
- Destinations screen: add, enable, rename, naming rule, Wi-Fi only, sidecar on/off, status and pending
  count, "retry now".
- Share sheet on a slip and on a selection.
- **Gate:** `./scripts/gate.sh`. Handoff records a manual check of a Folder destination on iCloud Drive and
  on one File Provider app the user has (Dropbox, OneDrive or Google Drive).

## P10 — WebDAV / LAN destination and App Intent

**Model:** sonnet. **Size:** M.

- `WebDAVDestination` (core, `URLSession`-based protocol for testability): base URL, user, password in
  Keychain, optional health URL; `probe` = `OPTIONS` or the health URL with a 3 s timeout; `exists` =
  `PROPFIND` depth 0 with size check; `deliver` = `MKCOL` for missing folders then `PUT`.
- HTTPS required except for hosts the user marks "local network" (then the app's Info.plist declares
  `NSLocalNetworkUsageDescription` and an ATS exception limited to local networking).
- App Intent `SendPendingSlipsIntent` ("Send pending slips"), plus an in-app help page showing how to
  make the Shortcuts automation "When joining <home Wi-Fi> → Send pending slips → run immediately".
- Uploads through a background `URLSession` from the file on disk.
- Tests: against an in-process WebDAV test double (PUT/PROPFIND/MKCOL, scripted failures). If the gate
  starts a localhost WebDAV container, its port comes from `ez ports next server --app slips` and is
  registered in `~/etzian/_foundation/tech/ports.yaml` (handoff lists that edit as a user step).
- **Gate:** `./scripts/gate.sh`.

## P11 — library, search, export

**Model:** sonnet. **Size:** M.

- Library: list grouped by month, filters (profile, kind, business, sub-category, payment method,
  status, delivery state, checks with warnings), search on merchant, notes and OCR text (SQLite FTS5
  table `slips_fts`, migration `v2_fts`).
- Slip detail: PDF viewer, fields, checks, per-destination delivery state with retry.
- Export: CSV and JSON for a period and filter (columns in `docs/EXPORT.md`), and a ZIP of PDFs named by
  the default rule plus the CSV; delivered through the share sheet.
- Tests: CSV escaping, FTS queries, ZIP manifest.
- **Gate:** `./scripts/gate.sh`.

## P12 — data map, legal documents, mandatory screens

**Model:** sonnet. **Size:** M.

- `legal/data-map.yaml` written from the code (schema `~/etzian/_foundation/legal/schema/data-map.schema.yaml`,
  `archetype: standalone`, `store_distribution: [app-store]`, permissions camera, photos, files, local
  network; every destination and what it receives; plan §9). `ez legal gen .` writes
  `legal/generated/`; the app bundles the privacy policy, terms and EULA in both locales, and
  `Slips/Resources/PrivacyInfo.xcprivacy` is the generated manifest.
- `scripts/gen-company.sh` → `Slips/Generated/Company.swift` from `ez profile --json` (legal name,
  copyright, privacy officer title and email, support contact), header "generated, do not edit"; the gate
  only checks the file exists, it never calls `ez`.
- Mandatory screens of plan §10: first run (once), About (*by Etzian*, version, copyright, links to
  `LICENSES/THIRD-PARTY.md` and the bundled documents), Privacy page (what is stored where, what each
  destination receives, same content as the data map), optional Face ID lock, "Erase all data on this
  iPhone" (confirmed, last in Settings). File protection classes verified.
- Tests: erase leaves no file or row behind; first-run flag; `Company.swift` matches `ez profile --json`
  when run by hand.
- **Gate:** `./scripts/gate.sh`, then `ez legal check .` (only the lawyer review may be pending; the EFVP
  transfer assessment for iCloud is listed for the user).

## P13 — accessibility, fr-CA review, v0.1.0

**Model:** sonnet. **Size:** M.

- Accessibility: VoiceOver labels on every control, Dynamic Type up to AX5 without truncation of amounts,
  44 pt targets, Reduce Motion, a UI test walking capture → save with VoiceOver identifiers.
  `etzian:ui-reviewer` against the behaviour contract and `.claude/rules/swift.md`.
- fr-CA review of every string with `etzian:i18n-guardian` and `~/etzian/_foundation/i18n/glossary.fr-CA.yaml`
  (Québec terms: reçu, commerçant, sous-catégorie, mode de paiement, TPS, TVQ, TVH, téléverser);
  non-breaking space before `:` and between amount and `$` through `FormatStyle`.
- `etzian:legal-compliance` over the data map and generated documents.
- Release v0.1.0 (marketing) / build 1 with `etzian:release` (`CHANGELOG.md` via git-cliff, local tag).
  Archive and TestFlight upload are the **user's** steps, listed in the handoff.
- **Gate:** `./scripts/gate.sh`, `ez doctor .`, plus the device exit test recorded by the user.
