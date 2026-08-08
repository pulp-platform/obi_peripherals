// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

#include "Vtb_obi_uart_interrupts.h"
#include "verilated.h"

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);

  Vtb_obi_uart_interrupts tb;
  vluint64_t time = 0;

  while (!Verilated::gotFinish()) {
    tb.clk = 0;
    tb.eval();
    time++;

    tb.clk = 1;
    tb.eval();
    time++;
  }

  tb.final();
  return 0;
}
