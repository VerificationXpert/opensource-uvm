interface fifo_if #(parameter int unsigned WIDTH = 8) (input logic clk, input logic rst_n);
  logic             push, pop, full, empty;
  logic [WIDTH-1:0] wdata, rdata;

  clocking drv_cb @(negedge clk);
    output push, pop, wdata;
    input  full, empty, rdata;
  endclocking

  clocking mon_cb @(posedge clk);
    input push, pop, wdata, rdata, full, empty;
  endclocking
endinterface
