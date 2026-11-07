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
  // tap[0] is clk_in directly (0 ps delay) to eliminate the input inverter deadband.
  (* keep = "true" *) wire tap [0:NUM_STAGES];
  assign tap[0] = clk_in;

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

  // 3. Polarity Normalization, 3-Tap Bubble Suppression & Priority Thermometer Encoder
  logic [NUM_STAGES-1:0] norm_q;
  logic [NUM_STAGES-1:0] clean_q;
  logic [8:0]            edge_pos;
  logic                  edge_found;
  logic [8:0]            edge_pos_clamped;
  logic [8:0]            quarter_period_steps;

  assign quarter_period_steps = half_period_steps >> 1;

  always @(dff_sync_q or half_period_steps or quarter_period_steps) begin
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

    dco_level  = clean_q[0];
    edge_pos   = 9'd0;
    edge_found = 1'b0;
    if (clean_q[0] == 1'b1) begin
      // DCO is HIGH: locate first 1 -> 0 transition (most recent rising wavefront)
      for (int j = 0; j < NUM_STAGES - 1; j++) begin
        if (!edge_found && (clean_q[j] == 1'b1) && (clean_q[j+1] == 1'b0)) begin
          edge_pos   = 9'(j);
          edge_found = 1'b1;
        end
      end
    end else begin
      // DCO is LOW: locate first 0 -> 1 transition (most recent falling wavefront)
      for (int j = 0; j < NUM_STAGES - 1; j++) begin
        if (!edge_found && (clean_q[j] == 1'b0) && (clean_q[j+1] == 1'b1)) begin
          edge_pos   = 9'(j);
          edge_found = 1'b1;
        end
      end
    end

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
