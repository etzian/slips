---
paths:
  - "Slips/**"
  - "SlipsCore/**"
---

# Swift in Slips

The foundation's rules, written for Swift (ADR 0001 says which default each one replaces). They apply on
top of `CLAUDE.md`; `etzian:design-ui` and `etzian:ui-reviewer` review screens against the behaviour
contract in `~/etzian/_uidesign/GUIDELINES.md` and `docs/screens.md`, and against this file.

## Targets

- `SlipsCore` imports Foundation, GRDB and CryptoKit only: no UIKit, SwiftUI, VisionKit, PDFKit or
  `os.Logger` calls that format user values. Screens never import GRDB; they observe through `SlipsCore`.
- Swift 6 language mode, strict concurrency. Shared mutable state lives in an actor (`Outbox`); no
  `@unchecked Sendable` without a comment saying why it is safe.
- No `print(`. `Logger(subsystem: "com.etzian.slips", category: …)`, user-derived values `privacy: .private`.

## Design system

- Colours and spacing from `EZ.Color.*` and `EZ.Space.*` (`Slips/DesignSystem/EtzianTokens.swift`), or
  system semantic styles (`.primary`, `.secondary`, `.tint`). No `Color(red:…)`, hex, or numeric padding,
  corner radius or animation duration literal in a view.
- `Slips/DesignSystem/` is a managed copy: never edit it. Upgrade by changing `source` in `ez-vendor.json`
  and running `ez vendor-ui .`; a local need goes in the app's own view code.
- Text uses Dynamic Type styles (`.body`, `.headline`, …), never a fixed size. Amounts stay readable and
  untruncated up to AX5.
- Every view that loads data has the eight states of GUIDELINES §4: ideal, empty (new), empty
  (filtered), loading first paint (`.redacted(reason: .placeholder)`, not a centred spinner), loading
  refresh (keep the old data), partial, error, offline/denied (what still works, what is queued). Every
  control has an accessibility label; touch targets are at least 44 pt.
- Haptics and motion respect Reduce Motion.

## Strings and formats

- Every user-visible string is a String Catalog key in `en` and `fr-CA`, added in the same commit.
  `String(localized:)` / `LocalizedStringKey`, never a literal shown as is. Plurals through the catalog's
  plural variations, never concatenation.
- Product and company names are not typed in a string: the app name comes from the bundle, company facts
  from `Slips/Generated/Company.swift`.
- Money, dates, numbers: `FormatStyle` (`.currency(code:)` with the slip's currency, `Date.FormatStyle`),
  never built by hand. fr-CA gets its non-breaking spaces from the formatter.
- fr-CA wording follows `~/etzian/_foundation/i18n/glossary.fr-CA.yaml`.

## Secrets and files

- Secrets in the Keychain only, keyed by destination id; never in `UserDefaults`, the database or a log.
- Slip files use `NSFileProtectionComplete`; files the outbox reads in the background use
  `completeUntilFirstUserAuthentication` (`docs/EXECUTION_PLAN.md` §9).
