//----------------------------------------------------------------------
// minimal_tb_top.sv
//
// The smallest useful UVM testbench: it exists to prove the toolchain
// (Verilator + UVM + the DPI layer) is wired up correctly, and it doubles as
// the compile-time benchmark, since almost all of the build cost here is the
// UVM library itself rather than the design.
//
// Note that run_test() is called with no argument.  Resolving the test name
// from +UVM_TESTNAME goes through uvm_cmdline_processor, which is a DPI path
// (vpi_get_vlog_info).  If this elaborates and runs, the DPI layer works.
//----------------------------------------------------------------------

`include "uvm_macros.svh"

package minimal_test_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class base_test extends uvm_test;
    `uvm_component_utils(base_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      `uvm_info("BASE_TEST", "Hello from open-source UVM on Verilator", UVM_LOW)
      #10ns;
      phase.drop_objection(this);
    endtask
  endclass

  // Exercises the parts of UVM that only work when DPI is enabled, so a
  // regression catches a build that silently fell back to UVM_NO_DPI.
  class dpi_smoke_test extends base_test;
    `uvm_component_utils(dpi_smoke_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
      uvm_cmdline_processor clp = uvm_cmdline_processor::get_inst();
      string values[$];
      int    n;

      phase.raise_objection(this);

      // 1. Real regular expressions.  Without the DPI regex layer UVM falls
      //    back to glob-only matching, where the character class below is
      //    treated literally and this match fails.
      if (uvm_is_match("/^uvm_test_[a-z]+$/", "uvm_test_top"))
        `uvm_info("DPI_SMOKE", "regex matching via DPI: OK", UVM_LOW)
      else
        `uvm_error("DPI_SMOKE",
                   "regex matching failed - built without the DPI regex layer?")

      // 2. Command-line access through vpi_get_vlog_info.
      n = clp.get_arg_values("+UVM_TESTNAME=", values);
      if (n > 0)
        `uvm_info("DPI_SMOKE",
                  $sformatf("cmdline processor via DPI: OK (+UVM_TESTNAME=%s)",
                            values[0]), UVM_LOW)
      else
        `uvm_error("DPI_SMOKE",
                   "uvm_cmdline_processor saw no +UVM_TESTNAME - DPI cmdline layer missing?")

      #10ns;
      phase.drop_objection(this);
    endtask
  endclass
endpackage

module minimal_tb_top;
  import uvm_pkg::*;
  import minimal_test_pkg::*;

  initial begin
    run_test();
  end
endmodule
