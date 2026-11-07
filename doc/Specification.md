# Specification: IHP SG13CMOS5L All-Digital Phase-Locked Loop (ADPLL) Testchip

## 1. Operating Parameters & Electrical Targets

| Parameter | Specification | Unit | Verification Method |
|:---|:---:|:---:|:---|
| **Process Technology** | IHP 130 nm CMOS (SG13CMOS5L) | - | KLayout DRC / LVS |
| **Metal Stack** | 5 Metal Layers (M1, M2, M3, M4, TM1) | - | Stack check (Via4, M5, TopVia2, TM2 forbidden) |
| **Die Area** | $1200 \times 1200$ ($1.440$) | $\mu\text{m}^2$ ($\text{mm}^2$) | Full layout measurement |
| **Core Area** | $544.32 \times 544.32$ ($0.2963$) | $\mu\text{m}^2$ ($\text{mm}^2$) | Core bounding box (`[332.64, 332.64]` to `[876.96, 876.96]`) |
| **Synthesized / Post-Route Cells** | $11,239$ / $12,117$ | cells | Yosys synthesis / OpenROAD post-route DEF |
| **Input Reference Frequency ($f_{\text{ref}}$)** | $1.0 - 10.0$ ($1.0$ nom) | $\text{MHz}$ | Multi-corner SDF simulation & STA |
| **Internal DCO Tuning Range ($f_{\text{dco}}$)** | $250.0 - 500.0$ (1 Octave) | $\text{MHz}$ | Guaranteed overlap across SLOW, TYP, FAST corners |
| **DCO Corner Envelope (Post-Layout)** | $226.2 - 531.9$ (SLOW) / $324.7 - 990.1$ (TYP) / $438.6 - 1724.1$ (FAST) | $\text{MHz}$ | Back-annotated SPEF + SDF characterization |
| **Output Frequency Range (`pad_dco_clk_out`)** | $1\,\text{Hz} - 500\,\text{MHz}$ (Div) / $500\,\text{MHz} - 1.0\,\text{GHz}$ ($2\times$ XOR) | - | Fractional-N output divider + $2\times$ XOR multiplier |
| **Fractional-N Frequency Resolution** | $\le 1\%$ step ($1\,\text{Hz} - 500\,\text{MHz}$) | - | 24-bit integer + 8-bit $\Delta\Sigma$ output divider |
| **Programmable Duty Cycle** | $1\% - 99\%$ ($< 100\,\text{MHz}$), $50\%$ ($\ge 100\,\text{MHz}$) | $\%$ | High-time pulse comparator (`REG_OUT_DUTY`) |
| **TDC Quantization Step ($\tau_{\text{inv}}$)** | $39.5$ (TYP) / $54.5$ (SLOW) / $28.5$ (FAST) | $\text{ps}$ | 256-stage tapped delay line |
| **Firmware Speed-Index Calibration** | 1-Read `REG_OTW_CUR (0x08)` $\rightarrow$ `speed_idx` ($5582 - 18151$) | - | 0 LSB OTW prediction error across all 6 corners |
| **Core Power Rails** | $1.20 \pm 10\%$ | $\text{V}$ | 3 isolated domains (`VDD_CORE`, `VDD_DCO`, `VDD_TDC`) |
| **IO Padring Voltage** | $3.30 \pm 10\%$ | $\text{V}$ | `IOVDD` / `IOVSS` rails |
| **Output Impedance (pad to supply)** | $50.00 \pm 2.0$ | $\Omega$ | Duplicated $16\times$ buffer horn (`sg13g2_buf_16`) |
| **Dynamic IR-Drop (Clock Horn)** | $< 5.0$ ($45.4\,\text{mV}$) | $\%$ | 5-point transition extraction |

## 2. Physical Verification & Sign-Off Criteria

| Verification Check | Target / Rule | Result | Status |
|:---|:---|:---:|:---:|
| **Foundry DRC** | Official IHP `sg13cmos5l_drc.lydrc` / `sg13g2_maximal.lydrc` ($densityRules = true) | **0 Errors** | **PASS** |
| **Transistor-Level LVS** | KLayout `sg13cmos5l.lvs` (104,386 devices, 52,492 nets) | **MATCH (0 Diff)** | **PASS** |
| **Formal Logic Equivalence (LEC)** | Yosys 3-stage SAT + Temporal Induction (`dpll_testchip_lec.log`) | **9,418 / 9,418 `$equiv` Proven** | **PASS** |
| **Pure Bondpad Reference** | Terminal matching exclusively on 16 TopMetal1 wirebond pads | **Verified** | **PASS** |
| **Process Antenna Ratio** | Max antenna ratio < 40,308 : 1 | **407.72 : 1 max** | **PASS** |
| **Clock Output Match** | $50.0\,\Omega \pm 2.0\,\Omega$ impedance from pad to supply | **$50.00\,\Omega$ exact** | **PASS** |
| **Dynamic IR-Drop** | Output clock buffer peak dynamic drop < 5.0% | **3.78% ($45.4\,\text{mV}$)** | **PASS** |
| **6-Corner Gate-Level SDF Sim** | Post-layout (`TYP/FAST/SLOW`) + Pre-layout (`SYNTH_TYP/FAST/SLOW`) | **15/15 Checks Pass, 0 Glitches** | **PASS** |

