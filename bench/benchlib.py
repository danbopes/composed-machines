"""Shared paths and helpers for the bench tooling."""
import json
import os
import shutil
import subprocess
from pathlib import Path

BENCH = Path(__file__).resolve().parent
FACTORIO = Path(os.environ.get("FACTORIO_DIR", Path.home() / "factorio"))
BINARY = FACTORIO / "bin/x64/factorio"
DATA_DIR = FACTORIO / "data"
MODS_DIR = FACTORIO / "mods"
HARNESS = FACTORIO / "ai-harness"
FH = Path(os.environ.get("FH") or shutil.which("fh") or "fh")
SAVES = BENCH / "saves"
RESULTS = BENCH / "results"
SCRATCH = BENCH / "scratch"

# Mods that are not in the shared library but appear in saves made by the lab:
# the harness mod and the project mod. Searched after mods/.
EXTRA_MOD_DIRS = [HARNESS / "run/component-lab/mods", BENCH.parent / "mod"]


def fh(*args, timeout=600, check=True):
    proc = subprocess.run([str(FH), *args], cwd=HARNESS, capture_output=True, text=True,
                          timeout=timeout)
    if check and proc.returncode != 0:
        raise RuntimeError(f"fh {' '.join(args)} failed ({proc.returncode}):\n"
                           f"{proc.stdout}\n{proc.stderr}")
    return proc.stdout.strip()


def lua_literal(v) -> str:
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return "{" + ", ".join(lua_literal(x) for x in v) + "}"
    if isinstance(v, dict):
        return "{" + ", ".join(f"[{json.dumps(k)}]={lua_literal(x)}" for k, x in v.items()) + "}"
    raise TypeError(type(v))


# --------------------------------------------------------------------------
# Isolated run directory matching a save's own mod list.

import re
import shutil
import sys

sys.path.insert(0, str(FACTORIO / "savetool"))
import saveheader  # noqa: E402
import zipfile  # noqa: E402
import zlib  # noqa: E402


def read_header(save: Path) -> dict:
    """saveheader.read_header, plus 1.0/1.1-era saves whose level.dat chunks
    are stored raw rather than zlib-compressed inside the zip."""
    try:
        return saveheader.read_header(save)
    except zlib.error:
        pass

    def raw_stream(path, limit_chunks=1):
        with zipfile.ZipFile(path) as z:
            names = sorted((n for n in z.namelist() if Path(n).name.startswith("level.dat")
                            and not n.endswith("metadata")),
                           key=lambda n: int(Path(n).name[len("level.dat"):] or -1))
            return z.read(names[0])

    orig = saveheader.level_stream
    saveheader.level_stream = raw_stream
    try:
        return saveheader.read_header(save)
    finally:
        saveheader.level_stream = orig

RUNS = BENCH / "runs"


def _vkey(v: str):
    return tuple(int(x) for x in re.findall(r"\d+", v))


def _scan(d: Path) -> dict:
    """name -> {version: path} for zipped and unpacked mods in d."""
    found = {}
    if not d.is_dir():
        return found
    for p in d.iterdir():
        if p.suffix == ".zip":
            m = re.match(r"(.+)_(\d+\.\d+\.\d+)\.zip$", p.name)
            if m:
                found.setdefault(m.group(1), {}).setdefault(m.group(2), p)
        elif p.is_dir() and (p / "info.json").exists():
            info = json.loads((p / "info.json").read_text())
            found.setdefault(info["name"], {}).setdefault(info["version"], p)
    return found


def mod_sources(save: Path) -> list:
    """Directories searched for a save's mods, most specific first."""
    dirs = []
    sidecar = save.with_suffix(".mods")
    if sidecar.is_dir():
        dirs.append(sidecar)
    dirs.append(MODS_DIR)
    dirs.extend(EXTRA_MOD_DIRS)
    return dirs


def build_run_dir(save: Path, root: Path) -> dict:
    """Assemble root/{mods,write,config.ini} for save. Returns a description.

    Exact version matches win; otherwise the highest available version is used
    and reported, because a pY save loaded against a different version is a
    different benchmark.
    """
    header = read_header(save)
    run_mods, write = root / "mods", root / "write"
    for d in (run_mods, write):
        shutil.rmtree(d, ignore_errors=True)
        d.mkdir(parents=True)

    pools = [_scan(d) for d in mod_sources(save)]
    builtin = {p.name for p in DATA_DIR.iterdir() if (p / "info.json").exists()}
    entries, missing, substituted = [], [], []
    for m in header["mods"]:
        name, want = m["name"], m["version"]
        if name in builtin:
            entries.append({"name": name, "enabled": True})
            continue
        # Compare numerically: a zip may be named 0.1.01 for version 0.1.1.
        src = next((p for pool in pools for v, p in pool.get(name, {}).items()
                    if _vkey(v) == _vkey(want)), None)
        if src is None:
            cands = [(v, p) for pool in pools for v, p in pool.get(name, {}).items()]
            if not cands:
                missing.append(f"{name} {want}")
                continue
            v, src = max(cands, key=lambda c: _vkey(c[0]))
            substituted.append(f"{name} {want} -> {v}")
        link = run_mods / src.name
        if not link.exists():
            link.symlink_to(src.resolve())
        entries.append({"name": name, "enabled": True})
    # Builtin mods the save predates (2.1 split recycler out of quality /
    # space-age) are enabled when an enabled builtin requires them.
    enabled = {e["name"] for e in entries}
    changed = True
    while changed:
        changed = False
        for name in sorted(enabled & builtin):
            for dep in json.loads((DATA_DIR / name / "info.json").read_text()).get("dependencies", []):
                dep = dep.strip()
                if dep[:1] in "?!(~":
                    continue
                dname = dep.split()[0]
                if dname in builtin and dname not in enabled:
                    enabled.add(dname)
                    entries.append({"name": dname, "enabled": True})
                    changed = True
    for name in builtin - enabled:
        entries.append({"name": name, "enabled": False})
    (run_mods / "mod-list.json").write_text(json.dumps({"mods": entries}, indent=2))

    config_ini = root / "config.ini"
    config_ini.write_text(
        f"[path]\nread-data={DATA_DIR}\nwrite-data={write}\n\n[general]\nlocale=en\n")
    return {"header": header, "config": config_ini, "mods": run_mods, "write": write,
            "missing": missing, "substituted": substituted}


def sync_settings(run: dict, save: Path, timeout: int = 1800) -> str:
    """Let Factorio write mod-list.json and mod-settings.dat from the save, so
    startup settings match what the save was built with. Only touches the
    isolated mod directory."""
    proc = subprocess.run(
        [str(BINARY), "--config", str(run["config"]), "--mod-directory", str(run["mods"]),
         "--sync-mods", str(save), "--disable-audio"],
        capture_output=True, text=True, timeout=timeout)
    return (proc.stdout + proc.stderr)[-2000:]
