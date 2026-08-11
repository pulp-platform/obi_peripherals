// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module tb_obi_uart_rx_fifo_deep (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       oversample_rate_edge,
  input  logic       baud_rate_edge,
  input  logic       rxd,
  input  logic       obi_read_rhr,
  input  logic       rx_fifo_rst,
  input  logic [1:0] rx_fifo_tl,
  output logic       trigger,
  output logic       timeout,
  output logic       rhr_valid,
  output logic [7:0] rhr,
  output logic       dr_valid,
  output logic       data_ready,
  output logic       overrun_valid,
  output logic       overrun,
  output logic       fifo_rst_valid,
  output logic       fifo_rst
);
  import obi_uart_pkg::*;

  reg_read_t     reg_read;
  rx_reg_write_t reg_write;

  assign reg_read = '{
    thr:           '0,
    ier:           '0,
    isr:           '0,
    fcr:           '{rx_fifo_tl: rx_fifo_tl, unused5: 1'b0, unused4: 1'b0,
                     unused3: 1'b0, tx_fifo_rst: 1'b0, rx_fifo_rst: rx_fifo_rst,
                     fifo_en: 1'b1},
    lcr:           '{dlab: 1'b0, set_break: 1'b0, force_par: 1'b0, even_par: 1'b0,
                     par_en: 1'b0, stop_bits: 1'b0, word_len: 2'b11},
    mcr:           '0,
    lsr:           '0,
    msr:           '0,
    dll:           '0,
    dlm:           '0,
    obi_read_rhr:  obi_read_rhr,
    obi_read_isr:  1'b0,
    obi_read_lsr:  1'b0,
    obi_read_msr:  1'b0,
    obi_write_thr: 1'b0,
    obi_write_dllm: 1'b0
  };

  obi_uart_rx i_dut (
    .clk_i                  (clk),
    .rst_ni                 (rst_n),
    .oversample_rate_edge_i (oversample_rate_edge),
    .baud_rate_edge_i       (baud_rate_edge),
    .rxd_i                  (rxd),
    .trigger_o              (trigger),
    .timeout_o              (timeout),
    .reg_read_i             (reg_read),
    .reg_write_o            (reg_write)
  );

  assign rhr_valid     = reg_write.rhr_valid;
  assign rhr           = reg_write.rhr.char_rx;
  assign dr_valid      = reg_write.dr_valid;
  assign data_ready    = reg_write.data_ready;
  assign overrun_valid = reg_write.overrun_valid;
  assign overrun       = reg_write.overrun;
  assign fifo_rst_valid = reg_write.fifo_rst_valid;
  assign fifo_rst       = reg_write.fifo_rst;
endmodule
