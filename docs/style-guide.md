# protly English style guide

The English style rules protly gives the model whenever it writes English: Translate (Korean to English) and Polish, in the keyboard and in the Chrome extension. Derived only from `cyanprot/humanizer` at `c86d244` (2026-10-29). Each rule below traces to a file there.

The prompt blocks in "Prompt blocks" are the source of truth. Code copies them verbatim: `src/lib/style.js` exports them, and `ios/keyboard-prompt.txt` carries the same lines. If this file and the code disagree, this file wins and the code is fixed.

## Scope

| Block | Goes into | Not into |
|---|---|---|
| `ENGLISH_STYLE` | Every call whose output is English: keyboard MODE out and MODE fix, extension outgoing and box with `lang` `en`, `EMAIL_SYSTEM`, `POLISH_SYSTEM` | MODE in (text to Korean), any non-English target |
| `POLISH_VOICE` | Polish only: keyboard MODE fix, extension `POLISH_SYSTEM` | Translation of any kind |
| `TRANSLATE_TONE` | Korean to English translation only: keyboard MODE out, extension outgoing, box, `EMAIL_SYSTEM` | Polish |
| `EMAIL_SHAPE` | Gmail only: `EMAIL_SYSTEM`, and `POLISH_SYSTEM` when the draft is an email | Chat, DMs, the keyboard |

The split follows one humanizer rule (`humanizer/prompts/style_rules.md`, Content): keep the source's genre, audience and person. A polish may reshape the user's own English. A translation carries the user's Korean across as it is, so it gets the word and punctuation rules but not the voice. `EMAIL_SHAPE` is the one exception: an email the extension writes from a Korean draft still puts the ask first, as the guide's email profile says.

## Prompt blocks

Each block is plain text with a leading `- ` per line. They obey their own rules: no em dash, en dash, semicolon or slash anywhere in them.

### ENGLISH_STYLE

```text
- Meaning: keep every fact, name, number, request and hedge. Add nothing the draft lacks.
- Words: plain, exact words and active verbs. A verb beats a noun made from a verb. Contractions are fine.
- Spelling: Canadian. Colour, centre, favourite, travelled, defence, but organize and analyze.
- Sentences: one idea each. Clauses the draft joins stay joined.
- Punctuation: periods, commas, question marks, colons, parentheses, hyphens, straight quotes and apostrophes. Join clauses with a comma and "and", "but" or "so", or end the first with a period. Write "and" or "or" between alternatives. A hyphen joins words or a range (7-8), never clauses. No em dash, en dash, semicolon or slash.
- Emoji and exclamation marks: keep the draft's own and add none.
- Say it plainly instead of: delve into, multifaceted, nuanced, it is important to note that, plays a crucial role, deep dive, holistic, I'd love to, passionate about, excited to, I'm just a student but, thank you for reaching out, hope this helps, I hope this finds you well, just circling back, please find attached. Open no sentence with Furthermore, Moreover, Additionally, Ultimately or Interestingly. End on the last real sentence, never on "Thank you for your time".
```

### POLISH_VOICE

```text
- Voice: direct, dry, understated. The main point or the ask goes first, reasons after. Side context goes in parentheses inside its sentence.
- A change of mind stays plain: "I thought X. Now I think Y." Length stays close to the draft: cut repetition and filler.
```

### TRANSLATE_TONE

```text
- Keep the draft's tone: warm stays warm, blunt stays blunt.
```

### EMAIL_SHAPE

```text
- Email: the ask goes first, context after. Keep "Hi <Name>," when the draft has it. Keep the draft's sign-off.
```

Sizes (characters, final newline excluded): `ENGLISH_STYLE` 1,228, `POLISH_VOICE` 263, `TRANSLATE_TONE` 60, `EMAIL_SHAPE` 111. The keyboard carries the first three, 1,551 in all. The Sprint 7a draft spent 1,468 on its `ENGLISH_STYLE` and `POLISH_VOICE`, and `TRANSLATE_TONE` replaces its 61-character MODE out tone line (with its `- ` and newline), so the keyboard prompt grows by about 22 characters over that draft, inside the 48 characters of headroom it measured. Recheck with the budget test.

## Where each rule comes from

Paths are in `cyanprot/humanizer`.

