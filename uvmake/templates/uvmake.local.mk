# Project-wide uvmake settings. Copy to your project root.
#
# Every makefile in the project includes this first, so a testbench works
# whether it is invoked from the project root or from its own directory.

UVMAKE ?= $(PROJECT_ROOT)/uvmake

# Pin anything from uvmake/core/config.mk here, project-wide:
#
# UVM_HOME   ?= /tools/uvm/1800.2-2020-3.1   # use an existing UVM install
# BUILD_MODE ?= fast
# JOBS       ?= 16
# UVMAKE_CACHE ?= /scratch/shared/.uvmake    # share UVM and .so across projects
