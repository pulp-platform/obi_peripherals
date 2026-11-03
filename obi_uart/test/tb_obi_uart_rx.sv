// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Drives obi_uart_rx directly and checks what it reports for each received frame:
// framing errors, the break indicator, clearing status on an LSR read, and the start-bit timing offset.
// One frame = start, 8 data bits, optional parity, stop.
module tb_obi_uart_rx;
  timeunit 1ns;
  timeprecision 1ps;

  import obi_uart_pkg::*;

  logic clk = 0, rst_n = 0, rxd = 1, os = 0, baud = 0;
  reg_read_t rd = '0;
  rx_reg_write_t wr;
  logic trig, tout;

  obi_uart_rx dut (
    .clk_i(clk), .rst_ni(rst_n), .oversample_rate_edge_i(os), .baud_rate_edge_i(baud), .rxd_i(rxd),
    .trigger_o(trig), .timeout_o(tout), .reg_read_i(rd), .reg_write_o(wr)
  );

  always #5 clk = ~clk;

  int div = 0, ticks = 0;
  always @(negedge clk) begin
    div <= (div + 1) % 4;
    os <= div == 3;
    if (div == 3) ticks <= (ticks + 1) % 16;
    baud <= div == 3 && ticks == 15;
  end

  // What the receiver reported for the last character, and what it did on the way.
  int writes = 0, resync_cycles = 0, load_with_clear = 0, load_alone = 0;
  logic [7:0] got_data;
  logic got_frame, got_break, got_parity;

  always @(posedge clk) if (rst_n) begin
    if (dut.state_q == RXRESYNCHRONIZE) resync_cycles++;
    if (dut.timing_load && dut.timing_clear) load_with_clear++;
    if (dut.timing_load && !dut.timing_clear) load_alone++;
    if (dut.write_init) begin
      writes++;
      if (rd.fcr.fifo_en) begin
        got_data = dut.fifo_data_i[7:0];
        got_break = dut.fifo_data_i[8];
        got_frame = dut.fifo_data_i[9];
        got_parity = dut.fifo_data_i[10];
      end else begin
        got_data = wr.rhr;
        got_break = wr.break_ind;
        got_frame = wr.frame_err;
        got_parity = wr.par_err;
      end
    end
  end

  task automatic bits(input logic v, input int n = 1);
    rxd = v;
    repeat (n * 64) @(negedge clk);
  endtask

  task automatic frame(input logic [7:0] d, input logic stop, input logic par = 0, input int phase = 0);
    repeat (phase) @(negedge clk);
    bits(0);
    for (int i = 0; i < 8; i++) bits(d[i]);
    if (rd.lcr.par_en) bits(par);
    bits(stop);
    bits(1, 4);
  endtask

  task automatic expect_frame(input string what, input logic frame_err, input logic parity_err);
    automatic int seen = writes;
    if (got_data !== 8'h55) $fatal(1, "%s: data %02h, expected 55", what, got_data);
    if (got_frame !== frame_err) $fatal(1, "%s: frame error %0b, expected %0b", what, got_frame, frame_err);
    if (got_break !== 1'b0) $fatal(1, "%s: break indicator %0b, expected 0", what, got_break);
    if (got_parity !== parity_err) $fatal(1, "%s: parity error %0b, expected %0b", what, got_parity, parity_err);
    if (seen == 0) $fatal(1, "%s: nothing was received", what);
  endtask

  initial begin
    repeat (8) @(negedge clk);
    rst_n = 1;
    repeat (200) @(negedge clk);
    rd.lcr.word_len = 2'b11;

    for (int phase = 0; phase < 8; phase++) begin
      frame(8'h55, 1'b1, 1'b0, phase);
      expect_frame($sformatf("FIFO off, valid frame, phase %0d", phase), 1'b0, 1'b0);
    end
    frame(8'h55, 1'b0);
    expect_frame("FIFO off, stop bit low", 1'b1, 1'b0);

    rd.fcr.fifo_en = 1;
    frame(8'h55, 1'b1);
    expect_frame("FIFO on, valid frame", 1'b0, 1'b0);
    frame(8'h55, 1'b0);
    expect_frame("FIFO on, stop bit low", 1'b1, 1'b0);

    rd.lcr.par_en = 1;        // odd parity: 0x55 has even weight, so a parity bit of 0 is wrong
    frame(8'h55, 1'b1, 1'b0);
    expect_frame("FIFO on, wrong parity", 1'b0, 1'b1);
    rd.lcr.par_en = 0;

    if (resync_cycles == 0) $fatal(1, "a framing error never reached RXRESYNCHRONIZE");
    if (load_alone == 0 || load_with_clear != 0)
      $fatal(1, "the timing offset was not loaded: %0d loads alone, %0d with a clear", load_alone, load_with_clear);

    @(negedge clk);
    rd.obi_read_lsr = 1;
    #1;
    if (!(wr.overrun_valid && wr.par_valid && wr.frame_valid && wr.break_valid))
      $fatal(1, "an LSR read does not clear status: valid %0b%0b%0b%0b", wr.overrun_valid, wr.par_valid, wr.frame_valid, wr.break_valid);

    $display("obi_uart_rx status test passed");
    $finish;
  end
endmodule
