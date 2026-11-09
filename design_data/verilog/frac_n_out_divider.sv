// ==============================================================================
// File: frac_n_out_divider.sv
// Description: Wide-Range Glitch-Free Fractional-N Output Clock Divider &
//              Programmable Duty-Cycle Shaper Coupled with 250-500 MHz DCO
//              - Input DCO Frequency Range: 250 MHz to 500 MHz (1 Octave)
//              - Output Frequency Range: 1 Hz to 500 MHz (Direct / Frac-N)
//              - Relative Frequency Granularity: < 0.4% (<= 1% requirement)
//                across the entire 1 Hz to 500 MHz span
//              - Programmable Duty Cycle: 1/256 to 255/256 for all f_out < 100 MHz
//              - 100% Glitch-Free Frequency & Duty-Cycle Switching
// ==============================================================================

module frac_n_out_divider (
  input  logic       clk_dco,                 // 250 - 500 MHz DCO clock
  input  logic       rst_n,                   // Active-low reset (synchronized to clk_dco)
  input  logic       rst_n_async = 1'b1,      // Active-low asynchronous external reset
  input  logic       out_div_bypass,          // 1 = Direct DCO pass-through (250..500 MHz)
  input  logic [4:0] out_prescale_shift,      // Binary octave prescaler S (0..20 -> 2^S)
  input  logic [9:0] out_div_int,             // 10-bit integer divisor mantissa M_int (1..1023)
  input  logic [7:0] out_div_frac,            // 8-bit fractional numerator F_frac (0..255 -> F/256)
  input  logic [7:0] out_duty,                // 8-bit duty cycle word (1..255, 128 = 50.0%)
  output logic       clk_out                  // Synthesized output clock (1 Hz .. 500 MHz)
);

  // Local replicated reset leaf registers (~35 FFs each) for 500 MHz recovery closure
  (* keep = "true" *) logic rst_n_sync_q;
  (* keep = "true" *) logic rst_n_c1_q;
  (* keep = "true" *) logic rst_n_c2_q;
  (* keep = "true" *) logic rst_n_c3_q;
  (* keep = "true" *) logic rst_n_pre_q;
  (* keep = "true" *) logic rst_n_fsm1_q;
  (* keep = "true" *) logic rst_n_fsm2_q;

  always_ff @(posedge clk_dco or negedge rst_n) begin
    if (!rst_n) begin
      rst_n_sync_q <= 1'b0;
      rst_n_c1_q   <= 1'b0;
      rst_n_c2_q   <= 1'b0;
      rst_n_c3_q   <= 1'b0;
      rst_n_pre_q  <= 1'b0;
      rst_n_fsm1_q <= 1'b0;
      rst_n_fsm2_q <= 1'b0;
    end else begin
      rst_n_sync_q <= 1'b1;
      rst_n_c1_q   <= 1'b1;
      rst_n_c2_q   <= 1'b1;
      rst_n_c3_q   <= 1'b1;
      rst_n_pre_q  <= 1'b1;
      rst_n_fsm1_q <= 1'b1;
      rst_n_fsm2_q <= 1'b1;
    end
  end

  // ----------------------------------------------------------------------------
  // 1. 2-FF CDC Synchronizer + Fine-Grained (<=6-Bit) Configuration Pipeline
  // ----------------------------------------------------------------------------
  logic        bypass_s1, bypass_s2;
  logic [4:0]  shift_s1,  shift_s2;
  logic [9:0]  int_s1,    int_s2;
  logic [7:0]  frac_s1,   frac_s2;
  logic [7:0]  duty_s1,   duty_s2;

  logic [4:0]  clamped_shift_w;
  logic [9:0]  eff_int_w;
  logic [7:0]  clamped_duty_w;

  // Stage c0: Clamped configuration inputs
  logic        bypass_c0;
  logic [4:0]  shift_c0;
  logic [9:0]  int_c0;
  logic [7:0]  duty_c0;
  logic [7:0]  frac_c0;

  // Stage c1: 3*int lower 6 bits + basic flags
  logic        bypass_c1;
  logic [4:0]  shift_c1;
  logic [9:0]  int_c1;
  logic [7:0]  duty_c1;
  logic [7:0]  frac_c1;
  logic        duty_128_c1;
  logic        int_eq1_c1;
  logic        shift_z_c1;
  logic        frac_nz_c1;
  logic        x3_c_c1;
  logic [4:0]  x3_lo5_c1;
  logic        x3_b0_c1;

  // Stage c2: 3*int upper 6 bits + (int - 1) lower 5 bits + mode decode
  logic [4:0]  mask_sub_w;
  logic [4:0]  shift_c2;
  logic [4:0]  mask_sub_c2;
  logic [9:0]  int_c2;
  logic [7:0]  duty_c2;
  logic [7:0]  frac_c2;
  logic        duty_128_c2;
  logic        int_eq1_c2;
  logic        pure_bypass_c2;
  logic        pulse_stretch_c2;
  logic [5:0]  x3_hi6_c2;
  logic [4:0]  x3_lo5_c2;
  logic        x3_b0_c2;
  logic [4:0]  m1_lo_c2;
  logic        m1_b_c2;

  // Stage c3: 4:1 MUX radix-4 partial products (0, X, 2X, 3X) + (int - 1) upper 5 bits
  logic [11:0] x3_full_w;
  logic [11:0] pp0_w, pp1_w, pp2_w, pp3_w;
  logic [4:0]  shift_c3;
  logic [4:0]  mask_sub_c3;
  logic [9:0]  int_c3;
  logic [9:0]  int_m1_c3;
  logic [7:0]  frac_c3;
  logic        duty_128_c3;
  logic        int_eq1_c3;
  logic        pure_bypass_c3;
  logic        pulse_stretch_c3;
  logic [11:0] pp0_c3, pp1_c3, pp2_c3, pp3_c3;

  // Stage c4: Pairwise partial-product sums (lower 6 bits)
  logic [4:0]  shift_c4;
  logic [4:0]  mask_sub_c4;
  logic [9:0]  int_c4;
  logic [9:0]  int_m1_c4;
  logic [7:0]  frac_c4;
  logic        duty_128_c4;
  logic        int_eq1_c4;
  logic        pure_bypass_c4;
  logic        pulse_stretch_c4;
  logic        slo_c_c4, shi_c_c4;
  logic [5:0]  slo_mid6_c4, shi_mid6_c4;
  logic [1:0]  shi_lo2_c4;
  logic [3:0]  pp0_top4_c4, pp2_top4_c4;
  logic [5:0]  pp1_top6_c4, pp3_top6_c4;

  // Stage c5: Pairwise partial-product sums (upper 6 bits) + prod_top lower 4 bits
  logic [4:0]  shift_c5;
  logic [4:0]  mask_sub_c5;
  logic [9:0]  int_c5;
  logic [9:0]  int_m1_c5;
  logic [7:0]  frac_c5;
  logic        duty_128_c5;
  logic        int_eq1_c5;
  logic        pure_bypass_c5;
  logic        pulse_stretch_c5;
  logic [5:0]  slo_top6_c5, shi_top6_c5;
  logic [3:0]  shi_mid4_c5;
  logic        ptop_c4_c5;
  logic [3:0]  ptop_lo4_c5;

  // Stage c6: prod_top middle 5 bits + rounding bit
  logic [4:0]  shift_c6;
  logic [4:0]  mask_sub_c6;
  logic [9:0]  int_c6;
  logic [9:0]  int_m1_c6;
  logic [7:0]  frac_c6;
  logic        duty_128_c6;
  logic        int_eq1_c6;
  logic        pure_bypass_c6;
  logic        pulse_stretch_c6;
  logic        ptop_c9_c6;
  logic [4:0]  ptop_mid5_c6;
  logic        slo_b13_c6;
  logic [4:0]  shi_top5_c6;
  logic        round_b_c6;

  // Stage c7: prod_top upper 5 bits + rounded duty_scaled lower 5 bits
  logic [4:0]  shift_c7;
  logic [4:0]  mask_sub_c7;
  logic [9:0]  int_c7;
  logic [9:0]  int_m1_c7;
  logic [7:0]  frac_c7;
  logic        duty_128_c7;
  logic        int_eq1_c7;
  logic        pure_bypass_c7;
  logic        pulse_stretch_c7;
  logic        dsc_c5_c7;
  logic [4:0]  dsc_lo5_c7;
  logic [4:0]  ptop_hi5_c7;

  // Stage c8: Rounded duty_scaled upper 5 bits + lower 5-bit bound check
  logic [4:0]  shift_c8;
  logic [4:0]  mask_sub_c8;
  logic [9:0]  int_c8;
  logic [9:0]  int_m1_c8;
  logic [7:0]  frac_c8;
  logic        duty_128_c8;
  logic        int_eq1_c8;
  logic        pure_bypass_c8;
  logic        pulse_stretch_c8;
  logic [4:0]  duty_hi5_c8;
  logic [4:0]  duty_lo5_c8;
  logic        ge_lo_c8;
  logic        dsc_lo_z_c8;

  // Stage c9: Clamped high_cycles selection (5-bit upper compare + MUX)
  logic        duty_ge_int_w;
  logic        duty_is_z_w;
  logic [9:0]  high_cycles_w;
  logic [4:0]  shift_c9;
  logic [4:0]  mask_sub_c9;
  logic [9:0]  int_c9;
  logic [9:0]  int_m1_c9;
  logic [7:0]  frac_c9;
  logic        int_eq1_c9;
  logic        pure_bypass_c9;
  logic        pulse_stretch_c9;
  logic [9:0]  high_cycles_c9;

  // Stage c10: (high_cycles - 1) lower 5 bits + band decode
  logic [4:0]  shift_c10;
  logic [3:0]  band_c10;
  logic [4:0]  mask_sub_c10;
  logic [9:0]  int_c10;
  logic [9:0]  int_m1_c10;
  logic [7:0]  frac_c10;
  logic        int_eq1_c10;
  logic        pure_bypass_c10;
  logic        pulse_stretch_c10;
  logic [4:0]  hm1_lo_c10;
  logic        hm1_b_c10;
  logic [4:0]  hc_hi5_c10;
  logic        hc_eq1_c10;

  // Final pre-decoded configuration registers
  logic [4:0]  shift_reg;
  logic        shift_zero_reg;
  logic [3:0]  band_reg;
  logic [4:0]  mask_sub_reg;
  logic [9:0]  int_reg;
  logic        int_lo_zero_reg;
  logic        int_hi_zero_reg;
  logic [9:0]  int_m1_reg;
  logic        int_m1_zero_reg;
  logic        int_m1_lo_zero_reg;
  logic        int_m1_hi_zero_reg;
  logic [9:0]  high_m1_reg;
  logic        high_m1_zero_reg;
  logic        high_m1_lo_zero_reg;
  logic        high_m1_hi_zero_reg;
  logic [7:0]  frac_reg;
  logic        pure_bypass_reg;
  logic        pulse_stretch_mode_reg;

  function automatic logic [11:0] sel_pp4(
    input logic [1:0]  sel,
    input logic [9:0]  x1,
    input logic [11:0] x3
  );
    case (sel)
      2'b00:   sel_pp4 = 12'd0;
      2'b01:   sel_pp4 = {2'd0, x1};
      2'b10:   sel_pp4 = {1'd0, x1, 1'b0};
      default: sel_pp4 = x3;
    endcase
  endfunction

  always_comb begin
    clamped_shift_w = (shift_s2 > 5'd20) ? 5'd20 : shift_s2;
    clamped_duty_w  = (duty_s2 == 8'd0)  ? 8'd128 : duty_s2;
    if (clamped_shift_w != 5'd0 && (int_s2[9:1] == 9'd0))
      eff_int_w = 10'd2;
    else if (int_s2 == 10'd0)
      eff_int_w = 10'd1;
    else
      eff_int_w = int_s2;

    case (shift_c1)
      5'd1, 5'd6,  5'd11, 5'd16: mask_sub_w = 5'b00001;
      5'd2, 5'd7,  5'd12, 5'd17: mask_sub_w = 5'b00011;
      5'd3, 5'd8,  5'd13, 5'd18: mask_sub_w = 5'b00111;
      5'd4, 5'd9,  5'd14, 5'd19: mask_sub_w = 5'b01111;
      default:                   mask_sub_w = 5'b11111;
    endcase

    x3_full_w = {x3_hi6_c2, x3_lo5_c2, x3_b0_c2};
    pp0_w     = sel_pp4(duty_c2[1:0], int_c2, x3_full_w);
    pp1_w     = sel_pp4(duty_c2[3:2], int_c2, x3_full_w);
    pp2_w     = sel_pp4(duty_c2[5:4], int_c2, x3_full_w);
    pp3_w     = sel_pp4(duty_c2[7:6], int_c2, x3_full_w);

    duty_ge_int_w = (duty_hi5_c8 > int_c8[9:5]) || ((duty_hi5_c8 == int_c8[9:5]) && ge_lo_c8);
    duty_is_z_w   = (duty_hi5_c8 == 5'd0) && dsc_lo_z_c8;
    if (int_eq1_c8) begin
      high_cycles_w = 10'd1;
    end else if (duty_128_c8) begin
      high_cycles_w = {1'b0, int_c8[9:1]};
    end else if (duty_is_z_w) begin
      high_cycles_w = 10'd1;
    end else if (duty_ge_int_w) begin
      high_cycles_w = int_m1_c8;
    end else begin
      high_cycles_w = {duty_hi5_c8, duty_lo5_c8};
    end
  end

  // CDC + Stages c0..c1 (~75 FFs on rst_n_sync_q)
  always_ff @(posedge clk_dco or negedge rst_n_sync_q) begin
    if (!rst_n_sync_q) begin
      bypass_s1   <= 1'b0;
      bypass_s2   <= 1'b0;
      shift_s1    <= 5'd0;
      shift_s2    <= 5'd0;
      int_s1      <= 10'd10;
      int_s2      <= 10'd10;
      frac_s1     <= 8'd0;
      frac_s2     <= 8'd0;
      duty_s1     <= 8'd128;
      duty_s2     <= 8'd128;

      bypass_c0   <= 1'b0;
      shift_c0    <= 5'd0;
      int_c0      <= 10'd10;
      duty_c0     <= 8'd128;
      frac_c0     <= 8'd0;

      bypass_c1   <= 1'b0;
      shift_c1    <= 5'd0;
      int_c1      <= 10'd10;
      duty_c1     <= 8'd128;
      frac_c1     <= 8'd0;
      duty_128_c1 <= 1'b1;
      int_eq1_c1  <= 1'b0;
      shift_z_c1  <= 1'b1;
      frac_nz_c1  <= 1'b0;
      x3_c_c1     <= 1'b0;
      x3_lo5_c1   <= 5'd15;
      x3_b0_c1    <= 1'b0;
    end else begin
      bypass_s1   <= out_div_bypass;
      bypass_s2   <= bypass_s1;
      shift_s1    <= out_prescale_shift;
      shift_s2    <= shift_s1;
      int_s1      <= out_div_int;
      int_s2      <= int_s1;
      frac_s1     <= out_div_frac;
      frac_s2     <= frac_s1;
      duty_s1     <= out_duty;
      duty_s2     <= duty_s1;

      bypass_c0   <= bypass_s2;
      shift_c0    <= clamped_shift_w;
      int_c0      <= eff_int_w;
      duty_c0     <= clamped_duty_w;
      frac_c0     <= frac_s2;

      bypass_c1   <= bypass_c0;
      shift_c1    <= shift_c0;
      int_c1      <= int_c0;
      duty_c1     <= duty_c0;
      frac_c1     <= frac_c0;
      duty_128_c1 <= (duty_c0 == 8'd128);
      int_eq1_c1  <= (int_c0 == 10'd1);
      shift_z_c1  <= (shift_c0 == 5'd0);
      frac_nz_c1  <= (frac_c0 != 8'd0);
      {x3_c_c1, x3_lo5_c1} <= {1'b0, int_c0[5:1]} + {1'b0, int_c0[4:0]};
      x3_b0_c1    <= int_c0[0];
    end
  end

  // Stages c2..c4 (~115 FFs split across rst_n_c1_q)
  always_ff @(posedge clk_dco or negedge rst_n_c1_q) begin
    if (!rst_n_c1_q) begin
      shift_c2         <= 5'd0;
      mask_sub_c2      <= 5'b11111;
      int_c2           <= 10'd10;
      duty_c2          <= 8'd128;
      frac_c2          <= 8'd0;
      duty_128_c2      <= 1'b1;
      int_eq1_c2       <= 1'b0;
      pure_bypass_c2   <= 1'b0;
      pulse_stretch_c2 <= 1'b0;
      x3_hi6_c2        <= 6'd0;
      x3_lo5_c2        <= 5'd15;
      x3_b0_c2         <= 1'b0;
      m1_lo_c2         <= 5'd9;
      m1_b_c2          <= 1'b0;

      shift_c3         <= 5'd0;
      mask_sub_c3      <= 5'b11111;
      int_c3           <= 10'd10;
      int_m1_c3        <= 10'd9;
      frac_c3          <= 8'd0;
      duty_128_c3      <= 1'b1;
      int_eq1_c3       <= 1'b0;
      pure_bypass_c3   <= 1'b0;
      pulse_stretch_c3 <= 1'b0;
      pp0_c3           <= 12'd0;
      pp1_c3           <= 12'd0;
      pp2_c3           <= 12'd0;
      pp3_c3           <= 12'd20;

      shift_c4         <= 5'd0;
      mask_sub_c4      <= 5'b11111;
      int_c4           <= 10'd10;
      int_m1_c4        <= 10'd9;
      frac_c4          <= 8'd0;
      duty_128_c4      <= 1'b1;
      int_eq1_c4       <= 1'b0;
      pure_bypass_c4   <= 1'b0;
      pulse_stretch_c4 <= 1'b0;
      slo_c_c4         <= 1'b0;
      slo_mid6_c4      <= 6'd0;
      shi_c_c4         <= 1'b0;
      shi_mid6_c4      <= 6'd20;
      shi_lo2_c4       <= 2'd0;
      pp0_top4_c4      <= 4'd0;
      pp1_top6_c4      <= 6'd0;
      pp2_top4_c4      <= 4'd0;
      pp3_top6_c4      <= 6'd0;
    end else begin
      shift_c2         <= shift_c1;
      mask_sub_c2      <= mask_sub_w;
      int_c2           <= int_c1;
      duty_c2          <= duty_c1;
      frac_c2          <= frac_c1;
      duty_128_c2      <= duty_128_c1;
      int_eq1_c2       <= int_eq1_c1;
      pure_bypass_c2   <= bypass_c1 || (shift_z_c1 && int_eq1_c1 && !frac_nz_c1);
      pulse_stretch_c2 <= (!bypass_c1) && shift_z_c1 && int_eq1_c1 && frac_nz_c1;
      x3_hi6_c2        <= {2'd0, int_c1[9:6]} + {1'b0, int_c1[9:5]} + {5'd0, x3_c_c1};
      x3_lo5_c2        <= x3_lo5_c1;
      x3_b0_c2         <= x3_b0_c1;
      m1_lo_c2         <= int_c1[4:0] - 5'd1;
      m1_b_c2          <= (int_c1[4:0] == 5'd0);

      shift_c3         <= shift_c2;
      mask_sub_c3      <= mask_sub_c2;
      int_c3           <= int_c2;
      int_m1_c3        <= { (int_c2[9:5] - {4'd0, m1_b_c2}), m1_lo_c2 };
      frac_c3          <= frac_c2;
      duty_128_c3      <= duty_128_c2;
      int_eq1_c3       <= int_eq1_c2;
      pure_bypass_c3   <= pure_bypass_c2;
      pulse_stretch_c3 <= pulse_stretch_c2;
      pp0_c3           <= pp0_w;
      pp1_c3           <= pp1_w;
      pp2_c3           <= pp2_w;
      pp3_c3           <= pp3_w;

      shift_c4                  <= shift_c3;
      mask_sub_c4               <= mask_sub_c3;
      int_c4                    <= int_c3;
      int_m1_c4                 <= int_m1_c3;
      frac_c4                   <= frac_c3;
      duty_128_c4               <= duty_128_c3;
      int_eq1_c4                <= int_eq1_c3;
      pure_bypass_c4            <= pure_bypass_c3;
      pulse_stretch_c4          <= pulse_stretch_c3;
      {slo_c_c4, slo_mid6_c4}   <= {1'b0, pp0_c3[7:2]} + {1'b0, pp1_c3[5:0]};
      {shi_c_c4, shi_mid6_c4}   <= {1'b0, pp2_c3[7:2]} + {1'b0, pp3_c3[5:0]};
      shi_lo2_c4                <= pp2_c3[1:0];
      pp0_top4_c4               <= pp0_c3[11:8];
      pp1_top6_c4               <= pp1_c3[11:6];
      pp2_top4_c4               <= pp2_c3[11:8];
      pp3_top6_c4               <= pp3_c3[11:6];
    end
  end

  // Stages c5..c7 (~110 FFs on rst_n_c2_q)
  always_ff @(posedge clk_dco or negedge rst_n_c2_q) begin
    if (!rst_n_c2_q) begin
      shift_c5         <= 5'd0;
      mask_sub_c5      <= 5'b11111;
      int_c5           <= 10'd10;
      int_m1_c5        <= 10'd9;
      frac_c5          <= 8'd0;
      duty_128_c5      <= 1'b1;
      int_eq1_c5       <= 1'b0;
      pure_bypass_c5   <= 1'b0;
      pulse_stretch_c5 <= 1'b0;
      slo_top6_c5      <= 6'd0;
      shi_top6_c5      <= 6'd0;
      shi_mid4_c5      <= 4'd5;
      ptop_c4_c5       <= 1'b0;
      ptop_lo4_c5      <= 4'd0;

      shift_c6         <= 5'd0;
      mask_sub_c6      <= 5'b11111;
      int_c6           <= 10'd10;
      int_m1_c6        <= 10'd9;
      frac_c6          <= 8'd0;
      duty_128_c6      <= 1'b1;
      int_eq1_c6       <= 1'b0;
      pure_bypass_c6   <= 1'b0;
      pulse_stretch_c6 <= 1'b0;
      ptop_c9_c6       <= 1'b0;
      ptop_mid5_c6     <= 5'd5;
      slo_b13_c6       <= 1'b0;
      shi_top5_c6      <= 5'd0;
      round_b_c6       <= 1'b0;

      shift_c7         <= 5'd0;
      mask_sub_c7      <= 5'b11111;
      int_c7           <= 10'd10;
      int_m1_c7        <= 10'd9;
      frac_c7          <= 8'd0;
      duty_128_c7      <= 1'b1;
      int_eq1_c7       <= 1'b0;
      pure_bypass_c7   <= 1'b0;
      pulse_stretch_c7 <= 1'b0;
      dsc_c5_c7        <= 1'b0;
      dsc_lo5_c7       <= 5'd5;
      ptop_hi5_c7      <= 5'd0;
    end else begin
      shift_c5                    <= shift_c4;
      mask_sub_c5                 <= mask_sub_c4;
      int_c5                      <= int_c4;
      int_m1_c5                   <= int_m1_c4;
      frac_c5                     <= frac_c4;
      duty_128_c5                 <= duty_128_c4;
      int_eq1_c5                  <= int_eq1_c4;
      pure_bypass_c5              <= pure_bypass_c4;
      pulse_stretch_c5            <= pulse_stretch_c4;
      slo_top6_c5                 <= {2'd0, pp0_top4_c4} + pp1_top6_c4 + {5'd0, slo_c_c4};
      shi_top6_c5                 <= {2'd0, pp2_top4_c4} + pp3_top6_c4 + {5'd0, shi_c_c4};
      shi_mid4_c5                 <= shi_mid6_c4[5:2];
      {ptop_c4_c5, ptop_lo4_c5}   <= {1'b0, slo_mid6_c4[5:2]} + {1'b0, shi_mid6_c4[1:0], shi_lo2_c4};

      shift_c6                    <= shift_c5;
      mask_sub_c6                 <= mask_sub_c5;
      int_c6                      <= int_c5;
      int_m1_c6                   <= int_m1_c5;
      frac_c6                     <= frac_c5;
      duty_128_c6                 <= duty_128_c5;
      int_eq1_c6                  <= int_eq1_c5;
      pure_bypass_c6              <= pure_bypass_c5;
      pulse_stretch_c6            <= pulse_stretch_c5;
      {ptop_c9_c6, ptop_mid5_c6}  <= {1'b0, slo_top6_c5[4:0]} + {1'b0, shi_top6_c5[0], shi_mid4_c5} + {5'd0, ptop_c4_c5};
      slo_b13_c6                  <= slo_top6_c5[5];
      shi_top5_c6                 <= shi_top6_c5[5:1];
      round_b_c6                  <= ptop_lo4_c5[3];

      shift_c7                    <= shift_c6;
      mask_sub_c7                 <= mask_sub_c6;
      int_c7                      <= int_c6;
      int_m1_c7                   <= int_m1_c6;
      frac_c7                     <= frac_c6;
      duty_128_c7                 <= duty_128_c6;
      int_eq1_c7                  <= int_eq1_c6;
      pure_bypass_c7              <= pure_bypass_c6;
      pulse_stretch_c7            <= pulse_stretch_c6;
      {dsc_c5_c7, dsc_lo5_c7}     <= {1'b0, ptop_mid5_c6} + {5'd0, round_b_c6};
      ptop_hi5_c7                 <= {4'd0, slo_b13_c6} + shi_top5_c6 + {4'd0, ptop_c9_c6};
    end
  end

  // Stages c8..reg (~140 FFs on rst_n_c3_q)
  always_ff @(posedge clk_dco or negedge rst_n_c3_q) begin
    if (!rst_n_c3_q) begin
      shift_c8               <= 5'd0;
      mask_sub_c8            <= 5'b11111;
      int_c8                 <= 10'd10;
      int_m1_c8              <= 10'd9;
      frac_c8                <= 8'd0;
      duty_128_c8            <= 1'b1;
      int_eq1_c8             <= 1'b0;
      pure_bypass_c8         <= 1'b0;
      pulse_stretch_c8       <= 1'b0;
      duty_hi5_c8            <= 5'd0;
      duty_lo5_c8            <= 5'd5;
      ge_lo_c8               <= 1'b0;
      dsc_lo_z_c8            <= 1'b0;

      shift_c9               <= 5'd0;
      mask_sub_c9            <= 5'b11111;
      int_c9                 <= 10'd10;
      int_m1_c9              <= 10'd9;
      frac_c9                <= 8'd0;
      int_eq1_c9             <= 1'b0;
      pure_bypass_c9         <= 1'b0;
      pulse_stretch_c9       <= 1'b0;
      high_cycles_c9         <= 10'd5;

      shift_c10              <= 5'd0;
      band_c10               <= 4'b0001;
      mask_sub_c10           <= 5'b11111;
      int_c10                <= 10'd10;
      int_m1_c10             <= 10'd9;
      frac_c10               <= 8'd0;
      int_eq1_c10            <= 1'b0;
      pure_bypass_c10        <= 1'b0;
      pulse_stretch_c10      <= 1'b0;
      hm1_lo_c10             <= 5'd4;
      hm1_b_c10              <= 1'b0;
      hc_hi5_c10             <= 5'd0;
      hc_eq1_c10             <= 1'b0;

      shift_reg              <= 5'd0;
      shift_zero_reg         <= 1'b1;
      band_reg               <= 4'b0001;
      mask_sub_reg           <= 5'b11111;
      int_reg                <= 10'd10;
      int_lo_zero_reg        <= 1'b0;
      int_hi_zero_reg        <= 1'b1;
      int_m1_reg             <= 10'd9;
      int_m1_zero_reg        <= 1'b0;
      int_m1_lo_zero_reg     <= 1'b0;
      int_m1_hi_zero_reg     <= 1'b1;
      high_m1_reg            <= 10'd4;
      high_m1_zero_reg       <= 1'b0;
      high_m1_lo_zero_reg    <= 1'b0;
      high_m1_hi_zero_reg    <= 1'b1;
      frac_reg               <= 8'd0;
      pure_bypass_reg        <= 1'b0;
      pulse_stretch_mode_reg <= 1'b0;
    end else begin
      shift_c8               <= shift_c7;
      mask_sub_c8            <= mask_sub_c7;
      int_c8                 <= int_c7;
      int_m1_c8              <= int_m1_c7;
      frac_c8                <= frac_c7;
      duty_128_c8            <= duty_128_c7;
      int_eq1_c8             <= int_eq1_c7;
      pure_bypass_c8         <= pure_bypass_c7;
      pulse_stretch_c8       <= pulse_stretch_c7;
      duty_hi5_c8            <= ptop_hi5_c7 + {4'd0, dsc_c5_c7};
      duty_lo5_c8            <= dsc_lo5_c7;
      ge_lo_c8               <= (dsc_lo5_c7 >= int_c7[4:0]);
      dsc_lo_z_c8            <= (dsc_lo5_c7 == 5'd0);

      shift_c9               <= shift_c8;
      mask_sub_c9            <= mask_sub_c8;
      int_c9                 <= int_c8;
      int_m1_c9              <= int_m1_c8;
      frac_c9                <= frac_c8;
      int_eq1_c9             <= int_eq1_c8;
      pure_bypass_c9         <= pure_bypass_c8;
      pulse_stretch_c9       <= pulse_stretch_c8;
      high_cycles_c9         <= high_cycles_w;

      shift_c10              <= shift_c9;
      band_c10[0]            <= (shift_c9 <= 5'd5);
      band_c10[1]            <= (shift_c9 > 5'd5)  && (shift_c9 <= 5'd10);
      band_c10[2]            <= (shift_c9 > 5'd10) && (shift_c9 <= 5'd15);
      band_c10[3]            <= (shift_c9 > 5'd15);
      mask_sub_c10           <= mask_sub_c9;
      int_c10                <= int_c9;
      int_m1_c10             <= int_m1_c9;
      frac_c10               <= frac_c9;
      int_eq1_c10            <= int_eq1_c9;
      pure_bypass_c10        <= pure_bypass_c9;
      pulse_stretch_c10      <= pulse_stretch_c9;
      hm1_lo_c10             <= high_cycles_c9[4:0] - 5'd1;
      hm1_b_c10              <= (high_cycles_c9[4:0] == 5'd0);
      hc_hi5_c10             <= high_cycles_c9[9:5];
      hc_eq1_c10             <= (high_cycles_c9 == 10'd1);

      shift_reg              <= shift_c10;
      shift_zero_reg         <= (shift_c10 == 5'd0);
      band_reg               <= band_c10;
      mask_sub_reg           <= mask_sub_c10;
      int_reg                <= int_c10;
      int_lo_zero_reg        <= (int_c10[4:0] == 5'd0);
      int_hi_zero_reg        <= (int_c10[9:5] == 5'd0);
      int_m1_reg             <= int_m1_c10;
      int_m1_zero_reg        <= int_eq1_c10;
      int_m1_lo_zero_reg     <= (int_m1_c10[4:0] == 5'd0);
      int_m1_hi_zero_reg     <= (int_m1_c10[9:5] == 5'd0);
      high_m1_reg            <= { (hc_hi5_c10 - {4'd0, hm1_b_c10}), hm1_lo_c10 };
      high_m1_zero_reg       <= hc_eq1_c10;
      high_m1_lo_zero_reg    <= (hm1_lo_c10 == 5'd0);
      high_m1_hi_zero_reg    <= ((hc_hi5_c10 - {4'd0, hm1_b_c10}) == 5'd0);
      frac_reg               <= frac_c10;
      pure_bypass_reg        <= pure_bypass_c10;
      pulse_stretch_mode_reg <= pulse_stretch_c10;
    end
  end

  // ----------------------------------------------------------------------------
  // 2. Active Prescaler Shadow Registers & Replicated Mode Flags
  // ----------------------------------------------------------------------------
  logic [4:0] shift_act;
  logic       shift_zero_act;
  logic [3:0] band_act;
  logic [4:0] mask_sub_act;
  logic       bypass_act;
  logic       stretch_mode_act;
  (* keep = "true" *) logic stretch_mode_st_q;
  (* keep = "true" *) logic div_mode_cnt_q;
  (* keep = "true" *) logic div_mode_cfg_q;
  (* keep = "true" *) logic div_mode_pre_q;

  // ----------------------------------------------------------------------------
  // 3. 4-Stage Pipelined 20-Bit Octave Prescaler (2^0 to 2^20)
  // ----------------------------------------------------------------------------
  logic [4:0] p0, p1, p2, p3;
  logic       p0_max, p1_max, p2_max;
  logic       m0_hit, m1_hit, m2_hit, m3_hit;
  logic       pre_tick;
  logic       prescale_Reload;

  assign m0_hit = &(p0 | ~mask_sub_act);
  assign m1_hit = &(p1 | ~mask_sub_act);
  assign m2_hit = &(p2 | ~mask_sub_act);
  assign m3_hit = &(p3 | ~mask_sub_act);

  always_ff @(posedge clk_dco or negedge rst_n_pre_q) begin
    if (!rst_n_pre_q) begin
      p0       <= 5'd0;
      p1       <= 5'd0;
      p2       <= 5'd0;
      p3       <= 5'd0;
      p0_max   <= 1'b0;
      p1_max   <= 1'b0;
      p2_max   <= 1'b0;
      pre_tick <= 1'b1;
    end else if (!div_mode_pre_q || shift_zero_act || prescale_Reload) begin
      p0       <= 5'd0;
      p1       <= 5'd0;
      p2       <= 5'd0;
      p3       <= 5'd0;
      p0_max   <= 1'b0;
      p1_max   <= 1'b0;
      p2_max   <= 1'b0;
      pre_tick <= shift_zero_reg;
    end else begin
      p0     <= p0 + 5'd1;
      p0_max <= (p0 == 5'h1E);

      if (p0_max) begin
        p1     <= p1 + 5'd1;
        p1_max <= (p1 == 5'h1E);
      end

      if (p0_max && p1_max) begin
        p2     <= p2 + 5'd1;
        p2_max <= (p2 == 5'h1E);
      end

      if (p0_max && p1_max && p2_max) begin
        p3 <= p3 + 5'd1;
      end

      pre_tick <= (band_act[0] && m0_hit) ||
                  (band_act[1] && p0_max && m1_hit) ||
                  (band_act[2] && p0_max && p1_max && m2_hit) ||
                  (band_act[3] && p0_max && p1_max && p2_max && m3_hit);
    end
  end

  // ----------------------------------------------------------------------------
  // 4. Glitch-Free Fractional-N State Machine (4-Bit Carry-Save SDMs + 5+5-Bit Counters)
  // ----------------------------------------------------------------------------
  logic [3:0] div_acc_lo;
  logic [3:0] div_acc_hi;
  logic [3:0] div_next_hi_q;
  logic [3:0] div_frac_hi_q;
  logic       div_lo_c;
  logic       div_sdm_carry_q;
  logic [3:0] st_acc_lo;
  logic [3:0] st_acc_hi;
  logic [3:0] st_frac_hi_q;
  logic       st_lo_c;
  logic [4:0] st_hi_sum_comb;
  logic [9:0] cnt;
  logic [9:0] high_cnt;
  logic       cnt_lo_zero_q, cnt_hi_zero_q;
  logic       high_lo_zero_q, high_hi_zero_q;
  (* keep = "true" *) logic cnt_zero_q;
  (* keep = "true" *) logic cnt_zero_cfg_q;
  (* keep = "true" *) logic cnt_zero_pre_q;
  logic       high_zero_q;
  logic       div_clk_reg;
  logic       pass_dco_clk;
  logic       stretch_active;
  logic       bypass_arm;
  (* keep = "true" *) logic clk_dco_b1;
  (* keep = "true" *) logic clk_dco_mux;
  (* keep = "true" *) logic clk_base;

  assign st_hi_sum_comb  = {1'b0, st_acc_hi} + {1'b0, st_frac_hi_q} + {4'd0, st_lo_c};
  assign prescale_Reload = div_mode_pre_q && (!bypass_arm) && pre_tick && cnt_zero_pre_q && (shift_act != shift_reg);

  // Mode Controller, Output Mux Controls & 4+4-Bit Carry-Save SDMs (rst_n_fsm1_q)
  always_ff @(posedge clk_dco or negedge rst_n_fsm1_q) begin
    if (!rst_n_fsm1_q) begin
      shift_act         <= 5'd0;
      shift_zero_act    <= 1'b1;
      band_act          <= 4'b0001;
      mask_sub_act      <= 5'b11111;
      bypass_act        <= 1'b0;
      stretch_mode_act  <= 1'b0;
      stretch_mode_st_q <= 1'b0;
      div_mode_cnt_q    <= 1'b1;
      div_mode_cfg_q    <= 1'b1;
      div_mode_pre_q    <= 1'b1;
      div_acc_lo        <= 4'd0;
      div_acc_hi        <= 4'd0;
      div_next_hi_q     <= 4'd0;
      div_frac_hi_q     <= 4'd0;
      div_lo_c          <= 1'b0;
      div_sdm_carry_q   <= 1'b0;
      st_acc_lo         <= 4'd0;
      st_acc_hi         <= 4'd0;
      st_frac_hi_q      <= 4'd0;
      st_lo_c           <= 1'b0;
      div_clk_reg       <= 1'b1;
      pass_dco_clk      <= 1'b0;
      stretch_active    <= 1'b0;
      bypass_arm        <= 1'b0;
    end else begin
      // Active prescaler parameters update cleanly whenever out of divider mode or at period end
      if (!div_mode_cfg_q || (!bypass_arm && pre_tick && cnt_zero_cfg_q)) begin
        shift_act      <= shift_reg;
        shift_zero_act <= shift_zero_reg;
        band_act       <= band_reg;
        mask_sub_act   <= mask_sub_reg;
      end

      // Isolated 4+4-bit pulse-stretch SDM
      if (!stretch_mode_st_q) begin
        st_acc_lo    <= 4'd0;
        st_acc_hi    <= 4'd0;
        st_frac_hi_q <= frac_reg[7:4];
        st_lo_c      <= 1'b0;
      end else if (!stretch_active && !pure_bypass_reg && pulse_stretch_mode_reg) begin
        st_frac_hi_q         <= frac_reg[7:4];
        {st_lo_c, st_acc_lo} <= {1'b0, st_acc_lo} + {1'b0, frac_reg[3:0]};
        st_acc_hi            <= st_hi_sum_comb[3:0];
      end

      // Isolated 4+4-bit divider-mode SDM (always >=2 cycles per period in divider mode)
      if (!div_mode_cnt_q) begin
        div_acc_lo      <= 4'd0;
        div_acc_hi      <= 4'd0;
        div_next_hi_q   <= frac_reg[7:4];
        div_frac_hi_q   <= frac_reg[7:4];
        div_lo_c        <= 1'b0;
        div_sdm_carry_q <= 1'b0;
      end else if (!bypass_arm) begin
        if (pre_tick && cnt_zero_q) begin
          {div_lo_c, div_acc_lo} <= {1'b0, div_acc_lo} + {1'b0, frac_reg[3:0]};
          div_frac_hi_q          <= frac_reg[7:4];
          div_acc_hi             <= div_next_hi_q;
        end else begin
          {div_sdm_carry_q, div_next_hi_q} <= {1'b0, div_acc_hi} + {1'b0, div_frac_hi_q} + {4'd0, div_lo_c};
        end
      end

      // Glitch-free mode & clock gate transitions
      if (bypass_act) begin
        div_clk_reg    <= 1'b1;
        stretch_active <= 1'b0;
        bypass_arm     <= 1'b0;
        if (!pure_bypass_reg) begin
          bypass_act        <= 1'b0;
          stretch_mode_act  <= pulse_stretch_mode_reg;
          stretch_mode_st_q <= pulse_stretch_mode_reg;
          div_mode_cnt_q    <= !pulse_stretch_mode_reg;
          div_mode_cfg_q    <= !pulse_stretch_mode_reg;
          div_mode_pre_q    <= !pulse_stretch_mode_reg;
          pass_dco_clk      <= pulse_stretch_mode_reg ? 1'b1 : 1'b0;
        end else begin
          pass_dco_clk <= 1'b1;
        end
      end else if (stretch_mode_act) begin
        div_clk_reg <= 1'b1;
        bypass_arm  <= 1'b0;
        if (stretch_active) begin
          stretch_active <= 1'b0;
          pass_dco_clk   <= 1'b1;
        end else if (pure_bypass_reg || !pulse_stretch_mode_reg) begin
          bypass_act        <= pure_bypass_reg;
          stretch_mode_act  <= 1'b0;
          stretch_mode_st_q <= 1'b0;
          div_mode_cnt_q    <= !pure_bypass_reg;
          div_mode_cfg_q    <= !pure_bypass_reg;
          div_mode_pre_q    <= !pure_bypass_reg;
          pass_dco_clk      <= pure_bypass_reg ? 1'b1 : 1'b0;
        end else if (st_hi_sum_comb[4]) begin
          stretch_active <= 1'b1;
          pass_dco_clk   <= 1'b0;
        end else begin
          stretch_active <= 1'b0;
          pass_dco_clk   <= 1'b1;
        end
      end else begin
        stretch_active <= 1'b0;
        if (bypass_arm) begin
          bypass_arm        <= 1'b0;
          bypass_act        <= 1'b1;
          stretch_mode_act  <= 1'b0;
          stretch_mode_st_q <= 1'b0;
          div_mode_cnt_q    <= 1'b0;
          div_mode_cfg_q    <= 1'b0;
          div_mode_pre_q    <= 1'b0;
          div_clk_reg       <= 1'b1;
          pass_dco_clk      <= 1'b1;
        end else if (pre_tick) begin
          if (cnt_zero_q) begin
            div_clk_reg  <= 1'b1;
            pass_dco_clk <= 1'b0;
            if (pure_bypass_reg) begin
              bypass_arm <= 1'b1;
            end else if (pulse_stretch_mode_reg) begin
              stretch_mode_act  <= 1'b1;
              stretch_mode_st_q <= 1'b1;
              div_mode_cnt_q    <= 1'b0;
              div_mode_cfg_q    <= 1'b0;
              div_mode_pre_q    <= 1'b0;
            end
          end else if (high_zero_q) begin
            div_clk_reg <= 1'b0;
          end
        end
      end
    end
  end

  // Dedicated 5+5-Bit Split Period & Duty Down-Counters (rst_n_fsm2_q)
  always_ff @(posedge clk_dco or negedge rst_n_fsm2_q) begin
    if (!rst_n_fsm2_q) begin
      cnt            <= 10'd0;
      cnt_lo_zero_q  <= 1'b1;
      cnt_hi_zero_q  <= 1'b1;
      cnt_zero_q     <= 1'b1;
      cnt_zero_cfg_q <= 1'b1;
      cnt_zero_pre_q <= 1'b1;
      high_cnt       <= 10'd0;
      high_lo_zero_q <= 1'b1;
      high_hi_zero_q <= 1'b1;
      high_zero_q    <= 1'b1;
    end else if (!div_mode_cnt_q) begin
      cnt            <= int_m1_reg;
      cnt_lo_zero_q  <= int_m1_lo_zero_reg;
      cnt_hi_zero_q  <= int_m1_hi_zero_reg;
      cnt_zero_q     <= int_m1_zero_reg;
      cnt_zero_cfg_q <= int_m1_zero_reg;
      cnt_zero_pre_q <= int_m1_zero_reg;
      high_cnt       <= high_m1_reg;
      high_lo_zero_q <= high_m1_lo_zero_reg;
      high_hi_zero_q <= high_m1_hi_zero_reg;
      high_zero_q    <= high_m1_zero_reg;
    end else if (!bypass_arm && pre_tick) begin
      if (cnt_zero_q) begin
        if (pure_bypass_reg || pulse_stretch_mode_reg) begin
          cnt            <= 10'd0;
          cnt_lo_zero_q  <= 1'b1;
          cnt_hi_zero_q  <= 1'b1;
          cnt_zero_q     <= 1'b1;
          cnt_zero_cfg_q <= 1'b1;
          cnt_zero_pre_q <= 1'b1;
          high_cnt       <= 10'd0;
          high_lo_zero_q <= 1'b1;
          high_hi_zero_q <= 1'b1;
          high_zero_q    <= 1'b1;
        end else begin
          cnt            <= div_sdm_carry_q ? int_reg : int_m1_reg;
          cnt_lo_zero_q  <= div_sdm_carry_q ? int_lo_zero_reg : int_m1_lo_zero_reg;
          cnt_hi_zero_q  <= div_sdm_carry_q ? int_hi_zero_reg : int_m1_hi_zero_reg;
          cnt_zero_q     <= (!div_sdm_carry_q) && int_m1_zero_reg;
          cnt_zero_cfg_q <= (!div_sdm_carry_q) && int_m1_zero_reg;
          cnt_zero_pre_q <= (!div_sdm_carry_q) && int_m1_zero_reg;
          high_cnt       <= high_m1_reg;
          high_lo_zero_q <= high_m1_lo_zero_reg;
          high_hi_zero_q <= high_m1_hi_zero_reg;
          high_zero_q    <= high_m1_zero_reg;
        end
      end else begin
        cnt[4:0]       <= cnt[4:0] - 5'd1;
        if (cnt_lo_zero_q)
          cnt[9:5]     <= cnt[9:5] - 5'd1;
        cnt_lo_zero_q  <= (cnt[4:0] == 5'd1);
        cnt_hi_zero_q  <= cnt_lo_zero_q ? (cnt[9:5] == 5'd1) : cnt_hi_zero_q;
        cnt_zero_q     <= cnt_hi_zero_q && (cnt[4:0] == 5'd1);
        cnt_zero_cfg_q <= cnt_hi_zero_q && (cnt[4:0] == 5'd1);
        cnt_zero_pre_q <= cnt_hi_zero_q && (cnt[4:0] == 5'd1);

        if (!high_zero_q) begin
          high_cnt[4:0]  <= high_cnt[4:0] - 5'd1;
          if (high_lo_zero_q)
            high_cnt[9:5] <= high_cnt[9:5] - 5'd1;
          high_lo_zero_q <= (high_cnt[4:0] == 5'd1);
          high_hi_zero_q <= high_lo_zero_q ? (high_cnt[9:5] == 5'd1) : high_hi_zero_q;
          high_zero_q    <= high_hi_zero_q && (high_cnt[4:0] == 5'd1);
        end
      end
    end
  end

  // ----------------------------------------------------------------------------
  // 5. Dedicated SG13G2 Base Clock Multiplexer (sg13g2_mux2_2) with 2-Stage
  //    CTS-Matched DCO Clock Delay Path (sg13g2_buf_4 -> sg13g2_buf_8)
  //    A0 = div_clk_reg (divided clock or stretched pulse hold-high)
  //    A1 = clk_dco_mux (CTS-matched 250-500 MHz DCO clock)
  // ----------------------------------------------------------------------------
  (* dont_touch = "true" *)
  sg13g2_buf_4 cts_match_b1 (
    .A (clk_dco),
    .X (clk_dco_b1)
  );

  (* dont_touch = "true" *)
  sg13g2_buf_8 cts_match_b2 (
    .A (clk_dco_b1),
    .X (clk_dco_mux)
  );

  (* dont_touch = "true" *)
  sg13g2_mux2_2 u_out_mux (
    .A0 (div_clk_reg),
    .A1 (clk_dco_mux),
    .S  (pass_dco_clk),
    .X  (clk_out)
  );

endmodule
