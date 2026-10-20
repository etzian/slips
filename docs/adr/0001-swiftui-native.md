# ADR 0001 — SwiftUI instead of Tauri 2 mobile

Status: Accepted · Date: 2026-10-20 · Project: slips

Accepted by the user on 2026-10-20: Slips is an iPhone-only app, so it is written in Swift.

## Context

The radar's default for phone apps is Tauri 2 mobile (D7, ring Trial), with SwiftUI (ring Assess) "only
for phone-first apps that need deep platform integration, via ADR". Slips runs on the iPhone only, and
most of what it does is a platform API:

- `VNDocumentCameraViewController` (VisionKit): edge detection, auto-capture, perspective correction
- `VNRecognizeTextRequest` (Vision): on-device OCR in French and English
- PDFKit: multi-page PDF with an invisible text layer
- `NWPathMonitor`, background `URLSession`, `BGTaskScheduler`: the outbox
- App Intents + Shortcuts ("when I join home Wi-Fi, send pending slips")
- iCloud container, security-scoped bookmarks to a Files folder, the share sheet
- Foundation Models (on-device LLM, iOS 26, Apple Intelligence devices) for M2
- Keychain, Face ID

Under Tauri, every item above becomes a Swift plugin plus an IPC bridge, so there would be Swift code
anyway, written twice over.

## Options

| | Tauri 2 mobile (radar default) | SwiftUI native |
| --- | --- | --- |
| Dev | Swift plugins for scanner, OCR, PDF, outbox, intents; Rust + Svelte + Swift | One language, one target, Apple samples apply directly |
| UX | Webview scrolling, keyboard and camera hand-offs are the known weak spots | Native scanner, pickers, haptics, Dynamic Type, VoiceOver for free |
| Tok | Three layers and a bridge per feature | One layer; `SlipsCore` package keeps logic small and testable |
| Ops | Same Apple account and signing either way | Same |
| Lic | Tauri MPL-2.0 crates need exceptions (`option-ext`) | Apple SDKs only; GRDB (MIT, ADR 0002) |
| Law 25 / data | Same (on device) | Same (on device) |

## Decision

SwiftUI, Swift 6, iOS 18 minimum, **iPhone only** (`TARGETED_DEVICE_FAMILY = 1`; an iPad runs it in
iPhone compatibility mode, with no iPad-specific work). Foundation Models features are gated at runtime
on iOS 26 + availability. The foundation's rules still apply; where they assume Rust or the web, this is
how Slips meets them:

| Foundation layer | Default | Slips |
| --- | --- | --- |
| Core / shell split (`archetypes/standalone.md`) | Rust core crate with no `tauri` dependency | `SlipsCore` Swift package with no UIKit, SwiftUI or VisionKit import |
| Local data | SQLite via rusqlite, WAL | SQLite via GRDB, WAL (ADR 0002) |
| i18n (`i18n/README.md`) | Fluent, `locales/{fr-CA,en}/*.ftl` | **String Catalogs** (`.xcstrings`), development language `en`, plus `fr-CA`. Declared in `i18n-exception.json` (system `xcstrings`, this ADR, check `npm run i18n:check`). Same rules otherwise: canonical codes, fr-CA is a release blocker, glossary `_foundation/i18n/glossary.fr-CA.yaml`, `etzian:translator` then `etzian:i18n-guardian` |
| Formatting | `Intl` | `FormatStyle` with the slip's currency and the user's locale |
| Design system (`@etzianco/ui`) | npm package | The package's Swift export, `src/platforms/swift/EtzianTokens.swift` (`EZ.Color.*`, `EZ.Space.*`), as a **managed copy** in `Slips/DesignSystem/` described by `ez-vendor.json`; `ez vendor-ui .` copies and stamps it, `ez doctor` fails on a hand edit. Views use `EZ` tokens and system components; no colour, spacing or radius literal in a view |
| Typography | Public Sans / Newsreader, self-hosted | **SF (system font) with Dynamic Type.** The brand comes through the neutrals, the accent and the *by Etzian* mark, not a custom face; a bundled font would fight Dynamic Type and VoiceOver |
| Behaviour contract (GUIDELINES, `docs/screens.md`) | Svelte components | Same states, latency budgets and mandatory screens, built from SwiftUI (`Form`, `List`, `ContentUnavailableView`, `.alert`) per `docs/EXECUTION_PLAN.md` §10 |
| Licence gate | `ez licence-audit` (Rust, JS, Python) | `scripts/check-licences.sh` in the gate: every package in `Package.resolved` must be listed in `LICENSES/THIRD-PARTY.md` with an SPDX id allowed by `_foundation/tech/licences/policy.yaml` |
| Project file | Cargo workspace | Xcode folder-synchronised groups (Xcode 16+), so adding a file never edits `project.pbxproj`. No XcodeGen or Tuist. Version numbers in `Slips/Config/Version.xcconfig` |

## Consequences

- No code sharing with fin's web UI. The shared surface is the HTTP contract (`fin/docs/api/receipts-v1.md`).
- A Mac with Xcode is required for every gate. Gates run on the iOS Simulator; the scanner and OCR on a
  real device are checked by hand in the phases that say so.
- Foundation tools see only part of this project. `ez doctor` finds bundle identifiers in
  `tauri.conf.json` only, so it does not check `com.etzian.slips`; `ez licence-audit` does not read
  SwiftPM. `i18n-exception.json` requires an `npm run` check, so the repo has a `package.json` with
  scripts only and no dependencies. Each is a candidate for the foundation (P9) rather than a local fork.
- `etzian:design-ui` and `etzian:ui-reviewer` are written for `@etzianco/ui` on the web; for Slips they
  review against the behaviour contract and `.claude/rules/swift.md`, not the Svelte components.
- If an Android or desktop version is ever wanted, `SlipsCore`'s logic is the part to port; that is a new ADR.
- For the next radar review: SwiftUI moves from Assess to Trial, with Slips as the project that reports back.
