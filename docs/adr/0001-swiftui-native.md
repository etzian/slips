# ADR 0001 — SwiftUI instead of Tauri 2 mobile

Status: Proposed · Date: 2026-10-20 · Project: slips

## Context

The radar's default for phone apps is Tauri 2 mobile (D7), with SwiftUI "only for phone-first apps that
need deep platform integration, via ADR". Slips is phone-only, and most of what it does is a platform API:

- `VNDocumentCameraViewController` (VisionKit): edge detection, auto-capture, perspective correction
- `VNRecognizeTextRequest` (Vision): on-device OCR in fr-CA and en-CA
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
| Lic | Tauri MPL-2.0 crates need exceptions | Apple SDKs only; GRDB (MIT, ADR 0002) |
| Law 25 / data | Same (on device) | Same (on device) |

## Decision

SwiftUI, iOS 18 minimum (Foundation Models features gated at runtime on iOS 26 + availability).
Deviations that follow from it, accepted with this ADR:

- **i18n:** String Catalogs (`.xcstrings`) instead of Fluent. Locales `en-CA`, `fr-CA`.
- **Design system:** `@etzianco/ui` has no Swift export yet (radar P4). Until it does, the app uses system
  components with semantic colours; when tokens export to Swift, a `Theme` file maps them, no redefinition.
- **Project file:** Xcode 16 folder-synchronised groups, so adding a file never edits `project.pbxproj`.
  No XcodeGen or Tuist.

## Consequences

- No code sharing with fin's web UI. The shared surface is the HTTP contract (`fin/docs/api/receipts-v1.md`).
- A Mac with Xcode is required for every gate. Gates run on the iOS Simulator; the scanner and OCR on a
  real device are checked by hand in the phases that say so.
- If an Android or desktop version is ever wanted, `SlipsCore`'s logic is the part to port; that is a new ADR.
