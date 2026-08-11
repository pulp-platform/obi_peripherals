// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module tb_obi_uart_modem (
  input logic clk
);
  import obi_uart_pkg::*;

  logic rst_n;
  logic cts_n;
  logic dsr_n;
  logic ri_n;
  logic cd_n;
  logic rts_n;
  logic dtr_n;
  logic out1_n;
  logic out2_n;

  reg_read_t reg_read;
  msr_bits_t msr_write;

  int unsigned cycle_count;
  int unsigned step;
  logic        saw_cts_delta;
  logic        saw_dsr_delta;

  obi_uart_modem i_dut (
    .clk_i       (clk),
    .rst_ni      (rst_n),
    .cts_ni      (cts_n),
    .dsr_ni      (dsr_n),
    .ri_ni       (ri_n),
    .cd_ni       (cd_n),
    .rts_no      (rts_n),
    .dtr_no      (dtr_n),
    .out1_no     (out1_n),
    .out2_no     (out2_n),
    .reg_read_i  (reg_read),
    .reg_write_o (msr_write)
  );

  initial begin
    rst_n       = 1'b0;
    cts_n       = 1'b1;
    dsr_n       = 1'b1;
    ri_n        = 1'b1;
    cd_n        = 1'b1;
    reg_read    = '0;
    cycle_count = 0;
    step        = 0;
    saw_cts_delta = 1'b0;
    saw_dsr_delta = 1'b0;
  end

  always_ff @(posedge clk) begin
    cycle_count <= cycle_count + 1;

    if (rst_n) begin
      saw_cts_delta <= saw_cts_delta | msr_write.d_cts;
      saw_dsr_delta <= saw_dsr_delta | msr_write.d_dsr;
    end

    if (cycle_count == 4) begin
      rst_n <= 1'b1;
    end

    if (rst_n) begin
      unique case (step)
        0: begin
          reg_read.mcr.rts  <= 1'b1;
          reg_read.mcr.dtr  <= 1'b1;
          reg_read.mcr.out1 <= 1'b1;
          reg_read.mcr.out2 <= 1'b0;
          step <= step + 1;
        end
        1: begin
          assert (!rts_n && !dtr_n && !out1_n && out2_n)
            else $fatal(1, "MCR outputs are not active-low encoded");
          cts_n <= 1'b0;
          dsr_n <= 1'b0;
          step <= step + 1;
        end
        2, 3, 4: begin
          step <= step + 1;
        end
        5: begin
          assert (msr_write.cts && msr_write.dsr)
            else $fatal(1, "MSR did not report active CTS/DSR inputs");
          assert (saw_cts_delta && saw_dsr_delta)
            else $fatal(1, "MSR did not report CTS/DSR deltas");
          reg_read.mcr.loopback <= 1'b1;
          reg_read.mcr.rts      <= 1'b0;
          reg_read.mcr.dtr      <= 1'b1;
          reg_read.mcr.out1     <= 1'b0;
          reg_read.mcr.out2     <= 1'b1;
          step <= step + 1;
        end
        6: begin
          assert (rts_n && dtr_n && out1_n && out2_n)
            else $fatal(1, "Loopback mode did not force modem outputs inactive");
          assert (!msr_write.cts && msr_write.dsr && !msr_write.ri && msr_write.cd)
            else $fatal(1, "Loopback modem status does not reflect MCR outputs");
          $display("obi_uart modem smoke passed");
          $finish;
        end
        default: begin
          $fatal(1, "Unexpected modem test step %0d", step);
        end
      endcase
    end

    if (cycle_count == 64) begin
      $fatal(1, "Timed out in modem smoke");
    end
  end
endmodule
