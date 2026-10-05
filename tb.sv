`include "uvm_macros.svh"
import uvm_pkg::*;

interface counter_if(input logic clk);
  logic rst_n;
  logic en;
  logic [7:0] count;
endinterface


class my_item extends uvm_sequence_item;
  rand bit rst_n;
  rand bit en;
  bit [7:0] count;

  constraint rst_c { rst_n dist {1 := 9, 0 := 1}; }

  `uvm_object_utils(my_item)

  function new(string name = "my_item");
    super.new(name);
  endfunction
endclass


class my_sequence extends uvm_sequence #(my_item);
  `uvm_object_utils(my_sequence)

  function new(string name = "my_sequence");
    super.new(name);
  endfunction

  task body();
    my_item item;

    repeat (2) begin
      item = my_item::type_id::create("item");
      start_item(item);
      item.rst_n = 0;
      item.en = 0;
      finish_item(item);
    end

    repeat (500) begin
      item = my_item::type_id::create("item");
      start_item(item);
      item.randomize();
      finish_item(item);
    end
  endtask
endclass


class my_driver extends uvm_driver #(my_item);
  `uvm_component_utils(my_driver)

  virtual counter_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual counter_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "could not get vif")
  endfunction

  task run_phase(uvm_phase phase);
    vif.rst_n <= 0;
    vif.en <= 0;
    forever begin
      seq_item_port.get_next_item(req);
      @(posedge vif.clk);
      vif.rst_n <= req.rst_n;
      vif.en <= req.en;
      seq_item_port.item_done();
    end
  endtask
endclass


class my_monitor extends uvm_monitor;
  `uvm_component_utils(my_monitor)

  virtual counter_if vif;
  uvm_analysis_port #(my_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual counter_if)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "could not get vif")
  endfunction

  task run_phase(uvm_phase phase);
    my_item item;
    forever begin
      @(posedge vif.clk);
      item = my_item::type_id::create("item");
      item.rst_n = vif.rst_n;
      item.en = vif.en;
      item.count = vif.count;
      ap.write(item);
    end
  endtask
endclass


class my_agent extends uvm_agent;
  `uvm_component_utils(my_agent)

  uvm_sequencer #(my_item) sqr;
  my_driver drv;
  my_monitor mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sqr = uvm_sequencer#(my_item)::type_id::create("sqr", this);
    drv = my_driver::type_id::create("drv", this);
    mon = my_monitor::type_id::create("mon", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass


class my_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(my_scoreboard)

  uvm_analysis_imp #(my_item, my_scoreboard) imp;

  my_item prev;
  int reset_pass = 0;
  int inc_pass = 0;
  int hold_pass = 0;
  int errors = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    imp = new("imp", this);
  endfunction

  function void write(my_item cur);
    bit [7:0] expected;

    if (prev != null) begin
      if (prev.rst_n == 0) begin
        if (cur.count == 0)
          reset_pass++;
        else begin
          errors++;
          `uvm_error("SB", $sformatf("reset failed, count = %0d", cur.count))
        end
      end
      else if (prev.en == 1) begin
        expected = prev.count + 1;
        if (cur.count == expected)
          inc_pass++;
        else begin
          errors++;
          `uvm_error("SB", $sformatf("increment failed, expected %0d got %0d", expected, cur.count))
        end
      end
      else begin
        if (cur.count == prev.count)
          hold_pass++;
        else begin
          errors++;
          `uvm_error("SB", $sformatf("hold failed, prev %0d now %0d", prev.count, cur.count))
        end
      end
    end

    prev = cur;
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

  my_agent agent;
  my_scoreboard sb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = my_agent::type_id::create("agent", this);
    sb = my_scoreboard::type_id::create("sb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    agent.mon.ap.connect(sb.imp);
  endfunction
endclass


class my_test extends uvm_test;
  `uvm_component_utils(my_test)

  my_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = my_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    my_sequence seq;
    seq = my_sequence::type_id::create("seq");

    phase.raise_objection(this);
    seq.start(env.agent.sqr);
    repeat (5) @(posedge env.agent.drv.vif.clk);
    phase.drop_objection(this);
  endtask
endclass


module tb_top;
  logic clk = 0;
  always #5 clk = ~clk;

  counter_if vif(clk);

  counter dut (
    .clk(clk),
    .rst_n(vif.rst_n),
    .en(vif.en),
    .count(vif.count)
  );

  initial begin
    uvm_config_db#(virtual counter_if)::set(null, "*", "vif", vif);
    run_test("my_test");
  end
endmodule
