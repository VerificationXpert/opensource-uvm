# ---------------------------------------------------------------------------
# mk/uvm.mk - UVM checkout and the precompiled shared libraries.
#
# Two things get built once here and then reused by every testbench:
#
#   libvltrt.so    Verilator's own runtime (verilated.cpp, verilated_timing.cpp,
#                  verilated_threads.cpp, the trace back ends, the VPI/DPI
#                  entry points, ...).  Verilator's generated makefile lists
#                  these in VM_GLOBAL_FAST and recompiles all of them into
#                  every simulation binary; building them once as a shared
#                  object removes that from each testbench's critical path.
#
#   libuvmdpi.so   The UVM DPI C/C++ layer, including the Verilator VPI
#                  backdoor backend from lib/dpi/.  This is what makes it
#                  possible to run UVM *without* +define+UVM_NO_DPI.
#
# Both are keyed on the Verilator version and the UVM flavour, so switching
# either rebuilds cleanly instead of silently linking stale objects.
# ---------------------------------------------------------------------------

VLT_VERSION := $(shell $(VERILATOR) --version 2>/dev/null | awk '{print $$2}')
LIB_TAG     := $(VLT_VERSION)-$(UVM_FLAVOR)-w$(UVM_HDL_MAX_WIDTH)
LIB_OUT     := $(LIB_DIR)/$(LIB_TAG)
LIB_OBJ     := $(LIB_OUT)/obj

VLTRT_SO  := $(LIB_OUT)/libvltrt.so
UVMDPI_SO := $(LIB_OUT)/libuvmdpi.so

# ---------------------------------------------------------------------------
# UVM checkout
# ---------------------------------------------------------------------------
ifeq ($(UVM_FLAVOR),accellera)
  UVM_URL := $(UVM_ACCELLERA_URL)
  UVM_REV := $(UVM_ACCELLERA_REV)
else ifeq ($(UVM_FLAVOR),antmicro)
  UVM_URL := $(UVM_ANTMICRO_URL)
  UVM_REV := $(UVM_ANTMICRO_REV)
else
  $(error UVM_FLAVOR must be 'accellera' or 'antmicro', got '$(UVM_FLAVOR)')
endif

UVM_STAMP := $(UVM_DIR)/.fetched-$(UVM_REV)

$(UVM_STAMP):
	@echo "[uvm]   fetching $(UVM_FLAVOR) UVM @ $(UVM_REV)"
	@rm -rf $(UVM_DIR)
	@mkdir -p $(dir $(UVM_DIR))
	@git clone -q --depth 1 --branch $(UVM_REV) $(UVM_URL) $(UVM_DIR)
	@touch $@

.PHONY: uvm
uvm: $(UVM_STAMP)

# ---------------------------------------------------------------------------
# Verilator runtime shared library
# ---------------------------------------------------------------------------
VLT_INC := $(VERILATOR_ROOT)/include

# The full runtime.  Verilator only pulls in the subset a given model needs,
# but compiling all of it once is cheaper than compiling the subset many
# times, and it means one library serves every trace/coverage/VPI
# configuration a testbench might ask for.
VLTRT_SRCS := \
  verilated.cpp \
  verilated_dpi.cpp \
  verilated_vpi.cpp \
  verilated_timing.cpp \
  verilated_threads.cpp \
  verilated_random.cpp \
  verilated_probdist.cpp \
  verilated_save.cpp \
  verilated_cov.cpp \
  verilated_covergroup.cpp \
  verilated_profiler.cpp \
  verilated_vcd_c.cpp \
  verilated_fst_c.cpp \
  verilated_saif_c.cpp

VLTRT_OBJS := $(addprefix $(LIB_OBJ)/vltrt/,$(VLTRT_SRCS:.cpp=.o))

# The FST back end compresses with lz4 and zstd, and the VCD back end with
# zlib.  Resolving them here rather than at each testbench's link keeps the
# dependency in one place.

# -DVL_TIME_CONTEXT matches what the generated makefiles use, so the runtime
# and the model agree on how time is fetched.
VLTRT_CXXFLAGS := -O2 -fPIC -std=gnu++20 -DVL_TIME_CONTEXT \
                  -I$(VLT_INC) -I$(VLT_INC)/vltstd \
                  -Wno-unused-parameter -Wno-shadow

$(LIB_OBJ)/vltrt/%.o: $(VLT_INC)/%.cpp
	@mkdir -p $(dir $@)
	@echo "[vltrt] $*"
	@$(OBJCACHE) $(CXX) $(VLTRT_CXXFLAGS) -c -o $@ $<

$(VLTRT_SO): $(VLTRT_OBJS)
	@mkdir -p $(dir $@)
	@echo "[vltrt] link $(notdir $@)"
	@$(CXX) -shared -o $@ $^ -lz -llz4 -lzstd -lpthread

# ---------------------------------------------------------------------------
# UVM DPI shared library
# ---------------------------------------------------------------------------
UVMDPI_SRC := $(REPO_ROOT)/lib/dpi/uvm_dpi_verilator.cpp

UVMDPI_CXXFLAGS := -O2 -fPIC -std=gnu++20 \
                   -I$(VLT_INC) -I$(VLT_INC)/vltstd \
                   -I$(UVM_SRC)/dpi -I$(REPO_ROOT)/lib/dpi \
                   -DUVM_HDL_MAX_WIDTH=$(UVM_HDL_MAX_WIDTH) \
                   -Wno-unused-parameter -Wno-write-strings

ifeq ($(UVM_VLT_POLLING),1)
  UVMDPI_CXXFLAGS += -DUVM_VLT_POLLING_SUPPORTED
endif

$(UVMDPI_SO): $(UVMDPI_SRC) $(REPO_ROOT)/lib/dpi/uvm_hdl_verilator.c | $(UVM_STAMP)
	@mkdir -p $(dir $@) $(LIB_OBJ)
	@echo "[uvmdpi] compile"
	@$(OBJCACHE) $(CXX) $(UVMDPI_CXXFLAGS) -c -o $(LIB_OBJ)/uvm_dpi_verilator.o $(UVMDPI_SRC)
	@echo "[uvmdpi] link $(notdir $@)"
	@$(CXX) -shared -o $@ $(LIB_OBJ)/uvm_dpi_verilator.o

# ---------------------------------------------------------------------------
# Aggregate target
# ---------------------------------------------------------------------------
SHARED_LIBS :=
ifeq ($(USE_SHARED_LIBS),1)
  SHARED_LIBS += $(VLTRT_SO)
  ifeq ($(UVM_DPI),1)
    SHARED_LIBS += $(UVMDPI_SO)
  endif
endif

.PHONY: libs
libs: $(UVM_STAMP) $(SHARED_LIBS)
	@echo "[libs]  ready in $(LIB_OUT)"

.PHONY: libs-clean
libs-clean:
	rm -rf $(LIB_DIR)
