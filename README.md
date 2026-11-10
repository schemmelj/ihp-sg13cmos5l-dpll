# IHP SG13CMOS5L Standalone DPLL Testchip Tapeout Package (`IHP__PLL3540`)

Open-source tapeout repository for the **$1200\,\mu\text{m} \times 1200\,\mu\text{m}$ All-Digital Phase-Locked Loop (ADPLL) Testchip (`PLL3540`)**, fully synthesized and hardened in the **IHP 130nm CMOS SG13CMOS5L (5-Metal Stack)** open-source technology.

Developed in strict accordance with the **IHP Open-Silicon-MPW Specifications** (`gen_structure.py` generator, November-2026 Mixed-Signal IP category conventions).

---

## 1. Key Design Specifications

| Parameter | Value | Unit | Description |
|:---|:---:|:---:|:---|
| **IP Identifier** | `PLL3540` | - | MPW Category: `Mixed-Signal` / Subcategory: `Phase-Locked Loop` |
| **Process Node** | IHP SG13CMOS5L | - | 130 nm CMOS (5 Metal Layers: M1-M4 + TopMetal1 thickness $2.0\,\mu\text{m}$) |
| **Chip Dimensions** | $1200 \times 1200$ | $\mu\text{m}$ | Includes standard perimeter sealring ($1.440\,\text{mm}^2$) |
| **Core Dimensions** | $544.32 \times 544.32$ | $\mu\text{m}$ | Standard-cell core (`[332.64, 332.64]` to `[876.96, 876.96]`, $0.2963\,\text{mm}^2$) |
| **Cell Count** | $11,239$ (synth) / $12,117$ (post-route) | cells | 100% standard cells, zero custom analog primitives |
| **Reference Clock ($f_{\text{ref}}$)** | $1.0 - 10.0$ ($1.0$ nom) | $\text{MHz}$ | Single-ended CMOS reference input |
| **Internal DCO Range ($f_{\text{dco}}$)** | $250.0 - 500.0$ | $\text{MHz}$ | 1-octave Vernier ring DCO across all PVT corners |
| **Output Frequency ($f_{\text{out}}$)** | $1\,\text{Hz} - 500\,\text{MHz}$ / $500\,\text{MHz} - 2.0\,\text{GHz}$ | - | Glitch-free Fractional-N divider + $2\times$/$4\times$ XOR multiplier |
| **Feedback Divider ($N_{\text{eff}}$)** | $N_{\text{int}} \in [25, 500] + F_{\text{fb}}/256$ | - | Coupled integer + 8-bit $\Delta\Sigma$ fractional feedback divider |
| **Quantization Step ($t_{\text{LSB}}$)** | $39.5$ (typ) / $28.5$ (fast) / $54.5$ (slow) | $\text{ps}$ | 256-stage Flash Inverter Delay Line TDC |
| **Speed-Index Calibration** | `REG_OTW_CUR (0x08)` readback | - | 1-lock silicon calibration (`speed_idx`), 0 LSB OTW prediction error |
| **Output Impedance** | $50.00$ | $\Omega$ | Direct coaxial $50\,\Omega$ match at `pad_dco_clk_out` |
| **Core Power Supplies** | 3 independent $1.2\,\text{V}$ rails | $\text{V}$ | `VDD_CORE`, `VDD_DCO`, `VDD_TDC` |
| **IO Padring Supply** | $3.3$ | $\text{V}$ | `IOVDD` / `IOVSS` ESD padring |
| **Total Wirebond Pads** | 16 | pads | $70 \times 70\,\mu\text{m}$ passivated `TopMetal1` openings |

---

## 2. Repository Structure

This repository adheres to the standard IHP Open-Silicon-MPW generated structure (`gen_structure.py`):

```text
├── LICENSE                          # Apache-2.0 open-source license
├── README.md                        # Project overview, pinout, and sign-off scorecard
├── PLL3540-main/                    # Canonical cell structure (all design views)
│   ├── layout/                      # Layout streams (GDS, DEF, LEF)
│   │   ├── klayout/PLL3540.gds      # Complete full-chip GDSII layout (top cell: PLL3540)
│   │   └── def/PLL3540.def          # Placed and routed DEF netlist
│   ├── netlist/                     # CDL & spice netlists
│   │   └── schematic/PLL3540.cdl    # Transistor-level schematic netlist (.SUBCKT PLL3540)
│   ├── verification/                # DRC, density, and LVS sign-off verification reports
│   │   ├── drc/drc_summary.rpt
│   │   ├── drc/density_summary.rpt
│   │   └── lvs/lvs_summary.rpt
│   └── README.md
├── dependencies/                    # Sub-cell modular hierarchy (DCO, TDC, LOOP_FILTER, etc.)
│   ├── DCO/
│   ├── TDC/
│   ├── LOOP_FILTER/
│   ├── FB_DIVIDER/
│   ├── OUT_DIVIDER/
│   └── SPI_SLAVE/
├── measurements/                    # Silicon validation & lab characterization data
│   └── v.1.0.0/
├── doc/                             # Comprehensive documentation & metadata
│   ├── info.json                    # IHP MPW IP metadata (name: PLL3540, unique_id: 3540)
│   ├── Specification.md             # Electrical & physical specification
│   ├── Datasheet.md                 # Feature overview and compliance datasheet
│   ├── TRL-Mixed-Signal-IP.md       # TRL-5 self-assessment quality checklist
│   ├── pinout.md                    # Detailed padring bonding and coordinate mapping
│   ├── testchip_documentation.pdf   # Complete standalone testchip documentation manual
│   └── figures/                     # High-resolution architectural, simulation, and layout figures
├── release/v.1.0.0/                 # Immutable versioned tapeout release package
│   ├── gds/PLL3540.gds.gz           # Gzip-compressed GDSII (top cell: PLL3540, no context info)
│   ├── netlist/PLL3540.cdl          # Top-level schematic CDL (.SUBCKT PLL3540)
│   ├── doc/testchip_documentation.pdf
│   └── ReleaseNote.md               # Version release notes
├── design_data/                     # Legacy source and simulation collateral
├── val/                             # Verification logs and multi-corner sign-off data
└── scripts/                         # Verification runners & structure generators
    ├── run_klayout_verification.py  # Automated KLayout DRC, density, sealring & pin integrity runner
    ├── gen_structure.py             # Official IHP MPW structure generator
    └── ip-categories.json           # IHP category registry
```

