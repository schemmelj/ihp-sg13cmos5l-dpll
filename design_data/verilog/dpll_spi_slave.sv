// ==============================================================================
// File: testchip/rtl/dpll_spi_slave.sv
// Description: Synthesizable Asynchronous SPI Slave Controller for IHP 130nm
//              SG13G2 DPLL Testchip (SPI Mode 0: CPOL=0, CPHA=0, MSB-first).
//
//              Supported Transactions (MSB-first, SPI Mode 0):
//                1) 64-Bit Core Burst Write / 96-Bit Extended Full-Chip Burst Write
//                   (Header = 8'hFF):
//                   Bits loaded on 64th rising edge of spi_sck:
//                     [63:56] = 8'hFF (Burst Write Command)
//                     [55:40] = otw_nominal[15:0]
//                     [39:30] = div_n[9:0] (25..500 for 1..10 MHz ref_clk -> 250..500 MHz DCO)
//                     [29:24] = kp_mult[5:0]
//                     [23:20] = ki_mult[3:0]
//                     [19:16] = ki_shift[3:0]
//                     [15]    = fast_lock_en
//                     [14:12] = fast_lock_mult[2:0]
//                     [11:4]  = gear_shift_thresh[7:0]
//                     [3]     = integrator_freeze
//                     [2]     = integrator_rst
//                     [1]     = clr_lock
//                     [0]     = out_mul2_en (1 = Enable 2x XOR output frequency multiplier)
//                   Optional 32-bit extension loaded on 96th rising edge of spi_sck:
//                     [31]    = out_div_bypass
//                     [30:26] = out_prescale_shift[4:0] (S = 0..20 -> 2^S)
//                     [25:16] = out_div_int[9:0]        (M_int = 1..1023)
//                     [15:8]  = out_duty[7:0]           (1..255, 128 = 50.0% duty)
//                     [7:0]   = out_div_frac[7:0]       (F_frac = 0..255 -> F/256)
//
//                2) 24-Bit Single-Register Write / Readback:
//                   [23]    = 1'b1 (Write) / 1'b0 (Read)
//                   [22:16] = 7-bit Register Address:
//                             7'h00 : REG_OTW_NOM   -> otw_nominal[15:0]
//                             7'h01 : REG_DIV_CTRL  -> {2'b0, out_mul2_en, integrator_rst, integrator_freeze, clr_lock, div_n[9:0]}
//                             7'h02 : REG_LOOP_GAIN -> {2'b0, ki_shift[3:0], ki_mult[3:0], kp_mult[5:0]}
//                             7'h03 : REG_GEAR_CFG  -> {4'b0, fast_lock_en, fast_lock_mult[2:0], gear_shift_thresh[7:0]}
//                             7'h04 : REG_STATUS    -> {5'h15, locked, div_n[9:0]} (Read-only)
//                             7'h05 : REG_OUT_DIV1  -> {out_div_bypass, out_prescale_shift[4:0], out_div_int[9:0]}
//                             7'h06 : REG_OUT_DIV2  -> {out_duty[7:0], out_div_frac[7:0]}
//                             7'h07 : REG_FB_FRAC   -> {7'd0, out_mul2_en, fb_frac[7:0]}
//                             7'h08 : REG_OTW_CUR   -> otw_mon[15:0] (Read-only live closed-loop OTW)
//                   [15:0]  = 16-bit Register Data
// ==============================================================================

