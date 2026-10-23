# Legal and privacy assessment — Slips M1 (v0.1.0)

2026-10-23. Prepared from the code and `legal/data-map.yaml` for the lawyer review recorded in
`_foundation/legal/review.yaml`. **Not legal advice**: it lists what the law and the App Store appear to
require, what the app does, and the questions a lawyer has to answer. Laws in scope: Québec Law 25,
PIPEDA, Charter of the French Language (Bill 96), Québec Consumer Protection Act; App Store rules for
distribution.

## 1. Etzian's role (decides everything below)

Slips has no account, no server, no analytics, no crash reporter and no third-party SDK that sends data
(GRDB, the only dependency, is a local database). A slip leaves the phone only to destinations the user
turns on, and every one is the user's own: their iCloud Drive, a folder they pick in Files, their WebDAV
server. Etzian receives nothing.

**Question for the lawyer:** is Etzian then a processor at all, or only the publisher of a tool
(`docs/EXECUTION_PLAN.md` §12 Q6)? If only a tool:

- the privacy policy can be short: what the app keeps on the phone, what each destination receives,
  that Etzian receives nothing, how to erase;
- the App Store privacy label is **Data Not Collected**;
- an EFVP (privacy impact assessment) is still advisable for the iCloud destination: data goes to
  Apple, outside Québec, even though it is the user's account and choice.

## 2. Documents

| Document | Required | Status | Notes |
| --- | --- | --- | --- |
| Privacy policy, fr-CA first, then en | Law 25, Bill 96, App Store | Not generated | Privacy officer named (`Slips/Generated/Company.swift`); purposes, retention, recipients per destination, rights, erasure — all in the data map |
| Terms of use | Advisable | Not generated | Free app; disclaimers on tax use (the app does not give tax advice) |
| EULA | App Store | Not generated | Apple's standard EULA may suffice; lawyer to decide |
| Retention schedule | Law 25 | Not generated | Data stays on the phone until the user deletes it; tax evidence is commonly kept six years (the phone need not be where it is kept) |
| EFVP (iCloud transfer) | Law 25, before release | Not done | Apple listed in `_foundation/legal/vendors.yaml` (to create) |
| `PrivacyInfo.xcprivacy` | App Store | Not generated | See §4 |
| App Store privacy label | App Store | Not filled | Data Not Collected, if §1 holds |
| Confidentiality-incident register | Law 25 | Company-level | One register for Etzian, not per app |

All of these are **generated** by `ez legal gen .` from `legal/data-map.yaml` and never written by
hand. The foundation's legal layer (schema, vendors, templates, `ez legal gen` / `check`) does not exist
yet; until it does, the data map is the brief a lawyer can draft from.

## 3. What the app already does

| Requirement | In the app |
| --- | --- |
| Privacy by default (Law 25) | Every destination except the on-phone library starts off; the first-run screen says so |
| Transparency | Settings › Privacy: what is stored where, what each destination receives, privacy officer |
| No tracking | No analytics, no ad identifier, no crash SDK, no account |
| Security | Slip PDFs with complete file protection; passwords in the Keychain, this device only, never synced; user data marked private in logs |
| Minimisation | Only the last four digits of a card are stored; never written to sidecars or exports |
| Automated processing | OCR, checks and suggestions run on the phone; the user confirms every field; no decision with legal effect. Disclosed on the Privacy screen |
| Erasure | Settings › Danger zone › Erase all data on this iPhone: rows, files, Keychain items, preferences; says delivered copies are not touched |
| Portability | CSV / JSON / ZIP export (`docs/EXPORT.md`) |
| French (Bill 96) | Full fr-CA interface; documents must be French first |

## 4. Privacy manifest inputs

- `NSPrivacyTracking`: false; no tracking domains.
- `NSPrivacyCollectedDataTypes`: none (if §1 holds).
- Required-reason APIs used by the app:
  - **UserDefaults** — `CA92.1` (app's own preferences: theme, first run, active profile, lock).
  - **File timestamp APIs** — `3B52.1` (`FileManager.attributesOfItem` on files in a folder the user
    picked, to see whether a slip is already there) and `C617.1` (files in the app's container).
- No disk-space, boot-time or keyboard APIs.

To confirm on a release build, as `.claude/rules/release.md` requires.

## 5. Gaps found and fixed (2026-10-23)

1. **WebDAV over plain HTTP** on a local network sends the password and slips unencrypted on that
   network. HTTPS stays required elsewhere; the setup screen now warns as soon as an `http://` address
   is typed. The privacy policy should say the same.
2. **Export files** stayed in the temporary folder after sharing. They are now deleted when the export
   screen closes, and leftovers (app killed) at the next launch.
3. **Startup fallback** to the temporary folder when Application Support could not be opened (iOS may
   purge it: slips could be lost). The app now shows the startup error instead and writes nothing.

## 6. Open items

| Item | Owner |
| --- | --- |
| Answer §1 (processor or tool) | Lawyer |
| Foundation legal layer: data-map schema, `vendors.yaml`, templates, `ez legal gen` / `check` | Etzian (foundation) |
| Validate `legal/data-map.yaml` against the schema (free-text "depends on the provider" entries may need a vocabulary) | After the schema exists |
| EFVP for iCloud; Apple in `vendors.yaml` | Etzian, before release |
| Generated documents bundled in the app (About lists them when present) and `PrivacyInfo.xcprivacy` | After `ez legal gen .` |
| `etzian:legal-compliance` review of the release | Before v0.1.0 |
| Privacy label in App Store Connect | At submission |
