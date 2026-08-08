// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module tb_obi_uart_rx_fifo (
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
  int unsigned sent_count;
  int unsigned rhr_valid_count;
  int unsigned baud_pulse_count;
  logic [9:0]   frame;
  logic [7:0]   next_data;

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

  task automatic start_frame(input logic [7:0] data);
    frame     <= {1'b1, data, 1'b0};
    frame_bit <= 0;
    bit_cycle <= 0;
    rxd       <= 1'b0;
  endtask

  task automatic drive_frame_bit(output logic done);
    done = 1'b0;
    rxd <= frame[frame_bit];
    if (bit_cycle == 15) begin
      bit_cycle <= 0;
      if (frame_bit == 9) begin
        rxd  <= 1'b1;
        done = 1'b1;
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
    baud_rate_edge       = 1'b0;
    rxd                  = 1'b1;
    reg_read             = '0;
    reg_read.lcr.word_len = 2'b11;
    reg_read.fcr.fifo_en = 1'b1;
    reg_read.fcr.rx_fifo_tl = 2'b01; // 16550A trigger level 4.
    cycle_count          = 0;
    step                 = 0;
    frame_bit            = 0;
    bit_cycle            = 0;
    sent_count           = 0;
    rhr_valid_count      = 0;
    baud_pulse_count     = 0;
    frame                = '1;
    next_data            = 8'h40;
  end

  always_ff @(posedge clk) begin
    logic frame_done;

    cycle_count <= cycle_count + 1;
    oversample_rate_edge <= rst_n;
    baud_rate_edge <= 1'b0;
    reg_read.obi_read_rhr <= 1'b0;
    frame_done = 1'b0;

    if (cycle_count == 8) begin
      rst_n <= 1'b1;
    end

    if (rst_n) begin
      if (reg_write.rhr_valid) begin
        rhr_valid_count <= rhr_valid_count + 1;
      end

      unique case (step)
        0: begin
          start_frame(next_data);
          step <= step + 1;
        end
        1: begin
          drive_frame_bit(frame_done);
          if (frame_done) begin
            sent_count <= sent_count + 1;
            next_data <= next_data + 1;
            step <= step + 1;
          end
        end
        2: begin
          if (sent_count == 5) begin
            step <= step + 1;
          end else begin
            start_frame(next_data);
            step <= 1;
          end
        end
        3: begin
          assert (rhr_valid_count >= 1)
            else $fatal(1, "FIFO mode never delivered a character to RHR");
          if (trigger) begin
            step <= step + 1;
          end
        end
        4: begin
          // Drive one baud pulse.  The following state drops the input and
          // records that pulse; the state after that samples timeout with no
          // pulse active, avoiding NBA ordering in the check.
          baud_rate_edge <= 1'b1;
          step <= step + 1;
        end
        5: begin
          // The high input was applied for this cycle's RX clock edge.
          baud_rate_edge <= 1'b0;
          baud_pulse_count <= baud_pulse_count + 1;
          step <= step + 1;
        end
        6: begin
          // Sample only after the accepted pulse, with baud_rate_edge low.
          if (timeout) begin
            assert (baud_pulse_count == 40)
              else $fatal(1, "RX timeout asserted after %0d baud pulses, expected 40",
                          baud_pulse_count);
            reg_read.obi_read_rhr <= 1'b1;
            step <= step + 1;
          end else begin
            assert (baud_pulse_count < 40)
              else $fatal(1, "RX timeout did not assert after 40 baud pulses");
            step <= 4;
          end
        end
        7: begin
          assert (reg_write.dr_valid && reg_write.data_ready)
            else $fatal(1, "FIFO did not keep data ready after popping one RHR byte");
          $display("obi_uart RX FIFO trigger/timeout smoke passed");
          $finish;
        end
        default: begin
          $fatal(1, "Unexpected RX FIFO step %0d", step);
        end
      endcase
    end

    if (cycle_count == 1400) begin
      $fatal(1, "Timed out in RX FIFO smoke at step %0d", step);
    end
  end
endmodule
