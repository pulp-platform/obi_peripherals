// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

#include "Vtb_obi_uart_top_rx.h"
#include "verilated.h"

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);

  Vtb_obi_uart_top_rx tb;

  while (!Verilated::gotFinish()) {
    tb.clk = 0;
    tb.eval();

    tb.clk = 1;
    tb.eval();
  }

  tb.final();
  return 0;
}
