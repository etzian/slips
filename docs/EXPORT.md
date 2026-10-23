# Export columns

Library › Export writes the slips that match the current filters and period as CSV, JSON, or a ZIP of
the PDFs plus the CSV. Built by `SlipsCore/Sources/SlipsCore/Export/Exporter.swift`; the file leaves
the phone only through the share sheet, where the user picks the target.

CSV: RFC 4180, UTF-8 with a byte-order mark, CRLF line ends, one header row. A field is quoted when it
holds a comma, a quote, a line break or edge spaces; a text field starting with `= + - @` gets a
leading `'` so a spreadsheet never runs it as a formula. JSON: an array of objects with the same keys.

| Column | Example | Meaning |
| --- | --- | --- |
| `id` | `3f2c…` | The slip's client UUID, the same as in sidecars and at every destination |
| `date` | `2026-10-20` | Transaction day, else the capture day (UTC) |
| `merchant` | `Quincaillerie Fictive` | As read or corrected |
| `currency` | `CAD` | ISO 4217 |
| `subtotal`, `gst`, `qst`, `hst`, `tip`, `total` | `43.67` | Decimal with a point, no grouping; empty when absent |
| `kind` | `enterprise` | `personal`, `family` or `enterprise` |
| `business` | `Studio Fictif` | For `enterprise` |
| `subcategory_key` | `enterprise.supplies` | fin's key, empty for a custom sub-category |
| `subcategory` | `Supplies` | The name shown in the app (custom name, or the key translated) |
| `payment_method` | `Visa pro` | Payment method name |
| `supplier_gst_no`, `supplier_qst_no` | `123456789 RT0001` | Supplier registration numbers |
| `notes` | | The user's notes |
| `status` | `ready` | `draft`, `ready` or `archived` |
| `checks` | `sum_mismatch tax_rate` | Codes of open checks, space-separated |
| `captured_at` | `2026-10-20T18:32:05Z` | Scan instant, ISO 8601 UTC |
| `pdf_file` | `Studio Fictif/2026/2026-10-20_Quincaillerie Fictive_43.67.pdf` | The PDF's path inside the ZIP (default naming rule; `_{id8}` on a clash) |

ZIP: stored entries (PDFs are already compressed), UTF-8 names, every PDF at its `pdf_file` path and
`slips.csv` at the root. A slip whose PDF is missing on the phone appears in the CSV only.
