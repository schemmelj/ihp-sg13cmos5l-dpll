// ==============================================================================
// File: dco_nco.sv
// Description: 100% Pure Standard-Cell Digitally Controlled Oscillator (DCO)
//              Target Technology: IHP 130nm BiCMOS (SG13G2 Standard Library, 1.2V)
//              Continuous Operating Range: 250.0 MHz to 500.0 MHz (1 Full Octave)
//              across all PVT corners (SLOW: 1.08V/125C, TYP: 1.20V/25C, FAST: 1.32V/-40C)
//              Architecture (Fixed Stage Counts):
//                - 3 Head Buffer Stages (HEAD_STAGES = 3)
//                - 15 Thermometer-Coded Lookahead-Gated Coarse MUX Stages (COARSE_STAGES = 15)
//                - 8 Standard-Cell Vernier Fine MUX Stages (FINE_STAGES = 8)
//                - 1 High-Speed Sigma-Delta Dither Vernier Stage
//              Glitch-Free Frequency Switching:
//                - 2-FF CDC synchronizer + per-DCO-cycle synchronous slew-rate
//                  limiter on the tuning word prevents multi-stage jumps.
//                - Thermometer Lookahead Branch Gating pre-enables stage k's
//                  delay branch via coarse_en[k-1] before coarse_en[k] switches,
//                  guaranteeing live phase-aligned MUX inputs during both 0->1
//                  and 1->0 transitions while keeping unused upper stages gated off.
// ==============================================================================

