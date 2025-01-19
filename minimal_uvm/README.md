# Minimal UVM Experiment

This repository contains a minimal Universal Verification Methodology (UVM) experiment to test the compilation and simulation of an empty `uvm_test` using Verilator.

## Directory Structure

```
minimal_uvm/
├── Makefile
├── README.md
└── tb
    └── top.sv
```

## Files

- **Makefile**: Contains the build and simulation instructions using Verilator.
- **tb/top.sv**: SystemVerilog file defining the top module and a simple UVM test class.

## Prerequisites

- Verilator
- Git

## Instructions

1. Clone the repository if not done:
    ```sh
    git clone https://github.com/verificationxpert/opensource-uvm.git
    cd opensource-uvm
    cd minimal_uvm
    ```

2. Fetch the UVM library:
    ```sh
    make uvm
    ```

3. Compile the Verilog sources with Verilator:
    ```sh
    make verilate
    ```

4. Build the simulation executable:
    ```sh
    make build
    ```

5. Run the simulation:
    ```sh
    make simulate
    ```

6. Clean up build artifacts:
    ```sh
    make clean
    ```

## Description

- The `Makefile` automates the process of fetching the UVM library, compiling the Verilog sources, building the simulation executable, and running the simulation.
- The `tb/top.sv` file includes a basic UVM test class that prints "Hello, UVM World!" during the simulation.

This setup provides a simple example of how to use Verilator to compile and simulate a UVM-based testbench.