`timescale 1ps / 1fs

module dpll_spi_slave #(
  parameter int OTW_WIDTH = 16,
  parameter int DIV_WIDTH = 10
)(
  input  logic                 clk,                // Buffered 1..10 MHz ref_clk (used only for clr_lock CDC pulse)
  input  logic                 rst_n,              // Active-low asynchronous system reset

  // External Asynchronous SPI Pad Interface (via sg13cmos5l_io pads, SPI Mode 0)
  input  logic                 spi_cs_n,           // Active-low SPI Chip Select
  input  logic                 spi_sck,            // Asynchronous SPI Serial Clock
  input  logic                 spi_mosi,           // SPI Master-Out Slave-In
  output logic                 spi_miso,           // SPI Master-In Slave-Out

  // DPLL Status Inputs for SPI Readback
  input  logic                 locked,             // Current DPLL Lock Detector status
  input  logic [OTW_WIDTH-1:0] otw_mon = 16'hE900, // Live closed-loop Oscillator Control Word (OTW)

  // Programmable Core DPLL Parameters
  output logic [OTW_WIDTH-1:0] otw_nominal,        // 16-bit Center Oscillator Tuning Word (for 250-500 MHz DCO)
  output logic [DIV_WIDTH-1:0] div_n,              // 10-bit Feedback Divider Ratio (25..500 for 1..10 MHz ref_clk)
  output logic [7:0]           fb_frac,            // 8-bit Fractional Feedback Numerator (0..255 -> F/256)
  output logic [5:0]           kp_mult,            // 6-bit Proportional Gain Multiplier
  output logic [3:0]           ki_mult,            // 4-bit Integral Gain Multiplier
  output logic [3:0]           ki_shift,           // 4-bit Integral Gain Shift
  output logic                 fast_lock_en,       // 1-bit Adaptive Gear-Shifting Enable
  output logic [2:0]           fast_lock_mult,     // 3-bit Acquisition Gain Boost Factor
  output logic [7:0]           gear_shift_thresh,  // 8-bit Fine Mode Phase Error Threshold
  output logic                 integrator_freeze,  // 1-bit Freeze Integrator Accumulator
  output logic                 integrator_rst,     // 1-bit Reset Integrator Accumulator
  output logic                 clr_lock,           // 1-bit Control-Domain Lock Clear Pulse

  // Programmable Output Fractional-N Divider, Duty-Cycle & 2x XOR Multiplier Parameters
  output logic                 out_div_bypass,     // 1-bit Direct 250-500 MHz Output Bypass
  output logic                 out_mul2_en,        // 1-bit 2x XOR Output Clock Multiplier Enable
  output logic [4:0]           out_prescale_shift, // 5-bit Binary Octave Prescaler S (0..20 -> 2^S)
  output logic [9:0]           out_div_int,        // 10-bit Output Divider Mantissa M_int (1..1023)
  output logic [7:0]           out_div_frac,       // 8-bit Output Divider Fractional Numerator F_frac (0..255)
  output logic [7:0]           out_duty            // 8-bit Output Duty-Cycle Word (1..255, 128 = 50.0%)
);

  // Frame-scoped active-low reset for the 7-bit SPI bit counter (cleared when CS_N=1 or RST_N=0)
  wire spi_frame_rst_n = rst_n & ~spi_cs_n;

  // SPI clock domain (spi_sck) shift registers, bit counter, and lock-clear toggle
  logic [63:0] shift_in_reg;
  logic [23:0] shift_out_reg;
  logic [6:0]  bit_cnt;
  logic        burst_ext_arm;
  logic        clr_lock_sw;
  logic        clr_toggle_sck;

  // Reference clock domain (clk) CDC synchronizer for automatic lock-clear pulse
  logic        clr_sync1, clr_sync2, clr_sync3;
  logic [1:0]  auto_clr_cnt;

  // Next shifted word and bit count on rising edge of spi_sck
  wire [63:0] next_shift_in = {shift_in_reg[62:0], spi_mosi};
  wire [6:0]  next_bit_cnt  = bit_cnt + 7'd1;

  // Readback mux for 24-bit register reads (loaded on the 8th rising edge of spi_sck)
  logic [15:0] read_data_mux;
  always_comb begin
    case (next_shift_in[6:0])
      7'h00:   read_data_mux = otw_nominal;
      7'h01:   read_data_mux = {2'b00, out_mul2_en, integrator_rst, integrator_freeze, clr_lock, div_n};
      7'h02:   read_data_mux = {2'b00, ki_shift, ki_mult, kp_mult};
      7'h03:   read_data_mux = {4'b0000, fast_lock_en, fast_lock_mult, gear_shift_thresh};
      7'h05:   read_data_mux = {out_div_bypass, out_prescale_shift, out_div_int};
      7'h06:   read_data_mux = {out_duty, out_div_frac};
      7'h07:   read_data_mux = {7'h00, out_mul2_en, fb_frac};
      7'h08:   read_data_mux = otw_mon;
      default: read_data_mux = {5'h15, locked, div_n};
    endcase
  end

  assign spi_miso = shift_out_reg[23];
  assign clr_lock = clr_lock_sw | (clr_sync1 != clr_sync2) | (clr_sync2 != clr_sync3) | (auto_clr_cnt != 2'b00);

  // ----------------------------------------------------------------------------
  // 1. Frame Bit Counter (Clocked by spi_sck, Asynchronously Cleared by CS_N=1)
  // ----------------------------------------------------------------------------
  always_ff @(posedge spi_sck or negedge spi_frame_rst_n) begin
    if (!spi_frame_rst_n) begin
      bit_cnt       <= 7'd0;
      burst_ext_arm <= 1'b0;
    end else begin
      bit_cnt <= next_bit_cnt;
      if (next_bit_cnt == 7'd64 && next_shift_in[63:56] == 8'hFF) begin
        burst_ext_arm <= 1'b1;
      end
    end
  end

  // ----------------------------------------------------------------------------
  // 2. Asynchronous SPI Shift Registers & Configuration Bank (Clocked by spi_sck)
  // ----------------------------------------------------------------------------
  always_ff @(posedge spi_sck or negedge rst_n) begin
    if (!rst_n) begin
      shift_in_reg       <= 64'd0;
      shift_out_reg      <= 24'hA50064;
      clr_lock_sw        <= 1'b0;
      clr_toggle_sck     <= 1'b0;

      // Calibrated Power-On Reset Defaults:
      // - 500.0 MHz DCO nominal (otw_nominal = 16'hE900 = 59648)
      // - 5.0 MHz reference clock (div_n = 100, fb_frac = 0 -> 500 MHz / 100 = 5.0 MHz)
      // - 50.0 MHz output clock (out_div_int = 10, out_div_frac = 0, out_duty = 128 = 50%, out_mul2_en = 0)
      otw_nominal        <= 16'hE900;
      div_n              <= 10'd100;
      fb_frac            <= 8'd0;
      kp_mult            <= 6'd8;
      ki_mult            <= 4'd1;
      ki_shift           <= 4'd1;
      fast_lock_en       <= 1'b1;
      fast_lock_mult     <= 3'd2;
      gear_shift_thresh  <= 8'd48;
      integrator_freeze  <= 1'b0;
      integrator_rst     <= 1'b0;
      out_div_bypass     <= 1'b0;
      out_mul2_en        <= 1'b0;
      out_prescale_shift <= 5'd0;
      out_div_int        <= 10'd10;
      out_div_frac       <= 8'd0;
      out_duty           <= 8'd128;
    end else if (!spi_cs_n) begin
      shift_in_reg <= next_shift_in;

      // Load addressed 16-bit register into shift_out_reg on 8th rising edge for Read (MSB=0)
      if (next_bit_cnt == 7'd8 && !next_shift_in[7]) begin
        shift_out_reg <= {read_data_mux, locked, div_n[6:0]};
      end else begin
        shift_out_reg <= {shift_out_reg[22:0], locked};
      end

      // Commit 64-Bit Core Burst Write on 64th rising edge of spi_sck
      if (next_bit_cnt == 7'd64 && next_shift_in[63:56] == 8'hFF) begin
        otw_nominal       <= next_shift_in[55:40];
        div_n             <= next_shift_in[39:30];
        kp_mult           <= next_shift_in[29:24];
        ki_mult           <= next_shift_in[23:20];
        ki_shift          <= next_shift_in[19:16];
        fast_lock_en      <= next_shift_in[15];
        fast_lock_mult    <= next_shift_in[14:12];
        gear_shift_thresh <= next_shift_in[11:4];
        integrator_freeze <= next_shift_in[3];
        integrator_rst    <= next_shift_in[2];
        clr_lock_sw       <= next_shift_in[1];
        out_mul2_en       <= next_shift_in[0];
        if (clr_toggle_sck == clr_sync2) begin
          clr_toggle_sck  <= ~clr_toggle_sck;
        end
      end else if (next_bit_cnt == 7'd96 && burst_ext_arm) begin
        // Commit 96-Bit Extended Burst Write (Output Fractional-N Divider & Duty Cycle)
        out_div_bypass     <= next_shift_in[31];
        out_prescale_shift <= next_shift_in[30:26];
        out_div_int        <= next_shift_in[25:16];
        out_duty           <= next_shift_in[15:8];
        out_div_frac       <= next_shift_in[7:0];
      end else if (next_bit_cnt == 7'd24 && next_shift_in[23] && (next_shift_in[22:16] != 7'h7F)) begin
        // Commit 24-Bit Single-Register Write on 24th rising edge of spi_sck
        case (next_shift_in[22:16])
          7'h00: begin
            otw_nominal <= next_shift_in[15:0];
            if (clr_toggle_sck == clr_sync2) begin
              clr_toggle_sck <= ~clr_toggle_sck;
            end
          end
          7'h01: begin
            div_n             <= next_shift_in[9:0];
            clr_lock_sw       <= next_shift_in[10];
            integrator_freeze <= next_shift_in[11];
            integrator_rst    <= next_shift_in[12];
            out_mul2_en       <= next_shift_in[13];
            if (clr_toggle_sck == clr_sync2) begin
              clr_toggle_sck  <= ~clr_toggle_sck;
            end
          end
          7'h02: begin
            kp_mult  <= next_shift_in[5:0];
            ki_mult  <= next_shift_in[9:6];
            ki_shift <= next_shift_in[13:10];
          end
          7'h03: begin
            gear_shift_thresh <= next_shift_in[7:0];
            fast_lock_mult    <= next_shift_in[10:8];
            fast_lock_en      <= next_shift_in[11];
          end
          7'h05: begin
            out_div_int        <= next_shift_in[9:0];
            out_prescale_shift <= next_shift_in[14:10];
            out_div_bypass     <= next_shift_in[15];
          end
          7'h06: begin
            out_div_frac <= next_shift_in[7:0];
            out_duty     <= next_shift_in[15:8];
          end
          7'h07: begin
            fb_frac     <= next_shift_in[7:0];
            out_mul2_en <= next_shift_in[8];
            if (clr_toggle_sck == clr_sync2) begin
              clr_toggle_sck <= ~clr_toggle_sck;
            end
          end
          default: ;
        endcase
      end
    end
  end

  // ----------------------------------------------------------------------------
  // 3. Reference-Clock CDC Synchronizer for Lock-Clear Pulse (clk domain)
  // ----------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      clr_sync1    <= 1'b0;
      clr_sync2    <= 1'b0;
      clr_sync3    <= 1'b0;
      auto_clr_cnt <= 2'd0;
    end else begin
      clr_sync1 <= clr_toggle_sck;
      clr_sync2 <= clr_sync1;
      clr_sync3 <= clr_sync2;

      if (clr_sync2 != clr_sync3) begin
        auto_clr_cnt <= 2'd2;
      end else if (auto_clr_cnt != 2'd0) begin
        auto_clr_cnt <= auto_clr_cnt - 2'd1;
      end
    end
  end

endmodule
