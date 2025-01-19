// top.sv
`include "uvm_pkg.sv"
import uvm_pkg::*;

module top;

  initial begin
    // Run a basic UVM test
    run_test("basic_test");
  end

endmodule

// Simple UVM test class
class basic_test extends uvm_test;
    `uvm_component_utils(basic_test)

    function new(string name = "basic_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("BASIC_TEST", "Hello, UVM World!", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass
