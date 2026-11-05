// ==============================================================================
// File: lock_detector.sv
// Description: Synthesizable Lock Detector with Hysteresis for IHP 130nm BiCMOS
//              (SG13G2) ADPLL.
//              Asserts lock when phase error remains within threshold for
//              LOCK_COUNT_MAX consecutive 1 MHz reference cycles; resets on hop.
// ==============================================================================

`timescale 1ps / 1fs

module lock_detector #(
  parameter int ERROR_WIDTH    = 16,
  parameter int THRESHOLD      = 8,     // TDC step tolerance (+/- 320 ps at 40 ps/step)
  parameter int LOCK_COUNT_MAX = 8      // 8 consecutive reference cycles (8 us at 1 MHz)
)(
  input  logic                             clk,         // 1 MHz Reference clock
  input  logic                             rst_n,       // Active-low asynchronous reset
  input  logic                             clear,       // Synchronous clear on channel hop
  input  logic signed [ERROR_WIDTH-1:0]    phase_error, // From TDC
  input  logic                             error_valid, // Update strobe
  output logic                             locked       // PLL lock status
);

  logic [7:0]                    lock_counter;
  logic signed [ERROR_WIDTH-1:0] abs_error;

  assign abs_error = (phase_error < 0) ? (-phase_error) : phase_error;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lock_counter <= '0;
      locked       <= 1'b0;
    end else if (clear) begin
      lock_counter <= '0;
      locked       <= 1'b0;
    end else if (error_valid) begin
      if (abs_error <= THRESHOLD) begin
        if (lock_counter < LOCK_COUNT_MAX[7:0]) begin
          lock_counter <= lock_counter + 8'd1;
        end else begin
          locked <= 1'b1;
        end
      end else begin
        if (abs_error > (THRESHOLD * 3)) begin
          lock_counter <= '0;
          locked       <= 1'b0;
        end else if (lock_counter > 8'd0) begin
          lock_counter <= lock_counter - 8'd1;
        end else begin
          locked <= 1'b0;
        end
      end
    end
  end

endmodule
