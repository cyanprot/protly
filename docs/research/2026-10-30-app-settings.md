# App settings, customization and app UX: a design study (2026-10-30)

Research only: no code changed. Base: `main` at 1624fcc. This study builds on the UI audit
(`docs/research/2026-10-30-ui-audit.md`, IDs such as F2, A1-A4, B4, K1 are its findings) and the competitor survey
(`docs/research/2026-10-30-competitors.md`); it does not repeat them. It is input for a later plan, not a plan.

## Sources and limits

- Code: `ios-app/Sources/Protly/ProtlyApp.swift`, every file in `ios-app/Sources/ProtlyKeyboard`, the ProtlyCore
  files that hold tunable values, the vendored KeyboardKit settings and gesture code, `ios-app/xtool.yml`,
  `ios-app/Package.swift`, the two Info.plist files. File and line are given for every code claim.
- xtool: cloned from https://github.com/xtool-org/xtool at 64fe8e3 (2026-10-30) and read locally.
- Apple: developer documentation and support pages read on 2026-10-30 (some through `curl`, because the pages render
  in JavaScript). Other products: official help pages and App Store listings first; where only a review or
  third-party guide was found, the claim says so.
- Not done: nothing here ran on a phone or simulator. The App Group findings come from Apple's documentation and
  xtool's source and pull request, not from a protly build. Every "to verify" item is listed in "Open questions".

## 1. What can be configured today

### 1.1 The container app

The app is one `Form` with three sections (`ProtlyApp.swift:29-58`):

| Section | What it holds | Where |
|---|---|---|
| Setup | Three static lines of text: add the keyboard, turn on Full Access, keep the Emoji keyboard | `ProtlyApp.swift:30-34` |
| About me | A multi-line field, a scalar counter `n / 1000`, a "Copy for the keyboard" button, a footer with the six-step handoff | `ProtlyApp.swift:35-54` |
| Test | A free text field | `ProtlyApp.swift:55-57` |

The about-me note is the only value a user can set. Everything else the keyboard does is fixed in code.

### 1.2 The keyboard: fixed choices that could be settings

| Behaviour | Value today | Where | User can change it? |
|---|---|---|---|
| Haptic on key press | Off, forced on every load | `KeyboardViewController.swift:61-64` | No |
| Key click sound | On (KeyboardKit default) | `Vendor/.../Feedback/FeedbackSettings.swift:27-28` | No (the ringer switch only) |
| Auto-capitalization | Off, forced on every load | `KeyboardViewController.swift:65-66` | No |
| Double-space period | On (KeyboardKit `endSentenceText` ". ", 3 s window) | `Vendor/.../_Keyboard/Keyboard+StandardKeyboardBehavior.swift:70-72`; phone check 11 PASS in `docs/ios-keyboard-notes.md:217` | No |
| Space long-press | Moves the cursor | `Vendor/.../_Keyboard/KeyboardSettings.swift:98-99` | No |
| Long-press and repeat delay | 0.5 s and 0.5 s; double tap 0.2 s | `Vendor/.../_Dependencies/GestureButton/GestureButtonConfiguration.swift:30-33` | No |
| Key pop-ups | Removed in the vendored patch | `ios-app/Vendor/KeyboardKit/VENDORED.md:20` | No |
| Key geometry | row pitch 54, key 43, bar row 29, side inset 11/3 pt | `ProtlyLayout.swift:7-20` | No |
| Keyboard height (portrait) | 257 pt pin | `ProtlyHeight.swift:26-27` | No |
| Key colors | KeyboardKit standard style, shift arrow recolored | `KeyboardViewController.swift:500-508` | No |
| Protly key | `character.bubble`, runs `act(nil)` | `KeyboardViewController.swift:417-423, 464-465` | No |
| Bar | Three fixed slots: flip, action or Undo, suggestion | `ProtlyBar.swift:18-22, 29-52` | No |
| Language of a new message | Last word's language, Korean when none | `TypingSession.swift:36`; saved at `KeyboardViewController.swift:363-374` | No |
| Detector prior | `priorBonus` 2.0; learned-word bonus 1.0 | `LanguageDetector.swift:24-32, 77-78` | No |
| Learned words | Up to 1,000 per language, keys up to 32 | `LearnedWords.swift:16-19`; stored at `Words.swift:9, 41-45` | No (no view, no delete) |
| Suggestions | Fix only for words with frequency ≥ 5,000; system text replacements and contact names included | `Suggester.swift:15`; `Words.swift:22-33` | No |
| Action choice | Hangul anywhere → Translate, else Polish; `ko:` → Korean polish | `ActionAPI.swift:64-73` | No (prefix only) |
| Default target | English when there is no prefix | `ActionAPI.swift:174` | No (prefix only) |
| Models and effort | Read clipboard: Sonnet; Translate and Polish: Opus; effort low | `ActionAPI.swift:90-92, 156-158` | No |
| Timeouts | 30 s idle, 90 s total | `ActionAPI.swift:101-102` | No |
| Register and style | Read clipboard into banmal; English keeps the draft's register; Canadian spelling; punctuation and phrase bans; fixed writer facts | `keyboard-prompt.txt:1, 4, 11, 20, 28, 30, 32` | No |
| About-me note | Up to 1,000 scalars, sent with Translate and Polish only | `AboutMe.swift:12, 70-76` | Yes, through the handoff below |
| API key | Baked in at build time | `ActionClient.swift:16` (`Secrets.apiKey`) | No (rebuild) |
| Memory readout | Build flag, ships false | `Words.swift:12` | No (rebuild) |

### 1.3 How the app and the keyboard share data today

They do not share storage. Each target writes its own `UserDefaults.standard`, which lives in its own sandbox:

