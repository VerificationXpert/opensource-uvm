#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scripts/preserve_mtimes.sh {snapshot|restore} <dir>
#
# Verilator rewrites every file in its output directory on each run, even
# when the new contents are byte-for-byte identical to the old.  For a UVM
# build that is catastrophic for incremental compilation:
#
#   * V<top>__pch.h gets a new mtime, so make rebuilds the ~290 MB
#     precompiled header, which verilated.mk lists as a prerequisite of
#     *every* object - so all ~2000 translation units recompile.
#   * The regenerated .gch has different bytes, so every compile line's
#     -include hash changes and ccache misses on all of them.
#
# Measured on tb/minimal: editing one string inside one test method changed
# the content of exactly zero generated headers, yet bumped the mtime of all
# of them and triggered a full rebuild with a 0% cache hit rate.
#
# This script closes that gap.  'snapshot' records each file's content hash
# and mtime before verilation; 'restore' puts the old mtime back on every
# file whose content did not actually change.  make then sees only the files
# that genuinely differ, the PCH survives, and ccache hits on the rest.
#
# Both passes work in bulk - one md5sum over the whole directory, and one
# touch per distinct timestamp rather than per file - because the directory
# holds several thousand files and a process per file would cost more than
# the compilation it saves.
# ---------------------------------------------------------------------------
set -uo pipefail

action="${1:-}"
dir="${2:-}"
[[ -n $action && -n $dir ]] || { echo "usage: $0 {snapshot|restore} <dir>" >&2; exit 2; }

manifest="$dir/.vlt_mtimes"

# Only the generated sources and headers matter; objects and archives are
# make's own business.
# Only the generated sources and headers matter; objects and archives are
# make's own business.
FILE_GLOBS=( -name '*.cpp' -o -name '*.h' -o -name '*.mk' -o -name '*.dat' )

list_files() {
  find "$dir" -maxdepth 1 -type f \( "${FILE_GLOBS[@]}" \) -print0 2>/dev/null
}

# Content hashes, one md5sum for the whole directory: "<md5>  <path>"
hashes_of() { list_files | xargs -0 -r md5sum 2>/dev/null; }

# Modification times, one find for the whole directory: "<mtime> <path>"
mtimes_of() {
  find "$dir" -maxdepth 1 -type f \( "${FILE_GLOBS[@]}" \) \
       -printf '%Ts %p\n' 2>/dev/null
}

case $action in
  snapshot)
    [[ -d $dir ]] || exit 0          # nothing built yet
    { mtimes_of; echo "--"; hashes_of; } | awk '
      $1 == "--" { split_marker = 1; next }
      !split_marker { mtime[$2] = $1; next }
      { path = $2; if (path in mtime) print mtime[path], $1, path }
    ' > "$manifest" 2>/dev/null
    ;;

  restore)
    [[ -s $manifest ]] || exit 0     # no snapshot: first build

    restored=$(
      { cat "$manifest"; echo "--"; hashes_of; } | awk '
        $1 == "--" { split_marker = 1; next }
        !split_marker { mtime[$3] = $1; hash[$3] = $2; next }
        {
          path = $2
          # Unchanged content: collect the path under its original mtime.
          if (path in hash && hash[path] == $1) group[mtime[path]] = group[mtime[path]] " " path
        }
        END { for (t in group) print t group[t] }
      ' | while read -r mtime paths; do
            [[ -n $paths ]] || continue
            # shellcheck disable=SC2086
            touch -d "@$mtime" $paths 2>/dev/null && wc -w <<<"$paths"
          done | awk '{ n += $1 } END { print n + 0 }'
    )

    rm -f "$manifest"
    [[ -n ${VERBOSE:-} ]] && echo "[mtimes]   kept $restored unchanged file(s)"
    ;;

  *)
    echo "unknown action: $action" >&2; exit 2 ;;
esac
exit 0
