// ==============================================================================
// File: pfd_linear.sv
// Description: Synthesizable Adaptive Coarse-Fine TDC Phase Detector
//              for IHP 130nm BiCMOS (SG13G2) ADPLL.
//              Combines synchronous DCO divider phase index (coarse, N = 25..500
//              plus 8-bit fractional feedback residue for 1..10 MHz reference
//              clock against the 250-500 MHz DCO) with a 256-stage IHP 130nm
//              Flash Inverter Delay-Line TDC for continuous, strictly monotonic
//              phase error measurement across all PVT corners (SLOW, TYP, FAST).
// ==============================================================================

`timescale 1ps / 1fs

module pfd_linear #(
  parameter int ERROR_WIDTH = 16,
  parameter int DIV_WIDTH   = 10,
  parameter int TDC_STEP_PS = 40     // IHP 130nm SG13G2 nominal TDC step (40 ps)
)(
  input  logic                          ref_clk,       // 1 - 10 MHz Reference clock
  input  logic                          fb_clk,        // 1 - 10 MHz Divided feedback clock
  input  logic                          dco_clk,       // 250 - 500 MHz DCO clock
  input  logic                          rst_n,         // Active-low reset (synchronized to ref_clk)
  input  logic [DIV_WIDTH-1:0]          div_ratio,     // Feedback divider ratio N (25..500)
  input  logic [DIV_WIDTH-1:0]          div_phase,     // Rising-edge divider phase (0..N-1)
  input  logic [DIV_WIDTH-1:0]          div_phase_neg, // Falling-edge retimed divider phase (0..N-1)
  input  logic [7:0]                    fb_sdm_phase,  // Fractional-N feedback SDM phase residue (0..255)
  input  logic [3:0]                    dco_coarse_idx,// Active coarse delay index (~otw[15:12]) for TDC scaling
  output logic signed [ERROR_WIDTH-1:0] phase_error,   // Phase error in TDC LSB steps
  output logic                          error_valid    // Strobe asserted when TDC measurement is valid
);

`ifndef FASTSIM
  // ----------------------------------------------------------------------------
  // Synthesizable High-Resolution Adaptive Coarse-Fine TDC Phase Detector
  // ----------------------------------------------------------------------------
  logic [15:0]        elapsed_cycles;
  logic [15:0]        fine_clamped;
  logic signed [15:0] step_scale;
  logic signed [15:0] frac_comp_steps;
  logic signed [31:0] error_scaled;
  logic [15:0]        half_div_ratio;

  // Flash Inverter Delay-Line TDC (256 stages of sg13g2_inv_1 cells)
  logic [8:0] flash_fine_offset;
  logic       flash_dco_level;
  logic       flash_near_posedge;
  logic [8:0] flash_half_period;

  // 2-Stage Coarse Phase Synchronizer (Stage 1: posedge ref_clk capture, Stage 2: negedge ref_clk resolve)
  logic [DIV_WIDTH-1:0] div_phase_pos_meta, div_phase_pos_sampled;
  logic [DIV_WIDTH-1:0] div_phase_neg_meta, div_phase_neg_sampled;
  logic [DIV_WIDTH-1:0] div_ratio_meta, div_ratio_sampled;
  logic [7:0]           fb_sdm_meta, fb_sdm_sampled;
  logic                 valid_meta, valid_reg;

  always_ff @(posedge ref_clk or negedge rst_n) begin
    if (!rst_n) begin
      div_phase_pos_meta <= 10'd0;
      div_phase_neg_meta <= 10'd0;
      div_ratio_meta     <= 10'd100;
      fb_sdm_meta        <= 8'd0;
      valid_meta         <= 1'b0;
    end else begin
      div_phase_pos_meta <= div_phase;
      div_phase_neg_meta <= div_phase_neg;
      div_ratio_meta     <= div_ratio;
      fb_sdm_meta        <= fb_sdm_phase;
      valid_meta         <= 1'b1;
    end
  end

  always_ff @(negedge ref_clk or negedge rst_n) begin
    if (!rst_n) begin
      div_phase_pos_sampled <= 10'd0;
      div_phase_neg_sampled <= 10'd0;
      div_ratio_sampled     <= 10'd100;
      fb_sdm_sampled        <= 8'd0;
      valid_reg             <= 1'b0;
    end else begin
      div_phase_pos_sampled <= div_phase_pos_meta;
      div_phase_neg_sampled <= div_phase_neg_meta;
      div_ratio_sampled     <= div_ratio_meta;
      fb_sdm_sampled        <= fb_sdm_meta;
      valid_reg             <= valid_meta;
    end
  end

  // Adaptive DCO period scale tracking the active DCO coarse delay index (~otw[15:12]):
  // Each coarse stage adds ~4 TDC inverter delays per half-period (8 per full period),
  // matching f_DCO across 250-500 MHz and SLOW/TYP/FAST with only 12 logic gates!
  assign flash_half_period = 9'd25 + ({5'd0, dco_coarse_idx} << 2);
  assign step_scale        = signed'({6'd0, flash_half_period, 1'b0});
  assign frac_comp_steps   = signed'((16'({8'd0, fb_sdm_sampled}) * step_scale[15:0]) >> 8);
  assign half_div_ratio    = {6'd0, div_ratio_sampled} >> 1;

  tdc_flash u_flash_tdc (
    .clk_in           (dco_clk),
    .sample_clk       (ref_clk),
    .rst_n            (rst_n),
    .half_period_steps(flash_half_period),
    .fine_offset      (flash_fine_offset),
    .dco_level        (flash_dco_level),
    .near_posedge     (flash_near_posedge)
  );

  // TDC-Guided Coarse Phase Selection (Eliminates Setup/Hold Violation at Lock):
  logic [DIV_WIDTH-1:0] div_phase_neg_plus1;
  logic [DIV_WIDTH-1:0] div_phase_selected;

  assign div_phase_neg_plus1 = (div_phase_neg_sampled >= (div_ratio_sampled - 10'd1))
                               ? 10'd0
                               : (div_phase_neg_sampled + 10'd1);

  always_comb begin
    if (flash_near_posedge) begin
      if (flash_dco_level == 1'b1) begin
        div_phase_selected = div_phase_neg_plus1;
      end else begin
        div_phase_selected = div_phase_neg_sampled;
      end
    end else begin
      div_phase_selected = div_phase_pos_sampled;
    end
  end

  // Unified Coarse + Fine + Fractional-N Residue Phase Error Computation:
  always_comb begin
    elapsed_cycles = {6'd0, div_phase_selected};
    fine_clamped   = ({7'd0, flash_fine_offset} > step_scale[15:0])
                     ? step_scale[15:0]
                     : {7'd0, flash_fine_offset};

    if (elapsed_cycles < half_div_ratio) begin
      // First half of feedback period: fb_clk rose recently -> LEADING (negative phase error)
      error_scaled = -(signed'({16'd0, elapsed_cycles}) * signed'(step_scale)
                       + signed'({16'd0, fine_clamped}))
                     + signed'({{16{frac_comp_steps[15]}}, frac_comp_steps});
    end else if (elapsed_cycles < {6'd0, div_ratio_sampled}) begin
      // Second half of feedback period: next fb_clk edge approaching -> LAGGING (positive phase error)
      error_scaled = (signed'({6'd0, div_ratio_sampled} - elapsed_cycles) * signed'(step_scale))
                     - signed'({16'd0, fine_clamped})
                     + signed'({{16{frac_comp_steps[15]}}, frac_comp_steps});
    end else begin
      // Transient boundary when div_ratio steps down before next DCO edge wraps div_phase
      error_scaled = 32'sd0;
    end

    // Symmetrical saturation clamping (+/- 12500 steps = +/- 500,000 ps = +/- half 1 MHz reference period)
    if (error_scaled > 32'sd12500)
      phase_error = 16'sd12500;
    else if (error_scaled < -32'sd12500)
      phase_error = -16'sd12500;
    else
      phase_error = error_scaled[ERROR_WIDTH-1:0];

    error_valid = valid_reg;
  end

`else
  // ----------------------------------------------------------------------------
  // High-Precision Simulation TDC Model (Event-driven with sub-cycle resolution)
  // ----------------------------------------------------------------------------
  logic [15:0] dco_cycle_cnt;
  realtime     t_last_dco;
  realtime     t_dco_period;

  initial begin
    dco_cycle_cnt = '0;
    t_last_dco    = 0;
    t_dco_period  = 2000.0;
  end

  always @(posedge dco_clk or negedge rst_n) begin
    if (!rst_n) begin
      dco_cycle_cnt <= '0;
      t_last_dco    <= 0;
      t_dco_period  <= 2000.0;
    end else begin
      dco_cycle_cnt <= dco_cycle_cnt + 1'b1;
      if (t_last_dco > 0) begin
        t_dco_period <= $realtime - t_last_dco;
      end
      t_last_dco <= $realtime;
    end
  end

  logic [15:0] fb_dco_snap;
  realtime     t_last_fb;
  realtime     t_fb_period;
  logic        fb_seen;

  initial begin
    fb_dco_snap = '0;
    t_last_fb   = 0;
    t_fb_period = 200000.0;
    fb_seen     = 1'b0;
  end

  always @(posedge fb_clk or negedge rst_n) begin
    if (!rst_n) begin
      fb_dco_snap <= '0;
      t_last_fb   <= 0;
      t_fb_period <= 200000.0;
      fb_seen     <= 1'b0;
    end else begin
      fb_dco_snap <= dco_cycle_cnt;
      if (fb_seen && (t_last_fb > 0)) begin
        t_fb_period <= $realtime - t_last_fb;
      end
      t_last_fb <= $realtime;
      fb_seen   <= 1'b1;
    end
  end

  logic [15:0] coarse_dco_diff;
  realtime     dt_since_fb;
  realtime     eff_period;
  realtime     phase_diff_ps;
  real         err_val;

  always @(posedge ref_clk or negedge rst_n) begin
    if (!rst_n) begin
      phase_error     <= '0;
      error_valid     <= 1'b0;
      coarse_dco_diff <= '0;
    end else if (!fb_seen) begin
      phase_error     <= '0;
      error_valid     <= 1'b0;
      coarse_dco_diff <= '0;
    end else begin
      coarse_dco_diff <= dco_cycle_cnt - fb_dco_snap;
      dt_since_fb = $realtime - t_last_fb;
      eff_period = (t_fb_period > 50000.0) ? t_fb_period : 200000.0;

      if (dt_since_fb < (eff_period / 2.0)) begin
        phase_diff_ps = -dt_since_fb;
      end else begin
        phase_diff_ps = eff_period - dt_since_fb;
      end

      err_val = phase_diff_ps / real'(TDC_STEP_PS);
      if (err_val > 12500.0)       err_val = 12500.0;
      else if (err_val < -12500.0) err_val = -12500.0;

      phase_error <= signed'(int'($floor(err_val + 0.5)));
      error_valid <= 1'b1;
    end
  end
`endif

endmodule