| Key | Container | Written by | Read by |
|---|---|---|---|
| `protly.aboutMe` | app | the About me field (`ProtlyApp.swift:24`) | the app only |
| `protly.aboutMe` | keyboard | Save on the confirm panel (`KeyboardViewController.swift:288-292`) | `ActionClient.swift:13` |
| `protly.previousLanguage` | keyboard | `KeyboardViewController.swift:371-374` | `KeyboardViewController.swift:363-369` |
| `protly.clipboardChangeCount` | keyboard | `KeyboardViewController.swift:249, 346` | `KeyboardViewController.swift:350` |
| `protly.learnedWords` | keyboard | `Words.swift:41-45` | `Words.swift:17-21` |
| KeyboardKit settings (`com.keyboardkit.settings.*`) | keyboard | KeyboardKit, plus the two forced writes at `KeyboardViewController.swift:62, 66` | KeyboardKit (`KeyboardSettings+Store.swift:20, 62-71`) |

The one channel is the clipboard, used for the about-me note
(`ProtlyApp.swift:5-6`, `AboutMe.swift:3-7`):

1. The app copies `protly about me v1` + newline + the note, local only, expiring after 10 minutes
   (`ProtlyApp.swift:63-71`).
2. The user opens a text field, taps Read clipboard (or the protly key on an empty field), and answers iOS's Allow
   Paste prompt (`KeyboardViewController.swift:246-268`).
3. `AboutMe.parse` checks the marker, strips tags, refuses hidden characters and notes over 1,000 scalars
   (`AboutMe.swift:34-43`).
4. A confirm panel shows the whole note; Save is inert for 0.5 s (`AboutMe.swift:18-20, 51-65`;
   `KeyboardViewController.swift:261-262, 288-292`).

Limits of this channel:

- **Six user steps and a system prompt per change.** The Allow Paste prompt appears on every read
  (`docs/ios-keyboard-notes.md:117`). The audit's A2 covers the wording; the step count cannot go lower on this path.
- **Full Access is required.** `act` returns at the Full Access guard before it reaches `readClipboard`
  (`KeyboardViewController.swift:216-223`). A user who keeps Full Access off cannot set the note at all.
- **One way, no confirmation back.** The app cannot see what the keyboard saved. The two `protly.aboutMe` copies
  drift: edit in the app without copying, and the app shows a note the keyboard does not send.
- **One value.** The marker format carries one string. Every new setting would need its own marker or a new
  format, a new parser and a new confirm panel.
- **Any app can write the marker.** That is why the confirm panel and delay exist (`AboutMe.swift:4-7`); a
  general settings handoff needs the same guard.

Two other channels exist without an App Group. Neither is built; both are proposals.

- **In-keyboard settings.** The keyboard writes its own `UserDefaults` at any time, with or without Full Access
  (it already does: table above). A small settings panel opened from the keyboard (audit A3) covers every setting
  the keyboard owns. Cost: settings live where people do not look for them, and the HIG asks to avoid help content
  inside the keyboard (quoted in the audit).
- **Field handoff.** The keyboard reads the whole field it types into (`documentContextBeforeInput`, full context
  measured in `docs/ios-keyboard-notes.md:116, 124`). The app can put a settings code in its own text field; when the
  keyboard comes up on that field it sees the marker and shows the same confirm panel. No pasteboard, so no Allow
  Paste prompt and no Full Access needed. Not measured: the length limit of the context on a long code, and whether
  the context is available before the first keystroke. To verify on the phone.

### 1.4 What an App Group would unlock and what it needs

**What Apple allows.** A keyboard without Full Access has "read-only access to the containing app's shared
containers"; writing to them needs open access (https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard).
A developer forum thread shows the failure mode on a device: the keyboard's write to an App Group suite fails with
"setting preferences outside an application's container requires user-preference-write or file-write-data sandbox
access" until `RequestsOpenAccess` is on and Full Access granted (https://developer.apple.com/forums/thread/728434).
A shipping keyboard's write-up reports the same silent failure (https://dev.to/tbds_2dadf2b626f315902eae/the-three-hard-constraints-of-an-ios-keyboard-extension-46af,
unofficial). Protly already requests open access (`ProtlyKeyboard-Info.plist:17`).

So the rule for protly: **the app writes settings, the keyboard reads them, always.** The keyboard writes back
(learned words, a usage counter, a "seen" status) only when Full Access is on, and must treat a failed write as
normal.

**What it needs on the signing side.**

- **Free Apple ID with xtool 1.24.0 (what the phone build uses today): not possible.** The plan recorded that xtool
  drops the App Groups entitlement on free teams (`docs/plans/2026-10-28-ios-keyboard.md:30-39`).
- **Free Apple ID with xtool after 1.24.0: possible, not yet released.** xtool merged "ds: allow one app group on
  free teams" on 2026-10-30 (commit 0c63e69, https://github.com/xtool-org/xtool/pull/284). It flips the App Groups
  capability to `isFree: true` (`Sources/XKit/DeveloperServices/App IDs/Entitlements/DeveloperServicesCapability.swift:74-78`
  at 64fe8e3) and throws if a free-team app asks for more than one group
  (`DeveloperServicesAddAppOperation.swift:189-193`). The PR reports a widget reading its app's
  `UserDefaults(suiteName:)` on iOS 27.2 with a free Apple ID. The latest tag is 1.24.0 (2026-10-25), so this needs
  the next release or a pinned build of `main`. Protly needs exactly one group, shared by both targets, which fits
  the one-group limit (each target is its own App ID with one group).
