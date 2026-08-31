#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scripts/check_log.sh <logfile> - decide whether a UVM run passed.
#
# Grepping for "UVM_ERROR" does not work: UVM's own end-of-run summary prints
# the line "UVM_ERROR :    0", so a clean run looks like a failure.  The
# counts in that summary are the authoritative result, and the summary's
# absence means the simulation died before it could report - also a failure.
#
# Exits 0 on pass, 1 on fail, and prints a one-line reason either way.
# ---------------------------------------------------------------------------
set -uo pipefail

log="${1:-}"
[[ -n $log && -f $log ]] || { echo "FAIL: no log file '${log:-}'"; exit 1; }

# UVM prints, under "** Report counts by severity":
#     UVM_INFO :    3
#     UVM_ERROR :    0
# Take the last occurrence, so a test that prints the words earlier in its
# own messages cannot affect the verdict.
count_of() {
  awk -v sev="$1" '
    $1 == sev && $2 == ":" { n = $3 }
    END { print (n == "" ? "" : n) }
  ' "$log"
}

if ! grep -q "UVM Report Summary" "$log"; then
  # No summary: the run never reached report_phase.
  if grep -qE "UVM_FATAL" "$log"; then
    echo "FAIL: UVM_FATAL before the report summary"
  else
    echo "FAIL: simulation ended without a UVM report summary (crash or timeout?)"
  fi
  exit 1
fi

errors=$(count_of UVM_ERROR)
fatals=$(count_of UVM_FATAL)
warns=$(count_of UVM_WARNING)

[[ -n $errors && -n $fatals ]] || { echo "FAIL: could not parse the UVM report summary"; exit 1; }

if (( errors > 0 || fatals > 0 )); then
  echo "FAIL: $errors UVM_ERROR, $fatals UVM_FATAL"
  exit 1
fi

echo "PASS: 0 UVM_ERROR, 0 UVM_FATAL, ${warns:-0} UVM_WARNING"
