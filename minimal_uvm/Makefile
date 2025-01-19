all: simulate

UVM_ROOT ?= uvm
VERILATOR ?= verilator

VERILOG_INCLUDE_DIRS = \
    ${UVM_ROOT}/src \
    tb

VERILOG_SOURCES = \
    ${UVM_ROOT}/src/uvm.sv \
    tb/top.sv
	

SIM_NAME ?= uvm_tb
SIM_DIR := $(SIM_NAME)-sim

# Warning suppression and error limit
WARNING_ARGS += -Wno-lint \
	-Wno-style \
	-Wno-SYMRSVDWORD \
	-Wno-IGNOREDRETURN \
	-Wno-CONSTRAINTIGN \
	-Wno-ZERODLY

COMPILE_ARGS = --top-module top
COMPILE_ARGS += -DUVM_NO_DPI
COMPILE_ARGS += --prefix $(SIM_NAME)
COMPILE_ARGS += -o $(SIM_NAME)
COMPILE_ARGS += $(addprefix +incdir+, $(VERILOG_INCLUDE_DIRS))

EXTRA_ARGS += --timescale 1ns/1ps --error-limit 0 --trace --trace-structs

# Fetch UVM
$(UVM_ROOT):
	git clone https://github.com/antmicro/uvm-verilator -b current-patches $(UVM_ROOT)
	#git clone https://github.com/chipsalliance/uvm-verilator $(UVM_ROOT)

# Verilator Compilation
verilate: $(UVM_ROOT) $(VERILOG_SOURCES)
	$(VERILATOR) --cc --exe --main --timing -Mdir $(SIM_DIR) \
    $(COMPILE_ARGS) \
	$(VERILOG_SOURCES) \
	$(WARNING_ARGS) \
	$(EXTRA_ARGS)

# Build the simulation executable
build: verilate
	$(MAKE) -C $(SIM_DIR) -f $(SIM_NAME).mk

# Run the simulation
simulate: build
	$(SIM_DIR)/$(SIM_NAME) +UVM_TESTNAME=basic_test

# Clean up build artifacts
clean:
	rm -rf $(SIM_DIR) *.vcd $(UVM_ROOT)


.PHONY: verilate build simulate clean
