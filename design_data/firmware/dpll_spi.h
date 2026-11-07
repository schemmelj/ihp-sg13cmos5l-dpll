/**
 * @file dpll_spi.h
 * @brief C/C++ Driver Header for the IHP 130nm SG13CMOS5L All-Digital PLL (DPLL) Testchip
 *
 * Asynchronous 4-Wire SPI Slave Interface (SPI Mode 0: CPOL = 0, CPHA = 0, MSB-First):
 *   - Operates directly on the external SPI clock (spi_sck), completely independent
 *     of the 1..10 MHz reference clock (ref_clk).
 *   - Supports 24-bit single-register R/W frames, 64-bit core atomic burst writes,
 *     and 96-bit extended full-chip burst writes.
 *   - Programs the 250..500 MHz 1-octave DCO, Fractional-N feedback divider
 *     (div_n = 25..500, fb_frac = 0..255), Fractional-N output divider (1 Hz .. 500 MHz,
 *     <= 1% step granularity), programmable duty cycle (< 100 MHz), and the
 *     2x XOR physical output clock multiplier (500 MHz .. 1.0 GHz).
 *   - Compatible with Arduino SPI (`<SPI.h>`) or custom HAL callbacks.
 */

#ifndef DPLL_SPI_H
#define DPLL_SPI_H

#include <stdint.h>
#include <stdbool.h>

#ifdef ARDUINO
#include <Arduino.h>
#include <SPI.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================== */
/* 1. SPI Register Map & Command Headers                                      */
/* ========================================================================== */

/** 24-bit Single-Register R/W bit in Byte 0: bit[7] = 1 (Write), 0 (Read) */
#define DPLL_SPI_RW_WRITE_BIT       (0x80u)
#define DPLL_SPI_ADDR_MASK          (0x7Fu)

/** 64-bit / 96-bit Atomic Full-Parameter Burst Write Command Header (Byte 0 = 0xFF) */
#define DPLL_CMD_BURST_WRITE        (0xFFu)

/** 7-bit Register Addresses for 24-bit Single-Register Transfers */
#define DPLL_REG_OTW_NOM            (0x00u) /**< [15:0]  Nominal Oscillator Tuning Word (OTW) */
#define DPLL_REG_DIV_CTRL           (0x01u) /**< [13] out_mul2_en, [12] rst_int, [11] frz_int, [10] clr_lock, [9:0] div_n */
#define DPLL_REG_LOOP_GAIN          (0x02u) /**< [13:10] ki_shift, [9:6] ki_mult, [5:0] kp_mult */
#define DPLL_REG_GEAR_CFG           (0x03u) /**< [11] fast_lock_en, [10:8] fast_lock_mult, [7:0] thresh */
#define DPLL_REG_STATUS             (0x04u) /**< [15:11] 0x15 magic, [10] locked, [9:0] div_n (Read-Only) */
#define DPLL_REG_OUT_DIV1           (0x05u) /**< [15] out_div_bypass, [14:10] out_prescale_shift, [9:0] out_div_int */
#define DPLL_REG_OUT_DIV2           (0x06u) /**< [15:8] out_duty (128 = 50%), [7:0] out_div_frac */
#define DPLL_REG_FB_FRAC            (0x07u) /**< [8] out_mul2_en, [7:0] fb_frac (F_fb / 256) */
#define DPLL_REG_OTW_CUR            (0x08u) /**< [15:0] Live closed-loop OTW readback (Read-Only) */

/** Calibrated Silicon Speed Index Constants (0 = uncalibrated / Typical corner default) */
#define DPLL_SPEED_UNCALIBRATED     (0)
#define DPLL_SPEED_TYP_ANCHOR       (10000) /**< Real chip Typical corner (1.20V, 25C, OTW_500 = 0xEE89) */

/* ========================================================================== */
/* 2. Register Bitfields & Power-On Reset (POR) Defaults                      */
/* ========================================================================== */

