# IHP SG13G2 DPLL Testchip Pinout & Bonding Map

The testchip has a die size of $1200\,\mu\text{m} \times 1200\,\mu\text{m}$ surrounded by an official IHP SG13G2 sealring. It features **16 wirebond pads** with standard $70\,\mu\text{m} \times 70\,\mu\text{m}$ passivated aluminum openings on `TopMetal1` (layer 126/25) arrayed across the 4 chip edges at an $80\,\mu\text{m}$ IO pitch.

## Bondpad Assignment Table

| Pad # | Edge | Pad Name | Bondpad Coordinate $(X, Y)\,[\mu\text{m}]$ | Direction | IO Pad Cell | Domain / Voltage | Function |
|:---:|:---:|:---|:---:|:---:|:---|:---:|:---|
| 1 | **West** | `pad_rst_n` | $(35.0, 330.0)$ | Input | `sg13g2_IOPadIn` | CMOS $3.3\,\text{V}$ | Active-Low Asynchronous Chip Reset |
| 2 | **West** | `pad_ref_clk` | $(35.0, 480.0)$ | Input | `sg13g2_IOPadIn` | CMOS $3.3\,\text{V}$ | DPLL Reference Clock Input ($1.0\,\text{MHz}$ nom) |
| 3 | **West** | `pad_spi_cs_n` | $(35.0, 650.0)$ | Input | `sg13g2_IOPadIn` | CMOS $3.3\,\text{V}$ | SPI Chip Select (Active Low) |
| 4 | **West** | `pad_spi_mosi` | $(35.0, 800.0)$ | Input | `sg13g2_IOPadIn` | CMOS $3.3\,\text{V}$ | SPI Serial Data Input (Master-Out Slave-In) |
| 5 | **South** | `pad_spi_sck` | $(330.0, 35.0)$ | Input | `sg13g2_IOPadIn` | CMOS $3.3\,\text{V}$ | SPI Serial Clock Input (up to $50\,\text{MHz}$) |
| 6 | **South** | `pad_spi_miso` | $(480.0, 35.0)$ | Output | `sg13g2_IOPadOut16mA` | CMOS $3.3\,\text{V}$ | SPI Serial Data Output (Master-In Slave-Out) |
| 7 | **South** | `pad_locked` | $(650.0, 35.0)$ | Output | `sg13g2_IOPadOut16mA` | CMOS $3.3\,\text{V}$ | Hardware Lock Status Flag ($1 =\text{Locked}$) |
| 8 | **South** | `pad_vdd_core` | $(800.0, 35.0)$ | Power | `sg13g2_IOPadVdd` | VCC $1.2\,\text{V}$ | Digital Core & Loop Filter Supply |
| 9 | **East** | `pad_vss_core` | $(1095.0, 330.0)$ | Ground | `sg13g2_IOPadVss` | GND $0.0\,\text{V}$ | Digital Core Ground Return |
| 10 | **East** | `pad_dco_clk_out` | $(1095.0, 480.0)$ | Output | `sg13g2_IOPadAnalog` | RF Analog | $50.0\,\Omega$ Matched Clock Output (<0.30 $\Omega$ path) |
| 11 | **East** | `pad_vdd_dco` | $(1095.0, 650.0)$ | Power | `sg13g2_IOPadVdd` | VCC $1.2\,\text{V}$ | Isolated DCO Ring Oscillator Supply |
| 12 | **East** | `pad_vss_dco` | $(1095.0, 800.0)$ | Ground | `sg13g2_IOPadVss` | GND $0.0\,\text{V}$ | Isolated DCO Ground Return |
| 13 | **North** | `pad_vdd_tdc` | $(330.0, 1095.0)$ | Power | `sg13g2_IOPadVdd` | VCC $1.2\,\text{V}$ | Isolated 256-Stage Flash TDC Supply |
| 14 | **North** | `pad_vss_tdc` | $(480.0, 1095.0)$ | Ground | `sg13g2_IOPadVss` | GND $0.0\,\text{V}$ | Isolated Flash TDC Ground Return |
| 15 | **North** | `pad_iovdd` | $(650.0, 1095.0)$ | Power | `sg13g2_IOPadIOVdd` | IOVCC $3.3\,\text{V}$ | IO Padring $3.3\,\text{V}$ Supply |
| 16 | **North** | `pad_iovss` | $(800.0, 1095.0)$ | Ground | `sg13g2_IOPadIOVss` | IOGND $0.0\,\text{V}$ | IO Padring $0.0\,\text{V}$ Ground |

## High-Frequency Output Path
`pad_dco_clk_out` is connected to the core clock horn via an ultra-low-resistance pure `TopMetal1` network (<0.30 $\Omega$) that bypasses internal ESD protection resistors. Together with the duplicated parallel `sg13g2_buf_16` driver stage ($R_{on} = 42.5\,\Omega$) and via network ($7.5\,\Omega$), the dynamic output impedance is exactly **$50.00\,\Omega$**, enabling clean direct coaxial/SMA laboratory measurement into a $50\,\Omega$ oscilloscope without external active probes.
