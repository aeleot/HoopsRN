# hoopsRN — Configuration gaps

**Scope:** —
**Verified:** 2026-09-16 @ 8209408

The half-finished rename, the deployment target nobody chose, and the platforms
the UI doesn't actually support.

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

## The deployment target excludes almost every device in use

**iOS 26.5**, and no API the app calls requires it. Worth confirming this is
intentional rather than an artifact of the Xcode version the project was
created with — it is the single line most likely to be a mistake nobody has
questioned.

---

## The project claims platforms the UI doesn't support

`SUPPORTED_PLATFORMS` includes `macosx` and `xros`, and the device family is
`1,2,7` (iPhone, iPad, Vision) — but the UI is iPhone-portrait-shaped
throughout. `MapTab`'s sheet now sizes off `onGeometryChange` rather than
`UIScreen.main.bounds`, so it at least follows its container; nothing else has
been checked at another shape.

---

## See also

- `../BUILD_AND_CONFIG.md` — the identity values behind all of the above.
