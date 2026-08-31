# ---------------------------------------------------------------------------
# mk/verilator.mk - verilate / build / run rules shared by every testbench.
#
# A testbench makefile sets a handful of variables and includes this file:
#
#     TB_NAME       := apb
#     TB_TOP        := apb_tb_top
#     TB_SRCS       := $(wildcard tb/*.sv) $(wildcard rtl/*.sv)
#     TB_INCDIRS    := tb tests
#     include $(REPO_ROOT)/mk/verilator.mk
#
# Everything else - UVM compilation, the shared libraries, waveform and
# verbosity plusargs, seeds, logs - is handled here.
# ---------------------------------------------------------------------------

ifndef TB_NAME
  $(error TB_NAME must be set before including mk/verilator.mk)
endif
TB_TOP ?= $(TB_NAME)_tb_top

# The object directory name carries every setting that changes the generated
# C++, so switching any of them gets a clean tree instead of silently reusing
# objects built under different flags.
# (kept on one line: a backslash-newline inside an assignment expands to a
# space, which would end up in the directory name)
OBJ_DIR  := $(BUILD_ROOT)/$(TB_NAME)-$(UVM_FLAVOR)-$(BUILD_MODE)$(if $(filter-out none,$(TRACE)),-$(TRACE))$(if $(filter 0,$(UVM_DPI)),-nodpi)
SIM_BIN  := $(OBJ_DIR)/V$(TB_TOP)
LOG_DIR  := $(BUILD_ROOT)/logs

# ---------------------------------------------------------------------------
# UVM sources
#
# Only uvm_pkg.sv is handed to Verilator.  It `includes the whole library, so
# listing individual files would just make Verilator read them twice.
# ---------------------------------------------------------------------------
UVM_PKG_SV := $(UVM_SRC)/uvm_pkg.sv

VLT_INCDIRS := $(UVM_SRC) $(TB_INCDIRS)

# ---------------------------------------------------------------------------
# Defines
# ---------------------------------------------------------------------------
VLT_DEFINES :=

ifeq ($(UVM_DPI),1)
  # DPI is on.  The regex layer (real regular expressions plus, on UVM
  # 2020.3.x, the compiled-regex LRU cache) and the command-line processor
  # both come alive here.  Only the HDL backdoor needs the Verilator-specific
  # backend in lib/dpi/, and that is linked in via libuvmdpi.so.
  VLT_DPI_ARGS := --vpi
  # Keep the SV side's UVM_HDL_MAX_WIDTH in step with the value libuvmdpi.so
  # was compiled with; see lib/dpi/uvm_hdl_verilator.c.
  VLT_DEFINES  += UVM_HDL_MAX_WIDTH=$(UVM_HDL_MAX_WIDTH)
else
  VLT_DEFINES  += UVM_NO_DPI
  VLT_DPI_ARGS :=
endif

VLT_DEFINES += $(TB_DEFINES)

# ---------------------------------------------------------------------------
# Trace
# ---------------------------------------------------------------------------
# Tracing is the single most expensive thing you can switch on in a UVM build:
# Verilator emits trace-registration code for the class hierarchy as well as
# the design, which is why it is opt-in here rather than always-on.
ifeq ($(TRACE),vcd)
  VLT_TRACE_ARGS := --trace-vcd --trace-structs --trace-depth 8
  WAVE_FILE      := $(LOG_DIR)/$(TB_NAME).vcd
else ifeq ($(TRACE),fst)
  # FST is dramatically smaller than VCD for long UVM runs and is what a
  # commercial flow's compressed dump would give you.
  VLT_TRACE_ARGS := --trace-fst --trace-structs --trace-depth 8
  WAVE_FILE      := $(LOG_DIR)/$(TB_NAME).fst
else ifeq ($(TRACE),none)
  VLT_TRACE_ARGS :=
  WAVE_FILE      :=
else
  $(error TRACE must be one of none/vcd/fst, got '$(TRACE)')
endif

# ---------------------------------------------------------------------------
# Optimisation mode
# ---------------------------------------------------------------------------
# OPT_FAST/OPT_SLOW are the flags Verilator's generated makefile applies to
# the model's own translation units.  Verilator defaults OPT_FAST to -Os,
# which is a poor trade for a UVM testbench: almost all of the emitted code is
# class methods that run a handful of times, so paying -Os on 1500+ files buys
# very little simulation speed and costs a great deal of compile time.
ifeq ($(BUILD_MODE),fast)
  MODEL_OPT_FAST := -O0
  MODEL_OPT_SLOW := -O0
  # Comments and #line directives in the generated C++ are useful when
  # debugging Verilator itself, and pure overhead otherwise.
  VLT_DECOR      := --no-decoration
else ifeq ($(BUILD_MODE),opt)
  MODEL_OPT_FAST := -O2
  MODEL_OPT_SLOW := -O1
  VLT_DECOR      := --no-decoration
