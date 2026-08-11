// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Hannah Pochert  <hpochert@ethz.ch>
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

module obi_uart_tx #()
(
  input logic  clk_i,
  input logic  rst_ni,

  input logic  baud_rate_edge_i,
  input logic  double_rate_edge_i,

  output logic txd_o,

  input obi_uart_pkg::reg_read_t      reg_read_i,
  output obi_uart_pkg::tx_reg_write_t reg_write_o
);

  // Import the UART package for definitions and parameters
  import obi_uart_pkg::*;

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Instantiations //
  ////////////////////////////////////////////////////////////////////////////////////////////////

  //--FIFO----------------------------------------------------------------------------------------
  logic fifo_clear;
  logic fifo_full;
  logic fifo_empty;
  logic [7:0] fifo_data_i;
  logic [7:0] fifo_data_o;
  logic fifo_push;
  logic fifo_pop;
  logic [3:0] fifo_usage;

  //--THR-Full------------------------------------------------------------------------------------
  logic thr_full_q, thr_full_d;

  //--Statemachine-Transition-Signals-------------------------------------------------------------
  state_type_tx_e state_q, state_d;

  logic [2:0] word_len_bits;
  logic [7:0] word_len_mask;

  //--Statemachine-TSR-Signals--------------------------------------------------------------------
  logic tsr_empty;
  logic tsr_finish;
  logic [7:0] tsr_q, tsr_d;
  logic [2:0] tsr_count_q, tsr_count_d;

  logic txd_q, txd_d;

  tx_reg_write_t reg_write_thr;
  tx_reg_write_t reg_write_status;
  tx_reg_write_t reg_write_after_thr;

  logic thr_full_write_valid;
  logic thr_full_write_value;
  logic thr_full_fsm_valid;
  logic thr_full_fsm_value;
  logic thr_full_fifo_valid;
  logic thr_full_fifo_value;
  logic thr_full_after_thr;
  logic thr_full_after_fsm;

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // FIFO Instantiation //
  ////////////////////////////////////////////////////////////////////////////////////////////////

  fifo_v3 # (
    .FALL_THROUGH(1'b0),
    .DATA_WIDTH  (8),
    .DEPTH       (16)
  ) i_fifo_v3 (
    .clk_i,
    .rst_ni,
    .flush_i   (fifo_clear),  // flush the queue
    .testmode_i(1'b0      ),
    // status flags
    .full_o    (fifo_full),   // queue is full
    .empty_o   (fifo_empty),  // queue is empty
    .usage_o   (fifo_usage),  // fill pointer
    // as long as the queue is not full we can push new data
    .data_i    (fifo_data_i), // data to push into the queue
    .push_i    (fifo_push  ), // data is valid and can be pushed to the queue
    // as long as the queue is not empty we can pop new elements
    .data_o    (fifo_data_o), // output data
    .pop_i     (fifo_pop   )  // pop head from queue
  );

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Decode Logic //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : tx_decode_comb
    unique case (reg_read_i.lcr.word_len)
      2'b00: begin
        word_len_bits = 3'b100; // 5 bits, last index in TSR.
        word_len_mask = 8'b0001_1111;
      end
      2'b01: begin
        word_len_bits = 3'b101; // 6 bits.
        word_len_mask = 8'b0011_1111;
      end
      2'b10: begin
        word_len_bits = 3'b110; // 7 bits.
        word_len_mask = 8'b0111_1111;
      end
      2'b11: begin
        word_len_bits = 3'b111; // 8 bits.
        word_len_mask = 8'b1111_1111;
      end
      default: begin
        word_len_bits = 3'b111;
        word_len_mask = 8'b1111_1111;
      end
    endcase
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // THR Write Status Logic //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : tx_thr_write_status_comb
    reg_write_thr         = '0;
    thr_full_write_valid  = 1'b0;
    thr_full_write_value  = thr_full_q;

    if (reg_read_i.obi_write_thr) begin
      reg_write_thr.thr_empty   = 1'b0;
      reg_write_thr.tx_empty    = 1'b0;
      reg_write_thr.thr_valid   = 1'b1;
      reg_write_thr.empty_valid = 1'b1;

      thr_full_write_valid = 1'b1;
      thr_full_write_value = 1'b1;
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // TX State Machine Logic //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : tx_fsm_comb
    state_d     = state_q;
    txd_o       = txd_q & ~reg_read_i.lcr.set_break;
    txd_d       = txd_q;
    fifo_pop    = 1'b0;
    tsr_d       = tsr_q;
    tsr_count_d = tsr_count_q;
    tsr_finish  = 1'b0;
    tsr_empty   = 1'b0;

    thr_full_fsm_valid = 1'b0;
    thr_full_fsm_value = thr_full_q;

    if (state_q == TXDATA & (tsr_count_q <= word_len_bits)) begin
      txd_d = tsr_q[tsr_count_q];
      if (baud_rate_edge_i) begin
        tsr_count_d = tsr_count_q + 1;
        tsr_finish  = (tsr_count_q == word_len_bits) ? 1'b1 : 1'b0;
      end
    end

    unique case(state_q)
      TXIDLE: begin
        txd_d       = 1'b1;
        tsr_d       = '0;
        tsr_count_d = '0;
        tsr_empty   = 1'b1;

        if (reg_read_i.fcr.fifo_en) begin
          if (~fifo_empty & baud_rate_edge_i) begin
            tsr_d    = fifo_data_o;
            fifo_pop = 1'b1;
            state_d  = TXSTART;
          end
        end else begin
          if (thr_full_q & baud_rate_edge_i) begin
            tsr_d                = reg_read_i.thr.char_tx & word_len_mask;
            state_d              = TXSTART;
            thr_full_fsm_valid   = 1'b1;
            thr_full_fsm_value   = 1'b0;
          end
        end
      end

      TXSTART: begin
        txd_d = 1'b0;
        if (baud_rate_edge_i) begin
          state_d = TXDATA;
        end
      end

      TXDATA: begin
        if (tsr_finish) begin
          state_d = reg_read_i.lcr.par_en ? TXPAR : TXSTOP1;
        end
      end

      TXPAR: begin
        unique case (reg_read_i.lcr[5:4])
          2'b00: txd_d = ~(^tsr_q); // Odd parity.
          2'b01: txd_d = ^tsr_q;    // Even parity.
          2'b10: txd_d = 1'b1;      // Forced 1.
          2'b11: txd_d = 1'b0;      // Forced 0.
          default: txd_d = 1'b0;
        endcase
        if (baud_rate_edge_i) begin
          state_d = TXSTOP1;
        end
      end

      TXSTOP1: begin
        txd_d = 1'b1;
        if (baud_rate_edge_i) begin
          if (reg_read_i.lcr.stop_bits) begin
            state_d = TXSTOP2;
          end else begin
            state_d = TXIDLE;
          end
        end
      end

      TXSTOP2: begin
        txd_d = 1'b1;
        if (word_len_bits == 3'b100) begin
          if (double_rate_edge_i) begin
            state_d = TXIDLE;
          end
        end else begin
          if (baud_rate_edge_i) begin
            state_d = TXIDLE;
          end
        end
      end

      default: state_d = TXIDLE;
    endcase
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // FIFO and Empty Status Logic //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : tx_fifo_status_comb
    reg_write_status    = '0;
    fifo_clear          = 1'b0;
    fifo_push           = 1'b0;
    fifo_data_i         = '0;
    thr_full_fifo_valid = 1'b0;
    thr_full_fifo_value = thr_full_q;

    if (reg_read_i.fcr.fifo_en) begin
      if (reg_read_i.fcr.tx_fifo_rst) begin
        fifo_clear = 1'b1;
        reg_write_status.fifo_rst       = 1'b0;
        reg_write_status.fifo_rst_valid = 1'b1;
      end

      if (thr_full_q & (~fifo_full)) begin
        fifo_push            = 1'b1;
        fifo_data_i          = reg_read_i.thr.char_tx & word_len_mask;
        thr_full_fifo_valid  = 1'b1;
        thr_full_fifo_value  = 1'b0;
      end

      // THRE describes the FIFO and holding register, while TEMT additionally
      // waits for the serializer to become idle.  A pending holding-register
      // byte is being moved into an empty FIFO when fifo_push is asserted, so
      // do not report either empty status for that cycle.
      if (fifo_empty && !thr_full_q && !reg_read_i.obi_write_thr && !fifo_push) begin
        reg_write_status.thr_empty = 1'b1;
        reg_write_status.thr_valid = 1'b1;
        if (tsr_empty) begin
          reg_write_status.tx_empty    = 1'b1;
          reg_write_status.empty_valid = 1'b1;
        end
      end

    end else begin
      fifo_clear = 1'b1;
      if (~thr_full_q && !reg_read_i.obi_write_thr) begin
        reg_write_status.thr_empty = 1'b1;
        reg_write_status.thr_valid = 1'b1;
        if (tsr_empty) begin
          reg_write_status.tx_empty    = 1'b1;
          reg_write_status.empty_valid = 1'b1;
        end
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // TX THR Write Apply Logic //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : tx_apply_thr_comb
    reg_write_after_thr = '0;
    thr_full_after_thr  = thr_full_q;

    if (reg_write_thr.fifo_rst_valid) begin
      reg_write_after_thr.fifo_rst       = reg_write_thr.fifo_rst;
      reg_write_after_thr.fifo_rst_valid = 1'b1;
    end
    if (reg_write_thr.empty_valid) begin
      reg_write_after_thr.tx_empty    = reg_write_thr.tx_empty;
      reg_write_after_thr.empty_valid = 1'b1;
    end
    if (reg_write_thr.thr_valid) begin
      reg_write_after_thr.thr_empty = reg_write_thr.thr_empty;
      reg_write_after_thr.thr_valid = 1'b1;
    end
    if (thr_full_write_valid) begin
      thr_full_after_thr = thr_full_write_value;
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // TX FSM THR-Full Apply Logic //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : tx_apply_fsm_comb
    thr_full_after_fsm = thr_full_after_thr;

    if (thr_full_fsm_valid) begin
      thr_full_after_fsm = thr_full_fsm_value;
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // TX Status Write Apply Logic //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : tx_apply_status_comb
    reg_write_o = reg_write_after_thr;
    thr_full_d  = thr_full_after_fsm;

    if (reg_write_status.fifo_rst_valid) begin
      reg_write_o.fifo_rst       = reg_write_status.fifo_rst;
      reg_write_o.fifo_rst_valid = 1'b1;
    end
    if (reg_write_status.empty_valid) begin
      reg_write_o.tx_empty    = reg_write_status.tx_empty;
      reg_write_o.empty_valid = 1'b1;
    end
    if (reg_write_status.thr_valid) begin
      reg_write_o.thr_empty = reg_write_status.thr_empty;
      reg_write_o.thr_valid = 1'b1;
    end
    if (thr_full_fifo_valid) begin
      thr_full_d = thr_full_fifo_value;
    end
    // A CPU write is the final arbitration winner.  This permits a new byte
    // to remain in the holding register while a previous byte is consumed or
    // pushed into the FIFO in the same cycle.
    if (reg_read_i.obi_write_thr) begin
      thr_full_d = 1'b1;
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Sequential //
  ////////////////////////////////////////////////////////////////////////////////////////////////

  `FF(thr_full_q, thr_full_d, '0, clk_i, rst_ni)

  `FF(tsr_q, tsr_d, '0, clk_i, rst_ni)
  `FF(tsr_count_q, tsr_count_d, '0, clk_i, rst_ni)

  `FF(txd_q, txd_d, '1, clk_i, rst_ni)

  `FF(state_q, state_d, TXIDLE, clk_i, rst_ni)

endmodule
