# IHP SG13G2 Standalone DPLL Testchip Tapeout Package

Open-source tapeout repository for the **$1200\,\mu\text{m} \times 1200\,\mu\text{m}$ All-Digital Phase-Locked Loop (ADPLL) Testchip**, fully synthesized and hardened in the **IHP 130nm BiCMOS SG13G2 (SG13CMOS5L)** open-source technology.

Developed in accordance with the **IHP Open-Source Tapeout Specifications** (`IHP-Open-DesignLib` / `FMD_QNC` guidelines).

---

## 1. Key Design Specifications

| Parameter | Value | Unit | Description |
|:---|:---:|:---:|:---|
| **Process Node** | IHP SG13G2 / SG13CMOS5L | - | 130 nm BiCMOS (5 Metal Layers, TopMetal1 thickness $2.0\,\mu\text{m}$) |
| **Chip Dimensions** | $1200 \times 1200$ | $\mu\text{m}$ | Includes standard perimeter sealring |
| **Core Dimensions** | $802.4 \times 802.4$ | $\mu\text{m}$ | Standard-cell rows 0 to 184 |
| **Synthesized Gate Count** | 9,872 | cells | 100% standard cells, zero custom analog primitives |
| **Reference Clock ($f_{\text{ref}}$)** | $1.0$ (nom), up to $10.2$ (typ) | $\text{MHz}$ | Single-ended CMOS reference input |
| **Output Frequency ($f_{\text{out}}$)** | $50.0 - 200.0$ | $\text{MHz}$ | Operational design range ($223.2\,\text{MHz}$ DCO ceiling) |
| **Divider Ratio ($N$)** | $50 - 200$ (nom), $2 - 255$ (hw) | - | 8-bit programmable integer feedback divider |
| **Quantization Step ($t_{\text{LSB}}$)** | $39.5$ | $\text{ps}$ | 256-stage Flash Inverter Delay Line TDC |
| **Phase Noise / Jitter** | $18.0$ (typ), $12.8$ (fast) | $\text{ps}_{\text{rms}}$ | Post-layout back-annotated SDF verification |
| **Lock Time** | $< 18.0$ | $\mu\text{s}$ | Fast adaptive gear-shifting acquisition |
| **Output Impedance** | $50.00$ | $\Omega$ | Direct coaxial $50\,\Omega$ match at bondpad |
| **Core Power Supplies** | 3 independent $1.2\,\text{V}$ rails | $\text{V}$ | `VDD_CORE`, `VDD_DCO`, `VDD_TDC` |
| **IO Padring Supply** | $3.3$ | $\text{V}$ | `IOVDD` / `IOVSS` ESD padring |
| **Total Wirebond Pads** | 16 | pads | $70 \times 70\,\mu\text{m}$ passivated `TopMetal1` openings |

---

## 2. Repository Structure

This repository adheres to the standard IHP open-source submission layout:

