// ==============================================================================
// File: dco_nco.sv
// Description: 100% Pure Standard-Cell Digitally Controlled Oscillator (DCO)
//              Target Technology: IHP 130nm BiCMOS (SG13G2 Standard Library, 1.2V)
//              Frequency Range: 47.9 MHz to 223.2 MHz (Operational: 50 - 200 MHz)
//              Architecture:
//                - 15 Thermometer-Coded Coarse MUX Delay Stages (512.0 ps/stage)
//                - 8 Binary-Weighted Standard-Cell Vernier MUX Stages (256.0 ps..2.0 ps)
//                - 4-Bit High-Speed Sigma-Delta Dither Vernier Stage (2.0 ps -> 125 fs LSB)
//              Uses ZERO custom cells — built exclusively from IHP SG13G2 standard
//              library gates (sg13g2_nand2_2, sg13g2_buf_1, sg13g2_inv_1, sg13g2_inv_2,
//              sg13g2_and2_1, sg13g2_and2_2, sg13g2_or2_1, sg13g2_or2_2,
//              sg13g2_mux2_1, sg13g2_buf_4, sg13g2_tiehi, sg13g2_tielo).
// ==============================================================================

`timescale 1ps / 1fs

(* dont_touch = "true" *)
module dco_nco #(
  parameter int OTW_WIDTH     = 16,
  parameter int HEAD_STAGES   = 3,    // Head fixed buffer stages (3x sg13g2_buf_1 = 384.0 ps)
  parameter int COARSE_STAGES = 15,   // 15 Thermometer-coded coarse MUX stages (512.0 ps each)
  parameter int FINE_STAGES   = 8     // 8 Binary Vernier MUX stages (256.0 ps down to 2.0 ps)
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
  logic [OTW_WIDTH-1:0]       ctrl_word;
  logic [COARSE_STAGES-1:0]   coarse_en_comb;
  logic [COARSE_STAGES-1:0]   coarse_en_meta, coarse_en;
  logic [FINE_STAGES-1:0]     fine_en_comb;
  logic [FINE_STAGES-1:0]     fine_en_meta, fine_en;
  logic [3:0]                 sdm_frac_comb;
  logic [3:0]                 sdm_frac_meta, sdm_frac;
  logic [3:0]                 sdm_acc;
  logic                       sdm_carry;

  assign ctrl_word     = ~otw;
  assign fine_en_comb  = ctrl_word[11:4];
  assign sdm_frac_comb = ctrl_word[3:0];

  // Thermometer decoder for 15 coarse stages (512.0 ps per stage):
  // ctrl_word[15:12] selects 0..15 active coarse delay stages
  genvar g_dec;
  generate
    for (g_dec = 0; g_dec < COARSE_STAGES; g_dec++) begin : gen_therm_dec
      assign coarse_en_comb[g_dec] = (g_dec < ctrl_word[15:12]);
    end
  endgenerate

  // 2-Stage DCO-Clock Synchronizer + 4-Bit First-Order Sigma-Delta Modulator:
  // Updates MUX select lines synchronously on posedge dco_clk_out while the entire
  // tunable delay chain (node_coarse and node_fine) is quiescent at logic 1'b1.
  always_ff @(posedge dco_clk_out or negedge rst_n) begin
    if (!rst_n) begin
      coarse_en_meta <= 15'h007F;
      coarse_en      <= 15'h007F;
      fine_en_meta   <= 8'h80;
      fine_en        <= 8'h80;
      sdm_frac_meta  <= 4'h0;
      sdm_frac       <= 4'h0;
      sdm_acc        <= 4'h0;
      sdm_carry      <= 1'b0;
    end else begin
      coarse_en_meta <= coarse_en_comb;
      coarse_en      <= coarse_en_meta;
      fine_en_meta   <= fine_en_comb;
      fine_en        <= fine_en_meta;
      sdm_frac_meta  <= sdm_frac_comb;
      sdm_frac       <= sdm_frac_meta;
      {sdm_carry, sdm_acc} <= {1'b0, sdm_acc} + {1'b0, sdm_frac};
    end
  end

  // ----------------------------------------------------------------------------
  // 1. Ring Oscillator Enable & Loop-Inverting Gate (sg13g2_nand2_2 = 48.0 ps)
  //    Holds node_head[0] = 1'b1 when rst_n = 1'b0; closes loop when rst_n = 1'b1
  // ----------------------------------------------------------------------------
  (* dont_touch = "true" *)
  sg13g2_nand2_2 u_nand_en (
    .A (rst_n),
    .B (ring_feedback),
    .Y (node_head[0])
  );

  // ----------------------------------------------------------------------------
  // 2. Head Base Ring Delay Chain (3x sg13g2_buf_1 = 384.0 ps)
  //    Provides >350 ps launch guard band after posedge dco_clk_out before any
  //    new edge reaches node_coarse[0].
  // ----------------------------------------------------------------------------
  genvar i;
  generate
    for (i = 0; i < HEAD_STAGES; i++) begin : gen_head_delay
      (* dont_touch = "true" *)
      sg13g2_buf_1 u_head_buf (
        .A (node_head[i]),
        .X (node_head[i+1])
      );
    end
  endgenerate

  assign node_coarse[0] = node_head[HEAD_STAGES];

  // ----------------------------------------------------------------------------
  // 3. Coarse Tunable Delay Line (15 Stages x 512.0 ps/stage using SG13G2 Cells)
  //    Each stage uses:
  //      - Fast path (A0): direct wire (0.0 ps)
  //      - Slow path (A1): 4x sg13g2_buf_1 (4 * 128.0 ps = 512.0 ps)
  //      - Path selector : 1x sg13g2_mux2_1 (40.0 ps)
  // ----------------------------------------------------------------------------
  genvar c;
  generate
    for (c = 0; c < COARSE_STAGES; c++) begin : gen_coarse_stages
      (* keep = "true" *) logic n_b1, n_b2, n_b3, n_slow;

      (* dont_touch = "true" *)
      sg13g2_buf_1 u_c_buf (
        .A (node_coarse[c]),
        .X (n_b1)
      );

      (* dont_touch = "true" *)
      sg13g2_buf_1 u_c_b2 (
        .A (n_b1),
        .X (n_b2)
      );

      (* dont_touch = "true" *)
      sg13g2_buf_1 u_c_b3 (
        .A (n_b2),
        .X (n_b3)
      );

      (* dont_touch = "true" *)
      sg13g2_buf_1 u_c_b4 (
        .A (n_b3),
        .X (n_slow)
      );

      (* dont_touch = "true" *)
      sg13g2_mux2_1 u_c_mux (
        .A0 (node_coarse[c]),
        .A1 (n_slow),
        .S  (coarse_en[c]),
        .X  (node_coarse[c+1])
      );
    end
  endgenerate

  assign node_fine[0] = node_coarse[COARSE_STAGES];

  // ----------------------------------------------------------------------------
  // 4. Binary-Weighted Standard-Cell Vernier Fine Delay Line (8 Stages)
  //    Achieves exact binary steps from 256.0 ps down to 2.0 ps using differential
  //    propagation delays between IHP SG13G2 standard library gates selected by
  //    sg13g2_mux2_1.
  // ----------------------------------------------------------------------------

  // --- Stage F7 (MSB, Bit 7): Step = 256.0 ps (A0 = 0.0 ps, A1 = 2x sg13g2_buf_1 = 256.0 ps) ---
  (* keep = "true" *) logic f7_mid, f7_slow;
  (* dont_touch = "true" *) sg13g2_buf_1  u_f7_and1 ( .A(node_fine[0]), .X(f7_mid)  );
  (* dont_touch = "true" *) sg13g2_buf_1  u_f7_and2 ( .A(f7_mid),       .X(f7_slow) );
  (* dont_touch = "true" *) sg13g2_mux2_1 u_f7_mux  ( .A0(node_fine[0]), .A1(f7_slow), .S(fine_en[7]), .X(node_fine[1]) );

  // --- Stage F6 (Bit 6): Step = 128.0 ps (A0 = 0.0 ps, A1 = 1x sg13g2_buf_1 = 128.0 ps) ---
  (* keep = "true" *) logic f6_slow;
  (* dont_touch = "true" *) sg13g2_buf_1  u_f6_and1 ( .A(node_fine[1]), .X(f6_slow) );
  (* dont_touch = "true" *) sg13g2_mux2_1 u_f6_mux  ( .A0(node_fine[1]), .A1(f6_slow), .S(fine_en[6]), .X(node_fine[2]) );

  // --- Stage F5 (Bit 5): Step = 64.0 ps (A0 = 0.0 ps, A1 = 1x sg13g2_and2_1 = 64.0 ps) ---
  (* keep = "true" *) logic f5_slow;
  (* dont_touch = "true" *) sg13g2_and2_1 u_f5_and1 ( .A(node_fine[2]), .B(tie_hi), .X(f5_slow) );
  (* dont_touch = "true" *) sg13g2_mux2_1 u_f5_mux  ( .A0(node_fine[2]), .A1(f5_slow), .S(fine_en[5]), .X(node_fine[3]) );

  // --- Stage F4 (Bit 4): Vernier Step = 32.0 ps (A0 = sg13g2_and2_1 [64.0 ps], A1 = 2x sg13g2_nand2_2 [96.0 ps]) ---
  (* keep = "true" *) logic f4_fast, f4_mid, f4_slow;
  (* dont_touch = "true" *) sg13g2_and2_1  u_f4_fast ( .A(node_fine[3]), .B(tie_hi), .X(f4_fast) );
  (* dont_touch = "true" *) sg13g2_nand2_2 u_f4_nd1  ( .A(node_fine[3]), .B(tie_hi), .Y(f4_mid)  );
  (* dont_touch = "true" *) sg13g2_nand2_2 u_f4_nd2  ( .A(f4_mid),       .B(tie_hi), .Y(f4_slow) );
  (* dont_touch = "true" *) sg13g2_mux2_1  u_f4_mux  ( .A0(f4_fast),     .A1(f4_slow), .S(fine_en[4]), .X(node_fine[4]) );

  // --- Stage F3 (Bit 3): Vernier Step = 16.0 ps (A0 = sg13g2_and2_1 [64.0 ps], A1 = 2x sg13g2_inv_1 [80.0 ps]) ---
  (* keep = "true" *) logic f3_fast, f3_mid, f3_slow;
  (* dont_touch = "true" *) sg13g2_and2_1 u_f3_fast ( .A(node_fine[4]), .B(tie_hi), .X(f3_fast) );
  (* dont_touch = "true" *) sg13g2_inv_1  u_f3_inv1 ( .A(node_fine[4]), .Y(f3_mid)  );
  (* dont_touch = "true" *) sg13g2_inv_1  u_f3_inv2 ( .A(f3_mid),       .Y(f3_slow) );
  (* dont_touch = "true" *) sg13g2_mux2_1 u_f3_mux  ( .A0(f3_fast),     .A1(f3_slow), .S(fine_en[3]), .X(node_fine[5]) );

  // --- Stage F2 (Bit 2): Vernier Step = 8.0 ps (A0 = sg13g2_and2_1 [64.0 ps], A1 = sg13g2_or2_1 [72.0 ps]) ---
  (* keep = "true" *) logic f2_fast, f2_slow;
  (* dont_touch = "true" *) sg13g2_and2_1 u_f2_fast ( .A(node_fine[5]), .B(tie_hi), .X(f2_fast) );
  (* dont_touch = "true" *) sg13g2_or2_1  u_f2_slow ( .A(node_fine[5]), .B(tie_lo), .X(f2_slow) );
  (* dont_touch = "true" *) sg13g2_mux2_1 u_f2_mux  ( .A0(f2_fast),     .A1(f2_slow), .S(fine_en[2]), .X(node_fine[6]) );

  // --- Stage F1 (Bit 1): Vernier Step = 4.0 ps (A0 = sg13g2_and2_1 [64.0 ps], A1 = sg13g2_or2_2 [68.0 ps]) ---
  (* keep = "true" *) logic f1_fast, f1_slow;
  (* dont_touch = "true" *) sg13g2_and2_1 u_f1_fast ( .A(node_fine[6]), .B(tie_hi), .X(f1_fast) );
  (* dont_touch = "true" *) sg13g2_or2_2  u_f1_slow ( .A(node_fine[6]), .B(tie_lo), .X(f1_slow) );
  (* dont_touch = "true" *) sg13g2_mux2_1 u_f1_mux  ( .A0(f1_fast),     .A1(f1_slow), .S(fine_en[1]), .X(node_fine[7]) );

  // --- Stage F0 (Bit 0): Vernier Step = 2.0 ps (A0 = sg13g2_and2_1 [64.0 ps], A1 = sg13g2_and2_2 [66.0 ps]) ---
  (* keep = "true" *) logic f0_fast, f0_slow;
  (* dont_touch = "true" *) sg13g2_and2_1 u_f0_fast ( .A(node_fine[7]), .B(tie_hi), .X(f0_fast) );
  (* dont_touch = "true" *) sg13g2_and2_2 u_f0_slow ( .A(node_fine[7]), .B(tie_hi), .X(f0_slow) );
  (* dont_touch = "true" *) sg13g2_mux2_1 u_f0_mux  ( .A0(f0_fast),     .A1(f0_slow), .S(fine_en[0]), .X(node_fine[8]) );

  // ----------------------------------------------------------------------------
  // 5. High-Speed Sigma-Delta Dither Vernier Stage (Step = 2.0 ps / 16 = 0.125 ps = 125 fs)
  //    Modulates the 4 fractional LSBs (~otw[3:0]) at f_DCO using SG13G2 cells
  // ----------------------------------------------------------------------------
  (* keep = "true" *) logic sdm_fast, sdm_slow;
  (* dont_touch = "true" *) sg13g2_and2_1 u_sdm_fast ( .A(node_fine[8]), .B(tie_hi), .X(sdm_fast) );
  (* dont_touch = "true" *) sg13g2_and2_2 u_sdm_slow ( .A(node_fine[8]), .B(tie_hi), .X(sdm_slow) );
  (* dont_touch = "true" *) sg13g2_mux2_1 u_sdm_mux  ( .A0(sdm_fast),    .A1(sdm_slow), .S(sdm_carry), .X(node_sdm_out) );

  // ----------------------------------------------------------------------------
  // 6. Tail Base Ring Delay Chain (2x sg13g2_buf_1 [256 ps] + 2x sg13g2_and2_1 [128 ps] + 2x sg13g2_inv_1 [80 ps] = 464.0 ps)
  //    Guarantees all parallel MUX branches have settled to 1'b1 before posedge dco_clk_out
  //    Total T_half_min = 48 + 384 + 600 + 640 + 104 + 464 = 2240.00 ps (f_max = 223.21 MHz)
  //    Total T_half_max = 2240.00 + 8191.875 = 10431.875 ps (f_min = 47.93 MHz)
  // ----------------------------------------------------------------------------
  (* dont_touch = "true" *) sg13g2_buf_1  u_tail_buf  ( .A(node_sdm_out),  .X(node_tail_buf) );
  (* dont_touch = "true" *) sg13g2_buf_1  u_tail_buf2 ( .A(node_tail_buf), .X(node_tail_b2)  );
  (* dont_touch = "true" *) sg13g2_and2_1 u_tail_and1 ( .A(node_tail_b2),  .B(tie_hi), .X(node_tail_a1) );
  (* dont_touch = "true" *) sg13g2_and2_1 u_tail_and2 ( .A(node_tail_a1),  .B(tie_hi), .X(node_tail_a2) );
  (* dont_touch = "true" *) sg13g2_inv_1  u_tail_inv1 ( .A(node_tail_a2),  .Y(node_tail_inv) );
  (* dont_touch = "true" *) sg13g2_inv_1  u_tail_inv2 ( .A(node_tail_inv), .Y(ring_feedback) );

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
