// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module tb_obi_uart_rx_line_status (
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

  int unsigned cycle_count;
  int unsigned step;
  int unsigned frame_bit;
  int unsigned bit_cycle;
  logic [9:0]   frame;
  int unsigned  received_count;
  logic         lsr_read_active;

  assign baud_rate_edge = 1'b0;

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

  function automatic logic [9:0] uart_8n1_frame(input logic [7:0] data);
    return {1'b1, data, 1'b0};
  endfunction

  task automatic start_frame(input logic [7:0] data);
    frame     <= uart_8n1_frame(data);
    frame_bit <= 0;
    bit_cycle <= 0;
    rxd       <= 1'b0;
  endtask

  task automatic drive_frame_bit();
    rxd <= frame[frame_bit];
    if (bit_cycle == 15) begin
      bit_cycle <= 0;
      if (frame_bit == 9) begin
        rxd <= 1'b1;
      end else begin
        frame_bit <= frame_bit + 1;
      end
    end else begin
      bit_cycle <= bit_cycle + 1;
    end
  endtask

  initial begin
    rst_n                = 1'b0;
    oversample_rate_edge = 1'b0;
    rxd                  = 1'b1;
    reg_read             = '0;
    reg_read.lcr.word_len = 2'b11;
    cycle_count          = 0;
    step                 = 0;
    frame_bit            = 0;
    bit_cycle            = 0;
    frame                = uart_8n1_frame(8'h00);
    received_count       = 0;
    lsr_read_active      = 1'b0;
  end

  always_ff @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    reg_read.obi_read_rhr <= 1'b0;
    if (!lsr_read_active) begin
      reg_read.obi_read_lsr <= 1'b0;
    end
    oversample_rate_edge <= rst_n;

    if (cycle_count == 8) begin
      rst_n <= 1'b1;
    end

    if (rst_n) begin
      unique case (step)
        0: begin
          start_frame(8'h33);
          step <= step + 1;
        end
        1: begin
          drive_frame_bit();
          if (reg_write.rhr_valid) begin
            assert (reg_write.rhr.char_rx == 8'h33)
              else $fatal(1, "First RX character %02x, expected 33", reg_write.rhr.char_rx);
            assert (reg_write.data_ready)
              else $fatal(1, "First RX did not set data ready");
            received_count <= received_count + 1;
            step <= step + 1;
          end
        end
        2: begin
          start_frame(8'hcc);
          // Hold LSR read active through completion of the next character.
          // The RHR overrun produced by that character must override the
          // read-clear value in the RX apply ordering.
          lsr_read_active <= 1'b1;
          reg_read.obi_read_lsr <= 1'b1;
          step <= step + 1;
        end
        3: begin
          drive_frame_bit();
          if (reg_write.rhr_valid) begin
            assert (reg_write.rhr.char_rx == 8'hcc)
              else $fatal(1, "Second RX character %02x, expected cc", reg_write.rhr.char_rx);
            assert (reg_write.overrun_valid && reg_write.overrun)
              else $fatal(1, "Second RX without RHR read did not report overrun");
            received_count <= received_count + 1;
            lsr_read_active <= 1'b0;
            reg_read.obi_read_lsr <= 1'b0;
            step <= step + 1;
          end
        end
        4: begin
          // A standalone LSR read emits valid zero clears for all four
          // LSR_BRK_ERROR_BITS.
          reg_read.obi_read_lsr <= 1'b1;
          step <= step + 1;
        end
        5: begin
          assert (reg_write.overrun_valid && !reg_write.overrun)
            else $fatal(1, "LSR read did not clear overrun");
          assert (reg_write.par_valid && !reg_write.par_err)
            else $fatal(1, "LSR read did not clear parity error");
          assert (reg_write.frame_valid && !reg_write.frame_err)
            else $fatal(1, "LSR read did not clear framing error");
          assert (reg_write.break_valid && !reg_write.break_ind)
            else $fatal(1, "LSR read did not clear break indication");
          reg_read.obi_read_rhr <= 1'b1;
          step <= step + 1;
        end
        6: begin
          assert (reg_write.rhr_valid && reg_write.rhr.char_rx == 8'h00)
            else $fatal(1, "RHR read did not clear the holding register");
          assert (reg_write.dr_valid && !reg_write.data_ready)
            else $fatal(1, "RHR read did not clear data ready");
          assert (received_count == 2)
            else $fatal(1, "Received count %0d, expected 2", received_count);
          $display("obi_uart RX line status smoke passed");
          $finish;
        end
        default: begin
          $fatal(1, "Unexpected RX line-status step %0d", step);
        end
      endcase
    end

    if (cycle_count == 1200) begin
      $fatal(1, "Timed out in RX line-status smoke at step %0d", step);
    end
  end
endmodule
