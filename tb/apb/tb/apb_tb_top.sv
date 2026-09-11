//----------------------------------------------------------------------
// apb_tb_top.sv - clock, reset, DUT instance and the UVM entry point.
//----------------------------------------------------------------------

`timescale 1ns/1ps

`include "uvm_macros.svh"

module apb_tb_top;

  import uvm_pkg::*;
  import apb_pkg::*;
  import apb_env_pkg::*;
  import apb_test_pkg::*;

  localparam time CLK_PERIOD = 10ns;

  logic pclk = 1'b0;
  logic presetn = 1'b0;

  always #(CLK_PERIOD/2) pclk = ~pclk;

  initial begin
    presetn = 1'b0;
    repeat (5) @(posedge pclk);
    presetn = 1'b1;
  end

  apb_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) apb_bus (
    .pclk    (pclk),
    .presetn (presetn)
  );

  apb_slave_regs #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) dut (
    .pclk    (pclk),
    .presetn (presetn),
    .psel    (apb_bus.psel),
    .penable (apb_bus.penable),
    .pwrite  (apb_bus.pwrite),
    .paddr   (apb_bus.paddr),
    .pwdata  (apb_bus.pwdata),
    .prdata  (apb_bus.prdata),
    .pready  (apb_bus.pready),
    .pslverr (apb_bus.pslverr)
  );

  // Waveforms are opt-in at run time as well as at compile time, so a build
  // that has tracing compiled in can still run at full speed without it.
  initial begin
    string wave_file;
    if ($test$plusargs("wave")) begin
      if (!$value$plusargs("wave_file=%s", wave_file)) wave_file = "apb.vcd";
      $dumpfile(wave_file);
      $dumpvars(0, apb_tb_top);
    end
  end

  // A hard stop so a hung sequence fails the regression instead of running
  // until the job scheduler kills it.
  initial begin
    #1ms;
    `uvm_fatal("TIMEOUT", "global timeout reached")
  end

  initial begin
    uvm_config_db #(virtual apb_if)::set(null, "uvm_test_top", "vif", apb_bus);
    run_test();
  end

endmodule
