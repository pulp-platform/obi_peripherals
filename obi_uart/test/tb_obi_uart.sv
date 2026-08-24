// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "obi/typedef.svh"

module tb_obi_uart;
  timeunit 1ns;
  timeprecision 1ps;

  import obi_uart_pkg::*;

  `OBI_TYPEDEF_DEFAULT_REQ_T(tb_obi_uart_req_t, obi_uart_a_chan_t)

  localparam logic [31:0] UartBase     = 32'h1000_0000;
  localparam logic [31:0] RegRhrThrDll = UartBase + 32'h00;
  localparam logic [31:0] RegIerDlm    = UartBase + 32'h04;
  localparam logic [31:0] RegLcr       = UartBase + 32'h0c;
  localparam logic [31:0] RegLsr       = UartBase + 32'h14;

  localparam logic [7:0] LcrDlab = 8'h80;
  localparam logic [7:0] Lcr8N1  = 8'h03;
  localparam int unsigned ClksPerBit = 32;

  logic clk;
  logic rst_n;
  tb_obi_uart_req_t obi_req;
  obi_uart_rsp_t obi_rsp;
  logic irq;
  logic irq_n;
  logic rxd;
  logic txd;
  logic rts_n;
  logic dtr_n;
  logic out1_n;
  logic out2_n;

  always #5ns clk = ~clk;

  obi_uart #(
    .obi_req_t (tb_obi_uart_req_t)
  ) i_dut (
    .clk_i     (clk),
    .rst_ni    (rst_n),
    .obi_req_i (obi_req),
    .obi_rsp_o (obi_rsp),
    .irq_o     (irq),
    .irq_no    (irq_n),
    .rxd_i     (rxd),
    .txd_o     (txd),
    .cts_ni    (1'b1),
    .dsr_ni    (1'b1),
    .ri_ni     (1'b1),
    .cd_ni     (1'b1),
    .rts_no    (rts_n),
    .dtr_no    (dtr_n),
    .out1_no   (out1_n),
    .out2_no   (out2_n)
  );

  function automatic tb_obi_uart_req_t idle_req();
    tb_obi_uart_req_t req;
    req = '0;
    return req;
  endfunction

  function automatic tb_obi_uart_req_t write_req(
    input logic [31:0] addr,
    input logic [7:0]  data
  );
    tb_obi_uart_req_t req;
    req = idle_req();
    req.req     = 1'b1;
    req.a.we    = 1'b1;
    req.a.be    = 4'b0001;
    req.a.addr  = addr;
    req.a.wdata = {24'h0, data};
    return req;
  endfunction

  function automatic tb_obi_uart_req_t read_req(input logic [31:0] addr);
    tb_obi_uart_req_t req;
    req = idle_req();
    req.req    = 1'b1;
    req.a.we   = 1'b0;
    req.a.be   = 4'b0001;
    req.a.addr = addr;
    return req;
  endfunction

  task automatic obi_write(input logic [31:0] addr, input logic [7:0] data);
    @(negedge clk);
    obi_req = write_req(addr, data);
    @(negedge clk);
    assert (obi_rsp.gnt)
      else $fatal(1, "OBI write to %08x was not granted", addr);
    obi_req = idle_req();
  endtask

  task automatic obi_read(input logic [31:0] addr, output logic [7:0] data);
    @(negedge clk);
    obi_req = read_req(addr);
    @(negedge clk);
    assert (obi_rsp.rvalid)
      else $fatal(1, "Missing OBI read response from %08x", addr);
    assert (!obi_rsp.r.err)
      else $fatal(1, "Unexpected OBI read error from %08x", addr);
    data = obi_rsp.r.rdata[7:0];
    obi_req = idle_req();
  endtask

  task automatic obi_write_error(input logic [31:0] addr, input logic [7:0] data);
    @(negedge clk);
    obi_req = write_req(addr, data);
    @(negedge clk);
    assert (obi_rsp.rvalid)
      else $fatal(1, "Missing OBI write response from %08x", addr);
    assert (obi_rsp.r.err)
      else $fatal(1, "OBI write to invalid address %08x did not report an error", addr);
    obi_req = idle_req();
  endtask

  task automatic obi_read_error(input logic [31:0] addr);
    @(negedge clk);
    obi_req = read_req(addr);
    @(negedge clk);
    assert (obi_rsp.rvalid)
      else $fatal(1, "Missing OBI read response from %08x", addr);
    assert (obi_rsp.r.err)
      else $fatal(1, "OBI read from invalid address %08x did not report an error", addr);
    obi_req = idle_req();
  endtask

  task automatic configure_uart();
    obi_write(RegLcr, LcrDlab);
    obi_write(RegRhrThrDll, 8'h02);
    obi_write(RegIerDlm, 8'h00);
    obi_write(RegLcr, Lcr8N1);
  endtask

  task automatic check_tx_byte(input logic [7:0] data);
    logic [9:0] frame;
    frame = {1'b1, data, 1'b0};

    wait (txd == 1'b0);
    repeat (ClksPerBit / 2) @(negedge clk);
    for (int unsigned bit_idx = 0; bit_idx < 10; bit_idx++) begin
      assert (txd == frame[bit_idx])
        else $fatal(1, "TX bit %0d was %0b, expected %0b", bit_idx, txd, frame[bit_idx]);
      if (bit_idx != 9) begin
        repeat (ClksPerBit) @(negedge clk);
      end
    end
  endtask

  task automatic drive_rx_byte(input logic [7:0] data);
    logic [9:0] frame;
    frame = {1'b1, data, 1'b0};

    @(negedge clk);
    for (int unsigned bit_idx = 0; bit_idx < 10; bit_idx++) begin
      rxd = frame[bit_idx];
      repeat (ClksPerBit) @(negedge clk);
    end
    rxd = 1'b1;
  endtask

  task automatic wait_for_lsr(
    input logic [7:0] mask,
    input logic [7:0] expected
  );
    logic [7:0] lsr;
    repeat (32) begin
      obi_read(RegLsr, lsr);
      if ((lsr & mask) == expected) begin
        return;
      end
    end
    $fatal(1, "LSR did not reach mask %02x == %02x", mask, expected);
  endtask

  initial begin
    logic [7:0] data;

    clk     = 1'b0;
    rst_n   = 1'b0;
    obi_req = idle_req();
    rxd     = 1'b1;

    repeat (5) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    // Only aligned offsets in the 0x00 through 0x1c register map are valid.
    obi_read_error(UartBase + 32'h020);
    obi_read_error(UartBase + 32'h040);
    obi_read_error(UartBase + 32'h080);
    obi_read_error(UartBase + 32'hffc);
    obi_read_error(UartBase + 32'h001);

    obi_write(RegLcr, Lcr8N1);
    obi_write_error(UartBase + 32'h02c, 8'h80);
    obi_write_error(UartBase + 32'h04c, 8'h80);
    obi_write_error(UartBase + 32'h08c, 8'h80);
    obi_write_error(UartBase + 32'hffc, 8'h80);
    obi_write_error(UartBase + 32'h00f, 8'h80);

    obi_read(RegLcr, data);
    assert (data == Lcr8N1)
      else $fatal(1, "Invalid address write changed LCR to %02x", data);

    configure_uart();

    fork
      check_tx_byte(8'ha5);
      obi_write(RegRhrThrDll, 8'ha5);
    join
    wait_for_lsr(8'h60, 8'h60);

    drive_rx_byte(8'h5a);
    wait_for_lsr(8'h01, 8'h01);
    obi_read_error(UartBase + 32'h020);
    obi_read(RegRhrThrDll, data);
    assert (data == 8'h5a)
      else $fatal(1, "Received %02x, expected 5a", data);

    $display("obi_uart basic transmit and receive test passed");
    $finish;
  end

  initial begin
    #100us;
    $fatal(1, "Timed out in obi_uart basic transmit and receive test");
  end

endmodule
