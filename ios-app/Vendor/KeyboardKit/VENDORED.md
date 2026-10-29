Vendored KeyboardKit 9.9.1 (MIT, last full-source tag, commit a7e33ac). Never upgrade to 10.x (closed binary).
Patched: asset catalogs removed (xtool has no actool); colors and two images defined in code.
Package.swift: KeyboardKitTests target removed (Tests/ not vendored).
Optional @Entry environment values given an explicit "= nil" (7 properties; the iOS 27.1 SDK @Entry macro requires a default).
All 46 #Preview blocks wrapped in "#if KEYBOARDKIT_PREVIEWS" (xtool OpenAppleMacrosServer drops property wrappers inside preview-local types; previews never run on device).

## Re-applying the patches

`protly.patch` is the full diff from upstream 9.9.1 (a7e33ac) to this tree, excluding the deleted
`Sources/KeyboardKit/Resources/*.xcassets` and `Sources/KeyboardKit/KeyboardKit.docc`. It reproduces this tree exactly:

    git clone https://github.com/KeyboardKit/KeyboardKit && cd KeyboardKit && git checkout a7e33ac
    rm -rf Sources/KeyboardKit/Resources/*.xcassets Sources/KeyboardKit/KeyboardKit.docc Tests
    git apply -p1 path/to/protly.patch

Files changed beyond the preview guards:
- `Package.swift`: KeyboardKitTests target removed.
- `Sources/KeyboardKit/Styling/Color+Keyboard.swift`: `KKColor` replaces the 11 colorsets (values checked against upstream).
- `Sources/KeyboardKit/Styling/Image+Keyboard.swift`: two asset images replaced with SF Symbols.
- `Sources/KeyboardKit/Callouts/Callouts+InputCallout.swift`: input callouts (key pop-ups) off. iOS clips a third-party
  keyboard at its top edge, so row 1's pop-ups were cut off (Sprint 4 phone check, the user asked to remove them).
- `Sources/KeyboardKit/Callouts/Callouts+ActionCallout.swift`: a long-press bubble that is taller than the room above
  its key shrinks to fit (padding to 2 pt, then item height), and `positionY` follows the real item height. Row 1's
  bubbles were cut at the top edge (Sprint 5 phone check).
- `Sources/KeyboardKit/_Keyboard/KeyboardHostingController.swift`: the hosting controller ignores safe areas in
  portrait (`safeAreaRegions = []`, iOS 16.4+; landscape keeps them). After an app switch iOS gave the keyboard a 17 pt
  top inset and the view grew by it above the keys (ios-app/CI simulator runs; docs/ios-keyboard-notes.md,
  "Simulator verification").
- `= nil` on optional `@Entry` values: `_Keyboard/KeyboardViewStyle.swift`, `_Keyboard/Models/Keyboard+DockEdge.swift`,
  `_Keyboard/Models/Keyboard+InputToolbar.swift`, `_Keyboard/Models/Keyboard+SpaceLongPressBehavior.swift`,
  `_Keyboard/Models/Keyboard+SpaceMenuType.swift` (2), `_Keyboard/Views/Keyboard+ButtonStyle.swift`.

The 46 preview guards are already in `protly.patch`. `scripts/guard_previews.py Sources/KeyboardKit` is the script that
added them, kept for a fresh upgrade (run once on pristine sources; not idempotent).
