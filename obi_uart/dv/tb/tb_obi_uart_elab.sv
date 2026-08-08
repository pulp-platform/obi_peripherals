// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "obi/typedef.svh"

module tb_obi_uart_elab (
  input  logic clk,
  input  logic rst_n,
  input  logic rxd,
  input  logic cts_n,
  input  logic dsr_n,
  input  logic ri_n,
  input  logic cd_n,
  output logic irq,
  output logic irq_n,
  output logic txd,
  output logic rts_n,
  output logic dtr_n,
  output logic out1_n,
  output logic out2_n
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

  uart_obi_req_t obi_req;
  uart_obi_rsp_t obi_rsp;

  assign obi_req = '0;

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
endmodule
