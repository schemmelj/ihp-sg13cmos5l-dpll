# Validation Data

This directory contains sign-off verification reports and 6-corner simulation artifacts:

- `drc/`: Foundry DRC sign-off report (`drc_summary.rpt`, 0 errors) and layer density report (`density_summary.rpt`, 7/7 global + 5/5 window pass).
- `lvs/`: Transistor-level LVS sign-off report using IHP `sg13cmos5l.lvs` (104,386 devices, 52,492 nets, 0 differences).
- `sim/`: Multi-corner back-annotated post-layout (`TYP`, `FAST`, `SLOW`) and pre-layout (`SYNTH_TYP`, `SYNTH_FAST`, `SYNTH_SLOW`) simulation logs and JSON summary (`15/15` checks passed, `0` glitches, firmware speed calibration verified).
