# hoopsRN — Configuration gaps

**Scope:** —
**Verified:** 2026-09-24 @ f30e4b2

The half-finished rename, and the iOS 18 fallback path nothing has run.

`Scope: —` because this is a narrative over the Xcode project and bundle
identity, which `BUILD_AND_CONFIG.md` owns. It can't be diffed, so it's re-read
by hand every pass.

---

## The app is called hoopsRN; everything structural still says `hoopr`

The 2026-08-15 rename was **deliberately shallow** — display name, user-facing
strings, log subsystem and URL scheme only. The bundle ID, target and scheme
names, module name, the three source directories, and every `hoopr`-prefixed
identifier in `Theme.swift`/`Typography.swift` are unchanged.

**This is not drift to be quietly repaired.** The bundle ID
`Big-Boss-LLC.hoopr` is pinned by `GoogleService-Info.plist` and can't move
without a new Firebase iOS app registration and a fresh plist — which orphans
every existing install. `BUILD_AND_CONFIG.md` has the full split, and the
agreed prefix (`hoops`) if the identifiers are ever renamed.

---

## Nothing below iOS 26 has ever run

The deployment target is iOS 18.0, and every iOS 26 API is gated — but the only
simulator runtimes installed are iOS 26.5 and 27.0, so the fallback branches
have never executed: `Support/Glass.swift`'s `.ultraThinMaterial` path (every
glass surface), `MapTab`'s pre-26 Maps hand-off, and the confetti and glow's
`TimelineView` paths on iOS 18. The compiler proves they *build*; nobody has
seen them. Closing it needs an iOS 18 runtime or device.

The UI is iPhone-portrait throughout, and the project says so
(`SUPPORTED_PLATFORMS` is `iphoneos iphonesimulator`, device family `1`), so
that is no longer a gap. `XROS_DEPLOYMENT_TARGET` is set and inert;
`../BUILD_AND_CONFIG.md` says why.

---

## See also

- `../BUILD_AND_CONFIG.md` — the identity values behind all of the above.
