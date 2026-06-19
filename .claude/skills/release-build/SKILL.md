---
name: release-build
description: Build, Developer ID sign, notarize, and staple MovieTagger.app into a distributable, Gatekeeper-approved zip. Use when the user wants to cut a release, build a signed/notarized build, or produce a distributable .app.
disable-model-invocation: true
---

# release-build

Produce a **Developer ID signed + notarized + stapled** build of MovieTagger.app,
packaged as a zip that launches on any Mac with no Gatekeeper warning.

This app is non-sandboxed, has **no third-party dependencies**, and uses **XcodeGen**
(`project.yml` is the source of truth — `project.pbxproj` is generated). Signing
settings live in the Release config of `project.yml`:
`CODE_SIGN_STYLE: Manual`, `CODE_SIGN_IDENTITY: "Developer ID Application"`,
`DEVELOPMENT_TEAM: 9R236BB67S`, `ENABLE_HARDENED_RUNTIME: YES`.

All artifacts go under `build/` (gitignored).

## Prerequisites (verify first — fail fast if missing)

```bash
# 1. Developer ID Application cert must be installed and valid
security find-identity -v -p codesigning   # must list: Developer ID Application: … (9R236BB67S)

# 2. notarytool credential profile must authenticate
xcrun notarytool history --keychain-profile "MovieTagger"   # must NOT error
```

If either fails, stop and tell the user — these are credential installs only they can
do (see "Credential setup" at the bottom). Do **not** attempt ad-hoc signing as a
substitute; it will not notarize.

## Procedure

Run from the repo root. Stop and report on any failure.

### 1. Version + regenerate

```bash
VERSION=$(grep -E 'MARKETING_VERSION' project.yml | sed -E 's/.*"([^"]+)".*/\1/')
xcodegen generate
```

If cutting a new version, bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in
`project.yml` first — never edit `project.pbxproj` directly.

### 2. Archive (Developer ID + Hardened Runtime)

```bash
rm -rf build/MovieTagger.xcarchive build/dist
xcodebuild -project MovieTagger.xcodeproj -scheme MovieTagger -configuration Release \
  -derivedDataPath build/DerivedData \
  archive -archivePath build/MovieTagger.xcarchive | tail -6
```

Verify the product before going further:

```bash
APP="build/MovieTagger.xcarchive/Products/Applications/MovieTagger.app"
# Must show: flags=…(runtime), Authority=Developer ID Application…, TeamIdentifier=9R236BB67S
codesign -dvvv "$APP" 2>&1 | grep -E 'Authority=Developer|flags=|TeamIdentifier'
# Must NOT exist — a nested app fails notarization (see Gotchas)
[ -e "$APP/Contents/Resources/MovieTagger.app" ] && echo "ABORT: nested app in Resources"
```

### 3. Package + notarize (waits for Apple's verdict)

```bash
mkdir -p build/dist
cp -R "$APP" build/dist/
ditto -c -k --keepParent "build/dist/MovieTagger.app" "build/dist/MovieTagger-$VERSION.zip"
xcrun notarytool submit "build/dist/MovieTagger-$VERSION.zip" \
  --keychain-profile "MovieTagger" --wait
```

If `status: Invalid`, pull the detailed reasons and fix before retrying:

```bash
xcrun notarytool log <submission-id> --keychain-profile "MovieTagger"
```

### 4. Staple + re-package + verify

The zip from step 3 was made *before* the ticket existed, so staple the app and
re-zip:

```bash
xcrun stapler staple "build/dist/MovieTagger.app"
xcrun stapler validate "build/dist/MovieTagger.app"
rm -f "build/dist/MovieTagger-$VERSION.zip"
ditto -c -k --keepParent "build/dist/MovieTagger.app" "build/dist/MovieTagger-$VERSION.zip"
# The real test — must say: accepted / source=Notarized Developer ID
spctl -a -vvv -t exec "build/dist/MovieTagger.app"
```

### 5. Report

Tell the user: version, path + size of `build/dist/MovieTagger-<VERSION>.zip`, and the
`spctl` result. Stapled means it launches offline with no Gatekeeper prompt.

## Gotchas (both hit on the first real release — check these on failure)

- **Nested `.app` in Resources → notarization Invalid.** A stray built
  `MovieTagger/MovieTagger.app` in the source tree gets swept in by `sources: - MovieTagger`
  and copied into `Contents/Resources/`. Apple rejects the unsigned inner bundle.
  `project.yml` now excludes `*.app` from sources and the artifact is gitignored;
  if it reappears, delete `MovieTagger/MovieTagger.app` before building.
- **"Invalid trust settings" at sign time.** If the Developer ID cert was ever set to
  "Always Trust" in Keychain Access, `codesign` refuses it. Fix in Keychain Access:
  double-click the cert → Trust → "Use System Defaults". (Diagnose with
  `security dump-trust-settings`.) This is a manual, user-only keychain change.

## After success

This skill does **not** tag or publish. Offer to `git tag v<VERSION>` and draft a
GitHub release with the zip attached.

## Credential setup (one-time, user does this)

- **Developer ID cert**: Xcode → Settings → Accounts → Manage Certificates → ＋ →
  Developer ID Application (or import a `.p12` from the Mac that created it).
- **notarytool profile** (App Store Connect API key is most reliable):
  `xcrun notarytool store-credentials "MovieTagger" --key AuthKey_XXXX.p8 --key-id <KEYID> --issuer <ISSUER-UUID>`
