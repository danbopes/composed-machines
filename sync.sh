#!/usr/bin/env bash
# Re-copy the published parts of the private working tree into this repository.
#
# Usage: ./sync.sh [--no-mod] [SRC_ROOT]
#   --no-mod   skip mod/ and harness/ (copy only model/, bench/ and docs/)
#   SRC_ROOT   the factorio directory holding component/ and ai-harness/
#              (default: the parent of this repository)
#
# Idempotent: every target is synced with rsync --delete, so files removed at the
# source disappear here too. Build outputs, saves, run directories and scratch
# space are never copied.
set -euo pipefail

with_mod=1
if [[ "${1:-}" == "--no-mod" ]]; then with_mod=0; shift; fi
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then sed -n '2,12p' "$0"; exit 0; fi

repo="$(cd "$(dirname "$0")" && pwd)"
src="${1:-$(dirname "$repo")}"
comp="$src/component"
harness="$src/ai-harness"

[[ -d "$comp" ]] || { echo "no component/ under $src" >&2; exit 1; }

rs=(rsync -a --delete --prune-empty-dirs)

"${rs[@]}" \
  --exclude 'scratch/' --exclude '*.o' --exclude '/model' --exclude '/model-clang' \
  --include '*/' --include '*.cpp' --include '*.h' --include '*.hpp' \
  --include 'Makefile' --include 'run.sh' --include '*.md' \
  --exclude '*' \
  "$comp/model/" "$repo/model/"

"${rs[@]}" \
  --exclude 'saves/' --exclude 'runs/' --exclude 'scratch/' --exclude '__pycache__/' \
  --include '/benchlib.py' --include '/make_save.py' --include '/run_bench.py' \
  --include '/bench_save.py' --include '/suite.py' --include '/census_save.py' \
  --include '/fetch_mulark.py' --include '/report.py' --include '/measure.sh' \
  --include '/RESULTS.md' --include '/RESULTS.notes.md' --include '/README.md' \
  --include '/builds/' --include '/builds/**' \
  --include '/census-mod/' --include '/census-mod/**' \
  --include '/results/' --include '/results/*.jsonl' --include '/results/*.census.json' \
  --exclude '*' \
  "$comp/bench/" "$repo/bench/"

mkdir -p "$repo/docs"
rm -f "$repo/docs/TEST-ENTITIES.md"
cp "$comp/design/ENTITIES-public.md" "$repo/docs/ENTITIES.md"
cp "$comp/design/TEST-ENTITIES-2.md" "$repo/docs/TEST-ENTITIES-2.md"