- **The group ID is rewritten.** xtool signs `group.com.northprot.protly` as
  `group.XTL-<ID>.com.northprot.protly`, where `XTL-<ID>.` is the same prefix it puts on the bundle IDs
  (`Sources/XKit/Utilities/ProvisioningIdentifiers.swift:15-40` at 64fe8e3;
  `DeveloperServicesAssignAppGroupsOperation.swift:38-52`). Code cannot hard-code the group (the plan already says
  the same for bundle IDs, `docs/plans/2026-10-28-ios-keyboard.md`, "Design amendments" 3). It can derive it at
  runtime from its own bundle ID. Proof, a local script mirroring xtool's functions (not committed):

  ```python
  # xtool ProvisioningIdentifiers @ 64fe8e3
  def identifier(sanitized, identity_id): return "XTL-" + identity_id.split("-")[0].upper() + "." + sanitized
  def group_id(requested, identity_id):
      s = requested[len("group."):] if requested.startswith("group.") else requested
      return "group." + identifier(s, identity_id)
  # proposed runtime rule, same in both targets
  def derived(bundle_id, ext_suffix=".ProtlyKeyboard"):
      app = bundle_id[:-len(ext_suffix)] if bundle_id.endswith(ext_suffix) else bundle_id
      return "group." + app
  for ident in ["a1b2c3d4-0000-1111-2222-333344445555", "ffff0000-aaaa-bbbb-cccc-ddddeeeeffff"]:
      app = identifier("com.northprot.protly", ident)
      kb = identifier("com.northprot.protly.ProtlyKeyboard", ident)
      assert derived(app) == group_id("group.com.northprot.protly", ident) == derived(kb)
  assert derived("com.northprot.protly.ProtlyKeyboard") == "group.com.northprot.protly"  # paid team: no rewrite
  ```

  Output: `XTL-A1B2C3D4.com.northprot.protly` → `group.XTL-A1B2C3D4.com.northprot.protly` for both targets, and the
  plain group for a paid team. The extension's bundle ID is `<app>.ProtlyKeyboard` because xtool forms it as
  `orgID.product` (`Sources/PackLib/PackSchema.swift:45-50`). The Swift version is a few lines in ProtlyCore,
  testable on Linux.
- **Files to change (all need the tower).** Two entitlements plists with `com.apple.security.application-groups`,
  and `entitlementsPath` for the app and for the extension in `ios-app/xtool.yml` (xtool's schema has both:
  `Sources/PackLib/PackSchema.swift:18, 33`). CLAUDE.md forbids editing `xtool.yml` without the tower. KeyboardKit
  then takes the group through `KeyboardApp(name:appGroupId:)` (`Vendor/.../App/KeyboardApp.swift:53`;
  `KeyboardSettings+Store.swift:62-71`), set in `KeyboardViewController.swift:55`, if protly wants KeyboardKit's own
  settings shared too.
