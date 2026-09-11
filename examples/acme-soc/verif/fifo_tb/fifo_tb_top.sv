`timescale 1ns/1ps
`include "uvm_macros.svh"

module fifo_tb_top;
  import uvm_pkg::*;
  import fifo_pkg::*;
  import fifo_test_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5ns clk = ~clk;

  initial begin
    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
  end

  fifo_if #(.WIDTH(8)) fifo_bus (.clk(clk), .rst_n(rst_n));

  sync_fifo #(.WIDTH(8), .DEPTH(4)) dut (
    .clk(clk), .rst_n(rst_n),
    .push (fifo_bus.push),  .wdata(fifo_bus.wdata),
    .pop  (fifo_bus.pop),   .rdata(fifo_bus.rdata),
    .full (fifo_bus.full),  .empty(fifo_bus.empty)
  );

  initial begin
    string wave_file;
    if ($test$plusargs("wave")) begin
      if (!$value$plusargs("wave_file=%s", wave_file)) wave_file = "fifo.vcd";
      $dumpfile(wave_file);
      $dumpvars(0, fifo_tb_top);
    end
  end

  initial begin
    #500us;
    `uvm_fatal("TIMEOUT", "global timeout reached")
  end

  initial begin
    uvm_config_db #(virtual fifo_if)::set(null, "uvm_test_top", "vif", fifo_bus);
    run_test();
  end
endmodule
