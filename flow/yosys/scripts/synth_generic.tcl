# Copyright 2026 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

yosys plugin -i slang.so
yosys read_slang --top $::env(TOP_DESIGN) -f $::env(FLIST)
yosys hierarchy -top $::env(TOP_DESIGN)
yosys proc
yosys check
yosys opt
yosys fsm
yosys opt
yosys memory -nomap
yosys memory_map
yosys opt -fast
yosys check
yosys tee -q -o "$::env(OUT_DIR)/synth_generic.rpt" stat
yosys write_verilog -norename -noexpr "$::env(OUT_DIR)/synth_generic.v"
