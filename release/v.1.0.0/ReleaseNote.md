# Release Note: v.1.0.0 (Tapeout Candidate)

- **Technology:** IHP 130 nm CMOS (SG13CMOS5L, 5-metal stack: M1-M4 thin, TM1 thick 2.0 um).
- **Die / Core Dimensions:** 1200 x 1200 um^2 die (1.44 mm^2), 544.32 x 544.32 um^2 core (0.2963 mm^2), 16 wirebond pads on TopMetal1 (70 x 70 um).
- **Architecture & Firmware:**
  - 250-500 MHz 1-octave Vernier ring DCO (3 head + 15 coarse + 8 fine + 1 SDM stage).
  - Glitch-free Fractional-N output divider (1 Hz - 500 MHz, programmable duty cycle) + SPI-switchable 2x XOR physical output multiplier (500 MHz - 1.0 GHz).
  - 9 SPI registers (`0x00`..`0x08`) including live `REG_OTW_CUR (0x08)` readback and C99/Arduino `dpll_configure_and_lock()` silicon speed-index calibration (`speed_idx`).
- **Sign-Off Deliverables:**
  - Complete tapeout GDSII (`FMD_QNC_dpll_testchip.gds.gz`).
  - Placed and routed DEF (`dpll_testchip.def`).
  - Transistor-level CDL netlist (`dpll_testchip_schematic.cdl`).
  - Synthesizable SystemVerilog RTL source, post-PnR gate netlist (`dpll_testchip_clean.v`), and C/Arduino firmware (`design_data/firmware/`).
  - Standalone documentation manual (`testchip_documentation.pdf`).
- **Physical & Dynamic Verification Sign-Off:**
  - **Foundry DRC:** Clean (0 violations in `sg13cmos5l_drc.lydrc` / `sg13g2_maximal.lydrc` with `$densityRules = true`).
  - **Transistor-Level LVS:** Clean match (104,386 devices, 52,492 nets, 0 differences in `sg13cmos5l.lvs`).
  - **Formal LEC:** 9,418 / 9,418 `$equiv` cells proven via Yosys SAT + temporal induction.
  - **Global & Window Layer Density:** All 7 layers pass IHP global and 800 x 800 um^2 moving-window specs (Activ 36.08%, GatPoly 18.89%, M1 35.55%, M2 39.91%, M3 37.17%, M4 56.40%, TM1 34.51%).
  - **6-Corner Gate-Level SDF Simulation:** 15/15 stage checks pass with 0 glitches across post-layout (`TYP`, `FAST`, `SLOW`) and pre-layout (`SYNTH_TYP`, `SYNTH_FAST`, `SYNTH_SLOW`) corners.