/* REG_DIV_CTRL (0x01) bit positions and masks */
#define DPLL_DIV_N_MASK             (0x03FFu)
#define DPLL_DIV_CLR_LOCK_BIT       (1u << 10)
#define DPLL_DIV_FRZ_INT_BIT        (1u << 11)
#define DPLL_DIV_RST_INT_BIT        (1u << 12)
#define DPLL_DIV_OUT_MUL2_EN_BIT    (1u << 13)

/* REG_LOOP_GAIN (0x02) bit positions and masks */
#define DPLL_KP_MULT_SHIFT          (0u)
#define DPLL_KP_MULT_MASK           (0x003Fu)
#define DPLL_KI_MULT_SHIFT          (6u)
#define DPLL_KI_MULT_MASK           (0x03C0u)
#define DPLL_KI_SHIFT_SHIFT         (10u)
#define DPLL_KI_SHIFT_MASK          (0x3C00u)

/* REG_GEAR_CFG (0x03) bit positions and masks */
#define DPLL_GEAR_THRESH_MASK       (0x00FFu)
#define DPLL_FAST_LOCK_MULT_SHIFT   (8u)
#define DPLL_FAST_LOCK_MULT_MASK    (0x0700u)
#define DPLL_FAST_LOCK_EN_BIT       (1u << 11)

/* REG_STATUS (0x04) bit positions and masks */
#define DPLL_STATUS_DIV_N_MASK      (0x03FFu)
#define DPLL_STATUS_LOCKED_BIT      (1u << 10)
#define DPLL_STATUS_MAGIC_SHIFT     (11u)
#define DPLL_STATUS_MAGIC_EXPECTED  (0x15u)

/* REG_OUT_DIV1 (0x05) bit positions and masks */
#define DPLL_OUT_DIV_INT_MASK       (0x03FFu)
#define DPLL_OUT_PRESCALE_SHIFT     (10u)
#define DPLL_OUT_PRESCALE_MASK      (0x7C00u)
#define DPLL_OUT_DIV_BYPASS_BIT     (1u << 15)

/* REG_FB_FRAC (0x07) bit positions and masks */
#define DPLL_FB_FRAC_MASK           (0x00FFu)
#define DPLL_FB_FRAC_MUL2_EN_BIT    (1u << 8)

/* Calibrated Power-On Reset Defaults (500.0 MHz DCO, 5.0 MHz ref_clk, 50.0 MHz output) */
#define DPLL_DEFAULT_OTW_250MHZ     (4096u)   /**< 0x1000: 250.0 MHz DCO lower octave bound */
#define DPLL_DEFAULT_OTW_350MHZ     (32768u)  /**< 0x8000: 350.0 MHz DCO mid-octave point */
#define DPLL_DEFAULT_OTW_500MHZ     (59648u)  /**< 0xE900: 500.0 MHz DCO POR nominal */
#define DPLL_DEFAULT_DIV_N          (100u)    /**< N = 100 (500 MHz / 5 MHz ref_clk) */
#define DPLL_DEFAULT_FB_FRAC        (0u)
#define DPLL_DEFAULT_KP_MULT        (8u)
#define DPLL_DEFAULT_KI_MULT        (1u)
#define DPLL_DEFAULT_KI_SHIFT       (1u)
#define DPLL_DEFAULT_FAST_LOCK_EN   (1u)
#define DPLL_DEFAULT_FAST_LOCK_MULT (2u)
#define DPLL_DEFAULT_GEAR_THRESH    (48u)
#define DPLL_DEFAULT_OUT_DIV_INT    (10u)     /**< M_int = 10 -> 500 MHz / 10 = 50.0 MHz POR output */
#define DPLL_DEFAULT_OUT_DUTY_50PCT (128u)    /**< 128 / 256 = 50.0% output duty cycle */

