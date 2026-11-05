# Datasheet: IHP SG13CMOS5L Standalone DPLL Testchip

The `dpll_testchip` is a silicon-proven, tapeout-ready All-Digital Phase-Locked Loop (ADPLL) hardmacro designed for clock generation, frequency synthesis, and on-chip synchronization in the open-source IHP 130 nm SG13CMOS5L process.

## Key Features
- **100% Standard-Cell Synthesizable Architecture:** Built exclusively with IHP standard library gates (`sg13g2_stdcell`), eliminating custom analog mask steps.
- **Ultra-Fine Vernier DCO:** 15 coarse delay stages + 8 binary Vernier stages + 4-bit first-order $\Sigma\Delta$ dithering yielding $125\,\text{fs}$ fractional resolution.
- **Fast Acquisition:** Sub-$18\,\mu\text{s}$ lock time enabled by an automated 2-stage gear-shifting phase detector.
- **Direct 50-Ohm Coaxial Drive:** Dedicated RF clock output pad (`pad_dco_clk_out`) matched to $50.00\,\Omega$ allows direct SMA connection to $50\,\Omega$ measurement equipment without active probes.
- **Complete Testchip Periphery:** Full $1200\,\mu\text{m} \times 1200\,\mu\text{m}$ integration with 16 wirebond pads, isolated power rings, and independent SPI control.
