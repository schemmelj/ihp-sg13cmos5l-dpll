# PLL3540-main

Main design views and sign-off artifacts for the IHP SG13CMOS5L Standalone DPLL Testchip (`PLL3540`).

## Directory Layout
- `layout/klayout/` : Full-chip sign-off GDSII stream (`PLL3540.gds`, top cell: `PLL3540`).
- `layout/def/`     : Routed full-chip DEF (`PLL3540.def`).
- `netlist/schematic/` : CDL transistor-level schematic netlist (`PLL3540.cdl`).
- `verification/drc/`  : Foundry DRC and layer density sign-off reports (0 errors, 100% compliant).
- `verification/lvs/`  : Transistor-level LVS verification report (104,386 devices, 52,492 nets, MATCH).
- `model/`          : Behavioral models and simulation primitives.
- `schematic/`      : Circuit schematics.
- `testbenches/`    : Verification testbenches across corners and operating modes.
- `timing/`         : Timing models, constraints, and SDF data.

## Cell Characteristics
- **Top Cell Name:** `PLL3540`
- **Die Size:** $1200\,\mu\text{m} \times 1200\,\mu\text{m}$ ($1.440\,\text{mm}^2$)
- **Core Area:** $544.32\,\mu\text{m} \times 544.32\,\mu\text{m}$ ($0.2963\,\text{mm}^2$)
- **Technology:** IHP SG13CMOS5L (5-metal stack: M1-M4 thin, TM1 thick)
- **Power Domains:** `VDD_CORE` (1.2V), `VDD_DCO` (1.2V), `VDD_TDC` (1.2V), `IOVDD` (3.3V)

