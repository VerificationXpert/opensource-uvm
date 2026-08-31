# Project-wide uvmake settings.
#
# Every makefile in this project includes this file first, so a testbench
# works whether it is invoked from the project root or from its own
# directory.
#
# This example lives inside the uvmake repository, so it reaches uvmake by a
# relative path. In your own project uvmake is normally a git submodule at
# $(PROJECT_ROOT)/uvmake, in which case this is just:
#
#     UVMAKE ?= $(PROJECT_ROOT)/uvmake
#
UVMAKE ?= $(abspath $(PROJECT_ROOT)/../../uvmake)

# Anything from uvmake/core/config.mk can be pinned here, project-wide:
#
# UVM_HOME     ?= /tools/uvm/1800.2-2020-3.1   # use an existing UVM install
# BUILD_MODE   ?= fast
# UVMAKE_CACHE ?= /scratch/shared/.uvmake      # share UVM + .so across projects
