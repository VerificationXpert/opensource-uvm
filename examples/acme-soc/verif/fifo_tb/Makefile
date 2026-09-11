# FIFO testbench.
#
# Works standalone (make run TEST=...) or via the project root.

PROJECT_ROOT ?= $(abspath $(CURDIR)/../..)
include $(PROJECT_ROOT)/uvmake.local.mk
include $(UVMAKE)/uvmake.mk

TB_NAME     := fifo_tb
TB_TOP      := fifo_tb_top
TB_FILELIST := $(CURDIR)/fifo_tb.f

TEST ?= fifo_smoke_test

$(uvmake-testbench)
