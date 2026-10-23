`include "uvm_macros.svh"
import uvm_pkg::*;

interface counter_if(input logic clk);
  logic rst_n;
  logic en;
  logic [7:0] count;

  modport dut_mp (input clk, rst_n, en, output count);
  modport drv_mp (input clk, count, output rst_n, en);
  modport mon_mp (input clk, rst_n, en, count);
endinterface


typedef struct {
  bit rst_n;
  bit en;
  bit [7:0] count;
} sample_t;


class my_item extends uvm_sequence_item;
  rand int num_txns;
  rand int num_resets;
  rand int reset_gap;
  rand int en_percent;

  constraint num_c { num_txns == 500; }
  constraint reset_c { num_resets inside {[3:6]}; reset_gap inside {[40:80]}; }
  constraint en_c { en_percent inside {[50:90]}; }

  `uvm_object_utils(my_item)

  function new(string name = "my_item");
    super.new(name);
  endfunction
endclass


class my_sample extends uvm_object;
  bit rst_n;
  bit en;
  bit [7:0] count;

  `uvm_object_utils(my_sample)

  function new(string name = "my_sample");
    super.new(name);
  endfunction
endclass


class my_sequence extends uvm_sequence #(my_item);
  `uvm_object_utils(my_sequence)

  function new(string name = "my_sequence");
    super.new(name);
  endfunction

  task body();
    my_item item_h;
    item_h = my_item::type_id::create("item_h");
    start_item(item_h);
    if (!item_h.randomize())
      `uvm_error("SEQ", "randomize failed")
    finish_item(item_h);
  endtask
endclass


class my_driver extends uvm_driver #(my_item);
  `uvm_component_utils(my_driver)

  virtual counter_if.drv_mp vif_h;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual counter_if.drv_mp)::get(this, "", "vif_h", vif_h))
      `uvm_fatal("DRV", "could not get vif_h")
  endfunction

  task run_phase(uvm_phase phase);
    vif_h.rst_n <= 0;
    vif_h.en <= 0;
    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  task drive_item(my_item item_h);
    int resets_done;
    resets_done = 0;

    repeat (2) @(posedge vif_h.clk);

    for (int i = 1; i <= item_h.num_txns; i++) begin
      @(posedge vif_h.clk);
      if (resets_done < item_h.num_resets && i % item_h.reset_gap == 0) begin
        vif_h.rst_n <= 0;
        resets_done++;
      end
      else begin
        vif_h.rst_n <= 1;
      end
      vif_h.en <= ($urandom_range(99) < item_h.en_percent);
    end
  endtask
endclass


class my_monitor extends uvm_monitor;
  `uvm_component_utils(my_monitor)

  virtual counter_if.mon_mp vif_h;
  uvm_analysis_port #(my_sample) ap_h;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap_h = new("ap_h", this);
    if (!uvm_config_db#(virtual counter_if.mon_mp)::get(this, "", "vif_h", vif_h))
      `uvm_fatal("MON", "could not get vif_h")
  endfunction

  task run_phase(uvm_phase phase);
    my_sample sample_h;
    forever begin
      @(posedge vif_h.clk);
      sample_h = my_sample::type_id::create("sample_h");
      sample_h.rst_n = vif_h.rst_n;
      sample_h.en = vif_h.en;
      sample_h.count = vif_h.count;
      ap_h.write(sample_h);
    end
  endtask
endclass


class my_agent extends uvm_agent;
  `uvm_component_utils(my_agent)

  uvm_sequencer #(my_item) sequencer_h;
  my_driver driver_h;
  my_monitor monitor_h;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    monitor_h = my_monitor::type_id::create("monitor_h", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sequencer_h = uvm_sequencer#(my_item)::type_id::create("sequencer_h", this);
      driver_h = my_driver::type_id::create("driver_h", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE)
      driver_h.seq_item_port.connect(sequencer_h.seq_item_export);
  endfunction
endclass


class my_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(my_scoreboard)

  uvm_analysis_imp #(my_sample, my_scoreboard) imp_h;

  sample_t prev_s;
  bit have_prev;
  int reset_pass = 0;
  int inc_pass = 0;
  int hold_pass = 0;
  int errors = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    imp_h = new("imp_h", this);
  endfunction

  function void write(my_sample cur_h);
    bit [7:0] expected;

    if (have_prev) begin
      if (prev_s.rst_n == 0) begin
        if (cur_h.count == 0)
          reset_pass++;
        else begin
          errors++;
          `uvm_error("SB", $sformatf("reset failed, count = %0d", cur_h.count))
        end
      end
      else if (prev_s.en == 1) begin
        expected = prev_s.count + 1;
        if (cur_h.count == expected)
          inc_pass++;
        else begin
          errors++;
          `uvm_error("SB", $sformatf("increment failed, expected %0d got %0d", expected, cur_h.count))
        end
      end
      else begin
        if (cur_h.count == prev_s.count)
          hold_pass++;
        else begin
          errors++;
          `uvm_error("SB", $sformatf("hold failed, prev %0d now %0d", prev_s.count, cur_h.count))
        end
      end
    end

    prev_s.rst_n = cur_h.rst_n;
    prev_s.en = cur_h.en;
    prev_s.count = cur_h.count;
    have_prev = 1;
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SB", $sformatf("reset_pass=%0d inc_pass=%0d hold_pass=%0d errors=%0d", reset_pass, inc_pass, hold_pass, errors), UVM_NONE)
    if (errors == 0)
      `uvm_info("SB", "TEST PASSED", UVM_NONE)
    else
      `uvm_info("SB", "TEST FAILED", UVM_NONE)
  endfunction
endclass


class my_env extends uvm_env;
  `uvm_component_utils(my_env)

  my_agent agent_h;
  my_scoreboard sb_h;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent_h = my_agent::type_id::create("agent_h", this);
    sb_h = my_scoreboard::type_id::create("sb_h", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    agent_h.monitor_h.ap_h.connect(sb_h.imp_h);
  endfunction
endclass


class my_test extends uvm_test;
  `uvm_component_utils(my_test)

  my_env env_h;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env_h = my_env::type_id::create("env_h", this);
  endfunction

  task run_phase(uvm_phase phase);
    my_sequence seq_h;
    seq_h = my_sequence::type_id::create("seq_h");

    phase.get_objection().set_drain_time(this, 50);

    phase.raise_objection(this);
    seq_h.start(env_h.agent_h.sequencer_h);
    phase.drop_objection(this);
  endtask
endclass


module tb_top;
  logic clk = 0;
  always #5 clk = ~clk;

  counter_if vif(clk);

  counter dut (
    .clk(vif.clk),
    .rst_n(vif.rst_n),
    .en(vif.en),
    .count(vif.count)
  );

  initial begin
    uvm_config_db#(virtual counter_if.drv_mp)::set(null, "*", "vif_h", vif.drv_mp);
    uvm_config_db#(virtual counter_if.mon_mp)::set(null, "*", "vif_h", vif.mon_mp);
    run_test("my_test");
  end
endmodule
