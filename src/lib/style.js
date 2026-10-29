// English style for Polish and for Korean -> English translation, distilled from cyanprot/humanizer
// (docs/style-guide.md, humanizer/prompts/style_rules.md, vale/styles/CyanStyle) plus the banned phrases of
// ~/Academia/_docs/style-guide.md, for chat and email. src/lib/prompts.js imports it. ios/keyboard-prompt.txt
// carries the same lines verbatim, and tests/ios-app.test.js fails when it does not.
// Keep it short: the keyboard sends it on every call, straight from the phone.

export const ENGLISH_STYLE = `- Words: plain and exact, precise beats ornate. Verbs over nouns made from verbs. Contractions are fine. Canadian spelling (colour, centre, favourite, neighbour, travelled).
- Punctuation: never an em dash, en dash, semicolon or slash. Use a comma, colon, parentheses or a new sentence instead, and "and" or "or" instead of a slash. Straight quotes and apostrophes. A range takes a hyphen (7-8). Add no exclamation mark or emoji the draft does not have.
- Never use: delve, multifaceted, nuanced, holistic, deep dive, it is important to note, plays a crucial role, tapestry, testament, pivotal, intricate, vibrant, showcase, underscore, sheds light on, at the heart of, paradigm shift, synergies, in today's society, in the modern world, additionally, furthermore, moreover, ultimately, interestingly, essentially, fundamentally, crucially, passionate about, excited to, I'd love to, I would be honored, I think maybe, I'm just a student but, hope this helps, I'd be happy to help, I hope this finds you well, I wanted to reach out, I'm reaching out because, just circling back, touching base, per our discussion, please find attached, pleased to announce, thank you for reaching out, thank you for your time, matters because, is genuinely, every single, rather than merely. No trailing participle clauses (", highlighting ..."), no "not X but Y" contrasts, no forced lists of three.`;

// Polish only. A translation keeps the draft's own tone and order.
export const POLISH_VOICE = `- Voice: direct, dry, understated. Main point first. Side context goes in parentheses inside its sentence.`;
