// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Hannah Pochert  <hpochert@ethz.ch>
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

/// Calculated interrupts and stores them until reset by hardware or by reading the ISR register
module obi_uart_interrupts import obi_uart_pkg::*; #()
(
  input logic  clk_i,
  input logic  rst_ni,

  input  logic rx_fifo_trigger,
  input  logic rx_timeout,

  output logic irq_o,
  output logic irq_no,

  input  reg_read_t   reg_read_i,
  input  reg_write_t  reg_write_i,
  output isr_bits_t   reg_isr_o
);


  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Instantiations //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  //--Interrupt-Control-Signals-------------------------------------------------------------------
  typedef struct packed {
    logic       rls;       // Receive Line Status Interrupt - Error notification
    logic       rxdr;      // Receiver Data Ready
    logic       timeout;   // Reception Timeout
    logic       thr_empty; // THR Empty Interrupt - Data can't be written
    logic       mstat;     // Modem Status Interrupt - Changes in Modem Line
  } reg_intrpt_t;

  reg_intrpt_t intrpt_reg_d, intrpt_reg_q;
  logic        thr_blocked_d, thr_blocked_q;

  // Current-cycle producer indications are distinct from retained register
  // levels.  This distinction gives read-clear operations set/new-event
  // dominance when a new character/error/modem transition arrives together
  // with the read.
  logic rls_new_event;
  logic rda_new_event;
  logic msi_new_event;
  logic thr_new_high;
  logic thr_new_low;
  logic thr_reported;


  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Generate Interrupt Signals //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : interrupt_next
    rls_new_event = (reg_write_i.rx.overrun_valid && reg_write_i.rx.overrun) |
      (reg_write_i.rx.par_valid && reg_write_i.rx.par_err) |
      (reg_write_i.rx.frame_valid && reg_write_i.rx.frame_err) |
      (reg_write_i.rx.break_valid && reg_write_i.rx.break_ind);
    rda_new_event = reg_write_i.rx.dr_valid && reg_write_i.rx.data_ready;
    msi_new_event = reg_write_i.modem.d_cts | reg_write_i.modem.d_dsr |
      reg_write_i.modem.te_ri | reg_write_i.modem.d_cd;
    thr_new_high  = reg_write_i.tx.thr_valid && reg_write_i.tx.thr_empty;
    thr_new_low   = reg_write_i.tx.thr_valid && !reg_write_i.tx.thr_empty;

    // IIR acknowledgement is qualified by the source actually reported.  A
    // read while RLS/RDA/MSI has higher priority must not acknowledge THRI.
    thr_reported = reg_read_i.obi_read_isr && !reg_isr_o.status &&
      (reg_isr_o.id == 3'b001);

    intrpt_reg_d = intrpt_reg_q;

    //--Receive-Line-Status-Interrupt-------------------------------------------------------------
    if (!reg_read_i.ier.rlstat) begin
      intrpt_reg_d.rls = 1'b0;
    end else begin
      if (reg_read_i.obi_read_lsr)
        intrpt_reg_d.rls = 1'b0;
      else if (reg_read_i.lsr.overrun | reg_read_i.lsr.par_err |
               reg_read_i.lsr.frame_err | reg_read_i.lsr.break_ind)
        intrpt_reg_d.rls = 1'b1;
      if (rls_new_event)
        intrpt_reg_d.rls = 1'b1;
    end

    //--Receive-Data-Ready-Interrupt--------------------------------------------------------------
    if (!reg_read_i.ier.dtr) begin
      intrpt_reg_d.rxdr = 1'b0;
    end else if (reg_read_i.fcr.fifo_en) begin
      // FIFO RDA is a level interrupt: it remains asserted while the trigger
      // level is met and clears naturally once a read drops below it.
      intrpt_reg_d.rxdr = rx_fifo_trigger;
    end else begin
      if (reg_read_i.obi_read_rhr)
        intrpt_reg_d.rxdr = 1'b0;
      else if (reg_read_i.lsr.data_ready)
        intrpt_reg_d.rxdr = 1'b1;
      if (rda_new_event)
        intrpt_reg_d.rxdr = 1'b1;
    end

    //--Character-Timeout-Interrupt---------------------------------------------------------------
    if (!reg_read_i.fcr.fifo_en || !reg_read_i.ier.dtr) begin
      intrpt_reg_d.timeout = 1'b0;
    end else if (reg_read_i.obi_read_rhr) begin
      // The timeout counter is restarted by an RHR/FIFO read.  Preserve only
      // a genuinely new assertion that was not already latched.
      intrpt_reg_d.timeout = rx_timeout && !intrpt_reg_q.timeout;
    end else begin
      // Unlike sticky RLS/MSI causes, timeout is a FIFO level indication.
      intrpt_reg_d.timeout = rx_timeout;
    end

    //--THR-Empty-Interrupt-----------------------------------------------------------------------
    if (!reg_read_i.ier.thr_empty) begin
      intrpt_reg_d.thr_empty = 1'b0;
    end else begin
      if (reg_read_i.obi_write_thr || thr_reported)
        intrpt_reg_d.thr_empty = 1'b0;
      if (!thr_reported && !thr_blocked_q &&
          (reg_read_i.lsr.thr_empty || thr_new_high))
        intrpt_reg_d.thr_empty = 1'b1;
      if (thr_new_low)
        intrpt_reg_d.thr_empty = 1'b0;
    end

    //--Modem-Status-Interrupt--------------------------------------------------------------------
    if (!reg_read_i.ier.mstat) begin
      intrpt_reg_d.mstat = 1'b0;
    end else begin
      if (reg_read_i.obi_read_msr)
        intrpt_reg_d.mstat = 1'b0;
      else if (reg_read_i.msr.d_cts | reg_read_i.msr.d_dsr |
               reg_read_i.msr.te_ri | reg_read_i.msr.d_cd)
        intrpt_reg_d.mstat = 1'b1;
      if (msi_new_event)
        intrpt_reg_d.mstat = 1'b1;
    end

    // THRI is blocked after an acknowledged IIR report while THRE remains
    // high.  A drop, THR write, or IER disable re-arms it.
    thr_blocked_d = thr_blocked_q;
    if (!reg_read_i.ier.thr_empty || reg_read_i.obi_write_thr || thr_new_low)
      thr_blocked_d = 1'b0;
    else if (thr_reported)
      thr_blocked_d = 1'b1;
  end


  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Setting ID & Status Bits //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : interrupt_decode
    //--Defaults----------------------------------------------------------------------------------
    reg_isr_o.id       = 3'b000;
    reg_isr_o.fifos_en = reg_read_i.fcr.fifo_en ? 2'b11 : 2'b00;
    reg_isr_o.unused4  = 1'b0;
    reg_isr_o.unused5  = 1'b0;

    reg_isr_o.status   = ~( |intrpt_reg_q );  // 0: interrupt present; 1: no interrupt

    //--Priority-Encoder--------------------------------------------------------------------------
    // 1. Priority Level
    if (intrpt_reg_q.rls) begin
      reg_isr_o.id     = 3'b011;
    // 2. Priority Level
    end else if (intrpt_reg_q.rxdr) begin
      reg_isr_o.id     = 3'b010;
    // 2. Priority Level
    end else if (intrpt_reg_q.timeout) begin
      reg_isr_o.id     = 3'b110;
    // 3. Priority Level
    end else if (intrpt_reg_q.thr_empty) begin
      reg_isr_o.id     = 3'b001;
    // 4. Priority Level
    end else if (intrpt_reg_q.mstat) begin
      reg_isr_o.id     = 3'b000;
    end

  end

    //////////////////////////////////////////////////////////////////////////////////////////////
    // Direct Output Interrupt - Alert the CPU //
    //////////////////////////////////////////////////////////////////////////////////////////////

    // Once high stays high until interrupt condition is removed
    assign irq_o  = ~reg_isr_o.status;
    assign irq_no = reg_isr_o.status;

    `FF(intrpt_reg_q, intrpt_reg_d, '0, clk_i, rst_ni)
    `FF(thr_blocked_q, thr_blocked_d, 1'b0, clk_i, rst_ni)

endmodule
