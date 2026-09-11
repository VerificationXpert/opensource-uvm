# APB UVM testbench.
#
#   make run TEST=apb_rw_test
#   make run TEST=apb_backdoor_test        # needs UVM_DPI=1 (the default)
#   make run TEST=apb_random_test SEED=42 TRACE=fst
#   make coverage TEST=apb_random_test && make coverage-report

PROJECT_ROOT ?= $(abspath $(CURDIR)/../..)
include $(PROJECT_ROOT)/uvmake/uvmake.mk

TB_NAME     := apb
TB_TOP      := apb_tb_top
TB_FILELIST := $(CURDIR)/apb.f

TEST ?= apb_rw_test

$(uvmake-testbench)
