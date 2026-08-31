# ---------------------------------------------------------------------------
# uvmake/core/verilate.mk - verilate and build the model.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Defines
# ---------------------------------------------------------------------------
VLT_DEFINES := $(UVMAKE_DEFINES)

ifeq ($(UVM_DPI),1)
  # --vpi is what lets the DPI layer reach vpi_get_vlog_info (the UVM
  # command-line processor) and vpi_handle_by_name (the uvm_reg backdoor).
  VLT_DPI_ARGS := --vpi
  # Keep the SV side's UVM_HDL_MAX_WIDTH in step with the value libuvmdpi.so
  # was compiled with; see uvmake/dpi/uvm_hdl_verilator.c.
  VLT_DEFINES  += UVM_HDL_MAX_WIDTH=$(UVM_HDL_MAX_WIDTH)
else
  VLT_DEFINES  += UVM_NO_DPI
  VLT_DPI_ARGS :=
endif

# ---------------------------------------------------------------------------
# Trace
# ---------------------------------------------------------------------------
# Tracing is the single most expensive thing to switch on in a UVM build:
# Verilator emits trace registration for the class hierarchy as well as the
# design, across a library that already generates thousands of translation
# units. Hence opt-in.
ifeq ($(TRACE),vcd)
  VLT_TRACE_ARGS := --trace-vcd --trace-structs --trace-depth $(TRACE_DEPTH)
  WAVE_EXT       := vcd
else ifeq ($(TRACE),fst)
  VLT_TRACE_ARGS := --trace-fst --trace-structs --trace-depth $(TRACE_DEPTH)
  WAVE_EXT       := fst
else ifeq ($(TRACE),none)
  VLT_TRACE_ARGS :=
  WAVE_EXT       :=
else
  $(error TRACE must be none, vcd or fst (got '$(TRACE)'))
endif
TRACE_DEPTH ?= 0

ifeq ($(COVERAGE),1)
  VLT_COV_ARGS := --coverage
else
  VLT_COV_ARGS :=
endif

# ---------------------------------------------------------------------------
# Optimisation mode
# ---------------------------------------------------------------------------
# OPT_FAST/OPT_SLOW are what Verilator's generated makefile applies to the
# model's translation units. Verilator defaults OPT_FAST to -Os, which is a
# poor trade for UVM: nearly all the emitted code is class methods that run a
# handful of times, so -Os across thousands of files buys little simulation
# speed for a lot of compile time.
ifeq ($(BUILD_MODE),fast)
  MODEL_OPT_FAST := -O0
  MODEL_OPT_SLOW := -O0
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
  $(error BUILD_MODE must be fast, opt or debug (got '$(BUILD_MODE)'))
endif

# ---------------------------------------------------------------------------
# Verilator arguments
# ---------------------------------------------------------------------------
VLT_COMMON_ARGS := \
  --timing \
  --top-module $(TB_TOP) \
  --timescale $(TIMESCALE) \
  $(addprefix +incdir+,$(UVMAKE_INCDIRS)) \
  $(addprefix +define+,$(VLT_DEFINES)) \
  $(addprefix -y ,$(UVMAKE_LIBDIRS)) \
  $(if $(UVMAKE_LIBEXTS),+libext+$(subst $(space),+,$(UVMAKE_LIBEXTS))) \
  $(UVMAKE_ROOT)/vlt/uvm_waivers.vlt \
  $(TB_VLT_ARGS)

# Lint stays fully enabled for the DUT and the testbench; the UVM library's
# own warnings are waived by path in uvmake/vlt/uvm_waivers.vlt. -Wno-fatal
# keeps a warning from stopping the build; LINT_STRICT=1 makes them fatal.
ifneq ($(LINT_STRICT),1)
  VLT_COMMON_ARGS += -Wno-fatal
endif

VLT_ARGS := \
  --cc --exe --main \
  --prefix V$(TB_TOP) \
  -o V$(TB_TOP) \
  -Mdir $(OBJ_DIR) \
  --output-split $(OUTPUT_SPLIT) \
  --output-split-cfuncs $(OUTPUT_SPLIT_CFUNCS) \
  --output-split-ctrace $(OUTPUT_SPLIT_CFUNCS) \
  --verilate-jobs $(VERILATE_JOBS) \
  $(VLT_DECOR) \
  $(VLT_TRACE_ARGS) \
  $(VLT_COV_ARGS) \
  $(VLT_DPI_ARGS) \
  $(VLT_COMMON_ARGS)

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
  # loading), and a command-line LDLIBS= would override all of that.
  MODEL_MAKE_ARGS := VM_GLOBAL_FAST= VM_GLOBAL_SLOW=
  SIM_LDLIBS      := -L$(LIB_OUT) -lvltrt -Wl,-rpath,$(LIB_OUT)
else
  MODEL_MAKE_ARGS :=
  SIM_LDLIBS      :=
