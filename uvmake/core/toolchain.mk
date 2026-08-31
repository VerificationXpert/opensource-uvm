# ---------------------------------------------------------------------------
# uvmake/core/toolchain.mk - check the environment before anything else.
#
# Every check here exists because its absence produces a confusing failure
# rather than an obvious one. Better to say what is wrong at parse time.
# ---------------------------------------------------------------------------

UVMAKE_VERILATOR_VERSION := $(shell $(VERILATOR) --version 2>/dev/null | awk '{print $$2}')

ifeq ($(UVMAKE_VERILATOR_VERSION),)
  $(warning )
  $(warning *** '$(VERILATOR)' was not found, or did not report a version.)
  $(warning *** Install it with uvmake/scripts/setup_verilator.sh, or set VERILATOR.)
  $(warning )
else
  # Compare as sortable version strings rather than numerically: 5.4 must not
  # look newer than 5.40.
  UVMAKE_VERILATOR_OK := $(shell printf '%s\n%s\n' "$(VERILATOR_MIN_VERSION)" \
                           "$(UVMAKE_VERILATOR_VERSION)" | sort -V | head -1)
  ifneq ($(UVMAKE_VERILATOR_OK),$(VERILATOR_MIN_VERSION))
    $(warning )
    $(warning *** Verilator $(UVMAKE_VERILATOR_VERSION) is older than the)
    $(warning *** $(VERILATOR_MIN_VERSION) this flow expects. Compiling upstream UVM)
    $(warning *** needs class and constraint support that earlier releases lack.)
    $(warning *** Distribution packages are usually well behind; build from source)
    $(warning *** with uvmake/scripts/setup_verilator.sh.)
    $(warning )
  endif
endif

ifeq ($(shell command -v $(SOLVER) 2>/dev/null),)
  $(warning )
  $(warning *** '$(SOLVER)' was not found on PATH.)
  $(warning *** Verilator needs an SMT solver to solve SystemVerilog constraints.)
  $(warning *** Without it EVERY constrained randomize() returns 0, so)
  $(warning *** constrained-random tests are meaningless - they fail with)
  $(warning *** unhelpful messages, or pass having randomised nothing.)
  $(warning ***   apt-get install z3   (or set VERILATOR_SOLVER))
  $(warning )
endif

ifeq ($(OBJCACHE),)
  # Not fatal, but the incremental-build story depends on it.
  $(warning *** ccache not found: rebuilds will be substantially slower.)
endif

.PHONY: check-env
check-env:
	@echo "verilator : $(VERILATOR) $(UVMAKE_VERILATOR_VERSION) (min $(VERILATOR_MIN_VERSION))"
	@echo "root      : $(VERILATOR_ROOT)"
	@echo "solver    : $(SOLVER) $$(command -v $(SOLVER) >/dev/null && echo found || echo 'NOT FOUND')"
	@echo "objcache  : $(if $(OBJCACHE),$(OBJCACHE),none)"
	@echo "compiler  : $(CXX) $$($(CXX) -dumpversion 2>/dev/null)"
	@echo "jobs      : $(JOBS)"
	@echo "uvm       : $(UVM_FLAVOR) -> $(UVM_SRC)"
	@echo "cache     : $(UVMAKE_CACHE)"