| Rule | Source |
|---|---|
| Keep every fact and hedge, add nothing | `docs/style-guide.md` Tone ("Never add claims the source does not contain"), `humanizer/prompts/style_rules.md` Content |
| Plain exact word, active verb, verbs over nominalizations | `style_rules.md` Words, `docs/style-guide.md` English, `humanizer/reference/data/graham_descriptors.md` ("use" over "utilize") |
| Contractions | `docs/style-guide.md` English ("Contractions fine in email and posts") |
| Canadian spelling with -ize and -yze | `docs/style-guide.md` English, the swap list in `vale/styles/CyanStyle/Canadian.yml`, and the M6 diagnosis in `docs/eval/2026-10-29-dev-2.md` (finding 3: "analyse" next to "criticize" read as mixed spelling, planned fix V8 in `docs/plans/2026-10-28-m6-tuning.md`) |
| One idea per sentence, keep joined clauses joined | `graham_descriptors.md`, and the M6 diagnosis (finding 1: the rewrite cut sentences shorter and more uniform than the source, and the judge called it choppy, planned fix V4) |
| Punctuation set and the fixes for each banned mark | `docs/style-guide.md` Punctuation, `style_rules.md` Punctuation, `vale/styles/CyanStyle/{Dash,Semicolon,Slash}.yml` (the Dash rule also catches a spaced hyphen between clauses) |
| Banned phrases, openers, closing line | `docs/style-guide.md` Banned phrases, the error-level rules `BannedAIFiller`, `BannedFiller`, `BannedHype`, `BannedOpener`, `BannedClosing` |
| Dry, direct, understated voice | `docs/style-guide.md` Tone, `style_rules.md` Words |
| Main point first, side context in parentheses, plain self-correction | `docs/style-guide.md` Structure |
| Length close to the draft | `style_rules.md` Content ("Keep the length close to the source") |
| Translation keeps the draft's tone | `style_rules.md` Content (keep genre, audience and person) |
| Email: ask first, "Hi <Name>," | `docs/style-guide.md` Email genre profile |
| Prompt text written in its own style | `docs/research-report.md` ("matching the prompt's own style to the output style"), `CLAUDE.md` Fixed decisions |

## Left out, and why

- **Candidate tells** ("matters because", "is genuinely", "every single", "rather than merely", trailing participle clauses, "not X but Y", forced lists of three, chatbot residue such as "I'd be happy to"). In humanizer these are Vale warnings, and `docs/style-guide.md` "Not yet merged" says none is a rule until Cyan adopts it (humanizer `_state/OPEN.md` [O-01]). When Cyan adopts one there, it joins the "Say it plainly instead of" line here.
- **Long-form, academic, reflective and LinkedIn sections**, the Graham exemplars, the Graham descriptors beyond the two used above, and the Dennett checklist. They shape whole documents. A chat message or a short email gets nothing from them, and the keyboard would pay for them on every call.
- **The email word cap and pleasantry line.** A cap fights "length close to the draft", and a pleasantry adds content the draft lacks (the same reason humanizer's M6 plan drops it in V2).
- **The pipeline**: linter, revise loop, claim check, `[[missing: ...]]` placeholders. protly makes one direct call.
- **Bans on the other marks** (`...`, `&`, arrows and bullets). They are warnings in humanizer (`OtherPunctuation.yml`), and chat uses an ellipsis on purpose.

## Where protly departs from humanizer

1. **The banned phrases sit in the prompt.** Humanizer keeps hard bans in its linter and states prompt rules positively. protly has no linter and no revise loop, so the error-level list goes into `ENGLISH_STYLE` as one line, framed as "Say it plainly instead of". The research behind humanizer's choice calls the priming risk of ban lists anecdotal (`docs/research-report.md`), so a short list is a small risk. `scripts/eval-polish.mjs` and `scripts/eval-ios.mjs` check that it holds.
2. **The draft's own emoji and exclamation marks stay.** The guide says no emoji and an exclamation mark only in a friendly greeting or sign-off. That describes how Cyan writes. In protly the draft is already Cyan's, so removing his emoji changes his message. The model adds none.

## Keeping it current

Update this file when humanizer changes any of these, then copy the blocks into `src/lib/style.js` and `ios/keyboard-prompt.txt`:

- `docs/style-guide.md` (for example when [O-02] replaces it with Cyan's canonical local guide)
- the error-level rules in `vale/styles/CyanStyle/`, or a candidate tell promoted under [O-01]
- the spelling or sentence lines in `humanizer/prompts/style_rules.md` after M6-2 (V4, V8)

## For Sprint 7a

Sprint 7a in `docs/plans/2026-10-28-ios-keyboard.md` drafted its own `ENGLISH_STYLE` and `POLISH_VOICE`. Use the blocks above instead. Changes that follow:

- `src/lib/style.js` exports all four blocks. `prompts.js` adds `TRANSLATE_TONE` to the outgoing, box and email prompts and `EMAIL_SHAPE` to the email prompt. `POLISH_SYSTEM` gets `EMAIL_SHAPE` too, since one polish prompt serves chat and email (the line only applies to an email draft).
- The keyboard prompt carries `ENGLISH_STYLE`, `POLISH_VOICE` and `TRANSLATE_TONE` verbatim, and its old "Keep the DRAFT's tone" line goes, since `TRANSLATE_TONE` replaces it. Recheck the 3,800-character budget test.
- `tests/style.test.js` in the plan asserts text this guide no longer has. Change `/never an em dash, en dash, semicolon or slash/` to `/No em dash, en dash, semicolon or slash/`. In the phrase list, `'delve'` and `'I hope this finds you well'` still match, `'additionally'` and `'thank you for your time'` become `'Additionally'` and `'Thank you for your time'` (the case in the block), and `'touching base'` goes (it came from a file outside humanizer). The self-punctuation test should cover all four blocks and the slash too.
- Decisions 2 and 5 of Sprint 7a (the extra phrases from `~/Academia/_docs/style-guide.md`) and the "precise beats ornate" wording no longer apply unless Cyan asks for them back.
