// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Hannah Pochert  <hpochert@ethz.ch>
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

module obi_uart_register import obi_uart_pkg::*; #(
  /// The OBI configuration connected to this peripheral.
  parameter obi_pkg::obi_cfg_t ObiCfg = obi_pkg::ObiDefaultConfig, // SbrObiCfg
  /// OBI request type
  parameter type obi_req_t = logic,
  /// OBI response type
  parameter type obi_rsp_t = logic
) (
  input logic clk_i,
  input logic rst_ni,

  // OBI request interface
  input obi_req_t  obi_req_i, // a.addr, a.we, a.be, a.wdata, a.aid, a.a_optional | rready, req
  // OBI response interface
  output obi_rsp_t obi_rsp_o, // r.rdata, r.rid, r.err, r.r_optional | gnt, rvalid

  output reg_read_t  reg_read_o,  // Current register values
  input  reg_write_t reg_write_i  // Internal updates to register values
);

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Registers //
  ////////////////////////////////////////////////////////////////////////////////////////////////

  rhr_bits_t rhr_d, rhr_q;
  thr_bits_t thr_d, thr_q;
  ier_bits_t ier_d, ier_q;
  fcr_bits_t fcr_d, fcr_q;
  lcr_bits_t lcr_d, lcr_q;
  mcr_bits_t mcr_d, mcr_q;
  lsr_bits_t lsr_d, lsr_q;
  msr_bits_t msr_d, msr_q;
  dll_bits_t dll_d, dll_q;
  dlm_bits_t dlm_d, dlm_q;

  `FF(rhr_q, rhr_d, obi_uart_pkg::RegResetVal.RHR, clk_i, rst_ni)
  `FF(thr_q, thr_d, obi_uart_pkg::RegResetVal.THR, clk_i, rst_ni)
  `FF(ier_q, ier_d, obi_uart_pkg::RegResetVal.IER, clk_i, rst_ni)
  `FF(fcr_q, fcr_d, obi_uart_pkg::RegResetVal.FCR, clk_i, rst_ni)
  `FF(lcr_q, lcr_d, obi_uart_pkg::RegResetVal.LCR, clk_i, rst_ni)
  `FF(mcr_q, mcr_d, obi_uart_pkg::RegResetVal.MCR, clk_i, rst_ni)
  `FF(lsr_q, lsr_d, obi_uart_pkg::RegResetVal.LSR, clk_i, rst_ni)
  `FF(msr_q, msr_d, obi_uart_pkg::RegResetVal.MSR, clk_i, rst_ni)
  `FF(dll_q, dll_d, obi_uart_pkg::RegResetVal.DLL, clk_i, rst_ni)
  `FF(dlm_q, dlm_d, obi_uart_pkg::RegResetVal.DLM, clk_i, rst_ni)

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // OBI A-Phase State //
  ////////////////////////////////////////////////////////////////////////////////////////////////

  localparam int unsigned ObiAddrWidth = $bits(obi_req_i.a.addr);
  localparam logic [ObiAddrWidth-1:0] UART_RHR_OFFSET_W = ObiAddrWidth'(UART_RHR_OFFSET);
  localparam logic [ObiAddrWidth-1:0] UART_THR_OFFSET_W = ObiAddrWidth'(UART_THR_OFFSET);
  localparam logic [ObiAddrWidth-1:0] UART_DLL_OFFSET_W = ObiAddrWidth'(UART_DLL_OFFSET);
  localparam logic [ObiAddrWidth-1:0] UART_IER_OFFSET_W = ObiAddrWidth'(UART_IER_OFFSET);
  localparam logic [ObiAddrWidth-1:0] UART_DLM_OFFSET_W = ObiAddrWidth'(UART_DLM_OFFSET);
  localparam logic [ObiAddrWidth-1:0] UART_ISR_OFFSET_W = ObiAddrWidth'(UART_ISR_OFFSET);
  localparam logic [ObiAddrWidth-1:0] UART_FCR_OFFSET_W = ObiAddrWidth'(UART_FCR_OFFSET);
  localparam logic [ObiAddrWidth-1:0] UART_LCR_OFFSET_W = ObiAddrWidth'(UART_LCR_OFFSET);
  localparam logic [ObiAddrWidth-1:0] UART_MCR_OFFSET_W = ObiAddrWidth'(UART_MCR_OFFSET);
  localparam logic [ObiAddrWidth-1:0] UART_LSR_OFFSET_W = ObiAddrWidth'(UART_LSR_OFFSET);
  localparam logic [ObiAddrWidth-1:0] UART_MSR_OFFSET_W = ObiAddrWidth'(UART_MSR_OFFSET);
  localparam logic [ObiAddrWidth-1:0] UART_SPR_OFFSET_W = ObiAddrWidth'(UART_SPR_OFFSET);

  logic                              req_q;
  logic                              we_q;
  logic                              be0_q;
  logic                              dlab_q;
  logic [$bits(obi_req_i.a.aid)-1:0] id_q;
  logic [ObiAddrWidth-1:0]            addr_q;
  logic [ObiAddrWidth-1:0]            addr_word;
  logic [ObiAddrWidth-1:0]            addr_word_q;
  logic                              addr_high_q;

  // Requests are decoded in the low internal window only.  Keep the high-address
  // indication with the A-phase state so that response timing remains unchanged.
  logic addr_high;
  assign addr_high = |(obi_req_i.a.addr >> IntAddrWidth);
  assign addr_word = {obi_req_i.a.addr[ObiAddrWidth-1:2], 2'b00};
  assign addr_word_q = {addr_q[ObiAddrWidth-1:2], 2'b00};

  `FF(req_q,  obi_req_i.req,                      '0, clk_i, rst_ni)
  `FF(we_q,   obi_req_i.a.we,                     '0, clk_i, rst_ni)
  `FF(be0_q,  obi_req_i.a.be[0],                  '0, clk_i, rst_ni)
  `FF(dlab_q, lcr_q.dlab,                         '0, clk_i, rst_ni)
  `FF(id_q,   obi_req_i.a.aid,                    '0, clk_i, rst_ni)
  `FF(addr_q, obi_req_i.a.addr,                  '0, clk_i, rst_ni)
  `FF(addr_high_q, addr_high,                    '0, clk_i, rst_ni)

  logic obi_read_rhr;
  logic obi_read_isr;
  logic obi_read_lsr;
  logic obi_read_msr;
  logic obi_write_thr;
  logic obi_write_dllm;

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Register Read Interface //
  ////////////////////////////////////////////////////////////////////////////////////////////////

  always_comb begin : reg_read
    reg_read_o                = '0;
    reg_read_o.thr            = thr_q;
    reg_read_o.ier            = ier_q;
    reg_read_o.isr            = '0;
    reg_read_o.fcr            = fcr_q;
    reg_read_o.lcr            = lcr_q;
    reg_read_o.mcr            = mcr_q;
    reg_read_o.lsr            = lsr_q;
    reg_read_o.msr            = msr_q;
    reg_read_o.dll            = dll_q;
    reg_read_o.dlm            = dlm_q;
    reg_read_o.obi_read_rhr   = obi_read_rhr;
    reg_read_o.obi_read_isr   = obi_read_isr;
    reg_read_o.obi_read_lsr   = obi_read_lsr;
    reg_read_o.obi_read_msr   = obi_read_msr;
    reg_read_o.obi_write_thr  = obi_write_thr;
    reg_read_o.obi_write_dllm = obi_write_dllm;
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Address Phase: Update Writable Registers //
  ////////////////////////////////////////////////////////////////////////////////////////////////

  always_comb begin : write_fsm
    rx_reg_write_t write_rx;
    tx_reg_write_t write_tx;

    write_rx = reg_write_i.rx;
    write_tx = reg_write_i.tx;

    obi_read_rhr   = 1'b0;
    obi_read_isr   = 1'b0;
    obi_read_lsr   = 1'b0;
    obi_read_msr   = 1'b0;
    obi_write_thr  = 1'b0;
    obi_write_dllm = 1'b0;

    rhr_d = rhr_q;
    thr_d = thr_q;
    ier_d = ier_q;
    fcr_d = fcr_q;
    lcr_d = lcr_q;
    mcr_d = mcr_q;
    lsr_d = lsr_q;
    msr_d = msr_q;
    dll_d = dll_q;
    dlm_d = dlm_q;

    // Internal hardware updates.
    fcr_d.rx_fifo_rst = write_rx.fifo_rst_valid ? write_rx.fifo_rst : fcr_q.rx_fifo_rst;
    fcr_d.tx_fifo_rst = write_tx.fifo_rst_valid ? write_tx.fifo_rst : fcr_q.tx_fifo_rst;

    rhr_d = write_rx.rhr_valid ? write_rx.rhr : rhr_q;

    lsr_d.fifo_err   = write_rx.fifo_err_valid ? write_rx.fifo_err   : lsr_q.fifo_err;
    lsr_d.tx_empty   = write_tx.empty_valid    ? write_tx.tx_empty   : lsr_q.tx_empty;
    lsr_d.thr_empty  = write_tx.thr_valid      ? write_tx.thr_empty  : lsr_q.thr_empty;
    lsr_d.break_ind  = write_rx.break_valid    ? write_rx.break_ind  : lsr_q.break_ind;
    lsr_d.frame_err  = write_rx.frame_valid    ? write_rx.frame_err  : lsr_q.frame_err;
    lsr_d.par_err    = write_rx.par_valid      ? write_rx.par_err    : lsr_q.par_err;
    lsr_d.data_ready = write_rx.dr_valid       ? write_rx.data_ready : lsr_q.data_ready;
    lsr_d.overrun    = write_rx.overrun_valid  ? write_rx.overrun    : lsr_q.overrun;

    msr_d.cd    = reg_write_i.modem.cd;
    msr_d.ri    = reg_write_i.modem.ri;
    msr_d.dsr   = reg_write_i.modem.dsr;
    msr_d.cts   = reg_write_i.modem.cts;
    msr_d.d_cd  = msr_q.d_cd  | reg_write_i.modem.d_cd;
    msr_d.te_ri = msr_q.te_ri | reg_write_i.modem.te_ri;
    msr_d.d_dsr = msr_q.d_dsr | reg_write_i.modem.d_dsr;
    msr_d.d_cts = msr_q.d_cts | reg_write_i.modem.d_cts;

    // Software writes. The UART only implements the low byte of each 32-bit OBI word.
    if (obi_req_i.req && obi_req_i.a.we && obi_req_i.a.be[0] && !addr_high) begin
      if (!lcr_q.dlab) begin
        unique case (addr_word)
          UART_THR_OFFSET_W: begin
            thr_d                    = obi_req_i.a.wdata[RegWidth-1:0];
            obi_write_thr            = 1'b1;
          end

          UART_IER_OFFSET_W: ier_d = obi_req_i.a.wdata[RegWidth-1:0];
          UART_FCR_OFFSET_W: fcr_d = obi_req_i.a.wdata[RegWidth-1:0];
          UART_LCR_OFFSET_W: lcr_d = obi_req_i.a.wdata[RegWidth-1:0];
          UART_MCR_OFFSET_W: mcr_d = obi_req_i.a.wdata[RegWidth-1:0];
          UART_SPR_OFFSET_W: ; // Scratch register is not implemented. Writes are ignored.
          default: ;
        endcase
      end else begin
        unique case (addr_word)
          UART_DLL_OFFSET_W: begin
            dll_d                     = obi_req_i.a.wdata[RegWidth-1:0];
            obi_write_dllm            = 1'b1;
          end

          UART_DLM_OFFSET_W: begin
            dlm_d                     = obi_req_i.a.wdata[RegWidth-1:0];
            obi_write_dllm            = 1'b1;
          end

          UART_FCR_OFFSET_W: fcr_d = obi_req_i.a.wdata[RegWidth-1:0];
          UART_LCR_OFFSET_W: lcr_d = obi_req_i.a.wdata[RegWidth-1:0];
          UART_MCR_OFFSET_W: mcr_d = obi_req_i.a.wdata[RegWidth-1:0];
          UART_SPR_OFFSET_W: ; // Scratch register is not implemented. Writes are ignored.
          default: ;
        endcase
      end
    end

    // Reads with side effects.
    if (req_q && !we_q && !addr_high_q) begin
      if (!dlab_q && (addr_word_q == UART_RHR_OFFSET_W)) begin
        obi_read_rhr = 1'b1;
      end

      if (addr_word_q == UART_ISR_OFFSET_W) begin
        obi_read_isr = 1'b1;
      end

      if (addr_word_q == UART_LSR_OFFSET_W) begin
        obi_read_lsr = 1'b1;
      end

      if (addr_word_q == UART_MSR_OFFSET_W) begin
        obi_read_msr = 1'b1;
        // Sticky delta bits are cleared by reading MSR, while the current
        // modem sample/delta remains visible if it changes in this cycle.
        msr_d = reg_write_i.modem;
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Response Phase: Read Data and Errors //
  ////////////////////////////////////////////////////////////////////////////////////////////////

  always_comb begin : obi_response
    obi_rsp_o        = '0;
    obi_rsp_o.gnt    = obi_req_i.req;
    obi_rsp_o.rvalid = req_q;
    obi_rsp_o.r.rid  = id_q;

    if (req_q) begin
      // Any address outside the low decode window is an OBI error,
      // irrespective of write byte enables.
      if (addr_high_q) begin
        obi_rsp_o.r.err = 1'b1;
      end else if (!we_q) begin
        // DLAB remaps only offsets 0 and 1.  The remaining UART registers
        // stay visible while the divisor latch is selected.
        unique case (addr_word_q)
          UART_RHR_OFFSET_W: begin
            if (dlab_q) begin
              obi_rsp_o.r.rdata[RegWidth-1:0] = dll_q;
            end else begin
              obi_rsp_o.r.rdata[RegWidth-1:0] = rhr_q;
            end
          end
          UART_IER_OFFSET_W: begin
            if (dlab_q) begin
              obi_rsp_o.r.rdata[RegWidth-1:0] = dlm_q;
            end else begin
              obi_rsp_o.r.rdata[RegWidth-1:0] = ier_q;
            end
          end
          UART_ISR_OFFSET_W: obi_rsp_o.r.rdata[RegWidth-1:0] = reg_write_i.isr;
          UART_LCR_OFFSET_W: obi_rsp_o.r.rdata[RegWidth-1:0] = lcr_q;
          UART_MCR_OFFSET_W: obi_rsp_o.r.rdata[RegWidth-1:0] = mcr_q;
          UART_LSR_OFFSET_W: obi_rsp_o.r.rdata[RegWidth-1:0] = lsr_q;
          UART_MSR_OFFSET_W: obi_rsp_o.r.rdata[RegWidth-1:0] = msr_q;
          UART_SPR_OFFSET_W: ; // Scratch register is not implemented. Reads return zero.
          default: obi_rsp_o.r.err = 1'b1;
        endcase
      end else if (be0_q) begin
        if (!dlab_q) begin
          unique case (addr_word_q)
            UART_THR_OFFSET_W,
            UART_IER_OFFSET_W,
            UART_FCR_OFFSET_W,
            UART_LCR_OFFSET_W,
            UART_MCR_OFFSET_W,
            UART_SPR_OFFSET_W: ;
            default: obi_rsp_o.r.err = 1'b1;
          endcase
        end else begin
          unique case (addr_word_q)
            UART_DLL_OFFSET_W,
            UART_DLM_OFFSET_W,
            UART_FCR_OFFSET_W,
            UART_LCR_OFFSET_W,
            UART_MCR_OFFSET_W,
            UART_SPR_OFFSET_W: ;
            default: obi_rsp_o.r.err = 1'b1;
          endcase
        end
      end
    end
  end

endmodule
