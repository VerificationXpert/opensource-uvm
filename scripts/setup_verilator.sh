#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scripts/setup_verilator.sh - build and install a Verilator new enough for
# this flow.
#
# Distribution packages lag well behind: Ubuntu 24.04 ships 5.020, which
# predates a good deal of the class, constraint and timing support that
# compiling upstream UVM depends on.  This installs a pinned release from
# source instead.
#
#   sudo ./scripts/setup_verilator.sh                 # default version+prefix
#   VERILATOR_VERSION=v5.048 ./scripts/setup_verilator.sh
#   PREFIX=$HOME/.local/verilator ./scripts/setup_verilator.sh
# ---------------------------------------------------------------------------
set -euo pipefail

VERILATOR_VERSION="${VERILATOR_VERSION:-v5.050}"
PREFIX="${PREFIX:-/opt/verilator-${VERILATOR_VERSION#v}}"
SRC_DIR="${SRC_DIR:-/tmp/verilator-src}"
JOBS="${JOBS:-$(nproc)}"

echo "Verilator $VERILATOR_VERSION -> $PREFIX (jobs=$JOBS)"

# Build dependencies, plus the compression libraries the FST trace back end
# needs (liblz4-dev and libzstd-dev are easy to miss: without them
# verilated_fst_c.cpp fails on a missing lz4.h only when you first enable
# FST tracing).
if command -v apt-get >/dev/null; then
  echo "==> installing build dependencies"
  apt-get update -qq
  # z3 is not a Verilator build dependency but a run-time one: Verilator
  # hands SystemVerilog constraints to an external SMT solver, and without
  # it every constrained randomize() returns 0.
  apt-get install -y --no-install-recommends \
    git perl python3 make autoconf g++ flex bison ccache \
    libfl-dev zlib1g-dev liblz4-dev libzstd-dev help2man numactl z3
fi

echo "==> fetching sources"
rm -rf "$SRC_DIR"
git clone --depth 1 -b "$VERILATOR_VERSION" \
  https://github.com/verilator/verilator.git "$SRC_DIR"

echo "==> building"
cd "$SRC_DIR"
autoconf
./configure --prefix="$PREFIX"
make -j"$JOBS"
make install

echo
echo "Installed: $("$PREFIX/bin/verilator" --version)"
echo
echo "Constraint solver: $(z3 --version 2>/dev/null || echo 'z3 NOT FOUND - constrained randomize() will not work')"
echo
echo "Add to your environment:"
echo "  export PATH=$PREFIX/bin:\$PATH"
