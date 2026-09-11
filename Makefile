# Project root.
#
#   make libs                      fetch UVM, build the shared libraries
#   make list                      show discovered testbenches
#   make apb                       build one testbench
#   make run TB=apb TEST=apb_rw_test
#   make regress
#   make help

PROJECT_ROOT := $(CURDIR)
include $(PROJECT_ROOT)/uvmake/uvmake.mk

$(uvmake-project)
