# ---------------------------------------------------------------------------
# uvmake - a reusable build system for UVM on Verilator.
#
# Include this from one place and it works out what you meant:
#
#   * If TB_NAME is set, you are describing a testbench, and you get
#     verilate / build / lint / run / waves / coverage.
#   * If it is not, you are the project root, and you get testbench
#     discovery, regress, bench and the aggregate targets.
#
# Testbench makefile:
#
#     PROJECT_ROOT ?= $(abspath $(CURDIR)/../..)
#     include $(PROJECT_ROOT)/uvmake/uvmake.mk        # or wherever it lives
#
#     TB_NAME     := apb
#     TB_TOP      := apb_tb_top
#     TB_FILELIST := $(CURDIR)/apb.f
#     TEST        ?= apb_rw_test
#
#     $(uvmake-testbench)
#
# Project makefile:
#
#     PROJECT_ROOT := $(CURDIR)
#     include $(PROJECT_ROOT)/uvmake/uvmake.mk
#     $(uvmake-project)
#
# See uvmake/README.md for the full variable reference.
# ---------------------------------------------------------------------------

# Where uvmake itself lives, derived from this file so it can be vendored
# anywhere - in-tree, a submodule, or a shared location outside the project.
UVMAKE_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# A literal space, for joining lists.
empty :=
space := $(empty) $(empty)

include $(UVMAKE_ROOT)/core/config.mk
include $(UVMAKE_ROOT)/core/toolchain.mk
include $(UVMAKE_ROOT)/core/uvm.mk

# The two modes are deferred into these macros rather than selected here,
# because a testbench makefile has to declare TB_NAME, TB_FILELIST and the
# rest *after* including this file - it needs UVM_HOME and PROJECT_ROOT to
# build its paths from. Calling $(uvmake-testbench) at the end of the
# testbench makefile evaluates the rules once those are known.
define uvmake-testbench
$(eval include $(UVMAKE_ROOT)/core/testbench.mk)
endef

define uvmake-project
$(eval include $(UVMAKE_ROOT)/core/project.mk)
endef
