#!/usr/bin/env python3
"""Benchmark a real save (e.g. a pY map) with the save's own mod list.

The save is first copied to saves/real/<name>.zip and only the copy is ever
loaded, so the original under ~/factorio/saves is untouched (Factorio only
reads it anyway, but the copy also pins exactly what was measured). Mods are
resolved from ~/factorio/mods at the versions the save records, and
--sync-mods writes matching startup settings into the isolated mod directory.
All other options are passed through to run_bench.py.
"""
import shutil
import sys
from pathlib import Path

import run_bench
from benchlib import SAVES


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1].startswith("-"):
        print(f"usage: {sys.argv[0]} <save.zip> [run_bench options]\n\n{__doc__}")
        return 2
    src = Path(sys.argv[1]).expanduser().resolve()
    name = src.stem.replace(" ", "_")
    dest = SAVES / "real" / f"{name}.zip"
    if src.is_relative_to(SAVES):
        dest = src  # already a bench-owned copy (e.g. saves/mulark/)
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest != src and not dest.exists() or dest.stat().st_size != src.stat().st_size \
            or dest.stat().st_mtime < src.stat().st_mtime:
        print(f":: copying {src} -> {dest}")
        shutil.copy2(src, dest)
    rest = sys.argv[2:]
    if "--name" not in rest:
        rest = ["--name", name] + rest
    return run_bench.main([str(dest)] + rest)


if __name__ == "__main__":
    sys.exit(main())
