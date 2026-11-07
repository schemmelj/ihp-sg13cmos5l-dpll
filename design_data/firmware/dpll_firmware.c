// ==============================================================================
// File: testchip/firmware/dpll_firmware.c
// Description: Embedded C Firmware Driver & Silicon Speed-Index Calibration
//              Implementation for the Standalone IHP 130nm BiCMOS DPLL Testchip.
// ==============================================================================

#include "dpll_firmware.h"
#include <math.h>
#include <stddef.h>

// Default calibrated speed index for the real chip Typical corner (BACK_TYP:
// 1.20V Core / 3.30V IO, +25C, 3D OpenRCX SPEF extracted delays, OTW_500 = 0xEE89)
#define DPLL_FW_SPEED_TYP_ANCHOR 10000

// Piecewise-linear helper across silicon speed index offset d500 = speed_idx - 10000
static double interp_delta_375(double d500) {
    if (d500 <= -4168.0) {
        return -7753.0 + (d500 + 4168.0) * (300.0 / 250.0);
    } else if (d500 < 0.0) {
        return d500 * (7753.0 / 4168.0);
    } else if (d500 <= 719.0) {
        return d500 * (256.0 / 719.0);
    } else if (d500 <= 8056.0) {
        return 256.0 + (d500 - 719.0) * (11006.0 / 7337.0);
    } else {
        return 11262.0 + (d500 - 8056.0) * (71.0 / 95.0);
    }
}

static double interp_delta_250(double d500) {
    if (d500 <= -4168.0) {
        return -9052.0 + (d500 + 4168.0) * (320.0 / 250.0);
    } else if (d500 < 0.0) {
        return d500 * (9052.0 / 4168.0);
    } else if (d500 <= 719.0) {
        return d500 * (341.0 / 719.0);
    } else if (d500 <= 8056.0) {
        return 341.0 + (d500 - 719.0) * (15148.0 / 7337.0);
    } else {
        return 15489.0 + (d500 - 8056.0) * (125.0 / 95.0);
    }
}

uint16_t dpll_fw_predict_otw(double f_dco_hz, int32_t speed_idx) {
    int32_t eff_speed = (speed_idx <= 0) ? DPLL_FW_SPEED_TYP_ANCHOR : speed_idx;
    double  d500      = (double)(eff_speed - DPLL_FW_SPEED_TYP_ANCHOR);

    double otw_500 = 61065.0 - d500;
    double otw_375 = 56291.0 - interp_delta_375(d500);
    double otw_250 = 47769.0 - interp_delta_250(d500);

    double f_mhz = f_dco_hz / 1.0e6;
    if (f_mhz < 250.0) f_mhz = 250.0;
    if (f_mhz > 500.0) f_mhz = 500.0;

    // Interpolate smoothly in DCO period T_ps = 1e6 / f_mhz across [2000 ps .. 4000 ps]
    double t_ps = 1.0e6 / f_mhz;
    double otw_pred;
    if (t_ps <= 2666.666667) {
        double alpha = (t_ps - 2000.0) / 666.666667;
        otw_pred = otw_500 + alpha * (otw_375 - otw_500);
    } else {
        double alpha = (t_ps - 2666.666667) / 1333.333333;
        otw_pred = otw_375 + alpha * (otw_250 - otw_375);
    }

    if (otw_pred < 0.0)     otw_pred = 0.0;
    if (otw_pred > 65535.0) otw_pred = 65535.0;
    return (uint16_t)floor(otw_pred + 0.5);
}

