# ---------------------------------------------------------------------------
# uvmake/core/project.mk - evaluated by $(uvmake-project).
#
# Project-level targets: discover testbenches, build them, run regressions.
# ---------------------------------------------------------------------------

# Where testbenches live. A testbench is any directory under one of these
# holding a Makefile. Override TB_DIRS if your layout differs.
TB_DIRS ?= $(PROJECT_ROOT)/tb

TESTBENCHES ?= $(sort $(notdir $(patsubst %/Makefile,%, \
                 $(foreach d,$(TB_DIRS),$(wildcard $(d)/*/Makefile)))))

# Map a testbench name back to its directory.
tb-dir = $(firstword $(foreach d,$(TB_DIRS),$(wildcard $(d)/$(1))))

# Forward only the knobs actually set on this make's command line, so each
# testbench keeps its own defaults (its TEST, mainly) unless overridden here.
UVMAKE_FORWARD := BUILD_MODE TRACE UVM_FLAVOR UVM_HOME UVM_DPI USE_SHARED_LIBS \
                  PCH JOBS SEED UVM_VERBOSITY OUTPUT_SPLIT COVERAGE PLUSARGS \
                  LINT_STRICT TEST UVMAKE_CACHE
FORWARD := $(foreach v,$(UVMAKE_FORWARD), \
             $(if $(filter command line,$(origin $(v))),$(v)='$($(v))'))

# PROJECT_ROOT and UVMAKE_CACHE must reach the sub-makes so every testbench
# shares one UVM checkout and one set of .so libraries.
export PROJECT_ROOT
export UVMAKE_CACHE

TB   ?= $(firstword $(TESTBENCHES))
LIST ?= $(PROJECT_ROOT)/regress/smoke.list

.PHONY: all help list $(TESTBENCHES) build run lint regress clean distclean

all: $(TESTBENCHES)

list:
	@$(if $(TESTBENCHES),printf '%s\n' $(TESTBENCHES),echo "(no testbenches found under $(TB_DIRS))")

$(TESTBENCHES): libs
	@$(MAKE) --no-print-directory -C $(call tb-dir,$@) $(FORWARD) build

build: $(TB)

run: libs
	@$(MAKE) --no-print-directory -C $(call tb-dir,$(TB)) $(FORWARD) run

# Per-testbench targets, so 'lint' and 'clean' can use the tb-dir function
# rather than assuming a layout inside a shell loop.
LINT_TARGETS  := $(addprefix lint-,$(TESTBENCHES))
CLEAN_TARGETS := $(addprefix clean-,$(TESTBENCHES))
.PHONY: $(LINT_TARGETS) $(CLEAN_TARGETS)

$(LINT_TARGETS): lint-%:
	@$(MAKE) --no-print-directory -C $(call tb-dir,$*) $(FORWARD) lint

$(CLEAN_TARGETS): clean-%:
	@$(MAKE) --no-print-directory -C $(call tb-dir,$*) clean

lint: $(LINT_TARGETS)

# ---------------------------------------------------------------------------
# Regression
# ---------------------------------------------------------------------------
# Delegated to a script rather than a shell loop in a recipe: it runs jobs in
# parallel, expands seed sweeps, and emits JUnit XML, none of which is
# pleasant to write in make.
REGRESS_JOBS ?= $(JOBS)
REGRESS_ARGS ?=

regress: libs
	@$(UVMAKE_ROOT)/scripts/regress.py \
	  --project-root $(PROJECT_ROOT) \
	  --list $(LIST) \
	  --jobs $(REGRESS_JOBS) \
	  $(addprefix --tb-dir ,$(TB_DIRS)) \
	  $(addprefix --set ,$(FORWARD)) \
	  $(REGRESS_ARGS)

.PHONY: bench
bench:
	@PROJECT_ROOT=$(PROJECT_ROOT) TB_DIRS='$(firstword $(TB_DIRS))' \
	  $(UVMAKE_ROOT)/scripts/benchmark.sh -t $(TB)

clean: $(CLEAN_TARGETS)
	@rm -rf $(PROJECT_ROOT)/build

# Also drops the fetched UVM and the prebuilt shared libraries.
distclean: clean
	rm -rf $(UVMAKE_CACHE)

help:
	@echo "Testbenches: $(if $(TESTBENCHES),$(TESTBENCHES),(none found under $(TB_DIRS)))"
	@echo
	@echo "  make libs                        fetch UVM, build libvltrt.so + libuvmdpi.so"
	@echo "  make <tb>                        build one testbench"
	@echo "  make run TB=<tb> TEST=<test>     build and run a single test"
	@echo "  make regress [LIST=...]          run a regression list in parallel"
	@echo "  make lint                        lint every testbench (fast)"
	@echo "  make check-env                   report the detected toolchain"
	@echo "  make clean | distclean"
	@echo
	@echo "Knobs: BUILD_MODE=fast|opt|debug  TRACE=none|vcd|fst  SEED=<n>"
	@echo "       UVM_FLAVOR=accellera|antmicro  UVM_HOME=<path>  UVM_DPI=0|1"
	@echo "       COVERAGE=0|1  USE_SHARED_LIBS=0|1  PCH=0|1  JOBS=<n>"
	@echo "       REGRESS_JOBS=<n>  REGRESS_ARGS='--seeds 5 --junit r.xml'"
