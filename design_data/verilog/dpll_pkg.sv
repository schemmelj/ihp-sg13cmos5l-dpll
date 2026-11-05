// ==============================================================================
// File: dpll_pkg.sv
// Description: Synthesizable Configuration Parameters and Types for IHP 130nm
//              BiCMOS (SG13G2) All-Digital Phase-Locked Loop (ADPLL)
//              (1 MHz Reference, 50 MHz - 200 MHz DCO Output)
// ==============================================================================

package dpll_pkg;

  // Technology & Frequency Specifications (IHP 130nm BiCMOS SG13G2 - Integer Units)
  localparam int REF_FREQ_MHZ       = 1;           // Reference clock frequency (1 MHz)
  localparam int REF_PERIOD_PS      = 1000000;     // Reference period (1,000,000 ps = 1000 ns = 1 us)
  localparam int DCO_MIN_FREQ_MHZ   = 50;          // Min target frequency (50 MHz)
  localparam int DCO_MAX_FREQ_MHZ   = 200;         // Max target frequency (200 MHz)
  localparam int DCO_BASE_FREQ_MHZ  = 45;          // DCO base frequency (~45.5 MHz)
  localparam int DCO_SPAN_MHZ       = 175;         // Frequency span across OTW range (~175 MHz)
  localparam int TDC_RESOLUTION_PS  = 40;          // IHP 130nm SG13G2 Flash TDC (40 ps/step, sg13g2_inv_1)

  // Architectural Bit-Widths
  localparam int OTW_WIDTH           = 16;         // Oscillator Tuning Word (16-bit)
  localparam int ERROR_WIDTH         = 16;         // Phase error bit width (in 40 ps TDC steps)
  localparam int FILTER_ACC_WIDTH    = 24;         // Loop filter integrator accumulator
  localparam int DIV_WIDTH           = 8;          // Feedback divider ratio width (N = 50..200)

  // Optimal Fast-Settling Default Loop Filter Parameters (calibrated for 40 ps TDC & 1 MHz Ref)
  localparam logic [5:0] DEFAULT_KP_MULT           = 6'd8;  // Proportional gain multiplier
  localparam logic [3:0] DEFAULT_KI_MULT           = 4'd1;  // Integral gain multiplier
  localparam logic [3:0] DEFAULT_KI_SHIFT          = 4'd1;  // Integral gain shift divisor
  localparam logic       DEFAULT_FAST_LOCK_EN      = 1'b1;  // Adaptive gear-shifting enabled
  localparam logic [2:0] DEFAULT_FAST_LOCK_MULT    = 3'd2;  // 2x gain boost during acquisition
  localparam logic [7:0] DEFAULT_GEAR_SHIFT_THRESH = 8'd48; // 48 TDC steps (1920 ps) fine threshold

  // Synthesizable loop filter parameter container struct
  typedef struct packed {
    logic [5:0] kp_mult;
    logic [3:0] ki_mult;
    logic [3:0] ki_shift;
    logic       fast_lock_en;
    logic [2:0] fast_lock_mult;
    logic [7:0] gear_shift_thresh;
  } loop_filter_config_t;

endpackage : dpll_pkg
