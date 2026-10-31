#!/usr/bin/env python3
"""Where a simulator keeps a setting: snapshots of a shut-down device's data folder, and their difference.

Usage:
  prefsdump.py snapshot <device data dir> <dest dir>
  prefsdump.py diff <before dir> <after dir> <out file>

run-shots.sh takes a snapshot before and after Full Access is turned on in Settings (plan Task 2.2 step 1), each
after `simctl shutdown` so the preference daemon has written to disk, and writes the difference to probe-prefs.txt.
A snapshot copies every .plist (binary or XML; up to 2 MB) and Library/TCC/TCC.db, and keeps an index of every
other file's size and mtime. The difference lists, per changed plist, every added, removed or changed key path
with its value; the TCC rows that were added or changed (and the access table's schema); and other new or changed
files by path only. Values are cut at 300 characters.
"""

import json
import os
import plistlib
import shutil
import sqlite3
import sys

# PRBPosterExtensionDataStore: wallpaper posters, rewritten on every boot (run 30's diff was mostly these).
SKIP_DIRS = {"Caches", "Logs", "Bundle", "tmp", "PRBPosterExtensionDataStore"}
MAX_PLIST = 2 * 1024 * 1024
TCC = os.path.join("Library", "TCC", "TCC.db")


def _walk(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            path = os.path.join(dirpath, name)
            yield os.path.relpath(path, root), path


def snapshot(data, dest):
    """Exits non-zero (SystemExit) when `data` is missing or holds no plist: an empty snapshot shows no change."""
    if not os.path.isdir(data):
        sys.exit(f"prefsdump: no device data folder {data}")
    files = os.path.join(dest, "files")
    os.makedirs(files, exist_ok=True)
    index = {}
    for rel, path in _walk(data):
        try:
            st = os.stat(path)
        except OSError:
            continue
        index[rel] = [st.st_size, st.st_mtime]
        if (rel.endswith(".plist") and st.st_size <= MAX_PLIST) or rel == TCC:
            target = os.path.join(files, rel)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            try:
                shutil.copy2(path, target)
            except OSError:
                pass
    with open(os.path.join(dest, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f)
    if not any(rel.endswith(".plist") for rel in index):
        sys.exit(f"prefsdump: no plist under {data}")


def _short(value):
    text = repr(value)
    return text if len(text) <= 300 else text[:300] + "..."


def _flatten(value, prefix=""):
    if isinstance(value, dict):
        out = {}
        for k, v in value.items():
            out.update(_flatten(v, f"{prefix}.{k}" if prefix else str(k)))
        return out or {prefix: {}}
    return {prefix: value}


def _load_plist(path):
    with open(path, "rb") as f:
        return plistlib.load(f)


def _plist_diff(rel, before, after):
    try:
        new = _flatten(_load_plist(after))
    except Exception as e:  # noqa: BLE001 - any parse error is reported, not raised
        return [f"{rel}: unreadable after ({type(e).__name__})"]
    if before is None:
        return [f"new {rel}"] + [f"  + {k}: {_short(v)}" for k, v in sorted(new.items())]
    try:
        old = _flatten(_load_plist(before))
    except Exception as e:  # noqa: BLE001
        return [f"{rel}: unreadable before ({type(e).__name__})"] + [f"  + {k}: {_short(v)}" for k, v in sorted(new.items())]
    lines = []
    for k in sorted(set(old) | set(new)):
        if k not in old:
            lines.append(f"  + {k}: {_short(new[k])}")
        elif k not in new:
            lines.append(f"  - {k}: {_short(old[k])}")
        elif old[k] != new[k]:
            lines.append(f"  ~ {k}: {_short(old[k])} -> {_short(new[k])}")
    return [rel] + lines if lines else []


def _tcc_rows(path):
    if not os.path.exists(path):
        return None, set()
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        schema = db.execute("select sql from sqlite_master where name = 'access'").fetchone()
        rows = set(db.execute("select * from access").fetchall())
    finally:
        db.close()
    return (schema[0] if schema else None), rows


def _count(snap):
    files = os.path.join(snap, "files")
    rels = [rel for rel, _ in _walk(files)] if os.path.isdir(files) else []
    return f"{sum(r.endswith('.plist') for r in rels)} plists{', TCC.db' if TCC in rels else ''}"


def diff(before, after):
    out = [f"snapshots: before {_count(before)}, after {_count(after)}"]
    files_b, files_a = os.path.join(before, "files"), os.path.join(after, "files")
    for rel, path in sorted(_walk(files_a)):
        if not rel.endswith(".plist"):
            continue
        old = os.path.join(files_b, rel)
        if os.path.exists(old):
            with open(old, "rb") as f1, open(path, "rb") as f2:
                if f1.read() == f2.read():
                    continue
            out += _plist_diff(rel, old, path)
        else:
            out += _plist_diff(rel, None, path)
    try:
        schema, rows_a = _tcc_rows(os.path.join(files_a, TCC))
        _, rows_b = _tcc_rows(os.path.join(files_b, TCC))
        added = sorted(rows_a - rows_b, key=repr)
        if added:
            out.append(f"{TCC}: {len(added)} rows added or changed; schema: {schema}")
            out += [f"  + {_short(r)}" for r in added]
    except sqlite3.Error as e:
        out.append(f"{TCC}: unreadable ({e})")
    if len(out) == 1:
        out.append("no plist or TCC change")
    try:
        with open(os.path.join(before, "index.json"), encoding="utf-8") as f:
            index_b = json.load(f)
        with open(os.path.join(after, "index.json"), encoding="utf-8") as f:
            index_a = json.load(f)
        other = [rel for rel in sorted(index_a) if not rel.endswith(".plist") and rel != TCC
                 and index_a[rel] != index_b.get(rel)]
        out.append(f"other new or changed files: {len(other)}")
        out += [f"  {rel}" for rel in other[:300]]
    except (OSError, ValueError) as e:
        out.append(f"no file index ({e})")
    return "\n".join(out) + "\n"


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) == 3 and argv[0] == "snapshot":
        snapshot(argv[1], argv[2])
        return 0
    if len(argv) == 4 and argv[0] == "diff":
        with open(argv[3], "a", encoding="utf-8") as f:
            f.write(diff(argv[1], argv[2]))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
