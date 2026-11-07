# Datasheet: IHP SG13CMOS5L Standalone DPLL Testchip

The `dpll_testchip_top` is a tapeout-ready All-Digital Phase-Locked Loop (ADPLL) hardmacro designed for wide-range clock synthesis ($1\,\text{Hz}$ to $1.0\,\text{GHz}$), Fractional-N frequency generation, and programmable duty-cycle synthesis in the open-source IHP 130 nm SG13CMOS5L process.

## Key Features
- **100% Standard-Cell Synthesizable Architecture:** Built exclusively with IHP standard library gates (`sg13g2_stdcell`) and `sg13cmos5l_io` pads, eliminating custom analog mask steps.
- **1-Octave Vernier DCO ($250 - 500\,\text{MHz}$):** 3 head inverter stages + 15 coarse NAND delay stages + 8 binary Vernier capacitor-load stages + 1 $\Delta\Sigma$ dithering stage with guaranteed PVT overlap across Slow ($1.08\,\text{V}, 125^\circ\text{C}$), Typical ($1.20\,\text{V}, 25^\circ\text{C}$), and Fast ($1.32\,\text{V}, -40^\circ\text{C}$) corners.
- **Wideband Output Synthesis ($1\,\text{Hz}$ to $1.0\,\text{GHz}$):** Glitch-free 24-bit integer + 8-bit Fractional-N output divider (`1 Hz` to `500 MHz`, programmable duty cycle `< 100 MHz`) combined with an SPI-switchable $2\times$ XOR physical frequency multiplier (`500 MHz` to `1.0 GHz`).
- **Closed-Loop Silicon Speed-Index Calibration (`REG_OTW_CUR`):** Hardware readback of the converged loop-filter oscillator tuning word (`0x08`) allows the embedded C/Arduino driver (`dpll_configure_and_lock()`) to calibrate the silicon speed index (`speed_idx`) in a single lock and pre-position `REG_OTW_NOM` with `0 LSB` error on all subsequent frequency hops.
- **Direct 50-Ohm Coaxial Drive:** Dedicated RF clock output pad (`pad_dco_clk_out`) matched to $50.00\,\Omega$ allows direct SMA connection to $50\,\Omega$ measurement equipment without active probes.
- **Complete Testchip Periphery:** Full $1200\,\mu\text{m} \times 1200\,\mu\text{m}$ integration with 16 wirebond pads, 3 isolated $1.2\,\text{V}$ core power domains, $3.3\,\text{V}$ ESD padring, and an independent SPI Mode 0 slave.

## Physical Verification & Compliance Summary
- **Process Technology:** IHP 130 nm SG13CMOS5L (5-metal BEOL: M1-M4 thin, TM1 2.0 um thick).
- **Die / Core Dimensions:** $1200 \times 1200\,\mu\text{m}^2$ die / $544.32 \times 544.32\,\mu\text{m}^2$ standard-cell core ($11,239$ synthesized / $12,117$ post-route cells).
- **Foundry DRC:** Clean (0 violations in `sg13cmos5l_drc.lydrc` / `sg13g2_maximal.lydrc` with `$densityRules = true`).
- **Foundry LVS:** Clean match (104,386 devices, 52,492 nets, 0 differences in `sg13cmos5l.lvs`).
- **Formal LEC:** 100% proven (9,418 / 9,418 `$equiv` cells proven via Yosys SAT + temporal induction).
- **Layer Density:** 100% compliant across all 7 layers (Activ: 36.08%, GatPoly: 18.89%, M1: 35.55%, M2: 39.91%, M3: 37.17%, M4: 56.40%, TM1: 34.51%).
- **6-Corner Gate-Level SDF Verification:** 15 / 15 testbench checks pass with 0 glitches across post-layout (`TYP`, `FAST`, `SLOW`) and pre-layout (`SYNTH_TYP`, `SYNTH_FAST`, `SYNTH_SLOW`) corners.
