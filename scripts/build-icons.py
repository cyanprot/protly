#!/usr/bin/python3
"""Build protly's icon (outlined p) and wordmark (outlined protly) from JetBrains Mono Medium.

Run: python3 -I scripts/build-icons.py
Output (committed): icons/p.svg, icons/wordmark.svg, icons/icon-{16,32,48,128}.png (PNGs via rsvg-convert).
Deliberate departure from BRAND.md 5.3: protly is a product, not the northprot mark, so it gets its own p.
"""
import subprocess
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont

FONT = '/usr/share/fonts/jetbrains-mono-fonts/JetBrainsMono-Medium.otf'
OUT = Path(__file__).resolve().parent.parent / 'icons'
PAPER, INK = '#F5F0E6', '#1A1F2E'
SIZES = (16, 32, 48, 128)

font = TTFont(FONT)
glyphs = font.getGlyphSet()
cmap = font.getBestCmap()


def outline(ch):
    g = glyphs[cmap[ord(ch)]]
    pen = SVGPathPen(glyphs)
    g.draw(pen)
    bounds = BoundsPen(glyphs)
    g.draw(bounds)
    return pen.getCommands(), bounds.bounds, g.width


def icon_svg():
    d, (xmin, ymin, xmax, ymax), _ = outline('p')
    tx = 500 - (xmin + xmax) / 2
    ty = 500 + (ymin + ymax) / 2  # font y is up; scale(1 -1) flips it
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" fill="{INK}">\n'
            f'  <rect width="1000" height="1000" fill="{PAPER}"/>\n'
            f'  <path transform="translate({tx} {ty}) scale(1 -1)" d="{d}"/>\n'
            '</svg>\n')


def wordmark_svg(text='protly'):
    cap = font['OS/2'].sCapHeight
    descent = font['hhea'].descent  # negative
    paths, x = [], 0
    for ch in text:
        d, _, advance = outline(ch)
        paths.append(f'  <path transform="translate({x} 0) scale(1 -1)" d="{d}"/>')
        x += advance
    # currentColor: pages theme it (inline it, or use it as a CSS mask over var(--pl-fg)).
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 {-cap} {x} {cap - descent}" fill="currentColor">\n'
            + '\n'.join(paths) + '\n</svg>\n')


if __name__ == '__main__':
    OUT.mkdir(exist_ok=True)
    (OUT / 'p.svg').write_text(icon_svg())
    (OUT / 'wordmark.svg').write_text(wordmark_svg())
    for s in SIZES:
        subprocess.run(['rsvg-convert', '-w', str(s), '-h', str(s), str(OUT / 'p.svg'), '-o', str(OUT / f'icon-{s}.png')],
                       check=True)
    print('built', ', '.join(p.name for p in sorted(OUT.iterdir())))
