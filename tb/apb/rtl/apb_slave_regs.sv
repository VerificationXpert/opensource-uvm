//----------------------------------------------------------------------
// apb_slave_regs.sv
//
// A small APB3 slave with four registers.  It exists to give the testbench
// something real to drive, and to exercise the uvm_reg frontdoor and
// backdoor paths.
//
// The `/*verilator public_flat_rw*/` attributes are what make the register
// storage reachable over VPI, which is what the UVM backdoor
// (uvm_hdl_read / uvm_hdl_deposit, see lib/dpi/uvm_hdl_verilator.c) needs.
// Without them the signals are optimised into Verilator's internals and
// vpi_handle_by_name cannot resolve them - the open-source equivalent of a
// missing PLI/ACC visibility setting on a commercial simulator.
//----------------------------------------------------------------------

module apb_slave_regs #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32
) (
    input  logic                    pclk,
    input  logic                    presetn,
    input  logic                    psel,
    input  logic                    penable,
    input  logic                    pwrite,
    input  logic [ADDR_WIDTH-1:0]   paddr,
    input  logic [DATA_WIDTH-1:0]   pwdata,
    output logic [DATA_WIDTH-1:0]   prdata,
    output logic                    pready,
    output logic                    pslverr
);

  localparam logic [11:0] ADDR_CTRL    = 12'h000;
  localparam logic [11:0] ADDR_STATUS  = 12'h004;
  localparam logic [11:0] ADDR_SCRATCH = 12'h008;
  localparam logic [11:0] ADDR_ID      = 12'h00C;

  localparam logic [31:0] ID_VALUE = 32'h0BADC0DE;

  logic [31:0] ctrl_q    /*verilator public_flat_rw*/;
  logic [31:0] scratch_q /*verilator public_flat_rw*/;
  logic [31:0] status_q  /*verilator public_flat_rw*/;

  // STATUS is read-only to the bus and simply reflects CTRL, so a test can
  // check that a frontdoor write is observable through a different register.
  assign status_q = {28'd0, ctrl_q[3:0]};

  wire        addr_valid = (paddr[11:0] inside {ADDR_CTRL, ADDR_STATUS,
                                                ADDR_SCRATCH, ADDR_ID});
  // APB3 access phase: PSEL & PENABLE, with PREADY driven high (no wait states).
  wire        access     = psel & penable;

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      ctrl_q    <= '0;
      scratch_q <= '0;
    end else if (access && pwrite && addr_valid) begin
      unique case (paddr[11:0])
        ADDR_CTRL:    ctrl_q    <= pwdata;
        ADDR_SCRATCH: scratch_q <= pwdata;
        default: ;  // STATUS and ID ignore writes
      endcase
    end
  end

  always_comb begin
    prdata = '0;
    if (psel && !pwrite) begin
      unique case (paddr[11:0])
        ADDR_CTRL:    prdata = ctrl_q;
        ADDR_STATUS:  prdata = status_q;
        ADDR_SCRATCH: prdata = scratch_q;
        ADDR_ID:      prdata = ID_VALUE;
        default:      prdata = '0;
      endcase
    end
  end

  assign pready  = 1'b1;
  assign pslverr = access & ~addr_valid;

endmodule