- **Paid Apple Developer Program.** 99 USD per year (https://developer.apple.com/programs/whats-included/). App Groups
  are a standard capability there, the group ID is not rewritten, and profiles do not expire every 7 days (the
  7-day free profile is in `docs/plans/2026-10-28-ios-keyboard-design.md:28-29`). Not required for the App Group
  any more once the xtool release ships; still the route to TestFlight or the App Store.
- **Settings bundle (settings inside iOS Settings).** Apple's archived keyboard guide suggests one, so settings
  "appear in the Keyboard area in Settings, associated with your keyboard"
  (https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html).
  Its values are written to the container app's preferences, so the keyboard still needs the App Group to read
  them, and the bundle's plist would need the rewritten group ID, which is only known at signing time. Not
  recommended for protly; not verified whether xtool packs a `Settings.bundle`.

**What it unlocks.**

| With an App Group | Without one |
|---|---|
| Every setting edited in the app, live: no clipboard, no Allow Paste, no confirm panel | In-keyboard panel, or a settings code through the clipboard (Full Access) or the field handoff |
| Works with Full Access off (reads are allowed) | Clipboard handoff needs Full Access |
| One source of truth for About me, style notes, glossary | Two copies that drift (1.3) |
| App can show learned words, usage and cost, last error, "keyboard seen" status (keyboard writes, Full Access on) | None of that is visible in the app |
| App can import or clear learned words (app writes an edit request, keyboard applies it) | Only from inside the keyboard |
| KeyboardKit's own settings (sound, haptics, autocap) set from the app | Set from the keyboard |

**Recommendation.** Plan for the App Group, behind a one-day spike: build with the first xtool release that has
#284, add the two entitlements, write one key from the app and read it in the keyboard with Full Access off and
on, and log the derived group ID. Design every setting so it also has a no-App-Group fallback (column "No AG" in
section 3), because the spike can fail and the 7-day free signing stays fragile.

## 2. Survey: settings and customization in other keyboards

Columns: what each keyboard exposes to users. "Not found" means not on the official pages read, not that the
product lacks it.

| | Apple keyboard | Gboard (iOS) | SwiftKey (iOS) | Grammarly Keyboard | Naver SmartBoard | Typewise | 디자인키보드 (Design Keyboard) |
|---|---|---|---|---|---|---|---|
| Where settings live | iOS Settings > General > Keyboard; from the keyboard: touch and hold the globe or emoji key, Keyboard Settings [A1] | Gboard app (cog in the keyboard opens it) [G2, G3] | SwiftKey app; themes also from the keyboard toolbar [S2] | Companion app, Keyboard section [R1, R2] | App [N1] | App [T1, T2] | App [D1] |
| Themes, key colors | System light/dark only | Themes, "custom themes ... change everything from background color to glide trail thickness" [G1] | Photo themes, animated themes, Nickel X with transparency [S2] | Not found | Skins or your own image [N1] | Themes (more in Pro) [T1, T3] | 100,000+ photo and animated themes; text color, background color and transparency per theme [D1] |
| Fonts | No | Not found | Not found | No | Not found | Font size [T3] | Many fonts [D1] |
| Key size or height | One-handed layout only [A1] | One-handed mode [G3] | Not found | Not found | Not found | Large hexagon keys; key layout and size options [T1, T3] | Not found |
| Bar or toolbar layout | Fixed predictive bar | Fixed | Toolbar with removable items asked for in reviews (a Bing button "no way to remove") [S3] | Completions bar on/off [R1] | Customizable "control center" style panel (review) [N1] | Not found | Not found |
| Haptics, sound | Settings > Sounds & Haptics > Keyboard Feedback: Sound, Haptic [A2] | Haptic on key press [G1] | Key Click Sounds toggle; limited haptics [S1] | Sound and haptic feedback on keypress [R1] | Not found | Vibration in Pro [T1] | Not found |
| Autocap, double-space, caps lock | Typing features under All Keyboards; double-tap space for period [A1] | Auto-capitalization, caps lock, period shortcut [G2] | Not found | Auto-capitalization, caps lock, "." shortcut, show lowercase keys [R1] | Not found | Not found | Not found |
| Key pop-ups | Character Preview toggle (third-party guide) [A3] | Character preview [G2] | Not found | Character Preview (long-press accents) [R1] | Not found | Not found | Not found |
| Long-press or hold delay | Not for the onscreen keyboard (Key Repeat is for external keyboards) [A4] | Not found on iOS | Not found | Not found | Not found | Hold duration, swipe length, button sensitivity (review) [T3] | Not found |
| Autocorrect, suggestions | Auto-correction, predictive text [A1] | Auto-correction, emoji suggestions, block offensive words [G2] | Autocorrect, predictions [S3] | Auto-correction, undo auto-correction, synonyms, smart formatting [R1, R2] | Next-word suggestions, saved phrases, keys you assign to repeated text [N1] | "Learns what you type" [T1] | Saved phrases, autocomplete [D1] |
| Language behaviour | Add keyboards; bilingual keyboards for some pairs; switches between your two most used [A5] | Up to three languages [G3] | Two languages at once [S3] | Six typing languages; dialect per language [R1] | Five Korean layouts (두벌식, 단모음, 천지인, 나랏글, 베가) [N1] | 40+ languages at once [T1] | Several Korean layouts [D1] |
| AI actions | Writing Tools, outside the keyboard settings | None on iOS (competitor survey) | Copilot, tone change | Rewrites, tone (Premium) [R3] | Translate into English, Chinese, Japanese while typing [N1] | Translate, proofread, tonality, shorten, extend [T1] | Translation [D1] |
| Privacy controls | Full Access is per keyboard in iOS Settings | Clear search history, location toggle [G3] | Not found | Personal dictionary management [R1]; training opt-out on the web (competitor survey) | "Does not collect any information about keyboard input" [N1] | No Full Access needed; offline mode turns off app analytics [T1] | Not found |

Sources:
- [A1] https://support.apple.com/guide/iphone/type-with-the-onscreen-keyboard-iph3c50f96e/27/ios/27
- [A2] https://support.apple.com/guide/iphone/change-the-sounds-and-vibrations-iph07c867f28/ios
- [A3] https://iphonelife.com/content/tip-day-how-disable-pop-character-previews-iphone-keyboard (third party)
- [A4] https://support.apple.com/guide/iphone/adjust-keyboard-settings-ipha7c3927eb/27/ios/27
- [A5] https://support.apple.com/guide/iphone/add-or-change-keyboards-iph73b71eb/27/ios/27
- [G1] https://apps.apple.com/us/app/gboard-the-google-keyboard/id1091700242 (release notes)
- [G2] https://techbriefly.com/2026/02/18/how-to-customize-gboard-settings-on-your-iphone-or-ipad/ (third party)
- [G3] https://ios.gadgethacks.com/how-to/20-tips-help-you-master-gboard-for-iphone-0182301/ (third party)
- [S1] https://support.microsoft.com/en-AU/swiftkey-keyboard/how-do-i-change-the-sounds-or-vibrations-that-my-microsoft-swiftkey-keyboard-makes
- [S2] https://support.microsoft.com/en-US/swiftkey-keyboard/which-themes-are-available-for-my-microsoft-swiftkey-keyboard
- [S3] https://apps.apple.com/us/app/microsoft-swiftkey-ai-keyboard/id911813648 (description and reviews)
- [R1] https://support.grammarly.com/hc/en-us/articles/360041391992
- [R2] https://support.grammarly.com/hc/en-us/articles/115000729831-How-to-turn-off-autocorrect-in-Grammarly-for-iPhone
- [R3] https://apps.apple.com/us/app/grammarly-ai-keyboard-voice/id1158877342
- [N1] https://apps.apple.com/kr/app/id1297816298 (description and reviews)
- [T1] https://apps.apple.com/us/app/id1470215025
- [T2] https://www.typewise.app/blog/privacy-typewise-keyboard-secure
- [T3] https://www.igeeksblog.com/typewise-custom-keyboard-ios-app-review/ (third party)
- [D1] https://apps.apple.com/KR/app/id1460767601 (description)

What this means for protly:

1. **Feedback and typing toggles are table stakes.** Apple, Gboard, Grammarly and SwiftKey all let people turn sound
   and haptics on or off, and Grammarly's list (auto-cap, caps lock, "." shortcut, character preview, lowercase
   keys) is close to Apple's. A third-party keyboard cannot read Apple's own switches (Apple's archived guide:
   "Your custom keyboard does not have access to most of the general keyboard settings",
   https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html), so protly must repeat
   them. Protly forces two of them off today (1.2).