else ifeq ($(BUILD_MODE),debug)
  MODEL_OPT_FAST := -O0 -g
  MODEL_OPT_SLOW := -O0 -g
  VLT_DECOR      :=
else
  $(error BUILD_MODE must be one of fast/opt/debug, got '$(BUILD_MODE)')
endif

# ---------------------------------------------------------------------------
# Verilator arguments
# ---------------------------------------------------------------------------
# --output-split trades off two things.  Smaller splits parallelise better
# across a -j build and give ccache a finer granularity, so an incremental
# rebuild after a one-file edit re-compiles less.  But each extra translation
# unit costs a compiler invocation, and UVM already produces well over a
# thousand of them, so splitting too aggressively costs more than it saves.
# OUTPUT_SPLIT in mk/config.mk is the knob; see docs/COMPILE_TIME.md.
VLT_ARGS := \
  --cc --exe --main --timing \
  --top-module $(TB_TOP) \
  --prefix V$(TB_TOP) \
  -o V$(TB_TOP) \
  -Mdir $(OBJ_DIR) \
  --timescale $(TIMESCALE) \
  --output-split $(OUTPUT_SPLIT) \
  --output-split-cfuncs $(OUTPUT_SPLIT_CFUNCS) \
  --output-split-ctrace $(OUTPUT_SPLIT_CFUNCS) \
  --verilate-jobs $(VERILATE_JOBS) \
  $(VLT_DECOR) \
  $(VLT_TRACE_ARGS) \
  $(VLT_DPI_ARGS) \
  $(addprefix +incdir+,$(VLT_INCDIRS)) \
  $(addprefix +define+,$(VLT_DEFINES)) \
  $(REPO_ROOT)/lib/vlt/uvm_waivers.vlt \
  $(TB_VLT_ARGS)

# Lint stays fully enabled for the DUT and the testbench; the UVM library's
# own warnings are waived by path in lib/vlt/uvm_waivers.vlt.
VLT_ARGS += -Wno-fatal

# ---------------------------------------------------------------------------
# Link arguments
# ---------------------------------------------------------------------------
ifeq ($(USE_SHARED_LIBS),1)
  # Hand the model the prebuilt runtime instead of letting it compile its own.
  # VM_GLOBAL_FAST is cleared on the sub-make command line, which takes
  # precedence over the assignment in the generated makefile.
  #
  # The libraries go through USER_LDLIBS rather than LDLIBS: verilated.mk
  # builds LDLIBS up with '+=' (-pthread, -latomic, -ldl for runtime VPI
  # loading), and a command-line LDLIBS= would override all of that. It
  # appends USER_LDLIBS for exactly this purpose.
  MODEL_MAKE_ARGS := VM_GLOBAL_FAST= VM_GLOBAL_SLOW=
  SIM_LDLIBS      := -L$(LIB_OUT) -lvltrt -Wl,-rpath,$(LIB_OUT)
  ifeq ($(UVM_DPI),1)
    SIM_LDLIBS += -luvmdpi
  endif
else
  MODEL_MAKE_ARGS :=
  SIM_LDLIBS      :=
  ifeq ($(UVM_DPI),1)
    SIM_LDLIBS += -L$(LIB_OUT) -luvmdpi -Wl,-rpath,$(LIB_OUT)
  endif
endif

# Verilator emits each `export "DPI-C"` function as a method on the model
# class plus a C-linkage wrapper, and puts both in V<top>__Dpi.o inside
# V<top>__ALL.a.  Nothing in the model itself calls those wrappers - only the
# DPI library does - and a static archive only yields the members that
# resolve an already-outstanding symbol.  Since the archive is linked before
# libuvmdpi.so, m__uvm_report_dpi is still unreferenced when the archive is
# read, __Dpi.o is dropped, and the link then fails on it.
#
# -u forces the symbol to be considered undefined up front, which pulls
# __Dpi.o in.  It has to appear before the archive on the link line, so it
# goes through LDFLAGS (USER_LDFLAGS) rather than LDLIBS.
ifeq ($(UVM_DPI),1)
  SIM_LDFLAGS := -u m__uvm_report_dpi
else
  SIM_LDFLAGS :=
endif

# Which makefile drives the model build. With PCH off we substitute our own
# rules (see mk/model.mk for why); with it on, Verilator's generated makefile
# is used as-is.
ifeq ($(PCH),1)
  MODEL_MK_ARGS := -f V$(TB_TOP).mk
else
  MODEL_MK_ARGS := -f $(REPO_ROOT)/mk/model.mk GEN_MK=V$(TB_TOP).mk VM_DEFAULT_RULES=0
endif

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------
.PHONY: all verilate build run clean waves help print-objdir print-config

all: build

verilate: $(OBJ_DIR)/V$(TB_TOP).mk

