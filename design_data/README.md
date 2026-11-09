# Design Data

This directory contains the primary design source, firmware, and deliverable files for the IHP SG13CMOS5L DPLL testchip (`dpll_testchip_top`):

- `gds/`: Full-chip GDSII layout files (`PLL3540.gds` and `PLL3540.gds.gz`).
- `def/`: Complete placed-and-routed DEF (`dpll_testchip.def`, 544.32 x 544.32 um core, 12,117 functional cells).
- `cdl/`: Transistor-level CDL schematic netlist (`dpll_testchip_schematic.cdl`).
- `verilog/`: Synthesizable SystemVerilog RTL and post-layout gate-level netlist (`dpll_testchip_clean.v`).
- `firmware/`: Portable C99 and Arduino driver (`dpll_firmware.h`, `dpll_firmware.c`, `dpll_spi.h`, `dpll_arduino_example/`) implementing automatic setup calculation and 1-lock silicon speed-index calibration (`REG_OTW_CUR`).
