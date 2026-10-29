// The user's own English style, written by Cyan on 2026-10-29. The bullets are the user's text verbatim: edit
// them only with the user. Each block's scope is fixed by the user too, and tests/style.test.js pins it:
// ENGLISH_STYLE goes into every call whose output is English, POLISH_VOICE into Polish (the rewrite mode, not the
// language) only, TRANSLATE_TONE into Korean -> English translation only, EMAIL_SHAPE into email only.
// src/lib/prompts.js imports them. ios/keyboard-prompt.txt carries ENGLISH_STYLE, POLISH_VOICE and TRANSLATE_TONE
// verbatim (it has no email mode), and tests/ios-app.test.js fails when it does not.
// Keep it short: the keyboard sends it on every call, straight from the phone.

export const ENGLISH_STYLE = `- Meaning: keep every fact, name, number, request and hedge. Add nothing the draft lacks. Meaning wins over style: if a rule below would drop a fact, request or hedge, keep it.
- Words: plain, exact words and active verbs. A verb beats a noun made from a verb. Contractions are fine.
- Spelling: Canadian. Colour, centre, favourite, travelled, defence, but organize and analyze.
- Sentences: clauses the draft joins stay joined.
- Punctuation: no em dash, en dash, semicolon or slash. Join clauses with a comma and "and", "but" or "so", or end the first with a period. Write "and" or "or" between alternatives. A hyphen joins words or a range (7-8), never clauses. Leave URLs, email addresses, file paths, code, dates, numbers and quotations exactly as written.
- Emoji and exclamation marks: keep the draft's own and add none.
- Say it plainly instead of: delve into, multifaceted, nuanced, it is important to note that, plays a crucial role, deep dive, holistic, I'd love to, passionate about, excited to, I'm just a student but, thank you for reaching out, I hope this finds you well, just circling back, hope this helps, please find attached. Open no sentence with Furthermore, Moreover, Additionally, Ultimately or Interestingly. End on the last real sentence, never on "Thank you for your time".`;

export const POLISH_VOICE = `- Voice: direct. Humour stays dry and understated. Keep the draft's register: casual stays casual, warm stays warm, and softeners like lol stay.
- The main point or the ask goes first, reasons after, unless the draft is casual chat. Side context goes in parentheses inside its sentence.
- A change of mind stays plain: "I thought X. Now I think Y." Length stays close to the draft: cut repetition and filler.`;

export const TRANSLATE_TONE = `- Keep the draft's tone: warm stays warm, blunt stays blunt.
- ㅋㅋ used as a softener becomes "lol" or is dropped.`;

export const EMAIL_SHAPE = `- Email: the ask goes first, context after. Keep "Hi <Name>," when the draft has it. Keep the draft's sign-off.`;
