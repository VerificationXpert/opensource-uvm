#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# uvmake/scripts/selftest.sh - unit tests for the parts of uvmake that are
# easy to break silently.
#
#   ./uvmake/scripts/selftest.sh
# ---------------------------------------------------------------------------
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fail=0
check() { # <what> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    echo "  ok    $1"
  else
    echo "  FAIL  $1"
    echo "          expected: $2"
    echo "          actual:   $3"
    fail=1
  fi
}

# ---------------------------------------------------------------------------
echo "expand_filelist:"

d="$WORK/fl"; mkdir -p "$d/rtl" "$d/tb" "$d/sub"
touch "$d/rtl/dut.sv" "$d/tb/pkg.sv" "$d/tb/top.sv" "$d/sub/extra.sv"

cat > "$d/top.f" <<'FL'
// a comment
+incdir+tb
+define+WIDTH=8+DEBUG
rtl/dut.sv        # trailing comment
-f sub/sub.f
$MYROOT/tb/pkg.sv
tb/top.sv
FL
cat > "$d/sub/sub.f" <<'FL'
-- paths here are relative to sub/
extra.sv
FL

out=$(MYROOT="$d" "$HERE/expand_filelist.py" "$d/top.f" 2>/dev/null)
srcs=$(sed -n 's/^FL_SOURCES := //p' <<<"$out" | tr ' ' '\n' | sed "s|$d/||" | tr '\n' ' ' | sed 's/ $//')
incs=$(sed -n 's/^FL_INCDIRS := //p' <<<"$out" | tr ' ' '\n' | sed "s|$d/||" | tr '\n' ' ' | sed 's/ $//')
defs=$(sed -n 's/^FL_DEFINES := //p' <<<"$out")

# -f is expanded in place, so extra.sv lands between dut.sv and pkg.sv.
check "compile order preserved through -f" "rtl/dut.sv sub/extra.sv tb/pkg.sv tb/top.sv" "$srcs"
check "incdir resolved"                    "tb"                                          "$incs"
check "defines collected"                  "WIDTH=8 DEBUG"                               "$defs"
check "nested relative path"               "1"  "$(grep -c 'sub/extra.sv' <<<"$out")"

# An undefined variable must be an error, not an empty expansion that
# silently drops a source file.
cat > "$d/bad.f" <<'FL'
$NOT_SET_ANYWHERE/x.sv
FL
"$HERE/expand_filelist.py" "$d/bad.f" >/dev/null 2>&1
check "undefined variable fails loudly" "1" "$?"

# A cycle must terminate rather than recurse forever.
printf -- '-f b.f\n' > "$d/a.f"
printf -- '-f a.f\n' > "$d/b.f"
timeout 10 "$HERE/expand_filelist.py" "$d/a.f" >/dev/null 2>&1
check "cyclic -f terminates" "0" "$?"

# ---------------------------------------------------------------------------
echo "regress list parsing:"

python3 - "$HERE" <<'PY'
import importlib.util, sys, pathlib, tempfile, os
here = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("regress", here / "regress.py")
regress = importlib.util.module_from_spec(spec)
spec.loader.exec_module(regress)

failed = 0
def check(what, expected, actual):
    global failed
    if expected == actual:
        print(f"  ok    {what}")
    else:
        print(f"  FAIL  {what}\n          expected: {expected}\n          actual:   {actual}")
        failed = 1

check("single seed", [7], regress.parse_seeds("7"))
check("seed range", [1, 2, 3], regress.parse_seeds("1-3"))
check("random seed yields one", 1, len(regress.parse_seeds("*")))

for bad in ("3-1", "abc", ""):
    try:
        regress.parse_seeds(bad)
        check(f"bad seed '{bad}' rejected", "raises", "accepted")
    except ValueError:
        check(f"bad seed '{bad}' rejected", "raises", "raises")

with tempfile.TemporaryDirectory() as tmp:
    path = os.path.join(tmp, "r.list")
    with open(path, "w") as fh:
        fh.write("# comment\n\n"
                 "apb  rw_test\n"
                 "apb  rand_test  1-3\n"
                 "apb  cfg_test   5  TRACE=fst UVM_VERBOSITY=UVM_HIGH\n")
    runs = regress.read_list(path)
    check("row count after seed expansion", 5, len(runs))
    check("default seed is 1", 1, runs[0].seed)
    check("range expanded", [1, 2, 3], [r.seed for r in runs[1:4]])
    check("per-run overrides kept",
          ["TRACE=fst", "UVM_VERBOSITY=UVM_HIGH"], runs[4].overrides)
    check("overrides not mistaken for a seed", 5, runs[4].seed)

