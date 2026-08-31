# acme-soc - an example project consuming uvmake from outside its repository.

PROJECT_ROOT := $(CURDIR)
include $(PROJECT_ROOT)/uvmake.local.mk
include $(UVMAKE)/uvmake.mk

# Testbenches live under verif/, not the default tb/.
TB_DIRS := $(PROJECT_ROOT)/verif

$(uvmake-project)
