#!/usr/bin/env python3
"""Count entities by prototype name in a save, grouped into the pY script
families that a pY mod survey (not included here) lists as benchmark targets.

The save's own mod set is assembled as for run_bench.py, plus the bench-census
mod (census-mod/), which counts on on_init when Factorio loads the save for a
1-tick --benchmark. The save is only read; nothing is saved. Writes
results/<name>.census.json.
"""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

from benchlib import BENCH, BINARY, RESULTS, RUNS, build_run_dir, sync_settings

FARMS = ["arqad-hive", "arthurian-pen", "auog-paddock", "cridren-enclosure", "dhilmos-pool",
         "dingrits-pack", "fish-farm", "kmauts-enclosure", "mukmoux-pasture", "phadai-enclosure",
         "phagnot-corral", "prandium-lab", "ez-ranch", "rc", "scrondrix-pen", "simik-den",
         "trits-reef", "ulric-corral", "vonix-den", "vrauks-paddock", "xenopen", "xyhiphoe-pool",
         "zipir-reef", "fwf", "grods-swamp", "guar-gum-plantation", "moss-farm",
         "ralesia-plantation", "rennea-plantation", "sap-extractor", "seaweed-crop",
         "sponge-culture", "tuuphra-plantation", "yotoi-aloe-orchard", "bhoddos-culture",
         "fawogae-plantation", "navens-culture", "cadaveric-arum", "kicalk-plantation",
         "space-fish-farm", "space-moss-farm"]
FARM_RE = re.compile(r"^(" + "|".join(map(re.escape, FARMS)) + r")(-mk0\d)?(-turd)?$")

# family -> list of (label, regex). Order matters only for display.
FAMILIES = {
    "dino dig site": [("dino-dig-site", r"^dino-dig-site$"),
                      ("food input (hidden container)", r"^dino-dig-site-food-input$"),
                      ("digosaur units", r"^digosaurus")],
    "seep derricks": [("drill", r"^(oil-derrick|tar-extractor|natural-gas-derrick)-mk0\d$"),
                      ("hidden -base assembler", r"^(oil-derrick|tar-extractor|natural-gas-derrick)-mk0\d-base$")],
    "caravans": [("units", r"^(caravan|flyavan|fluidavan|nukavan)(-turd)?$"),
                 ("outposts", r"^outpost")],
    "biofluid": [("bioport", r"^bioport$"), ("provider-tank", r"^provider-tank$"),
                 ("requester-tank", r"^requester-tank$"), ("vessels", r"^vessel(-to-ground)?$"),
                 ("courier units", r"^(gobachov|huzu|chorkok)$")],
    "aerial": [("turbines", r"^aerial-blimp-mk0\d$"), ("hidden accumulators", r"^aerial-blimp-mk0\d-accumulator"),
               ("base", r"^aerial-base$"), ("base parts", r"^aerial-base-(animation|chest)$")],
    "tailings pond": [("tailings-pond", r"^tailings-pond$")],
    "vat brain": [("vat-brain", r"^vat-brain(-mk0\d)?$"), ("hidden beacon", r"^hidden-beacon-vatbrain")],
    "farms": [("farm buildings", None)],
    "TURD hidden beacons": [("hidden-beacon-turd", r"^hidden-beacon-turd")],
}


def families(totals: dict) -> dict:
    out = {}
    for fam, parts in FAMILIES.items():
        rows = {}
        for label, pat in parts:
            if pat is None:
                names = [n for n in totals if FARM_RE.match(n)]
            else:
                rx = re.compile(pat)
                names = [n for n in totals if rx.search(n)]
            rows[label] = {"count": sum(totals[n] for n in names), "names": len(names)}
        out[fam] = rows
    return out


def main() -> int:
    save = Path(sys.argv[1]).expanduser().resolve()
    name = (sys.argv[2] if len(sys.argv) > 2 else save.stem).replace(" ", "_")
    root = RUNS / f"{name}-census"
    run = build_run_dir(save, root)
    if "Mods synced" not in sync_settings(run, save):
        print("--sync-mods failed", file=sys.stderr)
        return 1
    shutil.copytree(BENCH / "census-mod", run["mods"] / "bench-census", dirs_exist_ok=True)
    ml = json.loads((run["mods"] / "mod-list.json").read_text())
    ml["mods"].append({"name": "bench-census", "enabled": True})
    (run["mods"] / "mod-list.json").write_text(json.dumps(ml, indent=2))
    proc = subprocess.run([str(BINARY), "--config", str(run["config"]), "--mod-directory",
                           str(run["mods"]), "--benchmark", str(save), "--benchmark-ticks", "1",
                           "--benchmark-runs", "1", "--disable-audio",
                           "--disable-migration-window"],
                          capture_output=True, text=True, timeout=3600)
    produced = run["write"] / "script-output/bench-census.json"
    if not produced.exists():
        print((proc.stdout + proc.stderr)[-3000:], file=sys.stderr)
        return 2
    data = json.loads(produced.read_text())
    fams = families(data["totals"])
    res = {"save": str(save), "tick": data["tick"], "families": fams,
           "entities_total": sum(data["totals"].values()),
           "surfaces": {s: sum(v.values()) for s, v in data["surfaces"].items()},
           "totals": data["totals"]}
    RESULTS.mkdir(exist_ok=True)
    (RESULTS / f"{name}.census.json").write_text(json.dumps(res, indent=1) + "\n")
    print(f"{name}: {res['entities_total']} entities on {len(res['surfaces'])} surfaces")
    for fam, rows in fams.items():
        print(f"  {fam:<22} " + ", ".join(f"{k} {v['count']}" for k, v in rows.items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
