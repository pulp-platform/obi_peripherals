// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module tb_obi_uart_rx_smoke (
  input logic clk
);
  import obi_uart_pkg::*;

  logic rst_n;
  logic oversample_rate_edge;
  logic baud_rate_edge;
  logic rxd;
  logic trigger;
  logic timeout;

  reg_read_t     reg_read;
  rx_reg_write_t reg_write;

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

  logic [9:0] frame;
  int unsigned cycle_count;
  int unsigned frame_bit;
  int unsigned bit_cycle;
  bit          sent_frame;

  assign baud_rate_edge = 1'b0;

  initial begin
    rst_n                = 1'b0;
    oversample_rate_edge = 1'b0;
    rxd                  = 1'b1;
    reg_read             = '0;
    reg_read.lcr.word_len = 2'b11;
    frame                = {1'b1, 8'h55, 1'b0};
    cycle_count          = 0;
    frame_bit            = 0;
    bit_cycle            = 0;
    sent_frame           = 1'b0;
  end

  always_ff @(posedge clk) begin
    cycle_count <= cycle_count + 1;

    if (cycle_count == 8) begin
      rst_n <= 1'b1;
    end

    oversample_rate_edge <= rst_n;

    if (rst_n && !sent_frame) begin
      rxd <= frame[frame_bit];
      if (bit_cycle == 15) begin
        bit_cycle <= 0;
        if (frame_bit == 9) begin
          sent_frame <= 1'b1;
          rxd        <= 1'b1;
        end else begin
          frame_bit <= frame_bit + 1;
        end
      end else begin
        bit_cycle <= bit_cycle + 1;
      end
    end

    if (rst_n) begin
      if (reg_write.rhr_valid) begin
        assert (reg_write.rhr.char_rx == 8'h55)
          else $fatal(1, "Received %02x, expected 55", reg_write.rhr.char_rx);
        assert (reg_write.data_ready)
          else $fatal(1, "Data ready was not asserted with received character");
        $display("obi_uart RX smoke passed");
        $finish;
      end
    end

    if (cycle_count == 260) begin
      $fatal(1, "Timed out waiting for RX character");
    end
  end
endmodule
