# ---------------------------------------------------------------------------
# mk/config.mk - user-facing knobs for the open-source UVM flow.
#
# Every variable here is overridable on the command line or from the
# environment, e.g.:
#     make -C tb/apb run TEST=apb_rw_test TRACE=fst BUILD_MODE=opt
# ---------------------------------------------------------------------------

# Absolute path to the repository root, derived from this file's location so
# testbenches can live at any depth.
REPO_ROOT := $(patsubst %/,%,$(dir $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))))

# --- Tools -----------------------------------------------------------------
VERILATOR      ?= verilator
VERILATOR_ROOT ?= $(shell $(VERILATOR) --getenv VERILATOR_ROOT 2>/dev/null)
CXX            ?= g++

# ccache gives the single biggest incremental-build win on this flow: the
# generated C++ for the UVM package is byte-identical between rebuilds
# whenever the UVM sources and the set of used specialisations have not
# changed, so recompiling a test hits cache on nearly every UVM object.
# Verilator honours OBJCACHE for the objects it compiles.
OBJCACHE ?= $(if $(shell command -v ccache 2>/dev/null),ccache,)

# Parallelism. Verilator 5 splits verilation and C++ compilation into two
# separately schedulable pools.
JOBS         ?= $(shell nproc 2>/dev/null || echo 4)
VERILATE_JOBS ?= $(JOBS)
BUILD_JOBS    ?= $(JOBS)

# --- UVM library -----------------------------------------------------------
# Which UVM implementation to build against:
#   accellera : upstream Accellera uvm-core, IEEE 1800.2-2020 (2020.3.1).
#               Newer, and brings the compiled-regex LRU cache, uvm_phase_hopper
#               and the resource-pool rework - all runtime wins.
#   antmicro  : antmicro/uvm-verilator, IEEE 1800.2-2017 1.0 with Verilator
#               patches. The historical choice; kept for comparison.
UVM_FLAVOR ?= accellera

UVM_ACCELLERA_URL ?= https://github.com/accellera-official/uvm-core.git
UVM_ACCELLERA_REV ?= 2020.3.1
UVM_ANTMICRO_URL  ?= https://github.com/antmicro/uvm-verilator
UVM_ANTMICRO_REV  ?= current-patches

UVM_DIR  ?= $(REPO_ROOT)/.uvm/$(UVM_FLAVOR)
UVM_HOME ?= $(UVM_DIR)
UVM_SRC  ?= $(UVM_HOME)/src

# Enable the UVM DPI layer. Upstream UVM prints
#   "We are thinking of removing support for UVM_NO_DPI"
# when it is switched off, and turning it off costs real functionality:
# regular expressions degrade to glob-only matching, the command-line
# processor loses +uvm_set_* handling, and uvm_reg backdoor access is gone.
# See lib/dpi/ for the Verilator backend that makes DPI usable here.
UVM_DPI ?= 1

# Width of the widest field the uvm_reg backdoor can access.  This sizes the
# arrays UVM passes across the DPI boundary, so the SystemVerilog compile and
# the DPI library must agree; both are driven from this one variable.
UVM_HDL_MAX_WIDTH ?= 1024

# Passive polling API (UVM 2020.3, uvm_hdl_polling.c). Off by default; the
# stubs in uvm_dpi_verilator.cpp report cleanly if a test calls into it.
UVM_VLT_POLLING ?= 0

# --- Build behaviour -------------------------------------------------------
# BUILD_MODE selects the compile-time/run-time trade-off, mirroring the
# -fastcompile / -O style switches commercial simulators offer:
#   fast  : minimise turnaround. -O0 on generated code, no decoration.
#           The right default while writing tests.
#   opt   : minimise simulation wall time. -O2. Use for long regressions.
#   debug : -O0 -g, symbols kept, for gdb on the model itself.
BUILD_MODE ?= fast

# Waveforms are opt-in. Tracing UVM class code makes Verilator emit trace
# registration for every class member, which is one of the largest single
# contributors to compile time in the original flow.
#   none | vcd | fst
TRACE ?= none

# Precompiled shared libraries. When 1, the Verilator runtime and the UVM
# DPI layer are built once into .so files under .lib/ and linked by every
# testbench, instead of being recompiled into each simulation binary.
USE_SHARED_LIBS ?= 1

# Use Verilator's precompiled header. On by default: measured on tb/minimal
# it compiles a translation unit in 2.4s instead of 6.4s, a 2.7x saving over
# ~2000 files.
#
# The PCH is only safe to leave on because scripts/preserve_mtimes.sh stops
# Verilator's unconditional rewriting of unchanged output from invalidating
# it on every run; without that, every object depends on a ~290 MB .gch that
# is regenerated each time and a one-line edit costs a full rebuild. PCH=0
# selects the rules in mk/model.mk instead.
PCH ?= 1

# How aggressively Verilator splits the generated C++ into translation units.
# Verilator's own default is 20000 statements. Lowering it improves -j
# scaling and ccache granularity at the cost of more compiler invocations;
# see docs/COMPILE_TIME.md for the measurements behind this default.
OUTPUT_SPLIT        ?= 20000
OUTPUT_SPLIT_CFUNCS ?= 2000

# Directory for the shared build products (UVM checkout, .so files).
LIB_DIR   ?= $(REPO_ROOT)/.lib
BUILD_ROOT ?= build

# --- Constraint solver -----------------------------------------------------
# Verilator does not solve SystemVerilog constraints itself; it hands them to
# an external SMT solver, z3 by default (override with VERILATOR_SOLVER).
#
# This is a hard requirement for UVM, and its absence is nastier than a
# missing tool usually is: every constrained randomize() simply returns 0.
# A sequence that randomises its item silently generates nothing, and a test
# either fails with an unhelpful message or - worse - passes without having
# randomised anything. Check for it up front.
SOLVER := $(firstword $(if $(VERILATOR_SOLVER),$(VERILATOR_SOLVER),z3))
ifeq ($(shell command -v $(SOLVER) 2>/dev/null),)
  $(warning )
  $(warning *** '$(SOLVER)' was not found on PATH.)
  $(warning *** Verilator needs an SMT solver to solve SystemVerilog constraints.)
  $(warning *** Without it EVERY constrained randomize() returns 0 and)
  $(warning *** constrained-random tests are meaningless.)
  $(warning ***   apt-get install z3   (or set VERILATOR_SOLVER))
  $(warning )
endif

# --- Simulation defaults ---------------------------------------------------
TEST      ?=
UVM_VERBOSITY ?= UVM_MEDIUM
SEED      ?= 1
TIMESCALE ?= 1ns/1ps
PLUSARGS  ?=