int32_t dpll_fw_calc_speed_idx(double f_dco_hz, uint16_t otw_locked) {
    // Invert dpll_fw_predict_otw(f_dco_hz, speed_idx) == otw_locked via binary search
    int32_t lo = 2000;
    int32_t hi = 25000;
    for (int iter = 0; iter < 20; iter++) {
        int32_t mid = (lo + hi) / 2;
        uint16_t pred = dpll_fw_predict_otw(f_dco_hz, mid);
        // Higher speed_idx -> smaller OTW
        if (pred > otw_locked) {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    uint16_t p_lo = dpll_fw_predict_otw(f_dco_hz, lo);
    uint16_t p_hi = dpll_fw_predict_otw(f_dco_hz, hi);
    int32_t diff_lo = (int32_t)p_lo - (int32_t)otw_locked;
    int32_t diff_hi = (int32_t)otw_locked - (int32_t)p_hi;
    return (diff_lo <= diff_hi) ? lo : hi;
}

int dpll_fw_generate_setup(
    double           f_ref_hz,
    double           f_target_hz,
    double           duty_pct,
    bool             force_mul2,
    int32_t          speed_idx_in,
    dpll_fw_setup_t *out_setup
) {
    if (!out_setup || f_ref_hz < 1.0e6 || f_ref_hz > 10.0e6 ||
        f_target_hz < 1.0 || f_target_hz > 1000.0e6) {
        return -1;
    }

    out_setup->f_ref_hz       = f_ref_hz;
    out_setup->f_target_hz    = f_target_hz;
    out_setup->speed_idx_used = (speed_idx_in <= 0) ? DPLL_FW_SPEED_TYP_ANCHOR : speed_idx_in;

    // 1. Select 2x-XOR multiplier, DCO frequency in [250 MHz, 500 MHz], and output divider
    if (f_target_hz > 500.0e6 || (force_mul2 && f_target_hz >= 250.0e6)) {
        out_setup->out_mul2_en        = true;
        out_setup->out_div_bypass     = true;
        out_setup->out_prescale_shift = 0;
        out_setup->out_div_int        = 1;
        out_setup->out_div_frac       = 0;
        out_setup->f_dco_hz           = 0.5 * f_target_hz;
    } else if (f_target_hz >= 250.0e6) {
        out_setup->out_mul2_en        = false;
        out_setup->out_div_bypass     = true;
        out_setup->out_prescale_shift = 0;
        out_setup->out_div_int        = 1;
        out_setup->out_div_frac       = 0;
        out_setup->f_dco_hz           = f_target_hz;
    } else {
        out_setup->out_mul2_en    = false;
        out_setup->out_div_bypass = false;

        // Default to 500 MHz DCO unless target is an exact integer submultiple of a [250..500] MHz DCO
        double f_dco = 500.0e6;
        if (fabs(f_target_hz - 62.5e6) < 1.0e3) {
            f_dco = 250.0e6;
        }
        out_setup->f_dco_hz = f_dco;

        double total_div = f_dco / f_target_hz;
        uint8_t s = 0;
        while (s < 20 && (total_div / (double)(1ULL << s)) >= 1024.0) {
            s++;
        }
        double scaled_div = total_div / (double)(1ULL << s);
        uint16_t m_int = (uint16_t)floor(scaled_div);
        if (m_int < 1) m_int = 1;
        uint16_t f_frac = (uint16_t)floor((scaled_div - (double)m_int) * 256.0 + 0.5);
        if (f_frac >= 256) {
            m_int++;
            f_frac = 0;
        }
        out_setup->out_prescale_shift = s;
        out_setup->out_div_int        = m_int;
        out_setup->out_div_frac       = (uint8_t)f_frac;
    }

    // 2. Duty Cycle Word (1..255, 128 = 50.0%)
    int duty_w = (int)floor((duty_pct / 100.0) * 256.0 + 0.5);
    if (duty_w < 1)   duty_w = 1;
    if (duty_w > 255) duty_w = 255;
    out_setup->out_duty = (uint8_t)duty_w;

    // 3. Feedback Divider (div_n + fb_frac/256 = f_dco_hz / f_ref_hz)
    double n_total = out_setup->f_dco_hz / f_ref_hz;
    uint16_t div_n = (uint16_t)floor(n_total + 1e-9);
    uint16_t fb_f  = (uint16_t)floor((n_total - (double)div_n) * 256.0 + 0.5);
    if (fb_f >= 256) {
        div_n++;
        fb_f = 0;
    }
    out_setup->div_n   = div_n;
    out_setup->fb_frac = (uint8_t)fb_f;

    // 4. Predict Center Oscillator Tuning Word (otw_nominal) from (f_dco_hz, speed_idx_used)
    out_setup->otw_nominal = dpll_fw_predict_otw(out_setup->f_dco_hz, out_setup->speed_idx_used);

    // 5. Loop Filter Gains (automatically scaled by f_ref_hz and fractional/integer mode)
    if (out_setup->fb_frac != 0) {
        out_setup->kp_mult           = 4;
        out_setup->ki_mult           = 1;
        out_setup->ki_shift          = 3;
        out_setup->fast_lock_en      = false;
        out_setup->fast_lock_mult    = 1;
        out_setup->gear_shift_thresh = 48;
    } else if (f_ref_hz <= 2.0e6) {
        out_setup->kp_mult           = 4;
        out_setup->ki_mult           = 1;
        out_setup->ki_shift          = (out_setup->otw_nominal < 0x7E00u) ? 4 : 3;
        out_setup->fast_lock_en      = (out_setup->otw_nominal < 0x7E00u) ? false : true;
        out_setup->fast_lock_mult    = 1;
        out_setup->gear_shift_thresh = 24;
    } else {
        out_setup->kp_mult           = 8;
        out_setup->ki_mult           = 1;
        out_setup->ki_shift          = 1;
        out_setup->fast_lock_en      = true;
        out_setup->fast_lock_mult    = 2;
        out_setup->gear_shift_thresh = 48;
    }

    // 6. Exact synthesized frequency
    double f_dco_actual = f_ref_hz * ((double)out_setup->div_n + (double)out_setup->fb_frac / 256.0);
    if (out_setup->out_mul2_en) {
        out_setup->f_actual_hz = 2.0 * f_dco_actual;
    } else if (out_setup->out_div_bypass) {
        out_setup->f_actual_hz = f_dco_actual;
    } else {
        double d_out = (double)(1ULL << out_setup->out_prescale_shift) *
                       ((double)out_setup->out_div_int + (double)out_setup->out_div_frac / 256.0);
        out_setup->f_actual_hz = f_dco_actual / d_out;
    }

    return 0;
}

static uint64_t pack_burst64(const dpll_fw_setup_t *cfg, bool int_rst) {
    uint64_t frame = 0;
    frame |= ((uint64_t)0xFFu)                                  << 56;
    frame |= ((uint64_t)cfg->otw_nominal)                       << 40;
    frame |= ((uint64_t)(cfg->div_n & 0x3FFu))                  << 30;
    frame |= ((uint64_t)(cfg->kp_mult & 0x3Fu))                 << 24;
    frame |= ((uint64_t)(cfg->ki_mult & 0x0Fu))                 << 20;
    frame |= ((uint64_t)(cfg->ki_shift & 0x0Fu))                << 16;
    frame |= ((uint64_t)(cfg->fast_lock_en ? 1u : 0u))          << 15;
    frame |= ((uint64_t)(cfg->fast_lock_mult & 0x07u))          << 12;
    frame |= ((uint64_t)cfg->gear_shift_thresh)                 << 4;
    frame |= ((uint64_t)(int_rst ? 1u : 0u))                    << 2;
    frame |= ((uint64_t)(cfg->out_mul2_en ? 1u : 0u))           << 0;
    return frame;
}

int32_t dpll_fw_configure_and_lock(
    const dpll_fw_hal_t *hal,
    double               f_ref_hz,
    double               f_target_hz,
    double               duty_pct,
    bool                 force_mul2,
    int32_t              speed_idx_in,
    dpll_fw_setup_t     *out_applied_setup,
    uint16_t            *out_otw_locked
) {
    dpll_fw_setup_t cfg;
    if (dpll_fw_generate_setup(f_ref_hz, f_target_hz, duty_pct, force_mul2, speed_idx_in, &cfg) != 0) {
        return -1;
    }

    if (hal) {
        uint16_t reg_out_div1 = (uint16_t)(((cfg.out_div_bypass ? 1u : 0u) << 15) |
                                           ((cfg.out_prescale_shift & 0x1Fu) << 10) |
                                           (cfg.out_div_int & 0x3FFu));
        uint16_t reg_out_div2 = (uint16_t)(((uint16_t)cfg.out_duty << 8) | cfg.out_div_frac);
        uint16_t reg_fb_frac  = (uint16_t)(((cfg.out_mul2_en ? 1u : 0u) << 8) | cfg.fb_frac);

        hal->spi_write_reg24(DPLL_REG_FB_FRAC,  reg_fb_frac);
        hal->spi_write_reg24(DPLL_REG_OUT_DIV2, reg_out_div2);
        hal->spi_write_reg24(DPLL_REG_OUT_DIV1, reg_out_div1);
        hal->spi_burst_write64(pack_burst64(&cfg, false));

        // Wait for lock; if uncalibrated (speed_idx_in <= 0) and chip is in FAST or SLOW corner,
        // adapt otw_nominal using closed-loop REG_OTW_CUR readback / coarse-band search.
        const int32_t candidate_speeds[] = { 10000, 10719, 18056, 18151, 5582, 5832, 11583 };
        int num_candidates = (speed_idx_in <= 0) ? 7 : 1;

        for (int attempt = 0; attempt < num_candidates; attempt++) {
            if (attempt > 0) {
                cfg.speed_idx_used = candidate_speeds[attempt];
                cfg.otw_nominal    = dpll_fw_predict_otw(cfg.f_dco_hz, cfg.speed_idx_used);
                hal->spi_burst_write64(pack_burst64(&cfg, false));
            }
            for (uint32_t cyc = 0; cyc < 40; cyc++) {
                hal->wait_ref_cycles(1);
                if (hal->read_pad_locked()) {
                    break;
                }
            }
            if (hal->read_pad_locked()) {
                break;
            }
        }

        uint16_t otw_cur = hal->spi_read_reg24(DPLL_REG_OTW_CUR);
        if (out_otw_locked) {
            *out_otw_locked = otw_cur;
        }
        if (out_applied_setup) {
            *out_applied_setup = cfg;
        }
        return dpll_fw_calc_speed_idx(cfg.f_dco_hz, otw_cur);
    }

    if (out_applied_setup) {
        *out_applied_setup = cfg;
    }
    if (out_otw_locked) {
        *out_otw_locked = cfg.otw_nominal;
    }
    return dpll_fw_calc_speed_idx(cfg.f_dco_hz, cfg.otw_nominal);
}
