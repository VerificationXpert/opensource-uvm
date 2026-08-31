# Testbench makefile. Copy into your testbench directory as 'Makefile'.

PROJECT_ROOT ?= $(abspath $(CURDIR)/../..)
include $(PROJECT_ROOT)/uvmake.local.mk
include $(UVMAKE)/uvmake.mk

TB_NAME     := my_tb
TB_TOP      := my_tb_top
TB_FILELIST := $(CURDIR)/my_tb.f

TEST ?= my_base_test

# Optional:
# TB_INCDIRS := $(CURDIR)/tests
# TB_DEFINES := MY_FLAG
# TB_VLT_ARGS := --assert
# TB_LDLIBS  := -lmy_dpi_model

$(uvmake-testbench)
