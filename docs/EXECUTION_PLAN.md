# Slips — Execution Plan

**Scan a slip, say what it is, and it lands where it belongs.** iPhone, SwiftUI, local-first.
fin (`~/etzian/fin`) is an optional connector.

| Decision | Choice |
| --- | --- |
| Product | **Slips** (working name), bundle id `com.etzian.slips` (same prefix as `com.etzian.clip`), repo `~/etzian/slips` |
| Platform | iPhone, iOS 18+. iPad runs it unmodified; no iPad-specific work in v1 |
| UI | SwiftUI, Swift 6 (ADR 0001) |
| Storage | SQLite through GRDB, WAL (ADR 0002); PDFs on disk |
| Locales | `en-CA`, `fr-CA` (String Catalogs) |
| Distribution | Personal device + TestFlight first; App Store is a later decision |
| fin | Optional connector, contract owned by fin: `../fin/docs/api/receipts-v1.md` |

---

## 1. Product

1. **Capture.** Scan one or more pages with the system document scanner, or import a PDF or photo
   (share extension in M3). The PDF and its record are saved before anything else happens.
2. **Extract.** On-device OCR, then a parser pulls merchant, date, subtotal, GST, QST (or HST), tip,
   total, currency, card last four, and the supplier's GST/QST registration numbers.
3. **Classify.** One screen: profile → kind (personal / family / enterprise) → business → sub-category →
   payment method. Every picker is pre-filled from the merchant's history and the payment method's
   defaults; the user confirms or changes.
4. **Proof.** Checks run while the user is still holding the paper (§5).
5. **Deliver.** The outbox sends the PDF (and a JSON sidecar where the destination keeps one) to each
   destination the profile turned on, now or when it becomes reachable.
6. **Find and export.** Library with search and filters; CSV/JSON export and a ZIP of PDFs per period
   and business.

## 2. Architecture

```
┌──────────── Slips (app target) ─────────────┐
│ SwiftUI screens · VisionKit scanner         │
│ Vision OCR · PDFKit · App Intents           │
│ Destinations (iCloud, Folder, WebDAV, fin…) │
└───────────────┬─────────────────────────────┘
                │ calls (never the reverse)
┌───────────────▼─────────────────────────────┐
│ SlipsCore (Swift package, no UI imports)    │
│ Models · GRDB storage + migrations          │
│ Parser · Checks · Suggestions · Naming      │
│ Outbox scheduler (Destination protocol)     │
│ Export (CSV, JSON, ZIP manifest)            │
└─────────────────────────────────────────────┘
```

`SlipsCore` defines `protocol Destination { func probe() async -> Reachability; func deliver(_:) async
throws -> RemoteRef; func exists(_:) async throws -> Bool }`. Concrete destinations that need iOS-only
APIs live in the app target; the scheduler and its tests only see the protocol (a `FakeDestination` in
tests).

## 3. Data model (SQLite)

Amounts are **integer minor units** (cents) with an ISO currency. Ids are UUIDs generated on the device.
Reference tables carry `remote_id` (null until linked to fin) and `archived_at` (never hard-deleted while
a slip points at them).

| Table | Columns (main) |
| --- | --- |
| `profiles` | id, name, mode `local`/`fin`, fin_base_url, fin_workspace_id, fin_device_id, created_at |
| `enterprises` | id, profile_id, name, remote_id, archived_at |
| `subcategories` | id, profile_id, kind `personal`/`family`/`enterprise`/`any`, name_key, custom_name, sort_order, remote_id, archived_at |
| `payment_methods` | id, profile_id, name, type `credit_card`/`debit`/`chequing`/`cash`/`other`, last4, currency, default_kind, default_enterprise_id, remote_id, archived_at |
| `slips` | id, profile_id, status `draft`/`ready`/`archived`, captured_at, pdf_path, pdf_sha256, page_count, ocr_text, extracted (JSON, raw parser output with confidences), merchant, txn_date, currency, subtotal, gst, qst, hst, tip, total, supplier_gst_no, supplier_qst_no, kind, enterprise_id, subcategory_id, payment_method_id, notes, checks (JSON), updated_at |
| `merchant_memory` | profile_id, merchant_norm, kind, enterprise_id, subcategory_id, payment_method_id, uses, last_used_at |
| `destinations` | id, profile_id, type `library`/`icloud`/`folder`/`webdav`/`fin`/`dropbox`/`onedrive`/`gdrive`, name, config (JSON, no secret), naming_rule, wifi_only, enabled |
| `deliveries` | slip_id, destination_id, status `pending`/`in_flight`/`done`/`failed`/`needs_auth`, attempts, next_attempt_at, last_error_code, remote_ref, delivered_sha256, updated_at |

