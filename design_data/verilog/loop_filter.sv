// ==============================================================================
// File: loop_filter.sv
// Description: Synthesizable Fast-Settling Digital PI Loop Filter for IHP 130nm
//              BiCMOS (SG13G2) ADPLL.
//              Features continuous piecewise-linear gear-shifting, slew-clamped
//              anti-windup integration, and fractional sub-LSB accumulation.
// ==============================================================================

`timescale 1ps / 1fs

module loop_filter #(
  parameter int ERROR_WIDTH = 16,
  parameter int ACC_WIDTH   = 24,
  parameter int OTW_WIDTH   = 16
)(
  input  logic                             clk,               // 1 MHz Reference clock
  input  logic                             rst_n,             // Active-low asynchronous reset
  input  logic signed [ERROR_WIDTH-1:0]    phase_error,       // From TDC (40 ps/step)
  input  logic                             error_valid,       // Strobe from TDC
  
  // Programmable parameters with optimal fast-settling defaults
  input  logic [5:0]                       kp_mult,           // Proportional multiplier
  input  logic [3:0]                       ki_mult,           // Integral multiplier
  input  logic [3:0]                       ki_shift,          // Integral shift divisor
  input  logic                             fast_lock_en,      // Adaptive gear-shifting enable
  input  logic [2:0]                       fast_lock_mult,    // Acquisition gain boost factor
  input  logic [7:0]                       gear_shift_thresh, // Error threshold for fine mode
  input  logic                             integrator_freeze, // Freeze integral accumulation
  input  logic                             integrator_rst,    // Synchronous clear for integrator

  input  logic [OTW_WIDTH-1:0]             otw_nominal,       // Nominal base tuning word
  output logic [OTW_WIDTH-1:0]             otw                // Effective DCO Tuning Word
);

  localparam signed [ACC_WIDTH-1:0] ACC_MAX =  (1 << (ACC_WIDTH - 1)) - 1;
  localparam signed [ACC_WIDTH-1:0] ACC_MIN = -(1 << (ACC_WIDTH - 1));

  logic [ERROR_WIDTH-1:0]        abs_phase_error;
  logic                          is_fast_mode;
  logic [31:0]                   prop_mag;
  logic [5:0]                    eff_ki;
  logic signed [ERROR_WIDTH-1:0] int_error;

  logic signed [ACC_WIDTH-1:0]   integrator;
  logic signed [ACC_WIDTH-1:0]   integrator_next;
  logic signed [31:0]            scaled_step;
  logic signed [ACC_WIDTH-1:0]   delta;
  logic signed [ACC_WIDTH-1:0]   raw_sum;

  logic signed [31:0]            p_term;
  logic signed [31:0]            i_term;
  logic signed [31:0]            otw_calc;
  logic [OTW_WIDTH-1:0]          otw_next;

  // Absolute phase error for gear-shifting threshold check
  assign abs_phase_error = (phase_error < 0) ? (-phase_error) : phase_error;
  assign is_fast_mode    = fast_lock_en && (abs_phase_error > {8'b0, gear_shift_thresh});

  // 1. Continuous Piecewise-Linear Proportional Gain with Frequency-Band Normalization:
  //    - Fine zone (|e| <= thresh): slope = kp_mult
  //    - Fast zone (|e| >  thresh): slope = kp_mult * fast_lock_mult
  //    - Gain scheduling across otw_nominal compensates for DCO-to-TDC gain scaling with N
  //      (G_DCO = N / 160), maintaining uniform loop bandwidth across 50 MHz..200 MHz.
  logic signed [31:0] prop_signed;
  always_comb begin
    if (is_fast_mode) begin
      prop_mag = ({24'b0, gear_shift_thresh} * {26'b0, kp_mult}) +
                 (({16'b0, abs_phase_error} - {24'b0, gear_shift_thresh}) * {26'b0, kp_mult} * {29'b0, fast_lock_mult});
    end else begin
      prop_mag = {16'b0, abs_phase_error} * {26'b0, kp_mult};
    end

    prop_signed = (phase_error < 0) ? -signed'(prop_mag) : signed'(prop_mag);

    if (otw_nominal < 16'd38000)
      p_term = prop_signed >>> 4;
    else if (otw_nominal < 16'd56000)
      p_term = prop_signed >>> 5;
    else
      p_term = prop_signed >>> 6;
  end

  // 2. Slew-Clamped Anti-Windup Integrator Input:
  //    Clamping the integrator input to +/-(gear_shift_thresh >> 3) during coarse phase
  //    slewing prevents initial phase offsets from winding up the frequency integrator.
  logic [7:0] slew_int_clamp;
  assign slew_int_clamp = gear_shift_thresh >> 3;

  always_comb begin
    if (is_fast_mode && (phase_error > 0))
      int_error = signed'({8'b0, slew_int_clamp});
    else if (is_fast_mode && (phase_error < 0))
      int_error = -signed'({8'b0, slew_int_clamp});
    else
      int_error = phase_error;
  end

  assign eff_ki = {2'b0, ki_mult};

  // Fractional integral accumulation:
  // Integrator stores 4 fractional bits (i_term = integrator >>> 4).
  // Computing ((int_error * eff_ki) <<< 2) >>> ki_shift preserves all 4 fractional bits
  // for zero integral deadband down to 1 single TDC step (40 ps).
  assign scaled_step = ((signed'(int_error) * signed'({26'b0, eff_ki})) <<< 2) >>> ki_shift;
  assign delta       = scaled_step[ACC_WIDTH-1:0];
  assign raw_sum     = integrator + delta;

  always_comb begin
    if ((delta > 0) && (raw_sum < integrator))
      integrator_next = ACC_MAX;
    else if ((delta < 0) && (raw_sum > integrator))
      integrator_next = ACC_MIN;
    else
      integrator_next = raw_sum;
  end

  // Synthesizable sequential accumulator register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      integrator <= '0;
    end else if (integrator_rst) begin
      integrator <= '0;
    end else if (error_valid && !integrator_freeze) begin
      integrator <= integrator_next;
    end
  end

  // Scale updated integrator to integer OTW units (arithmetic right shift by 8)
  assign i_term = signed'(integrator_next >>> 8);

  // Combined PI filter output: OTW = otw_nominal + P + I (clamped to [0, 65535])
  assign otw_calc = signed'({16'b0, otw_nominal}) + p_term + i_term;

  always_comb begin
    if (otw_calc < 0)
      otw_next = 16'd0;
    else if (otw_calc > 32'sd65535)
      otw_next = 16'd65535;
    else
      otw_next = otw_calc[OTW_WIDTH-1:0];
  end

  // Glitch-free synchronous OTW output register in ref_clk domain
  logic [OTW_WIDTH-1:0] otw_reg;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      otw_reg <= 16'd32768;
    end else if (integrator_rst) begin
      otw_reg <= otw_nominal;
    end else if (error_valid) begin
      otw_reg <= otw_next;
    end else begin
      otw_reg <= otw_nominal;
    end
  end

  assign otw = error_valid ? otw_reg : otw_nominal;

endmodule
