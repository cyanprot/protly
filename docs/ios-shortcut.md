# iOS Shortcut: Protly

Renamed from IG Translate on 2026-10-28; the phone names are `Protly read` and `Protly write` (the phone is canonical). A phone whose
write wrapper still runs `IG Translate` must re-pick its Run Shortcut target after the read shortcut is renamed.

Translates chats in any iPhone app (built for Instagram DMs; KakaoTalk, iMessage, WhatsApp, Discord and the rest work the same way), plus any other screen with text: a post, a web page, an email. It only sends a screenshot, so it does not care which app is open. Double-tap the back of the phone:

- Clipboard holds Korean: it is your draft. The translation goes to the clipboard, the Korean back translation shows as a notification.
- Clipboard holds English prose: it is polished (spelling, grammar, structure, stronger words) and copied back.
- Otherwise: the friend's latest non-Korean messages on screen are translated to Korean and shown in an alert.

The shortcut sends a screenshot (720 px wide JPEG) plus your memos straight to the Claude API. No prot, no VPN.
Request body: `ios/body-template.json`, generated from `ios/system-prompt.txt` by `node scripts/build-ios-template.mjs`.
Checked against the live API with `node scripts/eval-ios.mjs <screenshot.jpg>` (synthetic screen `scripts/fixtures/ios-dm.html`).
A phone-friendly copy of this guide with copy buttons is published as a private claude.ai Artifact.

## Quick install (signed file)

`ios/protly.cherri` is the same shortcut as code. `scripts/build-ios-shortcut.sh` compiles it with Cherri v2.3.0 (`~/.local/opt/cherri-2.3.0/cherri`), signs it through HubSign (no Mac here; the file holds no key and no memos) and copies `Protly read.shortcut` and `Protly write.shortcut` to `~/GoogleDrive/`.

On the iPhone: Google Drive app > `Protly read.shortcut` > Share > Shortcuts > Add Shortcut. Edit the shortcut: paste the API key over `PASTE_API_KEY_HERE` in the first Text action (an alert says so if it is missing). Then edit the long Text action that starts with `(none) Replace this line` to hold your memos, and set up Back Tap (section 2). Section 0 still applies for the key.

Cherri v2.3.0 quirks found while writing it: a `rawAction` whose result is assigned loses its identifier (custom `action` definitions are used instead); an import question is bound only to action 0 (and on the phone the key from the import question never reached the request, so the key is now a placeholder Text action with a `sk-ant-` guard); multi-line default blocks in user `action` definitions fail to parse; a string cannot end in a backslash; conditions need a text constant on the left.