**The model mirrors fin on purpose.** fin's transactions carry `category` (personal / family /
enterprise), `enterprise_id` and `subcategory_id`; its accounts carry `masked_number` (last four). Slips
uses the same three kinds and seeds the **same sub-category keys** as fin (`personal.groceries`,
`enterprise.software`, `any.transfer`, …, from `fin/packages/shared/src/categories.ts`), so linking a
local profile to fin maps by key without asking.

Secrets (WebDAV password, OAuth refresh tokens, fin device token) are Keychain items keyed by
destination id; `destinations.config` never holds one.

## 4. Capture and extraction

- Scanner: `VNDocumentCameraViewController`; pages are JPEG-compressed (quality ≈ 0.7, long edge
  ≈ 2000 px) before the PDF is built, so a two-page slip is a few hundred kB.
- PDF: PDFKit, one page per scan page, invisible text layer from OCR so the file is searchable anywhere.
- OCR: `VNRecognizeTextRequest`, `.accurate`, languages `fr-CA`, `en-CA`, language correction off for
  numbers. Observations keep their bounding boxes so the parser can use line order and right-aligned
  amounts.
- Parser (`SlipsCore`, pure): input is OCR lines with boxes; output is fields with a confidence and the
  source line. Rules for: dates in Québec formats (`2026-10-20`, `20/10/2026`, `20 oct. 2026`, `10/20/26`
  with disambiguation), amounts with `,` or `.` decimals, the TOTAL / SOUS-TOTAL / TPS / TVQ / TVH /
  POURBOIRE / GST / QST / HST / TIP labels, card masks (`****1234`, `XXXXXXXXXXXX1234`), GST numbers
  (`123456789 RT0001`) and QST numbers (`1234567890 TQ0001`).
- Fixtures: synthetic OCR transcripts written for the tests, never real slips.

## 5. Checks ("AI supervision", rule-based in M1)

| Check | Severity |
| --- | --- |
| subtotal + taxes + tip ≠ total (± 0.02) | warning |
| GST ≠ 5 % or QST ≠ 9.975 % of the taxable amount (± rounding), when both present | info |
| date in the future, or older than the profile's limit (default 2 years) | warning |
| total missing or unreadable | blocking (the user must type it) |
| card last four found but no payment method has it | info (offers to create one) |
| kind = enterprise and GST/QST registration numbers absent | warning: needed to claim input tax credits / refunds above the thresholds (confirm thresholds with CRA / Revenu Québec or the accountant) |
| same merchant, date and total as an existing slip | warning (likely duplicate) |

M2 adds a model pass (§7) on top; these rules stay, because they are free, offline and explainable.

## 6. Outbox and destinations

One row in `deliveries` per (slip, destination). One scheduler drains rows that are due and whose
destination reports reachable. Triggers: app foreground, `NWPathMonitor` changes, a `BGAppRefreshTask`,
the **App Intent "Send pending slips"** (for a Shortcuts automation on joining home Wi-Fi), and the
completion of a previous delivery.

- Backoff: 30 s, 2 min, 10 min, 1 h, then every 6 h; `failed` after 20 attempts, retryable by hand.
- `needs_auth`: a 401 or a refresh failure stops retries for that destination and shows a banner.
- Idempotency: before uploading, `exists(slip)` checks the remote (same path and size, or a stored
  hash); fin uses the client UUID (`PUT`), so a replay is a no-op.
- A failure at one destination never blocks another.
- `wifi_only` and Low Data Mode are respected per destination.
- Uploads over HTTP use a background `URLSession` from a file on disk, so they finish if the app is
  suspended.

Naming rule (per destination): tokens `{year} {month} {day} {date} {kind} {business} {subcategory}
{merchant} {total} {currency} {payment} {id8}`; default
`{business}/{year}/{date}_{merchant}_{total}.pdf`. Names are sanitised for every target (no `/ : \ * ? "
< > |`, NFC, ≤ 120 chars) and get `_{id8}` when they collide.

