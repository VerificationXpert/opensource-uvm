//----------------------------------------------------------------------
// apb_env_pkg.sv
//
// Register model, register adapter, scoreboard and environment.
//
// The register block declares an hdl_path for each register, which is what
// the UVM backdoor resolves through uvm_hdl_read / uvm_hdl_deposit.  Those
// land in lib/dpi/uvm_hdl_verilator.c, since upstream UVM ships no backend
// for this simulator at all and the path is otherwise unavailable in
// open-source flows.
//----------------------------------------------------------------------

package apb_env_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import apb_pkg::*;

  //--------------------------------------------------------------------
  // Register model
  //--------------------------------------------------------------------
  class reg_ctrl extends uvm_reg;
    rand uvm_reg_field value;
    `uvm_object_utils(reg_ctrl)

    function new(string name = "reg_ctrl");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      value = uvm_reg_field::type_id::create("value");
      value.configure(this, 32, 0, "RW", 0, 64'h0, 1, 1, 1);
    endfunction
  endclass

  class reg_status extends uvm_reg;
    rand uvm_reg_field value;
    `uvm_object_utils(reg_status)

    function new(string name = "reg_status");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      value = uvm_reg_field::type_id::create("value");
      value.configure(this, 32, 0, "RO", 0, 64'h0, 1, 0, 1);
    endfunction
  endclass

  class reg_scratch extends uvm_reg;
    rand uvm_reg_field value;
    `uvm_object_utils(reg_scratch)

    function new(string name = "reg_scratch");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      value = uvm_reg_field::type_id::create("value");
      value.configure(this, 32, 0, "RW", 0, 64'h0, 1, 1, 1);
    endfunction
  endclass

  class apb_reg_block extends uvm_reg_block;

    rand reg_ctrl    ctrl;
    rand reg_status  status;
    rand reg_scratch scratch;

    uvm_reg_map apb_map;

    `uvm_object_utils(apb_reg_block)

    function new(string name = "apb_reg_block");
      super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      apb_map = create_map("apb_map", 0, 4, UVM_LITTLE_ENDIAN, 1);

      ctrl = reg_ctrl::type_id::create("ctrl");
      ctrl.configure(this, null, "ctrl_q");
      ctrl.build();
      apb_map.add_reg(ctrl, 64'h000, "RW");

      status = reg_status::type_id::create("status");
      status.configure(this, null, "status_q");
      status.build();
      apb_map.add_reg(status, 64'h004, "RO");

      scratch = reg_scratch::type_id::create("scratch");
      scratch.configure(this, null, "scratch_q");
      scratch.build();
      apb_map.add_reg(scratch, 64'h008, "RW");

      // Root of the backdoor paths.  Combined with the per-register
      // hdl_path above this resolves to e.g.
      //   apb_tb_top.dut.scratch_q
      // which is exactly the string handed to vpi_handle_by_name.
      add_hdl_path("apb_tb_top.dut");

      lock_model();
    endfunction

  endclass

  //--------------------------------------------------------------------
  // Register adapter - turns uvm_reg_bus_op into apb_item and back.
  //--------------------------------------------------------------------
  class apb_reg_adapter extends uvm_reg_adapter;

    `uvm_object_utils(apb_reg_adapter)

    function new(string name = "apb_reg_adapter");
      super.new(name);
      supports_byte_enable = 0;
      provides_responses   = 0;
    endfunction

    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
      apb_item item = apb_item::type_id::create("item");
      item.dir  = (rw.kind == UVM_WRITE) ? APB_WRITE : APB_READ;
      // uvm_reg_bus_op is 64-bit; this bus is 32-bit. Narrow explicitly.
      item.addr = 32'(rw.addr);
      item.data = 32'(rw.data);
      return item;
    endfunction

    virtual function void bus2reg(uvm_sequence_item bus_item,
                                  ref uvm_reg_bus_op rw);
      apb_item item;
      if (!$cast(item, bus_item)) begin
        `uvm_fatal("BUS2REG", "bus_item is not an apb_item")
        return;
      end
      rw.kind   = (item.dir == APB_WRITE) ? UVM_WRITE : UVM_READ;
      rw.addr   = uvm_reg_addr_t'(item.addr);
      rw.data   = uvm_reg_data_t'(item.data);
      rw.status = item.slverr ? UVM_NOT_OK : UVM_IS_OK;
    endfunction

  endclass

  //--------------------------------------------------------------------
  // Scoreboard
  //
  // Keeps a reference model of the writable registers and checks every read
  // against it.  STATUS and ID are checked against their derivation from
  // CTRL and the hard-coded ID respectively.
  //--------------------------------------------------------------------
  class apb_scoreboard extends uvm_component;

    `uvm_component_utils(apb_scoreboard)

    uvm_analysis_imp #(apb_item, apb_scoreboard) ap_imp;

    protected bit [31:0] m_ctrl;
    protected bit [31:0] m_scratch;
    protected int        m_checks;
    protected int        m_errors;

    static const bit [31:0] ID_VALUE = 32'h0BADC0DE;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap_imp = new("ap_imp", this);
    endfunction

    virtual function void write(apb_item t);
      if (t.dir == APB_WRITE) begin
        case (t.addr)
          32'h000: m_ctrl    = t.data;
          32'h008: m_scratch = t.data;
          default: ;  // STATUS and ID discard writes
        endcase
      end else begin
        bit [31:0] expected;
        case (t.addr)
          32'h000: expected = m_ctrl;
          32'h004: expected = {28'd0, m_ctrl[3:0]};
          32'h008: expected = m_scratch;
          32'h00C: expected = ID_VALUE;
          default: return;
        endcase

        m_checks++;
        if (t.data !== expected) begin
          m_errors++;
          `uvm_error("SCBD", $sformatf(
            "read mismatch at 0x%08h: expected 0x%08h, got 0x%08h",
            t.addr, expected, t.data))
        end else begin
          `uvm_info("SCBD", $sformatf("read match at 0x%08h = 0x%08h",
                    t.addr, t.data), UVM_HIGH)
        end
      end
    endfunction

    // A backdoor access changes the DUT's state without producing any bus
    // traffic, so the monitor never sees it and this reference model would
    // drift.  Any environment that mixes frontdoor and backdoor access needs
    // a way to resynchronise; this is it, and apb_backdoor_test calls it.
    virtual function void predict_write(bit [31:0] addr, bit [31:0] data);
      case (addr)
        32'h000: m_ctrl    = data;
        32'h008: m_scratch = data;
        default:
          `uvm_warning("SCBD", $sformatf(
            "predict_write for non-writable address 0x%08h ignored", addr))
      endcase
      `uvm_info("SCBD", $sformatf("backdoor write predicted at 0x%08h = 0x%08h",
                addr, data), UVM_HIGH)
    endfunction

    virtual function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      if (m_checks == 0)
        `uvm_error("SCBD", "no read transactions were checked")
      else
        `uvm_info("SCBD", $sformatf("%0d reads checked, %0d mismatches",
                  m_checks, m_errors), UVM_LOW)
    endfunction

  endclass

  //--------------------------------------------------------------------
  // Environment
  //--------------------------------------------------------------------
  class apb_env extends uvm_env;

    `uvm_component_utils(apb_env)

    apb_agent_cfg   cfg;
    apb_agent       agent;
    apb_scoreboard  scoreboard;
    apb_reg_block   regmodel;
    apb_reg_adapter adapter;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      if (!uvm_config_db #(apb_agent_cfg)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "apb_agent_cfg not found in uvm_config_db")

      uvm_config_db #(apb_agent_cfg)::set(this, "agent", "cfg", cfg);

      agent      = apb_agent::type_id::create("agent", this);
      scoreboard = apb_scoreboard::type_id::create("scoreboard", this);

      regmodel = apb_reg_block::type_id::create("regmodel");
      regmodel.build();
      adapter = apb_reg_adapter::type_id::create("adapter");
    endfunction

    virtual function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.ap.connect(scoreboard.ap_imp);

      if (cfg.is_active == UVM_ACTIVE) begin
        regmodel.apb_map.set_sequencer(agent.sequencer, adapter);
        // The monitor already feeds the scoreboard; letting the register
        // model auto-predict from the same traffic keeps its mirror in step
        // without a second predictor component.
        regmodel.apb_map.set_auto_predict(1);
      end
    endfunction

  endclass

endpackage
