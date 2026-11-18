#!/usr/bin/env python3
"""Download the third-party asset packs listed in assets/manifest.json.

Usage (from the repo root):
    python3 tools/fetch_assets.py            # fetch anything missing
    python3 tools/fetch_assets.py --force    # re-download and re-extract

Downloads are cached in assets/.cache/, verified against the pinned SHA-256,
and extracted into each pack's `dest` folder. Both folders are git-ignored.
Only the Python standard library is used.
"""
import fnmatch
import hashlib
import json
import os
import shutil
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "assets", ".cache")


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(url, path, expected_size=None):
    tmp = path + ".part"
    req = urllib.request.Request(url, headers={"User-Agent": "verdant-hold-asset-fetcher"})
    with urllib.request.urlopen(req) as r, open(tmp, "wb") as out:
        total = int(r.headers.get("Content-Length") or expected_size or 0)
        done = 0
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            out.write(chunk)
            done += len(chunk)
            if total:
                sys.stdout.write("\r  %5.1f%%  %d / %d MB" % (100.0 * done / total, done >> 20, total >> 20))
                sys.stdout.flush()
    print()
    os.replace(tmp, path)


def safe_extract(zf, members, dest, strip=""):
    """Extract members into dest, removing an optional leading `strip` folder."""
    dest_abs = os.path.abspath(dest)
    for m in members:
        rel = m[len(strip):] if strip and m.startswith(strip) else m
        target = os.path.abspath(os.path.join(dest, rel))
        if not target.startswith(dest_abs + os.sep):
            raise RuntimeError("refusing to extract outside destination: " + m)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with zf.open(m) as src, open(target, "wb") as out:
            shutil.copyfileobj(src, out)


def fetch(pack, force=False):
    dest = os.path.join(ROOT, pack["dest"])
    stamp = os.path.join(dest, ".fetched")
    if os.path.exists(stamp) and not force:
        with open(stamp) as f:
            if f.read().strip() == pack["sha256"]:
                print("[ok]   %s already present" % pack["id"])
                return
    os.makedirs(CACHE, exist_ok=True)
    zpath = os.path.join(CACHE, pack["id"] + ".zip")
    if force or not os.path.exists(zpath) or sha256_of(zpath) != pack["sha256"]:
        print("[get]  %s  (%s, %s)" % (pack["title"], pack["author"], pack["license"]))
        download(pack["url"], zpath, pack.get("size_bytes"))
    digest = sha256_of(zpath)
    if digest != pack["sha256"]:
        os.remove(zpath)
        raise SystemExit("checksum mismatch for %s: got %s" % (pack["id"], digest))
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    with zipfile.ZipFile(zpath) as zf:
        names = [n for n in zf.namelist() if not n.endswith("/")]
        strip = pack.get("strip", "")
        members = [n for n in names if any(fnmatch.fnmatch(n, strip + pat) for pat in pack["extract"])]
        safe_extract(zf, members, dest, strip)
    with open(stamp, "w") as f:
        f.write(pack["sha256"])
    print("[done] %s -> %s (%d files)" % (pack["id"], pack["dest"], len(members)))


def main():
    force = "--force" in sys.argv
    with open(os.path.join(ROOT, "assets", "manifest.json")) as f:
        manifest = json.load(f)
    for pack in manifest["packs"]:
        fetch(pack, force)
    print("Open (or re-open) the project in Godot so it imports the new files.")


if __name__ == "__main__":
    main()
