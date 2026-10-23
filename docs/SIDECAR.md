# Slip sidecar (`<name>.json`)

Destinations that keep a sidecar (Destinations › a destination › "JSON sidecar") write it next to the
PDF, with the same name and `.json`. It carries what the slip says and how the user filed it, so a
folder of slips can be read by a script, a spreadsheet import or fin without opening each PDF.

Written by `SlipsCore/Sources/SlipsCore/Delivery/Sidecar.swift`. UTF-8, pretty-printed, keys sorted.
It is rewritten when the slip is edited after delivery; the PDF never changes.

| Key | Type | Meaning |
| --- | --- | --- |
| `schema` | string | `com.etzian.slips.sidecar/1`. A new major number means a breaking change |
| `id` | string | The slip's client UUID (lowercase). The same at every destination; the idempotency key |
| `pdf_sha256` | string | SHA-256 of the PDF next to it, lowercase hex |
| `page_count` | integer | Pages in the PDF |
| `captured_at` | string | ISO 8601 instant of the scan (UTC) |
| `merchant` | string? | As read or corrected |
| `date` | string? | Transaction day, `YYYY-MM-DD` |
| `currency` | string | ISO 4217 (`CAD`, `USD`…) |
| `subtotal`, `gst`, `qst`, `hst`, `tip`, `total` | integer? | Minor units (cents) in `currency` |
| `supplier_gst_no`, `supplier_qst_no` | string? | `123456789 RT0001`, `1234567890 TQ0001` |
| `kind` | string? | `personal`, `family` or `enterprise` (fin's categories) |
| `business` | string? | Business name, for `enterprise` |
| `subcategory_key` | string? | fin's key (`enterprise.software`) for a seeded sub-category |
| `subcategory_name` | string? | The user's own name, when they renamed or created it |
| `payment_method` | string? | Payment method name (never a card number; the last four is not written) |
| `notes` | string? | The user's notes |
| `checks` | string[] | Codes of the open checks (`sum_mismatch`, `registration_missing`…) |

Absent values are omitted. Readers ignore keys they do not know.