2. **Heavy visual customization is a separate market.** Design Keyboard and SmartBoard sell themes, images and
   fonts; utility keyboards (Apple, Grammarly, Typewise) keep it to light/dark plus a few sizes. For protly,
   key colors, a few theme presets and a key-height choice match the owner's ask without a theme store.
3. **Nobody lets you arrange the bar.** SwiftKey reviewers ask to remove toolbar items and cannot. Bar slot
   assignment is a cheap way for protly to stand out.
4. **AI settings elsewhere are presets (tone lists), not personal rules.** Protly's about-me note and style rules
   are the differentiator the competitor survey found; exposing them as editable settings keeps that edge.
5. **Privacy as a setting.** Typewise sells "no Full Access needed"; SmartBoard states it collects nothing. Protly
   can say what it sends and let people keep Full Access off for typing (audit F2), and the App Group's read-only
   access without Full Access makes that a real option for settings too.

## 3. Settings catalog

Legend.
- **No AG**: can the keyboard get this value without an App Group?
  - **K**: keyboard-owned. It can live in the keyboard's own `UserDefaults`, set from an in-keyboard panel. Works
    with Full Access off.
  - **H**: handoff. The app sends it as a confirmed settings code (clipboard: Full Access needed; field handoff:
    not, to verify).
  - **No**: needs the App Group (the keyboard must write it back for the app to see it, so Full Access too).
- **Effort**: S up to half a day, M one to three days, L more, or needs new phone or CI checks.
- **Priority**: P1 next, P2 soon, P3 later.

### Screen: Keyboard › Feel

| Setting | What it does | Default | No AG | Effort | Priority |
|---|---|---|---|---|---|
| Haptic feedback | Off, Light, Medium on key press. Replaces the forced off at `KeyboardViewController.swift:61-64`; both bypass paths found in the plan (space long-press, callout selection, `docs/plans/2026-10-28-ios-keyboard.md:2238`) follow it | Off | K | S | P1 |
| Key sound | Click on key press (`FeedbackSettings.swift:27-28`) | On | K | S | P1 |
| Auto-capitalization | English sentence starts; Korean keycaps already ignore it (`ProtlyLayout.swift:52-58`) | Off | K | S | P1 |
| Double-space period | `endSentenceText` on or off | On | K | S | P2 |
| Long-press delay | 0.3 / 0.5 / 0.7 s, through `.keyboardButtonGestureConfiguration` (`Vendor/.../Gestures/GestureButton+KeyboardKit.swift:13-17`) | 0.5 s | K | S | P3 |
| Space long-press | Move cursor, or off | Move cursor | K | S | P3 |
| Key pop-ups | Rows 2 and 3 only (audit H1); needs a flag in the vendored callout patch and the `protly.patch` and `VENDORED.md` update | Off | K | M | P3 |

### Screen: Keyboard › Look

| Setting | What it does | Default | No AG | Effort | Priority |
|---|---|---|---|---|---|
| Appearance | System, Light, Dark (forces the color scheme in `ProtlyRoot`) | System | K | S | P2 |
| Theme preset | Four or five named palettes (Apple, Ink, Paper, Mint, Night) applied through the existing `keyboardButtonStyle` builder (`KeyboardViewController.swift:500-508`) | Apple | H | M | P2 |
| Key colors | Custom: letter key, function key, label, action accent (the accent also tints bar actions, audit B2). Color pickers in the app, contrast warning under 4.5:1 | Apple | H | M | P2 |
| Label weight and size | Regular / Medium / Semibold; S / M / L. SF only: a bundled font costs memory in a 40 MB budget (competitor survey, feasibility notes) | Regular, M | H | M | P3 |
| Key height | Compact / Standard / Tall (row pitch 50 / 54 / 58). Touches `ProtlyGeometry` and the height pin (`ProtlyLayout.swift:7-13`, `ProtlyHeight.swift:26-30`), which took a full sprint to settle; each preset needs its own CI shot set | Standard | H | L | P3 |
| Protly key glyph | Changes with the action (audit K1), or a fixed protly mark | Changes | K | S | P3 |

### Screen: Bar and actions

