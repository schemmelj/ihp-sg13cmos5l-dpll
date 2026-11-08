// ==============================================================================
// File: tdc_flash.sv
// Description: Synthesizable Flash Inverter Delay-Line Time-to-Digital Converter
//              Uses IHP 130nm BiCMOS (SG13G2) sg13g2_inv_1 inverters (~40.0 ps
//              delay each) and sg13g2_dfrbp_1 D-Flip-Flop sampling bank.
//              256 stages cover >6,500 ps to 13,000 ps across FAST/TYP/SLOW corners,
//              providing sub-DCO phase quantization across the 250-500 MHz DCO range.
// ==============================================================================

`timescale 1ps / 1fs

module tdc_flash #(
  parameter int NUM_STAGES = 256,    // 256 inverter stages (10,240 ps span at 40 ps/stage)
  parameter int STEP_PS    = 40      // IHP 130nm SG13G2 unit inverter propagation delay
)(
  input  logic       clk_in,             // High-frequency DCO clock (250 - 500 MHz)
  input  logic       sample_clk,         // Reference clock edge (1 - 10 MHz)
  input  logic       rst_n,              // Active-low reset (synchronized to sample_clk)
  input  logic [8:0] half_period_steps,  // Half DCO period in TDC steps
  output logic [8:0] fine_offset,        // Sub-cycle time offset in TDC steps
  output logic       dco_level,          // Sampled DCO logic level
  output logic       near_posedge        // High when sample_clk landed within +/- T_dco/4 of posedge clk_in
);

  // 1. Tapped Inverter Delay Line (256 stages of 40.0 ps sg13g2_inv_1 cells)
  //    2-stage CTS-matched buffer pair aligns tap[0] insertion delay with the
  //    2-level DCO CTS clock tree feeding clk_divider across all PVT corners.
  (* keep = "true" *) wire clk_in_b1;
  (* keep = "true" *) wire clk_in_matched;
  (* keep = "true" *) wire tap [0:NUM_STAGES];

  (* dont_touch = "true" *)
  sg13g2_buf_4 cts_match_b1 (
    .A (clk_in),
    .X (clk_in_b1)
  );

  (* dont_touch = "true" *)
  sg13g2_buf_8 cts_match_b2 (
    .A (clk_in_b1),
    .X (clk_in_matched)
  );

  assign tap[0] = clk_in_matched;

  genvar i;
  generate
    for (i = 0; i < NUM_STAGES; i++) begin : gen_inv_delay_chain
      (* dont_touch = "true" *)
      sg13g2_inv_1 u_inv (
        .A (tap[i]),
        .Y (tap[i+1])
      );
    end
  endgenerate

  // 2. High-Speed DFF Sampling Bank Clocked by Reference Clock (Stage 1 Capture)
  (* keep = "true" *) logic [NUM_STAGES-1:0] dff_q;
  logic [NUM_STAGES-1:0] dff_sync_q;

  generate
    for (i = 0; i < NUM_STAGES; i++) begin : gen_sampling_dffs
      sg13g2_dfrbp_1 u_dff (
        .D       (tap[i]),
        .CLK     (sample_clk),
        .RESET_B (rst_n),
        .Q       (dff_q[i])
      );
    end
  endgenerate

  // 2b. Half-Cycle Metastability Resolution Register Bank (Stage 2 Synchronizer)
  always_ff @(negedge sample_clk or negedge rst_n) begin
    if (!rst_n) begin
      dff_sync_q <= '0;
    end else begin
      dff_sync_q <= dff_q;
    end
  end

  // 3. Polarity Normalization, 3-Tap Bubble Suppression & 8-Level Binary Tree Priority Encoder
  logic [NUM_STAGES-1:0] norm_q;
  logic [NUM_STAGES-1:0] clean_q;
  logic [255:0]          hit;
  logic [127:0]          v1;
  logic                  idx1 [0:127];
  logic [63:0]           v2;
  logic [1:0]            idx2 [0:63];
  logic [31:0]           v3;
  logic [2:0]            idx3 [0:31];
  logic [15:0]           v4;
  logic [3:0]            idx4 [0:15];
  logic [7:0]            v5;
  logic [4:0]            idx5 [0:7];
  logic [3:0]            v6;
  logic [5:0]            idx6 [0:3];
  logic [1:0]            v7;
  logic [6:0]            idx7 [0:1];
  logic [8:0]            edge_pos;
  logic                  edge_found;
  logic [8:0]            edge_pos_clamped;
  logic [8:0]            quarter_period_steps;

  assign quarter_period_steps = half_period_steps >> 1;

  always_comb begin
    for (int k = 0; k < NUM_STAGES; k++) begin
      norm_q[k] = (k % 2 == 1) ? ~dff_sync_q[k] : dff_sync_q[k];
    end
    clean_q[0] = norm_q[0];
    for (int k = 1; k < NUM_STAGES - 1; k++) begin
      clean_q[k] = (norm_q[k-1] & norm_q[k]) |
                   (norm_q[k]   & norm_q[k+1]) |
                   (norm_q[k-1] & norm_q[k+1]);
    end
    clean_q[NUM_STAGES-1] = norm_q[NUM_STAGES-1];

    dco_level = clean_q[0];

    // Parallel edge-transition indicator vector (j = 0..254)
    for (int j = 0; j < 255; j++) begin
      hit[j] = clean_q[0] ? (clean_q[j] & ~clean_q[j+1]) : (~clean_q[j] & clean_q[j+1]);
    end
    hit[255] = 1'b0;

    // Balanced 8-level O(log2 N) Find-First-Set binary tree priority encoder
    for (int n = 0; n < 128; n++) begin
      v1[n]   = hit[2*n] | hit[2*n+1];
      idx1[n] = ~hit[2*n];
    end
    for (int n = 0; n < 64; n++) begin
      v2[n]   = v1[2*n] | v1[2*n+1];
      idx2[n] = v1[2*n] ? {1'b0, idx1[2*n]} : {1'b1, idx1[2*n+1]};
    end
    for (int n = 0; n < 32; n++) begin
      v3[n]   = v2[2*n] | v2[2*n+1];
      idx3[n] = v2[2*n] ? {1'b0, idx2[2*n]} : {1'b1, idx2[2*n+1]};
    end
    for (int n = 0; n < 16; n++) begin
      v4[n]   = v3[2*n] | v3[2*n+1];
      idx4[n] = v3[2*n] ? {1'b0, idx3[2*n]} : {1'b1, idx3[2*n+1]};
    end
    for (int n = 0; n < 8; n++) begin
      v5[n]   = v4[2*n] | v4[2*n+1];
      idx5[n] = v4[2*n] ? {1'b0, idx4[2*n]} : {1'b1, idx4[2*n+1]};
    end
    for (int n = 0; n < 4; n++) begin
      v6[n]   = v5[2*n] | v5[2*n+1];
      idx6[n] = v5[2*n] ? {1'b0, idx5[2*n]} : {1'b1, idx5[2*n+1]};
    end
    for (int n = 0; n < 2; n++) begin
      v7[n]   = v6[2*n] | v6[2*n+1];
      idx7[n] = v6[2*n] ? {1'b0, idx6[2*n]} : {1'b1, idx6[2*n+1]};
    end
    edge_found = v7[0] | v7[1];
    edge_pos   = edge_found ? (v7[0] ? {2'b00, idx7[0]} : {2'b01, idx7[1]}) : 9'd0;

    if (!edge_found || (edge_pos > half_period_steps)) begin
      edge_pos_clamped = half_period_steps;
    end else begin
      edge_pos_clamped = edge_pos;
    end

    if (clean_q[0] == 1'b1) begin
      fine_offset  = edge_pos_clamped;
      near_posedge = (edge_pos_clamped < quarter_period_steps);
    end else begin
      fine_offset  = half_period_steps + edge_pos_clamped;
      near_posedge = (edge_pos_clamped > quarter_period_steps);
    end
  end

endmodule