The build sends `anthropic-workspace-id` (the laptop's workspace, from `~/.config/anthropic/configs/default.json`): the user's phone key turned out to be org-level, and the API rejected it without the header (2026-10-28).

The manual build below is the fallback.

## 0. Before you start

1. On the phone, open console.anthropic.com. Create a workspace `iphone` with a monthly spend limit (for example $5). Create an API key inside it named `iphone-shortcut` and copy it. A key made inside a workspace needs no workspace header.
2. Settings > Apps > Shortcuts > Paste from Other Apps: Allow.

Never share this shortcut: the key travels with it. With iCloud sync on, the shortcut (and key) is in iCloud; it is end-to-end encrypted only with Advanced Data Protection.

## 1. Build the shortcut

New shortcut, name `Protly read`. Add these actions in order. "Regex ON" means the Regular Expression switch in Replace Text (tap Show More).

| # | Action | Settings |
|---|---|---|
| 1 | Get Clipboard | |
| 2 | Match Text | pattern `[가-힣ㄱ-ㆎ]` in Clipboard |
| 3 | If | Matches has any value |
| 4 | Text (inside If) | `MODE: out`, blank line, `DRAFT:`, new line, then the Clipboard variable |
| 5 | Otherwise: Text | `MODE: in` |
| 6 | End If | its output is the variable "If Result" |
| 7 | Text | your memos, one friend per line: `Name (handle): who they are, gender, reply language, tone` |
| 8 | Text | `PEOPLE:`, new line, Text (step 7), blank line, If Result |
| 9 | Replace Text, regex ON | find `\\` replace `\\\\` in Text (step 8) |
| 10 | Replace Text, regex ON | find `"` replace `\\"` in Updated Text |
| 11 | Replace Text, regex ON | find `\n` replace `\\n` in Updated Text |
| 12 | Replace Text, regex ON | find `[\x00-\x1F]` replace with one space, in Updated Text |
| 13 | Set Variable | `Escaped` = Updated Text |
| 14 | Take Screenshot | |
| 15 | Resize Image | Screenshot, width 720, height Auto |
| 16 | Convert Image | Resized Image to JPEG, quality about 70%, Preserve Metadata off |
| 17 | Base64 Encode | Converted Image, Line Breaks: None |
| 18 | Text | paste `ios/body-template.json` exactly (one line) |
| 19 | Replace Text, regex OFF | find `{{TEXT}}` replace with `Escaped`, in Text (step 18) |
| 20 | Replace Text, regex OFF | find `{{IMAGE_B64}}` replace with Base64 Encoded, in Updated Text |
| 21 | Get Contents of URL | `https://api.anthropic.com/v1/messages`, Method POST, Headers `x-api-key` = your key, `anthropic-version` = `2023-06-01`, `content-type` = `application/json`; Request Body: File = Updated Text (step 20) |
| 22 | Get Dictionary Value | `type` in Contents of URL |
| 23 | If | Dictionary Value is `error` |
| 24 | Get Dictionary Value, Show Alert, Stop This Shortcut (inside If) | `error.message` in Contents of URL; alert shows it |
| 25 | End If | |
| 26 | Get Dictionary Value | `stop_reason` in Contents of URL |
| 27 | If | Dictionary Value is not `end_turn`: Show Alert `Stopped: ` + Dictionary Value, Stop This Shortcut; End If |
| 28 | Get Dictionary Value | `content` in Contents of URL |
| 29 | Get Item from List | Last Item |
| 30 | Get Dictionary Value | `text` in Item from List |
| 31 | Get Dictionary from Input | Dictionary Value |
| 32 | Set Variable | `Result` = Dictionary |
| 33 | If | If Result contains `MODE: out` |
| 34 | inside If | Get Dictionary Value `translation` in Result; Copy to Clipboard; Get Dictionary Value `back_translation` in Result; Show Notification title `[out] copied`, body = that value |
| 35 | Otherwise | Get Dictionary Value `translation` in Result; Show Alert title `[in]`, message = that value |
| 36 | End If | |

Model split (same as the extension): the template is MODE in, Sonnet with thinking off (`between_tools`). Right after Set Variable `template`, an If `mode` is not `in` block runs Replace Text `claude-sonnet-5-5` -> `claude-opus-5-5` and `between_tools` -> `adaptive`, each followed by Set Variable `template` to Updated Text.

Why the escaping: Shortcuts has no JSON-escape action. Steps 9 to 12 turn the memos and draft into a valid JSON string (backslash first, then quotes, newlines, and any other control character to a space). Steps 19 and 20 must have regex OFF, or `\\` and `$` in the text get rewritten.

## 2. Back Tap

Settings > Accessibility > Touch > Back Tap > Double Tap > Protly.

## 3. First run and phone test

Run it once from the Shortcuts app and pick Always Allow for `api.anthropic.com`.

1. Incoming: open a DM where the friend wrote in English or Russian. Double-tap. Expect an `[in]` alert in Korean.
2. Outgoing: type a Korean draft with a `"` and a line break in the composer, Select All, Copy, triple-tap. Expect `[out] copied`. Select All, Paste, and check before sending.
3. Error path: change one character of the key, run. Expect an alert naming the invalid key. Put the key back.

## Daily use

- Mode comes from the tap, never from the clipboard (a leftover copy used to send every run to write mode): double tap = read the screen, triple tap = write (`Protly write` runs `Protly read` with the input `write`). Install both files; Back Tap > Double Tap = Protly read, Triple Tap = Protly write. Keep the main shortcut named exactly `Protly read`: the Run Shortcut action in `Protly write` targets it by name, so after a rename re-pick the target there.
- Read: open the chat, double-tap the back.
- Group chats and apps that left-align everyone (Discord, Slack): add a memo line `Me: your name (handle)` so the shortcut knows which messages are yours. Without it, only two-sided chats (mine on the right) are reliable.
- Not a chat (a post, article, email): the main text on screen is translated, menus and ads are skipped.
- Write: type Korean, Select All, Copy, triple-tap, Select All, Paste, send.
- Target language: start the draft with a language code and a colon (`en:`, `ru:`, `ja:`) to pick it for that message. Without a prefix: the memo reply language, else the friend's language on screen, else English.
- The `[out]` notification shows the translation first, then `KO:` with the back translation.
- Polish English: copy English text (more than one word), triple-tap. The improved text is copied, the notification `[fix] copied, paste it` shows it with a short Korean list of the main changes. The rules are the CyanStyle voice from the user's own `cyanprot/humanizer` repo (style guide plus Vale lists), cut to a few lines: Canadian spelling, no em or en dash, semicolon or slash, the banned phrase lists. The full humanizer pipeline (linter, reference passages, claim check) does not run on the phone.
- Results the shortcut copies expire from the clipboard after 3 minutes, so a leftover English result does not turn the next run into a polish run. Within those 3 minutes a run on new incoming messages would polish the old result instead; wait, or copy something else first.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Alert about invalid JSON (400) | Base64 Line Breaks not None, or a regex switch wrong in steps 9 to 12 / 19 to 20 |
| Alert `invalid x-api-key` | Key typo, or the key was revoked |
| Alert about the workspace header | The key was made outside a workspace. Make it inside the `iphone` workspace |
| `[out]` when you wanted `[in]` | Old Korean text was still on the clipboard. Copy anything else first |
| Nothing happens on double tap | Back Tap needs firm taps; some thick cases block it |
