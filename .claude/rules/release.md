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