| Setting | What it does | Default | No AG | Effort | Priority |
|---|---|---|---|---|---|
| Bar slots | Left, center, right each take one of: Flip, Action, Suggestion, Read clipboard, Empty. Undo always takes the action's slot after an Insert. Today fixed at `ProtlyBar.swift:18-52` | Flip, Action, Suggestion | H | M | P2 |
| Actions shown | Translate, Polish, Read clipboard: each on or off. Off hides it from the bar and the protly key's menu | All on | H | S | P2 |
| Protly key does | Auto (today's `act(nil)`), or a fixed action, or opens the action menu (audit K1) | Auto | H | S | P2 |
| Read clipboard offer | When new (today, `KeyboardViewController.swift:342-351`), Always when the clipboard has text (audit B6), Never | When new | K | S | P2 |
| Action label | "Translate" or "→ English" with the target (audit B5) | With target | K | S | P2 |
| Flip slot shows | Always, When plausible (audit B4), Never | When plausible | K | S | P2 |
| Suggestions | Fixes and completions, Fixes only, Off | Fixes and completions | K | S | P3 |
| Autocorrect on space | Apple-style correction on space with Undo (audit B7) | Off | K | M | P3 |

### Screen: Languages and detection

| Setting | What it does | Default | No AG | Effort | Priority |
|---|---|---|---|---|---|
| New message starts in | Last used (today), Korean, English (`TypingSession.swift:36`) | Last used | K | S | P2 |
| When unsure, prefer | Korean, Balanced, English: a small bias added to one side's score where the prior is added (`LanguageDetector.swift:77-78`). Not `priorBonus` itself: accuracy is flat from 1.0 up (`docs/ios-keyboard-notes.md:22-50`). Each step must be measured with `protly-eval` and the Spanish-flip cases (`docs/research/2026-10-30-spanish-flip.md`, "Fix options") before it ships | Balanced | K | M | P3 |
| Learn from flips | On or off (`LearnedWords`) | On | K | S | P2 |

### Screen: Writing (AI)

| Setting | What it does | Default | No AG | Effort | Priority |
|---|---|---|---|---|---|
| About me | Today's note, edited in one place (`AboutMe.swift`); the keyboard shows "note from the app, n characters" | Empty | H (today's path) | S | P1 |
| Style notes | A second free-text note for how the writer wants English to read ("short sentences", "no exclamation marks"). Wrapped in its own tag like `AboutMe.system` (`AboutMe.swift:70-80`), same cleaning and 1,000-scalar cap, sent with Translate and Polish | Empty | H | M | P2 |
| Default target | The language Translate uses without a prefix, one of `Languages.names` (`Languages.swift:7`); today English (`ActionAPI.swift:174`) | English | H | S | P2 |
| Favorite targets | Up to five languages shown in the protly key's menu, so a target is one tap instead of a typed `ru:` | None | H | S | P3 |
| Prefixes | On or off. Off avoids a draft starting with `es:` being read as a target (`Languages.prefix`) | On | K | S | P3 |
| English register | Match the draft (prompt line 20 and 34 today), Casual, Polite, Formal: one line added to the user message | Match | H | S | P2 |
| Korean speech level for Read clipboard | 반말 (prompt line 4 today), 해요체, 합쇼체 | 반말 | H | S | P2 |
| Spelling | Canadian (prompt line 28 today), US, UK | Canadian | H | S | P2 |
| Punctuation rules | The no-dash, no-semicolon rule (prompt line 30) on or off | On | H | S | P3 |
| Show the Korean check | Back translation for Translate and change notes for Polish shown or hidden (the model writes them either way, prompt lines 12 and 24) | Shown | K | S | P3 |
| Keep-as-is words | Names and terms never translated or "fixed" (competitor survey, idea 7) | Empty | H | M | P3 |
| Speed or quality | Opus for Translate and Polish (today, `ActionAPI.swift:90-92`) or Sonnet for all | Quality | H | S | P3 |

The register, speech level, spelling and punctuation settings change prompt behaviour that the evals check
(`scripts/eval-polish.mjs`, `docs/ios-keyboard-notes.md`, Sprint 7 and 8 runs). Recommend sending them as lines in
the user message (next to `MODE` and `TARGET`, `ActionAPI.swift:167-176`), so the cached system prompt stays the
same and each value gets one eval case.

The fixed writer facts in `keyboard-prompt.txt:1, 11` are personal to the owner. If protly is ever used by someone
else they belong in About me; until then they stay as they are, and this study does not propose a setting for them.

### Screen: Words

| Setting | What it does | Default | No AG | Effort | Priority |
|---|---|---|---|---|---|
| Learned words | List by language with counts, search, swipe to delete, add a word. The keyboard writes a copy to the group when Full Access is on; the app writes delete or add requests the keyboard applies on its next load | - | No | M | P2 |
| Clear learned words | One button; in the keyboard panel without an App Group | - | K | S | P2 |
| Text replacements | A link and a line: protly already uses iOS's text replacements and contact names (`Words.swift:22-33`) | - | - | S | P3 |

### Screen: Privacy and data

| Setting | What it does | Default | No AG | Effort | Priority |
|---|---|---|---|---|---|
| What protly sends | Static page (audit F2): only on an action tap, the field or selection or clipboard text plus the notes, straight to the model API, never keystrokes | - | - | S | P1 |
| Send notes with | Translate and Polish (today, `AboutMe.swift:74`), or Never | Translate and Polish | H | S | P3 |
| Usage | Calls and estimated cost this month (competitor survey, idea 11). Counted in the keyboard, shown in the app with the App Group | On | No (in-keyboard only) | S | P3 |
| Clear keyboard data | Learned words, notes, last language, clipboard marker | - | K | S | P2 |

### Screen: Advanced

| Setting | What it does | Default | No AG | Effort | Priority |
|---|---|---|---|---|---|
| Memory readout | The Sprint 6 debug readout (`Words.swift:10-12`) as a switch instead of a rebuild | Off | K | S | P3 |
| Reset all settings | Back to defaults; does not touch words or notes | - | K | S | P2 |
| API key | Stays a build-time value (`ActionClient.swift:16`). Never in `UserDefaults` or the App Group, which are plain files; a shared Keychain group was never tested on the free team | Build time | - | - | Not proposed |

## 4. App structure, first run and how settings reach the keyboard

### 4.1 Structure

Four tabs. Each stays short; the catalog's screens become sections inside them.

```
 Home            Keyboard              Writing              More
 ─────           ────────              ───────              ────
 Status          Live preview          About me             Words
 Try it field    Feel                  Style notes          Privacy and data
 Quick tips      Look                  Default target       How to use (audit A1)
                 Bar and actions       Register, spelling   Advanced
                 Languages             Keep-as-is words     About protly
```

Rationale: Home answers "is it working" and lets people type at once (audit A4); Keyboard holds everything the
user sees and feels, next to a preview; Writing holds what goes into the model; More holds the rest.

### 4.2 First run

Five short screens, each with one button, skippable after step 2. The HIG asks for exactly this tutorial in the
app (quoted in the audit, "Consider providing a keyboard tutorial in your app").

