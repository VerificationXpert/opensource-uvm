// A small but complete UVM agent for the FIFO, written the way a project
// would write one - the point of this example is that nothing in it knows
// anything about the build system.
package fifo_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum bit {FIFO_PUSH = 1'b0, FIFO_POP = 1'b1} fifo_op_e;

  class fifo_item extends uvm_sequence_item;
    rand fifo_op_e op;
    rand bit [7:0] data;
    bit            full, empty;

    `uvm_object_utils(fifo_item)
    function new(string name = "fifo_item"); super.new(name); endfunction

    virtual function string convert2string();
      return $sformatf("%s data=0x%02h", op.name(), data);
    endfunction
  endclass

  class fifo_cfg extends uvm_object;
    virtual fifo_if vif;
    `uvm_object_utils(fifo_cfg)
    function new(string name = "fifo_cfg"); super.new(name); endfunction
  endclass

  typedef uvm_sequencer #(fifo_item) fifo_sequencer;

  class fifo_driver extends uvm_driver #(fifo_item);
    `uvm_component_utils(fifo_driver)
    fifo_cfg cfg;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(fifo_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "fifo_cfg not found")
    endfunction

    virtual task run_phase(uvm_phase phase);
      fifo_item req;
      cfg.vif.drv_cb.push <= 1'b0;
      cfg.vif.drv_cb.pop  <= 1'b0;
      wait (cfg.vif.rst_n === 1'b1);
      forever begin
        seq_item_port.get_next_item(req);
        @(cfg.vif.drv_cb);
        cfg.vif.drv_cb.push  <= (req.op == FIFO_PUSH);
        cfg.vif.drv_cb.pop   <= (req.op == FIFO_POP);
        cfg.vif.drv_cb.wdata <= req.data;
        @(cfg.vif.drv_cb);
        cfg.vif.drv_cb.push <= 1'b0;
        cfg.vif.drv_cb.pop  <= 1'b0;
        seq_item_port.item_done();
      end
    endtask
  endclass

  class fifo_monitor extends uvm_monitor;
    `uvm_component_utils(fifo_monitor)
    fifo_cfg cfg;
    uvm_analysis_port #(fifo_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(fifo_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "fifo_cfg not found")
    endfunction

    virtual task run_phase(uvm_phase phase);
      forever begin
        @(cfg.vif.mon_cb);
        if (cfg.vif.mon_cb.push && !cfg.vif.mon_cb.full) begin
          fifo_item t = fifo_item::type_id::create("t");
          t.op = FIFO_PUSH; t.data = cfg.vif.mon_cb.wdata;
          ap.write(t);
        end
        if (cfg.vif.mon_cb.pop && !cfg.vif.mon_cb.empty) begin
          fifo_item t = fifo_item::type_id::create("t");
          t.op = FIFO_POP; t.data = cfg.vif.mon_cb.rdata;
          ap.write(t);
        end
      end
    endtask
  endclass

  class fifo_agent extends uvm_agent;
    `uvm_component_utils(fifo_agent)
    fifo_cfg       cfg;
    fifo_driver    driver;
    fifo_sequencer sequencer;
    fifo_monitor   monitor;
    uvm_analysis_port #(fifo_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(fifo_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "fifo_cfg not found")
      uvm_config_db #(fifo_cfg)::set(this, "*", "cfg", cfg);
      driver    = fifo_driver::type_id::create("driver", this);
      sequencer = fifo_sequencer::type_id::create("sequencer", this);
      monitor   = fifo_monitor::type_id::create("monitor", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
      monitor.ap.connect(ap);
    endfunction
  endclass

  // Checks FIFO ordering: whatever is pushed must pop back in order.
  class fifo_scoreboard extends uvm_component;
    `uvm_component_utils(fifo_scoreboard)
    uvm_analysis_imp #(fifo_item, fifo_scoreboard) ap_imp;
    protected bit [7:0] model[$];
    protected int       checks, errors;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap_imp = new("ap_imp", this);
    endfunction

    virtual function void write(fifo_item t);
      if (t.op == FIFO_PUSH) begin
        model.push_back(t.data);
      end else begin
        bit [7:0] expected;
        if (model.size() == 0) begin
          `uvm_error("SCBD", "pop observed with an empty reference model")
          return;
        end
        expected = model.pop_front();
        checks++;
        if (t.data !== expected) begin
          errors++;
          `uvm_error("SCBD", $sformatf("pop mismatch: expected 0x%02h, got 0x%02h",
                                       expected, t.data))
        end
      end
    endfunction

    virtual function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      if (checks == 0) `uvm_error("SCBD", "no pops were checked")
      else `uvm_info("SCBD", $sformatf("%0d pops checked, %0d mismatches",
                                       checks, errors), UVM_LOW)
    endfunction
  endclass

  class fifo_env extends uvm_env;
    `uvm_component_utils(fifo_env)
    fifo_cfg        cfg;
    fifo_agent      agent;
    fifo_scoreboard scoreboard;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(fifo_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "fifo_cfg not found")
      uvm_config_db #(fifo_cfg)::set(this, "agent", "cfg", cfg);
      agent      = fifo_agent::type_id::create("agent", this);
      scoreboard = fifo_scoreboard::type_id::create("scoreboard", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.ap.connect(scoreboard.ap_imp);
    endfunction
  endclass

  class fifo_fill_drain_seq extends uvm_sequence #(fifo_item);
    rand int unsigned n;
    constraint c_n { n inside {[2:4]}; }
    `uvm_object_utils(fifo_fill_drain_seq)
    function new(string name = "fifo_fill_drain_seq"); super.new(name); endfunction

    virtual task body();
      fifo_item req;
      for (int i = 0; i < n; i++) begin
        req = fifo_item::type_id::create("req");
        start_item(req);
        req.op = FIFO_PUSH; req.data = 8'(i + 1);
        finish_item(req);
      end
      for (int i = 0; i < n; i++) begin
        req = fifo_item::type_id::create("req");
        start_item(req);
        req.op = FIFO_POP; req.data = '0;
        finish_item(req);
      end
    endtask
  endclass
endpackage
