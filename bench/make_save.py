#!/usr/bin/env python3
"""Build a benchmark world in the component-lab harness server and save it.

Boots `fh test component-lab --keep`, runs builds/<variant>.lua over RCON with
ARGS substituted, lets the world tick until it reaches steady state, records a
status histogram, then stops the server. fh stops with SIGTERM, on which
Factorio saves the map it booted (run/component-lab/session.zip); that file is
copied to saves/<name>.zip. This deliberately avoids /server-save, which would
write into ~/factorio/saves (the harness server's write dir is ~/factorio).
"""
import argparse
import json
import shutil
import sys
import time
from pathlib import Path

from benchlib import BENCH, HARNESS, SAVES, SCRATCH, fh, lua_literal

PROJECT = "component-lab"
RUN_DIR = HARNESS / "run" / PROJECT
SESSION = RUN_DIR / "session.zip"
BUILDS = BENCH / "builds"
CELL_VARIANTS = {"stone-furnace", "electric-furnace", "assembler", "idle-furnace"}
NATIVE_MATRIX = sorted(CELL_VARIANTS | {"chests"})
# Composed-vs-native pairs (../docs/TEST-ENTITIES.md). Each composed
# cl-* build has a native-* twin in the same layout; where the native
# comparison is an existing matrix variant it is listed as well.
COMPOSED = ["cl-fluid-chest", "cl-signal-chest", "cl-fuelled-chest", "cl-cold-box",
            "cl-timed-converter", "cl-seep-derrick", "cl-dig-site", "cl-signal-endpoint",
            # The eight later entities (../docs/TEST-ENTITIES-2.md).
            "cl-hearth", "cl-brazier", "cl-creep-collector", "cl-rotating-chest",
            "cl-slag-generator", "cl-waste-heat-smelter", "cl-mass-driver", "cl-tuned-furnace"]
PAIRS = {
    "cl-fluid-chest": ["native-fluid-chest", "chests"],
    "cl-signal-chest": ["native-signal-chest"],
    "cl-fuelled-chest": ["native-fuelled-chest", "stone-furnace"],
    "cl-cold-box": ["native-cold-box", "chests"],
    "cl-timed-converter": ["assembler", "stone-furnace"],
    "cl-seep-derrick": ["native-seep-derrick"],
    "cl-dig-site": ["electric-furnace", "assembler"],
    "cl-signal-endpoint": ["native-signal-endpoint"],
    "cl-hearth": ["native-cl-hearth", "stone-furnace"],
    "cl-brazier": ["native-cl-brazier"],
    "cl-creep-collector": ["native-cl-creep-collector", "poll-creep-collector", "electric-furnace"],
    "cl-rotating-chest": ["native-cl-rotating-chest", "chests"],
    "cl-slag-generator": ["native-cl-slag-generator"],
    "cl-waste-heat-smelter": ["native-cl-waste-heat-smelter", "reactor-waste-heat-smelter",
                              "electric-furnace"],
    "cl-mass-driver": ["native-cl-mass-driver", "poll-mass-driver", "assembler"],
    "cl-tuned-furnace": ["native-cl-tuned-furnace", "beacon-tuned-furnace"],
}
# Every twin that is not a native-matrix variant (native-*, poll-*, beacon-*,
# reactor-*) is a grid cell built with _grid.lua like the composed ones.
GRID_VARIANTS = set(COMPOSED) | {n for v in PAIRS.values() for n in v if n not in NATIVE_MATRIX}
VARIANTS = sorted(set(NATIVE_MATRIX) | GRID_VARIANTS | {"empty"})


def assemble(variant: str, args: dict) -> Path:
    parts = [f"ARGS = {lua_literal(args)}\n", (BUILDS / "_common.lua").read_text(),
             (BUILDS / f"{variant}.lua").read_text()]
    if variant in CELL_VARIANTS:
        parts.append((BUILDS / "_cells.lua").read_text())
    elif variant in GRID_VARIANTS:
        parts.append((BUILDS / "_grid.lua").read_text())
    out = SCRATCH / f"{args['name']}.build.lua"
    out.write_text("\n".join(parts))
    return out


