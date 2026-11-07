// ==============================================================================
// File: clk_divider.sv
// Description: Synthesizable High-Speed Programmable Integer/Fractional-N Feedback
//              Divider for IHP 130nm BiCMOS (SG13G2) ADPLL.
//              Operates across the 250-500 MHz DCO range, dividing down to a
//              programmable 1 MHz - 10 MHz reference frequency (N = 25..500,
//              plus 8-bit fractional numerator fb_frac / 256).
// ==============================================================================

`timescale 1ps / 1fs

module clk_divider #(
  parameter int DIV_WIDTH = 10
)(
  input  logic                 clk,           // 250 - 500 MHz DCO clock
  input  logic                 rst_n,         // Active-low reset (synchronized to clk)
  input  logic [DIV_WIDTH-1:0] div_ratio,     // Integer feedback division ratio N (25..500)
  input  logic [7:0]           fb_frac,       // 8-bit fractional feedback numerator (0..255 -> F/256)
  output logic                 clk_out,       // 1 - 10 MHz divided feedback clock
  output logic [DIV_WIDTH-1:0] div_phase,     // Rising-edge phase index in DCO cycles (0..N-1)
  output logic [DIV_WIDTH-1:0] div_phase_neg, // Falling-edge retimed phase index for metastability-free CDC
  output logic [7:0]           fb_sdm_phase   // Instantaneous fractional SDM accumulator residue (0..255)
);

  logic [7:0]           frac_meta, frac_sync;
  logic [7:0]           sdm_acc;
  logic [8:0]           sdm_sum_comb;
  logic                 sdm_carry;
  logic [DIV_WIDTH-1:0] base_m1;
  logic [DIV_WIDTH-1:0] active_m1;
  logic [DIV_WIDTH-1:0] half_div;

  assign sdm_sum_comb = {1'b0, sdm_acc} + {1'b0, frac_sync};

  // Pre-register division bounds for 500 MHz timing closure across all corners
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      frac_meta <= 8'd0;
      frac_sync <= 8'd0;
      base_m1   <= 10'd99;
      half_div  <= 10'd49;
    end else begin
      frac_meta <= fb_frac;
      frac_sync <= frac_meta;
      base_m1   <= (div_ratio > 10'd1) ? (div_ratio - 10'd1) : 10'd1;
      half_div  <= (div_ratio > 10'd2) ? ((div_ratio >> 1) - 10'd1) : 10'd0;
    end
  end

  // Primary coarse phase counter + 8-bit first-order Fractional-N Sigma-Delta Modulator
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      div_phase    <= '0;
      clk_out      <= 1'b0;
      sdm_acc      <= 8'd0;
      sdm_carry    <= 1'b0;
      active_m1    <= 10'd99;
      fb_sdm_phase <= 8'd0;
    end else begin
      if (div_phase >= active_m1) begin
        div_phase    <= '0;
        clk_out      <= 1'b1;
        sdm_acc      <= sdm_sum_comb[7:0];
        sdm_carry    <= sdm_sum_comb[8];
        active_m1    <= sdm_sum_comb[8] ? (base_m1 + 10'd1) : base_m1;
        fb_sdm_phase <= sdm_sum_comb[7:0];
      end else begin
        div_phase <= div_phase + 1'b1;
        if (div_phase == half_div) begin
          clk_out <= 1'b0;
        end
      end
    end
  end

  // Half-cycle delayed shadow register clocked on negedge DCO clock:
  // Guarantees stationary coarse phase when posedge ref_clk collides with posedge DCO clock
  always_ff @(negedge clk or negedge rst_n) begin
    if (!rst_n) begin
      div_phase_neg <= '0;
    end else begin
      div_phase_neg <= div_phase;
    end
  end

endmodule
