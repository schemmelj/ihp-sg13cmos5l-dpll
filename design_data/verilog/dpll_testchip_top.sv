// ==============================================================================
// File: testchip/rtl/dpll_testchip_top.sv
// Description: Full Standalone Tapeout-Ready IHP 130nm BiCMOS (SG13CMOS5L IO +
//              SG13G2 Standard-Cell Core) DPLL Testchip Top-Level Module.
//
//              Architecture:
//                1. Full IHP SG13CMOS5L IO Padring (16 Pads + 4 Corners + IO Fillers):
//                   - 3 Separate 1.2V Core/Analog VCC Supply Domains:
//                       * VDD_CORE (u_pad_vdd_core : sg13cmos5l_IOPadVdd)
//                       * VDD_DCO  (u_pad_vdd_dco  : sg13cmos5l_IOPadVdd)
//                       * VDD_TDC  (u_pad_vdd_tdc  : sg13cmos5l_IOPadVdd)
//                   - 3 Dedicated 0V Ground Return Pads (sg13cmos5l_IOPadVss):
//                       * u_pad_vss_core, u_pad_vss_dco, u_pad_vss_tdc
//                   - 3.3V IO Padring Supply & Ground (sg13cmos5l_IOPadIOVdd / IOVss):
//                       * u_pad_iovdd, u_pad_iovss
//                   - 5 Digital Input Pads (sg13cmos5l_IOPadIn):
//                       * pad_ref_clk (1..10 MHz), pad_rst_n, pad_spi_cs_n, pad_spi_sck, pad_spi_mosi
//                   - 2 Digital Output Pads (sg13cmos5l_IOPadOut16mA):
//                       * pad_spi_miso, pad_locked
//                   - 1 Direct Analog Test Output Pad (sg13cmos5l_IOPadAnalog):
//                       * pad_dco_clk_out (1 Hz .. 500 MHz, programmable duty cycle < 100 MHz)
//                2. Asynchronous SPI Slave Controller (u_spi_slave, independent of ref_clk)
//                3. All-Digital Phase-Locked Loop Core (u_dpll : 250-500 MHz DCO +
//                   Glitch-Free Fractional-N Output Divider 1 Hz .. 500 MHz)
//                4. 4-Stage Tapered Very Strong Clock Buffer (u_clk_out_buf)
// ==============================================================================

`timescale 1ps / 1fs

module dpll_testchip_top (
`ifndef SYNTHESIS
  // Three Separate 1.2V VCC Supplies + Ground + 3.3V IO Supplies
  inout  wire pad_vdd_core,      // 1.2V Digital Core & Loop Filter & SPI Supply
  inout  wire pad_vdd_dco,       // 1.2V Isolated DCO Ring Oscillator Supply
  inout  wire pad_vdd_tdc,       // 1.2V Isolated 256-Stage Flash TDC Supply
  inout  wire pad_vss,           // 0.0V Ground Return
  inout  wire pad_iovdd,         // 3.3V IO Ring Supply
  inout  wire pad_iovss,         // 0.0V IO Ring Ground
`endif

  // External Digital & Analog Signal Pads
  input  wire pad_ref_clk,       // 1.0 - 10.0 MHz Reference Clock Input Pad
  input  wire pad_rst_n,         // Active-Low Asynchronous Reset Input Pad
  input  wire pad_spi_cs_n,      // SPI Slave Chip Select Input Pad (Active Low)
  input  wire pad_spi_sck,       // SPI Slave Clock / Shift Enable Input Pad
  input  wire pad_spi_mosi,      // SPI Slave Master-Out Slave-In Input Pad
  output wire pad_spi_miso,      // SPI Slave Master-In Slave-Out Output Pad
  output wire pad_locked,        // DPLL Hardware Lock Detector Status Output Pad
  inout  wire pad_dco_clk_out    // Analog IO Cell Test Output for Generated Clock (1 Hz .. 500 MHz)
);

  // Internal Core-Side Pad Signals
  logic ref_clk_core;
  logic rst_n_core;
  logic spi_cs_n_core;
  logic spi_sck_core;
  logic spi_mosi_core;
  logic spi_miso_core;
  logic locked_core;
  logic dco_clk_core;

  // Programmable DPLL & Output Fractional-N Divider Parameters Driven by SPI Slave
  logic [15:0] otw_nominal;
  logic [15:0] otw_mon;
  logic [9:0]  div_n;
  logic [7:0]  fb_frac;
  logic [5:0]  kp_mult;
  logic [3:0]  ki_mult;
  logic [3:0]  ki_shift;
  logic        fast_lock_en;
  logic [2:0]  fast_lock_mult;
  logic [7:0]  gear_shift_thresh;
  logic        integrator_freeze;
  logic        integrator_rst;
  logic        clr_lock;
  logic        out_div_bypass;
  logic        out_mul2_en;
  logic [4:0]  out_prescale_shift;
  logic [9:0]  out_div_int;
  logic [7:0]  out_div_frac;
  logic [7:0]  out_duty;

  // ============================================================================
  // 1. IHP SG13CMOS5L IO Padring Instantiations
  // ============================================================================

  // --- West Side: Reference Clock, Reset, SPI CS_N, SPI MOSI ---
  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadIn u_pad_rst_n (
    .pad (pad_rst_n),
    .p2c (rst_n_core)
  );

  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadIn u_pad_ref_clk (
    .pad (pad_ref_clk),
    .p2c (ref_clk_core)
  );

  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadIn u_pad_spi_cs_n (
    .pad (pad_spi_cs_n),
    .p2c (spi_cs_n_core)
  );

  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadIn u_pad_spi_mosi (
    .pad (pad_spi_mosi),
    .p2c (spi_mosi_core)
  );

  // --- South Side: SPI SCK, SPI MISO, Locked Status, Core Supply VDD_CORE ---
  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadIn u_pad_spi_sck (
    .pad (pad_spi_sck),
    .p2c (spi_sck_core)
  );

  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadOut16mA u_pad_spi_miso (
    .pad (pad_spi_miso),
    .c2p (spi_miso_core)
  );

  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadOut16mA u_pad_locked (
    .pad (pad_locked),
    .c2p (locked_core)
  );

  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadVdd u_pad_vdd_core ();

  // --- East Side: Core Ground, Analog Clock Test Output, Isolated VDD_DCO & VSS_DCO ---
  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadVss u_pad_vss_core ();

`ifdef SYNTHESIS
  logic dco_clk_strong;
  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadAnalog u_pad_clk_out (
    .pad    (pad_dco_clk_out),
    .padres (dco_clk_strong)
  );
