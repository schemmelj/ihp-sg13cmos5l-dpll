// ==============================================================================
// File: dpll_top.sv
// Description: Synthesizable Top-Level All-Digital PLL (ADPLL) for IHP 130nm
//              BiCMOS (SG13G2 Standard Cell Library, 1.2V).
//              - Programmable Reference Clock: 1 MHz to 10 MHz
//              - Internal Ring DCO: Continuous 1-Octave 250.0 MHz to 500.0 MHz
//                across all PVT corners (N_fb = 25..500 + fb_frac / 256)
//              - Coupled Glitch-Free Output Fractional-N Divider & Duty-Cycle Shaper:
//                  * Frequency Range: 1 Hz to 500 MHz
//                  * Relative Frequency Granularity: <= 1% (< 0.4%)
//                  * Programmable Duty Cycle: 1/256..255/256 for f_out < 100 MHz
//                  * 100% Glitch-Free Live Frequency & Duty-Cycle Switching
// ==============================================================================

`timescale 1ps / 1fs

module dpll_top #(
  parameter int OTW_WIDTH   = 16,
  parameter int ERROR_WIDTH = 16,
  parameter int ACC_WIDTH   = 24,
  parameter int DIV_WIDTH   = 10,
  parameter int TDC_STEP_PS = 40     // IHP 130nm SG13G2 Flash TDC delay (40 ps)
)(
  input  logic                 ref_clk,            // 1 - 10 MHz external reference clock
  input  logic                 rst_n,              // Active-low asynchronous reset
  input  logic [OTW_WIDTH-1:0] otw_nominal,        // Center tuning word for 250-500 MHz DCO
  input  logic [DIV_WIDTH-1:0] div_n,              // Integer feedback division ratio (25..500)
  input  logic [7:0]           fb_frac = 8'd0,     // Fractional feedback numerator (0..255 -> F/256)

  // Programmable Loop Filter & Control Parameters
  input  logic [5:0]           kp_mult,            // Proportional gain multiplier
  input  logic [3:0]           ki_mult,            // Integral gain multiplier
  input  logic [3:0]           ki_shift,           // Integral gain shift divisor
  input  logic                 fast_lock_en,       // Adaptive gear-shifting enable
  input  logic [2:0]           fast_lock_mult,     // Acquisition gain boost factor
  input  logic [7:0]           gear_shift_thresh,  // Error threshold for fine mode
  input  logic                 integrator_freeze,  // Freeze integral accumulation
  input  logic                 integrator_rst,     // Synchronous reset of integrator
  input  logic                 clr_lock,           // Control-domain lock clear before parameter change

  // Programmable Output Fractional-N Divider, Duty-Cycle & 2x XOR Multiplier Control
  input  logic                 out_div_bypass,     // 1 = Direct 250-500 MHz DCO pass-through
  input  logic                 out_mul2_en = 1'b0, // 1 = Enable 2x XOR output frequency multiplier
  input  logic [4:0]           out_prescale_shift, // Binary octave prescaler S (0..20 -> 2^S)
  input  logic [9:0]           out_div_int,        // 10-bit integer divisor mantissa M_int (1..1023)
  input  logic [7:0]           out_div_frac,       // 8-bit fractional numerator F_frac (0..255 -> F/256)
  input  logic [7:0]           out_duty,           // 8-bit duty cycle word (1..255, 128 = 50.0%)

  output logic                 dco_clk_out,        // 1 Hz - 1 GHz Synthesized Output Clock
  output logic                 locked,             // PLL Lock Status flag
  output logic [OTW_WIDTH-1:0] otw_mon             // Live closed-loop Oscillator Control Word monitor
);

  logic signed [ERROR_WIDTH-1:0] phase_error;
  logic                          error_valid;
  logic [OTW_WIDTH-1:0]          otw;
  assign otw_mon = otw;
  (* keep = "true" *) logic      dco_clk_500m;
  logic                          fb_clk;
  logic [DIV_WIDTH-1:0]          fb_div_phase;
  logic [DIV_WIDTH-1:0]          fb_div_phase_neg;
  logic [7:0]                    fb_sdm_phase;
  logic [DIV_WIDTH-1:0]          div_n_q;
  logic [7:0]                    fb_frac_q;
  logic [OTW_WIDTH-1:0]          otw_nominal_q;
  logic                          channel_hop;
  logic                          clr_lock_meta, clr_lock_sync;
  logic                          lock_clear;

  // ----------------------------------------------------------------------------
  // Reset Synchronizers (Asynchronous Assert, Synchronous Deassert)
  // ----------------------------------------------------------------------------
  logic rst_n_meta, rst_n_sync;
  logic rst_n_dco_meta, rst_n_dco_sync;

  // 1. Reference clock (1 - 10 MHz) reset synchronizer
  always_ff @(posedge ref_clk or negedge rst_n) begin
    if (!rst_n) begin
      rst_n_meta <= 1'b0;
      rst_n_sync <= 1'b0;
    end else begin
      rst_n_meta <= 1'b1;
      rst_n_sync <= rst_n_meta;
    end
  end

  // 2. 250-500 MHz DCO clock reset synchronizer for feedback & output dividers
  always_ff @(posedge dco_clk_500m or negedge rst_n_sync) begin
    if (!rst_n_sync) begin
      rst_n_dco_meta <= 1'b0;
      rst_n_dco_sync <= 1'b0;
    end else begin
      rst_n_dco_meta <= 1'b1;
      rst_n_dco_sync <= rst_n_dco_meta;
    end
  end

  // 3. Control-domain clr_lock 2-FF synchronizer + fallback parameter change detector
  always_ff @(posedge ref_clk or negedge rst_n_sync) begin
    if (!rst_n_sync) begin
      clr_lock_meta <= 1'b0;
      clr_lock_sync <= 1'b0;
      div_n_q       <= '0;
      fb_frac_q     <= '0;
      otw_nominal_q <= '0;
    end else begin
      clr_lock_meta <= clr_lock;
      clr_lock_sync <= clr_lock_meta;
      div_n_q       <= div_n;
      fb_frac_q     <= fb_frac;
      otw_nominal_q <= otw_nominal;
    end
  end

  assign channel_hop = (div_n != div_n_q) || (fb_frac != fb_frac_q) || (otw_nominal != otw_nominal_q);
  assign lock_clear  = clr_lock_sync || channel_hop;

  // 1. Synthesizable Adaptive Coarse-Fine TDC Phase Detector (256-Stage SG13G2 Flash TDC)
  pfd_linear #(
    .ERROR_WIDTH(ERROR_WIDTH),
    .DIV_WIDTH  (DIV_WIDTH),
    .TDC_STEP_PS(TDC_STEP_PS)
  ) u_tdc (
    .ref_clk       (ref_clk),
    .fb_clk        (fb_clk),
    .dco_clk       (dco_clk_500m),
    .rst_n         (rst_n_sync),
    .div_ratio     (div_n),
    .div_phase     (fb_div_phase),
    .div_phase_neg (fb_div_phase_neg),
    .fb_sdm_phase  (fb_sdm_phase),
    .dco_coarse_idx(~otw[15:12]),
    .phase_error   (phase_error),
    .error_valid   (error_valid)
  );

  // 2. Synthesizable Digital PI Loop Filter with Continuous Gear-Shifting
  loop_filter u_filter (
    .clk              (ref_clk),
    .rst_n            (rst_n_sync),
    .phase_error      (phase_error),
    .error_valid      (error_valid),
    .kp_mult          (kp_mult),
    .ki_mult          (ki_mult),
    .ki_shift         (ki_shift),
    .fast_lock_en     (fast_lock_en),
    .fast_lock_mult   (fast_lock_mult),
    .gear_shift_thresh(gear_shift_thresh),
    .integrator_freeze(integrator_freeze),
    .integrator_rst   (integrator_rst),
    .otw_nominal      (otw_nominal),
    .otw              (otw)
  );

  // 3. Synthesizable IHP 130nm Standard-Cell Digitally Controlled Ring Oscillator (250-500 MHz)
  dco_nco u_dco (
    .rst_n      (rst_n),
    .otw        (otw),
    .dco_clk_out(dco_clk_500m)
  );

  // 4. Synthesizable High-Speed Integer/Fractional-N Feedback Divider (N = 25..500 + F/256)
  clk_divider #(
    .DIV_WIDTH(DIV_WIDTH)
  ) u_divider (
    .clk          (dco_clk_500m),
    .rst_n        (rst_n_dco_sync),
    .div_ratio    (div_n),
    .fb_frac      (fb_frac),
    .clk_out      (fb_clk),
    .div_phase    (fb_div_phase),
    .div_phase_neg(fb_div_phase_neg),
    .fb_sdm_phase (fb_sdm_phase)
  );

  // 5. Synthesizable Glitch-Free Output Fractional-N Divider, Duty-Cycle & 2x XOR Multiplier
  frac_n_out_divider u_out_div (
    .clk_dco           (dco_clk_500m),
    .rst_n             (rst_n_dco_sync),
    .out_div_bypass    (out_div_bypass),
    .out_mul2_en       (out_mul2_en),
    .out_prescale_shift(out_prescale_shift),
    .out_div_int       (out_div_int),
    .out_div_frac      (out_div_frac),
    .out_duty          (out_duty),
    .clk_out           (dco_clk_out)
  );

  // 6. Synthesizable Lock Detector with Hysteresis
  lock_detector u_lock_det (
    .clk        (ref_clk),
    .rst_n      (rst_n_sync),
    .clear      (lock_clear),
    .phase_error(phase_error),
    .error_valid(error_valid),
    .locked     (locked)
  );

endmodule
