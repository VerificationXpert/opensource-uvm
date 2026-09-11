//----------------------------------------------------------------------
// apb_if.sv - APB3 interface plus the clocking blocks the agent drives and
// samples through.
//----------------------------------------------------------------------

interface apb_if #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32
) (
    input logic pclk,
    input logic presetn
);

  logic                  psel;
  logic                  penable;
  logic                  pwrite;
  logic [ADDR_WIDTH-1:0] paddr;
  logic [DATA_WIDTH-1:0] pwdata;
  logic [DATA_WIDTH-1:0] prdata;
  logic                  pready;
  logic                  pslverr;

  // Driving on the negedge and sampling on the posedge keeps the testbench
  // clear of the setup/hold window without needing explicit clocking-block
  // skews, which are only partially supported.
  clocking drv_cb @(negedge pclk);
    output psel, penable, pwrite, paddr, pwdata;
    input  prdata, pready, pslverr;
  endclocking

  clocking mon_cb @(posedge pclk);
    input psel, penable, pwrite, paddr, pwdata, prdata, pready, pslverr;
  endclocking

  modport drv (clocking drv_cb, input pclk, presetn);
  modport mon (clocking mon_cb, input pclk, presetn);

endinterface
