#!/usr/bin/python3
"""Build protly's icon (outlined p) and wordmark (outlined protly) from JetBrains Mono Medium.

Run: python3 -I scripts/build-icons.py
Output (committed): icons/p.svg, icons/wordmark.svg, icons/icon-{16,32,48,128}.png (PNGs via rsvg-convert),
and ios-app/Support/AppIcon.png (xtool.yml iconPath: 1024x1024, opaque RGB, square; iOS masks the corners).
Deliberate departure from BRAND.md 5.3: protly is a product, not the northprot mark, so it gets its own p.
"""
import io
import subprocess
from pathlib import Path

from PIL import Image

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont

FONT = '/usr/share/fonts/jetbrains-mono-fonts/JetBrainsMono-Medium.otf'
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'icons'
IOS_ICON = ROOT / 'ios-app' / 'Support' / 'AppIcon.png'
IOS_SIZE = 1024
IOS_SCALE = 0.85  # the p fills 74% of the height; shrunk so it sits inside the home-screen squircle with air
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


def icon_svg(k=1):
    d, (xmin, ymin, xmax, ymax), _ = outline('p')
    tx = 500 - k * (xmin + xmax) / 2
    ty = 500 + k * (ymin + ymax) / 2  # font y is up; scale(k -k) flips it
    sc = '1 -1' if k == 1 else f'{k} {-k}'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" fill="{INK}">\n'
            f'  <rect width="1000" height="1000" fill="{PAPER}"/>\n'
            f'  <path transform="translate({tx} {ty}) scale({sc})" d="{d}"/>\n'
            '</svg>\n')


def ios_icon():
    # rsvg-convert always writes RGBA; iOS blackens or rejects an app icon with an alpha channel, so drop it.
    png = subprocess.run(['rsvg-convert', '-w', str(IOS_SIZE), '-h', str(IOS_SIZE)],
                         input=icon_svg(IOS_SCALE).encode(), capture_output=True, check=True).stdout
    Image.open(io.BytesIO(png)).convert('RGB').save(IOS_ICON, optimize=True)


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
    ios_icon()
    print('built', ', '.join(p.name for p in sorted(OUT.iterdir())), IOS_ICON.relative_to(ROOT))
