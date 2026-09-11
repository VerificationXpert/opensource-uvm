// A synchronous FIFO - the DUT for this example project.
module sync_fifo #(
    parameter int unsigned WIDTH = 8,
    parameter int unsigned DEPTH = 4
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             push,
    input  logic [WIDTH-1:0] wdata,
    input  logic             pop,
    output logic [WIDTH-1:0] rdata,
    output logic             full,
    output logic             empty
);
  localparam int unsigned PTRW = $clog2(DEPTH);

  logic [WIDTH-1:0] mem [DEPTH];
  logic [PTRW:0]    wptr, rptr;

  assign empty = (wptr == rptr);
  assign full  = (wptr[PTRW] != rptr[PTRW]) && (wptr[PTRW-1:0] == rptr[PTRW-1:0]);
  assign rdata = mem[rptr[PTRW-1:0]];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wptr <= '0;
      rptr <= '0;
    end else begin
      if (push && !full) begin
        mem[wptr[PTRW-1:0]] <= wdata;
        wptr <= wptr + 1'b1;
      end
      if (pop && !empty) rptr <= rptr + 1'b1;
    end
  end
endmodule
