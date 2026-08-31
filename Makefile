# ---------------------------------------------------------------------------
# Top-level entry point.
#
#   make libs                       build the UVM checkout and the .so libraries
#   make minimal                    build one testbench
#   make run TB=apb TEST=apb_rw_test
#   make regress                    run regress/smoke.list
#   make bench                      compile-time measurements
#   make clean
#
# Every knob in mk/config.mk can be set on the command line and is forwarded
# to the testbench makefiles, e.g.
#   make regress BUILD_MODE=opt TRACE=fst UVM_FLAVOR=antmicro
# ---------------------------------------------------------------------------

REPO_ROOT := $(abspath $(CURDIR))
include $(REPO_ROOT)/mk/config.mk
include $(REPO_ROOT)/mk/uvm.mk

# Anything with a Makefile under tb/ is a testbench.
TESTBENCHES := $(patsubst tb/%/Makefile,%,$(wildcard tb/*/Makefile))

# Knobs to forward to the sub-makes.  Only pass through the ones actually
# set on this make's command line, so each testbench keeps its own defaults
# (its TEST, mainly) unless the user overrode them here.
FORWARD := $(foreach v,BUILD_MODE TRACE UVM_FLAVOR UVM_DPI USE_SHARED_LIBS \
                       JOBS SEED UVM_VERBOSITY OUTPUT_SPLIT PLUSARGS TEST, \
             $(if $(filter command line,$(origin $(v))),$(v)='$($(v))'))

TB   ?= minimal
LIST ?= regress/smoke.list

.PHONY: all help $(TESTBENCHES) build run regress bench clean distclean list

all: $(TESTBENCHES)

help:
	@echo "Testbenches:  $(TESTBENCHES)"
	@echo
	@echo "  make libs                      fetch UVM, build libvltrt.so + libuvmdpi.so"
	@echo "  make <tb>                      build one testbench"
	@echo "  make run TB=<tb> TEST=<test>   build and run a single test"
	@echo "  make regress [LIST=...]        run a regression list"
	@echo "  make bench [TB=<tb>]           compile-time measurements"
	@echo "  make clean | distclean"
	@echo
	@echo "Knobs (see mk/config.mk):"
	@echo "  BUILD_MODE=fast|opt|debug   TRACE=none|vcd|fst   SEED=<n>"
	@echo "  UVM_FLAVOR=accellera|antmicro  UVM_DPI=0|1  USE_SHARED_LIBS=0|1"
	@echo "  JOBS=<n>  UVM_VERBOSITY=UVM_LOW|UVM_MEDIUM|...  OUTPUT_SPLIT=<n>"

list:
	@for t in $(TESTBENCHES); do echo "$$t"; done

$(TESTBENCHES): libs
	@$(MAKE) --no-print-directory -C tb/$@ $(FORWARD) build

build: $(TB)

run: libs
	@$(MAKE) --no-print-directory -C tb/$(TB) $(FORWARD) run

# ---------------------------------------------------------------------------
# Regression
#
# Runs every line of the list, keeps going after a failure so one broken test
# does not hide the rest, and exits non-zero if anything failed - the minimum
# a CI job needs.
# ---------------------------------------------------------------------------
regress: libs
	@echo "[regress] $(LIST)"
	@fail=0; pass=0; \
	while read -r tb test seed rest; do \
	  case "$$tb" in ''|'#'*) continue ;; esac; \
	  seed=$${seed:-1}; \
	  echo "[regress] $$tb/$$test seed=$$seed"; \
	  if $(MAKE) --no-print-directory -C tb/$$tb $(FORWARD) run \
	       TEST=$$test SEED=$$seed >/dev/null 2>&1; then \
	    pass=$$((pass+1)); echo "[regress]   PASS"; \
	  else \
	    fail=$$((fail+1)); echo "[regress]   FAIL  (log: build/logs/$$test-$$seed.log)"; \
	  fi; \
	done < $(LIST); \
	echo "[regress] $$pass passed, $$fail failed"; \
	[ $$fail -eq 0 ]

bench:
	@./scripts/benchmark.sh -t $(TB)

clean:
	@for t in $(TESTBENCHES); do $(MAKE) --no-print-directory -C tb/$$t clean; done
	@rm -rf build

# Also drops the UVM checkout and the prebuilt shared libraries.
distclean: clean libs-clean
	@rm -rf $(UVM_DIR)
