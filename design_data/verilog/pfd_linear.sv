// ==============================================================================
// File: pfd_linear.sv
// Description: Synthesizable Coarse-Fine Time-to-Digital Converter (TDC) Phase Detector
//              for IHP 130nm BiCMOS (SG13G2) ADPLL.
//              Combines synchronous DCO divider phase index (coarse, N = 50..200)
//              with a 256-stage IHP 130nm Flash Inverter Delay-Line TDC (fine 40 ps
//              steps) for continuous, strictly monotonic phase error measurement
//              across the full [-T_ref/2, +T_ref/2] = [-500 ns, +500 ns] range.
// ==============================================================================

`timescale 1ps / 1fs

module pfd_linear #(
  parameter int ERROR_WIDTH = 16,
  parameter int TDC_STEP_PS = 40     // IHP 130nm SG13G2 TDC step (40 ps)
)(
  input  logic                          ref_clk,       // 1 MHz Reference clock
  input  logic                          fb_clk,        // 1 MHz Divided feedback clock
  input  logic                          dco_clk,       // 50 - 200 MHz DCO clock
  input  logic                          rst_n,         // Active-low reset (synchronized to ref_clk)
  input  logic [7:0]                    div_ratio,     // Feedback divider ratio N (50..200)
  input  logic [7:0]                    div_phase,     // Rising-edge divider phase (0..N-1)
  input  logic [7:0]                    div_phase_neg, // Falling-edge retimed divider phase (0..N-1)
  output logic signed [ERROR_WIDTH-1:0] phase_error,   // Phase error in TDC LSB steps (40 ps/step)
  output logic                          error_valid    // Strobe asserted when TDC measurement is valid
);

`ifndef FASTSIM
  // ----------------------------------------------------------------------------
  // Synthesizable High-Resolution Coarse-Fine TDC Phase Detector for ASIC Synthesis
  // ----------------------------------------------------------------------------
  logic [15:0]        elapsed_cycles;
  logic [15:0]        fine_clamped;
  logic signed [15:0] step_scale;
  logic signed [31:0] error_scaled;
  logic [15:0]        half_div_ratio;

  // Flash Inverter Delay-Line TDC (256 stages of 40.0 ps sg13g2_inv_1 cells)
  logic [8:0] flash_fine_offset;
  logic       flash_dco_level;
  logic       flash_near_posedge;
  logic [8:0] flash_half_period;

  // 2-Stage Coarse Phase Synchronizer (Stage 1: posedge ref_clk capture, Stage 2: negedge ref_clk resolve)
  // Matches the 2-stage TDC sampling pipeline and provides 500,000 ps (500 ns) of metastability resolution.
  logic [7:0] div_phase_pos_meta, div_phase_pos_sampled;
  logic [7:0] div_phase_neg_meta, div_phase_neg_sampled;
  logic [7:0] div_ratio_meta, div_ratio_sampled;
  logic       valid_meta, valid_reg;

  always_ff @(posedge ref_clk or negedge rst_n) begin
    if (!rst_n) begin
      div_phase_pos_meta <= 8'd0;
      div_phase_neg_meta <= 8'd0;
      div_ratio_meta     <= 8'd100;
      valid_meta         <= 1'b0;
    end else begin
      div_phase_pos_meta <= div_phase;
      div_phase_neg_meta <= div_phase_neg;
      div_ratio_meta     <= div_ratio;
      valid_meta         <= 1'b1;
    end
  end

  always_ff @(negedge ref_clk or negedge rst_n) begin
    if (!rst_n) begin
      div_phase_pos_sampled <= 8'd0;
      div_phase_neg_sampled <= 8'd0;
      div_ratio_sampled     <= 8'd100;
      valid_reg             <= 1'b0;
    end else begin
      div_phase_pos_sampled <= div_phase_pos_meta;
      div_phase_neg_sampled <= div_phase_neg_meta;
      div_ratio_sampled     <= div_ratio_meta;
      valid_reg             <= valid_meta;
    end
  end

  assign flash_half_period = step_scale[9:1];
  assign half_div_ratio    = {8'd0, div_ratio_sampled} >> 1;

  tdc_flash u_flash_tdc (
    .clk_in           (dco_clk),
    .sample_clk       (ref_clk),
    .rst_n            (rst_n),
    .half_period_steps(flash_half_period),
    .fine_offset      (flash_fine_offset),
    .dco_level        (flash_dco_level),
    .near_posedge     (flash_near_posedge)
  );

  // TDC steps (40 ps LSB) per DCO cycle across N = 50..200 (1 MHz Ref -> T_ref = 1,000,000 ps):
  // Step size is round((1,000,000 ps / div_ratio) / 40 ps) = round(25000 / div_ratio)
  always_comb begin
    case (div_ratio_sampled)
      8'd50:  step_scale = 16'sd500;
      8'd51:  step_scale = 16'sd490;
      8'd52:  step_scale = 16'sd481;
      8'd53:  step_scale = 16'sd472;
      8'd54:  step_scale = 16'sd463;
      8'd55:  step_scale = 16'sd455;
      8'd56:  step_scale = 16'sd446;
      8'd57:  step_scale = 16'sd439;
      8'd58:  step_scale = 16'sd431;
      8'd59:  step_scale = 16'sd424;
      8'd60:  step_scale = 16'sd417;
      8'd61:  step_scale = 16'sd410;
      8'd62:  step_scale = 16'sd403;
      8'd63:  step_scale = 16'sd397;
      8'd64:  step_scale = 16'sd391;
      8'd65:  step_scale = 16'sd385;
      8'd66:  step_scale = 16'sd379;
      8'd67:  step_scale = 16'sd373;
      8'd68:  step_scale = 16'sd368;
      8'd69:  step_scale = 16'sd362;
      8'd70:  step_scale = 16'sd357;
      8'd71:  step_scale = 16'sd352;
      8'd72:  step_scale = 16'sd347;
      8'd73:  step_scale = 16'sd342;
      8'd74:  step_scale = 16'sd338;
      8'd75:  step_scale = 16'sd333;
      8'd76:  step_scale = 16'sd329;
      8'd77:  step_scale = 16'sd325;
      8'd78:  step_scale = 16'sd321;
      8'd79:  step_scale = 16'sd316;
      8'd80:  step_scale = 16'sd313;
      8'd81:  step_scale = 16'sd309;
      8'd82:  step_scale = 16'sd305;
      8'd83:  step_scale = 16'sd301;
      8'd84:  step_scale = 16'sd298;
      8'd85:  step_scale = 16'sd294;
      8'd86:  step_scale = 16'sd291;
      8'd87:  step_scale = 16'sd287;
      8'd88:  step_scale = 16'sd284;
      8'd89:  step_scale = 16'sd281;
      8'd90:  step_scale = 16'sd278;
      8'd91:  step_scale = 16'sd275;
      8'd92:  step_scale = 16'sd272;
      8'd93:  step_scale = 16'sd269;
      8'd94:  step_scale = 16'sd266;
      8'd95:  step_scale = 16'sd263;
      8'd96:  step_scale = 16'sd260;
      8'd97:  step_scale = 16'sd258;
      8'd98:  step_scale = 16'sd255;
      8'd99:  step_scale = 16'sd253;
      8'd100: step_scale = 16'sd250;
      8'd101: step_scale = 16'sd248;
      8'd102: step_scale = 16'sd245;
      8'd103: step_scale = 16'sd243;
      8'd104: step_scale = 16'sd240;
      8'd105: step_scale = 16'sd238;
      8'd106: step_scale = 16'sd236;
      8'd107: step_scale = 16'sd234;
      8'd108: step_scale = 16'sd231;
      8'd109: step_scale = 16'sd229;
      8'd110: step_scale = 16'sd227;
      8'd111: step_scale = 16'sd225;
      8'd112: step_scale = 16'sd223;
      8'd113: step_scale = 16'sd221;
      8'd114: step_scale = 16'sd219;
      8'd115: step_scale = 16'sd217;
      8'd116: step_scale = 16'sd216;
      8'd117: step_scale = 16'sd214;
      8'd118: step_scale = 16'sd212;
      8'd119: step_scale = 16'sd210;
      8'd120: step_scale = 16'sd208;
      8'd121: step_scale = 16'sd207;
      8'd122: step_scale = 16'sd205;
      8'd123: step_scale = 16'sd203;
      8'd124: step_scale = 16'sd202;
      8'd125: step_scale = 16'sd200;
      8'd126: step_scale = 16'sd198;
      8'd127: step_scale = 16'sd197;
      8'd128: step_scale = 16'sd195;
      8'd129: step_scale = 16'sd194;
      8'd130: step_scale = 16'sd192;
      8'd131: step_scale = 16'sd191;
      8'd132: step_scale = 16'sd189;
      8'd133: step_scale = 16'sd188;
      8'd134: step_scale = 16'sd187;
      8'd135: step_scale = 16'sd185;
      8'd136: step_scale = 16'sd184;
      8'd137: step_scale = 16'sd182;
      8'd138: step_scale = 16'sd181;
      8'd139: step_scale = 16'sd180;
      8'd140: step_scale = 16'sd179;
      8'd141: step_scale = 16'sd177;
      8'd142: step_scale = 16'sd176;
      8'd143: step_scale = 16'sd175;
      8'd144: step_scale = 16'sd174;
      8'd145: step_scale = 16'sd172;
      8'd146: step_scale = 16'sd171;
      8'd147: step_scale = 16'sd170;
      8'd148: step_scale = 16'sd169;
      8'd149: step_scale = 16'sd168;
      8'd150: step_scale = 16'sd167;
      8'd151: step_scale = 16'sd166;
      8'd152: step_scale = 16'sd164;
      8'd153: step_scale = 16'sd163;
      8'd154: step_scale = 16'sd162;
      8'd155: step_scale = 16'sd161;
      8'd156: step_scale = 16'sd160;
      8'd157: step_scale = 16'sd159;
      8'd158: step_scale = 16'sd158;
      8'd159: step_scale = 16'sd157;
      8'd160: step_scale = 16'sd156;
      8'd161: step_scale = 16'sd155;
      8'd162: step_scale = 16'sd154;
      8'd163: step_scale = 16'sd153;
      8'd164: step_scale = 16'sd152;
      8'd165: step_scale = 16'sd152;
      8'd166: step_scale = 16'sd151;
      8'd167: step_scale = 16'sd150;
      8'd168: step_scale = 16'sd149;
      8'd169: step_scale = 16'sd148;
      8'd170: step_scale = 16'sd147;
      8'd171: step_scale = 16'sd146;
      8'd172: step_scale = 16'sd145;
      8'd173: step_scale = 16'sd145;
      8'd174: step_scale = 16'sd144;
      8'd175: step_scale = 16'sd143;
      8'd176: step_scale = 16'sd142;
      8'd177: step_scale = 16'sd141;
      8'd178: step_scale = 16'sd140;
      8'd179: step_scale = 16'sd140;
      8'd180: step_scale = 16'sd139;
      8'd181: step_scale = 16'sd138;
      8'd182: step_scale = 16'sd137;
      8'd183: step_scale = 16'sd137;
      8'd184: step_scale = 16'sd136;
      8'd185: step_scale = 16'sd135;
      8'd186: step_scale = 16'sd134;
      8'd187: step_scale = 16'sd134;
      8'd188: step_scale = 16'sd133;
      8'd189: step_scale = 16'sd132;
      8'd190: step_scale = 16'sd132;
      8'd191: step_scale = 16'sd131;
      8'd192: step_scale = 16'sd130;
      8'd193: step_scale = 16'sd130;
      8'd194: step_scale = 16'sd129;
      8'd195: step_scale = 16'sd128;
      8'd196: step_scale = 16'sd128;
      8'd197: step_scale = 16'sd127;
      8'd198: step_scale = 16'sd126;
      8'd199: step_scale = 16'sd126;
      8'd200: step_scale = 16'sd125;
      default: step_scale = 16'sd250;
    endcase
  end

  // TDC-Guided Coarse Phase Selection (Eliminates Setup/Hold Violation at Lock):
  // When posedge ref_clk falls near posedge dco_clk (flash_near_posedge == 1),
  // div_phase_pos may have been transitioning, so we use the stationary negedge-latched
  // div_phase_neg_sampled. Otherwise, div_phase_pos_sampled is mid-window stable.
  logic [7:0] div_phase_neg_plus1;
  logic [7:0] div_phase_selected;

  assign div_phase_neg_plus1 = (div_phase_neg_sampled >= (div_ratio_sampled - 8'd1))
                               ? 8'd0
                               : (div_phase_neg_sampled + 8'd1);

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

  // Unified Coarse + Fine Phase Error Computation:
  // Total elapsed time since most recent posedge fb_clk (when div_phase became 0):
  //   total_elapsed = elapsed_cycles * step_scale + fine_clamped
  // Remaining time until next posedge fb_clk (when div_phase wraps from N-1 to 0):
  //   total_remaining = (div_ratio - elapsed_cycles) * step_scale - fine_clamped
  always_comb begin
    elapsed_cycles = {8'd0, div_phase_selected};
    fine_clamped   = ({7'd0, flash_fine_offset} > step_scale[15:0])
                     ? step_scale[15:0]
                     : {7'd0, flash_fine_offset};

    if (elapsed_cycles < half_div_ratio) begin
      // First half of feedback period: fb_clk rose recently -> LEADING (negative phase error)
      error_scaled = -(signed'({16'd0, elapsed_cycles}) * signed'(step_scale)
                       + signed'({16'd0, fine_clamped}));
    end else if (elapsed_cycles < {8'd0, div_ratio_sampled}) begin
      // Second half of feedback period: next fb_clk edge approaching -> LAGGING (positive phase error)
      error_scaled = (signed'({8'd0, div_ratio_sampled} - elapsed_cycles) * signed'(step_scale))
                     - signed'({16'd0, fine_clamped});
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
    t_dco_period  = 10000.0;
  end

  always @(posedge dco_clk or negedge rst_n) begin
    if (!rst_n) begin
      dco_cycle_cnt <= '0;
      t_last_dco    <= 0;
      t_dco_period  <= 10000.0;
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
    t_fb_period = 1000000.0;
    fb_seen     = 1'b0;
  end

  always @(posedge fb_clk or negedge rst_n) begin
    if (!rst_n) begin
      fb_dco_snap <= '0;
      t_last_fb   <= 0;
      t_fb_period <= 1000000.0;
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
      eff_period = (t_fb_period > 250000.0) ? t_fb_period : 1000000.0;

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
