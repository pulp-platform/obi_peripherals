# Copyright 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

yosys plugin -i slang.so
yosys read_slang --top $::env(TOP_DESIGN) -f $::env(FLIST)
yosys hierarchy -check -top $::env(TOP_DESIGN)
yosys proc
yosys check -assert
yosys tee -q -o "$::env(OUT_DIR)/elaborated.rpt" stat
yosys write_verilog -norename -noexpr "$::env(OUT_DIR)/elaborated.v"
