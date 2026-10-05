#!/bin/bash
verilator --binary --timing -j 0 --top-module tb_top -Wno-fatal -Wno-lint -Wno-style +define+UVM_NO_DPI +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv counter.v tb.sv && ./obj_dir/Vtb_top
