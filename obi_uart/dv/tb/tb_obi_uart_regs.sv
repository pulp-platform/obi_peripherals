// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "obi/typedef.svh"

module tb_obi_uart_regs (
  input logic clk
);
  localparam obi_pkg::obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig;

  `OBI_TYPEDEF_MINIMAL_A_OPTIONAL(uart_obi_a_optional_t)
  `OBI_TYPEDEF_A_CHAN_T(uart_obi_a_chan_t, ObiCfg.AddrWidth, ObiCfg.DataWidth, ObiCfg.IdWidth,
      uart_obi_a_optional_t)
  `OBI_TYPEDEF_REQ_T(uart_obi_req_t, uart_obi_a_chan_t)
  `OBI_TYPEDEF_MINIMAL_R_OPTIONAL(uart_obi_r_optional_t)
  `OBI_TYPEDEF_R_CHAN_T(uart_obi_r_chan_t, ObiCfg.DataWidth, ObiCfg.IdWidth,
      uart_obi_r_optional_t)
  `OBI_TYPEDEF_RSP_T(uart_obi_rsp_t, uart_obi_r_chan_t)

  localparam logic [31:0] REG_RHR_THR_DLL = 32'h00;
  localparam logic [31:0] REG_IER_DLM     = 32'h04;
  localparam logic [31:0] REG_IIR_FCR     = 32'h08;
  localparam logic [31:0] REG_LCR         = 32'h0c;
  localparam logic [31:0] REG_MCR         = 32'h10;
  localparam logic [31:0] REG_LSR         = 32'h14;
  localparam logic [31:0] REG_MSR         = 32'h18;
  localparam logic [31:0] REG_SCR         = 32'h1c;

  localparam logic [7:0] LCR_DLAB = 8'h80;

  logic clk_unused;
  logic rst_n;
  uart_obi_req_t obi_req;
  uart_obi_rsp_t obi_rsp;
  logic irq;
  logic irq_n;
  logic rxd;
  logic txd;
  logic cts_n;
  logic dsr_n;
  logic ri_n;
  logic cd_n;
  logic rts_n;
  logic dtr_n;
  logic out1_n;
  logic out2_n;

  int unsigned cycle_count;
  int unsigned step;

  assign clk_unused = clk;

  obi_uart #(
    .ObiCfg    (ObiCfg),
    .obi_req_t (uart_obi_req_t),
    .obi_rsp_t (uart_obi_rsp_t)
  ) i_dut (
    .clk_i     (clk),
    .rst_ni    (rst_n),
    .obi_req_i (obi_req),
    .obi_rsp_o (obi_rsp),
    .irq_o     (irq),
    .irq_no    (irq_n),
    .rxd_i     (rxd),
    .txd_o     (txd),
    .cts_ni    (cts_n),
    .dsr_ni    (dsr_n),
    .ri_ni     (ri_n),
    .cd_ni     (cd_n),
    .rts_no    (rts_n),
    .dtr_no    (dtr_n),
    .out1_no   (out1_n),
    .out2_no   (out2_n)
  );

  function automatic uart_obi_req_t idle_req();
    uart_obi_req_t req;
    req = '0;
    req.rready = 1'b1;
    return req;
  endfunction

  function automatic uart_obi_req_t bus_write(input logic [31:0] addr, input logic [7:0] data);
    uart_obi_req_t req;
    req = idle_req();
    req.req     = 1'b1;
    req.a.we    = 1'b1;
    req.a.be    = 4'b0001;
    req.a.addr  = addr;
    req.a.wdata = {24'h0, data};
    return req;
  endfunction

  function automatic uart_obi_req_t bus_read(input logic [31:0] addr);
    uart_obi_req_t req;
    req = idle_req();
    req.req    = 1'b1;
    req.a.we   = 1'b0;
    req.a.be   = 4'b0001;
    req.a.addr = addr;
    return req;
  endfunction

  task automatic expect_rsp(input logic [7:0] expected);
    assert (obi_rsp.rvalid)
      else $fatal(1, "Expected OBI read response at step %0d", step);
    assert (!obi_rsp.r.err)
      else $fatal(1, "Unexpected OBI error at step %0d", step);
    assert (obi_rsp.r.rdata[7:0] == expected)
      else $fatal(1, "Read %02x, expected %02x at step %0d", obi_rsp.r.rdata[7:0], expected, step);
  endtask

  task automatic expect_err();
    assert (obi_rsp.rvalid)
      else $fatal(1, "Expected OBI read error response at step %0d", step);
    assert (obi_rsp.r.err)
      else $fatal(1, "Expected OBI read error at step %0d", step);
  endtask

  initial begin
    rst_n       = 1'b0;
    obi_req     = idle_req();
    rxd         = 1'b1;
    cts_n       = 1'b1;
    dsr_n       = 1'b1;
    ri_n        = 1'b1;
    cd_n        = 1'b1;
    cycle_count = 0;
    step        = 0;
  end

  always_ff @(negedge clk) begin
    cycle_count <= cycle_count + 1;
    obi_req <= idle_req();

    if (cycle_count == 4) begin
      rst_n <= 1'b1;
    end

    if (rst_n) begin
      unique case (step)
        0: begin
          obi_req <= bus_read(REG_LSR);
          step <= step + 1;
        end
        1: begin
          expect_rsp(8'h60); // THR empty and transmitter empty after reset.
          step <= step + 1;
        end
        2: begin
          obi_req <= bus_write(REG_RHR_THR_DLL, 8'ha5);
          step <= step + 1;
        end
        3: begin
          obi_req <= bus_read(REG_LSR);
          step <= step + 1;
        end
        4: begin
          expect_rsp(8'h00); // THR write clears THRE/TEMT until transmit progresses.
          step <= step + 1;
        end
        5: begin
          obi_req <= bus_read(REG_IIR_FCR);
          step <= step + 1;
        end
        6: begin
          expect_rsp(8'h01); // FIFO disabled after reset: no interrupt pending.
          step <= step + 1;
        end
        7: begin
          obi_req <= bus_write(REG_LCR, LCR_DLAB);
          step <= step + 1;
        end
        8: begin
          obi_req <= bus_write(REG_RHR_THR_DLL, 8'h34);
          step <= step + 1;
        end
        9: begin
          obi_req <= bus_write(REG_IER_DLM, 8'h12);
          step <= step + 1;
        end
        10: begin
          obi_req <= bus_read(REG_RHR_THR_DLL);
          step <= step + 1;
        end
        11: begin
          expect_rsp(8'h34);
          step <= step + 1;
        end
        12: begin
          obi_req <= bus_read(REG_IER_DLM);
          step <= step + 1;
        end
        13: begin
          expect_rsp(8'h12);
          step <= step + 1;
        end
        14: begin
          obi_req <= bus_read(REG_IIR_FCR);
          step <= step + 1;
        end
        15: begin
          expect_rsp(8'h01); // IIR remains visible with FIFO disabled while DLAB selects DLL/DLM.
          step <= step + 1;
        end
        16: begin
          obi_req <= bus_read(REG_LCR);
          step <= step + 1;
        end
        17: begin
          expect_rsp(LCR_DLAB); // LCR, including DLAB, remains visible.
          step <= step + 1;
        end
        18: begin
          obi_req <= bus_read(REG_MCR);
          step <= step + 1;
        end
        19: begin
          expect_rsp(8'h00); // MCR reset value remains visible with DLAB set.
          step <= step + 1;
        end
        20: begin
          obi_req <= bus_read(REG_LSR);
          step <= step + 1;
        end
        21: begin
          expect_rsp(8'h00); // THR remains busy; DLAB does not hide LSR.
          step <= step + 1;
        end
        22: begin
          obi_req <= bus_read(REG_MSR);
          step <= step + 1;
        end
        23: begin
          expect_rsp(8'h0f); // Reset synchronization deltas remain sticky; DLAB does not hide MSR.
          step <= step + 1;
        end
        24: begin
          obi_req <= bus_read(REG_SCR);
          step <= step + 1;
        end
        25: begin
          expect_rsp(8'h00); // Scratch register is intentionally not implemented.
          step <= step + 1;
        end
        26: begin
          obi_req <= bus_write(REG_LCR, 8'h00);
          step <= step + 1;
        end
        27: begin
          obi_req <= bus_write(REG_IER_DLM, 8'h0f);
          step <= step + 1;
        end
        28: begin
          obi_req <= bus_read(REG_IER_DLM);
          step <= step + 1;
        end
        29: begin
          expect_rsp(8'h0f);
          step <= step + 1;
        end
        30: begin
          obi_req <= bus_read(REG_SCR);
          step <= step + 1;
        end
        31: begin
          expect_rsp(8'h00); // Scratch register is intentionally not implemented.
          step <= step + 1;
        end
        32: begin
          obi_req <= bus_read(32'h80);
          step <= step + 1;
        end
        33: begin
          expect_err();
          // High-address writes must not alias the low register window.
          obi_req <= bus_write(32'h84, 8'h55);
          step <= step + 1;
        end
        34: begin
          expect_err();
          // The rejected write must not corrupt IER.
          obi_req <= bus_read(REG_IER_DLM);
          step <= step + 1;
        end
        35: begin
          expect_rsp(8'h0f);
          obi_req <= bus_read(32'h40);
          step <= step + 1;
        end
        36: begin
          expect_err();
          // Enable the FIFO and verify that IIR advertises 16550A support.
          obi_req <= bus_write(REG_IIR_FCR, 8'h01);
          step <= step + 1;
        end
        37: begin
          obi_req <= bus_read(REG_IIR_FCR);
          step <= step + 1;
        end
        38: begin
          expect_rsp(8'hc1); // FIFO enabled: 16550A FIFO ID bits, no interrupt pending.
          $display("obi_uart register compatibility smoke passed");
          $finish;
        end
        default: begin
          $fatal(1, "Unexpected test step %0d", step);
        end
      endcase
    end

    if (cycle_count == 128) begin
      $fatal(1, "Timed out in register compatibility smoke");
    end
  end
endmodule
