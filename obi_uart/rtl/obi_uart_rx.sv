// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Hannah Pochert  <hpochert@ethz.ch>
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>

`include "common_cells/registers.svh"

module obi_uart_rx import obi_uart_pkg::*; #()
(
  input logic  clk_i,
  input logic  rst_ni,

  input logic  oversample_rate_edge_i,
  input logic  baud_rate_edge_i,

  input logic  rxd_i,

  output logic trigger_o,
  output logic timeout_o,

  input  reg_read_t     reg_read_i,
  output rx_reg_write_t reg_write_o
);

  //--Timing--------------------------------------------------------------------------------------
  logic timing_bit_center_q, timing_bit_center_d;
  logic timing_bit_center_edge;
  logic timing_clear;
  logic timing_init_clear;
  logic timing_load;
  logic [4:0] timing_offset;
  logic [4:0] timing_count;

  //--Synchronization-Signals---------------------------------------------------------------------
  logic sync_rxd;

  //--Majority-Filter-Signals---------------------------------------------------------------------
  logic [1:0] high_count_q, high_count_d;
  logic filtered_rxd_q, filtered_rxd_d;

  //--FIFO-signals--------------------------------------------------------------------------------
  logic fifo_clear;
  logic fifo_full;
  logic fifo_empty;
  logic [3:0] fifo_usage;
  // fifo_v3.usage_o is only four bits wide and wraps when its depth is full.
  // Keep a widened count for the software-visible receive storage, which also
  // includes the byte prefetched into RHR.
  logic [4:0] fifo_occupied;
  logic [4:0] rx_occupied;
  logic [10:0] fifo_data_i;
  logic [10:0] fifo_data_o;
  logic fifo_push;
  logic fifo_pop;
  // FIFO Write
  logic break_interrupt;
  logic [3:0] fifo_error_index_q, fifo_error_index_d;
  // FIFO trigger
  logic [3:0] tl_characters;
  // FIFO timeout
  // longest character: 1 start, 8 data, 1 parity, 2 stop -> 12bit
  // timeout occurs after 4 characters -> 48bit -> $clog2(48) = 6
  logic [3:0] character_length;
  logic [5:0] timeout_level;
  logic [5:0] timeout_count_q, timeout_count_d;

  //--Write-Read-FIFO-or-Write-RHR----------------------------------------------------------------
  logic rhr_full_q, rhr_full_d;

  //--Statemachine-Transition-Signals-------------------------------------------------------------
  state_type_rx_e state_q, state_d;
  logic rsr_finish;
  logic par_finish;
  logic stop_finish;
  logic write_init;

  //--Statemachine-RSR-Signals--------------------------------------------------------------------
  logic [7:0] rsr_q, rsr_d;
  logic [2:0] bitcount_q, bitcount_d; // Count up to character_len
  logic [2:0] word_len_bits;          // 5-8 Bits

  //--Statemachine-Error-Signals------------------------------------------------------------------
  // Parity Check
  logic parity_err_q, parity_err_d;
  logic data_parity;
  // Stop Bit Check
  logic framing_err_q, framing_err_d;
  logic break_q, break_d;

  rx_reg_write_t reg_write_read_clear;
  rx_reg_write_t reg_write_rhr;
  rx_reg_write_t reg_write_fifo;
  rx_reg_write_t reg_write_after_read_clear;
  rx_reg_write_t reg_write_after_rhr;

  logic rhr_full_read_valid;
  logic rhr_full_read_value;
  logic rhr_full_rhr_valid;
  logic rhr_full_rhr_value;
  logic rhr_full_after_read_clear;
  logic rhr_full_after_rhr;

  logic fifo_error_index_rhr_valid;
  logic [3:0] fifo_error_index_rhr;
  logic fifo_error_index_fifo_valid;
  logic [3:0] fifo_error_index_fifo;
  logic [3:0] fifo_error_index_after_rhr;

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Timing //
  ////////////////////////////////////////////////////////////////////////////////////////////////

  //----------------------------------------------------------------------------------------------
  // Counter Instantiation
  //----------------------------------------------------------------------------------------------

  //--Clear-Counter-------------------------------------------------------------------------------
  assign timing_clear = ((timing_count == 5'b01111) && oversample_rate_edge_i)
                        | (timing_init_clear) ? 1'b1 : 1'b0;

  counter #(
    .WIDTH          (5),
    .STICKY_OVERFLOW(0)
  ) i_counter (
    .clk_i,
    .rst_ni,
    .clear_i   (timing_clear),         // Synchronous clear: Sets Counter 0 in the next cycle
    .en_i      (oversample_rate_edge_i),
    .load_i    (timing_load),
    .down_i    (1'b0),                 // Always count upwards
    .d_i       (timing_offset),
    .q_o       (timing_count),
    .overflow_o()
  );

  //----------------------------------------------------------------------------------------------
  // Timing Bit Center
  //----------------------------------------------------------------------------------------------
  // Is high for one oversample_rate cycle
  assign timing_bit_center_d    = (timing_count == 5'b01000) ? 1'b1 : 1'b0;
  // Edge is high for one clk_i cycle
  assign timing_bit_center_edge = (timing_bit_center_d & ~timing_bit_center_q) ? 1'b1 : 1'b0;

  `FF(timing_bit_center_q, timing_bit_center_d, '0, clk_i, rst_ni)

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Input Stages //
  ////////////////////////////////////////////////////////////////////////////////////////////////

  //----------------------------------------------------------------------------------------------
  // 2-Stage Input Synchronization
  //----------------------------------------------------------------------------------------------
  sync #(
    .STAGES (NrSyncStages)
  ) i_sync (
    .clk_i,
    .rst_ni,
    .serial_i(rxd_i),
    .serial_o(sync_rxd)
  );

  //----------------------------------------------------------------------------------------------
  // 3-Sample Majority Filter
  //----------------------------------------------------------------------------------------------
  // The Majority Filter takes 3 samples and sets filtered_rxd high if at least 2 of them are high

  always_comb begin : rx_majority_filter_comb

    high_count_d = high_count_q;
    filtered_rxd_d = filtered_rxd_q;

    // no timing lock yet, use as last sync_rxd value
    if( (state_q == RXIDLE) || (state_q == RXRESYNCHRONIZE) ) begin
      filtered_rxd_d = sync_rxd;
    end

    if (timing_count == 5'b00100) begin // Start reset in cycle 5: "Majority Init"
      high_count_d = 2'b00;
    end else if (oversample_rate_edge_i) begin
      if (sync_rxd & (timing_count < 5'b00111)) begin // Take samples in Cycle 6, 7, 8
        high_count_d = high_count_q + 1;
      end else if (timing_count == 5'b00111) begin // filtered_rxd is set for Oversample Cycle 8
        if ((high_count_q == 2'b10) | (high_count_q == 2'b11) ) begin
          filtered_rxd_d = 1'b1;
        end else begin
          filtered_rxd_d = 1'b0;
        end
      end
    end

  end

  `FF(high_count_q, high_count_d, '0, clk_i, rst_ni)
  `FF(filtered_rxd_q, filtered_rxd_d, 1'b1, clk_i, rst_ni)

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // FIFO Instantiation//
  ////////////////////////////////////////////////////////////////////////////////////////////////

  fifo_v3 # (
    .FALL_THROUGH(),
    .DATA_WIDTH  (11),
    .DEPTH       (16),
    .dtype       (),
    .ADDR_DEPTH  ()  // DO NOT OVERWRITE THIS PARAMETER
  ) i_fifo_v3 (
    .clk_i,                   // Clock
    .rst_ni,                  // Asynchronous reset active low
    .flush_i   (fifo_clear),  // flush the queue
    .testmode_i(1'b0),
    // status flags
    .full_o    (fifo_full),   // queue is full
    .empty_o   (fifo_empty),  // queue is empty
    .usage_o   (fifo_usage),  // fill pointer
    // as long as the queue is not full we can push new data
    .data_i    (fifo_data_i), // data to push into the queue
    .push_i    (fifo_push),   // data is valid and can be pushed to the queue
    // as long as the queue is not empty we can pop new elements
    .data_o    (fifo_data_o), // output data
    .pop_i     (fifo_pop)     // pop head from queue
  );

  assign fifo_occupied = fifo_full ? 5'd16 : {1'b0, fifo_usage};
  assign rx_occupied   = fifo_occupied + {{4{1'b0}}, rhr_full_q};

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Decode Logic //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : rx_decode_comb
    unique case (reg_read_i.lcr.word_len)
      2'b00: word_len_bits = 3'b100; // 5 bits, last index in RSR.
      2'b01: word_len_bits = 3'b101; // 6 bits.
      2'b10: word_len_bits = 3'b110; // 7 bits.
      2'b11: word_len_bits = 3'b111; // 8 bits.
      default: word_len_bits = 3'b111;
    endcase

    unique case (reg_read_i.fcr.rx_fifo_tl)
      2'b00: tl_characters = 4'b0001; // 1 character.
      2'b01: tl_characters = 4'b0100; // 4 characters.
      2'b10: tl_characters = 4'b1000; // 8 characters.
      2'b11: tl_characters = 4'b1110; // 14 characters.
      default: tl_characters = 4'b0001;
    endcase

    // One start bit, the programmed data bits, optional parity, and the
    // selected stop time.  word_len_bits is the last data-bit index, so add
    // three for the data-bit count, start bit, and mandatory stop bit.
    character_length = 4'd3 + {1'b0, word_len_bits} + {3'b000, reg_read_i.lcr.par_en} +
                       {3'b000, reg_read_i.lcr.stop_bits};
    timeout_level    = ({2'b00, character_length} << 2);
    // For a five-bit word, LCR.stop_bits selects a 1.5-bit stop.  Keep the
    // half-bit in quarter-bit units so four character times are integral.
    if ((word_len_bits == 3'b100) && reg_read_i.lcr.stop_bits) begin
      timeout_level = timeout_level - 6'd2;
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // RX State Machine Logic //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : rx_fsm_comb
    state_d       = state_q;
    rsr_d         = rsr_q;
    bitcount_d    = bitcount_q;
    parity_err_d  = parity_err_q;
    framing_err_d = framing_err_q;
    break_d       = break_q;

    rsr_finish  = 1'b0;
    par_finish  = 1'b0;
    stop_finish = 1'b0;
    write_init  = 1'b0;

    data_parity = 1'b0;

    timing_init_clear = 1'b0;
    timing_load       = 1'b0;
    timing_offset     = 5'b00000;

    if (state_q == RXDATA) begin
      if (timing_bit_center_edge & (bitcount_q <= word_len_bits)) begin
        rsr_d[bitcount_q] = filtered_rxd_q;
        bitcount_d        = bitcount_q + 1;
        if (bitcount_q == word_len_bits) begin
          rsr_finish = 1'b1;
        end
      end
    end

    if (state_q == RXPAR) begin
      parity_err_d = 1'b0;
      data_parity  = ^rsr_q;

      if (timing_bit_center_edge) begin
        unique case (reg_read_i.lcr[5:4])
          2'b00: parity_err_d = (data_parity == filtered_rxd_q); // Odd parity.
          2'b01: parity_err_d = (data_parity != filtered_rxd_q); // Even parity.
          2'b10: parity_err_d = ~filtered_rxd_q;                 // Forced 1.
          2'b11: parity_err_d = filtered_rxd_q;                  // Forced 0.
          default: parity_err_d = 1'b0;
        endcase
        break_d      = ~filtered_rxd_q;
        par_finish   = 1'b1;
      end
    end

    if (state_q == RXSTOP) begin
      framing_err_d = 1'b0;
      if (timing_bit_center_edge) begin
        break_d     = ~filtered_rxd_q & (break_q | ~reg_read_i.lcr.par_en);
        write_init  = 1'b1;
        stop_finish = 1'b1;
        framing_err_d = !filtered_rxd_q;
      end
    end

    unique case(state_q)
      RXIDLE: begin
        if (filtered_rxd_q & ~sync_rxd) begin
          state_d = RXSTART;
          if (oversample_rate_edge_i) begin
            timing_load   = 1'b1;
            timing_offset = 5'b00010;
          end
        end
        timing_init_clear = 1'b1;
      end

      RXSTART: begin
        if (timing_bit_center_edge) begin
          if (~filtered_rxd_q) begin
            bitcount_d = 3'b000;
            rsr_d      = '0;
            state_d    = RXDATA;
          end else begin
            state_d = RXIDLE;
          end
        end
      end

      RXDATA: begin
        if (rsr_finish) begin
          state_d = reg_read_i.lcr.par_en ? RXPAR : RXSTOP;
        end
      end

      RXPAR: begin
        if (par_finish) begin
          state_d = RXSTOP;
        end
      end

      RXSTOP: begin
        if (stop_finish) begin
          state_d = framing_err_d ? RXRESYNCHRONIZE : RXIDLE;
        end
      end

      RXRESYNCHRONIZE: begin
        state_d = (filtered_rxd_q & ~sync_rxd) ? RXSTART : RXIDLE;
      end

      default: state_d = RXIDLE;
    endcase

    // Character is all zeros, parity and stop indicate break, current line is still 0.
    break_interrupt = (rsr_q == '0) & (break_q | break_d) & (~filtered_rxd_q);
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // RHR and LSR Read/Clear Logic //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : rx_read_clear_comb
    reg_write_read_clear = '0;
    rhr_full_read_valid  = 1'b0;
    rhr_full_read_value  = rhr_full_q;

    if (reg_read_i.obi_read_rhr) begin
      reg_write_read_clear.rhr        = '0;
      reg_write_read_clear.rhr_valid  = 1'b1;
      reg_write_read_clear.data_ready = 1'b0;
      reg_write_read_clear.dr_valid   = 1'b1;
      rhr_full_read_valid             = 1'b1;
      rhr_full_read_value             = 1'b0;
    end

    if (reg_read_i.obi_read_lsr) begin
      reg_write_read_clear.overrun   = 1'b0;
      reg_write_read_clear.par_err   = 1'b0;
      reg_write_read_clear.frame_err = 1'b0;
      reg_write_read_clear.break_ind = 1'b0;
      // LSR_BRK_ERROR_BITS are read-to-clear.  The subsequent apply stages
      // (RHR fill, then FIFO/producers) intentionally override these values,
      // so a character/error completed in the same cycle wins over the clear.
      reg_write_read_clear.overrun_valid = 1'b1;
      reg_write_read_clear.par_valid     = 1'b1;
      reg_write_read_clear.frame_valid   = 1'b1;
      reg_write_read_clear.break_valid   = 1'b1;

      if (fifo_error_index_q == 4'b0000) begin
        reg_write_read_clear.fifo_err       = 1'b0;
        reg_write_read_clear.fifo_err_valid = 1'b1;
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // RHR Fill Logic //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : rx_rhr_fill_comb
    reg_write_rhr             = '0;
    fifo_pop                  = 1'b0;
    rhr_full_rhr_valid        = 1'b0;
    rhr_full_rhr_value        = rhr_full_q;
    fifo_error_index_rhr      = fifo_error_index_q;
    fifo_error_index_rhr_valid = 1'b0;

    if (reg_read_i.fcr.fifo_en) begin
      reg_write_rhr.dr_valid   = 1'b1;
      reg_write_rhr.data_ready = write_init | ~fifo_empty | rhr_full_q;

      if ((~rhr_full_q) & (~fifo_empty)) begin
        reg_write_rhr.rhr         = fifo_data_o[7:0];
        reg_write_rhr.rhr_valid   = 1'b1;
        reg_write_rhr.data_ready  = 1'b1;
        reg_write_rhr.break_ind   = fifo_data_o[8];
        reg_write_rhr.frame_err   = fifo_data_o[9];
        reg_write_rhr.par_err     = fifo_data_o[10];
        reg_write_rhr.break_valid = 1'b1;
        reg_write_rhr.frame_valid = 1'b1;
        reg_write_rhr.par_valid   = 1'b1;

        fifo_pop           = 1'b1;
        rhr_full_rhr_valid = 1'b1;
        rhr_full_rhr_value = 1'b1;

        if (4'b0000 != fifo_error_index_q) begin
          fifo_error_index_rhr       = fifo_error_index_q - 4'b0001;
          fifo_error_index_rhr_valid = 1'b1;
        end
      end

    end else if (write_init) begin
      if (rhr_full_q) begin
        reg_write_rhr.overrun       = 1'b1;
        reg_write_rhr.overrun_valid = 1'b1;
      end

      reg_write_rhr.rhr          = rsr_q;
      reg_write_rhr.rhr_valid    = 1'b1;
      reg_write_rhr.data_ready   = 1'b1;
      reg_write_rhr.dr_valid     = 1'b1;
      reg_write_rhr.par_err      = parity_err_q;
      // RXSTOP computes the framing result in framing_err_d on the same
      // cycle that write_init publishes the character.
      reg_write_rhr.frame_err    = framing_err_d;
      reg_write_rhr.break_ind    = break_interrupt;
      reg_write_rhr.break_valid  = 1'b1;
      reg_write_rhr.par_valid    = 1'b1;
      reg_write_rhr.frame_valid  = 1'b1;

      rhr_full_rhr_valid = 1'b1;
      rhr_full_rhr_value = 1'b1;
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // FIFO and Timeout Logic //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : rx_fifo_timeout_comb
    reg_write_fifo              = '0;
    fifo_clear                  = 1'b1;
    fifo_push                   = 1'b0;
    fifo_data_i                 = '0;
    trigger_o                   = 1'b0;
    timeout_o                   = 1'b0;
    timeout_count_d             = timeout_count_q;
    fifo_error_index_fifo       = fifo_error_index_q;
    fifo_error_index_fifo_valid = 1'b0;

    if (reg_read_i.fcr.fifo_en) begin
      fifo_clear = 1'b0;

      if (reg_read_i.fcr.rx_fifo_rst) begin
        fifo_clear = 1'b1;
        reg_write_fifo.fifo_rst       = 1'b0;
        reg_write_fifo.fifo_rst_valid = 1'b1;
        // Resetting the RX FIFO also removes the byte prefetched into RHR and
        // its associated line-status error bits.  OE is intentionally not
        // touched here; it remains read-to-clear through LSR.
        reg_write_fifo.rhr          = '0;
        reg_write_fifo.rhr_valid    = 1'b1;
        reg_write_fifo.data_ready   = 1'b0;
        reg_write_fifo.dr_valid     = 1'b1;
        reg_write_fifo.fifo_err       = 1'b0;
        reg_write_fifo.fifo_err_valid = 1'b1;
        reg_write_fifo.par_err      = 1'b0;
        reg_write_fifo.par_valid    = 1'b1;
        reg_write_fifo.frame_err    = 1'b0;
        reg_write_fifo.frame_valid  = 1'b1;
        reg_write_fifo.break_ind    = 1'b0;
        reg_write_fifo.break_valid  = 1'b1;
        timeout_count_d             = '0;
      end else begin
        if ({1'b0, tl_characters} <= rx_occupied) begin
          trigger_o = 1'b1;
        end

        if (write_init) begin
          // The 16-byte FIFO capacity includes the byte currently exposed in
          // RHR.  A simultaneous RHR read frees that slot for the newly
          // completed character when RHR was full.
          if ((rx_occupied < 5'd16) ||
              ((rx_occupied == 5'd16) && rhr_full_q && reg_read_i.obi_read_rhr)) begin
            fifo_push   = 1'b1;
            fifo_data_i = {parity_err_q, framing_err_d, break_interrupt, rsr_q};

            if (parity_err_q | framing_err_d | break_interrupt) begin
              fifo_error_index_fifo       = fifo_usage;
              fifo_error_index_fifo_valid = 1'b1;
              reg_write_fifo.fifo_err       = 1'b1;
              reg_write_fifo.fifo_err_valid = 1'b1;
            end
          end else begin
            reg_write_fifo.overrun       = 1'b1;
            reg_write_fifo.overrun_valid = 1'b1;
          end
        end

        if (reg_read_i.obi_read_rhr | write_init) begin
          timeout_count_d = '0;
        end else if (~fifo_empty | rhr_full_q) begin
          if (timeout_count_q == timeout_level) begin
            timeout_o       = 1'b1;
            timeout_count_d = timeout_count_q;
          end else if (baud_rate_edge_i) begin
            timeout_count_d = timeout_count_q + 1;
          end
        end
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // RX Read/Clear Write Apply Logic //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : rx_apply_read_clear_comb
    reg_write_after_read_clear = '0;
    rhr_full_after_read_clear  = rhr_full_q;

    if (reg_write_read_clear.rhr_valid) begin
      reg_write_after_read_clear.rhr       = reg_write_read_clear.rhr;
      reg_write_after_read_clear.rhr_valid = 1'b1;
    end
    if (reg_write_read_clear.fifo_rst_valid) begin
      reg_write_after_read_clear.fifo_rst       = reg_write_read_clear.fifo_rst;
      reg_write_after_read_clear.fifo_rst_valid = 1'b1;
    end
    if (reg_write_read_clear.fifo_err_valid) begin
      reg_write_after_read_clear.fifo_err       = reg_write_read_clear.fifo_err;
      reg_write_after_read_clear.fifo_err_valid = 1'b1;
    end
    if (reg_write_read_clear.dr_valid) begin
      reg_write_after_read_clear.data_ready = reg_write_read_clear.data_ready;
      reg_write_after_read_clear.dr_valid   = 1'b1;
    end
    if (reg_write_read_clear.overrun_valid) begin
      reg_write_after_read_clear.overrun       = reg_write_read_clear.overrun;
      reg_write_after_read_clear.overrun_valid = 1'b1;
    end
    if (reg_write_read_clear.par_valid) begin
      reg_write_after_read_clear.par_err   = reg_write_read_clear.par_err;
      reg_write_after_read_clear.par_valid = 1'b1;
    end
    if (reg_write_read_clear.frame_valid) begin
      reg_write_after_read_clear.frame_err   = reg_write_read_clear.frame_err;
      reg_write_after_read_clear.frame_valid = 1'b1;
    end
    if (reg_write_read_clear.break_valid) begin
      reg_write_after_read_clear.break_ind   = reg_write_read_clear.break_ind;
      reg_write_after_read_clear.break_valid = 1'b1;
    end
    if (rhr_full_read_valid) begin
      rhr_full_after_read_clear = rhr_full_read_value;
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // RX RHR Write Apply Logic //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : rx_apply_rhr_comb
    reg_write_after_rhr       = reg_write_after_read_clear;
    rhr_full_after_rhr        = rhr_full_after_read_clear;
    fifo_error_index_after_rhr = fifo_error_index_q;

    if (reg_write_rhr.rhr_valid) begin
      reg_write_after_rhr.rhr       = reg_write_rhr.rhr;
      reg_write_after_rhr.rhr_valid = 1'b1;
    end
    if (reg_write_rhr.fifo_rst_valid) begin
      reg_write_after_rhr.fifo_rst       = reg_write_rhr.fifo_rst;
      reg_write_after_rhr.fifo_rst_valid = 1'b1;
    end
    if (reg_write_rhr.fifo_err_valid) begin
      reg_write_after_rhr.fifo_err       = reg_write_rhr.fifo_err;
      reg_write_after_rhr.fifo_err_valid = 1'b1;
    end
    if (reg_write_rhr.dr_valid) begin
      reg_write_after_rhr.data_ready = reg_write_rhr.data_ready;
      reg_write_after_rhr.dr_valid   = 1'b1;
    end
    if (reg_write_rhr.overrun_valid) begin
      reg_write_after_rhr.overrun       = reg_write_rhr.overrun;
      reg_write_after_rhr.overrun_valid = 1'b1;
    end
    if (reg_write_rhr.par_valid) begin
      reg_write_after_rhr.par_err   = reg_write_rhr.par_err;
      reg_write_after_rhr.par_valid = 1'b1;
    end
    if (reg_write_rhr.frame_valid) begin
      reg_write_after_rhr.frame_err   = reg_write_rhr.frame_err;
      reg_write_after_rhr.frame_valid = 1'b1;
    end
    if (reg_write_rhr.break_valid) begin
      reg_write_after_rhr.break_ind   = reg_write_rhr.break_ind;
      reg_write_after_rhr.break_valid = 1'b1;
    end
    if (rhr_full_rhr_valid) begin
      rhr_full_after_rhr = rhr_full_rhr_value;
    end
    if (fifo_error_index_rhr_valid) begin
      fifo_error_index_after_rhr = fifo_error_index_rhr;
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // RX FIFO Write Apply Logic //
  ////////////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin : rx_apply_fifo_comb
    reg_write_o        = reg_write_after_rhr;
    rhr_full_d         = rhr_full_after_rhr;
    fifo_error_index_d = fifo_error_index_after_rhr;

    if (reg_write_fifo.rhr_valid) begin
      reg_write_o.rhr       = reg_write_fifo.rhr;
      reg_write_o.rhr_valid = 1'b1;
    end
    if (reg_write_fifo.fifo_rst_valid) begin
      reg_write_o.fifo_rst       = reg_write_fifo.fifo_rst;
      reg_write_o.fifo_rst_valid = 1'b1;
    end
    if (reg_write_fifo.fifo_err_valid) begin
      reg_write_o.fifo_err       = reg_write_fifo.fifo_err;
      reg_write_o.fifo_err_valid = 1'b1;
    end
    if (reg_write_fifo.dr_valid) begin
      reg_write_o.data_ready = reg_write_fifo.data_ready;
      reg_write_o.dr_valid   = 1'b1;
    end
    if (reg_write_fifo.overrun_valid) begin
      reg_write_o.overrun       = reg_write_fifo.overrun;
      reg_write_o.overrun_valid = 1'b1;
    end
    if (reg_write_fifo.par_valid) begin
      reg_write_o.par_err   = reg_write_fifo.par_err;
      reg_write_o.par_valid = 1'b1;
    end
    if (reg_write_fifo.frame_valid) begin
      reg_write_o.frame_err   = reg_write_fifo.frame_err;
      reg_write_o.frame_valid = 1'b1;
    end
    if (reg_write_fifo.break_valid) begin
      reg_write_o.break_ind   = reg_write_fifo.break_ind;
      reg_write_o.break_valid = 1'b1;
    end
    if (fifo_error_index_fifo_valid) begin
      fifo_error_index_d = fifo_error_index_fifo;
    end

    if (reg_read_i.fcr.fifo_en && reg_read_i.fcr.rx_fifo_rst) begin
      rhr_full_d         = 1'b0;
      fifo_error_index_d = '0;
    end
  end

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // FIFO & WRITE RHR Sequential //
  ////////////////////////////////////////////////////////////////////////////////////////////////

  //--FIFO----------------------------------------------------------------------------------------
  `FF(fifo_error_index_q, fifo_error_index_d, '0, clk_i, rst_ni)
  `FF(timeout_count_q, timeout_count_d, '0, clk_i, rst_ni)

  //--Write-RHR-----------------------------------------------------------------------------------
  `FF(rhr_full_q, rhr_full_d, '0, clk_i, rst_ni)

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Statemachine Sequential//
  ////////////////////////////////////////////////////////////////////////////////////////////////

  //--Statelogic----------------------------------------------------------------------------------
  `FF(state_q, state_d, RXIDLE, clk_i, rst_ni)

  //--RSR-----------------------------------------------------------------------------------------
  `FF(rsr_q, rsr_d, '0, clk_i, rst_ni)
  `FF(bitcount_q, bitcount_d, '0, clk_i, rst_ni)

  //--Parity--------------------------------------------------------------------------------------
  `FF(parity_err_q, parity_err_d, '0, clk_i, rst_ni)

  //--Stop----------------------------------------------------------------------------------------
  `FF(framing_err_q, framing_err_d, '0, clk_i, rst_ni)

  //--Break-Interrupt-----------------------------------------------------------------------------
  `FF(break_q, break_d, '0, clk_i, rst_ni)

endmodule
