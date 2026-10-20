# Slips

An iPhone app that scans purchase slips and bills, extracts their data, has the user classify each one
(profile, business, category, sub-category, payment method) and delivers the PDF and its data to the
destinations the user picks: on-device library, iCloud, a folder in Files, a LAN server, later Dropbox,
OneDrive, Google Drive and **fin** (`~/etzian/fin`). Working name; repo `~/etzian/slips`.

**Standalone first.** Every feature works with no server. fin is an optional connector, never a dependency.

People trust this app with what they buy and with business tax evidence: a slip delivered to the wrong
place, or lost, is the worst possible failure.

## Stack (deviations from the radar are ADRs in `docs/adr/`)

- **SwiftUI, iOS 18+** (ADR 0001, deviates from the Tauri-mobile default D7). Swift 6 strict concurrency
- `SlipsCore/`: a local Swift package with **no UIKit, VisionKit or SwiftUI import**: models, storage,
  outbox, extraction parser, checks, naming rules, export. Tested with `swift test` on macOS
- `Slips/`: the app target: screens, VisionKit scanner, Vision OCR, PDFKit, destinations, App Intents
- **SQLite via GRDB** (ADR 0002, MIT) under Application Support; files under `Slips/<profile>/<slip-id>/`
- **i18n:** String Catalogs (`.xcstrings`), `en-CA` and `fr-CA`; fr-CA is a release blocker
- Secrets (OAuth tokens, device tokens, WebDAV passwords) in the **Keychain only**
- Long-range plan: `docs/EXECUTION_PLAN.md`. fin contract: `../fin/docs/api/receipts-v1.md` (owned by fin)

## Run / verify

```sh
./scripts/gate.sh        # swift test (SlipsCore) + xcodebuild build/test on the simulator + checks
```

Redirect output to a file and read the tail.

## Invariants

- **Capture never waits on the network.** A scan is written to disk and to the database before any
  delivery starts. Every delivery goes through the outbox (`deliveries` table), including iCloud.
- **Idempotent delivery.** Each slip has a client UUID and the SHA-256 of its PDF; a retry never creates a
  second copy at a destination.
- **Nothing leaves the device without a destination the user turned on.** No analytics, no crash
  reporter that sends data, no third-party SDK beyond the ones an ADR names.
- **No real slips in the repo.** Tests use synthetic OCR text in `SlipsCore/Tests/Fixtures/`; never a
  photo of a real receipt, a real card number or a real registration number.
- **No amount, merchant, card digit or token in logs.** `os.Logger` with `privacy: .private` for anything
  user-derived.
- **Strings through String Catalogs** in both locales; money, dates and numbers through `FormatStyle`
  with the slip's currency, never hand-built.
- **Licences:** `_foundation/tech/licences/policy.yaml`. No new Swift package without naming its licence
  and asking.
- **SlipsCore stays pure.** If logic needs UIKit, it is in the wrong target.

## Key paths

| Path                | Role                                                          |
| ------------------- | ------------------------------------------------------------- |
| `SlipsCore/`        | Swift package: model, GRDB storage, outbox, parser, export    |
| `Slips/`            | App target: SwiftUI screens, scanner, OCR, destinations       |
| `Slips/Resources/`  | `Localizable.xcstrings`, `PrivacyInfo.xcprivacy`, assets      |
| `scripts/gate.sh`   | The one gate                                                  |
| `docs/`             | `EXECUTION_PLAN.md`, `adr/`, `DATA_MAP.md`                    |
| `.claude/plan/`     | Phase plan (`PHASES.md` frozen spec, `STATE.md` state)        |

## Phased work

`etzian:next-phase` runs the next phase of `.claude/plan/PHASES.md`. Rules: `.claude/rules/phase-work.md`.
One commit per phase, orchestrator commits, nobody pushes. Never edit `PHASES.md` mid-flight.
