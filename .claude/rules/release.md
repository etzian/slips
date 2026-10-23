# Release

`etzian:release` cuts releases. The version lives in one file, `Slips/Config/Version.xcconfig`:
`MARKETING_VERSION` (semver, the tag `v<x.y.z>`) and `CURRENT_PROJECT_VERSION` (build number, +1 on every
TestFlight upload). `package.json` has no `"version"`. The changelog is git-cliff with the skill's
`cliff.toml`.

Before a release: `./scripts/gate.sh` green, `ez doctor .` and `ez legal check .` pass, fr-CA complete
(`etzian:i18n-guardian`), legal documents regenerated (`ez legal gen .`) and the generated
`PrivacyInfo.xcprivacy` verified against a release build, `LICENSES/THIRD-PARTY.md` up to date.
`etzian:legal-compliance` reviews any release that changes what leaves the device.

Archive, upload to TestFlight and App Store Connect are the user's steps.

## Internal snapshots (`v0.0.x`)

A `v0.0.x` version is an **internal snapshot**, not a release: it is never uploaded to TestFlight or
the App Store and never given to anyone. It needs `./scripts/gate.sh` green on the Mac and `ez doctor .`;
the legal preflight above (`ez legal check .`, generated documents, `PrivacyInfo.xcprivacy`,
`etzian:legal-compliance`) is **not** required, because nothing reaches a user. It still gets a version
in `Version.xcconfig`, a `CHANGELOG.md` entry and a `v0.0.x` tag. Distributing a `v0.0.x` build is not
allowed; the first build anyone else installs is a full release (`v0.1.0` or later) with every check.
(User decision, 2026-10-23.)
