#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# uvmake/scripts/setup_verilator.sh - build and install a Verilator new enough
# for this flow, plus the runtime dependencies UVM needs.
#
# Distribution packages lag well behind: Ubuntu 24.04 ships 5.020, which
# predates a good deal of the class, constraint and timing support that
# compiling upstream UVM depends on.
#
#   ./setup_verilator.sh                          # default version, /opt
#   PREFIX=$HOME/verilator ./setup_verilator.sh   # no root needed for install
#   VERILATOR_VERSION=v5.048 ./setup_verilator.sh
#   SKIP_DEPS=1 ./setup_verilator.sh              # packages already installed
#
# sudo is used automatically for the package install when not running as
# root, so the whole script does not have to run privileged - which matters
# when PREFIX is inside your home directory, and in CI.
# ---------------------------------------------------------------------------
set -euo pipefail

VERILATOR_VERSION="${VERILATOR_VERSION:-v5.050}"
PREFIX="${PREFIX:-/opt/verilator-${VERILATOR_VERSION#v}}"
SRC_DIR="${SRC_DIR:-/tmp/verilator-src}"
JOBS="${JOBS:-$(nproc)}"
SKIP_DEPS="${SKIP_DEPS:-0}"

if [[ $EUID -eq 0 ]]; then
  SUDO=""
elif command -v sudo >/dev/null; then
  SUDO="sudo"
else
  SUDO=""
fi

echo "Verilator $VERILATOR_VERSION -> $PREFIX (jobs=$JOBS)"

# Build dependencies, plus two runtime ones that are easy to miss:
#
#   liblz4-dev / libzstd-dev  the FST trace back end compresses with them, so
#                             without them verilated_fst_c.cpp fails on a
#                             missing lz4.h - but only once you enable FST.
#   z3                        Verilator does not solve SystemVerilog
#                             constraints itself; it shells out to an SMT
#                             solver. Without one, every constrained
#                             randomize() returns 0 and constrained-random
#                             tests are meaningless.
if [[ $SKIP_DEPS != 1 ]] && command -v apt-get >/dev/null; then
  echo "==> installing dependencies"
  $SUDO apt-get update -qq
  $SUDO apt-get install -y --no-install-recommends \
    git perl python3 make autoconf g++ flex bison ccache \
    libfl-dev zlib1g-dev liblz4-dev libzstd-dev help2man numactl z3
elif [[ $SKIP_DEPS == 1 ]]; then
  echo "==> skipping dependency install (SKIP_DEPS=1)"
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

# Only the install step can need privilege, and only when PREFIX is outside
# a writable location.
if [[ -w "$(dirname "$PREFIX")" ]] || [[ -w "$PREFIX" ]] 2>/dev/null; then
  make install
else
  $SUDO make install
fi

echo
echo "Installed: $("$PREFIX/bin/verilator" --version)"
if command -v z3 >/dev/null; then
  echo "Solver:    $(z3 --version)"
else
  echo "Solver:    z3 NOT FOUND - constrained randomize() will not work"
fi
echo
echo "Add to your environment:"
echo "  export PATH=$PREFIX/bin:\$PATH"