endif

ifeq ($(UVM_DPI),1)
  SIM_LDLIBS += -L$(LIB_OUT) -luvmdpi -Wl,-rpath,$(LIB_OUT)
endif

SIM_LDLIBS += $(TB_LDLIBS)

# Verilator emits each `export "DPI-C"` function as a method on the model
# class plus a C-linkage wrapper, and puts both in V<top>__Dpi.o inside
# V<top>__ALL.a. Nothing in the model itself calls those wrappers - only the
# DPI library does - and a static archive only yields the members that
# resolve an already-outstanding symbol. Since the archive is linked before
# libuvmdpi.so, m__uvm_report_dpi is still unreferenced when the archive is
# read, __Dpi.o is dropped, and the link fails on it.
#
# -u forces the symbol to be considered undefined up front, which pulls
# __Dpi.o in. It has to appear before the archive on the link line, so it
# goes through LDFLAGS (USER_LDFLAGS) rather than LDLIBS.
ifeq ($(UVM_DPI),1)
  SIM_LDFLAGS := -u m__uvm_report_dpi
else
  SIM_LDFLAGS :=
endif
SIM_LDFLAGS += $(TB_LDFLAGS)

# Which makefile drives the model build. With PCH off we substitute our own
# rules (see uvmake/core/model.mk for why); with it on, Verilator's generated
# makefile is used as-is.
ifeq ($(PCH),1)
  MODEL_MK_ARGS := -f V$(TB_TOP).mk
else
  MODEL_MK_ARGS := -f $(UVMAKE_ROOT)/core/model.mk GEN_MK=V$(TB_TOP).mk VM_DEFAULT_RULES=0
endif

# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------
.PHONY: verilate build lint

verilate: $(OBJ_DIR)/V$(TB_TOP).mk

# The UVM sources are covered by UVM_STAMP rather than listed individually:
# on a clean tree they do not exist yet, and make would refuse to start.
TB_SOURCE_DEPS := $(filter-out $(UVM_SRC)/%,$(UVMAKE_SOURCES))

$(OBJ_DIR)/V$(TB_TOP).mk: $(UVM_STAMP) $(TB_SOURCE_DEPS) $(FL_DEPS) \
                          $(UVMAKE_ROOT)/vlt/uvm_waivers.vlt
	@mkdir -p $(OBJ_DIR)
	@echo "[verilate] $(TB_NAME) (mode=$(BUILD_MODE) trace=$(TRACE) dpi=$(UVM_DPI) uvm=$(UVM_ID))"
	@$(if $(strip $(UVMAKE_SOURCES)),,echo "error: no sources. Set TB_FILELIST or TB_SRCS." >&2; false)
	@$(UVMAKE_ROOT)/scripts/preserve_mtimes.sh snapshot $(OBJ_DIR)
	$(VERILATOR) $(VLT_ARGS) $(UVMAKE_SOURCES)
	@$(UVMAKE_ROOT)/scripts/preserve_mtimes.sh restore $(OBJ_DIR)

# 'build' is phony on purpose. It would be tempting to write
#
#     $(SIM_BIN): $(OBJ_DIR)/V$(TB_TOP).mk $(SHARED_LIBS)
#
# and let make decide, but that is wrong here: the generated makefile's
# timestamp says nothing about whether any of the thousands of generated .cpp
# files changed, and preserve_mtimes.sh deliberately keeps it unchanged when
# its contents did not change. The binary would then look up to date while a
# genuinely edited source sat un-recompiled, and the edit would silently not
# take effect.
#
# The sub-make already does the real per-file dependency checking, so always
# hand off to it; with nothing to do it returns in well under a second.
build: $(OBJ_DIR)/V$(TB_TOP).mk $(SHARED_LIBS)
	@echo "[build]    $(TB_NAME) -j$(BUILD_JOBS)"
	@$(MAKE) --no-print-directory -C $(OBJ_DIR) $(MODEL_MK_ARGS) -j$(BUILD_JOBS) \
	  OBJCACHE="$(OBJCACHE)" \
	  USER_LDFLAGS="$(SIM_LDFLAGS)" \
	  USER_LDLIBS="$(SIM_LDLIBS)" \
	  OPT_FAST="$(MODEL_OPT_FAST)" \
	  OPT_SLOW="$(MODEL_OPT_SLOW)" \
	  OPT_GLOBAL="$(MODEL_OPT_FAST)" \
	  VM_PARALLEL_BUILDS=1 \
	  $(MODEL_MAKE_ARGS)

# Elaborate and lint without generating or compiling any C++. Seconds rather
# than minutes, so it belongs in a pre-commit hook or the fast CI stage.
lint: $(UVM_STAMP)
	@echo "[lint]     $(TB_NAME)"
	$(VERILATOR) --lint-only $(VLT_COMMON_ARGS) $(UVMAKE_SOURCES)
