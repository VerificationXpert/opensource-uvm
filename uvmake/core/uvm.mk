# ---------------------------------------------------------------------------
# uvmake/core/uvm.mk - the UVM library and the precompiled shared objects.
#
# Two things are genuinely independent of any testbench and are built once
# per toolchain into $(UVMAKE_CACHE):
#
#   libvltrt.so    Verilator's runtime (verilated.cpp, verilated_timing.cpp,
#                  the trace back ends, the VPI/DPI entry points, ...).
#                  Verilator's generated makefile lists these in
#                  VM_GLOBAL_FAST and recompiles them into every simulation
#                  binary; they depend only on the Verilator version.
#
#   libuvmdpi.so   The UVM DPI C/C++ layer, including the Verilator VPI
#                  backdoor backend in uvmake/dpi/. This is what makes it
#                  possible to run UVM without +define+UVM_NO_DPI.
#
# The cache path carries the Verilator version, the UVM identity and the HDL
# width, so switching any of them gets its own libraries rather than silently
# reusing incompatible ones.
# ---------------------------------------------------------------------------

# A stable identity for the UVM in use. For a fetched library that is the
# flavour and revision; for a user-supplied UVM_HOME it is a hash of the path,
# since two installs can share a basename.
ifeq ($(UVM_FLAVOR),custom)
  UVM_ID := custom-$(shell printf '%s' '$(UVM_HOME)' | md5sum | cut -c1-8)
else ifeq ($(UVM_FLAVOR),accellera)
  UVM_ID := accellera-$(UVM_ACCELLERA_REV)
else ifeq ($(UVM_FLAVOR),antmicro)
  UVM_ID := antmicro-$(UVM_ANTMICRO_REV)
else
  $(error UVM_FLAVOR must be accellera, antmicro or custom (got '$(UVM_FLAVOR)'))
endif

LIB_TAG := vlt$(UVMAKE_VERILATOR_VERSION)-$(UVM_ID)-w$(UVM_HDL_MAX_WIDTH)
LIB_OUT := $(UVMAKE_CACHE)/lib/$(LIB_TAG)
LIB_OBJ := $(LIB_OUT)/obj

VLTRT_SO  := $(LIB_OUT)/libvltrt.so
UVMDPI_SO := $(LIB_OUT)/libuvmdpi.so

# ---------------------------------------------------------------------------
# UVM checkout
# ---------------------------------------------------------------------------
ifeq ($(UVM_FLAVOR),custom)

# Nothing to fetch. Fail early and clearly if the path is wrong, rather than
# letting Verilator report a missing uvm_pkg.sv.
UVM_STAMP := $(UVM_SRC)/uvm_pkg.sv

$(UVM_STAMP):
	@echo "error: UVM_HOME='$(UVM_HOME)' has no src/uvm_pkg.sv" >&2
	@echo "       Point UVM_HOME at the root of a UVM kit (the directory" >&2
	@echo "       containing src/), or unset it to fetch one." >&2
	@false

else

UVM_URL := $(if $(filter accellera,$(UVM_FLAVOR)),$(UVM_ACCELLERA_URL),$(UVM_ANTMICRO_URL))
UVM_REV := $(if $(filter accellera,$(UVM_FLAVOR)),$(UVM_ACCELLERA_REV),$(UVM_ANTMICRO_REV))

UVM_STAMP := $(UVM_DIR)/.fetched-$(UVM_REV)

$(UVM_STAMP):
	@echo "[uvm]     fetching $(UVM_FLAVOR) UVM @ $(UVM_REV)"
	@rm -rf $(UVM_DIR)
	@mkdir -p $(dir $(UVM_DIR))
	@git clone -q --depth 1 --branch $(UVM_REV) $(UVM_URL) $(UVM_DIR)
	@touch $@

endif

.PHONY: uvm
uvm: $(UVM_STAMP)

# ---------------------------------------------------------------------------
# Verilator runtime shared library
# ---------------------------------------------------------------------------
VLT_INC := $(VERILATOR_ROOT)/include

