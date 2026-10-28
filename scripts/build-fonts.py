#!/usr/bin/python3
"""Build the protly-mono woff2 subsets (Latin) from the system JetBrains Mono OTFs.

Run: python3 -I scripts/build-fonts.py
Output: src/ui/fonts/protly-mono-400.woff2 and -500.woff2, committed. Re-run only when the subset changes.
"""
import shutil
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

SRC = Path('/usr/share/fonts/jetbrains-mono-fonts')
LICENSE = Path('/usr/share/licenses/jetbrains-mono-fonts/OFL.txt')
OUT = Path(__file__).resolve().parent.parent / 'src' / 'ui' / 'fonts'
FAMILY = 'protly-mono'
# Basic Latin, Latin-1, general punctuation (dashes, quotes, bullet, ellipsis), arrows, dot operator.
UNICODES = [*range(0x20, 0x7F), *range(0xA0, 0x100), *range(0x2010, 0x2028), *range(0x2190, 0x2194), 0x22C5]


def build(weight, style):
    opts = subset.Options()
    opts.flavor = 'woff2'
    opts.layout_features = []  # no ligatures: "->" stays two characters in protly's UI
    opts.name_IDs = ['*']
    opts.notdef_outline = True
    font = TTFont(SRC / f'JetBrainsMono-{style}.otf')
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=UNICODES)
    sub.subset(font)
    name = font['name']
    name.removeNames(nameID=16)
    name.removeNames(nameID=17)
    for rec in name.names:
        if rec.nameID == 1:
            rec.string = FAMILY
        elif rec.nameID == 2:
            rec.string = 'Regular'  # one family, two weights: CSS picks by weight
        elif rec.nameID == 4:
            rec.string = f'{FAMILY} {style}'
        elif rec.nameID == 6:
            rec.string = f'{FAMILY}-{style}'
    font.flavor = 'woff2'
    out = OUT / f'{FAMILY}-{weight}.woff2'
    font.save(out)
    print(f'{out.name}: {out.stat().st_size} bytes')


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    build('400', 'Regular')
    build('500', 'Medium')
    shutil.copyfile(LICENSE, OUT / 'OFL.txt')
