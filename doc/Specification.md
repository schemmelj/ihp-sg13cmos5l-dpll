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
