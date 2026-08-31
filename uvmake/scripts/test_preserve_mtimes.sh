#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Self-test for scripts/preserve_mtimes.sh.
#
# The script is small but subtle, and getting it wrong is not loud: restoring
# too much means edits silently do not rebuild, restoring too little means
# every build is a full rebuild.  Both failure modes look like "it worked".
#
#   ./scripts/test_preserve_mtimes.sh
# ---------------------------------------------------------------------------
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/preserve_mtimes.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fail=0
check() { # <what> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    echo "  ok    $1"
  else
    echo "  FAIL  $1: expected '$2', got '$3'"; fail=1
  fi
}

d="$WORK/obj"; mkdir -p "$d"
for i in 1 2 3 4 5; do echo "content $i" > "$d/f$i.cpp"; done
# Two distinct timestamps, so the grouping path is exercised.
touch -d "@1700000000" "$d/f1.cpp" "$d/f2.cpp" "$d/f3.cpp"
touch -d "@1700000500" "$d/f4.cpp" "$d/f5.cpp"

"$SCRIPT" snapshot "$d"

# Stand in for Verilator: rewrite everything, but only change f3's content.
for i in 1 2 4 5; do echo "content $i" > "$d/f$i.cpp"; done
echo "content 3 CHANGED" > "$d/f3.cpp"
now=$(stat -c %Y "$d/f1.cpp")

"$SCRIPT" restore "$d"

echo "preserve_mtimes:"
check "unchanged file keeps its old mtime"        "1700000000" "$(stat -c %Y "$d/f1.cpp")"
check "unchanged file in 2nd time group"          "1700000500" "$(stat -c %Y "$d/f4.cpp")"
check "changed file keeps the NEW mtime"          "$now"       "$(stat -c %Y "$d/f3.cpp")"
check "manifest is cleaned up"                    "absent"     "$([[ -e $d/.vlt_mtimes ]] && echo present || echo absent)"

# A restore with no snapshot must be a harmless no-op, not an error.
rm -f "$d/.vlt_mtimes"
"$SCRIPT" restore "$d"
check "restore without a snapshot succeeds"       "0"          "$?"

# A snapshot of a directory that does not exist yet (first ever build).
"$SCRIPT" snapshot "$WORK/does-not-exist"
check "snapshot of a missing directory succeeds"  "0"          "$?"

echo
if (( fail )); then echo "FAILED"; exit 1; fi
echo "all checks passed"
