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

# ---------------------------------------------------------------------------
# Local patch series
#
# The UVM tree is used unmodified today - upstream Accellera 2020.3.1 compiles
# under Verilator 5.050 with no changes. This exists for when that stops being
# true, so a fix can be carried as a patch against a pinned revision rather
# than by forking UVM.
#
# Patches are part of the checkout's identity: their combined hash goes into
# the stamp filename and into UVM_ID, so editing, adding or removing one
# re-fetches a clean tree and re-applies the series. Nothing is ever applied
# on top of an already-patched tree.
# ---------------------------------------------------------------------------
UVM_PATCHES := $(sort $(wildcard $(addsuffix /*.patch,$(UVM_PATCH_DIRS))) \
                      $(wildcard $(addsuffix /*.diff,$(UVM_PATCH_DIRS))))

# Hash the contents, not just the names, so editing a patch in place counts.
ifneq ($(strip $(UVM_PATCHES)),)
  UVM_PATCH_HASH := $(shell cat $(UVM_PATCHES) | md5sum | cut -c1-8)
  UVM_PATCH_TAG  := -p$(UVM_PATCH_HASH)
else
  UVM_PATCH_HASH :=
  UVM_PATCH_TAG  :=
endif

# A stable identity for the UVM in use. For a fetched library that is the
# flavour and revision; for a user-supplied UVM_HOME it is a hash of the path,
# since two installs can share a basename. The patch series is folded in so a
# patched and an unpatched UVM never share a shared-library cache entry.
ifeq ($(UVM_FLAVOR),custom)
  UVM_ID := custom-$(shell printf '%s' '$(UVM_HOME)' | md5sum | cut -c1-8)$(UVM_PATCH_TAG)
else ifeq ($(UVM_FLAVOR),accellera)
  UVM_ID := accellera-$(UVM_ACCELLERA_REV)$(UVM_PATCH_TAG)
else ifeq ($(UVM_FLAVOR),antmicro)
  UVM_ID := antmicro-$(UVM_ANTMICRO_REV)$(UVM_PATCH_TAG)
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
APPLY_PATCHES := $(UVMAKE_ROOT)/scripts/apply_patches.sh

ifeq ($(UVM_FLAVOR),custom)

ifeq ($(strip $(UVM_PATCHES)),)

# Nothing to fetch and nothing to patch: use the install as it stands. Fail
# early and clearly if the path is wrong, rather than letting Verilator
# report a missing uvm_pkg.sv.
UVM_STAMP := $(UVM_SRC)/uvm_pkg.sv

$(UVM_STAMP):
	@echo "error: UVM_HOME='$(UVM_HOME)' has no src/uvm_pkg.sv" >&2
	@echo "       Point UVM_HOME at the root of a UVM kit (the directory" >&2
	@echo "       containing src/), or unset it to fetch one." >&2
	@false

else

# A UVM_HOME the user supplied is very often a shared, read-only site
# install, so it is never modified in place. Copy it into the cache and patch
# the copy; UVM_SRC is redirected at the copy for everything downstream.
UVM_PATCHED_DIR := $(UVMAKE_CACHE)/uvm/$(UVM_ID)
UVM_SRC         := $(UVM_PATCHED_DIR)/src
UVM_STAMP       := $(UVM_PATCHED_DIR)/.patched-$(UVM_PATCH_HASH)

# Only a command-line or environment UVM_SRC counts as the user overriding
# us; config.mk's own '?=' default makes the origin 'file', which would
# otherwise make this fire on every build.
ifneq ($(filter command line environment,$(origin UVM_SRC)),)
  $(warning *** UVM_SRC was set explicitly and local patches are present.)
  $(warning *** Your UVM_SRC wins, so the patched copy under)
  $(warning *** $(UVM_PATCHED_DIR) will NOT be used.)
endif

$(UVM_STAMP):
	@echo "[uvm]     copying $(UVM_HOME) to patch it (original left untouched)"
	@rm -rf $(UVM_PATCHED_DIR)
	@mkdir -p $(dir $(UVM_PATCHED_DIR))
	@cp -a $(UVM_HOME)/. $(UVM_PATCHED_DIR)/
	@$(APPLY_PATCHES) $(UVM_PATCHED_DIR) $(UVM_PATCH_DIRS)
	@touch $@

endif

else

UVM_URL := $(if $(filter accellera,$(UVM_FLAVOR)),$(UVM_ACCELLERA_URL),$(UVM_ANTMICRO_URL))
UVM_REV := $(if $(filter accellera,$(UVM_FLAVOR)),$(UVM_ACCELLERA_REV),$(UVM_ANTMICRO_REV))

# The patch hash is part of the stamp name, so changing the series asks for a
# tree that does not exist yet and the rule below re-fetches from scratch.
# Patches are therefore only ever applied to a pristine checkout.
UVM_STAMP := $(UVM_DIR)/.fetched-$(UVM_REV)$(UVM_PATCH_TAG)

$(UVM_STAMP): $(UVM_PATCHES)
	@echo "[uvm]     fetching $(UVM_FLAVOR) UVM @ $(UVM_REV)"
	@rm -rf $(UVM_DIR)
	@mkdir -p $(dir $(UVM_DIR))
	@git clone -q --depth 1 --branch $(UVM_REV) $(UVM_URL) $(UVM_DIR)
	@$(APPLY_PATCHES) $(UVM_DIR) $(UVM_PATCH_DIRS)
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

# Introspection for the patch series - what was found, what identity it
# produces, and which tree everything will actually compile against. Worth
# having because a patch silently not being picked up looks exactly like a
# patch that had no effect.
.PHONY: print-patches
print-patches:
	@echo "flavor      : $(UVM_FLAVOR)"
	@echo "patch dirs  : $(UVM_PATCH_DIRS)"
	@echo "patches     : $(if $(UVM_PATCHES),$(UVM_PATCHES),(none))"
	@echo "patch hash  : $(if $(UVM_PATCH_HASH),$(UVM_PATCH_HASH),(none))"
	@echo "uvm id      : $(UVM_ID)"
	@echo "uvm src     : $(UVM_SRC)"
