// ==============================================================================
// File: clk_divider.sv
// Description: Synthesizable High-Speed Programmable Divider for IHP 130nm
//              BiCMOS (SG13G2) ADPLL.
//              Operates at 50 MHz - 200 MHz DCO rate, dividing down to 1 MHz
//              (Integer division ratio N = 50..200).
// ==============================================================================

`timescale 1ps / 1fs

module clk_divider #(
  parameter int DIV_WIDTH = 8
)(
  input  logic                 clk,           // 50 - 200 MHz DCO clock
  input  logic                 rst_n,         // Active-low reset (synchronized to clk)
  input  logic [DIV_WIDTH-1:0] div_ratio,     // Integer division ratio N (50..200)
  output logic                 clk_out,       // 1 MHz divided feedback clock
  output logic [DIV_WIDTH-1:0] div_phase,     // Rising-edge phase index in DCO cycles (0..N-1)
  output logic [DIV_WIDTH-1:0] div_phase_neg  // Falling-edge retimed phase index for metastability-free CDC
);

  logic [DIV_WIDTH-1:0] half_div;

  assign half_div = (div_ratio > 8'd2) ? ((div_ratio >> 1) - 1'b1) : 8'd0;

  // Primary coarse phase counter clocked on posedge DCO clock
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      div_phase <= '0;
      clk_out   <= 1'b0;
    end else begin
      if (div_phase >= div_ratio - 1'b1) begin
        div_phase <= '0;
        clk_out   <= 1'b1;
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