sys.exit(failed)
PY
[[ $? -eq 0 ]] || fail=1

# ---------------------------------------------------------------------------
echo "apply_patches:"

pd="$WORK/patches"; mkdir -p "$pd"

make_kit() {  # <dir> [--git]
  rm -rf "$1"; mkdir -p "$1/src/base"
  printf 'line one\nline two\nline three\n' > "$1/src/base/thing.svh"
  if [[ ${2:-} == --git ]]; then
    git -C "$1" init -q
    git -C "$1" -c user.name=t -c user.email=t@t add -A >/dev/null
    git -C "$1" -c user.name=t -c user.email=t@t commit -qm base >/dev/null
  fi
}

cat > "$pd/0010-ok.patch" <<'PATCH'
diff --git a/src/base/thing.svh b/src/base/thing.svh
--- a/src/base/thing.svh
+++ b/src/base/thing.svh
@@ -1,3 +1,4 @@
 line one
+PATCHED
 line two
 line three
PATCH

# A kit that is its own git repo (the fetched case).
kit="$WORK/kit-git"; make_kit "$kit" --git
"$HERE/apply_patches.sh" "$kit" "$pd" >/dev/null 2>&1
check "applies to a git-repo kit" "1" "$(grep -c PATCHED "$kit/src/base/thing.svh")"

# A kit with no git of its own, sitting inside another repository. git apply
# resolves against the *enclosing* work tree, so without the fix this
# reported success while changing nothing.
outer="$WORK/outer"; mkdir -p "$outer"
git -C "$outer" init -q
kit2="$outer/nested-kit"; make_kit "$kit2"
"$HERE/apply_patches.sh" "$kit2" "$pd" >/dev/null 2>&1
check "applies inside an enclosing repo" "1" "$(grep -c PATCHED "$kit2/src/base/thing.svh")"
check "enclosing repo untouched" "0" "$(ls "$outer/src" 2>/dev/null | wc -l)"

# Ordering: patches apply lowest-numbered first.
cat > "$pd/0020-second.patch" <<'PATCH'
diff --git a/src/base/thing.svh b/src/base/thing.svh
--- a/src/base/thing.svh
+++ b/src/base/thing.svh
@@ -1,4 +1,5 @@
 line one
 PATCHED
+SECOND
 line two
 line three
PATCH
kit3="$WORK/kit-order"; make_kit "$kit3" --git
"$HERE/apply_patches.sh" "$kit3" "$pd" >/dev/null 2>&1
check "series applies in order" "PATCHED SECOND" \
      "$(sed -n '2p;3p' "$kit3/src/base/thing.svh" | tr '\n' ' ' | sed 's/ $//')"
rm -f "$pd/0020-second.patch"

# A patch whose context is wrong must fail, and must not half-apply.
bad="$WORK/bad"; mkdir -p "$bad"
sed 's/^ line one/ NOT THE REAL CONTEXT/' "$pd/0010-ok.patch" > "$bad/0010-bad.patch"
kit4="$WORK/kit-bad"; make_kit "$kit4" --git
"$HERE/apply_patches.sh" "$kit4" "$bad" >/dev/null 2>&1
check "bad patch fails"            "1" "$?"
check "bad patch leaves tree clean" "0" "$(grep -c PATCHED "$kit4/src/base/thing.svh")"

# No patches at all is a silent success, not an error.
empty="$WORK/empty"; mkdir -p "$empty"
kit5="$WORK/kit-none"; make_kit "$kit5" --git
"$HERE/apply_patches.sh" "$kit5" "$empty" >/dev/null 2>&1
check "empty series succeeds" "0" "$?"

# ---------------------------------------------------------------------------
echo "preserve_mtimes:"
"$HERE/test_preserve_mtimes.sh" 2>&1 | sed -n 's/^  \(ok\|FAIL\)/  \1/p'
"$HERE/test_preserve_mtimes.sh" >/dev/null 2>&1 || fail=1

# ---------------------------------------------------------------------------
echo
if (( fail )); then echo "SELFTEST FAILED"; exit 1; fi
echo "all uvmake self-tests passed"