```text
├── LICENSE                          # Apache-2.0 open-source license
├── README.md                        # Project overview, pinout, and sign-off scorecard
├── design_data/                     # Primary chip design files
│   ├── gds/
│   │   ├── FMD_QNC_dpll_testchip.gds      # Complete full-chip GDSII layout (75 MB)
│   │   └── FMD_QNC_dpll_testchip.gds.gz   # Gzip-compressed GDSII (14 MB, IHP shuttle delivery)
│   ├── def/
│   │   └── dpll_testchip.def              # Placed and routed DEF netlist
│   ├── cdl/
│   │   └── dpll_testchip_schematic.cdl    # Transistor-level CDL schematic netlist
│   └── verilog/                           # Synthesizable SystemVerilog RTL & gate-level netlists
│       ├── dpll_testchip_top.sv           # Chip top-level module with padring
│       ├── dpll_spi_slave.sv              # Independent asynchronous SPI slave
│       ├── dpll_clk_out_buffer.sv         # 4-stage 50-Ohm matched output clock buffer
│       ├── dco_nco.sv                     # All-standard-cell 15-coarse + 8-fine Vernier DCO
│       ├── pfd_linear.sv                  # Linear Phase Frequency Detector
│       ├── tdc_flash.sv                   # 256-stage Flash Inverter Delay-Line TDC
│       ├── loop_filter.sv                 # Proportional-Integral (PI) digital loop filter
│       ├── clk_divider.sv                 # High-speed feedback divider
│       ├── lock_detector.sv               # Digital windowed lock detector
│       ├── dpll_pkg.sv                    # Configuration package
│       └── dpll_testchip.v                # Full post-PnR gate-level netlist
├── doc/                             # Comprehensive documentation
│   ├── README.md                    # Documentation summary
│   ├── pinout.md                    # Detailed padring bonding and coordinate mapping
│   ├── testchip_documentation.pdf   # Complete 15 MB standalone testchip documentation manual
│   └── figures/                     # High-resolution architectural and layout figures
└── val/                             # Physical and dynamic sign-off verification data
    ├── README.md                    # Validation summary
    ├── drc/
    │   └── drc_summary.rpt          # KLayout SG13G2 DRC sign-off: 0 errors
    ├── lvs/
    │   └── lvs_summary.rpt          # KLayout transistor-level LVS sign-off: MATCH (0 diff)
    └── sim/
        ├── testchip_sim_results.json# Multi-corner dynamic simulation results
        ├── sim_typ.log              # Typical corner post-layout SDF simulation log
        ├── sim_fast.log             # Fast corner post-layout SDF simulation log
        └── sim_slow.log             # Slow corner post-layout SDF simulation log
```

---

## 3. Tapeout Sign-Off Scorecard

| Verification Metric | Target / Rule | Result | Status |
|:---|:---|:---:|:---:|
| **Foundry DRC** | Official IHP `sg13g2.lydrc` (78 rule categories) | **0 Errors** | **PASS** |
| **Transistor-Level LVS** | KLayout `sg13g2.lvs` (83,952 devices, 42,205 nets) | **MATCH (0 Diff)** | **PASS** |
| **Pure Bondpad Reference** | Terminal matching exclusively at 16 TopMetal1 wirebond pads | **Verified** | **PASS** |
| **Logic Equivalence (LEC)**| 3-Stage Formal LEC (Yosys SAT + Induction) | **8,138 / 8,138 Proven** | **PASS** |
| **Process Antenna Ratio** | Max antenna ratio $< 40,308 : 1$ | **407.72 : 1 max** | **PASS** |
| **Clock Output Match** | $50.0\,\Omega \pm 2\,\Omega$ impedance from pad to supply | **$50.00\,\Omega$ exact** | **PASS** |
| **Dynamic IR-Drop** | Output clock buffer peak dynamic drop $< 5.0\,\%$ | **$3.78\,\%$ ($45.4\,\text{mV}$)** | **PASS** |
| **Multi-Corner Post-Layout Sim**| Multi-stage back-annotated torture bench (TYP, FAST, SLOW) | **9/9 checks passed** | **PASS** |
| **Runt Pulses / Glitches** | Continuous cycle-by-cycle monitor | **0 Glitches** | **PASS** |

---

## 4. SPI Register Map

The on-chip SPI slave operates in SPI Mode 0 ($CPOL=0, CPHA=0$) and supports shift clocks up to $50\,\text{MHz}$ asynchronously to the PLL reference clock:

| Address | Register Name | Bits | Access | Default | Description |
|:---:|:---|:---:|:---:|:---:|:---|
| `0x00` | `REG_OTW_NOM` | `[15:0]` | R/W | `0x0D7F` | Nominal DCO tuning word ($OTW$) |
| `0x01` | `REG_DIV_CTRL` | `[7:0]` | R/W | `0x32` ($50$) | Integer feedback division ratio ($N = 50..200$) |
| `0x02` | `REG_KP_KI` | `[9:0]` | R/W | `0x081` | Loop filter gains: $K_p [9:4]$, $K_i [3:0]$ |
| `0x03` | `REG_STATUS` | `[15:0]` | RO | - | Hardware status: `locked` [0], `gear` [1], live error [15:4] |

---

## 5. License
Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
