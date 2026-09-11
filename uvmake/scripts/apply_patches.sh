#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# uvmake/scripts/apply_patches.sh <uvm-dir> [<patch-dir> ...]
#
# Apply a local patch series to a UVM checkout.
#
# Upstream Accellera UVM compiles under Verilator unpatched today, so uvmake
# ships no patches. This exists so that when that stops being true - a
# Verilator regression, a UVM release with a construct Verilator cannot yet
# handle, or a site-specific fix - the change can be carried here as a patch
# against a pinned upstream revision, instead of forking UVM and inheriting
# a fork's maintenance.
#
# Patches apply in lexicographic order, so name them with a numeric prefix:
#
#     uvmake/patches/accellera/0010-fix-whatever.patch
#
# They are applied with `git apply -p1` against the root of the UVM kit, so
# paths in the diff start with src/ (what `git diff` produces from inside a
# UVM checkout).
#
# This is only ever run against a freshly fetched tree - the caller makes the
# patch series part of the checkout's identity, so changing a patch re-fetches
# rather than trying to apply on top of an already-patched tree.
# ---------------------------------------------------------------------------
set -uo pipefail

uvm_dir="${1:-}"
shift || true
[[ -n $uvm_dir && -d $uvm_dir ]] || { echo "usage: $0 <uvm-dir> [patch-dir ...]" >&2; exit 2; }

# Collect the series, in order, across every directory given.
#
# Paths are absolutised: `git -C <dir> apply <relative>` resolves the patch
# relative to <dir>, not to the current directory, so a relative path here
# would look for the patch inside the UVM kit.
patches=()
for dir in "$@"; do
  [[ -d $dir ]] || continue
  dir=$(cd "$dir" && pwd)
  while IFS= read -r p; do patches+=("$p"); done \
    < <(find "$dir" -maxdepth 1 \( -name '*.patch' -o -name '*.diff' \) | sort)
done

if (( ${#patches[@]} == 0 )); then
  exit 0
fi

# `git apply` resolves paths against the top of the enclosing work tree, not
# against -C. A copied UVM kit has no .git of its own and usually sits inside
# the project's repository (the cache lives under it), so without this git
# would silently apply relative to the *project* root instead of the kit -
# reporting success while changing nothing. Giving the kit its own work tree
# makes the target unambiguous, and leaves it diffable: `git diff` inside it
# shows exactly what the series changed.
if [[ "$(git -C "$uvm_dir" rev-parse --show-toplevel 2>/dev/null)" != "$(cd "$uvm_dir" && pwd)" ]]; then
  git -C "$uvm_dir" init -q
  # Commit the pristine kit first, so `git diff` inside the tree afterwards
  # shows exactly what the patch series changed and nothing else.
  git -C "$uvm_dir" -c user.name=uvmake -c user.email=uvmake@localhost \
      -c commit.gpgsign=false add -A >/dev/null 2>&1
  git -C "$uvm_dir" -c user.name=uvmake -c user.email=uvmake@localhost \
      -c commit.gpgsign=false commit -qm "pristine UVM kit before local patches" \
      >/dev/null 2>&1
fi

echo "[uvm]     applying ${#patches[@]} local patch(es)"

for patch in "${patches[@]}"; do
  name=$(basename "$patch")

  # Check before applying so a failure names the patch and leaves the tree
  # untouched, rather than half-applying a series.
  if ! git -C "$uvm_dir" apply --check -p1 "$patch" 2>/dev/null; then
    echo >&2
    echo "error: patch does not apply: $name" >&2
    echo "       against: $uvm_dir" >&2
    echo >&2
    git -C "$uvm_dir" apply --check -p1 "$patch" 2>&1 | sed 's/^/       /' >&2
    echo >&2
    echo "       The UVM revision was probably bumped without refreshing the" >&2
    echo "       patch. Re-cut it against the pinned revision, or drop it if" >&2
    echo "       upstream has fixed the issue." >&2
    exit 1
  fi

  git -C "$uvm_dir" apply -p1 "$patch" || {
    echo "error: applying $name failed after --check passed" >&2
    exit 1
  }

  # Post-condition: an applied patch must reverse-apply cleanly. This is what
  # catches a patch that "succeeded" without touching the intended tree -
  # exactly the failure the git-init above prevents, caught rather than
  # trusted.
  if ! git -C "$uvm_dir" apply --reverse --check -p1 "$patch" 2>/dev/null; then
    echo >&2
    echo "error: $name reported success but is not present in the tree" >&2
    echo "       target: $uvm_dir" >&2
    echo "       This usually means the patch applied somewhere unintended." >&2
    exit 1
  fi

  echo "[uvm]       $name"
done