/* ========================================================================== */
/* 3. Configuration Structure & Helper Macros                                 */
/* ========================================================================== */

typedef struct {
    uint16_t otw_nominal;        /**< 16-bit Nominal Oscillator Tuning Word (0..65535) */
    uint16_t div_n;              /**< 10-bit Feedback Divider Integer Ratio N (25..500) */
    uint8_t  fb_frac;            /**< 8-bit Feedback Fractional Numerator F_fb (0..255 -> F_fb/256) */
    uint8_t  kp_mult;            /**< 6-bit Proportional Gain Multiplier (0..63, default 8) */
    uint8_t  ki_mult;            /**< 4-bit Integral Gain Multiplier (0..15, default 1) */
    uint8_t  ki_shift;           /**< 4-bit Integral Right-Shift (0..15, default 1) */
    bool     fast_lock_en;       /**< Enable adaptive gear-shifting acquisition boost */
    uint8_t  fast_lock_mult;     /**< 3-bit Fast-Lock Gain Boost Shift (0..7, default 2 = 4x) */
    uint8_t  gear_shift_thresh;  /**< 8-bit TDC Phase Error Threshold for fine gear (default 48) */
    bool     integrator_freeze;  /**< Hold loop filter integral accumulator constant */
    bool     integrator_rst;     /**< Synchronously zero loop filter integral accumulator */
    bool     clr_lock;           /**< Force lock detector reset (auto-pulsed on frequency commit) */
    bool     out_mul2_en;        /**< Enable 2x XOR physical output clock multiplier (500 MHz .. 1.0 GHz) */
    bool     out_div_bypass;     /**< Bypass output divider (direct 250..500 MHz or 500..1000 MHz w/ mul2) */
    uint8_t  out_prescale_shift; /**< 5-bit Binary Octave Prescaler S (0..20 -> 2^S) */
    uint16_t out_div_int;        /**< 10-bit Output Divider Mantissa M_int (1..1023) */
    uint8_t  out_div_frac;       /**< 8-bit Output Divider Fractional Numerator F_frac (0..255) */
    uint8_t  out_duty;           /**< 8-bit Programmable Output Duty Cycle (1..255, 128 = 50.0%) */
} dpll_config_t;

/** Pack REG_DIV_CTRL (0x01) 16-bit payload */
static inline uint16_t dpll_pack_div_ctrl(uint16_t div_n, bool clr_lock, bool frz_int, bool rst_int, bool out_mul2_en) {
    return (uint16_t)(div_n & DPLL_DIV_N_MASK)
         | (clr_lock    ? DPLL_DIV_CLR_LOCK_BIT    : 0u)
         | (frz_int     ? DPLL_DIV_FRZ_INT_BIT     : 0u)
         | (rst_int     ? DPLL_DIV_RST_INT_BIT     : 0u)
         | (out_mul2_en ? DPLL_DIV_OUT_MUL2_EN_BIT : 0u);
}

/** Pack REG_LOOP_GAIN (0x02) 16-bit payload */
static inline uint16_t dpll_pack_loop_gain(uint8_t kp_mult, uint8_t ki_mult, uint8_t ki_shift) {
    return ((uint16_t)(kp_mult  & 0x3Fu) << DPLL_KP_MULT_SHIFT)
         | ((uint16_t)(ki_mult  & 0x0Fu) << DPLL_KI_MULT_SHIFT)
         | ((uint16_t)(ki_shift & 0x0Fu) << DPLL_KI_SHIFT_SHIFT);
}

/** Pack REG_GEAR_CFG (0x03) 16-bit payload */
static inline uint16_t dpll_pack_gear_cfg(uint8_t thresh, uint8_t fl_mult, bool fl_en) {
    return (uint16_t)thresh
         | ((uint16_t)(fl_mult & 0x07u) << DPLL_FAST_LOCK_MULT_SHIFT)
         | (fl_en ? DPLL_FAST_LOCK_EN_BIT : 0u);
}

