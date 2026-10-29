#!/usr/bin/env python3
"""UserPromptSubmit hook: tell Claude which language to reply in.

Counts Hangul syllables against Latin words in the user's own text
(code, URLs and pasted blocks removed). Korean wins when Hangul
syllables >= Latin words. Prints one context line, or nothing if the
prompt has no letters.
"""
import json
import re
import sys

try:
    prompt = json.load(sys.stdin).get("prompt", "")
except Exception:
    sys.exit(0)

text = re.sub(r"<pasted_content[^>]*>.*?</pasted_content[^>]*>", " ", prompt, flags=re.S)
text = re.sub(r"```.*?```", " ", text, flags=re.S)
text = re.sub(r"`[^`]*`", " ", text)
text = re.sub(r"https?://\S+", " ", text)
if text.lstrip().startswith("/"):
    text = text.split(None, 1)[1] if len(text.split(None, 1)) > 1 else ""

ko = len(re.findall(r"[가-힣ㄱ-ㆎ]", text))
en = len(re.findall(r"\b[A-Za-z]+\b", text))

if ko == 0 and en == 0:
    sys.exit(0)

lang = "Korean" if ko >= en else "English"
print(
    f"[lang-mirror] The user wrote this message in {lang}. Write the final reply and any "
    f"question to the user in {lang}. Code, identifiers and technical terms stay English. "
    "Short progress updates between tool calls may be English. Files, memory and docs stay English."
)
