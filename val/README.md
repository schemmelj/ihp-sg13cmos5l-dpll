# Validation Data

This directory contains sign-off verification reports and multi-corner simulation artifacts:

- `drc/`:
  - `drc_summary.rpt`: Foundry DRC sign-off report using IHP `sg13g2_maximal.lydrc` (0 errors).
  - `density_summary.rpt`: Global and moving-window layer density verification report (100% pass across all 7 layers).
- `lvs/`:
  - `lvs_summary.rpt`: Transistor-level LVS sign-off report using IHP `sg13g2.lvs` (matched, 83,952 devices, 42,205 nets, 0 differences, pure bondpad comparison).
- `sim/`:
  - `testchip_sim_results.json`: Summary scorecard of multi-corner dynamic simulations.
  - `sim_typ.log`, `sim_fast.log`, `sim_slow.log`: Post-layout back-annotated simulation logs across Typical, Fast, and Slow PVT corners.