```
 1 Welcome                2 Add the keyboard         3 Full Access (optional)
┌──────────────────────┐ ┌──────────────────────┐   ┌──────────────────────┐
│        protly        │ │ Add protly           │   │ Actions need Full    │
│                      │ │                      │   │ Access               │
│ Type Korean and      │ │ Settings › General › │   │                      │
│ English on one grid. │ │ Keyboard › Keyboards │   │ Typing works without │
│ Translate or polish  │ │ › Add New Keyboard › │   │ it. Translate,       │
│ before you send.     │ │ Protly               │   │ Polish, Read         │
│                      │ │                      │   │ clipboard need it.   │
│                      │ │ [ Open Settings ]    │   │ What protly sends ›  │
│                      │ │                      │   │                      │
│ [ Set up ]           │ │ Status: ● not seen   │   │ Status: ● limited    │
└──────────────────────┘ └──────────────────────┘   └──────────────────────┘
 4 Try it                 5 About you (optional)
┌──────────────────────┐ ┌──────────────────────┐
│ Type dkssud, then    │ │ A few facts that help│
│ tap the left slot.   │ │ names come out right │
│ ┌──────────────────┐ │ │ ┌──────────────────┐ │
│ │ 안녕|             │ │ │ │                  │ │
│ └──────────────────┘ │ │ └──────────────────┘ │
│ ✓ flip  ○ Translate  │ │ Sent only with your  │
│ ○ ru: prefix         │ │ own drafts.          │
│ [ Next ]             │ │ [ Done ]             │
└──────────────────────┘ └──────────────────────┘
```

