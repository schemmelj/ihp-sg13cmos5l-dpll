# Specification: IHP SG13CMOS5L All-Digital Phase-Locked Loop (ADPLL) Testchip

## 1. Operating Parameters & Electrical Targets

| Parameter | Specification | Unit | Verification Method |
|:---|:---:|:---:|:---|
| **Process Technology** | IHP 130 nm CMOS (SG13CMOS5L) | - | KLayout DRC / LVS |
| **Metal Stack** | 5 Metal Layers (M1, M2, M3, M4, TM1) | - | Stack check (M5, TM2 forbidden) |
| **Die Area** | $1200 \times 1200$ | $\mu\text{m}^2$ | Full layout measurement |
| **Core Area** | $802.4 \times 802.4$ | $\mu\text{m}^2$ | Core bounding box |
| **Nominal Input Reference Frequency** | $1.0$ | $\text{MHz}$ | Post-layout simulation |
| **Max Valid Input Reference Frequency** | $10.20$ (TYP) / $7.04$ (SLOW) / $14.50$ (FAST) | $\text{MHz}$ | Static timing analysis & PFD |
| **Output Frequency Tuning Range** | $50.0 - 200.0$ | $\text{MHz}$ | Operational design specification |
| **DCO Max Free-Running Frequency** | $223.2$ (TYP) / $164.5$ (SLOW) / $265.2$ (FAST) | $\text{MHz}$ | 15-stage coarse saturation |
| **TDC Quantization Step ($\tau_{\text{inv}}$)** | $39.5$ (TYP) / $54.5$ (SLOW) / $28.5$ (FAST) | $\text{ps}$ | 256-stage tapped delay line |
| **RMS Cycle-to-Cycle Jitter** | $18.0$ (TYP) / $28.8$ (SLOW) / $12.8$ (FAST) | $\text{ps}$ | Back-annotated SPEF simulation |
| **Acquisition Lock Time** | $< 18.0$ | $\mu\text{s}$ | Fast adaptive gear-shifting |
| **Core Power Rails** | $1.20 \pm 10\%$ | $\text{V}$ | 3 isolated domains |
| **IO Padring Voltage** | $3.30 \pm 10\%$ | $\text{V}$ | `IOVDD` / `IOVSS` rails |
| **Output Impedance (pad to supply)** | $50.00 \pm 2.0$ | $\Omega$ | Duplicated $16\times$ buffer horn |
| **Peak Clock Output Slew Rate** | $< 300$ | $\text{ps}$ | $50\,\Omega$ coaxial terminated load |
| **Dynamic IR-Drop (Clock Horn)** | $< 5.0$ ($45.4\,\text{mV}$) | $\%$ | 5-point transition extraction |

## 2. Physical Verification & Sign-Off Criteria

| Verification Check | Target / Rule | Result | Status |
|:---|:---|:---:|:---:|
| **Foundry DRC** | Official IHP `sg13g2_maximal.lydrc` ($densityRules = true) | **0 Errors** | **PASS** |
| **Transistor-Level LVS** | KLayout `sg13g2.lvs` (83,952 devices, 42,205 nets) | **MATCH (0 Diff)** | **PASS** |
| **Pure Bondpad Reference** | Terminal matching exclusively on 16 TopMetal1 wirebond pads | **Verified** | **PASS** |
| **Process Antenna Ratio** | Max antenna ratio < 40,308 : 1 | **407.72 : 1 max** | **PASS** |
| **Clock Output Match** | $50.0\,\Omega \pm 2.0\,\Omega$ impedance from pad to supply | **$50.00\,\Omega$ exact** | **PASS** |
| **Dynamic IR-Drop** | Output clock buffer peak dynamic drop < 5.0% | **3.78% ($45.4\,\text{mV}$)** | **PASS** |
| **Precheck Filler Cells** | Standard decap/fillers (`sg13g2_decap_*`, `sg13g2_fill_*`) | **100% matched** | **PASS** |

