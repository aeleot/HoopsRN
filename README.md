# hoopsRN

A SwiftUI iOS app (Xcode project name `hoopr`, product name `hoopsRN`) for
finding pickup basketball games, backed by Firebase (Auth + Firestore).

This file is the setup checklist for a new developer's machine. For how the
app is actually built — architecture, data model, dependencies, test coverage
— read [`context/INDEX.md`](context/INDEX.md) first; it routes you to the
right doc instead of making you guess.

## Prerequisites

| Tool | Why | Notes |
|---|---|---|
| **Xcode 26.6+** | Builds against the iOS **26.5** SDK | The project's `IPHONEOS_DEPLOYMENT_TARGET` is 26.5, so Xcode must ship that SDK. Xcode also needs to have downloaded the **iOS 26.5 Simulator** runtime (Settings → Platforms) before you can run in Simulator. |
| **Node.js** | Only for the Firebase CLI and the optional geocoding script | Not needed to build or run the app itself. |
| **Python 3** | Only for the court-dataset scripts in `tools/` | Standard library only — no `pip install` needed. |

No Ruby/CocoaPods, no Fastlane. The only dependency manager in play is Swift
Package Manager, and Xcode drives that itself.

## 1. Clone and open

```bash
git clone <repo-url>
cd hoopr
open hoopr.xcodeproj
```

Xcode resolves Swift Package Manager dependencies automatically on first
open (Firebase iOS SDK 12.16.0 and its transitive pins — 14 packages total).
`Package.resolved` is committed, so you get the exact versions everyone else
has, not whatever `firebase-ios-sdk` happens to be on that day. If Xcode
seems stuck, **File → Packages → Resolve Package Versions**.

There's no scheme file checked into the repo — Xcode auto-generates one
named `hoopr` for the app target the first time it opens the project. If it's
missing from the scheme picker, use **Product → Scheme → Manage Schemes** and
add it.

## 2. Firebase — nothing to configure

`hoopr/GoogleService-Info.plist` is committed and already points at the
shared Firebase project (`hoopsrn-4f1e9`). You don't need your own Firebase
project, and you don't need to download a plist from the console — just
build and run.

You only need the **Firebase CLI** if you're changing `firestore.rules` or
`firestore.indexes.json`:

```bash
npm install -g firebase-tools
firebase login
firebase deploy --only firestore:rules,firestore:indexes --dry-run   # compiles without deploying
```

Until rules are deployed, writes fail with `permission-denied` and the app
surfaces "Not allowed to save yet" — that's a rules problem, not a client bug.

## 3. Run it

Select the **hoopr** scheme, pick an iOS 26.5 Simulator, Cmd+R. Auth is email/
password via Firebase Auth — sign up a throwaway account from the login
screen, no invite or allowlist needed.

Running on a **physical device** additionally needs your own Apple Developer
team selected under **Signing & Capabilities** (`CODE_SIGN_STYLE` is
`Automatic`, so Xcode handles provisioning once a team is picked).

## 4. Run the tests

```bash
xcodebuild test -project hoopr.xcodeproj -scheme hoopr \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:hooprTests
```

Scope it to `hooprTests` — the `hooprUITests` runner currently fails to
launch (`RequestDenied` from SpringBoard on this project), so `xcodebuild
test` without `-only-testing` will report a failure that has nothing to do
with your change. `hooprTests` alone is 120 real test methods across eleven
suites; none of it is scaffold.

## Optional tooling

- `tools/build_courts.py`, `tools/fetch_city_courts.py` — regenerate/extend
  the bundled court dataset (`hoopr/Resources/courts.json`) from OpenStreetMap.
  Pure standard-library Python, no install step, no API key.
- `location-decoder-script/` — a standalone Node script for reverse-geocoding
  via OpenStreetMap Nominatim. Run `npm install` inside that directory first;
  it's not part of the app build.
- `tools/check_context_drift.py` — checks whether `context/*.md` docs have
  fallen out of sync with the code. Only relevant if you're updating those
  docs: `python3 tools/check_context_drift.py`.

## Where to go next

[`context/INDEX.md`](context/INDEX.md) is a routing table into the rest of
the docs — architecture, data model, the map layer, build/test details,
known gaps — each scoped to the source paths it covers. Start there rather
than reading source cold.