---

## 3. Tapeout Sign-Off Scorecard

| Verification Metric | Target / Rule | Result | Status |
|:---|:---|:---:|:---:|
| **Foundry DRC** | Official IHP `sg13cmos5l_drc.lydrc` / `sg13g2_maximal.lydrc` | **0 Errors** | **PASS** |
| **Transistor-Level LVS** | KLayout `sg13cmos5l.lvs` (104,386 devices, 52,492 nets) | **MATCH (0 Diff)** | **PASS** |
| **Global Layer Density** | Activ (36.1%), GatPoly (18.9%), M1-M4 (35.6-56.4%), TM1 (34.5%) | **7/7 Layers Pass** | **PASS** |
| **Moving Window Density** | $800 \times 800\,\mu\text{m}^2$ windows, step $400\,\mu\text{m}$ | **100% Tiles Pass** | **PASS** |
| **Pure Bondpad Reference** | Terminal matching exclusively at 16 TopMetal1 wirebond pads | **Verified** | **PASS** |
| **Logic Equivalence (LEC)**| 3-Stage Formal LEC (Yosys SAT + Temporal Induction) | **9,418 / 9,418 Proven** | **PASS** |
| **Process Antenna Ratio** | Max antenna ratio $< 40,308 : 1$ | **407.72 : 1 max** | **PASS** |
| **Clock Output Match** | $50.0\,\Omega \pm 2\,\Omega$ impedance from pad to supply | **$50.00\,\Omega$ exact** | **PASS** |
| **Dynamic IR-Drop** | Output clock buffer peak dynamic drop $< 5.0\,\%$ | **$3.78\,\%$ ($45.4\,\text{mV}$)** | **PASS** |
| **6-Corner SDF Verification**| Post-layout (`TYP/FAST/SLOW`) + Pre-layout (`SYNTH_TYP/FAST/SLOW`) | **15/15 checks passed** | **PASS** |
| **Runt Pulses / Glitches** | Continuous cycle-by-cycle monitor across all 6 stages | **0 Glitches** | **PASS** |

---

## 4. SPI Register Map

The on-chip SPI slave operates in SPI Mode 0 ($CPOL=0, CPHA=0$) using a 24-bit frame (`[23]=R/W`, `[22:16]=ADDR`, `[15:0]=DATA`) up to $50\,\text{MHz}$ asynchronously to `ref_clk`:

| Address | Register Name | Bits | Access | Default | Description |
|:---:|:---|:---:|:---:|:---:|:---|
| `0x00` | `REG_OTW_NOM` | `[15:0]` | R/W | `0x1E00` | Nominal DCO tuning word ($OTW_{\text{nom}}$, coarse `[11:8]`, fine `[7:0]`) |
| `0x01` | `REG_DIV_CTRL` | `[15:0]` | R/W | `0x015E` | `[8:0]` Integer feedback ratio $N_{\text{int}} \in [25, 500]$ ($350$ default), `[15]` `out_mul2_en` ($2\times$ XOR) |
| `0x02` | `REG_KP_KI` | `[9:0]` | R/W | `0x0081` | Loop filter gains: `kp_shift` `[9:4]`, `ki_shift` `[3:0]` |
| `0x03` | `REG_STATUS` | `[15:0]` | RO | - | Hardware status: `locked` `[0]`, `gear` `[1]`, live phase error `[15:4]` |
| `0x04` | `REG_FB_FRAC` | `[7:0]` | R/W | `0x0000` | 8-bit Fractional-N feedback numerator $F_{\text{fb}} \in [0, 255]$ ($F_{\text{fb}}/256$) |
| `0x05` | `REG_OUT_DIV_HI` | `[15:0]` | R/W | `0x0000` | Output divider integer ratio upper bits `M_int[23:8]` (staged) |
| `0x06` | `REG_OUT_DIV_LO` | `[15:0]` | R/W | `0x0700` | `[15:8]` `M_int[7:0]` ($M_{\text{int}}=7 \rightarrow 50\,\text{MHz}$ default), `[7:0]` `F_out[7:0]` (commits divider) |
| `0x07` | `REG_OUT_DUTY` | `[15:0]` | R/W | `0x0000` | Output high-time cycles (`0` = automatic $50\%$ duty cycle) |
| `0x08` | `REG_OTW_CUR` | `[15:0]` | RO | - | Live converged loop-filter tuning word `otw[15:0]` for 1-lock speed calibration |

---

## 5. License
Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
