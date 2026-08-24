# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

yosys plugin -i slang.so
yosys read_slang --top $::env(TOP_DESIGN) -f $::env(FLIST)
yosys synth -top $::env(TOP_DESIGN) -run begin:fine
yosys check -assert
yosys tee -q -o "$::env(OUT_DIR)/synth_generic.rpt" stat
yosys write_verilog -norename -noexpr "$::env(OUT_DIR)/synth_generic.v"
