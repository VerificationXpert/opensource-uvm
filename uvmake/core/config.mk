# ---------------------------------------------------------------------------
# uvmake/core/config.mk - every knob, with defaults.
#
# Everything here is overridable from the command line, the environment, or
# the including makefile. Nothing in uvmake/ is specific to any project.
# ---------------------------------------------------------------------------

# --- Where things live -----------------------------------------------------
# PROJECT_ROOT is the consuming project's root. It is only used to place the
# shared cache; set it in your project's makefiles (the template does).
PROJECT_ROOT ?= $(CURDIR)

# Shared, regenerable artefacts: the UVM checkout and the prebuilt .so files.
# Point several projects at one directory to share them.
UVMAKE_CACHE ?= $(PROJECT_ROOT)/.uvmake

# Per-testbench build output. Relative paths are relative to the testbench.
BUILD_ROOT ?= build

# --- Tools -----------------------------------------------------------------
VERILATOR      ?= verilator
VERILATOR_ROOT ?= $(shell $(VERILATOR) --getenv VERILATOR_ROOT 2>/dev/null)
VERILATOR_COVERAGE ?= verilator_coverage
CXX            ?= g++

# Minimum Verilator this flow is known to work with. Older releases lack the
# class and constraint support that compiling upstream UVM needs.
VERILATOR_MIN_VERSION ?= 5.040

# ccache gives the largest incremental win here; see docs/COMPILE_TIME.md.
OBJCACHE ?= $(if $(shell command -v ccache 2>/dev/null),ccache,)

JOBS          ?= $(shell nproc 2>/dev/null || echo 4)
VERILATE_JOBS ?= $(JOBS)
BUILD_JOBS    ?= $(JOBS)

# --- UVM library -----------------------------------------------------------
# accellera : upstream accellera-official/uvm-core, IEEE 1800.2-2020.
# antmicro  : antmicro/uvm-verilator, IEEE 1800.2-2017 with Verilator patches.
# custom    : you supply UVM_HOME yourself; nothing is fetched.
#
# Setting UVM_HOME selects 'custom' automatically, which is what most
# established projects want - they already have a UVM install to build against.
#
# This tests how UVM_HOME was *defined* rather than its value: UVM_HOME
# defaults to UVM_DIR, which is built from UVM_FLAVOR, so reading the value
# here would be a reference cycle.
UVM_HOME_GIVEN := $(if $(filter undefined default,$(origin UVM_HOME)),,1)
UVM_FLAVOR ?= $(if $(UVM_HOME_GIVEN),custom,accellera)

UVM_ACCELLERA_URL ?= https://github.com/accellera-official/uvm-core.git
UVM_ACCELLERA_REV ?= 2020.3.1
UVM_ANTMICRO_URL  ?= https://github.com/antmicro/uvm-verilator
UVM_ANTMICRO_REV  ?= current-patches

# Where a fetched UVM lands. Ignored when UVM_HOME is supplied.
UVM_DIR  ?= $(UVMAKE_CACHE)/uvm/$(UVM_FLAVOR)
UVM_HOME ?= $(UVM_DIR)
UVM_SRC  ?= $(UVM_HOME)/src

# Enable the UVM DPI layer. Turning it off costs real functionality: regular
# expressions degrade to glob matching, the command-line processor loses
# +uvm_set_*, and uvm_reg backdoor access disappears. See uvmake/dpi/.
UVM_DPI ?= 1

# Passive polling API (UVM 2020.3, uvm_hdl_polling.c).
UVM_VLT_POLLING ?= 0

# Width of the widest field the uvm_reg backdoor can access. This sizes the
# arrays UVM passes across the DPI boundary, so the SystemVerilog compile and
# the DPI library must agree; both are driven from this one variable.
UVM_HDL_MAX_WIDTH ?= 1024

# --- Build behaviour -------------------------------------------------------
# fast  : minimise turnaround (-O0, no decoration). The right default while
#         writing tests.
# opt   : minimise simulation wall time (-O2). For long regressions.
# debug : -O0 -g, for gdb on the model itself.
BUILD_MODE ?= fast

# none | vcd | fst
TRACE ?= none

# Precompiled shared libraries for the Verilator runtime and the UVM DPI
# layer, built once per toolchain instead of into every simulation binary.
USE_SHARED_LIBS ?= 1

# Verilator's precompiled header. See uvmake/core/model.mk.
PCH ?= 1

# How aggressively Verilator splits the generated C++ into translation units.
OUTPUT_SPLIT        ?= 20000
OUTPUT_SPLIT_CFUNCS ?= 2000

# Collect Verilator coverage (line/toggle/functional).
COVERAGE ?= 0

# --- Constraint solver -----------------------------------------------------
# Verilator does not solve SystemVerilog constraints itself; it hands them to
# an external SMT solver, z3 by default (override with VERILATOR_SOLVER).
# Its absence is quiet and destructive: every constrained randomize() returns
# 0, so tests fail confusingly or pass having randomised nothing.
SOLVER := $(firstword $(if $(VERILATOR_SOLVER),$(VERILATOR_SOLVER),z3))

# --- Simulation defaults ---------------------------------------------------
TEST          ?=
UVM_VERBOSITY ?= UVM_MEDIUM
SEED          ?= 1
TIMESCALE     ?= 1ns/1ps
PLUSARGS      ?=
SIM_ARGS      ?=
