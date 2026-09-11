#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scripts/benchmark.sh - compile-time measurements for the UVM/Verilator flow.
#
# Each configuration is built from a clean object directory with a cleared
# ccache, so the numbers are cold-build numbers.  The incremental case is
# measured separately, by touching one testbench file and rebuilding.
#
#   ./scripts/benchmark.sh              # all configurations, minimal TB
#   ./scripts/benchmark.sh -t apb       # against the APB testbench
#   ./scripts/benchmark.sh -c opt       # a single named configuration
#
# Results are appended to build/benchmark.csv.
# ---------------------------------------------------------------------------
set -uo pipefail

# uvmake may be vendored anywhere, so the project it is measuring cannot be
# inferred from this script's location. Take it from the environment (the
# 'bench' target exports it) or the working directory.
PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"
TB=minimal
TB_DIRS_DEFAULT="$PROJECT_ROOT/tb"
ONLY=""

usage() { sed -n '2,16p' "$0"; exit "${1:-0}"; }

while getopts ":t:c:h" opt; do
  case $opt in
    t) TB="$OPTARG" ;;
    c) ONLY="$OPTARG" ;;
    h) usage 0 ;;
    *) usage 1 ;;
  esac
done

TB_DIR="${TB_DIRS:-$TB_DIRS_DEFAULT}/$TB"
[[ -d $TB_DIR ]] || { echo "no such testbench: $TB_DIR" >&2; exit 1; }

RESULTS="$PROJECT_ROOT/build/benchmark.csv"
mkdir -p "$(dirname "$RESULTS")"
[[ -f $RESULTS ]] || echo "timestamp,testbench,config,stage,seconds,cpp_files" > "$RESULTS"

# --- configurations --------------------------------------------------------
# Each entry is a name and the make variables that define it.  "legacy"
# reproduces the settings the original flow used (always-on VCD tracing, -Os
# on the model, runtime recompiled into the binary); the others turn the
# levers on one at a time so the contribution of each is visible.
declare -A CONFIGS=(
  [legacy]="BUILD_MODE=opt TRACE=vcd USE_SHARED_LIBS=0 UVM_DPI=0 UVM_FLAVOR=antmicro"
  [notrace]="BUILD_MODE=opt TRACE=none USE_SHARED_LIBS=0 UVM_DPI=0 UVM_FLAVOR=antmicro"
  [fastcompile]="BUILD_MODE=fast TRACE=none USE_SHARED_LIBS=0 UVM_DPI=0 UVM_FLAVOR=antmicro"
  [sharedlibs]="BUILD_MODE=fast TRACE=none USE_SHARED_LIBS=1 UVM_DPI=0 UVM_FLAVOR=antmicro"
  [default]="BUILD_MODE=fast TRACE=none USE_SHARED_LIBS=1 UVM_DPI=1 UVM_FLAVOR=accellera"
  [opt]="BUILD_MODE=opt TRACE=none USE_SHARED_LIBS=1 UVM_DPI=1 UVM_FLAVOR=accellera"
)
ORDER=(legacy notrace fastcompile sharedlibs default opt)

now() { date +%s.%N; }
delta() { echo "$1 $2" | awk '{printf "%.1f", $2-$1}'; }

record() {
  printf '%s,%s,%s,%s,%s,%s\n' \
    "$(date -Is)" "$TB" "$1" "$2" "$3" "${4:-}" >> "$RESULTS"
  printf '  %-12s %-16s %8ss  %s\n' "$1" "$2" "$3" "${4:-}"
}

run_config() {
  local name="$1" vars="${CONFIGS[$1]}"
  echo "=== $name : $vars"

  # Cold: no object directory, no ccache entries.
  make -C "$TB_DIR" clean >/dev/null 2>&1
  command -v ccache >/dev/null && ccache -C >/dev/null 2>&1

  local t0 t1 t2 objdir
  t0=$(now)
  if ! make -C "$TB_DIR" $vars verilate >/dev/null 2>&1; then
    record "$name" verilate FAILED; return 1
  fi
  t1=$(now)
  record "$name" verilate "$(delta "$t0" "$t1")"

  objdir=$(make -C "$TB_DIR" $vars -s print-objdir 2>/dev/null)
  local nfiles=""
  [[ -d $objdir ]] && nfiles=$(find "$objdir" -name '*.cpp' | wc -l)

  if ! make -C "$TB_DIR" $vars build >/dev/null 2>&1; then
    record "$name" build FAILED "$nfiles"; return 1
  fi
  t2=$(now)
  record "$name" build "$(delta "$t1" "$t2")" "$nfiles"
  record "$name" cold-total "$(delta "$t0" "$t2")" "$nfiles"

  # Incremental: edit one testbench file and rebuild.  This is the number
  # that actually governs day-to-day turnaround, and the one ccache and a
  # finer --output-split are there to protect.
  local src
  src=$(find "$TB_DIR" -name '*_tb_top.sv' | head -1)
  if [[ -n $src ]]; then
    touch "$src"
    t0=$(now)
    make -C "$TB_DIR" $vars build >/dev/null 2>&1
    t1=$(now)
    record "$name" incremental "$(delta "$t0" "$t1")" "$nfiles"
  fi
}

echo "Verilator: $(verilator --version 2>/dev/null)"
echo "CPUs:      $(nproc)"
echo "Results:   $RESULTS"
echo

if [[ -n $ONLY ]]; then
  [[ -v CONFIGS[$ONLY] ]] || { echo "unknown config: $ONLY" >&2; exit 1; }
  run_config "$ONLY"
else
  for c in "${ORDER[@]}"; do run_config "$c"; done
fi

echo
echo "--- summary (seconds) ---"
awk -F, 'NR>1 && $2=="'"$TB"'" {printf "%-12s %-12s %8s\n", $3, $4, $5}' "$RESULTS"
