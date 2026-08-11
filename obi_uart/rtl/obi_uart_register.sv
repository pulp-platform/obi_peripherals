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
  // OBI preparations
  ////////////////////////////////////////////////////////////////////////////////////////////////

  logic [ObiCfg.DataWidth-1:0] rsp_data;
  logic                        valid_d, valid_q;
  logic                        err;
  logic                        w_err_d, w_err_q;
  logic [AddressBits-1:0]      word_addr_d, word_addr_q;
  logic [ObiCfg.IdWidth-1:0]   id_d, id_q;
  logic                        we_d, we_q;
  logic                        req_d, req_q;

  assign id_d        = obi_req_i.a.aid;
  assign valid_d     = obi_req_i.req;
  assign word_addr_d = obi_req_i.a.addr[AddressOffset+:AddressBits];
  assign we_d        = obi_req_i.a.we;
  assign req_d       = obi_req_i.req;

  `FF(id_q,        id_d,        '0, clk_i, rst_ni)
  `FF(valid_q,     valid_d,     '0, clk_i, rst_ni)
  `FF(word_addr_q, word_addr_d, '0, clk_i, rst_ni)
  `FF(we_q,        we_d,        '0, clk_i, rst_ni)
  `FF(w_err_q,     w_err_d,     '0, clk_i, rst_ni)
  `FF(req_q,       req_d,       '0, clk_i, rst_ni)

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Registers
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

  // Hardware updates are collected before software accesses are applied. This
  // preserves the original priority when a response-phase read clears a field.
  uart_reg_fields_t new_reg;

  always_comb begin : hw_update
    new_reg = '0;
    new_reg.RHR = rhr_q;
    new_reg.THR = thr_q;
    new_reg.IER = ier_q;
    new_reg.FCR = fcr_q;
    new_reg.LCR = lcr_q;
    new_reg.MCR = mcr_q;
    new_reg.LSR = lsr_q;
    new_reg.MSR = msr_q;
    new_reg.DLL = dll_q;
    new_reg.DLM = dlm_q;

    new_reg.FCR.rx_fifo_rst = reg_write_i.rx.fifo_rst_valid ?
                              reg_write_i.rx.fifo_rst : fcr_q.rx_fifo_rst;
    new_reg.FCR.tx_fifo_rst = reg_write_i.tx.fifo_rst_valid ?
                              reg_write_i.tx.fifo_rst : fcr_q.tx_fifo_rst;

    new_reg.RHR = reg_write_i.rx.rhr_valid ? reg_write_i.rx.rhr : rhr_q;

    new_reg.LSR.fifo_err   = reg_write_i.rx.fifo_err_valid ? reg_write_i.rx.fifo_err : lsr_q.fifo_err;
    new_reg.LSR.tx_empty   = reg_write_i.tx.empty_valid    ? reg_write_i.tx.tx_empty : lsr_q.tx_empty;
    new_reg.LSR.thr_empty  = reg_write_i.tx.thr_valid      ? reg_write_i.tx.thr_empty : lsr_q.thr_empty;
    new_reg.LSR.break_ind  = reg_write_i.rx.break_valid    ? reg_write_i.rx.break_ind : lsr_q.break_ind;
    new_reg.LSR.frame_err  = reg_write_i.rx.frame_valid    ? reg_write_i.rx.frame_err : lsr_q.frame_err;
    new_reg.LSR.par_err    = reg_write_i.rx.par_valid      ? reg_write_i.rx.par_err : lsr_q.par_err;
    new_reg.LSR.data_ready = reg_write_i.rx.dr_valid       ? reg_write_i.rx.data_ready : lsr_q.data_ready;
    new_reg.LSR.overrun    = reg_write_i.rx.overrun_valid  ? reg_write_i.rx.overrun : lsr_q.overrun;

    new_reg.MSR.cd    = reg_write_i.modem.cd;
    new_reg.MSR.ri    = reg_write_i.modem.ri;
    new_reg.MSR.dsr   = reg_write_i.modem.dsr;
    new_reg.MSR.cts   = reg_write_i.modem.cts;
    new_reg.MSR.d_cd  = msr_q.d_cd  | reg_write_i.modem.d_cd;
    new_reg.MSR.te_ri = msr_q.te_ri | reg_write_i.modem.te_ri;
    new_reg.MSR.d_dsr = msr_q.d_dsr | reg_write_i.modem.d_dsr;
    new_reg.MSR.d_cts = msr_q.d_cts | reg_write_i.modem.d_cts;
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Register read interface
  ////////////////////////////////////////////////////////////////////////////////////////////////

  logic obi_read_rhr;
  logic obi_read_isr;
  logic obi_read_lsr;
  logic obi_write_thr;
  logic obi_write_dllm;

  always_comb begin : reg_read
    reg_read_o              = '0;
    reg_read_o.thr          = thr_q;
    reg_read_o.ier          = ier_q;
    reg_read_o.isr          = reg_write_i.isr;
    reg_read_o.fcr          = fcr_q;
    reg_read_o.lcr          = lcr_q;
    reg_read_o.mcr          = mcr_q;
    reg_read_o.dll          = dll_q;
    reg_read_o.dlm          = dlm_q;
    reg_read_o.obi_read_rhr = obi_read_rhr;
    reg_read_o.obi_read_isr = obi_read_isr;
    reg_read_o.obi_read_lsr = obi_read_lsr;
    // MSR reads never generated a side-effect pulse in the original register file.
    reg_read_o.obi_read_msr = 1'b0;
    reg_read_o.obi_write_thr = obi_write_thr;
    reg_read_o.obi_write_dllm = obi_write_dllm;
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Software register accesses
  ////////////////////////////////////////////////////////////////////////////////////////////////

  always_comb begin : sw_update
    err     = w_err_q;
    w_err_d = 1'b0;

    obi_read_rhr   = 1'b0;
    obi_read_isr   = 1'b0;
    obi_read_lsr   = 1'b0;
    obi_write_thr  = 1'b0;
    obi_write_dllm = 1'b0;

    rsp_data = '0;

    rhr_d = new_reg.RHR;
    thr_d = new_reg.THR;
    ier_d = new_reg.IER;
    fcr_d = new_reg.FCR;
    lcr_d = new_reg.LCR;
    mcr_d = new_reg.MCR;
    lsr_d = new_reg.LSR;
    msr_d = new_reg.MSR;
    dll_d = new_reg.DLL;
    dlm_d = new_reg.DLM;

    // OBI writes use only the low byte. Invalid byte enables do not generate
    // an error, matching the original register interface.
    if (obi_req_i.req && obi_req_i.a.we && obi_req_i.a.be[0]) begin
      if (!lcr_q.dlab) begin
        unique case (word_addr_d)
          RegAddrTHR: begin
            thr_d = obi_req_i.a.wdata[RegWidth-1:0];
            obi_write_thr = 1'b1;
          end
          RegAddrIER: ier_d = obi_req_i.a.wdata[RegWidth-1:0];
          RegAddrFCR: fcr_d = obi_req_i.a.wdata[RegWidth-1:0];
          RegAddrLCR: lcr_d = obi_req_i.a.wdata[RegWidth-1:0];
          RegAddrMCR: mcr_d = obi_req_i.a.wdata[RegWidth-1:0];
          RegAddrSPR: ; // Scratch register is not implemented.
          default: w_err_d = 1'b1;
        endcase
      end else begin
        unique case (word_addr_d)
          RegAddrDLL: begin
            dll_d = obi_req_i.a.wdata[RegWidth-1:0];
            obi_write_dllm = 1'b1;
          end
          RegAddrDLM: begin
            dlm_d = obi_req_i.a.wdata[RegWidth-1:0];
            obi_write_dllm = 1'b1;
          end
          RegAddrFCR: fcr_d = obi_req_i.a.wdata[RegWidth-1:0];
          RegAddrLCR: lcr_d = obi_req_i.a.wdata[RegWidth-1:0];
          RegAddrMCR: mcr_d = obi_req_i.a.wdata[RegWidth-1:0];
          RegAddrSPR: ; // Scratch register is not implemented.
          default: w_err_d = 1'b1;
        endcase
      end
    end

    // Response-phase reads use the current LCR value. This intentionally does
    // not capture DLAB with the request because an intervening write is visible
    // during the response phase in the original implementation.
    if (req_q && !we_q) begin
      err = 1'b0;
      if (!lcr_q.dlab) begin
        unique case (word_addr_q)
          RegAddrRHR: begin
            rsp_data[RegWidth-1:0] = rhr_q;
            obi_read_rhr = 1'b1;
          end
          RegAddrIER: rsp_data[RegWidth-1:0] = ier_q;
          RegAddrISR: begin
            rsp_data[RegWidth-1:0] = reg_write_i.isr;
            obi_read_isr = 1'b1;
          end
          RegAddrLCR: rsp_data[RegWidth-1:0] = lcr_q;
          RegAddrMCR: rsp_data[RegWidth-1:0] = mcr_q;
          RegAddrLSR: begin
            rsp_data[RegWidth-1:0] = lsr_q;
            obi_read_lsr = 1'b1;
          end
          RegAddrMSR: begin
            rsp_data[RegWidth-1:0] = msr_q;
            msr_d = reg_write_i.modem;
          end
          RegAddrSPR: rsp_data[RegWidth-1:0] = '0;
          default: err = 1'b1;
        endcase
      end else begin
        unique case (word_addr_q)
          RegAddrDLL: rsp_data[RegWidth-1:0] = dll_q;
          RegAddrDLM: rsp_data[RegWidth-1:0] = dlm_q;
          default: err = 1'b1;
        endcase
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // OBI response
  ////////////////////////////////////////////////////////////////////////////////////////////////

  always_comb begin : obi_response
    obi_rsp_o         = '0;
    obi_rsp_o.r.rdata = rsp_data;
    obi_rsp_o.r.rid   = id_q;
    obi_rsp_o.r.err   = err;
    obi_rsp_o.gnt     = obi_req_i.req;
    obi_rsp_o.rvalid  = valid_q;
  end

endmodule
