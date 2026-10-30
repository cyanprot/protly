# Competitor survey: where protly can beat Grammarly for a Korean and English writer

Date: 2026-10-30. Research only: no code changed.

## Scope and method

- Products: Grammarly Keyboard and Grammarly for Chrome, Gboard, Apple's keyboard with Writing Tools and Apple
  Intelligence, Microsoft SwiftKey, DeepL (app, Write), Naver Papago (and Naver SmartBoard, Naver's keyboard),
  Samsung Keyboard with Galaxy AI, and three newer keyboards: Catchtype, Wispr Flow and CleverType.
- Sources: official pages and App Store listings first, read on 2026-10-29/30. Where only a third-party page was
  found, the claim says so. Every claim carries its URL.
- App Store pages often print dates without a year ("Oct 23"). Those dates are given as printed. Review samples on
  App Store pages are the handful the page shows, not a full review analysis.
- Tap counts come from the vendor's own steps where they were found; where they were not, the count is an
  estimate and says so. "Tap" counts each touch after the text is written, up to the result being in the field.
- Not reached: Grammarly's help article for the iOS keyboard, Apple's Writing Tools and multilingual-typing guide
  pages (the fetch returned only the guide's table of contents), and Apple's `UITextDocumentProxy` reference
  (title only). Claims that would have come from those pages are marked as estimates or unverified.

## Protly today (baseline)

What the repo ships, from its own plans and notes:

- One QWERTY grid; keycaps switch per word between English letters and Dubeolsik jamo, decided by an on-device
  detector; a space-bar flick flips the last word (`docs/plans/2026-10-28-ios-keyboard-design.md`, "Automatic
  language per word").
- Predictive bar: completions while typing; with a finished draft the centre slot offers one action, Translate
  (Korean draft) or Polish (English draft); an empty field offers Read clipboard (same file, "Predictive bar";
  `docs/ios-keyboard-notes.md`, "Sprint 5: actions").
- Panel at the key area's height: result, back translation for Translate, Insert, Cancel; Undo after Insert
  (design doc, "Panel").
- Writing style rules for English output and an about-me note sent with Translate and Polish
  (`docs/plans/2026-10-28-ios-keyboard.md`, "Sprint 7").
- A language-code prefix (`ru: 노트 고마워`) translates a Korean draft into one of 46 target languages; `ko:`
  polishes a Korean draft in Korean (same plan, "Sprint 8").
- Privacy and cost model: the keyboard calls the Anthropic Messages API directly with a key baked in at build time;
  there is no protly server; actions need Full Access, typing does not (design doc, "Architecture", "Errors";
  plan, "Design amendments" 1).
- Distribution: built with xtool and a free Apple ID (7-day profile), not on the App Store (plan, header and
  "Design amendments").
- Chrome extension: Instagram DMs and Gmail drafts, Alt+T on the focused box (`manifest.json`), with the recent
  conversation and a per-thread memo in the prompt (`src/lib/prompts.js`).

## Product survey

### Grammarly Keyboard (iOS)

- **Features.** Spelling, grammar and conciseness suggestions "in 20+ languages", "Typing in 6 languages", voice
  dictation with cleanup, tone detection, tone transformations and vocabulary/clarity suggestions (Premium only),
  generative rewrites "in 20+ languages". App now sold by Superhuman Platform Inc., version 16.1.0, rating 4.7 from
  228K ratings. https://apps.apple.com/us/app/grammarly-ai-keyboard-voice/id1158877342
- **Translation.** The App Store description does not mention translation
  (https://apps.apple.com/us/app/grammarly-ai-keyboard-voice/id1158877342), but a third-party release tracker quotes
  a May 2026 note "Translate text right from the keyboard without switching apps"
  (https://releases.sh/superhuman/grammarly.md). Treat keyboard translation as shipped but not documented.
- **Trigger, taps to result.** Not verified (help article not reached). Estimate: Grammarly button in the
  keyboard toolbar, pick a rewrite or tone, accept: about 3 taps.
- **Korean.** The keyboard types English, French, German, Italian, Portuguese and Spanish only; Korean is not in
  the listing's languages (https://apps.apple.com/us/app/grammarly-ai-keyboard-voice/id1158877342). So a Korean
  writer must leave Grammarly's keyboard to type Hangul. Korean grammar and spelling support arrived on
  2026-03-11 as a beta for the browser extension and desktop app, "grammar and error correction for now", with
  fluency, clarity and tone "soon" (https://www.grammarly.com/blog/product/multilingual-support-in-additional-languages/).
- **Privacy.** App Store labels: "Data Used to Track You" includes contact info, identifiers and usage data; user
  content (texts, audio) is collected, not linked
  (https://apps.apple.com/us/app/grammarly-ai-keyboard-voice/id1158877342). Grammarly says it does not sell data and
  lets users opt out of training ("Product Improvement and Training"); no training on EU/UK accounts
  (https://grammarly.com/privacy). Full Access is required, and reviewers object to it
  (https://apps.apple.com/us/app/grammarly-ai-keyboard-voice/id1158877342).
- **Price.** Web: Free (100 AI prompts/month) and Pro at "$12" (billing basis not shown on the page; 2,000
  prompts/month) (https://www.grammarly.com/plans). Third-party pages put it at $12/month billed annually or $30
  monthly (https://www.eesel.ai/blog/grammarly-ai-pricing). App Store in-app prices: $29.99 monthly, $139.99
  annual, "Mobile Only" $17.99 monthly or $83.99 annual
  (https://apps.apple.com/us/app/grammarly-ai-keyboard-voice/id1158877342).
- **Top complaints.**
  - Lag and missed keystrokes compared with the stock keyboard; behaviour depends on connection quality
    (https://justuseapp.com/en/app/1158877342/grammarly-grammar-keyboard/reviews;
    https://unstar.app/blog/gboard-swiftkey-grammarly-fleksy-typewise-keyboard-apps-ranked-2026, a third-party
    ranking).
  - Paywall nags ("You're all out of samples") and the best suggestions Premium-only
    (https://apps.apple.com/us/app/grammarly-ai-keyboard-voice/id1158877342).
  - Wrong corrections (suggesting "coincidence" for "convenience") and the Full Access requirement
    (https://apps.apple.com/us/app/grammarly-ai-keyboard-voice/id1158877342).
  - No swipe typing; no keyboard features with a Bluetooth keyboard
    (https://justuseapp.com/en/app/1158877342/grammarly-keyboard/reviews).

### Grammarly for Chrome

- **Features.** Drafts, rewrites, tone and word-choice changes, plagiarism and AI-content checks, citations;
  rating 3.9 from 43.2K ratings, 40,000,000 users, updated 2026-10-28
  (https://chromewebstore.google.com/detail/grammarly-ai-writing-and/kbfnbcaeplbcioakkpcpgfkobkghlhen).
- **Translation.** Pro: highlight text, select "Translate", choose the language, "Accept", in "19 languages";
  the free web translator takes 5,000 characters on Grammarly's page only (https://www.grammarly.com/translation).
- **Trigger, taps to result.** Translate in Chrome: highlight, Translate, pick language, Accept: 4 actions
  (https://www.grammarly.com/translation).
- **Korean.** Korean is a translation language (https://www.grammarly.com/translation); writing support is the
  grammar-only beta above (https://www.grammarly.com/blog/product/multilingual-support-in-additional-languages/).
- **Privacy.** Chrome Web Store disclosure: personal communications, website content, user activity and location
  (https://chromewebstore.google.com/detail/grammarly-ai-writing-and/kbfnbcaeplbcioakkpcpgfkobkghlhen).
- **Price.** Same plans as above (https://www.grammarly.com/plans).
- **Top complaints.**
  - Slow in Gmail's composer, a 2016 report closed as WONTFIX (https://bugzilla.mozilla.org/show_bug.cgi?id=1258946);
    Grammarly's own list of sites with known issues (https://support.grammarly.com/hc/en-us/articles/360041953832-Known-issues-on-websites).
  - Too formal for casual writing and stylistic changes that miss the intended tone (a G2 review:
    https://aws.amazon.com/marketplace/reviews/reviews-list/prodview-34k35moukptwm?page=76).
  - Built for native speakers: in one test of a Korean writer's English, Grammarly's output still did not sound
    native (https://blog.engram.us/best-ai-proofreader-grammarly-quillbot-engram-trinka, a competitor's blog).

### Gboard (iOS)

- **Features.** GIF, emoji and sticker search, glide typing, Google Search in the keyboard; latest version 2.3.19
  of 2022-05-02 (https://apps.apple.com/us/app/gboard-the-google-keyboard/id1091700242). Wikipedia lists the iOS
  version as discontinued (https://en.wikipedia.org/wiki/Gboard).
- **AI writing.** Gemini Nano proofread and rephrase are Android only (Pixel 10, then select Android phones)
  (https://www.androidauthority.com/pixel-10-gboard-writing-tool-3589264;
  https://www.androidauthority.com/gboard-writing-tools-upgrade-3668502/). Nothing on iOS.
- **Translation and taps.** Translate (all Google Translate languages) arrived in 2019 and is in the old release
  notes, no longer in the description (https://apps.apple.com/us/app/gboard-the-google-keyboard/id1091700242;
  https://www.engadget.com/2019/03/15/google-gboard-ios-keyboard-translate/). Flow from 2019 coverage: open the G
  menu, Translate, pick languages, type into Gboard's own box, result goes into the field
  (https://www.businessinsider.nl/how-to-use-gboard-translate-on-iphone/): about 2 taps plus typing in a separate box.
- **Korean.** Korean is a supported typing language
  (https://apps.apple.com/us/app/gboard-the-google-keyboard/id1091700242).
- **Privacy.** "Gboard doesn't send anything you type to Google" except searches and voice input; App Store labels
  list audio data and device ID linked to the user
  (https://apps.apple.com/us/app/gboard-the-google-keyboard/id1091700242).
- **Price.** Free (https://apps.apple.com/us/app/gboard-the-google-keyboard/id1091700242).
- **Top complaints.** Abandoned on iOS: no meaningful update in years
  (https://gadgets.beebom.com/stories/i-want-google-to-fix-gboard-on-ios-app); dictation bugs (first word lowercase,
  mic icon intermittent) (https://apps.apple.com/us/app/gboard-the-google-keyboard/id1091700242).

### Apple keyboard, Writing Tools and Apple Intelligence

- **Features.** Writing Tools: rewrite, proofread, summarize, with tones and a free-text "describe your change"
  (https://www.igeeksblog.com/how-to-use-writing-tools-on-iphone-ipad/, third-party how-to). Apple's page now
  advertises proofreading "as you type" and drafts that "match your writing style" through Siri AI
  (https://www.apple.com/apple-intelligence/).
- **Trigger, taps to result.** Select text, open the edit menu or the Apple Intelligence icon at the top of the
  keyboard, pick Rewrite or a tone, then Done
  (https://www.igeeksblog.com/how-to-use-writing-tools-on-iphone-ipad/;
  https://support.apple.com/en-hk/guide/ipad/ipad04c3f67f/ipados): about 4-5 taps including the selection.
- **Translation.** Live Translation translates incoming and outgoing texts inside Messages; Korean is one of its
  languages (https://support.apple.com/en-us/121115; https://www.macrumors.com/how-to/ios-live-translation-in-messages/).
  It is automatic once on, but only in Messages, FaceTime and Phone (https://www.apple.com/apple-intelligence/).
- **Korean.** Apple Intelligence supports Korean (https://support.apple.com/en-us/121115); at the Korean launch
  not all English features were available in Korean (https://www.koreaherald.com/article/10467676). Typing Korean
  and English still means two keyboards and the globe key; users ask to limit the globe cycle to just those two
  (https://forums.imore.com/ask-question/377131-how-may-i-set-keyboard-setting-so-i-can-save-time-pressing-globe-button.html).
  Whether iOS multilingual typing covers Korean plus English is unverified (only a 2016 article claims it:
  https://www.ubergizmo.com/2016/06/ios-10-easy-multilingual-typing).
- **Privacy.** On-device models plus Private Cloud Compute: "Your data is never stored", "Used only for your
  requests" (https://www.apple.com/apple-intelligence/).
- **Price and devices.** Free with the device, but only iPhone 15 Pro and later
  (https://www.apple.com/apple-intelligence/). Server features have daily usage limits
  (https://support.apple.com/en-us/121115).
- **Top complaints.**
  - Not available in Instagram, WhatsApp, Facebook, Threads and Messenger
    (https://www.macrumors.com/2025/04/17/apple-intelligence-not-available-in-meta-apps/). Instagram is protly's
    main target.
  - It replaces the original text instead of suggesting (https://kirkville.com/the-big-problem-with-apples-ai-writing-tools/).
  - Proofreading was not real time (https://www.digitaltrends.com/?p=3662211); "basically useless" threads
    (https://forums.macrumors.com/threads/writing-tools-are-basically-useless.2476764/); some users cancelled
    Grammarly for it (https://talk.macpowerusers.com/t/are-you-happy-with-apple-intelligence/39338).
  - iOS 26 keyboard lag and autocorrect complaints, 600+ comments on one Reddit thread
    (https://www.techradar.com/phones/ios/youre-not-bad-at-typing-ios-26s-autocorrect-is-broken-and-theres-still-no-fix-in-ios-26-2).

### Microsoft SwiftKey (iOS)

- **Features.** Copilot, emoji, "Tone change", swipe typing; version 4.3.7; rating 4.6 from 122K
  (https://apps.apple.com/us/app/microsoft-swiftkey-ai-keyboard/id911813648). Translator is not on the iOS listing
  (same URL); it is documented for Android (https://clevertype.co/post/best-swiftkey-alternative-with-ai-writing-features,
  a competitor's blog).
- **Trigger, taps to result.** Copilot icon, Tone, pick Professional/Casual/Polite/Social Post, Replace; Microsoft
  account sign-in required (https://support.microsoft.com/en-us/swiftkey-keyboard/how-to-use-tone-in-microsoft-swiftkey-keyboard):
  about 4 taps.
- **Korean.** iOS languages: English, French, German, Italian, Portuguese, Spanish; no Korean
  (https://apps.apple.com/us/app/microsoft-swiftkey-ai-keyboard/id911813648). Tone quality varies by language
  (https://support.microsoft.com/en-us/swiftkey-keyboard/how-to-use-tone-in-microsoft-swiftkey-keyboard).
- **Privacy.** Email, user ID and device ID linked to the user; typed content collected, not linked
  (https://apps.apple.com/us/app/microsoft-swiftkey-ai-keyboard/id911813648).
- **Price.** Free with in-app purchases (https://apps.apple.com/us/app/microsoft-swiftkey-ai-keyboard/id911813648).
- **Top complaints.** Toolbar AI button clutter; Full Access needed for swiping; only two languages at once
  (https://apps.apple.com/us/app/microsoft-swiftkey-ai-keyboard/id911813648).

### DeepL (iOS app, Write)

- **Features.** Text, voice, camera and file translation, alternatives, glossary and formal/informal tone (paid),
  DeepL Write suggestions; rating 4.8 from 13K (https://apps.apple.com/us/app/deepl-translate-write/id1552407475;
  https://www.deepl.com/en/ios-app). No keyboard extension (both URLs).
- **Trigger, taps to result.** In-app only: copy, switch to DeepL, paste, translate, copy, switch back, paste,
  about 7 steps (derived from the in-app-only flow at https://www.deepl.com/en/ios-app). A share-sheet route needs
  a third-party app (https://apps.apple.com/np/app/multi-translators-with-deepl/id1672159079).
- **Korean.** Korean translation since 2023 (https://www.deepl.com/en/press-release/deepl-translator-adds-korean-and-norwegian-bokml);
  DeepL Write lists Korean among nine languages "as of 2026" (https://www.deepl.com/en/blog/introducing-deepl-write).
- **Privacy.** Free: texts are processed "to train and improve our neural networks"; Pro: kept only temporarily,
  never used for training (https://www.deepl.com/en/privacy; https://www.deepl.com/en/pro).
- **Price.** Individual €7.49/month billed annually (300,000 characters); Write Pro add-on €6.99/month
  (https://www.deepl.com/en/pro).
- **Top complaints.** Invented details such as pronouns and gender in translations; price; a removed dictionary
  feature (https://apps.apple.com/us/app/deepl-translate-write/id1552407475).

### Naver Papago and Naver SmartBoard

- **Papago features.** Text, image, voice, offline, conversation, handwriting, website and document translation,
  14 languages, free; version 1.13.1 (https://apps.apple.com/us/app/naver-papago-ai-translator/id1147874819). No
  keyboard (same URL). Papago Plus is a separate paid business app for documents and glossaries
  (https://apps.apple.com/app/id6743303161), from $9.99 (https://papago-plus.com/pricing/comparison, vendor page,
  not re-checked).
- **Papago trigger.** In-app copy-and-paste round trip like DeepL
  (https://apps.apple.com/us/app/naver-papago-ai-translator/id1147874819).
- **Papago Korean.** Naver's home language; a user reports an honorific option
  (https://apps.apple.com/us/app/naver-papago-ai-translator/id1147874819).
- **Papago privacy.** Identifiers used to track; email, name, phone number, user ID linked
  (https://apps.apple.com/us/app/naver-papago-ai-translator/id1147874819).
- **Papago complaints.** Honorific output got less formal; cognates instead of native words ("마른" for maroon);
  image translation resets the source language
  (https://apps.apple.com/us/app/naver-papago-ai-translator/id1147874819).
- **SmartBoard (Naver's keyboard).** Translation into English, Chinese and Japanese while typing Korean, spell
  check, saved phrases, five Korean layouts, free; version 1.13.9; rating 3.4 from about 8.4K; news, weather,
  search and OCR were removed in 2025; claims it "does not collect any information about keyboard input"
  (https://apps.apple.com/kr/app/id1297816298). Complaints: the keyboard disappears, removed features, paste
  notifications (same URL).

### Samsung Keyboard with Galaxy AI (Android, for reference)

- **Features.** Writing assist: Chat translation, Composer, Writing style, Spelling and grammar
  (https://www.samsung.com/us/support/answer/ANS10000943/). Since One UI 7 it is no longer tied to Samsung Keyboard
  (https://www.phonearena.com/news/Samsungs-One-UI-7-frees-Galaxy-AI-writing-tools-from-its-own-keyboard_id167226).
- **Trigger.** "Tap the Writing assist ... icon (the three stars) on the keyboard's toolbar", then the tool, then
  apply: about 3 taps (https://www.samsung.com/us/support/answer/ANS10000943/).
- **Korean.** One of 16 supported languages (https://www.samsung.com/us/support/answer/ANS10000943/).
- **Privacy.** The support pages do not state on-device or cloud processing for Writing assist
  (https://www.samsung.com/us/support/answer/ANS10000943/;
  https://www.samsung.com/uk/support/mobile-devices/how-to-use-galaxy-ai-features-on-writing-assist/). Unverified.
- **Price.** Basic Galaxy AI features free; enhanced features "may be subject to fees"
  (https://www.samsung.com/us/support/answer/ANS10000943/).
- **Complaints.** Not researched: Android only, so not an option for an iPhone user. It matters as a design
  reference: Korean chat translation in the keyboard is a mainstream feature in Korea's best-selling phones.

### Newer keyboards

- **Catchtype** (closest to protly's grid). "Korean & English, no switching": decides word by word, fixes
  `deploy했는데`, `ㅋㅋㅋ`, "Leaves text alone when unsure"; every decision on device; Full Access optional; "Data
  Not Collected"; free; no AI features; first version 1.0 dated Oct 19, now 1.1.9, 3 ratings
  (https://apps.apple.com/app/id6822543636). Complaints so far: asked for haptics (same URL).
- **Wispr Flow.** Voice keyboard with "AI-polished output", personal dictionary; "100+ languages" but the
  listing names only English; $15/month or $143.99/year; identifiers and usage data used to track
  (https://apps.apple.com/us/app/id6497229487). Complaints: the app reopens and you swipe back each time, the mic
  stays live, the price (same URL). The reopen complaint matches Apple's rule that keyboards cannot use the
  microphone (https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html).
- **CleverType.** Grammar fix, 13 tones plus custom tones, reply suggestions, translation in the keyboard; Full
  Access "required for any AI feature"; text goes to its own servers in India and is deleted after the result; no
  refunds (https://clevertype.co/; https://clevertype.co/privacy-policy). Price not rendered on its site. Most
  "best AI keyboard 2026" lists that rank it are vendor blogs (https://clevertype.co/post/best-ai-keyboard-apps-for-iphone-in).

## Taps to result (rewrite or translate an already-typed draft)

| Product | Rewrite / polish | Translate outgoing | Korean typing in the same keyboard |
|---|---|---|---|
| protly | 2 (Polish, Insert) | 2 (Translate, Insert) | yes, same grid |
| Grammarly Keyboard | about 3 (estimate) | about 3 (estimate, undocumented) | no |
| Grammarly for Chrome | 3-4 | 4 (highlight, Translate, language, Accept) | n/a |
| Apple Writing Tools | about 4-5 incl. selection | Messages only (automatic) | no, globe key |
| Gboard iOS | none | about 2 plus retyping in its box | yes, separate layout |
| SwiftKey iOS | about 4, sign-in | not on iOS | no |
| DeepL / Papago | about 7 (app round trip) | about 7 | n/a |
| SmartBoard | none found | in keyboard (EN/ZH/JA) | yes, separate layout |
| Samsung (Android) | about 3 | about 3 | yes, separate layout |
| Catchtype | none | none | yes, auto per word |

Protly counts: `docs/plans/2026-10-28-ios-keyboard-design.md` ("Panel"). Others: the product sections above.

## Gap table

### What they do that protly does not

| Capability | Who | Can a keyboard extension do it? |
|---|---|---|
| Suggestions underlined as you type (real-time proofreading) | Grammarly, Apple | Partly: a keyboard cannot draw in the host app, only in its own bar |
| Tone presets (formal, casual, polite, custom) | Grammarly (Premium), SwiftKey, Apple, CleverType | Yes |
| Voice dictation | Grammarly, Wispr Flow, Gboard | No microphone in keyboards; apps bounce to the container app |
| Swipe / glide typing | Gboard, SwiftKey | Yes (heavy work) |
| Automatic translation of incoming messages | Apple (Messages), Samsung | No: a keyboard cannot see the chat |
| Works with no network / on device | Apple (on device), Catchtype | Typing yes; AI actions no |
| Camera, document and voice translation | DeepL, Papago | Not in a keyboard |
| Glossary (terms kept or forced) | DeepL (paid), Papago Plus | Yes |
| Explanations of each fix | Grammarly cards | Yes, in the panel |
| App Store distribution, accounts, sync | all | Needs the paid Apple program |
| Works without Full Access | Catchtype (fully) | protly typing yes, actions no |

Sources: the product sections above; keyboard limits from
https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html.

### What protly does that they do not

| Capability | Closest rival and its gap |
|---|---|
| Korean and English on one grid, chosen per word | Catchtype does the grid but has no AI; Grammarly and SwiftKey cannot type Korean; Apple needs the globe key |
| Prefix-driven target: `ru: ...` sends a Korean draft to any of 46 languages | Gboard iOS and SmartBoard translate but pick languages in menus; SmartBoard only EN/ZH/JA |
| `ko:` Korean polish inside the keyboard | Grammarly Korean is a grammar-only beta in the browser and desktop, not the keyboard |
| Back translation into Korean next to the result | none of the surveyed keyboards documents one |
| About-me note and the writer's own style rules in every call | Apple and Grammarly offer generic tones; Wispr has a dictionary, not a style |
| Read clipboard into Korean from the keyboard | Apple's Live Translation only in Messages; DeepL and Papago need an app switch |
| Works in Instagram on any iPhone | Apple Writing Tools is blocked in Meta apps and needs an iPhone 15 Pro or later |
| Extension uses the DM conversation and a per-thread memo | Grammarly for Chrome works on the box alone |
| No subscription, no vendor server between the writer and the model | Grammarly $12-30/month; CleverType and Wispr route through their servers |

Protly side: the baseline section. Rival side: the product sections above.

## Where protly can beat Grammarly

1. **Korean is Grammarly's blind spot on iPhone.** Its keyboard cannot type Hangul and its Korean support is a
   grammar-only browser beta. Every Korean message is typed outside Grammarly. Protly covers both languages in one
   keyboard, which is the single strongest position.
2. **Fewer taps, one action.** Two taps against about three plus Premium gates.
3. **Meaning check in the writer's first language.** Back translation into Korean is something an English-first
   tool will not build.
4. **Personal voice, not presets.** Style rules and the about-me note against generic tones.
5. **Price and privacy story.** Pay per call, no tracking labels, no middle server.

Weak spots to keep in mind: no real-time underlines, no tone presets yet, no voice, latency of about 1.5 s per call
without streaming (`docs/ios-keyboard-notes.md`, "Sprint 2: bare spike"), and Catchtype now gives the same mixed
grid free and offline.

## Feature ideas, ranked

Feasibility notes use these facts: actions already need Full Access for the network; without Full Access a
keyboard has no network, no shared container and no pasteboard; keyboards cannot use the microphone, select text
in the host or type in secure fields
(https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html).
Community measurements put the memory ceiling around 50-60 MB (https://dev.to/tbds_2dadf2b626f315902eae/the-three-hard-constraints-of-an-ios-keyboard-extension-46af,
unofficial); protly's own budget is 40 MB (`docs/plans/2026-10-28-ios-keyboard.md`, Sprint 6 decision 7).

1. **Back translation for Polish too.**
   What: show a short Korean gloss of the polished English under the result, as Translate already does.
   Why it beats Grammarly: the writer checks the meaning in Korean before sending; Grammarly explains in English only.
   Effort: S. Extension: yes (Full Access, same call, one more schema field).
2. **Register chips on the result panel.**
   What: one-tap re-run as casual / polite / formal; for Korean output 반말 / 해요체 / 합쇼체.
   Why: Grammarly tone changes are Premium and English-only; Korean speech levels exist nowhere in it.
   Effort: S. Extension: yes (one more call; no new storage).
3. **Streaming the result into the panel.**
   What: show the first words as they arrive instead of a spinner for the whole call.
   Why: lag is Grammarly's top keyboard complaint; perceived speed is where protly can win cheaply.
   Effort: M. Extension: yes (`URLSession` byte stream; memory unaffected).
4. **Mixed-draft output choice.**
   What: a draft that mixes Korean and English (what the one grid produces) gets an explicit "all English / all
   Korean / keep the mix" choice in the panel.
   Why: Grammarly checks one language per text and cannot even type the Korean half.
   Effort: S. Extension: yes (prompt and panel only).
5. **Prefix confirmation chip.**
   What: once `ru:` is typed, the bar shows "→ Russian" so the target is visible before the tap; unknown codes show
   nothing.
   Why: makes the 46-language prefix discoverable and safe; Grammarly hides translation in menus.
   Effort: S. Extension: yes, offline, no Full Access needed.
6. **Diff view for Polish.**
   What: highlight what changed between draft and result, with an "Original" toggle.
   Why: Apple's Writing Tools is criticised for silently replacing text; Grammarly shows cards one by one.
   Effort: M (word diff in ProtlyCore, testable on Linux). Extension: yes, local.
7. **Keep-as-is glossary.**
   What: a short list of names, slang and terms that must not be translated or "fixed", sent with each call.
   Why: Grammarly "corrects" names and slang; DeepL charges for glossaries.
   Effort: S-M. Extension: yes (keyboard `UserDefaults`, entered through the same confirm-panel path as the
   about-me note, since there is no App Group).
8. **Reply in the sender's language from Read clipboard.**
   What: when Read clipboard detects a non-Korean source, the panel offers "Reply in Russian", which puts `ru: ` at
   the start of the empty field.
   Why: closes the read-reply loop for any language in two taps; respects the Sprint 8 decision (nothing remembered,
   the prefix stays explicit).
   Effort: S-M. Extension: yes (Full Access; MODE in schema gains a source code).
9. **One-shot chat context.**
   What: copy the friend's last messages, Read clipboard keeps them (after a tap) as context for the next Translate
   only, then forgets them.
   Why: the extension already uses the conversation; on iPhone neither Grammarly nor protly can see the chat.
   Effort: M. Extension: yes, but each read shows Allow Paste (`docs/ios-keyboard-notes.md`, Sprint 2 table, row 6).
10. **Short Korean explanations of the top English fixes.**
    What: under a Polish result, up to three one-line notes in Korean ("a → the: 이미 말한 대상").
    Why: turns each message into a lesson in the writer's first language; Grammarly's cards are English.
    Effort: S-M. Extension: yes (same call, schema field, panel scroll).
11. **Cost meter in the keyboard.**
    What: tokens and an estimated cost per call and per month, shown on long-press of the protly icon.
    Why: the pay-per-use model is protly's price edge over a $12-30 subscription; make it visible.
    Effort: S. Extension: yes (local count from the API response's usage field).
12. **Offline Korean spacing and spelling hints.**
    What: an on-device 띄어쓰기 and common-typo check for Korean drafts, shown in the bar.
    Why: Grammarly has no Korean in its keyboard at all; this works even without Full Access.
    Effort: L. Extension: yes, but tight on memory next to the 11 MB word lists; measure first.
13. **Action extension for selected text.**
    What: "protly" in the share or action sheet to translate selected text in apps where the clipboard flow is
    clumsy.
    Why: Apple's Writing Tools is blocked in Meta apps; this reaches text the keyboard cannot.
    Effort: M. Not a keyboard feature: a new extension target, which needs `ios-app/Package.swift` and
    `ios-app/xtool.yml` changes, so the tower decides.
14. **Dictation through the container app.**
    What: a mic key that opens the protly app to record, then returns the polished text.
    Why: Grammarly now has dictation with cleanup.
    Effort: L. Extension: no microphone in keyboards; the app bounce is what Wispr users complain about, and opening
    the container app from a keyboard has no supported API. Lowest priority.

## Sources

Official and store pages:
- https://apps.apple.com/us/app/grammarly-ai-keyboard-voice/id1158877342
- https://www.grammarly.com/blog/product/multilingual-support-in-additional-languages/
- https://www.grammarly.com/translation
- https://www.grammarly.com/plans
- https://grammarly.com/privacy
- https://support.grammarly.com/hc/en-us/articles/360041953832-Known-issues-on-websites
- https://chromewebstore.google.com/detail/grammarly-ai-writing-and/kbfnbcaeplbcioakkpcpgfkobkghlhen
- https://apps.apple.com/us/app/gboard-the-google-keyboard/id1091700242
- https://support.apple.com/en-us/121115
- https://www.apple.com/apple-intelligence/
- https://support.apple.com/en-hk/guide/ipad/ipad04c3f67f/ipados
- https://apps.apple.com/us/app/microsoft-swiftkey-ai-keyboard/id911813648
- https://support.microsoft.com/en-us/swiftkey-keyboard/how-to-use-tone-in-microsoft-swiftkey-keyboard
- https://www.deepl.com/en/ios-app
- https://apps.apple.com/us/app/deepl-translate-write/id1552407475
- https://www.deepl.com/en/blog/introducing-deepl-write
- https://www.deepl.com/en/press-release/deepl-translator-adds-korean-and-norwegian-bokml
- https://www.deepl.com/en/pro
- https://www.deepl.com/en/privacy
- https://apps.apple.com/us/app/naver-papago-ai-translator/id1147874819
- https://apps.apple.com/app/id6743303161
- https://papago-plus.com/pricing/comparison
- https://apps.apple.com/kr/app/id1297816298
- https://www.samsung.com/us/support/answer/ANS10000943/
- https://www.samsung.com/uk/support/mobile-devices/how-to-use-galaxy-ai-features-on-writing-assist/
- https://apps.apple.com/app/id6822543636
- https://apps.apple.com/us/app/id6497229487
- https://clevertype.co/
- https://clevertype.co/privacy-policy
- https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html

Press, forums and third-party pages:
- https://releases.sh/superhuman/grammarly.md
- https://www.eesel.ai/blog/grammarly-ai-pricing
- https://justuseapp.com/en/app/1158877342/grammarly-grammar-keyboard/reviews
- https://justuseapp.com/en/app/1158877342/grammarly-keyboard/reviews
- https://unstar.app/blog/gboard-swiftkey-grammarly-fleksy-typewise-keyboard-apps-ranked-2026
- https://bugzilla.mozilla.org/show_bug.cgi?id=1258946
- https://aws.amazon.com/marketplace/reviews/reviews-list/prodview-34k35moukptwm?page=76
- https://blog.engram.us/best-ai-proofreader-grammarly-quillbot-engram-trinka
- https://en.wikipedia.org/wiki/Gboard
- https://gadgets.beebom.com/stories/i-want-google-to-fix-gboard-on-ios-app
- https://www.androidauthority.com/pixel-10-gboard-writing-tool-3589264
- https://www.androidauthority.com/gboard-writing-tools-upgrade-3668502/
- https://www.engadget.com/2019/03/15/google-gboard-ios-keyboard-translate/
- https://www.businessinsider.nl/how-to-use-gboard-translate-on-iphone/
- https://www.igeeksblog.com/how-to-use-writing-tools-on-iphone-ipad/
- https://www.macrumors.com/how-to/ios-live-translation-in-messages/
- https://www.koreaherald.com/article/10467676
- https://forums.imore.com/ask-question/377131-how-may-i-set-keyboard-setting-so-i-can-save-time-pressing-globe-button.html
- https://www.ubergizmo.com/2016/06/ios-10-easy-multilingual-typing
- https://www.macrumors.com/2025/04/17/apple-intelligence-not-available-in-meta-apps/
- https://kirkville.com/the-big-problem-with-apples-ai-writing-tools/
- https://www.digitaltrends.com/?p=3662211
- https://forums.macrumors.com/threads/writing-tools-are-basically-useless.2476764/
- https://talk.macpowerusers.com/t/are-you-happy-with-apple-intelligence/39338
- https://www.techradar.com/phones/ios/youre-not-bad-at-typing-ios-26s-autocorrect-is-broken-and-theres-still-no-fix-in-ios-26-2
- https://clevertype.co/post/best-swiftkey-alternative-with-ai-writing-features
- https://clevertype.co/post/best-ai-keyboard-apps-for-iphone-in
- https://apps.apple.com/np/app/multi-translators-with-deepl/id1672159079
- https://www.phonearena.com/news/Samsungs-One-UI-7-frees-Galaxy-AI-writing-tools-from-its-own-keyboard_id167226
- https://dev.to/tbds_2dadf2b626f315902eae/the-three-hard-constraints-of-an-ios-keyboard-extension-46af
