# Minimal UVM testbench.
#
#   make run TEST=base_test
#   make run TEST=dpi_smoke_test
#   make run TEST=base_test TRACE=fst BUILD_MODE=opt

REPO_ROOT := $(abspath $(CURDIR)/../..)
include $(REPO_ROOT)/mk/config.mk
include $(REPO_ROOT)/mk/uvm.mk

TB_NAME    := minimal
TB_TOP     := minimal_tb_top
TB_SRCS    := $(CURDIR)/minimal_tb_top.sv
TB_INCDIRS := $(CURDIR)

TEST ?= base_test

include $(REPO_ROOT)/mk/verilator.mk
