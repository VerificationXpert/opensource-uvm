package fifo_test_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import fifo_pkg::*;

  class fifo_base_test extends uvm_test;
    `uvm_component_utils(fifo_base_test)
    fifo_env env;
    fifo_cfg cfg;
    protected time drain_time = 100ns;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cfg = fifo_cfg::type_id::create("cfg");
      if (!uvm_config_db #(virtual fifo_if)::get(this, "", "vif", cfg.vif))
        `uvm_fatal("NOVIF", "virtual fifo_if not set")
      uvm_config_db #(fifo_cfg)::set(this, "env", "cfg", cfg);
      env = fifo_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
      phase.raise_objection(this, get_type_name());
      body();
      #(drain_time);
      phase.drop_objection(this, get_type_name());
    endtask

    virtual task body(); endtask
  endclass

  class fifo_smoke_test extends fifo_base_test;
    `uvm_component_utils(fifo_smoke_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    virtual task body();
      fifo_fill_drain_seq seq = fifo_fill_drain_seq::type_id::create("seq");
      if (seq.randomize() == 0) `uvm_fatal("RANDFAIL", "seq randomize failed")
      seq.start(env.agent.sequencer);
    endtask
  endclass

  class fifo_stress_test extends fifo_base_test;
    `uvm_component_utils(fifo_stress_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    virtual task body();
      repeat (5) begin
        fifo_fill_drain_seq seq = fifo_fill_drain_seq::type_id::create("seq");
        if (seq.randomize() == 0) `uvm_fatal("RANDFAIL", "seq randomize failed")
        seq.start(env.agent.sequencer);
      end
    endtask
  endclass
endpackage
