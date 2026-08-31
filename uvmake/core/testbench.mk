# ---------------------------------------------------------------------------
# uvmake/core/testbench.mk - evaluated by $(uvmake-testbench).
#
# Split out from uvmake.mk so that a testbench can declare TB_NAME,
# TB_FILELIST and friends after including uvmake (it needs UVM_HOME,
# PROJECT_ROOT and the tool paths to build them from).
# ---------------------------------------------------------------------------

ifndef TB_NAME
  $(error TB_NAME must be set before calling $$(uvmake-testbench))
endif
TB_TOP ?= $(TB_NAME)_tb_top

# The object directory name carries every setting that changes the generated
# C++, so switching any of them gets a clean tree instead of silently reusing
# objects built under different flags. Kept on one line: a backslash-newline
# inside an assignment expands to a space, which would land in the path.
OBJ_DIR := $(BUILD_ROOT)/$(TB_NAME)-$(UVM_FLAVOR)-$(BUILD_MODE)$(if $(filter-out none,$(TRACE)),-$(TRACE))$(if $(filter 0,$(UVM_DPI)),-nodpi)$(if $(filter 1,$(COVERAGE)),-cov)

include $(UVMAKE_ROOT)/core/filelist.mk
include $(UVMAKE_ROOT)/core/verilate.mk
include $(UVMAKE_ROOT)/core/run.mk

.DEFAULT_GOAL := build

.PHONY: help
help:
	@echo "Testbench '$(TB_NAME)' (top module $(TB_TOP))"
	@echo
	@echo "  make lint                    elaborate and lint only (seconds)"
	@echo "  make build                   build the simulation binary"
	@echo "  make run TEST=<name>         build and run one test"
	@echo "  make waves TEST=<name>       ...with a waveform"
	@echo "  make coverage TEST=<name>    ...with coverage collection"
	@echo "  make coverage-report         merge and annotate collected coverage"
	@echo "  make clean"
	@echo
	@echo "  make print-config | print-filelist | print-objdir | check-env"
	@echo
	@echo "Knobs: BUILD_MODE=fast|opt|debug  TRACE=none|vcd|fst  SEED=<n>"
	@echo "       UVM_DPI=0|1  COVERAGE=0|1  USE_SHARED_LIBS=0|1  PCH=0|1"
	@echo "       UVM_FLAVOR=accellera|antmicro  UVM_HOME=<path>  JOBS=<n>"
