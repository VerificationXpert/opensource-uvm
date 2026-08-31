# APB UVM testbench.
#
#   make run TEST=apb_rw_test
#   make run TEST=apb_reg_test
#   make run TEST=apb_backdoor_test      # needs UVM_DPI=1 (the default)
#   make run TEST=apb_random_test SEED=7 TRACE=fst

REPO_ROOT := $(abspath $(CURDIR)/../..)
include $(REPO_ROOT)/mk/config.mk
include $(REPO_ROOT)/mk/uvm.mk

TB_NAME := apb
TB_TOP  := apb_tb_top

# Order matters: packages must be compiled before the modules that import them.
TB_SRCS := \
  $(CURDIR)/rtl/apb_slave_regs.sv \
  $(CURDIR)/tb/apb_if.sv \
  $(CURDIR)/tb/apb_pkg.sv \
  $(CURDIR)/tb/apb_env_pkg.sv \
  $(CURDIR)/tests/apb_test_pkg.sv \
  $(CURDIR)/tb/apb_tb_top.sv

TB_INCDIRS := $(CURDIR)/tb $(CURDIR)/tests

TEST ?= apb_rw_test

include $(REPO_ROOT)/mk/verilator.mk
