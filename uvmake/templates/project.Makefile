# Project root makefile. Copy to your project root as 'Makefile'.

PROJECT_ROOT := $(CURDIR)
include $(PROJECT_ROOT)/uvmake.local.mk
include $(UVMAKE)/uvmake.mk

# Where testbenches live; each subdirectory with a Makefile is one.
# TB_DIRS := $(PROJECT_ROOT)/verif

$(uvmake-project)