/** Pack REG_OUT_DIV1 (0x05) 16-bit payload */
static inline uint16_t dpll_pack_out_div1(bool bypass, uint8_t prescale_s, uint16_t div_int) {
    return (uint16_t)(div_int & DPLL_OUT_DIV_INT_MASK)
         | ((uint16_t)(prescale_s & 0x1Fu) << DPLL_OUT_PRESCALE_SHIFT)
         | (bypass ? DPLL_OUT_DIV_BYPASS_BIT : 0u);
}

/** Pack REG_OUT_DIV2 (0x06) 16-bit payload */
static inline uint16_t dpll_pack_out_div2(uint8_t duty, uint8_t div_frac) {
    return ((uint16_t)duty << 8) | (uint16_t)div_frac;
}

/** Pack REG_FB_FRAC (0x07) 16-bit payload */
static inline uint16_t dpll_pack_fb_frac(uint8_t fb_frac, bool out_mul2_en) {
    return (uint16_t)fb_frac | (out_mul2_en ? DPLL_FB_FRAC_MUL2_EN_BIT : 0u);
}

/**
 * @brief Predict calibrated 16-bit nominal OTW from target DCO frequency (250..500 MHz)
 *        and optional silicon speed_idx (pass 0 for real-chip Typical corner default).
 */
static inline uint16_t dpll_predict_otw(double f_dco_hz, int32_t speed_idx) {
    int32_t eff_speed = (speed_idx <= 0) ? DPLL_SPEED_TYP_ANCHOR : speed_idx;
    double  d500      = (double)(eff_speed - DPLL_SPEED_TYP_ANCHOR);
    double  d375, d250;

    if (d500 <= -4168.0) {
        d375 = -7753.0 + (d500 + 4168.0) * (300.0 / 250.0);
        d250 = -9052.0 + (d500 + 4168.0) * (320.0 / 250.0);
    } else if (d500 < 0.0) {
        d375 = d500 * (7753.0 / 4168.0);
        d250 = d500 * (9052.0 / 4168.0);
    } else if (d500 <= 719.0) {
        d375 = d500 * (256.0 / 719.0);
        d250 = d500 * (341.0 / 719.0);
    } else if (d500 <= 8056.0) {
        d375 = 256.0 + (d500 - 719.0) * (11006.0 / 7337.0);
        d250 = 341.0 + (d500 - 719.0) * (15148.0 / 7337.0);
    } else {
        d375 = 11262.0 + (d500 - 8056.0) * (71.0 / 95.0);
        d250 = 15489.0 + (d500 - 8056.0) * (125.0 / 95.0);
    }

    double otw_500 = 61065.0 - d500;
    double otw_375 = 56291.0 - d375;
    double otw_250 = 47769.0 - d250;

    double f_mhz = f_dco_hz / 1.0e6;
    if (f_mhz < 250.0) f_mhz = 250.0;
    if (f_mhz > 500.0) f_mhz = 500.0;

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
    return (uint16_t)(otw_pred + 0.5);
}

/**
 * @brief Calculate silicon speed_idx from the closed-loop OTW read back from
 *        DPLL_REG_OTW_CUR (0x08) after locking at f_dco_hz.
 */