# Make the copied tree self-contained: no absolute paths into the working
# machine, no references to the private notes it was produced alongside.
sanitize() {
  local b="$repo/bench" d="$repo/docs" m="$repo/model"
  local gone='see ../research/pyanodons.md'

  sed -i -E \
    -e 's#"/[^"]*/component/bench/(saves/)#"\1#g' \
    -e 's#"host": "[^"]*"#"host": "bench-host"#g' \
    -e 's#\(\w+ \+ C\+\+ bench#(other analysis + C++ bench#g' \
    "$b"/results/*.jsonl "$b"/results/*.census.json

  sed -i -E \
    -e 's#^import json$#import json\nimport os\nimport shutil#' \
    -e 's#^FACTORIO = Path\("/[^"]*/factorio"\)#FACTORIO = Path(os.environ.get("FACTORIO_DIR", Path.home() / "factorio"))#' \
    -e 's#^FH = Path\("/[^"]*/bin/fh"\)#FH = Path(os.environ.get("FH") or shutil.which("fh") or "fh")#' \
    -e 's#FACTORIO / "component/mod"#BENCH.parent / "mod"#' \
    "$b/benchlib.py"

  sed -i -E \
    -e 's#"/[^"]*/factorio/saves/#"${FACTORIO_DIR:-$HOME/factorio}/saves/#g' \
    "$b/measure.sh"

  sed -i -E \
    -e "s#\(?\`?[a-z]+/pyanodons\.md\`?\)?#($gone)#g" \
    -e 's#component/design/TEST-ENTITIES\.md#../docs/TEST-ENTITIES.md#g' \
    -e "s# \(maybe another agent's\)##; s# \(another agent's\)##" \
    -e 's#"/[^"]*/factorio/saves/#"$FACTORIO_DIR/saves/#g' \
    -e 's#^cd ~/factorio/component/bench$#cd bench#' \
    -e 's#^\(pY\) benchmarked with their own mod list\. Private analysis\.#(pY) benchmarked with their own mod list.#' \
    -e 's#^Taken 2026-11-01 with a \w+ analysis, a C\+\+ benchmark#Taken 2026-11-01 with other analysis work, a C++ benchmark#' \
    -e 's#^They stay private here\.#They are not included in this repository.#' \
    "$b"/README.md "$b"/RESULTS.md "$b"/report.py "$b"/census_save.py "$b"/make_save.py
  # census_save.py's docstring reads "families that <x> lists"

  sed -i -E \
    -e 's#^This is a private model, not Factorio\.#This is a model, not Factorio.#' \
    "$m/RESULTS.md"
  sed -i -E -e 's# \(V2-PARTS section 5 item 2\)##' "$m/RESULTS-v2.md"
  sed -i -E -e 's#`CraftingMachine::update`#the crafting-machine update#g; s#`EntityOrderList<[^`]*>::update`#the engine\x27s per-type update loop#g' "$m/RESULTS.md" "$m/RESULTS-v2.md" "$m/README.md"
  sed -i -E -e 's#docs/TEST-ENTITIES\.md#docs/ENTITIES.md#g' "$repo/README.md" "$b/README.md" "$b/RESULTS.md" "$b/RESULTS.notes.md" 2>/dev/null || true
  sed -i -E -e 's#component/design/TEST-ENTITIES-2\.md#../docs/TEST-ENTITIES-2.md#g' "$b/README.md" "$b/RESULTS.md" "$b/RESULTS.notes.md" "$b/make_save.py"
  sed -i -E -e 's#`EntityOrderList` entry#per-type update slot#g' "$m/RESULTS.md"
  sed -i -E -e "s#EntityOrderList<[^>]*>::update#the engine's per-type update loop#g; s#EntityOrderList#per-type update list#g" "$m/model.cpp"

  local note='> Part of the composed-machine proposal. `SPEC.md`, `WRITEUP.txt` and `V2-PARTS.md` are `SPEC.md`, `WRITEUP.md` and `V2-PARTS.md` in this folder; the research notes are in `../research/`.'
  sed -i -E 's#conventions as `TEST-ENTITIES\.md`#conventions as `ENTITIES.md`#' "$d/TEST-ENTITIES-2.md"
  for f in "$d/ENTITIES.md" "$d/TEST-ENTITIES-2.md"; do
    sed -i -E \
      -e 's#^Private\. Eight entities#Eight entities#' \
      -e 's#^Private draft, 2026-11-02\.#Draft, 2026-11-02.#' \
      -e 's#`component/mod/component-lab`#`mod/component-lab`#g' \
      -e 's# \(`[a-z]+/RESEARCH\.md`\)##' \
      "$f"
    perl -0pi -e 's/ \(citations: `research\/\n?forum-dropped-features\.md`, `research\/github-issues\.md`\)//' "$f"
    sed -i "1a\\
\\
$note" "$f"
  done
}
sanitize

if (( with_mod )); then
  mkdir -p "$repo/mod" "$repo/harness/suites"
  "${rs[@]}" --exclude '*.zip' --exclude 'scratch/' \
    "$comp/mod/component-lab/" "$repo/mod/component-lab/"
  "${rs[@]}" "$harness/suites/component-lab/" "$repo/harness/suites/component-lab/"
  cp "$harness/projects/component-lab.json" "$repo/harness/component-lab.json"
  sed -i -E 's#"source": *"[^"]*"#"source": "../mod/component-lab"#' "$repo/harness/component-lab.json"
  rm -f "$repo/mod/README.md" "$repo/harness/README.md"
  sed -i -E 's#~/factorio/component/mod/ws/#mod/ws/#g' "$repo"/mod/component-lab/*.md
  sed -i -E \
    -e 's#`component/design/SPEC\.md`#`../../docs/SPEC.md`#g' \
    -e 's#`component/design/TEST-ENTITIES\.md`#`../../docs/ENTITIES.md`#g' \
    -e 's#`component/design/TEST-ENTITIES-2\.md`#`../../docs/TEST-ENTITIES-2.md`#g' \
    -e 's#component/design/TEST-ENTITIES-2\.md#../../docs/TEST-ENTITIES-2.md#g' \
    -e 's#component/design/TEST-ENTITIES\.md#../../docs/ENTITIES.md#g' \
    "$repo"/mod/component-lab/*.md
fi

echo "synced from $src (mod/harness: $([[ $with_mod == 1 ]] && echo yes || echo skipped))"