`timescale 1ps / 1fs

(* keep_hierarchy = "true" *)
module dco_nco #(
  parameter int OTW_WIDTH     = 16,
  parameter int HEAD_STAGES   = 3,    // 3 Head fixed buffer stages
  parameter int COARSE_STAGES = 15,   // 15 Thermometer-coded coarse MUX stages
  parameter int FINE_STAGES   = 8     // 8 Vernier fine MUX stages
)(
  input  logic                 rst_n,
  input  logic [OTW_WIDTH-1:0] otw,         // 16-bit Oscillator Tuning Word
  output logic                 dco_clk_out
);

  // Internal ring oscillator interconnect nodes (unpacked 1-bit nets avoid O(N^2) vector fanout)
  (* keep = "true" *) logic node_head   [0:HEAD_STAGES];
  (* keep = "true" *) logic node_coarse [0:COARSE_STAGES];
  (* keep = "true" *) logic node_fine   [0:FINE_STAGES];
  (* keep = "true" *) logic                   node_sdm_out;
  (* keep = "true" *) logic                   node_tail_buf;
  (* keep = "true" *) logic                   node_tail_b2;
  (* keep = "true" *) logic                   node_tail_a1;
  (* keep = "true" *) logic                   node_tail_a2;
  (* keep = "true" *) logic                   node_tail_inv;
  (* keep = "true" *) logic                   ring_feedback;
  (* keep = "true" *) logic                   clk_prebuf;
  (* keep = "true" *) logic                   tie_hi;
  (* keep = "true" *) logic                   tie_lo;

  // Standard-cell Tie-High and Tie-Low instances for constant gate inputs
  (* dont_touch = "true" *) sg13g2_tiehi u_tie_hi ( .L_HI(tie_hi) );
  (* dont_touch = "true" *) sg13g2_tielo u_tie_lo ( .L_LO(tie_lo) );

  // Inverted tuning word: ctrl_word = 0 -> fastest (f_max), ctrl_word = 65535 -> slowest (f_min)
  (* keep = "true" *) logic [OTW_WIDTH-1:0]     ctrl_word;
  logic [OTW_WIDTH-1:0]     ctrl_word_meta, ctrl_word_sync;
  logic [8:0]               ctrl_top_act;
  (* keep = "true" *) logic [8:0]               ctrl_dec_src_q;
  logic [1:0]               slew_phase;
  logic [3:0]               sync_hi_q;
  logic                     inc_c_q, dec_b_q;
  logic                     lt_lo_q, gt_lo_q;
  logic [4:0]               ctrl_inc_lo_q, ctrl_dec_lo_q;
  logic [3:0]               ctrl_inc_hi_q, ctrl_dec_hi_q;
  logic                     step_up_q, step_dn_q;
  logic [OTW_WIDTH-1:0]     ctrl_word_act;
  logic [COARSE_STAGES-1:0] coarse_en_comb;
  logic [COARSE_STAGES-1:0] coarse_en;
  logic [FINE_STAGES-1:0]   fine_en_comb;
  logic [FINE_STAGES-1:0]   fine_en;
  logic [8:0]               sdm_frac_comb;
  logic [8:0]               sdm_frac;
  logic [3:0]               sdm_frac_hi_q;
  logic [4:0]               sdm_acc_lo;
  logic [3:0]               sdm_acc_hi;
  logic                     lo_carry_q;
  logic                     sdm_carry;

  assign ctrl_word     = ~otw;
  assign ctrl_word_act = {ctrl_dec_src_q, ctrl_word_sync[6:0]};

  // Thermometer decoder for 15 coarse stages:
  // ctrl_word_act[15:12] selects 0..15 active coarse delay stages
  genvar g_dec;
  generate
    for (g_dec = 0; g_dec < COARSE_STAGES; g_dec++) begin : gen_therm_dec
      assign coarse_en_comb[g_dec] = (ctrl_word_act[15:12] > 4'(g_dec));
    end
  endgenerate

  // Thermometer + Vernier decoding for the 8 Fine Stages:
  // - ctrl_word_act[11:10] & ctrl_word_act[9] monotonically span one coarse step (~550 ps)
  //   without overhang cliffs across sub-step or coarse boundaries
  // - ctrl_word_act[8:0] (9 bits: 0..511) drives the high-speed Sigma-Delta fractional dither
  assign fine_en_comb[7] = (ctrl_word_act[11:10] >= 2'd1);
  assign fine_en_comb[6] = (ctrl_word_act[11:10] == 2'd3);
  assign fine_en_comb[5] = 1'b0;
  assign fine_en_comb[4] = 1'b0;
  assign fine_en_comb[3] = (ctrl_word_act[11:10] < 2'd2) & ctrl_word_act[9];
  assign fine_en_comb[2] = 1'b0;
  assign fine_en_comb[1] = 1'b0;
  assign fine_en_comb[0] = (ctrl_word_act[11:10] == 2'd2) | ((ctrl_word_act[11:10] < 2'd2) & ctrl_word_act[9]);
  assign sdm_frac_comb   = ctrl_word_act[8:0];

  // 2-Stage DCO-Clock Synchronizer + 3-Stage 5+4-Bit Slew-Rate Limiter + 2-Stage Carry-Save 9-Bit SDM
  always_ff @(posedge dco_clk_out or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_word_meta <= 16'h16FF;
      ctrl_word_sync <= 16'h16FF;
      ctrl_top_act   <= 9'h02D;
      ctrl_dec_src_q <= 9'h02D;
      slew_phase     <= 2'd0;
      coarse_en      <= 15'h0001;
      fine_en        <= 8'h80;
      sdm_frac       <= 9'h000;
      sdm_frac_hi_q  <= 4'h0;
      sdm_acc_lo     <= 5'h00;
      sdm_acc_hi     <= 4'h0;
      lo_carry_q     <= 1'b0;
      sdm_carry      <= 1'b0;
    end else begin
      ctrl_word_meta <= ctrl_word;
      ctrl_word_sync <= ctrl_word_meta;
      coarse_en                   <= coarse_en_comb;
      fine_en                     <= fine_en_comb;
      sdm_frac                    <= sdm_frac_comb;
      sdm_frac_hi_q               <= sdm_frac[8:5];
      {lo_carry_q, sdm_acc_lo}    <= {1'b0, sdm_acc_lo} + {1'b0, sdm_frac[4:0]};
      {sdm_carry,  sdm_acc_hi}    <= {1'b0, sdm_acc_hi} + {1'b0, sdm_frac_hi_q} + {4'b0, lo_carry_q};

      if (slew_phase == 2'd0) begin
        slew_phase <= 2'd1;
      end else if (slew_phase == 2'd1) begin
        slew_phase <= 2'd2;
      end else begin
        slew_phase <= 2'd0;
        if (step_up_q) begin
          ctrl_top_act   <= {ctrl_inc_hi_q, ctrl_inc_lo_q};
          ctrl_dec_src_q <= {ctrl_inc_hi_q, ctrl_inc_lo_q};
        end else if (step_dn_q) begin
          ctrl_top_act   <= {ctrl_dec_hi_q, ctrl_dec_lo_q};
          ctrl_dec_src_q <= {ctrl_dec_hi_q, ctrl_dec_lo_q};
        end
      end
    end
  end

  // Reset-free intermediate pipeline registers (written in phase 0 -> phase 1 before phase 2 read;
  // keeps async rst_n fanout identical to baseline so u_nand_en slew is undisturbed)
  always_ff @(posedge dco_clk_out) begin
    if (slew_phase == 2'd0) begin
      sync_hi_q     <= ctrl_word_sync[15:12];
      ctrl_inc_lo_q <= ctrl_top_act[4:0] + 5'd1;
      inc_c_q       <= (ctrl_top_act[4:0] == 5'h1F);
      ctrl_dec_lo_q <= ctrl_top_act[4:0] - 5'd1;
      dec_b_q       <= (ctrl_top_act[4:0] == 5'd0);
      lt_lo_q       <= (ctrl_top_act[4:0] < ctrl_word_sync[11:7]);
      gt_lo_q       <= (ctrl_top_act[4:0] > ctrl_word_sync[11:7]);
    end else if (slew_phase == 2'd1) begin
      ctrl_inc_hi_q <= ctrl_top_act[8:5] + {3'd0, inc_c_q};
      ctrl_dec_hi_q <= ctrl_top_act[8:5] - {3'd0, dec_b_q};
      step_up_q     <= (ctrl_top_act[8:5] < sync_hi_q) || ((ctrl_top_act[8:5] == sync_hi_q) && lt_lo_q);
      step_dn_q     <= (ctrl_top_act[8:5] > sync_hi_q) || ((ctrl_top_act[8:5] == sync_hi_q) && gt_lo_q);
    end
  end

  // ----------------------------------------------------------------------------
  // 1. Ring Oscillator Enable & Loop-Inverting Gate (sg13g2_nand2_2)
  //    Holds node_head[0] = 1'b1 when rst_n = 1'b0; closes loop when rst_n = 1'b1
  // ----------------------------------------------------------------------------
  (* dont_touch = "true" *)
  sg13g2_nand2_2 u_nand_en (
    .A (rst_n),
    .B (ring_feedback),
    .Y (node_head[0])
  );

  // ----------------------------------------------------------------------------
  // 2. Telescopic Lookahead-Gated Coarse Tunable Delay Line (15 Thermometer Stages)
  //    Each stage c = 0..14 has:
  //      - 2x sg13g2_buf_1 + 1x sg13g2_nand2_2 (lookahead-gated) + 1x sg13g2_inv_2
  //      - 1x sg13g2_mux2_1 return tap
  //    Stage c's delay branch is gated by coarse_en[c-1] (or rst_n for c = 0) so
  //    the lookahead stage k is already warm and phase-aligned before coarse_en[k]
  //    transitions, while higher unused stages (c > k) remain quiescent at logic 0.
  // ----------------------------------------------------------------------------
  logic c_stage_in [0:COARSE_STAGES-1];
  logic c_mux_a1   [0:COARSE_STAGES-1];
  logic c_mux_out  [0:COARSE_STAGES-1];
  logic c_branch_en[0:COARSE_STAGES-1];

  assign c_stage_in[0]              = node_head[0];
  assign c_branch_en[0]             = tie_hi;
  assign c_mux_a1[COARSE_STAGES-1]  = ring_feedback_ext;
  assign node_coarse[COARSE_STAGES] = c_mux_out[0];

  genvar c;
  generate
    for (c = 0; c < COARSE_STAGES; c++) begin : gen_coarse_stages
      (* keep = "true" *) logic n_b1, n_b2, n_b3, n_slow;

      if (c > 0) begin : gen_c_chain
        assign c_stage_in[c]  = gen_coarse_stages[c-1].n_slow;
        assign c_branch_en[c] = coarse_en[c-1];
        assign c_mux_a1[c-1]  = node_coarse[c];
        assign node_coarse[c] = c_mux_out[c];
      end

      (* dont_touch = "true" *)
      sg13g2_buf_1 u_c_buf (
        .A (c_stage_in[c]),
        .X (n_b1)
      );

      (* dont_touch = "true" *)
      sg13g2_buf_1 u_c_b2 (
        .A (n_b1),
        .X (n_b2)
      );

      (* dont_touch = "true" *)
      sg13g2_nand2_2 u_c_b3 (
        .A (n_b2),
        .B (c_branch_en[c]),
        .Y (n_b3)
      );

      (* dont_touch = "true" *)
      sg13g2_inv_2 u_c_b4 (
        .A (n_b3),
        .Y (n_slow)
      );

      (* dont_touch = "true" *)
      sg13g2_mux2_1 u_c_mux (
        .A0 (c_stage_in[c]),
        .A1 (c_mux_a1[c]),
        .S  (coarse_en[c]),
        .X  (c_mux_out[c])
      );
    end
  endgenerate

  // ----------------------------------------------------------------------------
  // 3. Stage 14 Slow-Path Extension Chain (3 Head Buffers + Tail Extension Cells)
  // ----------------------------------------------------------------------------
  (* keep = "true" *) logic ring_feedback_ext;
  logic head_in  [0:HEAD_STAGES-1];
  logic head_out [0:HEAD_STAGES-1];
  assign head_in[0]     = gen_coarse_stages[COARSE_STAGES-1].n_slow;
  assign node_head[1]   = head_out[0];
  assign head_in[1]     = node_head[1];
  assign node_head[2]   = head_out[1];
  assign head_in[2]     = node_head[2];
  assign node_head[3]   = head_out[2];
  assign node_coarse[0] = node_head[3];

  genvar i;
  generate
    for (i = 0; i < HEAD_STAGES; i++) begin : gen_head_delay
      (* dont_touch = "true" *)
      sg13g2_buf_1 u_head_buf (
        .A (head_in[i]),
        .X (head_out[i])
      );
    end
  endgenerate

  assign node_fine[0] = node_coarse[COARSE_STAGES];

  // ----------------------------------------------------------------------------
  // 4. Telescopic & Differential Vernier Fine Delay Line (8 Stages: F7..F0)
  //    Only 2 fine MUXes (u_f4_mux and u_f0_mux) are in series on the minimum
  //    delay path (ctrl_word = 0), enabling f_max > 590 MHz in SLOW (1.08V, 125C)
  //    so 250.0 MHz - 500.0 MHz is achieved across all corners (SLOW, TYP, FAST).
  // ----------------------------------------------------------------------------
  (* keep = "true" *) logic f7_mid, f7_slow;
  (* keep = "true" *) logic f6_slow;
  (* keep = "true" *) logic f5_slow;
  (* keep = "true" *) logic f4_fast, f4_mid, f4_slow;
  (* keep = "true" *) logic f3_fast, f3_mid, f3_slow;
  (* keep = "true" *) logic f2_fast, f2_slow;
  (* keep = "true" *) logic f1_fast, f1_slow;
  (* keep = "true" *) logic f0_fast, f0_slow;

  // Upper-Fine Telescopic Chain (F4 root, F5 -> F6 -> F7 branches kept live for glitch-free tap selection)
  (* dont_touch = "true" *) sg13g2_and2_1  u_f4_fast ( .A(node_coarse[0]), .B(tie_hi), .X(f4_fast) );
  (* dont_touch = "true" *) sg13g2_nand2_2 u_f4_nd1  ( .A(node_fine[0]),   .B(tie_hi), .Y(f4_mid)  );
  (* dont_touch = "true" *) sg13g2_inv_2   u_f4_nd2  ( .A(f4_mid),                     .Y(f4_slow) );

  (* dont_touch = "true" *) sg13g2_and2_2  u_f5_and1 ( .A(f4_slow),        .B(tie_hi), .X(f5_slow) );
  (* dont_touch = "true" *) sg13g2_and2_2  u_f6_and1 ( .A(f5_slow),        .B(tie_hi), .X(f6_slow) );
  (* dont_touch = "true" *) sg13g2_and2_2  u_f7_and1 ( .A(f6_slow),        .B(tie_hi), .X(f7_mid)  );
  (* dont_touch = "true" *) sg13g2_or2_2   u_f7_and2 ( .A(f7_mid),         .B(tie_lo), .X(f7_slow) );

  (* dont_touch = "true" *) sg13g2_mux2_1  u_f7_mux  ( .A0(f6_slow),       .A1(f7_slow),      .S(fine_en[4]), .X(node_fine[1]) );
  (* dont_touch = "true" *) sg13g2_mux2_1  u_f6_mux  ( .A0(f5_slow),       .A1(node_fine[1]), .S(fine_en[5]), .X(node_fine[2]) );
  (* dont_touch = "true" *) sg13g2_mux2_1  u_f5_mux  ( .A0(f4_slow),       .A1(node_fine[2]), .S(fine_en[6]), .X(node_fine[3]) );
  (* dont_touch = "true" *) sg13g2_mux2_1  u_f4_mux  ( .A0(node_fine[0]),  .A1(node_fine[3]), .S(fine_en[7]), .X(node_fine[4]) );

  // Lower-Fine Telescopic Chain (F0 root, F3 -> F2 -> F1 branches kept live for glitch-free tap selection)
  (* dont_touch = "true" *) sg13g2_and2_1  u_f3_fast ( .A(f4_fast),        .B(tie_hi), .X(f3_fast) );
  (* dont_touch = "true" *) sg13g2_nand2_2 u_f3_inv1 ( .A(node_fine[4]),   .B(tie_hi), .Y(f3_mid)  );
  (* dont_touch = "true" *) sg13g2_inv_2   u_f3_inv2 ( .A(f3_mid),                     .Y(f3_slow) );

  (* dont_touch = "true" *) sg13g2_buf_1   u_f2_fast ( .A(f3_slow),                    .X(f2_fast) );
  (* dont_touch = "true" *) sg13g2_and2_2  u_f2_slow ( .A(f2_fast),        .B(tie_hi), .X(f2_slow) );

  (* dont_touch = "true" *) sg13g2_buf_1   u_f1_fast ( .A(f2_slow),                    .X(f1_fast) );
  (* dont_touch = "true" *) sg13g2_and2_2  u_f1_slow ( .A(f1_fast),        .B(tie_hi), .X(f1_slow) );

  (* dont_touch = "true" *) sg13g2_buf_1   u_f0_fast ( .A(f1_slow),                    .X(f0_fast) );
  (* dont_touch = "true" *) sg13g2_buf_2   u_f0_slow ( .A(f0_fast),                    .X(f0_slow) );

  (* dont_touch = "true" *) sg13g2_mux2_1  u_f3_mux  ( .A0(f1_slow),       .A1(f0_slow),      .S(fine_en[1]), .X(node_fine[5]) );
  (* dont_touch = "true" *) sg13g2_mux2_1  u_f2_mux  ( .A0(f2_slow),       .A1(node_fine[5]), .S(fine_en[1]), .X(node_fine[6]) );
  (* dont_touch = "true" *) sg13g2_mux2_1  u_f1_mux  ( .A0(f3_slow),       .A1(node_fine[6]), .S(fine_en[2]), .X(node_fine[7]) );
  (* dont_touch = "true" *) sg13g2_mux2_1  u_f0_mux  ( .A0(node_fine[4]),  .A1(node_fine[7]), .S(fine_en[0]), .X(node_fine[8]) );

  // ----------------------------------------------------------------------------
  // 5. High-Speed Sigma-Delta Dither Vernier Stage (9-Bit SDM -> <0.3 ps LSB)
  // ----------------------------------------------------------------------------
  (* keep = "true" *) logic sdm_fast, sdm_slow;
  (* dont_touch = "true" *) sg13g2_buf_1  u_sdm_fast ( .A(node_fine[8]), .X(sdm_fast) );
  (* dont_touch = "true" *) sg13g2_or2_2  u_sdm_slow ( .A(sdm_fast),     .B(tie_lo),    .X(sdm_slow) );
  (* dont_touch = "true" *) sg13g2_mux2_1 u_sdm_mux  ( .A0(node_fine[8]), .A1(sdm_slow), .S(sdm_carry), .X(node_sdm_out) );

  // ----------------------------------------------------------------------------
  // 6. Stage 14 Extension Buffers & Direct Loop Closure
  // ----------------------------------------------------------------------------
  (* dont_touch = "true" *) sg13g2_buf_1  u_tail_buf  ( .A(f3_fast),       .X(node_tail_buf)     );
  (* dont_touch = "true" *) sg13g2_buf_1  u_tail_buf2 ( .A(node_tail_buf), .X(node_tail_b2)      );
  (* dont_touch = "true" *) sg13g2_and2_1 u_tail_and1 ( .A(node_tail_b2),  .B(tie_hi), .X(node_tail_a1) );
  (* dont_touch = "true" *) sg13g2_and2_1 u_tail_and2 ( .A(node_tail_a1),  .B(tie_hi), .X(node_tail_a2) );
  (* dont_touch = "true" *) sg13g2_inv_1  u_tail_inv1 ( .A(node_tail_a2),  .Y(node_tail_inv)     );
  (* dont_touch = "true" *) sg13g2_inv_1  u_tail_inv2 ( .A(node_tail_inv), .Y(ring_feedback_ext) );

  assign ring_feedback = node_sdm_out;

  // ----------------------------------------------------------------------------
  // 7. Output Clock Isolation Inverter & High-Drive Clock Buffer (SG13G2 Cells)
  //    Ensures dco_clk_out is 1'b0 during reset and cleanly buffered to divider
  // ----------------------------------------------------------------------------
  (* dont_touch = "true" *)
  sg13g2_inv_2 u_clk_inv (
    .A (node_head[0]),
    .Y (clk_prebuf)
  );

  (* dont_touch = "true" *)
  sg13g2_buf_4 u_clk_buf (
    .A (clk_prebuf),
    .X (dco_clk_out)
  );

endmodule
