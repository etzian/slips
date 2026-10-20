# Slips — by Etzian

Scan a purchase slip or a bill with your iPhone, say what it is, and it lands where it belongs.

Slips reads the slip on the device (merchant, date, subtotal, GST/QST, tip, total, card last four,
supplier registration numbers), asks for its profile, business, category, sub-category and payment
method, checks it while you still hold the paper, and delivers the PDF to the destinations you choose,
now or as soon as they are reachable.

> **Status:** planning. M1 (standalone MVP) is cut and has not started. "Slips" is a working name.

## Standalone first, fin optional

Slips works with no server at all and has no account of its own: library on the phone, iCloud Drive, any folder in Files, a WebDAV
server on your LAN, CSV/ZIP export. Linking a profile to **fin** (`../fin`) adds matching with bank
statement lines and server-side proofing; you sign in with the same credentials you use for fin, on fin's
own sign-in page. Unlinking keeps everything. See
[`docs/EXECUTION_PLAN.md` §8](docs/EXECUTION_PLAN.md).

## Features by milestone

| Milestone | What you get |
| --- | --- |
| **M1** Standalone MVP | Scanner, on-device OCR and extraction, classification with suggestions, checks, library and search, outbox to iCloud / Files folder / WebDAV, "Send pending slips" Shortcut, CSV/ZIP export |
| **M2** AI | On-device model pass (Apple Intelligence devices), optional Ollama or cloud endpoint with consent |
| **M3** More in, more out | Share extension (PDF/photo in), mail import, direct Dropbox / OneDrive / Google Drive where Files folders are not enough |
| **M4** fin connector | Sign in with your fin account (same email and password), reference data from fin, upload and match to transactions |
| **M5** Release | Polish, App Store decision |

## Requirements

- macOS with **Xcode 26**
- An iPhone on **iOS 18+**; Slips is an iPhone-only app (on-device AI features need iOS 26 and an Apple
  Intelligence device)
- **Apple Developer Program** membership for iCloud, background delivery and TestFlight. A free account
  can run the app on your own phone for 7 days at a time, without iCloud.
- The Etzian foundation CLI `ez` (`~/etzian/_foundation`, `npm link`) for `ez doctor`, `ez legal`,
  `ez vendor-ui` and `ez profile`. The gate itself needs only Xcode.

## Build and test

Available from phase P1:

```sh
./scripts/gate.sh        # SlipsCore tests (macOS), app build + tests on the simulator, string, hygiene and licence checks
open Slips.xcodeproj     # run on a simulator or a connected iPhone
```

## Layout

```
SlipsCore/        Swift package, no UI imports: model, storage, outbox, parser, checks, export
Slips/            app target: SwiftUI screens, scanner, OCR, destinations, App Intents
Slips/DesignSystem/  EtzianTokens.swift, managed copy from @etzianco/ui (ez-vendor.json)
Slips/Generated/  Company.swift, generated from `ez profile`
scripts/          gate.sh and its checks (strings, hygiene, licences), gen-company.sh
legal/            data-map.yaml, generated/ (privacy policy, terms, EULA, PrivacyInfo.xcprivacy)
docs/             EXECUTION_PLAN.md · adr/ · api/receipts-v1.md (copy of fin's contract)
LICENSES/         THIRD-PARTY.md
.claude/          phase plan and rules for Claude Code
i18n-exception.json · ez-vendor.json · package.json (scripts only, for `ez doctor`)
```

## Documentation

- [`docs/EXECUTION_PLAN.md`](docs/EXECUTION_PLAN.md): product, architecture, data model, outbox, foundation alignment (§10), milestones, open questions
- [`docs/adr/`](docs/adr/): SwiftUI over Tauri mobile (0001, accepted), SQLite via GRDB (0002), signing in to fin with fin's credentials (0003)
- [`docs/api/receipts-v1.md`](docs/api/receipts-v1.md): the fin contract (owned by fin, pinned here)
- [`CLAUDE.md`](CLAUDE.md): invariants and conventions for Claude Code sessions

## Privacy

Nothing leaves the phone unless you turn a destination on. There is no analytics or tracking SDK.
Secrets live in the Keychain. The repository never contains real slips, card numbers or registration
numbers; tests use synthetic text. Details: `legal/data-map.yaml` and the documents generated from it
with `ez legal gen .` (P12).

## Licence

Proprietary, © 2026 Etzian inc. Third-party notices are in `LICENSES/THIRD-PARTY.md`.