static inline int32_t dpll_calc_speed_idx(double f_dco_hz, uint16_t otw_locked) {
    int32_t lo = 2000, hi = 25000;
    for (int iter = 0; iter < 20; iter++) {
        int32_t mid = (lo + hi) / 2;
        uint16_t pred = dpll_predict_otw(f_dco_hz, mid);
        if (pred > otw_locked) {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    uint16_t p_lo = dpll_predict_otw(f_dco_hz, lo);
    uint16_t p_hi = dpll_predict_otw(f_dco_hz, hi);
    int32_t diff_lo = (int32_t)p_lo - (int32_t)otw_locked;
    int32_t diff_hi = (int32_t)otw_locked - (int32_t)p_hi;
    return (diff_lo <= diff_hi) ? lo : hi;
}

/**
 * @brief Generate all DPLL setup parameters from reference frequency (f_ref_hz),
 *        target frequency (f_target_hz), and optional silicon speed_idx (0 = Typical).
 */
static inline bool dpll_generate_setup(
    double         f_ref_hz,
    double         f_target_hz,
    int32_t        speed_idx_in,
    double         duty_pct,
    bool           force_mul2,
    dpll_config_t *cfg,
    double        *out_f_dco_hz
) {
    if (!cfg || f_ref_hz < 1.0e6 || f_ref_hz > 10.0e6 || f_target_hz < 1.0 || f_target_hz > 1000.0e6) {
        return false;
    }
    double f_dco_hz = 500.0e6;
    if (f_target_hz > 500.0e6 || (force_mul2 && f_target_hz >= 250.0e6)) {
        cfg->out_mul2_en        = true;
        cfg->out_div_bypass     = true;
        cfg->out_prescale_shift = 0u;
        cfg->out_div_int        = 1u;
        cfg->out_div_frac       = 0u;
        f_dco_hz                = 0.5 * f_target_hz;
    } else if (f_target_hz >= 250.0e6) {
        cfg->out_mul2_en        = false;
        cfg->out_div_bypass     = true;
        cfg->out_prescale_shift = 0u;
        cfg->out_div_int        = 1u;
        cfg->out_div_frac       = 0u;
        f_dco_hz                = f_target_hz;
    } else {
        cfg->out_mul2_en    = false;
        cfg->out_div_bypass = false;
        if (f_target_hz >= 62.499e6 && f_target_hz <= 62.501e6) {
            f_dco_hz = 250.0e6;
        }
        double total_div = f_dco_hz / f_target_hz;
        uint8_t s = 0u;
        while (s < 20u && (total_div / (double)(1ULL << s)) >= 1024.0) {
            s++;
        }
        double scaled_div = total_div / (double)(1ULL << s);
        uint16_t m_int = (uint16_t)scaled_div;
        if (m_int < 1u) m_int = 1u;
        uint16_t f_frac = (uint16_t)((scaled_div - (double)m_int) * 256.0 + 0.5);
        if (f_frac >= 256u) {
            m_int++;
            f_frac = 0u;
        }
        cfg->out_prescale_shift = s;
        cfg->out_div_int        = m_int;
        cfg->out_div_frac       = (uint8_t)f_frac;
    }

    int duty_w = (int)((duty_pct / 100.0) * 256.0 + 0.5);
    if (duty_w < 1)   duty_w = 1;
    if (duty_w > 255) duty_w = 255;
    cfg->out_duty = (uint8_t)duty_w;

    double n_total = f_dco_hz / f_ref_hz;
    uint16_t div_n = (uint16_t)(n_total + 1e-9);
    uint16_t fb_f  = (uint16_t)((n_total - (double)div_n) * 256.0 + 0.5);
    if (fb_f >= 256u) {
        div_n++;
        fb_f = 0u;
    }
    cfg->div_n       = div_n;
    cfg->fb_frac     = (uint8_t)fb_f;
    cfg->otw_nominal = dpll_predict_otw(f_dco_hz, speed_idx_in);

    if (cfg->fb_frac != 0u) {
        cfg->kp_mult           = 4u;
        cfg->ki_mult           = 1u;
        cfg->ki_shift          = 3u;
        cfg->fast_lock_en      = false;
        cfg->fast_lock_mult    = 1u;
        cfg->gear_shift_thresh = 48u;
    } else if (f_ref_hz <= 2.0e6) {
        cfg->kp_mult           = 4u;
        cfg->ki_mult           = 1u;
        cfg->ki_shift          = (cfg->otw_nominal < 0x7E00u) ? 4u : 3u;
        cfg->fast_lock_en      = (cfg->otw_nominal < 0x7E00u) ? false : true;
        cfg->fast_lock_mult    = 1u;
        cfg->gear_shift_thresh = 24u;
    } else {
        cfg->kp_mult           = 8u;
        cfg->ki_mult           = 1u;
        cfg->ki_shift          = 1u;
        cfg->fast_lock_en      = true;
        cfg->fast_lock_mult    = 2u;
        cfg->gear_shift_thresh = 48u;
    }
    cfg->integrator_freeze = false;
    cfg->integrator_rst    = false;
    cfg->clr_lock          = false;

    if (out_f_dco_hz) {
        *out_f_dco_hz = f_dco_hz;
    }
    return true;
}

/**
 * @brief Compute calibrated feed-forward nominal OTW for a target DCO frequency (250..500 MHz)
 */
static inline uint16_t dpll_calc_otw_nominal(uint16_t dco_freq_mhz) {
    return dpll_predict_otw((double)dco_freq_mhz * 1.0e6, DPLL_SPEED_UNCALIBRATED);
}

/**
 * @brief Serialize a dpll_config_t structure into an 8-byte (64-bit) MSB-first SPI core burst buffer
 */
static inline void dpll_pack_burst64(const dpll_config_t *cfg, uint8_t buf[8]) {
    uint16_t dn = cfg->div_n & 0x03FFu;
    buf[0] = DPLL_CMD_BURST_WRITE;                                 /* [63:56] 0xFF Header */
    buf[1] = (uint8_t)((cfg->otw_nominal >> 8) & 0xFFu);           /* [55:48] otw_nominal[15:8] */
    buf[2] = (uint8_t)(cfg->otw_nominal & 0xFFu);                  /* [47:40] otw_nominal[7:0] */
    buf[3] = (uint8_t)((dn >> 2) & 0xFFu);                         /* [39:32] div_n[9:2] */
    buf[4] = (uint8_t)(((dn & 0x03u) << 6)                         /* [31:30] div_n[1:0] */
                     | (cfg->kp_mult & 0x3Fu));                    /* [29:24] kp_mult[5:0] */
    buf[5] = (uint8_t)(((cfg->ki_mult & 0x0Fu) << 4)               /* [23:20] ki_mult[3:0] */
                     | (cfg->ki_shift & 0x0Fu));                   /* [19:16] ki_shift[3:0] */
    buf[6] = (uint8_t)(((cfg->fast_lock_en ? 1u : 0u) << 7)        /* [15]    fast_lock_en */
                     | ((cfg->fast_lock_mult & 0x07u) << 4)        /* [14:12] fast_lock_mult[2:0] */
                     | ((cfg->gear_shift_thresh >> 4) & 0x0Fu));   /* [11:8]  gear_shift_thresh[7:4] */
    buf[7] = (uint8_t)(((cfg->gear_shift_thresh & 0x0Fu) << 4)     /* [7:4]   gear_shift_thresh[3:0] */
                     | ((cfg->integrator_freeze ? 1u : 0u) << 3)   /* [3]     integrator_freeze */
                     | ((cfg->integrator_rst    ? 1u : 0u) << 2)   /* [2]     integrator_rst */
                     | ((cfg->clr_lock          ? 1u : 0u) << 1)   /* [1]     clr_lock */
                     | (cfg->out_mul2_en        ? 1u : 0u));       /* [0]     out_mul2_en */
}

/**
 * @brief Serialize a dpll_config_t structure into a 12-byte (96-bit) extended full-chip burst buffer
 */
static inline void dpll_pack_burst96(const dpll_config_t *cfg, uint8_t buf[12]) {
    uint16_t m_int = cfg->out_div_int & 0x03FFu;
    dpll_pack_burst64(cfg, buf);
    buf[8]  = (uint8_t)(((cfg->out_div_bypass ? 1u : 0u) << 7)
                      | ((cfg->out_prescale_shift & 0x1Fu) << 2)
                      | ((m_int >> 8) & 0x03u));
    buf[9]  = (uint8_t)(m_int & 0xFFu);
    buf[10] = cfg->out_duty;
    buf[11] = cfg->out_div_frac;
}

/* ========================================================================== */
/* 4. Arduino Hardware SPI Transfer Functions (SPI Mode 0, MSB-First)         */
/* ========================================================================== */

#ifdef ARDUINO

#ifndef DPLL_SPI_CLOCK_HZ
#define DPLL_SPI_CLOCK_HZ (4000000UL) /**< Default 4 MHz SPI clock (supports up to 20 MHz) */
#endif

/**
 * @brief Write a 16-bit value to a 7-bit DPLL register via a 24-bit SPI Mode 0 transaction
 */
static inline void dpll_spi_write_reg24(uint8_t cs_pin, uint8_t reg_addr, uint16_t data) {
    SPI.beginTransaction(SPISettings(DPLL_SPI_CLOCK_HZ, MSBFIRST, SPI_MODE0));
    digitalWrite(cs_pin, LOW);
    SPI.transfer((uint8_t)(DPLL_SPI_RW_WRITE_BIT | (reg_addr & DPLL_SPI_ADDR_MASK)));
    SPI.transfer((uint8_t)((data >> 8) & 0xFFu));
    SPI.transfer((uint8_t)(data & 0xFFu));
    digitalWrite(cs_pin, HIGH);
    SPI.endTransaction();
}

/**
 * @brief Read a 16-bit value from a 7-bit DPLL register via a 24-bit SPI Mode 0 transaction
 */
static inline uint16_t dpll_spi_read_reg24(uint8_t cs_pin, uint8_t reg_addr) {
    uint8_t hi, lo;
    SPI.beginTransaction(SPISettings(DPLL_SPI_CLOCK_HZ, MSBFIRST, SPI_MODE0));
    digitalWrite(cs_pin, LOW);
    SPI.transfer((uint8_t)(reg_addr & DPLL_SPI_ADDR_MASK)); /* Bit 7 = 0 (Read) */
    hi = SPI.transfer(0x00u);
    lo = SPI.transfer(0x00u);
    digitalWrite(cs_pin, HIGH);
    SPI.endTransaction();
    return ((uint16_t)hi << 8) | (uint16_t)lo;
}

/**
 * @brief Atomically program core DPLL parameters via a 64-bit (8-byte) SPI burst write
 */
static inline void dpll_spi_write_burst64(uint8_t cs_pin, const dpll_config_t *cfg) {
    uint8_t frame[8];
    dpll_pack_burst64(cfg, frame);
    SPI.beginTransaction(SPISettings(DPLL_SPI_CLOCK_HZ, MSBFIRST, SPI_MODE0));
    digitalWrite(cs_pin, LOW);
    for (uint8_t i = 0; i < 8u; i++) {
        SPI.transfer(frame[i]);
    }
    digitalWrite(cs_pin, HIGH);
    SPI.endTransaction();
}

/**
 * @brief Atomically program all core and output divider parameters via a 96-bit (12-byte) SPI burst write
 */
static inline void dpll_spi_write_burst96(uint8_t cs_pin, const dpll_config_t *cfg) {
    uint8_t frame[12];
    dpll_pack_burst96(cfg, frame);
    SPI.beginTransaction(SPISettings(DPLL_SPI_CLOCK_HZ, MSBFIRST, SPI_MODE0));
    digitalWrite(cs_pin, LOW);
    for (uint8_t i = 0; i < 12u; i++) {
        SPI.transfer(frame[i]);
    }
    digitalWrite(cs_pin, HIGH);
    SPI.endTransaction();
}

/**
 * @brief Read REG_STATUS (0x04) and verify the 0x15 magic signature, lock status, and 10-bit div_n
 */
static inline bool dpll_read_status(uint8_t cs_pin, bool *is_locked, uint16_t *current_div_n) {
    uint16_t raw = dpll_spi_read_reg24(cs_pin, DPLL_REG_STATUS);
    uint8_t magic = (uint8_t)((raw >> DPLL_STATUS_MAGIC_SHIFT) & 0x1Fu);
    if (is_locked) {
        *is_locked = (raw & DPLL_STATUS_LOCKED_BIT) != 0u;
    }
    if (current_div_n) {
        *current_div_n = (uint16_t)(raw & DPLL_STATUS_DIV_N_MASK);
    }
    return (magic == DPLL_STATUS_MAGIC_EXPECTED);
}

/**
 * @brief Full-Chip Firmware Configuration, Lock Acquisition & Speed-Index Calibration:
 *        Takes reference frequency f_ref_hz (1..10 MHz), target frequency f_target_hz
 *        (1 Hz .. 1000 MHz), and optional speed_idx_in (0 = Typical corner default).
 *        Programs all setup parameters over SPI, acquires lock, reads back REG_OTW_CUR
 *        (0x08), and returns the calibrated silicon speed_idx so future calls passing
 *        this speed_idx lock maximally fast.
 */
static inline int32_t dpll_configure_and_lock(
    uint8_t        cs_pin,
    uint8_t        lock_pin,
    double         f_ref_hz,
    double         f_target_hz,
    int32_t        speed_idx_in,
    double         duty_pct,
    bool           force_mul2,
    uint16_t      *out_otw_locked,
    uint32_t      *out_lock_us
) {
    dpll_config_t cfg;
    double        f_dco_hz = 500.0e6;
    if (!dpll_generate_setup(f_ref_hz, f_target_hz, speed_idx_in, duty_pct, force_mul2, &cfg, &f_dco_hz)) {
        return -1;
    }

    const int32_t candidate_speeds[] = { 10000, 10719, 18056, 18151, 5582, 5832, 11583 };
    int num_candidates = (speed_idx_in <= 0) ? 7 : 1;

    uint32_t t0 = micros();
    dpll_spi_write_reg24(cs_pin, DPLL_REG_FB_FRAC, dpll_pack_fb_frac(cfg.fb_frac, cfg.out_mul2_en));
    dpll_spi_write_reg24(cs_pin, DPLL_REG_OUT_DIV2, dpll_pack_out_div2(cfg.out_duty, cfg.out_div_frac));
    dpll_spi_write_reg24(cs_pin, DPLL_REG_OUT_DIV1, dpll_pack_out_div1(cfg.out_div_bypass, cfg.out_prescale_shift, cfg.out_div_int));

    for (int attempt = 0; attempt < num_candidates; attempt++) {
        if (attempt > 0) {
            cfg.otw_nominal = dpll_predict_otw(f_dco_hz, candidate_speeds[attempt]);
        }
        dpll_spi_write_burst64(cs_pin, &cfg);
        uint32_t wait_t0 = micros();
        uint32_t timeout_us = (uint32_t)((40.0 * 1.0e6) / f_ref_hz) + 10U;
        while (digitalRead(lock_pin) == LOW && (micros() - wait_t0) < timeout_us) {
            /* wait for lock_pin */
        }
        if (digitalRead(lock_pin) == HIGH) {
            break;
        }
    }

    if (out_lock_us) {
        *out_lock_us = micros() - t0;
    }
    uint16_t otw_cur = dpll_spi_read_reg24(cs_pin, DPLL_REG_OTW_CUR);
    if (out_otw_locked) {
        *out_otw_locked = otw_cur;
    }
    return dpll_calc_speed_idx(f_dco_hz, otw_cur);
}

#endif /* ARDUINO */

#ifdef __cplusplus
}
#endif

#endif /* DPLL_SPI_H */
