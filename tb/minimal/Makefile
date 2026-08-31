# Minimal UVM testbench - the toolchain smoke test.
#
#   make run TEST=base_test
#   make run TEST=dpi_smoke_test
#   make lint
#   make run TEST=base_test TRACE=fst BUILD_MODE=opt

PROJECT_ROOT ?= $(abspath $(CURDIR)/../..)
include $(PROJECT_ROOT)/uvmake/uvmake.mk

TB_NAME     := minimal
TB_TOP      := minimal_tb_top
TB_FILELIST := $(CURDIR)/minimal.f

TEST ?= base_test

$(uvmake-testbench)