"Open Settings" uses `UIApplication.openSettingsURLString` (KeyboardKit wraps it,
`Vendor/.../_Keyboard/Url+SystemSettings.swift:17-37`, and notes the link can land on the Settings root instead of
the app's page).

**Status without an App Group: the probe field.** The app cannot ask iOS whether its keyboard is added or has Full
Access. It can ask the keyboard, through a text field: the app puts a probe string in the field and focuses it;
when the keyboard comes up on a field that holds exactly the probe, it replaces it with its status. Neither side
needs the clipboard, an App Group or Full Access. A sketch, not built or run:

```swift
// Keyboard (viewWillAppear and textDidChange): answer only a field that holds exactly the probe.
static let probe = "protly probe v1"
let p = textDocumentProxy
if p.documentContextBeforeInput == Self.probe, (p.documentContextAfterInput ?? "").isEmpty, !session.isComposing {
    for _ in Self.probe { p.deleteBackward() }
    p.insertText(hasFullAccess ? "protly ok, full access" : "protly ok, limited")
}

// App: the setup field reads the answer, then clears it.
.onChange(of: probeText) { _, new in
    if new.hasPrefix("protly ok") { status = new.hasSuffix("full access") ? .full : .limited; probeText = "" }
}
```

The keyboard edits a field without a keystroke only for this exact string; any app could show the probe, and the
answer reveals only that protly is installed and its Full Access state. With the App Group the keyboard can
instead write a "last seen" time and its Full Access state (writes need Full Access, so "seen, full access" is the
only state it can report that way; the probe covers "limited").

### 4.3 Home

```
┌───────────────────────────────┐
│ protly                        │
│ ┌───────────────────────────┐ │
│ │ ● Keyboard on             │ │
│ │ ● Full Access on          │ │
│ │ ○ About me: empty   Add › │ │
│ └───────────────────────────┘ │
│ Try it                        │
│ ┌───────────────────────────┐ │
│ │ type here                 │ │
│ └───────────────────────────┘ │
│ Tips                          │
│  Flip a word    dkssud → 안녕 │
│  Translate      ru: 고마워    │
│  Read a message copy, tap ⧉   │
│  Emoji          use the globe │
└───────────────────────────────┘
```

The tips are the audit's A1 list, each with a sample that fills the Try it field.

### 4.4 Keyboard tab with a live preview

```
┌───────────────────────────────┐
│ Keyboard                      │
│ ┌───────────────────────────┐ │
│ │ “안녕”    → English   the │ │  ← preview: bar with the chosen slots
│ │ q w e r t y u i o p       │ │    and labels, keys in the chosen
│ │  a s d f g h j k l        │ │    colors and height. Not the real
│ │ ⇧ z x c v b n m ⌫         │ │    keyboard: a drawing.
│ │ 123  ◎  space       ↵     │ │
│ └───────────────────────────┘ │
│ [ Try on the real keyboard ]  │  ← focuses a field: the real thing
│ Feel                       ›  │
│ Look                       ›  │
│ Bar and actions            ›  │
│ Languages                  ›  │
└───────────────────────────────┘
 Bar and actions
┌───────────────────────────────┐
│ Left     [ Flip          ▾ ]  │
│ Center   [ Action        ▾ ]  │
│ Right    [ Suggestion    ▾ ]  │
│ Actions  ☑ Translate          │
│          ☑ Polish             │
│          ☑ Read clipboard     │
│ Protly key [ Auto        ▾ ]  │
│ Label    [ → English     ▾ ]  │
└───────────────────────────────┘
```

Two previews, because neither alone is enough:

- **A drawn preview** in the app, updated on every change, so a color or height choice is seen at once. The app
  target links nothing today (`ios-app/Package.swift:25`; `ProtlyApp.swift:14` repeats AboutMe constants for that
  reason), so the drawing cannot reuse KeyboardKit. Plain SwiftUI rectangles with protly's geometry values are
  enough. Geometry and theme values should then move into ProtlyCore as plain numbers and hex strings (testable on
  Linux), and the app should link ProtlyCore: a one-line `Package.swift` change, which needs the tower.
- **The real keyboard** in a Try field, which shows the truth only after the keyboard has the new values (App Group:
  next appearance; no App Group: after the handoff).

### 4.5 Writing tab

```
┌───────────────────────────────┐
│ Writing                       │
│ About me              212/1000│
│ ┌───────────────────────────┐ │
│ │ ...                       │ │
│ └───────────────────────────┘ │
│ Style notes            48/1000│
│ ┌───────────────────────────┐ │
│ │ short sentences, no "!"   │ │
│ └───────────────────────────┘ │
│ Translate to   [ English ▾ ]  │
│ English tone   [ Match   ▾ ]  │
│ Spelling       [ Canadian▾ ]  │
│ Reading tone   [ 반말    ▾ ]  │
│ Keep as is     3 words     ›  │
│ ── Without an App Group ──    │
│ [ Send to keyboard ]          │  ← only shown when the spike failed
└───────────────────────────────┘
```

### 4.6 How a change reaches the keyboard

**With the App Group (target design).**

- One versioned value, `protly.settings.v1`, a JSON `ProtlySettings` (every field optional; a missing or invalid
  field means the default), in `UserDefaults(suiteName: derivedGroupID)`. The app is its only writer. Notes (About
  me, style notes, keep-as-is words) are separate keys, so a long note does not rewrite the settings blob.
- The keyboard reads it in `viewDidLoad` and again in `viewWillAppear`. iOS reloads the controller for every host
  (`KeyboardViewController.swift:78`), so most changes show on the next keyboard appearance. For the Try field,
  where the keyboard is already up while the app changes a value, the app posts a Darwin notification and the
  keyboard re-reads on it (`CFNotificationCenterGetDarwinNotifyCenter`; to verify from an extension).
- The keyboard parses the blob as untrusted input, as `LearnedWords` already does with its own JSON
  (`LearnedWords.swift:25-30`): unknown keys ignored, out-of-range values clamped, a size cap.
- KeyboardKit's own settings (sound, haptics, autocap) are set from `ProtlySettings` on each load, replacing the
  forced writes at `KeyboardViewController.swift:61-66`. Moving KeyboardKit's store into the group
  (`appGroupId`) is not needed and would make KeyboardKit's own writes fail without Full Access.
- The keyboard writes only its own keys to the group (learned words copy, usage, last seen), only with Full Access,
  and ignores a failed write.

```swift
// ProtlyCore: one value, every field optional, decoded leniently.
public struct ProtlySettings: Codable, Equatable, Sendable {
    public var version = 1
    public var haptics: Haptics?          // off, light, medium
    public var keySound: Bool?
    public var autocapitalization: Bool?
    public var barSlots: [BarSlot]?       // exactly 3, else default
    public var actions: Set<Action>?      // translate, polish, readClipboard
    public var defaultTarget: String?     // a Languages.names code, else English
    public var englishRegister: Register? // match, casual, polite, formal
    // ...
}
```

**Without the App Group (fallback).** "Send to keyboard" builds a settings code: a first line marker
`protly settings v1` and the JSON. It travels by the field handoff (no prompt, no Full Access, to verify) or the
clipboard (today's path, Full Access). `AboutMe.parse` generalises to one parser for both markers; the confirm
panel lists what changes ("Haptics: Light, Default target: Russian") with the same 0.5 s Save delay. Settings
marked K in the catalog also get the in-keyboard panel, opened from the protly key's long-press menu (audit K1),
so the keyboard alone stays usable.

### 4.7 In-keyboard quick settings (both cases)

```
┌───────────────────────────────┐
│ Quick settings           Done │  ← panel in place of the keys,
│ Haptics      ( Off ‹Light› )  │    same height (Panel.swift)
│ Sound        [■ On ]          │
│ Auto-caps    [  Off]          │
│ Start in     ( Last ‹한› EN ) │
│ More in the protly app        │
└───────────────────────────────┘
```

At most five rows, only K settings, no help text (HIG). With the App Group these write nothing: the panel shows the
app's values read-only with "Change in the protly app", because the keyboard cannot write the group without Full
Access and two writers would conflict.

## 5. Suggested order

1. **Spike: App Group on the free team** (1 day, tower: `xtool.yml`, entitlements). Pass: the keyboard reads a value
   the app wrote, with Full Access off and on, on the phone. The answer picks between the two columns of 1.4.
2. **App restructure and first run** (M-L): tabs, onboarding, Open Settings, the probe status, "What protly sends",
   tips with samples. Covers audit F2, A1, A2, A4.
3. **P1 settings**: haptics, key sound, auto-caps, About me in one place.
4. **P2 settings**: bar slots and actions, default target, register and spelling (with one eval case each), style
   notes, learned words list, Read clipboard offer, flip slot display, start language, theme presets and key colors
   with the drawn preview.
5. **P3**: key height presets (with CI shot sets), long-press delay, pop-ups, detector bias (with eval runs),
   glossary, usage meter, speed or quality.

## Open questions

- Does the first xtool release with #284 sign protly's app and extension with the same group, and does the derived
  group ID match what the profile holds? (Spike.)
- Can the keyboard read the group with Full Access off on iOS 26 and 27, as Apple's page says? (Spike.)
- Field handoff and probe: is `documentContextBeforeInput` filled when the keyboard appears on a pre-filled field,
  before any keystroke, and how long a code does it return? (Phone or simulator check.)
- Darwin notifications between the app and a keyboard extension: delivered while the keyboard is up in the app's
  own field? (Simulator check.)
- Linking ProtlyCore into the app target: any effect on the phone build or app size? (`xtool dev build`, tower.)
- Who else will use protly? If only the owner, the prompt's writer facts and the API key can stay build-time; if
  others, they move to About me and a key entry flow, which brings the Keychain question back.
