Vendored KeyboardKit 9.9.1 (MIT, last full-source tag, commit a7e33ac). Never upgrade to 10.x (closed binary).
Patched: asset catalogs removed (xtool has no actool); colors and two images defined in code.
Package.swift: KeyboardKitTests target removed (Tests/ not vendored).
Optional @Entry environment values given an explicit "= nil" (7 properties; the iOS 27.1 SDK @Entry macro requires a default).
All 46 #Preview blocks wrapped in "#if KEYBOARDKIT_PREVIEWS" (xtool OpenAppleMacrosServer drops property wrappers inside preview-local types; previews never run on device).
