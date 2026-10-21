# ADR 0002 — Local storage: SQLite through GRDB

Status: Accepted · Date: 2026-10-20 · Project: slips

The radar's local-data default is SQLite via rusqlite; that is a Rust crate, so with SwiftUI (ADR 0001)
the choice is which Swift layer sits on SQLite.

## Context

Slips is local-first. The database holds profiles, reference data (businesses, categories, payment
methods), slips with their extracted and classified fields, and the outbox (`deliveries`: one row per
slip × destination with status, attempts, next retry). The outbox needs plain, testable queries ("due
deliveries for reachable destinations, oldest first") and explicit, versioned migrations, because a
schema mistake on a phone cannot be fixed by hand.

## Options

| | SwiftData (Apple) | GRDB.swift | Core Data |
| --- | --- | --- | --- |
| Dev | Least code for CRUD; migrations and predicates get awkward fast | SQL you can read, `DatabaseMigrator`, value-type records | Mature, verbose |
| Tok | Hidden schema, macro magic | Schema in one migrations file | Model editor file |
| Tests | Needs the app host or an in-memory container | In-memory `DatabaseQueue` in `swift test` on macOS | Needs a stack |
| Lic | Apple SDK | **MIT** | Apple SDK |
| Fit with the radar ("ORMs: Hold", SQL stays readable) | No | Yes | No |

## Decision

GRDB.swift (MIT), pinned by exact version in `SlipsCore/Package.swift`. One `DatabasePool` in WAL mode
under Application Support, excluded from nothing (it is included in the device backup on purpose).
Migrations are append-only, named `v1_…`, `v2_…`; never edit one that has shipped.

## Consequences

- One third-party package in the app. It is recorded in `LICENSES/THIRD-PARTY.md` (name, version, SPDX
  `MIT`, licence text) from P1, and `scripts/check-licences.sh` fails the gate when `Package.resolved`
  holds a package that file does not list with a licence allowed by `_foundation/tech/licences/policy.yaml`.
- SwiftUI observation goes through GRDB's `ValueObservation`, wrapped in `SlipsCore` so screens never
  import GRDB directly.
