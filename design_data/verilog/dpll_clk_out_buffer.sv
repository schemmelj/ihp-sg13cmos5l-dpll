// ==============================================================================
// File: testchip/rtl/dpll_clk_out_buffer.sv
// Description: Synthesizable Very Strong Clock Output Buffer for IHP 130nm
//              BiCMOS (SG13G2). Implements a 4-stage tapered exponential horn
//              (sg13g2_buf_2 -> sg13g2_buf_4 -> sg13g2_buf_8 -> sg13g2_buf_16)
//              that isolates the internal DPLL ring oscillator from pad loading
//              and drives the low-impedance Analog IO Test Pad (sg13g2_IOPadAnalog)
//              across the 50 MHz - 200 MHz output frequency range.
// ==============================================================================

`timescale 1ps / 1fs

(* dont_touch = "true" *)
module dpll_clk_out_buffer (
  input  logic clk_in,          // Internal DPLL synthesized clock (dco_clk_out)
  output logic clk_out_analog   // High-drive clock output to sg13g2_IOPadAnalog
);

  (* keep = "true" *) logic n_stg1;
  (* keep = "true" *) logic n_stg2;
  (* keep = "true" *) logic n_stg3;

  // Stage 1: Low-input-capacitance isolation buffer (2x drive)
  (* dont_touch = "true" *)
  sg13g2_buf_2 u_buf_stg1 (
    .A (clk_in),
    .X (n_stg1)
  );

  // Stage 2: Intermediate pre-driver buffer (4x drive)
  (* dont_touch = "true" *)
  sg13g2_buf_4 u_buf_stg2 (
    .A (n_stg1),
    .X (n_stg2)
  );

  // Stage 3: High-drive pre-driver buffer (8x drive)
  (* dont_touch = "true" *)
  sg13g2_buf_8 u_buf_stg3 (
    .A (n_stg2),
    .X (n_stg3)
  );

  // Stage 4: Duplicated parallel output clock driver stage (2x sg13g2_buf_16)
  //          Halves the CMOS driver output resistance from 85.0 Ohm to 42.50 Ohm
  //          and doubles the drain/source contact and finger count (80 Cont on X,
  //          104 Cont on VDD, 88 Cont on VSS) so that together with the 7.50 Ohm
  //          multi-via & widened interconnect network the total series output
  //          impedance at pad_dco_clk_out is matched to 50.0 Ohm.
  (* dont_touch = "true" *)
  sg13g2_buf_16 u_buf_stg4 (
    .A (n_stg3),
    .X (clk_out_analog)
  );

  (* dont_touch = "true" *)
  sg13g2_buf_16 u_buf_stg4_b (
    .A (n_stg3),
    .X (clk_out_analog)
  );

endmodule

