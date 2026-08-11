// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

#include "Vtb_obi_uart_rx_fifo_deep.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>

namespace {

struct RxModel {
  bool data_ready = false;
  bool overrun = false;
  uint8_t rhr = 0;
};

void fail(const char *msg) {
  std::fprintf(stderr, "%s\n", msg);
  std::exit(1);
}

void eval_cycle(Vtb_obi_uart_rx_fifo_deep &tb, RxModel &model) {
  tb.clk = 0;
  tb.eval();

  tb.clk = 1;
  tb.eval();

  if (tb.rst_n) {
    if (tb.rhr_valid) {
      model.rhr = tb.rhr;
    }
    if (tb.dr_valid) {
      model.data_ready = tb.data_ready;
    }
    if (tb.overrun_valid) {
      model.overrun = tb.overrun;
    }
  } else {
    model = {};
  }
}

void wait_cycles(Vtb_obi_uart_rx_fifo_deep &tb, RxModel &model, int cycles) {
  for (int i = 0; i < cycles; ++i) {
    eval_cycle(tb, model);
  }
}

void reset_dut(Vtb_obi_uart_rx_fifo_deep &tb, RxModel &model) {
  tb.rst_n = 0;
  tb.oversample_rate_edge = 0;
  tb.baud_rate_edge = 0;
  tb.rxd = 1;
  tb.obi_read_rhr = 0;
  tb.rx_fifo_rst = 0;
  tb.rx_fifo_tl = 0;
  wait_cycles(tb, model, 5);

  tb.rst_n = 1;
  tb.oversample_rate_edge = 1;
  wait_cycles(tb, model, 5);
}

void send_8n1(Vtb_obi_uart_rx_fifo_deep &tb, RxModel &model, uint8_t data) {
  const uint16_t frame = static_cast<uint16_t>((1u << 9) | (static_cast<uint16_t>(data) << 1));
  for (int bit = 0; bit < 10; ++bit) {
    tb.rxd = (frame >> bit) & 1u;
    wait_cycles(tb, model, 16);
  }
  tb.rxd = 1;
  wait_cycles(tb, model, 2);
}

void read_rhr(Vtb_obi_uart_rx_fifo_deep &tb, RxModel &model) {
  tb.obi_read_rhr = 1;
  wait_cycles(tb, model, 1);
  tb.obi_read_rhr = 0;
  wait_cycles(tb, model, 1);
}

void wait_rhr(Vtb_obi_uart_rx_fifo_deep &tb, RxModel &model, uint8_t expected) {
  for (int poll = 0; poll < 40; ++poll) {
    wait_cycles(tb, model, 1);
    if (model.data_ready && model.rhr == expected) {
      return;
    }
  }
  std::fprintf(stderr, "RHR did not present expected byte 0x%02x, got ready=%d byte=0x%02x\n",
               expected, model.data_ready, model.rhr);
  std::exit(1);
}

void drain_bytes(Vtb_obi_uart_rx_fifo_deep &tb, RxModel &model, uint8_t first, int count) {
  for (int idx = 0; idx < count; ++idx) {
    wait_rhr(tb, model, static_cast<uint8_t>(first + idx));
    read_rhr(tb, model);
  }
  wait_cycles(tb, model, 4);
  if (model.data_ready) {
    fail("RX FIFO still reports data ready after draining expected bytes");
  }
}

void clear_rx_fifo(Vtb_obi_uart_rx_fifo_deep &tb, RxModel &model) {
  tb.rx_fifo_rst = 1;
  wait_cycles(tb, model, 1);
  if (!tb.fifo_rst_valid || tb.fifo_rst) {
    fail("RX FIFO reset did not request FCR reset-bit clear");
  }
  if (!tb.rhr_valid || tb.rhr != 0 || !tb.dr_valid || tb.data_ready || model.data_ready) {
    fail("RX FIFO reset did not clear the prefetched RHR and data-ready state");
  }
  tb.rx_fifo_rst = 0;
  wait_cycles(tb, model, 2);
}

void check_trigger_level(Vtb_obi_uart_rx_fifo_deep &tb, RxModel &model, uint8_t trigger_sel,
                         int fifo_threshold, uint8_t first_byte) {
  tb.rx_fifo_tl = trigger_sel;
  wait_cycles(tb, model, 2);

  for (int idx = 0; idx < fifo_threshold; ++idx) {
    send_8n1(tb, model, static_cast<uint8_t>(first_byte + idx));
    const bool threshold_reached = (idx + 1) >= fifo_threshold;
    if (tb.trigger != threshold_reached) {
      std::fprintf(stderr,
                   "RX FIFO trigger level %d %s on total byte %d\n",
                   fifo_threshold, threshold_reached ? "did not assert" : "asserted early",
                   idx + 1);
      std::exit(1);
    }
  }

  // Trigger level 1 is a level interrupt: it remains asserted while the
  // prefetched RHR byte is still unread.
  if (fifo_threshold == 1 && !tb.trigger) {
    fail("RX FIFO trigger level 1 did not persist for the prefetched RHR byte");
  }

  drain_bytes(tb, model, first_byte, fifo_threshold);
}

void check_fifo_reset(Vtb_obi_uart_rx_fifo_deep &tb, RxModel &model, uint8_t first_byte) {
  send_8n1(tb, model, first_byte);
  send_8n1(tb, model, static_cast<uint8_t>(first_byte + 1));
  wait_rhr(tb, model, first_byte);
  clear_rx_fifo(tb, model);
  if (model.data_ready || model.rhr != 0) {
    fail("RX FIFO reset did not leave the RHR/FIFO empty");
  }
}

void check_fifo_overrun(Vtb_obi_uart_rx_fifo_deep &tb, RxModel &model, uint8_t first_byte) {
  for (int idx = 0; idx < 16; ++idx) {
    send_8n1(tb, model, static_cast<uint8_t>(first_byte + idx));
    if (model.overrun) {
      fail("RX FIFO overrun asserted before the 17th received byte");
    }
  }

  send_8n1(tb, model, static_cast<uint8_t>(first_byte + 16));
  wait_cycles(tb, model, 4);
  if (!model.overrun) {
    fail("RX FIFO overrun did not assert on the 17th received byte");
  }

  drain_bytes(tb, model, first_byte, 16);
}

} // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);

  Vtb_obi_uart_rx_fifo_deep tb;
  RxModel model;

  reset_dut(tb, model);

  // The 16550 receiver FIFO exposes 16 bytes total, including the prefetched RHR byte.
  check_trigger_level(tb, model, 0, 1, 0x10);
  check_trigger_level(tb, model, 1, 4, 0x20);
  check_trigger_level(tb, model, 2, 8, 0x30);
  check_trigger_level(tb, model, 3, 14, 0x40);

  check_fifo_reset(tb, model, 0x70);
  check_fifo_overrun(tb, model, 0x80);

  std::puts("obi_uart RX FIFO deep behavior passed");
  tb.final();
  return 0;
}
