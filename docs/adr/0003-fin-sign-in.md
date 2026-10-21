# ADR 0003 — Connecting to fin with the fin account's own credentials

Status: Accepted · Date: 2026-10-20 · Project: slips

Accepted by the user on 2026-10-20; fin's contract updated the same day.

## Context

Slips lives by itself: it has **no account of its own**, and every feature works with no server. A profile
can optionally be linked to fin. The user's requirement (2026-10-20): linking uses **the same credentials
as fin**, the email and password a member already signs in to fin with, and not a separate pairing secret.

fin's draft connector (`../fin/docs/RECEIPTS_CONNECTOR.md` §3, contract `receipts-v1.md` §1) has the phone
scan a QR code from fin's web Settings and receive a device token. That token model is right: hashed at
rest, bound to one member and one workspace, scoped `reference:read receipts:write`, revocable from the
web, bearer-only routes, and it doesn't expire while the phone is offline. Only the way the phone gets it
changes.

The suite's identity decision (`_foundation/tech/suite-adr/0001-etzian-id.md`, proposed) already says
native clients sign in through the **system browser with authorization code + PKCE**, with the refresh token
in the OS keychain. fin is not on Etzian ID yet; it has its own argon2id login.

## Options

| | A. fin's login page in `ASWebAuthenticationSession`, code + PKCE | B. Native email/password form, `POST /device/login` | C. QR pairing only (current draft) |
| --- | --- | --- | --- |
| Same credentials | Yes | Yes | No: a code, not the account |
| Password seen by Slips | Never: typed on fin's own page | Yes, in transit through the app | Never |
| MFA, passkeys, reset, lockout later | Inherited from fin's page | Each needs app work | n/a |
| Move to Etzian ID | Same flow, other issuer (OIDC-shaped) | Rewrite | Rewrite |
| AutoFill | Safari's saved fin password works | Needs associated domains | n/a |
| Dev | Two endpoints in fin (`authorize`, `token`), one sheet in Slips | One endpoint, one form | Already drafted |
| Law 25 / data | Token only, Keychain | Password handled by one more client | Token only |

## Decision

**A.** In a profile set to fin, "Sign in with fin" opens fin's own sign-in page in
`ASWebAuthenticationSession` (`prefersEphemeralWebBrowserSession = false`, so a fin session already open in
Safari carries over). The member signs in with their fin email and password and picks the workspace that
this Slips profile maps to. fin redirects to `com.etzian.slips:/fin/callback` with a one-time code; Slips
exchanges it, with its PKCE verifier, for the **same device token** the connector already defines. The
token goes to the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so it is not in backups
and background uploads can read it). The password never reaches Slips.

- **One profile = one fin workspace.** A member with several workspaces signs in once per profile;
  switching is a new sign-in (Etzian ID's `wid` model).
- **Revocation and expiry** are unchanged: fin's Settings → Devices lists and revokes Slips sign-ins;
  `401 device.revoked` puts the fin destination in `needs_auth` ("Sign in to fin again"), and the outbox
  keeps the slips queued. No retry loop on a 401.
- **Signing out** in Slips calls fin's revoke endpoint when reachable, deletes the Keychain item, and
  unlinks the profile as plan §8 describes. Nothing local is deleted.
- **QR** may still fill in the server address, so nobody types a LAN URL; it no longer carries a secret.

## Consequences

- **fin owns the contract.** `receipts-v1.md` §1 (fin, 2026-10-20) replaces QR pairing with the
  `GET /device/authorize` page, `POST /api/devices/authorize` (session, recent authentication) and
  `POST /api/v1/device/token` (code + verifier → device token, rate class `auth`), plus
  `POST /api/v1/device/revoke` for signing out. Client `slips`, redirect URI exactly
  `com.etzian.slips:/fin/callback`. A password change or reset in fin revokes the member's devices.
  fin records the server side as its own ADR 0003 in its R2 slice. Slips' pinned copy
  `docs/api/receipts-v1.md` matches that version.
- **HTTPS is required** for the sign-in page. A LAN fin needs a certificate the iPhone trusts (a local CA
  profile or a real name). Plan §12.
- When fin moves to **Etzian ID**, Slips points the same flow at Etzian ID's `/authorize` with
  `aud=fin`; fin then verifies Etzian ID tokens. Slips changes its issuer URL and token refresh, and the
  rest stays. That is a new ADR then.
- Slips stays account-free: nothing in M1–M3 asks for a sign-in.