| Destination | Milestone | How |
| --- | --- | --- |
| Library (on device) | M1 | Always on; it *is* the source of truth |
| iCloud Drive (Slips folder) | M1 | Ubiquity container; done once written locally, iOS syncs |
| Folder in Files | M1 | User picks a folder once; security-scoped bookmark; works for iCloud Drive, On My iPhone, an SMB share mounted in Files, and File Provider apps (Dropbox, OneDrive, Google Drive) **when the provider keeps the bookmark valid**: test each provider on a device and document what holds |
| WebDAV / LAN server | M1 | HTTPS `PUT` + `PROPFIND`; probe on a health URL; works with a NAS (Nextcloud, a WebDAV container, Synology) |
| Share sheet | M1 | Manual, one slip or a selection |
| fin | M4 | `../fin/docs/api/receipts-v1.md`; needs fin's connector milestone first |
| Dropbox, OneDrive, Google Drive (API) | M3 | Only if the Files-folder route proves unreliable for a provider; each one is an ADR (SDK licence, OAuth app, scopes: Drive `drive.file`) |

## 7. AI (M2)

- **On device:** Foundation Models (iOS 26, Apple Intelligence devices, checked at runtime) with guided
  generation into a `@Generable` struct: merchant, date, amounts, taxes, suggested sub-category key. Input
  is the OCR text, not the image. Its output is compared with the parser's; disagreements become checks.
- **Optional endpoint:** an Ollama URL on the LAN or a cloud key, per profile, with an explicit "what is
  sent" screen and consent like fin's (§2.4 of fin's plan). Off by default.
- **Through fin (M4):** the slip goes to fin, fin's LLM feature re-extracts and proofs, and the phone
  shows the verdict.

## 8. fin connector (client side, M4)

See `../fin/docs/RECEIPTS_CONNECTOR.md` for the server side. In Slips:

- **Link:** a profile in mode `fin` is paired by scanning the QR code fin shows in Settings → Devices;
  the app stores the device token in the Keychain.
- **Reference data:** pulled from fin (`GET /api/v1/device/reference`), read-only in the app, cached for
  offline use.
- **Linking an existing local profile:** a one-time mapping screen; sub-categories map by `name_key`,
  payment methods by last four + type, businesses by name; the rest is created in fin (if the role
  allows) or left "to classify". Then the backlog is queued to fin like new slips.
- **Unlinking:** mirrored data becomes local and editable again. Nothing is deleted.
- **Status back:** the phone polls `GET /api/v1/device/receipts?since=` to show "matched", "awaiting
  statement", "needs review".

## 9. Privacy

- Everything stays on the device unless a destination is turned on. No analytics SDK, no ad id.
- `PrivacyInfo.xcprivacy` declares the required-reason APIs used (file timestamps, UserDefaults).
- `docs/DATA_MAP.md`: what is stored, where, and what each destination receives.
- Optional app lock with Face ID; the PDF folder uses `NSFileProtectionComplete` (`completeUntilFirstUserAuthentication`
  for the outbox files, so background uploads can read them).
- Logs: `os.Logger`, user-derived values `.private`.

## 10. Milestones

| # | Milestone | Releases as |
| --- | --- | --- |
| M1 | Standalone MVP: capture, extraction, classification, checks, library, outbox, iCloud / Folder / WebDAV, export | v0.1.0 (TestFlight) |
| M2 | AI: Foundation Models pass, optional Ollama/cloud endpoint, suggestions from history improved | v0.2.0 |
| M3 | Import and more destinations: share extension (PDF/photo in), mail import, direct cloud APIs where needed | v0.3.0 |
| M4 | fin connector (needs fin's receipts milestone) | v0.4.0 |
| M5 | Release polish, App Store decision | v1.0.0 |

## 11. Open questions

1. Final product name ("Slips" is the working name); the bundle id follows it.
2. Apple Developer Program membership: needed for TestFlight, iCloud container and background tasks on a
   device beyond 7-day installs.
3. Which LAN server is the WebDAV target (NAS container, Nextcloud, fin later)? M1 tests against a local
   WebDAV container only.
4. Keep emailIngestion for bills that arrive by email, or fold mail import into Slips M3 / fin?
5. Retention: should archived slips' PDFs ever be purged on the phone once delivered to N destinations?
   (Tax evidence: keep six years in Québec/Canada; the phone does not have to be where it is kept.)
