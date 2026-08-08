// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

module tb_obi_uart_tx_waveform (
  input logic clk
);
  import obi_uart_pkg::*;

  logic rst_n;
  logic baud_rate_edge;
  logic double_rate_edge;
  logic txd;
  reg_read_t     reg_read;
  tx_reg_write_t reg_write;

  int unsigned cycle_count;
  int unsigned step;

  obi_uart_tx i_dut (
    .clk_i              (clk),
    .rst_ni             (rst_n),
    .baud_rate_edge_i   (baud_rate_edge),
    .double_rate_edge_i (double_rate_edge),
    .txd_o              (txd),
    .reg_read_i         (reg_read),
    .reg_write_o        (reg_write)
  );

  task automatic pulse_baud();
    baud_rate_edge <= 1'b1;
  endtask

  task automatic pulse_double();
    double_rate_edge <= 1'b1;
  endtask

  task automatic expect_txd(input logic expected);
    assert (txd == expected)
      else $fatal(1, "TXD %0b, expected %0b at step %0d", txd, expected, step);
  endtask

  initial begin
    rst_n            = 1'b0;
    baud_rate_edge   = 1'b0;
    double_rate_edge = 1'b0;
    reg_read         = '0;
    reg_read.lcr.word_len = 2'b11;
    cycle_count      = 0;
    step             = 0;
  end

  always_ff @(negedge clk) begin
    cycle_count <= cycle_count + 1;
    baud_rate_edge <= 1'b0;
    double_rate_edge <= 1'b0;
    reg_read.obi_write_thr <= 1'b0;

    if (cycle_count == 4) begin
      rst_n <= 1'b1;
    end

    if (rst_n) begin
      unique case (step)
        0: begin
          expect_txd(1'b1);
          assert (reg_write.thr_valid && reg_write.thr_empty)
            else $fatal(1, "THRE was not set while TX idle");
          assert (reg_write.empty_valid && reg_write.tx_empty)
            else $fatal(1, "TEMT was not set while TX idle");
          reg_read.thr.char_tx <= 8'ha5;
          reg_read.obi_write_thr <= 1'b1;
          step <= step + 1;
        end
        1: begin
          assert (reg_write.thr_valid && !reg_write.thr_empty)
            else $fatal(1, "THR write did not clear THRE");
          assert (reg_write.empty_valid && !reg_write.tx_empty)
            else $fatal(1, "THR write did not clear TEMT");
          pulse_baud();
          step <= step + 1;
        end
        2: begin
          pulse_baud();
          step <= step + 1;
        end
        3: begin
          expect_txd(1'b0); // Start bit.
          pulse_baud();
          step <= step + 1;
        end
        4: begin
          expect_txd(1'b1); // bit 0 of 8'ha5
          pulse_baud();
          step <= step + 1;
        end
        5: begin
          expect_txd(1'b0); // bit 1
          pulse_baud();
          step <= step + 1;
        end
        6: begin
          expect_txd(1'b1); // bit 2
          pulse_baud();
          step <= step + 1;
        end
        7: begin
          expect_txd(1'b0); // bit 3
          pulse_baud();
          step <= step + 1;
        end
        8: begin
          expect_txd(1'b0); // bit 4
          pulse_baud();
          step <= step + 1;
        end
        9: begin
          expect_txd(1'b1); // bit 5
          pulse_baud();
          step <= step + 1;
        end
        10: begin
          expect_txd(1'b0); // bit 6
          pulse_baud();
          step <= step + 1;
        end
        11: begin
          expect_txd(1'b1); // bit 7
          pulse_baud();
          step <= step + 1;
        end
        12: begin
          expect_txd(1'b1); // Stop bit.
          pulse_baud();
          step <= step + 1;
        end
        13: begin
          expect_txd(1'b1);
          assert (reg_write.thr_valid && reg_write.thr_empty)
            else $fatal(1, "THRE did not reassert after TX drained");
          assert (reg_write.empty_valid && reg_write.tx_empty)
            else $fatal(1, "TEMT did not reassert after TX drained");
          // Queue a byte in the non-FIFO holding register, then service the
          // holding register while issuing the next CPU write.  The first
          // byte must serialize before the newly written byte.
          reg_read.thr.char_tx <= 8'h3c;
          reg_read.obi_write_thr <= 1'b1;
          step <= step + 1;
        end
        14: begin
          assert (reg_write.thr_valid && !reg_write.thr_empty)
            else $fatal(1, "Overlap THR write did not clear THRE");
          assert (reg_write.empty_valid && !reg_write.tx_empty)
            else $fatal(1, "Overlap THR write did not clear TEMT");
          // The write indicator overlaps consumption of the old 8'h3c byte.
          reg_read.obi_write_thr <= 1'b1;
          pulse_baud();
          step <= step + 1;
        end
        15: begin
          // The register value is updated after the write edge, as it is at
          // the module-level register interface.  This is the new pending B.
          assert (reg_write.thr_valid && !reg_write.thr_empty)
            else $fatal(1, "Concurrent B write did not clear THRE");
          assert (reg_write.empty_valid && !reg_write.tx_empty)
            else $fatal(1, "Concurrent B write did not clear TEMT");
          reg_read.thr.char_tx <= 8'hc3;
          reg_read.obi_write_thr <= 1'b0;
          pulse_baud();
          step <= step + 1;
        end
        16: begin
          expect_txd(1'b0); // A start bit.
          pulse_baud();
          step <= step + 1;
        end
        17: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        18: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        19: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        20: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        21: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        22: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        23: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        24: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        25: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        26: begin
          // The first stop bit is still high while the pending B byte waits
          // in TXSTART.  Hold one cycle before advancing to its data phase.
          expect_txd(1'b1);
          step <= step + 1;
        end
        27: begin
          // B is already pending when A finishes.  Consume it and check that
          // THRE reasserts while B is in the serializer, before TEMT does.
          pulse_baud();
          step <= step + 1;
        end
        28: begin
          assert (reg_write.thr_valid && reg_write.thr_empty)
            else $fatal(1, "THRE did not reassert with B in serializer");
          assert (!reg_write.empty_valid)
            else $fatal(1, "TEMT asserted while B was still transmitting");
          expect_txd(1'b0); // B start bit.
          pulse_baud();
          step <= step + 1;
        end
        29: begin
          expect_txd(1'b1); // B bit 0.
          pulse_baud();
          step <= step + 1;
        end
        30: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        31: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        32: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        33: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        34: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        35: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        36: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        37: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        38: begin
          expect_txd(1'b1); // B stop bit.
          pulse_baud();
          step <= step + 1;
        end
        39: begin
          expect_txd(1'b1);
          assert (reg_write.thr_valid && reg_write.thr_empty)
            else $fatal(1, "THRE did not reassert after overlap drain");
          assert (reg_write.empty_valid && reg_write.tx_empty)
            else $fatal(1, "TEMT did not reassert after overlap drain");
          // Enter FIFO mode and clear it before the FIFO-specific checks.
          reg_read.fcr.fifo_en <= 1'b1;
          reg_read.fcr.tx_fifo_rst <= 1'b1;
          step <= step + 1;
        end
        40: begin
          assert (reg_write.fifo_rst_valid && !reg_write.fifo_rst)
            else $fatal(1, "FIFO reset was not acknowledged");
          reg_read.fcr.tx_fifo_rst <= 1'b0;
          step <= step + 1;
        end
        41: begin
          assert (reg_write.thr_valid && reg_write.thr_empty)
            else $fatal(1, "FIFO THRE was not set while empty");
          assert (reg_write.empty_valid && reg_write.tx_empty)
            else $fatal(1, "FIFO TEMT was not set while idle");
          // Single-byte FIFO case.
          reg_read.thr.char_tx <= 8'ha5;
          reg_read.obi_write_thr <= 1'b1;
          step <= step + 1;
        end
        42: begin
          assert (reg_write.thr_valid && !reg_write.thr_empty)
            else $fatal(1, "FIFO write did not clear THRE");
          assert (reg_write.empty_valid && !reg_write.tx_empty)
            else $fatal(1, "FIFO write did not clear TEMT");
          step <= step + 1;
        end
        43: begin
          // The pending byte is being pushed into an empty FIFO.  Empty
          // status must not pulse in this cycle.
          assert (!reg_write.thr_valid && !reg_write.empty_valid)
            else $fatal(1, "FIFO push into empty queue spuriously asserted empty status");
          step <= step + 1;
        end
        44: begin
          assert (!reg_write.thr_valid && !reg_write.empty_valid)
            else $fatal(1, "FIFO queued byte incorrectly reported empty");
          pulse_baud();
          step <= step + 1;
        end
        45: begin
          assert (reg_write.thr_valid && reg_write.thr_empty)
            else $fatal(1, "THRE did not assert after FIFO became empty");
          assert (!reg_write.empty_valid)
            else $fatal(1, "TEMT asserted while FIFO byte was transmitting");
          pulse_baud();
          step <= step + 1;
        end
        46: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        47: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        48: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        49: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        50: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        51: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        52: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        53: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        54: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        55: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        56: begin
          expect_txd(1'b1);
          assert (reg_write.thr_valid && reg_write.thr_empty)
            else $fatal(1, "FIFO THRE did not remain set after drain");
          assert (reg_write.empty_valid && reg_write.tx_empty)
            else $fatal(1, "FIFO TEMT did not assert after drain");
          // Reset FIFO and test old-A push concurrent with a new-B write.
          reg_read.fcr.tx_fifo_rst <= 1'b1;
          step <= step + 1;
        end
        57: begin
          assert (reg_write.fifo_rst_valid && !reg_write.fifo_rst)
            else $fatal(1, "Second FIFO reset was not acknowledged");
          reg_read.fcr.tx_fifo_rst <= 1'b0;
          step <= step + 1;
        end
        58: begin
          reg_read.thr.char_tx <= 8'h96;
          reg_read.obi_write_thr <= 1'b1;
          step <= step + 1;
        end
        59: begin
          assert (reg_write.thr_valid && !reg_write.thr_empty)
            else $fatal(1, "FIFO overlap A write did not clear THRE");
          // Keep the old A value visible while this write indicator overlaps
          // the push into the FIFO; update to B after the edge.
          reg_read.obi_write_thr <= 1'b1;
          step <= step + 1;
        end
        60: begin
          assert (reg_write.thr_valid && !reg_write.thr_empty)
            else $fatal(1, "FIFO overlap B write did not clear THRE");
          assert (reg_write.empty_valid && !reg_write.tx_empty)
            else $fatal(1, "FIFO overlap B write did not clear TEMT");
          reg_read.thr.char_tx <= 8'h69;
          reg_read.obi_write_thr <= 1'b0;
          step <= step + 1;
        end
        61: begin
          // B is pending while A is queued; push B before starting A.
          assert (!reg_write.thr_valid && !reg_write.empty_valid)
            else $fatal(1, "FIFO overlap B pending status was incorrect");
          pulse_baud();
          step <= step + 1;
        end
        62: begin
          assert (!reg_write.thr_valid && !reg_write.empty_valid)
            else $fatal(1, "FIFO reported empty with A and B queued");
          pulse_baud();
          step <= step + 1;
        end
        63: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        64: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        65: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        66: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        67: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        68: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        69: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        70: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        71: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        72: begin
          expect_txd(1'b1); // A stop bit.
          pulse_baud();
          step <= step + 1;
        end
        73: begin
          // B is in TXSTART after the first stop-bit edge.  Hold one cycle
          // before advancing to its data phase.
          step <= step + 1;
        end
        74: begin
          assert (reg_write.thr_valid && reg_write.thr_empty)
            else $fatal(1, "FIFO THRE did not assert after B was popped");
          assert (!reg_write.empty_valid)
            else $fatal(1, "FIFO TEMT asserted before B transmission");
          pulse_baud();
          step <= step + 1;
        end
        75: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        76: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        77: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        78: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        79: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        80: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        81: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        82: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        83: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        84: begin
          expect_txd(1'b1); // B stop bit.
          pulse_baud();
          step <= step + 1;
        end
        85: begin
          expect_txd(1'b1);
          assert (reg_write.thr_valid && reg_write.thr_empty)
            else $fatal(1, "FIFO overlap THRE did not reassert after drain");
          assert (reg_write.empty_valid && reg_write.tx_empty)
            else $fatal(1, "FIFO overlap TEMT did not reassert after drain");
          // STB=1 selects two full stop bits for an 8-bit word.
          reg_read.fcr.fifo_en <= 1'b0;
          reg_read.lcr.stop_bits <= 1'b1;
          reg_read.thr.char_tx <= 8'h55;
          reg_read.obi_write_thr <= 1'b1;
          step <= step + 1;
        end
        86: begin
          assert (reg_write.thr_valid && !reg_write.thr_empty)
            else $fatal(1, "8-bit two-stop write did not clear THRE");
          assert (reg_write.empty_valid && !reg_write.tx_empty)
            else $fatal(1, "8-bit two-stop write did not clear TEMT");
          pulse_baud();
          step <= step + 1;
        end
        87: begin
          pulse_baud();
          step <= step + 1;
        end
        88: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        89: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        90: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        91: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        92: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        93: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        94: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        95: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        96: begin
          assert (i_dut.state_q == TXSTOP1)
            else $fatal(1, "8-bit first stop state was skipped");
          expect_txd(1'b0);
          pulse_baud();
          step <= step + 1;
        end
        97: begin
          assert (i_dut.state_q == TXSTOP2)
            else $fatal(1, "8-bit second stop state was skipped");
          expect_txd(1'b1);
          assert (!reg_write.empty_valid)
            else $fatal(1, "TEMT asserted during first 8-bit stop");
          step <= step + 1;
        end
        98: begin
          assert (i_dut.state_q == TXSTOP2)
            else $fatal(1, "8-bit second stop state did not hold");
          expect_txd(1'b1);
          assert (!reg_write.empty_valid)
            else $fatal(1, "TEMT asserted during second 8-bit stop");
          pulse_baud();
          step <= step + 1;
        end
        99: begin
          assert (i_dut.state_q == TXIDLE)
            else $fatal(1, "8-bit transmitter did not leave TXSTOP2 after its baud edge");
          expect_txd(1'b1);
          assert (reg_write.empty_valid && reg_write.tx_empty)
            else $fatal(1, "TEMT did not assert after two 8-bit stop bits");
          // STB=1 with a 5-bit word selects a 1.5-stop-bit frame.  The
          // second stop state must hold until the half-bit enable.
          reg_read.lcr.word_len <= 2'b00;
          reg_read.thr.char_tx <= 8'h15;
          reg_read.obi_write_thr <= 1'b1;
          step <= step + 1;
        end
        100: begin
          assert (reg_write.thr_valid && !reg_write.thr_empty)
            else $fatal(1, "5-bit 1.5-stop write did not clear THRE");
          pulse_baud();
          step <= step + 1;
        end
        101: begin
          pulse_baud();
          step <= step + 1;
        end
        102: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        103: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        104: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        105: begin expect_txd(1'b1); pulse_baud(); step <= step + 1; end
        106: begin expect_txd(1'b0); pulse_baud(); step <= step + 1; end
        107: begin
          assert (i_dut.state_q == TXSTOP1)
            else $fatal(1, "5-bit first stop state was skipped");
          expect_txd(1'b1);
          pulse_baud();
          step <= step + 1;
        end
        108: begin
          assert (i_dut.state_q == TXSTOP2)
            else $fatal(1, "5-bit half-stop state was skipped");
          expect_txd(1'b1);
          assert (!reg_write.empty_valid)
            else $fatal(1, "TEMT asserted during 5-bit first stop");
          step <= step + 1;
        end
        109: begin
          assert (i_dut.state_q == TXSTOP2)
            else $fatal(1, "5-bit half-stop state was skipped");
          expect_txd(1'b1);
          assert (!reg_write.empty_valid)
            else $fatal(1, "TEMT asserted during 5-bit half stop");
          pulse_double();
          step <= step + 1;
        end
        110: begin
          assert (i_dut.state_q == TXIDLE)
            else $fatal(1, "5-bit transmitter did not wait for half-stop enable");
          expect_txd(1'b1);
          assert (reg_write.empty_valid && reg_write.tx_empty)
            else $fatal(1, "TEMT did not assert after 1.5 stop bits");
          $display("obi_uart TX overlap/FIFO/stop-bit checks passed");
          $finish;
        end
        default: begin
          $fatal(1, "Unexpected TX waveform step %0d", step);
        end
      endcase
    end

    if (cycle_count == 350) begin
      $fatal(1, "Timed out in TX waveform smoke at step %0d", step);
    end
  end
endmodule
