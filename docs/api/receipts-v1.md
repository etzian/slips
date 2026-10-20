# Receipts API v1 — contract between fin and Slips

Status: draft, 2026-10-20. Owned by fin; Slips keeps a copy at `docs/api/receipts-v1.md` and records the
version it targets. Server design: `docs/RECEIPTS_CONNECTOR.md`.

Conventions: JSON, UTF-8, `camelCase`. Amounts are **decimal strings** with two places (`"42.17"`),
never floats. Dates `YYYY-MM-DD`; timestamps RFC 3339 UTC. Errors are `{ "error": "<code>" }` with the
HTTP status below. Breaking changes go to `/api/v2/device`; additive fields may appear in v1 and clients
ignore unknown fields.

## 1. Pairing

### `POST /api/devices/pairing` (web session, recent authentication, CSRF)

Starts a pairing. Response `201`:

```json
{ "code": "K7Q2-9XMF-4TBD", "expiresAt": "2026-10-20T23:40:00Z",
  "qr": "fin-pair:v1?u=https%3A%2F%2Ffin.lan&c=K7Q2-9XMF-4TBD" }
```

### `POST /api/v1/device/pair` (public, strict rate class)

Request: `{ "code": "K7Q2-9XMF-4TBD", "deviceName": "iPhone d'Edy", "client": "slips/0.4.0 (iOS 26.1)" }`

Response `201`:

```json
{ "deviceId": "uuid", "token": "fdt_…", "workspace": { "id": "uuid", "name": "Germain" },
  "user": { "id": "uuid", "displayName": "Edy" }, "scopes": ["reference:read", "receipts:write"] }
```

Errors: `400 pairing.invalid`, `410 pairing.expired`, `429 rate_limited`.

### `GET /api/devices` · `PATCH /api/devices/:id` · `DELETE /api/devices/:id` (web session)

List, rename, revoke. A revoked token gets `401 device.revoked` on its next call.

## 2. Device routes

Every route below: `Authorization: Bearer fdt_…`; cookies ignored. `401 device.unauthorized` /
`device.revoked`, `403 permission.denied`.

### `GET /api/v1/device/reference`

What the phone needs to classify offline, filtered by the member's visibility. `ETag` and
`If-None-Match` supported (`304`).

```json
{
  "workspace": { "id": "uuid", "name": "Germain", "currency": "CAD" },
  "categories": ["personal", "family", "enterprise"],
  "enterprises": [ { "id": "uuid", "name": "Germain Architecte", "archived": false } ],
  "subcategories": [
    { "id": "uuid", "category": "enterprise", "nameKey": "enterprise.software", "customName": null,
      "sortOrder": 40, "archived": false }
  ],
  "accounts": [
    { "id": "uuid", "name": "Visa Affaires", "type": "credit_card", "currency": "CAD",
      "maskedNumber": "1234", "defaultCategory": "enterprise", "defaultEnterpriseId": "uuid",
      "canWrite": true, "archived": false }
  ],
  "permissions": { "receipts": "write" }
}
```

### `PUT /api/v1/device/receipts/:id`

Idempotent upload; `:id` is the client UUID. `multipart/form-data` with two parts:

- `meta` (`application/json`), the entry below
- `file` (`application/pdf`); header `X-Content-SHA256: <hex>` on the request must match the file

```json
{
  "schema": "receipt.v1",
  "clientUpdatedAt": "2026-10-20T22:51:03Z",
  "txnDate": "2026-10-20",
  "merchant": "Quincaillerie Exemple",
  "currency": "CAD",
  "amounts": { "subtotal": "36.68", "gst": "1.83", "qst": "3.66", "hst": null, "tip": null, "total": "42.17" },
  "supplierTaxNumbers": { "gst": "100000000 RT0001", "qst": "1000000000 TQ0001" },
  "classification": { "category": "enterprise", "enterpriseId": "uuid",
                      "subcategoryId": "uuid", "accountId": "uuid" },
  "cardLast4": "1234",
  "notes": null,
  "extracted": { "total": { "value": "42.17", "confidence": 0.97 }, "…": {} },
  "ocrText": "…",
  "pageCount": 1
}
```

Responses:
- `201` created, `200` same id and same hash already stored (replay), body = the receipt status (§2.4).
- Same id with a **different** `clientUpdatedAt` and the same file: metadata update, `200`.
- Same id with a different file hash: `409 receipt.file_mismatch` (the PDF is immutable).
- `422` with `receipt.invalid_classification` (e.g. `enterpriseId` with category ≠ enterprise),
  `receipt.unknown_reference` (an id the member cannot see: the receipt is **kept** with that field
  cleared and status `needs_review`, response `201` with `warnings`), `receipt.file_invalid`,
  `receipt.file_too_large`.

### `GET /api/v1/device/receipts?since=<RFC 3339>`

Status feed for receipts this device or this member uploaded, changed after `since`. Paginated with
`cursor`.

```json
{ "items": [ { "id": "uuid", "status": "matched", "transactionId": "uuid",
               "proof": { "discrepancies": [] }, "updatedAt": "2026-10-23T11:02:00Z" } ],
  "cursor": null }
```

Status values: `awaiting_statement`, `matched`, `needs_review`, `rejected`, `archived`.

### `GET /api/v1/device/health`

Unauthenticated `204`; used by the phone's reachability probe. Returns no version or host detail.

## 3. Versioning

The phone sends `X-Client: slips/<version>`. The server may answer `426 client.upgrade_required` if a
version is known bad. `schema` in `meta` lets v1 accept `receipt.v1` and later `receipt.v1.1` side by
side.
