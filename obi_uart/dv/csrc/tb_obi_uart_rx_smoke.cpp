// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

#include "Vtb_obi_uart_rx_smoke.h"
#include "verilated.h"

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);

  Vtb_obi_uart_rx_smoke top;

  while (!Verilated::gotFinish()) {
    top.clk = 0;
    top.eval();
    top.clk = 1;
    top.eval();
  }

  top.final();
  return 0;
}
