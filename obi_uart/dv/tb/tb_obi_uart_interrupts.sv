// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module tb_obi_uart_interrupts (
  input logic clk
);
  import obi_uart_pkg::*;

  logic rst_n;
  logic rx_fifo_trigger;
  logic rx_timeout;
  logic irq;
  logic irq_n;

  reg_read_t  reg_read;
  reg_write_t reg_write;
  isr_bits_t  isr;

  int unsigned cycle_count;
  int unsigned step;

  obi_uart_interrupts i_dut (
    .clk_i           (clk),
    .rst_ni          (rst_n),
    .rx_fifo_trigger (rx_fifo_trigger),
    .rx_timeout      (rx_timeout),
    .irq_o           (irq),
    .irq_no          (irq_n),
    .reg_read_i      (reg_read),
    .reg_write_i     (reg_write),
    .reg_isr_o       (isr)
  );

  function automatic void clear_inputs();
    reg_read.obi_read_rhr   = 1'b0;
    reg_read.obi_read_isr   = 1'b0;
    reg_read.obi_read_lsr   = 1'b0;
    reg_read.obi_read_msr   = 1'b0;
    reg_read.obi_write_thr  = 1'b0;
    reg_write.rx            = '0;
    reg_write.tx            = '0;
    reg_write.modem.d_cts   = 1'b0;
    reg_write.modem.d_dsr   = 1'b0;
    reg_write.modem.te_ri   = 1'b0;
    reg_write.modem.d_cd    = 1'b0;
    rx_fifo_trigger         = 1'b0;
    rx_timeout              = 1'b0;
  endfunction

  task automatic expect_iir(input logic [7:0] expected);
    assert (isr == expected)
      else $fatal(1, "IIR %02x, expected %02x at step %0d", isr, expected, step);
    assert (irq == !expected[0])
      else $fatal(1, "IRQ mismatch for IIR %02x at step %0d", isr, step);
    assert (irq_n == expected[0])
      else $fatal(1, "IRQ_N mismatch for IIR %02x at step %0d", isr, step);
  endtask

  initial begin
    rst_n           = 1'b0;
    reg_read        = '0;
    reg_write       = '0;
    rx_fifo_trigger = 1'b0;
    rx_timeout      = 1'b0;
    cycle_count     = 0;
    step            = 0;
  end

  always_ff @(negedge clk) begin
    cycle_count <= cycle_count + 1;
    clear_inputs();

    if (cycle_count == 4) begin
      rst_n <= 1'b1;
      reg_read.ier <= 8'h00;
      reg_read.fcr.fifo_en <= 1'b0;
    end

    if (rst_n) begin
      unique case (step)
        0: begin
          // A retained line error must survive with IER disabled.
          reg_read.lsr.frame_err <= 1'b1;
          step <= step + 1;
        end
        1: begin
          expect_iir(8'h01);
          reg_read.ier <= 8'h04; // Enable RLS after the error was retained.
          step <= step + 1;
        end
        2: begin
          expect_iir(8'h06);
          // LSR read clears the old error, but a same-cycle new error wins.
          reg_read.obi_read_lsr <= 1'b1;
          reg_write.rx.par_valid <= 1'b1;
          reg_write.rx.par_err <= 1'b1;
          step <= step + 1;
        end
        3: begin
          expect_iir(8'h06);
          reg_read.obi_read_lsr <= 1'b1;
          reg_read.lsr.frame_err <= 1'b0;
          reg_read.lsr.par_err <= 1'b0;
          step <= step + 1;
        end
        4: begin
          expect_iir(8'h01);
          // Non-FIFO RDA is also level-backed and supports late IER enable.
          reg_read.lsr.data_ready <= 1'b1;
          reg_read.ier <= 8'h01;
          step <= step + 1;
        end
        5: begin
          expect_iir(8'h04);
          // RHR clear and a new received character in the same cycle: set wins.
          reg_read.obi_read_rhr <= 1'b1;
          reg_write.rx.dr_valid <= 1'b1;
          reg_write.rx.data_ready <= 1'b1;
          step <= step + 1;
        end
        6: begin
          expect_iir(8'h04);
          reg_read.obi_read_rhr <= 1'b1;
          reg_read.lsr.data_ready <= 1'b0;
          step <= step + 1;
        end
        7: begin
          expect_iir(8'h01);
          // MSR delta bits retained while disabled, then enabled late.
          reg_read.msr.d_cts <= 1'b1;
          reg_read.ier <= 8'h08;
          step <= step + 1;
        end
        8: begin
          expect_iir(8'h00);
          // MSR read clears old delta; a simultaneous modem transition wins.
          reg_read.obi_read_msr <= 1'b1;
          reg_write.modem.d_dsr <= 1'b1;
          step <= step + 1;
        end
        9: begin
          expect_iir(8'h00);
          reg_read.obi_read_msr <= 1'b1;
          reg_read.msr.d_cts <= 1'b0;
          reg_read.msr.d_dsr <= 1'b0;
          step <= step + 1;
        end
        10: begin
          expect_iir(8'h01);
          // THRI is level-backed and appears when enabled with retained THRE.
          reg_read.lsr.thr_empty <= 1'b1;
          reg_read.ier <= 8'h02;
          step <= step + 1;
        end
        11: begin
          expect_iir(8'h02);
          // Only an IIR read reporting THRI acknowledges it.
          reg_read.obi_read_isr <= 1'b1;
          step <= step + 1;
        end
        12: begin
          expect_iir(8'h01);
          // THRI must not immediately reassert while THRE remains high.
          step <= step + 1;
        end
        13: begin
          expect_iir(8'h01);
          // A THRE drop re-arms the interrupt, and a later rise asserts it.
          reg_read.lsr.thr_empty <= 1'b0;
          reg_write.tx.thr_valid <= 1'b1;
          reg_write.tx.thr_empty <= 1'b0;
          step <= step + 1;
        end
        14: begin
          expect_iir(8'h01);
          reg_read.lsr.thr_empty <= 1'b1;
          reg_write.tx.thr_valid <= 1'b1;
          reg_write.tx.thr_empty <= 1'b1;
          step <= step + 1;
        end
        15: begin
          expect_iir(8'h02);
          // FIFO RDA is trigger-level based and does not clear above trigger.
          reg_read.fcr.fifo_en <= 1'b1;
          reg_read.ier <= 8'h01;
          rx_fifo_trigger <= 1'b1;
          step <= step + 1;
        end
        16: begin
          expect_iir(8'hc4);
          reg_read.obi_read_rhr <= 1'b1;
          rx_fifo_trigger <= 1'b1;
          step <= step + 1;
        end
        17: begin
          expect_iir(8'hc4);
          rx_fifo_trigger <= 1'b0;
          step <= step + 1;
        end
        18: begin
          expect_iir(8'hc1);
          // Timeout follows the FIFO timeout level and clears when it drops.
          rx_timeout <= 1'b1;
          step <= step + 1;
        end
        19: begin
          expect_iir(8'hcc);
          rx_timeout <= 1'b0;
          step <= step + 1;
        end
        20: begin
          expect_iir(8'hc1);
          $display("obi_uart interrupt compatibility smoke passed");
          $finish;
        end
        default: begin
          $fatal(1, "Unexpected test step %0d", step);
        end
      endcase
    end

    if (cycle_count == 64) begin
      $fatal(1, "Timed out in interrupt priority smoke");
    end
  end
endmodule
