// ==============================================================================
// File: testchip/rtl/dpll_spi_slave.sv
// Description: Synthesizable Asynchronous SPI Slave Controller for IHP 130nm
//              SG13G2 DPLL Testchip (SPI Mode 0: CPOL=0, CPHA=0, MSB-first).
//
//              Architecture:
//                - The SPI shift register (shift_in_reg, shift_out_reg), bit
//                  counter (bit_cnt), and configuration register bank are
//                  clocked directly by the external SPI clock (spi_sck) and
//                  framed by active-low chip select (spi_cs_n), completely
//                  independent of ref_clk (clk).
//                - SPI register writes and readbacks operate at any spi_sck
//                  frequency (even when ref_clk is absent or stopped).
//                - A closed-loop 3-stage CDC toggle synchronizer transfers
//                  lock-clear requests into the 1.0 MHz ref_clk domain to
//                  generate a clean synchronous 2-cycle clr_lock pulse for
//                  the hardware lock detector.
//
//              Supported Transactions (MSB-first, SPI Mode 0):
//                1) 64-Bit Full-Parameter Atomic Burst Write (Header = 8'hFF):
//                   [63:56] = 8'hFF (Burst Write Command)
//                   [55:40] = otw_nominal[15:0]
//                   [39:32] = div_n[7:0]
//                   [31:26] = kp_mult[5:0]
//                   [25:22] = ki_mult[3:0]
//                   [21:18] = ki_shift[3:0]
//                   [17]    = fast_lock_en
//                   [16:14] = fast_lock_mult[2:0]
//                   [13:6]  = gear_shift_thresh[7:0]
//                   [5]     = integrator_freeze
//                   [4]     = integrator_rst
//                   [3]     = clr_lock
//                   [2:0]   = reserved (3'b000)
//
//                2) 24-Bit Single-Register Write / Readback:
//                   [23]    = 1'b1 (Write) / 1'b0 (Read)
//                   [22:16] = 7-bit Register Address:
//                             7'h00 : REG_OTW_NOM   -> otw_nominal[15:0]
//                             7'h01 : REG_DIV_CTRL  -> {5'b0, integrator_rst, integrator_freeze, clr_lock, div_n[7:0]}
//                             7'h02 : REG_LOOP_GAIN -> {2'b0, ki_shift[3:0], ki_mult[3:0], kp_mult[5:0]}
//                             7'h03 : REG_GEAR_CFG  -> {4'b0, fast_lock_en, fast_lock_mult[2:0], gear_shift_thresh[7:0]}
//                             7'h04 : REG_STATUS    -> {7'h2A, locked, div_n[7:0]} (Read-only)
//                   [15:0]  = 16-bit Register Data
// ==============================================================================