# All of it. Verilator would pull in only the subset a given model needs, but
# compiling everything once is cheaper than compiling the subset many times,
# and one library then serves every trace/coverage/VPI configuration.
VLTRT_SRCS := \
  verilated.cpp verilated_dpi.cpp verilated_vpi.cpp \
  verilated_timing.cpp verilated_threads.cpp \
  verilated_random.cpp verilated_probdist.cpp verilated_save.cpp \
  verilated_cov.cpp verilated_covergroup.cpp verilated_profiler.cpp \
  verilated_vcd_c.cpp verilated_fst_c.cpp verilated_saif_c.cpp

VLTRT_OBJS := $(addprefix $(LIB_OBJ)/vltrt/,$(VLTRT_SRCS:.cpp=.o))

# -DVL_TIME_CONTEXT matches what the generated makefiles use, so the runtime
# and the model agree on how simulation time is fetched.
VLTRT_CXXFLAGS := -O2 -fPIC -std=gnu++20 -DVL_TIME_CONTEXT \
                  -I$(VLT_INC) -I$(VLT_INC)/vltstd \
                  -Wno-unused-parameter -Wno-shadow

$(LIB_OBJ)/vltrt/%.o: $(VLT_INC)/%.cpp
	@mkdir -p $(dir $@)
	@echo "[vltrt]   $*"
	@$(OBJCACHE) $(CXX) $(VLTRT_CXXFLAGS) -c -o $@ $<

# The FST back end compresses with lz4 and zstd and the VCD back end with
# zlib; resolving them here keeps the dependency out of every testbench link.
$(VLTRT_SO): $(VLTRT_OBJS)
	@mkdir -p $(dir $@)
	@echo "[vltrt]   link $(notdir $@)"
	@$(CXX) -shared -o $@ $^ -lz -llz4 -lzstd -lpthread

# ---------------------------------------------------------------------------
# UVM DPI shared library
# ---------------------------------------------------------------------------
UVMDPI_SRC  := $(UVMAKE_ROOT)/dpi/uvm_dpi_verilator.cpp
UVMDPI_DEPS := $(UVMDPI_SRC) $(UVMAKE_ROOT)/dpi/uvm_hdl_verilator.c

UVMDPI_CXXFLAGS := -O2 -fPIC -std=gnu++20 \
                   -I$(VLT_INC) -I$(VLT_INC)/vltstd \
                   -I$(UVM_SRC)/dpi -I$(UVMAKE_ROOT)/dpi \
                   -DUVM_HDL_MAX_WIDTH=$(UVM_HDL_MAX_WIDTH) \
                   -Wno-unused-parameter -Wno-write-strings

ifeq ($(UVM_VLT_POLLING),1)
  UVMDPI_CXXFLAGS += -DUVM_VLT_POLLING_SUPPORTED
endif

$(UVMDPI_SO): $(UVMDPI_DEPS) | $(UVM_STAMP)
	@mkdir -p $(dir $@) $(LIB_OBJ)
	@echo "[uvmdpi]  compile"
	@$(OBJCACHE) $(CXX) $(UVMDPI_CXXFLAGS) -c -o $(LIB_OBJ)/uvm_dpi_verilator.o $(UVMDPI_SRC)
	@echo "[uvmdpi]  link $(notdir $@)"
	@$(CXX) -shared -o $@ $(LIB_OBJ)/uvm_dpi_verilator.o

# ---------------------------------------------------------------------------
SHARED_LIBS :=
ifeq ($(USE_SHARED_LIBS),1)
  SHARED_LIBS += $(VLTRT_SO)
endif
ifeq ($(UVM_DPI),1)
  SHARED_LIBS += $(UVMDPI_SO)
endif

.PHONY: libs libs-clean
libs: $(UVM_STAMP) $(SHARED_LIBS)
	@echo "[libs]    ready in $(LIB_OUT)"

libs-clean:
	rm -rf $(UVMAKE_CACHE)/lib