## 3. Density & Dummy Metal Fill Specification

All density checks strictly follow the IHP SG13G2 Maximal DRC rule deck (`sg13g2_maximal.lydrc`).

### 3.1 Global Layer Density
- **Die Area:** $1200.0 \times 1200.0\,\mu\text{m}^2 = 1.440\,\text{mm}^2$

| Layer | Drawn Area | Fill Area (dt 22) | Total Area | Density | IHP Spec | Status |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| **Activ** | $521.3\,\text{k}\mu\text{m}^2$ | $0.0\,\mu\text{m}^2$ | $521.3\,\text{k}\mu\text{m}^2$ | **36.20%** | 35.0% - 55.0% | **PASS** (`AFil.g`) |
| **GatPoly** | $89.0\,\text{k}\mu\text{m}^2$ | $272.2\,\text{k}\mu\text{m}^2$ | $361.2\,\text{k}\mu\text{m}^2$ | **25.08%** | $\ge 15.0\%$ | **PASS** (`GFil.g`) |
| **Metal1** | $515.2\,\text{k}\mu\text{m}^2$ | $0.0\,\mu\text{m}^2$ | $515.2\,\text{k}\mu\text{m}^2$ | **35.78%** | 35.0% - 60.0% | **PASS** (`M1.j`) |
| **Metal2** | $195.2\,\text{k}\mu\text{m}^2$ | $356.8\,\text{k}\mu\text{m}^2$ | $552.0\,\text{k}\mu\text{m}^2$ | **38.33%** | 35.0% - 60.0% | **PASS** (`M2.j`) |
| **Metal3** | $598.3\,\text{k}\mu\text{m}^2$ | $0.0\,\mu\text{m}^2$ | $598.3\,\text{k}\mu\text{m}^2$ | **41.55%** | 35.0% - 60.0% | **PASS** (`M3.j`) |
| **Metal4** | $561.3\,\text{k}\mu\text{m}^2$ | $0.0\,\mu\text{m}^2$ | $561.3\,\text{k}\mu\text{m}^2$ | **38.98%** | 35.0% - 60.0% | **PASS** (`M4.j`) |
| **TopMetal1** | $602.6\,\text{k}\mu\text{m}^2$ | $0.0\,\mu\text{m}^2$ | $602.6\,\text{k}\mu\text{m}^2$ | **41.85%** | 25.0% - 70.0% | **PASS** (`TM1.c`) |

### 3.2 Local Moving-Window Density ($800 \times 800\,\mu\text{m}^2$, step = $400\,\mu\text{m}$)
- Per IHP DRC deck (`tile_size(800.0.um), tile_step(400.0.um), tiles_stay_inside: true`):
  - **Activ:** [35.74%, 37.32%] (Spec: 25.0% - 65.0%) $\rightarrow$ **PASS**
  - **Metal1:** [35.11%, 37.44%] (Spec: 25.0% - 75.0%) $\rightarrow$ **PASS**
  - **Metal2:** [32.28%, 34.36%] (Spec: 25.0% - 75.0%) $\rightarrow$ **PASS**
  - **Metal3:** [37.18%, 37.44%] (Spec: 25.0% - 75.0%) $\rightarrow$ **PASS**
  - **Metal4:** [32.97%, 33.08%] (Spec: 25.0% - 75.0%) $\rightarrow$ **PASS**

### 3.3 Metal Fill Strategy
- GatPoly dummy fill (5/22) is inserted to meet the 15% min global requirement.
- Metal2 dummy fill (10/22) is inserted to bring local window density comfortably above 25% across all tiles.
- Metal1, Metal3, Metal4, and TopMetal1 natively satisfy all global (35-60%) and local window (25-75%) requirements via dense power distribution meshes and padring routing.
- All dummy geometries strictly follow `MFil.c` ($\ge 0.42\,\mu\text{m}$ clearance) and `MFil.a2` ($\le 5.0\,\mu\text{m}$ width).