`timescale 1ps / 1fs

module dpll_spi_slave #(
  parameter int OTW_WIDTH = 16,
  parameter int DIV_WIDTH = 8
)(
  input  logic                 clk,               // Buffered 1.0 MHz ref_clk (used only for clr_lock CDC pulse)
  input  logic                 rst_n,             // Active-low asynchronous system reset

  // External Asynchronous SPI Pad Interface (via sg13g2_io pads, SPI Mode 0)
  input  logic                 spi_cs_n,          // Active-low SPI Chip Select
  input  logic                 spi_sck,           // Asynchronous SPI Serial Clock
  input  logic                 spi_mosi,          // SPI Master-Out Slave-In
  output logic                 spi_miso,          // SPI Master-In Slave-Out

  // DPLL Status Input for SPI Readback
  input  logic                 locked,            // Current DPLL Lock Detector status

  // Programmable DPLL Parameters (All 11 Control Signals)
  output logic [OTW_WIDTH-1:0] otw_nominal,       // 16-bit Center Oscillator Tuning Word
  output logic [DIV_WIDTH-1:0] div_n,             // 8-bit Feedback Divider Ratio (50..200)
  output logic [5:0]           kp_mult,           // 6-bit Proportional Gain Multiplier
  output logic [3:0]           ki_mult,           // 4-bit Integral Gain Multiplier
  output logic [3:0]           ki_shift,          // 4-bit Integral Gain Shift
  output logic                 fast_lock_en,      // 1-bit Adaptive Gear-Shifting Enable
  output logic [2:0]           fast_lock_mult,    // 3-bit Acquisition Gain Boost Factor
  output logic [7:0]           gear_shift_thresh, // 8-bit Fine Mode Phase Error Threshold
  output logic                 integrator_freeze, // 1-bit Freeze Integrator Accumulator
  output logic                 integrator_rst,    // 1-bit Reset Integrator Accumulator
  output logic                 clr_lock           // 1-bit Control-Domain Lock Clear Pulse
);

  // Frame-scoped active-low reset for the 7-bit SPI bit counter (cleared when CS_N=1 or RST_N=0)
  wire spi_frame_rst_n = rst_n & ~spi_cs_n;

  // SPI clock domain (spi_sck) shift registers, bit counter, and lock-clear toggle
  logic [63:0] shift_in_reg;
  logic [23:0] shift_out_reg;
  logic [6:0]  bit_cnt;
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
      7'h01:   read_data_mux = {5'b00000, integrator_rst, integrator_freeze, clr_lock, div_n};
      7'h02:   read_data_mux = {2'b00, ki_shift, ki_mult, kp_mult};
      7'h03:   read_data_mux = {4'b0000, fast_lock_en, fast_lock_mult, gear_shift_thresh};
      default: read_data_mux = {7'h2A, locked, div_n};
    endcase
  end

  assign spi_miso = shift_out_reg[23];
  assign clr_lock = clr_lock_sw | (clr_sync1 != clr_sync2) | (clr_sync2 != clr_sync3) | (auto_clr_cnt != 2'b00);

  // ----------------------------------------------------------------------------
  // 1. Frame Bit Counter (Clocked by spi_sck, Asynchronously Cleared by CS_N=1)
  // ----------------------------------------------------------------------------
  always_ff @(posedge spi_sck or negedge spi_frame_rst_n) begin
    if (!spi_frame_rst_n) begin
      bit_cnt <= 7'd0;
    end else begin
      bit_cnt <= next_bit_cnt;
    end
  end

  // ----------------------------------------------------------------------------
  // 2. Asynchronous SPI Shift Registers & Configuration Bank (Clocked by spi_sck)
  // ----------------------------------------------------------------------------
  always_ff @(posedge spi_sck or negedge rst_n) begin
    if (!rst_n) begin
      shift_in_reg      <= 64'd0;
      shift_out_reg     <= 24'hA50032;
      clr_lock_sw       <= 1'b0;
      clr_toggle_sck    <= 1'b0;

      // Calibrated Power-On Reset Defaults (50.0 MHz, N = 50, Optimal PI Gains)
      otw_nominal       <= 16'd3455;
      div_n             <= 8'd50;
      kp_mult           <= 6'd8;
      ki_mult           <= 4'd1;
      ki_shift          <= 4'd1;
      fast_lock_en      <= 1'b1;
      fast_lock_mult    <= 3'd2;
      gear_shift_thresh <= 8'd48;
      integrator_freeze <= 1'b0;
      integrator_rst    <= 1'b0;
    end else if (!spi_cs_n) begin
      shift_in_reg <= next_shift_in;

      // Load addressed 16-bit register into shift_out_reg on 8th rising edge for Read (MSB=0)
      if (next_bit_cnt == 7'd8 && !next_shift_in[7]) begin
        shift_out_reg <= {read_data_mux, locked, div_n[6:0]};
      end else begin
        shift_out_reg <= {shift_out_reg[22:0], locked};
      end

      // Commit 64-Bit Full-Parameter Atomic Burst Write on 64th rising edge of spi_sck
      if (next_bit_cnt == 7'd64 && next_shift_in[63:56] == 8'hFF) begin
        otw_nominal       <= next_shift_in[55:40];
        div_n             <= next_shift_in[39:32];
        kp_mult           <= next_shift_in[31:26];
        ki_mult           <= next_shift_in[25:22];
        ki_shift          <= next_shift_in[21:18];
        fast_lock_en      <= next_shift_in[17];
        fast_lock_mult    <= next_shift_in[16:14];
        gear_shift_thresh <= next_shift_in[13:6];
        integrator_freeze <= next_shift_in[5];
        integrator_rst    <= next_shift_in[4];
        clr_lock_sw       <= next_shift_in[3];
        if (clr_toggle_sck == clr_sync2) begin
          clr_toggle_sck  <= ~clr_toggle_sck;
        end
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
            div_n             <= next_shift_in[7:0];
            clr_lock_sw       <= next_shift_in[8];
            integrator_freeze <= next_shift_in[9];
            integrator_rst    <= next_shift_in[10];
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
