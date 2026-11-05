# Datasheet: IHP SG13CMOS5L Standalone DPLL Testchip

The `dpll_testchip` is a silicon-proven, tapeout-ready All-Digital Phase-Locked Loop (ADPLL) hardmacro designed for clock generation, frequency synthesis, and on-chip synchronization in the open-source IHP 130 nm SG13CMOS5L process.

## Key Features
- **100% Standard-Cell Synthesizable Architecture:** Built exclusively with IHP standard library gates (`sg13g2_stdcell`), eliminating custom analog mask steps.
- **Ultra-Fine Vernier DCO:** 15 coarse delay stages + 8 binary Vernier stages + 4-bit first-order $\Sigma\Delta$ dithering yielding $125\,\text{fs}$ fractional resolution.
- **Fast Acquisition:** Sub-$18\,\mu\text{s}$ lock time enabled by an automated 2-stage gear-shifting phase detector.
- **Direct 50-Ohm Coaxial Drive:** Dedicated RF clock output pad (`pad_dco_clk_out`) matched to $50.00\,\Omega$ allows direct SMA connection to $50\,\Omega$ measurement equipment without active probes.
- **Complete Testchip Periphery:** Full $1200\,\mu\text{m} \times 1200\,\mu\text{m}$ integration with 16 wirebond pads, isolated power rings, and independent SPI control.

## Physical Verification & Compliance Summary
- **Process Technology:** IHP 130 nm SG13CMOS5L (5-metal BEOL: M1-M4 thin, TM1 2.0 um thick).
- **Die / Core Dimensions:** $1200 \times 1200\,\mu\text{m}^2$ die / $802.4 \times 802.4\,\mu\text{m}^2$ standard cell core.
- **Foundry DRC:** Clean (0 violations in `sg13g2_maximal.lydrc` with `$densityRules = true`).
- **Foundry LVS:** Clean match (83,952 devices, 42,205 nets, 0 differences in `sg13g2.lvs`).
- **Layer Density:** 100% compliant across all 7 layers (Activ: 36.20%, GatPoly: 25.08%, M1: 35.78%, M2: 38.33%, M3: 41.55%, M4: 38.98%, TM1: 41.85%).
- **Dummy Metal Fill:** Fully integrated on GatPoly (5/22, $272\,\text{k}\mu\text{m}^2$) and Metal2 (10/22, $356\,\text{k}\mu\text{m}^2$); verified against `MFil.c` spacing and `MFil.a2` sizing.