`else
  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadAnalog u_pad_clk_out (
    .pad    (pad_dco_clk_out),
    .padres ()
  );
`endif

  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadVdd u_pad_vdd_dco ();

  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadVss u_pad_vss_dco ();

  // --- North Side: Isolated VDD_TDC, VSS_TDC, 3.3V IOVDD, 0V IOVSS ---
  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadVdd u_pad_vdd_tdc ();

  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadVss u_pad_vss_tdc ();

  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadIOVdd u_pad_iovdd ();

  (* keep = "true", dont_touch = "true" *)
  sg13cmos5l_IOPadIOVss u_pad_iovss ();

`ifndef SYNTHESIS
  // Supply-aware check in behavioral/RTL simulation: all 3 VCC supplies must be active
  wire pwr_ok = pad_vdd_core & pad_vdd_dco & pad_vdd_tdc & (~pad_vss) & pad_iovdd & (~pad_iovss);
  wire rst_n_eff = rst_n_core & pwr_ok;
`else
  wire rst_n_eff = rst_n_core;
`endif

  // ============================================================================
  // 2. Asynchronous SPI Slave Controller (Sets All DPLL & Output Divider Parameters)
  // ============================================================================
  dpll_spi_slave u_spi_slave (
    .clk                (ref_clk_core),
    .rst_n              (rst_n_eff),
    .spi_cs_n           (spi_cs_n_core),
    .spi_sck            (spi_sck_core),
    .spi_mosi           (spi_mosi_core),
    .spi_miso           (spi_miso_core),
    .locked             (locked_core),
    .otw_mon            (otw_mon),
    .otw_nominal        (otw_nominal),
    .div_n              (div_n),
    .fb_frac            (fb_frac),
    .kp_mult            (kp_mult),
    .ki_mult            (ki_mult),
    .ki_shift           (ki_shift),
    .fast_lock_en       (fast_lock_en),
    .fast_lock_mult     (fast_lock_mult),
    .gear_shift_thresh  (gear_shift_thresh),
    .integrator_freeze  (integrator_freeze),
    .integrator_rst     (integrator_rst),
    .clr_lock           (clr_lock),
    .out_div_bypass     (out_div_bypass),
    .out_mul2_en        (out_mul2_en),
    .out_prescale_shift (out_prescale_shift),
    .out_div_int        (out_div_int),
    .out_div_frac       (out_div_frac),
    .out_duty           (out_duty)
  );

  // ============================================================================
  // 3. All-Digital Phase-Locked Loop Core (250-500 MHz DCO + Frac-N Output Divider)
  // ============================================================================
  dpll_top u_dpll (
    .ref_clk            (ref_clk_core),
    .rst_n              (rst_n_eff),
    .otw_nominal        (otw_nominal),
    .div_n              (div_n),
    .fb_frac            (fb_frac),
    .kp_mult            (kp_mult),
    .ki_mult            (ki_mult),
    .ki_shift           (ki_shift),
    .fast_lock_en       (fast_lock_en),
    .fast_lock_mult     (fast_lock_mult),
    .gear_shift_thresh  (gear_shift_thresh),
    .integrator_freeze  (integrator_freeze),
    .integrator_rst     (integrator_rst),
    .clr_lock           (clr_lock),
    .out_div_bypass     (out_div_bypass),
    .out_mul2_en        (out_mul2_en),
    .out_prescale_shift (out_prescale_shift),
    .out_div_int        (out_div_int),
    .out_div_frac       (out_div_frac),
    .out_duty           (out_duty),
    .dco_clk_out        (dco_clk_core),
    .locked             (locked_core),
    .otw_mon            (otw_mon)
  );

  // ============================================================================
  // 4. Very Strong Tapered Clock Output Buffer Driving Analog IO Test Cell
  // ============================================================================
`ifdef SYNTHESIS
  dpll_clk_out_buffer u_clk_out_buf (
    .clk_in             (dco_clk_core),
    .clk_out_analog     (dco_clk_strong)
  );
`else
  dpll_clk_out_buffer u_clk_out_buf (
    .clk_in             (dco_clk_core),
    .clk_out_analog     (pad_dco_clk_out)
  );
`endif

endmodule
