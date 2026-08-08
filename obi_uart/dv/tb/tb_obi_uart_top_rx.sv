// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "obi/typedef.svh"

module tb_obi_uart_top_rx (
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
  localparam logic [31:0] REG_LSR         = 32'h14;

  localparam logic [7:0] LCR_DLAB = 8'h80;
  localparam logic [7:0] LCR_8N1  = 8'h03;
  localparam int unsigned ClksPerBit = 32;

  logic rst_n;
  uart_obi_req_t obi_req;
  uart_obi_rsp_t obi_rsp;
  logic irq;
  logic irq_n;
  logic rxd;
  logic txd;
  logic rts_n;
  logic dtr_n;
  logic out1_n;
  logic out2_n;

  int unsigned cycle_count;
  int unsigned step;
  int unsigned frame_bit;
  int unsigned bit_cycle;
  int unsigned wait_count;
  logic [9:0] frame;

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
    .cts_ni    (1'b1),
    .dsr_ni    (1'b1),
    .ri_ni     (1'b1),
    .cd_ni     (1'b1),
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

  task automatic expect_rsp_mask(input logic [7:0] mask, input logic [7:0] expected);
    assert (obi_rsp.rvalid)
      else $fatal(1, "Expected OBI read response at step %0d", step);
    assert (!obi_rsp.r.err)
      else $fatal(1, "Unexpected OBI error at step %0d", step);
    assert ((obi_rsp.r.rdata[7:0] & mask) == expected)
      else $fatal(1, "Read %02x, expected mask %02x == %02x at step %0d",
                  obi_rsp.r.rdata[7:0], mask, expected, step);
  endtask

  task automatic start_frame(input logic [7:0] data);
    frame     <= {1'b1, data, 1'b0};
    frame_bit <= 0;
    bit_cycle <= 0;
    rxd       <= 1'b0;
  endtask

  task automatic drive_frame_bit(output logic done);
    done = 1'b0;
    rxd <= frame[frame_bit];
    if (bit_cycle == ClksPerBit - 1) begin
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
    rst_n       = 1'b0;
    obi_req     = idle_req();
    rxd         = 1'b1;
    cycle_count = 0;
    step        = 0;
    frame_bit   = 0;
    bit_cycle   = 0;
    wait_count  = 0;
    frame       = '1;
  end

  always_ff @(negedge clk) begin
    logic frame_done;

    cycle_count <= cycle_count + 1;
    obi_req <= idle_req();
    frame_done = 1'b0;

    if (cycle_count == 4) begin
      rst_n <= 1'b1;
    end

    if (rst_n) begin
      unique case (step)
        0: begin
          obi_req <= bus_write(REG_LCR, LCR_DLAB);
          step <= step + 1;
        end
        1: begin
          obi_req <= bus_write(REG_RHR_THR_DLL, 8'h02); // Divisor 2: 32 clk per UART bit.
          step <= step + 1;
        end
        2: begin
          obi_req <= bus_write(REG_IER_DLM, 8'h00);
          step <= step + 1;
        end
        3: begin
          obi_req <= bus_write(REG_LCR, LCR_8N1);
          step <= step + 1;
        end
        4: begin
          obi_req <= bus_write(REG_IER_DLM, 8'h01); // Enable received-data interrupt.
          step <= step + 1;
        end
        5: begin
          if (wait_count == 64) begin
            wait_count <= 0;
            start_frame(8'h5a);
            step <= step + 1;
          end else begin
            wait_count <= wait_count + 1;
          end
        end
        6: begin
          drive_frame_bit(frame_done);
          if (frame_done) begin
            step <= step + 1;
          end
        end
        7: begin
          if (wait_count == 16) begin
            wait_count <= 0;
            obi_req <= bus_read(REG_LSR);
            step <= step + 1;
          end else begin
            wait_count <= wait_count + 1;
          end
        end
        8: begin
          if (obi_rsp.r.rdata[0]) begin
            expect_rsp_mask(8'h61, 8'h61); // DR and reset-time THRE/TEMT are set.
            assert (irq && !irq_n)
              else $fatal(1, "IRQ did not assert with received data");
            obi_req <= bus_read(REG_IIR_FCR);
            step <= step + 1;
          end else begin
            if (wait_count == 16) begin
              wait_count <= 0;
              obi_req <= bus_read(REG_LSR);
            end else begin
              wait_count <= wait_count + 1;
            end
          end
        end
        9: begin
          expect_rsp(8'h04); // RDA interrupt with FIFO disabled.
          obi_req <= bus_read(REG_RHR_THR_DLL);
          step <= step + 1;
        end
        10: begin
          expect_rsp(8'h5a);
          obi_req <= bus_read(REG_LSR);
          step <= step + 1;
        end
        11: begin
          expect_rsp_mask(8'h01, 8'h00); // RHR read cleared DR.
          obi_req <= bus_read(REG_IIR_FCR);
          step <= step + 1;
        end
        12: begin
          expect_rsp(8'h01);
          assert (!irq && irq_n)
            else $fatal(1, "IRQ did not clear after RHR read");
          $display("obi_uart top-level RX/IRQ smoke passed");
          $finish;
        end
        default: begin
          $fatal(1, "Unexpected top-level RX step %0d", step);
        end
      endcase
    end

    if (cycle_count == 800) begin
      $fatal(1, "Timed out in top-level RX smoke at step %0d", step);
    end
  end
endmodule
