import sys, pathlib
root = pathlib.Path(sys.argv[1]); blocks = 0; files = 0
for p in sorted(root.rglob('*.swift')):
    lines = p.read_text().split('\n')
    if not any(l.startswith('#Preview') for l in lines): continue
    out, i, n = [], 0, 0
    while i < len(lines):
        l = lines[i]
        if l.startswith('#Preview'):
            depth, j = 0, i
            while True:
                depth += lines[j].count('{') - lines[j].count('}')
                if depth == 0 and j > i or (j == i and depth == 0 and '{' in lines[j]): break
                j += 1
            assert lines[j] == '}', (p, j + 1, lines[j])
            out.append('#if KEYBOARDKIT_PREVIEWS // protly patch: xtool cannot expand #Preview reliably')
            out.extend(lines[i:j + 1]); out.append('#endif'); i = j + 1; n += 1
            continue
        out.append(l); i += 1
    p.write_text('\n'.join(out)); blocks += n; files += 1
print('files', files, 'blocks', blocks)
