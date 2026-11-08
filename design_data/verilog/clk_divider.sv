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
  input  logic                 rst_n,         // Active-low reset (synchronized to posedge clk)
  input  logic                 rst_n_neg = 1'b1, // Active-low reset (synchronized to negedge clk)
  input  logic [DIV_WIDTH-1:0] div_ratio,     // Integer feedback division ratio N (25..500)
  input  logic [7:0]           fb_frac,       // 8-bit fractional feedback numerator (0..255 -> F/256)
  output logic                 clk_out,       // 1 - 10 MHz divided feedback clock
  output logic [DIV_WIDTH-1:0] div_phase,     // Rising-edge phase index in DCO cycles (0..N-1)
  output logic [DIV_WIDTH-1:0] div_phase_neg, // Falling-edge retimed phase index for metastability-free CDC
  output logic [7:0]           fb_sdm_phase   // Instantaneous fractional SDM accumulator residue (0..255)
);

  // Local reset leaf registers to isolate RESET_B fanout (~45 FFs each) across all corners
  (* keep = "true" *) logic rst_n_pos_a_q;
  (* keep = "true" *) logic rst_n_pos_b_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rst_n_pos_a_q <= 1'b0;
      rst_n_pos_b_q <= 1'b0;
    end else begin
      rst_n_pos_a_q <= 1'b1;
      rst_n_pos_b_q <= 1'b1;
    end
  end

  logic [7:0]           frac_meta, frac_sync;
  logic [7:0]           sdm_acc;
  logic [4:0]           sdm_lo_q;
  logic [3:0]           sdm_hi_in_q, frac_hi_in_q;
  logic [8:0]           sdm_next_sum_q;
  logic [DIV_WIDTH-1:0] clamped_n_q;
  logic [4:0]           cn_hi_q;
  logic [4:0]           m1_lo_q, m2_lo_q, hm2_lo_q;
  logic                 m1_b_q, m2_b_q, hm2_b_q;
  logic [DIV_WIDTH-1:0] base_m1_q;
  logic [DIV_WIDTH-1:0] base_m2_q;
  logic [DIV_WIDTH-1:0] half_m2_q;
  logic [DIV_WIDTH-1:0] active_m2;
  logic [DIV_WIDTH-1:0] active_half_m2;
  (* keep = "true" *) logic [DIV_WIDTH-1:0] div_cnt;
  logic                 div_c5_q;
  (* keep = "true" *) logic wrap_q;
  (* keep = "true" *) logic wrap_sdm_q;
  logic                 half_hit_q;

  // 3-stage 5+5-bit pipelined division bounds for 500 MHz setup closure across all corners
  always_ff @(posedge clk or negedge rst_n_pos_a_q) begin
    if (!rst_n_pos_a_q) begin
      frac_meta   <= 8'd0;
      frac_sync   <= 8'd0;
      clamped_n_q <= 10'd100;
      cn_hi_q     <= 5'd3;
      m1_lo_q     <= 5'd3;
      m1_b_q      <= 1'b0;
      m2_lo_q     <= 5'd2;
      m2_b_q      <= 1'b0;
      hm2_lo_q    <= 5'd16;
      hm2_b_q     <= 1'b0;
      base_m1_q   <= 10'd99;
      base_m2_q   <= 10'd98;
      half_m2_q   <= 10'd48;
    end else begin
      frac_meta   <= fb_frac;
      frac_sync   <= frac_meta;
      clamped_n_q <= (div_ratio < 10'd4) ? 10'd4 : div_ratio;

      cn_hi_q     <= clamped_n_q[9:5];
      m1_lo_q     <= clamped_n_q[4:0] - 5'd1;
      m1_b_q      <= (clamped_n_q[4:0] == 5'd0);
      m2_lo_q     <= clamped_n_q[4:0] - 5'd2;
      m2_b_q      <= (clamped_n_q[4:0] < 5'd2);
      hm2_lo_q    <= clamped_n_q[5:1] - 5'd2;
      hm2_b_q     <= (clamped_n_q[5:1] < 5'd2);

      base_m1_q   <= { (cn_hi_q - {4'd0, m1_b_q}), m1_lo_q };
      base_m2_q   <= { (cn_hi_q - {4'd0, m2_b_q}), m2_lo_q };
      half_m2_q   <= { ({1'b0, cn_hi_q[4:1]} - {4'd0, hm2_b_q}), hm2_lo_q };
    end
  end

  // 5+5-bit split up-counter & 2-stage 4+4-bit SDM lookahead pipeline
  always_ff @(posedge clk or negedge rst_n_pos_b_q) begin
    if (!rst_n_pos_b_q) begin
      div_cnt        <= '0;
      div_phase      <= '0;
      div_c5_q       <= 1'b0;
      clk_out        <= 1'b0;
      sdm_acc        <= 8'd0;
      sdm_lo_q       <= 5'd0;
      sdm_hi_in_q    <= 4'd0;
      frac_hi_in_q   <= 4'd0;
      sdm_next_sum_q <= 9'd0;
      active_m2      <= 10'd98;
      active_half_m2 <= 10'd48;
      fb_sdm_phase   <= 8'd0;
      wrap_q         <= 1'b0;
      wrap_sdm_q     <= 1'b0;
      half_hit_q     <= 1'b0;
    end else begin
      wrap_q     <= (!wrap_q) && (div_cnt == active_m2);
      wrap_sdm_q <= (!wrap_q) && (div_cnt == active_m2);
      half_hit_q <= (!wrap_q) && (div_cnt == active_half_m2);

      if (!wrap_sdm_q) begin
        sdm_lo_q       <= {1'b0, sdm_acc[3:0]} + {1'b0, frac_sync[3:0]};
        sdm_hi_in_q    <= sdm_acc[7:4];
        frac_hi_in_q   <= frac_sync[7:4];
        sdm_next_sum_q <= { ({1'b0, sdm_hi_in_q} + {1'b0, frac_hi_in_q} + {4'd0, sdm_lo_q[4]}), sdm_lo_q[3:0] };
      end

      if (wrap_q) begin
        div_cnt   <= '0;
        div_phase <= '0;
        div_c5_q  <= 1'b0;
        clk_out   <= 1'b1;
      end else begin
        div_cnt[4:0]   <= div_cnt[4:0] + 5'd1;
        div_phase[4:0] <= div_cnt[4:0] + 5'd1;
        if (div_c5_q) begin
          div_cnt[9:5]   <= div_cnt[9:5] + 5'd1;
          div_phase[9:5] <= div_cnt[9:5] + 5'd1;
        end
        div_c5_q <= (div_cnt[4:0] == 5'h1E);

        if (half_hit_q) begin
          clk_out <= 1'b0;
        end
      end

      if (wrap_sdm_q) begin
        sdm_acc        <= sdm_next_sum_q[7:0];
        active_m2      <= sdm_next_sum_q[8] ? base_m1_q : base_m2_q;
        active_half_m2 <= half_m2_q;
        fb_sdm_phase   <= sdm_next_sum_q[7:0];
      end
    end
  end

  // Half-cycle delayed shadow register clocked on negedge DCO clock:
  // Guarantees stationary coarse phase when posedge ref_clk collides with posedge DCO clock
  always_ff @(negedge clk or negedge rst_n_neg) begin
    if (!rst_n_neg) begin
      div_phase_neg <= '0;
    end else begin
      div_phase_neg <= div_phase;
    end
  end

endmodule
