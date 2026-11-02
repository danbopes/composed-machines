#!/usr/bin/env python3
"""Download mulark's public benchmark maps into saves/mulark/ and record
provenance (URL, size, sha256, map version, mods from the header).

The files are treated as data: they are fetched with curl, hashed, and only
their uncompressed save header is read (savetool/saveheader.py). Nothing in
saves/mulark/ is ever unzipped or executed. Expected sha256s come from
mulark's factorio-benchmark-helper master.json where the map is listed there.
"""
import hashlib
import json
import subprocess
import sys
import urllib.parse
from pathlib import Path

from benchlib import SAVES, read_header

DEST = SAVES / "mulark"
B2 = "https://f000.backblazeb2.com/file/mulark-maps/"
DRIVE = "https://drive.usercontent.google.com/download?export=download&confirm=t&id="

# local name -> (url, expected sha256 or None, why it is in the set)
MAPS = {
    "test-000060.no_primed.400x.zip": (
        B2 + "test-000060/test-000060.no_primed.400x.zip",
        "9a5362506756", "1.1.107; 400x direct-insertion chains: inserters + assemblers"),
    "test-000059.full_beacon.cloned.zip": (
        B2 + "test-000059/test-000059.full_beacon.cloned.zip",
        "e06b4e99368a", "1.1.42; cloned beaconed assembler build"),
    "test-000061.naive.zip": (
        B2 + "test-000061/test-000061.naive.zip",
        "98495741e8f2", "1.1.107; inserters picking from belts (chasing)"),
    "UPS Wars 3 - mulark.10x -1M.zip": (
        B2 + "UPS Wars 3 - 1M/UPS Wars 3 - mulark.10x -1M.zip",
        "31f5d7e0119e", "UPS Wars 3 entry: whole-factory build"),
    "test-000013.1_network.zip": (
        B2 + "test-000013/test-000013.1_network.zip",
        "0f1732ea34a4", "1.0.0; 32 identical bot-based factories on one network (largest >=1.0 map found)"),
    "test-000066.infinity.cloned.zip": (
        DRIVE + "1lHL46LbS5AtoZ1wyPBbdcQNKY-Xn8OBR",
        None, "2.0.60; item voiding via infinity chests"),
}


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main(names) -> int:
    DEST.mkdir(parents=True, exist_ok=True)
    manifest_path = DEST / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    for name in names or MAPS:
        url, expect, why = MAPS[name]
        out = DEST / name
        if not out.exists():
            quoted = url if url.startswith(DRIVE) else B2 + urllib.parse.quote(url[len(B2):])
            subprocess.run(["curl", "-sSfL", "-o", str(out), quoted], check=True)
        digest = sha256(out)
        if expect and not digest.startswith(expect):
            print(f"{name}: sha256 {digest[:12]} != expected {expect}; removing", file=sys.stderr)
            out.unlink()
            continue
        try:
            h = read_header(out)
            hdr = {"map_version": h["map_version"],
                   "mods": [f"{m['name']} {m['version']}" for m in h["mods"]]}
        except Exception as e:  # header layouts differ across very old versions
            hdr = {"map_version": None, "header_error": repr(e)}
        manifest[name] = {**manifest.get(name, {}), "url": url, "bytes": out.stat().st_size, "sha256": digest,
                          "why": why, **hdr}
        print(f"{name}: {out.stat().st_size} B  {hdr.get('map_version')}  "
              f"{hdr.get('mods', hdr.get('header_error'))}")
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
