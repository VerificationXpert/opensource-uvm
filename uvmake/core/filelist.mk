# ---------------------------------------------------------------------------
# uvmake/core/filelist.mk - turn .f filelists into make variables.
#
# A testbench supplies sources either way round:
#
#   TB_FILELIST := tb.f            a filelist (what real projects have)
#   TB_SRCS     := a.sv b.sv       an explicit list
#
# Both may be given; filelist sources come first, since a filelist usually
# carries the RTL and package compile order.
#
# The expansion is written to the build directory and included. Make will
# regenerate it and re-exec itself whenever any .f in the tree changes, which
# is what FL_DEPS is for.
# ---------------------------------------------------------------------------

FL_MK := $(OBJ_DIR)/filelist.mk

ifneq ($(strip $(TB_FILELIST)),)

# Variables a filelist may reference as $NAME. PROJECT_ROOT and TB_DIR cover
# the common "everything hangs off the repo root" and "everything is beside
# this filelist" cases without the filelist hard-coding a path.
FL_VARS ?= PROJECT_ROOT=$(PROJECT_ROOT) TB_DIR=$(CURDIR) UVM_HOME=$(UVM_HOME)

$(FL_MK): $(TB_FILELIST)
	@mkdir -p $(dir $@)
	@$(UVMAKE_ROOT)/scripts/expand_filelist.py \
	   $(addprefix -D,$(FL_VARS)) -o $@ $(TB_FILELIST)

# '-include' rather than 'include': on a clean tree the fragment does not
# exist yet, and make builds it from the rule above and restarts.
-include $(FL_MK)

# Re-expand when any filelist reached through -f changes, not just the top one.
ifneq ($(strip $(FL_DEPS)),)
$(FL_MK): $(FL_DEPS)
endif

endif

# The UVM package itself. uvm_pkg.sv `includes the whole library, so this one
# file is all Verilator needs; listing the individual sources would make it
# read them twice.
#
# It is prepended automatically because every UVM testbench needs it and
# forgetting it produces a baffling error deep inside the library rather than
# an obvious "no such package". Set UVM_AUTO_COMPILE=0 if your filelist
# already names it (some projects compile UVM as part of a shared library
# filelist and would otherwise get it twice).
UVM_AUTO_COMPILE ?= 1
UVM_PKG_SV := $(UVM_SRC)/uvm_pkg.sv

# What the rest of the flow consumes.
UVMAKE_SOURCES := $(if $(filter 1,$(UVM_AUTO_COMPILE)),$(UVM_PKG_SV)) \
                  $(FL_SOURCES) $(TB_SRCS)
UVMAKE_INCDIRS := $(UVM_SRC) $(FL_INCDIRS) $(TB_INCDIRS)
UVMAKE_DEFINES := $(FL_DEFINES) $(TB_DEFINES)
UVMAKE_LIBDIRS := $(FL_LIBDIRS) $(TB_LIBDIRS)
UVMAKE_LIBEXTS := $(FL_LIBEXTS) $(TB_LIBEXTS)

.PHONY: print-filelist
print-filelist:
	@echo "sources:"; $(if $(UVMAKE_SOURCES),printf '  %s\n' $(UVMAKE_SOURCES),echo "  (none)")
	@echo "incdirs:"; $(if $(UVMAKE_INCDIRS),printf '  %s\n' $(UVMAKE_INCDIRS),echo "  (none)")
	@echo "defines:"; $(if $(UVMAKE_DEFINES),printf '  %s\n' $(UVMAKE_DEFINES),echo "  (none)")
