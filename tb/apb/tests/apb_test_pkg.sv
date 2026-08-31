//----------------------------------------------------------------------
// apb_test_pkg.sv - the test library.
//----------------------------------------------------------------------

package apb_test_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import apb_pkg::*;
  import apb_env_pkg::*;

  //--------------------------------------------------------------------
  // Base test: builds the environment and publishes the agent config.
  //--------------------------------------------------------------------
  class apb_base_test extends uvm_test;

    `uvm_component_utils(apb_base_test)

    apb_env       env;
    apb_agent_cfg cfg;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      cfg = apb_agent_cfg::type_id::create("cfg");
      if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", cfg.vif))
        `uvm_fatal("NOVIF", "virtual apb_if not set in uvm_config_db")

      uvm_config_db #(apb_agent_cfg)::set(this, "env", "cfg", cfg);
      env = apb_env::type_id::create("env", this);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      uvm_top.print_topology();
    endfunction

    // Objection handling lives here, once, rather than being repeated in
    // every test.  Tests override body() and never touch the objection,
    // which removes the commonest way to hang a UVM run.
    //
    // The trailing delay is the drain time: the monitor samples a transfer
    // on the clock edge that completes it, so without it the last transfer
    // of a sequence can be dropped when the run phase tears down.  It is
    // done here rather than through phase.get_objection().set_drain_time()
    // in start_of_simulation_phase, because get_objection() returns null for
    // a function phase and dereferencing it is fatal.
    virtual task run_phase(uvm_phase phase);
      phase.raise_objection(this, get_type_name());
      body();
      #(drain_time);
      phase.drop_objection(this, get_type_name());
    endtask

    // Overridden by each test. The base test drives no traffic, so a build
    // that only elaborates still runs cleanly.
    virtual task body();
    endtask

    protected time drain_time = 200ns;

  endclass

  //--------------------------------------------------------------------
  // Directed write/read over every writable register.
  //--------------------------------------------------------------------
  class apb_rw_test extends apb_base_test;

    `uvm_component_utils(apb_rw_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual task body();
      apb_rw_seq seq = apb_rw_seq::type_id::create("seq");
      seq.start(env.agent.sequencer);
    endtask

  endclass

  //--------------------------------------------------------------------
  // Constrained-random traffic.
  //--------------------------------------------------------------------
  class apb_random_test extends apb_base_test;

    `uvm_component_utils(apb_random_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual task body();
      apb_random_seq seq = apb_random_seq::type_id::create("seq");
      if (seq.randomize() == 0)
        `uvm_fatal("RANDFAIL", "apb_random_seq randomize failed")
      seq.start(env.agent.sequencer);
    endtask

  endclass

  //--------------------------------------------------------------------
  // Register-model test: frontdoor access through the APB map.
  //--------------------------------------------------------------------
  class apb_reg_test extends apb_base_test;

    `uvm_component_utils(apb_reg_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual task body();
      uvm_status_e status;
      uvm_reg_data_t rdata;

      env.regmodel.scratch.write(status, 64'hCAFE_BABE, UVM_FRONTDOOR);
      if (status != UVM_IS_OK)
        `uvm_error("REG", "frontdoor write to scratch failed")

      env.regmodel.scratch.read(status, rdata, UVM_FRONTDOOR);
      if (status != UVM_IS_OK)
        `uvm_error("REG", "frontdoor read of scratch failed")
      else if (rdata != 64'hCAFE_BABE)
        `uvm_error("REG", $sformatf(
          "scratch frontdoor readback: expected 0xCAFEBABE, got 0x%08h", rdata))
      else
        `uvm_info("REG", "frontdoor write/read of scratch: OK", UVM_LOW)
    endtask

  endclass

  //--------------------------------------------------------------------
  // Backdoor test.
  //
  // This is the test that only passes because of the Verilator VPI backend
  // in lib/dpi/uvm_hdl_verilator.c.  Built with +define+UVM_NO_DPI (or
  // against upstream uvm_hdl.c, which has no Verilator backend at all) the
  // backdoor accesses below cannot work.
  //--------------------------------------------------------------------
  class apb_backdoor_test extends apb_base_test;

    `uvm_component_utils(apb_backdoor_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual task body();
      uvm_status_e   status;
      uvm_reg_data_t rdata;

      // 1. Frontdoor write, backdoor read: proves the backdoor path resolves
      //    the HDL name and observes what the bus actually wrote.
      env.regmodel.scratch.write(status, 64'h1234_5678, UVM_FRONTDOOR);
      if (status != UVM_IS_OK)
        `uvm_error("BKDR", "frontdoor write to scratch failed")

      env.regmodel.scratch.read(status, rdata, UVM_BACKDOOR);
      if (status != UVM_IS_OK)
        `uvm_error("BKDR", "backdoor read of scratch failed - is the signal public to VPI?")
      else if (rdata != 64'h1234_5678)
        `uvm_error("BKDR", $sformatf(
          "backdoor read: expected 0x12345678, got 0x%08h", rdata))
      else
        `uvm_info("BKDR", "frontdoor write / backdoor read: OK", UVM_LOW)

      // 2. Backdoor write (deposit), frontdoor read: proves the deposit
      //    actually reached the RTL register.
      env.regmodel.scratch.write(status, 64'hDEAD_BEEF, UVM_BACKDOOR);
      if (status != UVM_IS_OK)
        `uvm_error("BKDR", "backdoor write to scratch failed")

      // The deposit produced no bus traffic, so the scoreboard's reference
      // model has not seen it and would flag the frontdoor read below as a
      // mismatch. Tell it what happened.
      env.scoreboard.predict_write(32'h008, 32'hDEAD_BEEF);

      env.regmodel.scratch.read(status, rdata, UVM_FRONTDOOR);
      if (status != UVM_IS_OK)
        `uvm_error("BKDR", "frontdoor read of scratch failed")
      else if (rdata != 64'hDEAD_BEEF)
        `uvm_error("BKDR", $sformatf(
          "frontdoor readback after backdoor write: expected 0xDEADBEEF, got 0x%08h",
          rdata))
      else
        `uvm_info("BKDR", "backdoor write / frontdoor read: OK", UVM_LOW)
    endtask

  endclass

endpackage