## 3. Density & Dummy Metal Fill Specification

All density checks strictly follow the IHP SG13G2/SG13CMOS5L Maximal DRC rule deck (`sg13g2_maximal.lydrc`).

### 3.1 Global Layer Density
- **Die Area:** $1200.0 \times 1200.0\,\mu\text{m}^2 = 1.440\,\text{mm}^2$

| Layer | Drawn Area | Fill Area (dt 22) | Total Area | Density | IHP Spec | Status |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| **Activ** | $519.6\,\text{k}\mu\text{m}^2$ | $0.0\,\mu\text{m}^2$ | $519.6\,\text{k}\mu\text{m}^2$ | **36.08%** | 35.0% - 55.0% | **PASS** (`AFil.g`) |
| **GatPoly** | $80.0\,\text{k}\mu\text{m}^2$ | $192.0\,\text{k}\mu\text{m}^2$ | $272.0\,\text{k}\mu\text{m}^2$ | **18.89%** | $\ge 15.0\%$ | **PASS** (`GFil.g`) |
| **Metal1** | $511.9\,\text{k}\mu\text{m}^2$ | $0.0\,\mu\text{m}^2$ | $511.9\,\text{k}\mu\text{m}^2$ | **35.55%** | 35.0% - 60.0% | **PASS** (`M1.j`) |
| **Metal2** | $134.2\,\text{k}\mu\text{m}^2$ | $440.5\,\text{k}\mu\text{m}^2$ | $574.7\,\text{k}\mu\text{m}^2$ | **39.91%** | 35.0% - 60.0% | **PASS** (`M2.j`) |
| **Metal3** | $535.2\,\text{k}\mu\text{m}^2$ | $0.0\,\mu\text{m}^2$ | $535.2\,\text{k}\mu\text{m}^2$ | **37.17%** | 35.0% - 60.0% | **PASS** (`M3.j`) |
| **Metal4** | $496.0\,\text{k}\mu\text{m}^2$ | $316.2\,\text{k}\mu\text{m}^2$ | $812.2\,\text{k}\mu\text{m}^2$ | **56.40%** | 35.0% - 60.0% | **PASS** (`M4.j`) |
| **TopMetal1** | $497.0\,\text{k}\mu\text{m}^2$ | $0.0\,\mu\text{m}^2$ | $497.0\,\text{k}\mu\text{m}^2$ | **34.51%** | 25.0% - 70.0% | **PASS** (`TM1.c`) |

### 3.2 Local Moving-Window Density ($800 \times 800\,\mu\text{m}^2$, step = $400\,\mu\text{m}$)
- Per IHP DRC deck (`tile_size(800.0.um), tile_step(400.0.um), tiles_stay_inside: true`):
  - **Activ:** [35.55%, 37.22%] (Spec: 25.0% - 65.0%) $\rightarrow$ **PASS**
  - **Metal1:** [34.82%, 37.11%] (Spec: 25.0% - 75.0%) $\rightarrow$ **PASS**
  - **Metal2:** [34.39%, 35.23%] (Spec: 25.0% - 75.0%) $\rightarrow$ **PASS**
  - **Metal3:** [33.82%, 34.09%] (Spec: 25.0% - 75.0%) $\rightarrow$ **PASS**
  - **Metal4:** [52.83%, 53.35%] (Spec: 25.0% - 75.0%) $\rightarrow$ **PASS**

### 3.3 Metal Fill Strategy
- GatPoly dummy fill (5/22) is inserted to meet the 15% min global requirement.
- Metal2 (10/22) and Metal4 (50/22) dummy fill are inserted to balance global and local window densities comfortably within foundry limits across all tiles.
- All dummy geometries strictly follow `MFil.c` ($\ge 0.42\,\mu\text{m}$ clearance) and `MFil.a2` ($\le 5.0\,\mu\text{m}$ width).
