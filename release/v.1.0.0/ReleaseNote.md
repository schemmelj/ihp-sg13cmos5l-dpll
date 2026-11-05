# Release Note: v.1.0.0 (Tapeout Candidate)

- **Technology:** IHP 130 nm CMOS (SG13CMOS5L, 5-metal stack: M1-M4 thin, TM1 thick 2.0 um).
- **Die Dimensions:** 1200 x 1200 um^2 (1.44 mm^2), 16 wirebond pads on TopMetal1 (70 x 70 um).
- **Sign-Off Deliverables:**
  - Complete tapeout GDSII (`FMD_QNC_dpll_testchip.gds.gz`, 14 MB compressed / 75 MB uncompressed).
  - Placed and routed DEF (`dpll_testchip.def`).
  - Transistor-level CDL netlist (`dpll_testchip_schematic.cdl`).
  - Synthesizable SystemVerilog RTL source and post-PnR gate netlist.
  - Standalone documentation manual (`testchip_documentation.pdf`).
- **Physical Verification Sign-Off:**
  - **Foundry DRC:** Clean (0 violations in `sg13g2_maximal.lydrc` with `$densityRules = true`).
  - **Transistor-Level LVS:** Clean match (83,952 devices, 42,205 nets, 0 differences in `sg13g2.lvs`).
  - **Global Layer Density:** All 7 layers pass IHP specs (Activ 36.20%, GatPoly 25.08%, M1 35.78%, M2 38.33%, M3 41.55%, M4 38.98%, TM1 41.85%).
  - **Local Window Density:** 100% pass across all 800 x 800 um^2 tiles (step 400 um) per IHP maximal rule deck.
  - **Dummy Metal Fill:** Integrated on GatPoly (5/22, 272.2k um^2) and Metal2 (10/22, 356.8k um^2); verified against `MFil.c` and `MFil.a2`.
  - **Antenna & Dynamic IR-Drop:** Max antenna 407.72:1 (< 40,308:1 spec), dynamic IR-drop 3.78% (< 5.0% spec).
  - **Multi-Corner Dynamic Simulation:** 9/9 corner checks pass (TYP, FAST, SLOW).