def rcon_file(path: Path, timeout: int) -> str:
    return fh("rcon", "--project", PROJECT, "--no-boot", "--timeout", str(timeout), "file", str(path))


def rcon_expr(expr: str) -> str:
    return fh("rcon", "--project", PROJECT, "--no-boot", "expr", expr)


def server_live() -> bool:
    return (RUN_DIR / "server.json").exists() and " up " in fh("status", PROJECT, check=False)


def last_json(text: str) -> dict:
    for line in reversed(text.splitlines()):
        line = line.strip()
        if line.startswith("{"):
            return json.loads(line)
    raise ValueError(f"no JSON in output:\n{text}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("variant", choices=VARIANTS)
    ap.add_argument("-n", "--cells", type=int, default=2000, help="cells (or chests) to build")
    ap.add_argument("--name", help="save name (default <variant>-<n>)")
    ap.add_argument("--settle", type=int, default=1800,
                    help="ticks to run after building, before saving (default 1800 = 30 s)")
    ap.add_argument("--pollution", action="store_true", help="leave pollution enabled")
    ap.add_argument("--reuse", action="store_true",
                    help="use an already-running component-lab server instead of refusing")
    args = ap.parse_args()
    name = args.name or f"{args.variant}-{args.cells}"
    SAVES.mkdir(exist_ok=True)
    SCRATCH.mkdir(exist_ok=True)

    if server_live() and not args.reuse:
        print("a component-lab server is already running; "
              "refusing to hijack it. Pass --reuse if it is yours.", file=sys.stderr)
        return 2

    t0 = time.monotonic()
    if not server_live():
        print(":: booting component-lab")
        # The suite has deliberate KNOWN-LIMIT failures, so its exit code says
        # nothing about whether the server is usable; the status check does.
        fh("test", PROJECT, "--keep", timeout=900, check=False)
        if not server_live():
            print("fh test did not leave a server running", file=sys.stderr)
            return 4
    lua = assemble(args.variant, {"name": name, "variant": args.variant, "n": args.cells,
                                  "pollution": args.pollution})
    print(f":: building {args.variant} x{args.cells}")
    build = last_json(rcon_file(lua, timeout=600))
    print("   " + json.dumps(build))

    start = int(rcon_expr("game.tick"))
    print(f":: settling {args.settle} ticks from tick {start}")
    while int(rcon_expr("game.tick")) < start + args.settle:
        time.sleep(1)
    check_lua = SCRATCH / f"{name}.check.lua"
    check_lua.write_text(f"ARGS = {lua_literal({})}\n" + (BENCH / "builds/_check.lua").read_text())
    check = last_json(rcon_file(check_lua, timeout=120))
    print("   " + json.dumps(check))

    before = SESSION.stat().st_mtime
    print(":: stopping (server saves session.zip on SIGTERM)")
    fh("stop", PROJECT, "--timeout", "120", timeout=300)
    if SESSION.stat().st_mtime <= before:
        print("session.zip was not rewritten on stop; no save produced", file=sys.stderr)
        return 3
    dest = SAVES / f"{name}.zip"
    shutil.copy2(SESSION, dest)
    # Pin the non-library mods (aitest, component-lab) beside the save: the
    # project mod is under active development, and a rerun weeks later must
    # load the code the save was made with. run_bench.py searches here first.
    pinned = SAVES / f"{name}.mods"
    shutil.rmtree(pinned, ignore_errors=True)
    pinned.mkdir()
    for p in (RUN_DIR / "mods").iterdir():
        if p.is_dir():
            shutil.copytree(p, pinned / p.name, symlinks=False)
    meta = {"name": name, "variant": args.variant, "cells": args.cells, "settle": args.settle,
            "pollution": args.pollution, "build": build, "check": check,
            "made_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "build_seconds": round(time.monotonic() - t0, 1)}
    (SAVES / f"{name}.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f":: wrote {dest} ({dest.stat().st_size / 1e6:.1f} MB) in {meta['build_seconds']} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