$(OBJ_DIR)/V$(TB_TOP).mk: $(UVM_STAMP) $(TB_SRCS) $(REPO_ROOT)/lib/vlt/uvm_waivers.vlt
	@mkdir -p $(OBJ_DIR)
	@echo "[verilate] $(TB_NAME) (mode=$(BUILD_MODE) trace=$(TRACE) dpi=$(UVM_DPI) uvm=$(UVM_FLAVOR))"
	@$(REPO_ROOT)/scripts/preserve_mtimes.sh snapshot $(OBJ_DIR)
	$(VERILATOR) $(VLT_ARGS) $(UVM_PKG_SV) $(TB_SRCS)
	@$(REPO_ROOT)/scripts/preserve_mtimes.sh restore $(OBJ_DIR)

# 'build' is phony on purpose.  It would be tempting to write
#
#     $(SIM_BIN): $(OBJ_DIR)/V$(TB_TOP).mk $(SHARED_LIBS)
#
# and let make decide, but that is wrong here: the generated makefile's own
# timestamp says nothing about whether any of the ~2000 generated .cpp files
# changed, and scripts/preserve_mtimes.sh deliberately keeps it unchanged
# when its contents did not change.  The binary would then look up to date
# while a genuinely edited source sat un-recompiled, and the edit would
# silently not take effect.
#
# The sub-make already does the real per-file dependency checking, so always
# hand off to it; when there is nothing to do it returns in well under a
# second.
build: $(OBJ_DIR)/V$(TB_TOP).mk $(SHARED_LIBS)
	@echo "[build]    $(TB_NAME) -j$(BUILD_JOBS)"
	@$(MAKE) --no-print-directory -C $(OBJ_DIR) $(MODEL_MK_ARGS) -j$(BUILD_JOBS) \
	  OBJCACHE="$(OBJCACHE)" \
	  USER_LDFLAGS="$(SIM_LDFLAGS)" \
	  OPT_FAST="$(MODEL_OPT_FAST)" \
	  OPT_SLOW="$(MODEL_OPT_SLOW)" \
	  OPT_GLOBAL="$(MODEL_OPT_FAST)" \
	  VM_PARALLEL_BUILDS=1 \
	  $(MODEL_MAKE_ARGS) \
	  USER_LDLIBS="$(SIM_LDLIBS)"

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
# +verilator+seed+ is Verilator's own seed plusarg; UVM picks up
# $urandom from the same generator.  +UVM_NO_RELNOTES silences the release
# banner on every run (it is a plusarg, not a compile-time define).
SIM_PLUSARGS := +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(UVM_VERBOSITY) \
                +verilator+seed+$(SEED) $(if $(RELNOTES),,+UVM_NO_RELNOTES) \
                $(PLUSARGS)
ifneq ($(WAVE_FILE),)
  SIM_PLUSARGS += +wave +wave_file=$(WAVE_FILE)
endif

run: build
ifeq ($(TEST),)
	$(error TEST is not set. Try: make run TEST=<uvm_test_name>)
endif
	@mkdir -p $(LOG_DIR)
	@echo "[run]      $(TEST) seed=$(SEED)"
	@cd $(LOG_DIR) && $(abspath $(SIM_BIN)) $(SIM_PLUSARGS) 2>&1 \
	  | tee $(TEST)-$(SEED).log
	@printf '[run]      %s\n' \
	  "$$($(REPO_ROOT)/scripts/check_log.sh $(LOG_DIR)/$(TEST)-$(SEED).log)"
	@$(REPO_ROOT)/scripts/check_log.sh $(LOG_DIR)/$(TEST)-$(SEED).log >/dev/null \
	  || (echo "[run]      see $(LOG_DIR)/$(TEST)-$(SEED).log"; false)

waves:
	@$(MAKE) run TRACE=$(if $(filter none,$(TRACE)),fst,$(TRACE))

clean:
	rm -rf $(BUILD_ROOT)

# Introspection, used by scripts/benchmark.sh and handy when debugging the
# flow itself.
print-objdir:
	@echo $(OBJ_DIR)

print-config:
	@echo "tb=$(TB_NAME) top=$(TB_TOP)"
	@echo "uvm=$(UVM_FLAVOR) ($(UVM_SRC))  dpi=$(UVM_DPI)"
	@echo "mode=$(BUILD_MODE) trace=$(TRACE) shared_libs=$(USE_SHARED_LIBS)"
	@echo "objdir=$(OBJ_DIR)"
	@echo "objcache=$(OBJCACHE) jobs=$(BUILD_JOBS) output_split=$(OUTPUT_SPLIT)"

help:
	@echo "Targets:  verilate | build | run | waves | clean"
	@echo "Knobs:    TEST=<name> BUILD_MODE=fast|opt|debug TRACE=none|vcd|fst"
	@echo "          SEED=<n> UVM_VERBOSITY=<UVM_*> UVM_FLAVOR=accellera|antmicro"
	@echo "          UVM_DPI=0|1 USE_SHARED_LIBS=0|1 JOBS=<n>"
