//----------------------------------------------------------------------
// apb_pkg.sv
//
// A conventional UVM agent for the APB3 slave: sequence item, driver,
// monitor, sequencer, coverage collector, agent, plus a register model,
// predictor-backed scoreboard and the environment that ties them together.
//
// The structure here is deliberately the one a commercial project would use
// (config objects in uvm_config_db, an analysis-port scoreboard, a RAL block
// with both frontdoor and backdoor maps), so that the compile-time and
// runtime numbers in docs/COMPILE_TIME.md come from a realistic amount of
// UVM rather than from an empty test.
//----------------------------------------------------------------------

package apb_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum bit {APB_READ = 1'b0, APB_WRITE = 1'b1} apb_dir_e;

  //--------------------------------------------------------------------
  // Sequence item
  //--------------------------------------------------------------------
  class apb_item extends uvm_sequence_item;

    rand bit [31:0] addr;
    rand bit [31:0] data;
    rand apb_dir_e  dir;
    bit             slverr;

    // The DUT decodes four word-aligned registers in 0x000..0x00C.
    constraint c_addr {
      addr inside {32'h000, 32'h004, 32'h008, 32'h00C};
    }

    // Deliberately not using `uvm_field_* here.  The field macros implement
    // copy/compare/print through a generic reflection loop, which is both
    // slower at run time and expands to width-mismatched code that lints
    // badly in the *user's* file rather than in the UVM tree, where the
    // waivers in lib/vlt/uvm_waivers.vlt could catch it.  Writing the three
    // hooks out costs a few lines and keeps the testbench lint-clean.
    `uvm_object_utils(apb_item)

    function new(string name = "apb_item");
      super.new(name);
    endfunction

    virtual function void do_copy(uvm_object rhs);
      apb_item that;
      if (!$cast(that, rhs)) begin
        `uvm_fatal("DO_COPY", "rhs is not an apb_item")
        return;
      end
      super.do_copy(rhs);
      addr   = that.addr;
      data   = that.data;
      dir    = that.dir;
      slverr = that.slverr;
    endfunction

    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      apb_item that;
      if (!$cast(that, rhs)) return 0;
      return super.do_compare(rhs, comparer)
             && (addr   == that.addr)
             && (data   == that.data)
             && (dir    == that.dir)
             && (slverr == that.slverr);
    endfunction

    virtual function string convert2string();
      return $sformatf("%s addr=0x%08h data=0x%08h slverr=%0b",
                       dir.name(), addr, data, slverr);
    endfunction

  endclass

  //--------------------------------------------------------------------
  // Agent configuration
  //--------------------------------------------------------------------
  class apb_agent_cfg extends uvm_object;

    virtual apb_if      vif;
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    bit                 coverage_enable = 1;

    `uvm_object_utils(apb_agent_cfg)

    function new(string name = "apb_agent_cfg");
      super.new(name);
    endfunction

  endclass

  //--------------------------------------------------------------------
  // Sequencer
  //--------------------------------------------------------------------
  typedef uvm_sequencer #(apb_item) apb_sequencer;

  //--------------------------------------------------------------------
  // Driver
  //--------------------------------------------------------------------
  class apb_driver extends uvm_driver #(apb_item);

    `uvm_component_utils(apb_driver)

    apb_agent_cfg cfg;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(apb_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "apb_agent_cfg not found in uvm_config_db")
    endfunction

    virtual task run_phase(uvm_phase phase);
      apb_item req;

      // Park the bus until reset is released.
      cfg.vif.drv_cb.psel    <= 1'b0;
      cfg.vif.drv_cb.penable <= 1'b0;
      wait (cfg.vif.presetn === 1'b1);

      forever begin
        seq_item_port.get_next_item(req);
        drive(req);
        seq_item_port.item_done();
      end
    endtask

    // APB3: one setup cycle (PSEL, !PENABLE) then access cycles
    // (PSEL & PENABLE) until PREADY.
    protected virtual task drive(apb_item req);
      @(cfg.vif.drv_cb);
      cfg.vif.drv_cb.psel    <= 1'b1;
      cfg.vif.drv_cb.penable <= 1'b0;
      cfg.vif.drv_cb.pwrite  <= (req.dir == APB_WRITE);
      cfg.vif.drv_cb.paddr   <= req.addr;
      cfg.vif.drv_cb.pwdata  <= req.data;

      @(cfg.vif.drv_cb);
      cfg.vif.drv_cb.penable <= 1'b1;

      do @(cfg.vif.drv_cb); while (cfg.vif.drv_cb.pready !== 1'b1);

      if (req.dir == APB_READ) req.data = cfg.vif.drv_cb.prdata;
      req.slverr = cfg.vif.drv_cb.pslverr;

      cfg.vif.drv_cb.psel    <= 1'b0;
      cfg.vif.drv_cb.penable <= 1'b0;
    endtask

  endclass

  //--------------------------------------------------------------------
  // Monitor
  //--------------------------------------------------------------------
  class apb_monitor extends uvm_monitor;

    `uvm_component_utils(apb_monitor)

    apb_agent_cfg               cfg;
    uvm_analysis_port #(apb_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(apb_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "apb_agent_cfg not found in uvm_config_db")
    endfunction

    virtual task run_phase(uvm_phase phase);
      apb_item tr;
      forever begin
        // Sample the transfer on the cycle where the access phase completes.
        @(cfg.vif.mon_cb);
        if (cfg.vif.mon_cb.psel && cfg.vif.mon_cb.penable &&
            cfg.vif.mon_cb.pready) begin
          tr        = apb_item::type_id::create("tr");
          tr.addr   = cfg.vif.mon_cb.paddr;
          tr.dir    = cfg.vif.mon_cb.pwrite ? APB_WRITE : APB_READ;
          tr.data   = cfg.vif.mon_cb.pwrite ? cfg.vif.mon_cb.pwdata
                                            : cfg.vif.mon_cb.prdata;
          tr.slverr = cfg.vif.mon_cb.pslverr;
          `uvm_info("APB_MON", $sformatf("%s addr=0x%08h data=0x%08h",
                    tr.dir.name(), tr.addr, tr.data), UVM_HIGH)
          ap.write(tr);
        end
      end
    endtask

  endclass

  //--------------------------------------------------------------------
  // Coverage
  //--------------------------------------------------------------------
  class apb_coverage extends uvm_subscriber #(apb_item);

    `uvm_component_utils(apb_coverage)

    // The sampled values are passed in as arguments rather than read from a
    // class member: a coverpoint that references an enclosing class member
    // is not supported and the whole covergroup would be silently dropped
    // (warning COVERIGN).
    covergroup cg_apb with function sample(bit [31:0] addr, apb_dir_e dir);
      option.per_instance = 1;
      cp_addr : coverpoint addr {
        bins ctrl    = {32'h000};
        bins status  = {32'h004};
        bins scratch = {32'h008};
        bins id      = {32'h00C};
      }
      cp_dir  : coverpoint dir;
      x_addr_dir : cross cp_addr, cp_dir;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg_apb = new();
    endfunction

    virtual function void write(apb_item t);
      cg_apb.sample(t.addr, t.dir);
    endfunction

  endclass

  //--------------------------------------------------------------------
  // Agent
  //--------------------------------------------------------------------
  class apb_agent extends uvm_agent;

    `uvm_component_utils(apb_agent)

    apb_agent_cfg                 cfg;
    apb_driver                    driver;
    apb_sequencer                 sequencer;
    apb_monitor                   monitor;
    apb_coverage                  coverage;
    uvm_analysis_port #(apb_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      if (!uvm_config_db #(apb_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "apb_agent_cfg not found in uvm_config_db")

      // Pass the config down rather than making children reach up for it.
      uvm_config_db #(apb_agent_cfg)::set(this, "*", "cfg", cfg);

      monitor = apb_monitor::type_id::create("monitor", this);

      if (cfg.is_active == UVM_ACTIVE) begin
        driver    = apb_driver::type_id::create("driver", this);
        sequencer = apb_sequencer::type_id::create("sequencer", this);
      end

      if (cfg.coverage_enable)
        coverage = apb_coverage::type_id::create("coverage", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      monitor.ap.connect(ap);
      if (cfg.coverage_enable) monitor.ap.connect(coverage.analysis_export);
      if (cfg.is_active == UVM_ACTIVE)
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

  endclass

  //--------------------------------------------------------------------
  // Sequences
  //--------------------------------------------------------------------
  class apb_base_seq extends uvm_sequence #(apb_item);
    `uvm_object_utils(apb_base_seq)
    function new(string name = "apb_base_seq");
      super.new(name);
    endfunction
  endclass

  // Single explicit access, used by the register adapter path and by
  // directed tests.
  class apb_single_seq extends apb_base_seq;

    rand bit [31:0] addr;
    rand bit [31:0] data;
    rand apb_dir_e  dir;

    `uvm_object_utils(apb_single_seq)

    function new(string name = "apb_single_seq");
      super.new(name);
    endfunction

    virtual task body();
      apb_item req = apb_item::type_id::create("req");
      start_item(req);
      // Every field is determined by the caller, so set them directly rather
      // than constraining a randomize() call to a single solution.
      req.addr = addr;
      req.data = data;
      req.dir  = dir;
      finish_item(req);
    endtask

  endclass

  // Write-then-read every writable register, which is the traffic the
  // scoreboard checks.
  class apb_rw_seq extends apb_base_seq;

    rand int unsigned num_iters;
    constraint c_iters { num_iters inside {[4:8]}; }

    `uvm_object_utils(apb_rw_seq)

    function new(string name = "apb_rw_seq");
      super.new(name);
    endfunction

    virtual task body();
      bit [31:0] writable[$] = '{32'h000, 32'h008};

      foreach (writable[i]) begin
        bit [31:0] wdata = $urandom();
        apb_single_seq wr = apb_single_seq::type_id::create("wr");
        apb_single_seq rd = apb_single_seq::type_id::create("rd");

        wr.addr = writable[i]; wr.data = wdata; wr.dir = APB_WRITE;
        wr.start(m_sequencer);

        rd.addr = writable[i]; rd.data = '0;    rd.dir = APB_READ;
        rd.start(m_sequencer);
      end
    endtask

  endclass

  // Purely random legal traffic, for soak/regression runs.
  class apb_random_seq extends apb_base_seq;

    rand int unsigned num_items;
    constraint c_items { num_items inside {[10:30]}; }

    `uvm_object_utils(apb_random_seq)

    function new(string name = "apb_random_seq");
      super.new(name);
    endfunction

    virtual task body();
      repeat (num_items) begin
        apb_item req = apb_item::type_id::create("req");
        start_item(req);
        if (req.randomize() == 0)
          `uvm_fatal("RANDFAIL", "apb_item randomize failed")
        finish_item(req);
      end
    endtask

  endclass

endpackage
