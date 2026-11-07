// ==============================================================================
// File: testchip/firmware/dpll_firmware.h
// Description: Embedded C Firmware Driver & Silicon Speed-Index Calibration API
//              for the Standalone IHP 130nm BiCMOS (SG13CMOS5L IO + SG13G2 Core)
//              All-Digital PLL Testchip (`dpll_testchip_top`).
//
// Overview:
//   Provides `dpll_fw_configure_and_lock()`, which takes:
//     - Reference frequency `f_ref_hz` (1.0 MHz .. 10.0 MHz)
//     - Target output frequency `f_target_hz` (1.0 Hz .. 1000.0 MHz)
//     - Optional silicon `speed_idx_in` (pass 0 / DPLL_SPEED_UNCALIBRATED on
//       first call to start from the real chip Typical corner parameters; pass
//       the returned `speed_idx` on all subsequent calls for maximal fast lock).
// ==============================================================================

#ifndef DPLL_FIRMWARE_H
#define DPLL_FIRMWARE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// ------------------------------------------------------------------------------
// 1. Hardware SPI Register Map (24-Bit Single-Reg & 64/96-Bit Atomic Burst)
// ------------------------------------------------------------------------------
#define DPLL_REG_OTW_NOM            (0x00u)  // [15:0] otw_nominal
#define DPLL_REG_DIV_CTRL           (0x01u)  // [13] out_mul2_en, [12] int_rst, [11] int_frz, [10] clr_lock, [9:0] div_n
#define DPLL_REG_LOOP_GAIN          (0x02u)  // [13:10] ki_shift, [9:6] ki_mult, [5:0] kp_mult
#define DPLL_REG_GEAR_CFG           (0x03u)  // [11] fast_lock_en, [10:8] fast_lock_mult, [7:0] gear_shift_thresh
#define DPLL_REG_STATUS             (0x04u)  // [15:11] 5'h15 magic, [10] locked, [9:0] div_n (Read-Only)
#define DPLL_REG_OUT_DIV1           (0x05u)  // [15] out_div_bypass, [14:10] out_prescale_shift, [9:0] out_div_int
#define DPLL_REG_OUT_DIV2           (0x06u)  // [15:8] out_duty, [7:0] out_div_frac
#define DPLL_REG_FB_FRAC            (0x07u)  // [8] out_mul2_en, [7:0] fb_frac
#define DPLL_REG_OTW_CUR            (0x08u)  // [15:0] otw_mon live closed-loop OTW readback (Read-Only)

// ------------------------------------------------------------------------------
// 2. Silicon Speed Index Constants (Calibrated to Post-Layout Extracted Chip)
// ------------------------------------------------------------------------------
// When `speed_idx_in <= 0` (DPLL_SPEED_UNCALIBRATED), the firmware generates
// initial setup parameters for the real chip Typical corner (1.20V, 25C,
// post-layout 3D OpenRCX SPEF extracted delays: speed_idx = 10000).
// After locking, the firmware reads back `DPLL_REG_OTW_CUR (0x08)` and returns
// the measured silicon speed index:
//   -  5582 : Post-layout SLOW corner (1.08V, +125C, OTW_500 = 0xFFCB)
//   -  5832 : Pre-layout  SLOW corner (1.08V, +125C, OTW_500 = 0xFED1)
//   - 10000 : Post-layout TYP  corner (1.20V,  +25C, OTW_500 = 0xEE89) [DEFAULT]
//   - 10719 : Pre-layout  TYP  corner (1.20V,  +25C, OTW_500 = 0xEBBA)
//   - 18056 : Post-layout FAST corner (1.32V,  -40C, OTW_500 = 0xCF11)
//   - 18151 : Pre-layout  FAST corner (1.32V,  -40C, OTW_500 = 0xCEB2)
#define DPLL_SPEED_UNCALIBRATED     (0)
#define DPLL_SPEED_TYP_ANCHOR       (10000)
#define DPLL_SPEED_NOMINAL_TYP      (10000)
#define DPLL_SPEED_MIN_SLOW         (2000)
#define DPLL_SPEED_MAX_FAST         (25000)

// ------------------------------------------------------------------------------
// 3. Complete Synthesized DPLL Register Setup Structure
// ------------------------------------------------------------------------------
typedef struct {
    // Target & Internal Oscillator Frequencies
    double   f_ref_hz;            // Reference input clock (1.0 MHz .. 10.0 MHz)
    double   f_target_hz;         // Requested output clock (1.0 Hz .. 1000.0 MHz)
    double   f_dco_hz;            // Selected internal DCO frequency (250.0 MHz .. 500.0 MHz)
    double   f_actual_hz;         // Exact synthesized output frequency (Hz)
    int32_t  speed_idx_used;      // Speed index used to predict otw_nominal (1000 = Typ)

    // Core Feedback Divider & DCO Tuning Word
    uint16_t otw_nominal;         // REG_OTW_NOM (0x00): 16-bit center DCO tuning word
    uint16_t div_n;               // REG_DIV_CTRL[9:0]: Integer feedback ratio N (25..500)
    uint8_t  fb_frac;             // REG_FB_FRAC[7:0]: Fractional feedback numerator (0..255)

    // Digital PI Loop Filter & Gear-Shifting Parameters
    uint8_t  kp_mult;             // REG_LOOP_GAIN[5:0]: Proportional gain (1..63)
    uint8_t  ki_mult;             // REG_LOOP_GAIN[9:6]: Integral gain multiplier (1..15)
    uint8_t  ki_shift;            // REG_LOOP_GAIN[13:10]: Integral gain right-shift (0..15)
    bool     fast_lock_en;        // REG_GEAR_CFG[11]: Enable acquisition gear-shifting
    uint8_t  fast_lock_mult;      // REG_GEAR_CFG[10:8]: Fast-lock boost multiplier (1..7)
    uint8_t  gear_shift_thresh;   // REG_GEAR_CFG[7:0]: Phase error threshold for gear shift

    // Glitch-Free Output Fractional-N Divider, Duty Shaper & 2x-XOR Multiplier
    bool     out_div_bypass;      // REG_OUT_DIV1[15]: 1 = Direct 250-500 MHz DCO bypass
    bool     out_mul2_en;         // REG_FB_FRAC[8]:   1 = Enable 2x-XOR frequency doubler
    uint8_t  out_prescale_shift;  // REG_OUT_DIV1[14:10]: Octave prescaler S (0..20 -> 2^S)
    uint16_t out_div_int;         // REG_OUT_DIV1[9:0]: Integer divisor M_int (1..1023)
    uint8_t  out_div_frac;        // REG_OUT_DIV2[7:0]: Fractional divisor F_frac (0..255)
    uint8_t  out_duty;            // REG_OUT_DIV2[15:8]: Duty cycle word (1..255, 128=50%)
} dpll_fw_setup_t;

// ------------------------------------------------------------------------------
// 4. Platform Hardware Abstraction Layer (HAL) Callbacks for External Chip Pads
// ------------------------------------------------------------------------------
typedef struct {
    void     (*spi_write_reg24)(uint8_t reg_addr, uint16_t reg_data);
    uint16_t (*spi_read_reg24)(uint8_t reg_addr);
    void     (*spi_burst_write64)(uint64_t mosi_frame);
    bool     (*read_pad_locked)(void);
    void     (*wait_ref_cycles)(uint32_t num_cycles);
} dpll_fw_hal_t;

// ------------------------------------------------------------------------------
// 5. Public Firmware API Functions
// ------------------------------------------------------------------------------

/**
 * Predicts the 16-bit DCO Oscillator Tuning Word (`otw_nominal`) for a given
 * DCO frequency `f_dco_hz` (250..500 MHz) and silicon `speed_idx` (where 0 or
 * 1000 selects the real chip Typical corner model).
 */
uint16_t dpll_fw_predict_otw(double f_dco_hz, int32_t speed_idx);

/**
 * Calculates the silicon `speed_idx` from the closed-loop `otw_locked` read
 * back from `DPLL_REG_OTW_CUR (0x08)` after locking at `f_dco_hz`.
 */
int32_t dpll_fw_calc_speed_idx(double f_dco_hz, uint16_t otw_locked);

/**
 * Generates all DPLL and output divider setup parameters from `(f_ref_hz,
 * f_target_hz, speed_idx_in)` (plus duty cycle and optional 2x-XOR override).
 */
int dpll_fw_generate_setup(
    double           f_ref_hz,
    double           f_target_hz,
    double           duty_pct,
    bool             force_mul2,
    int32_t          speed_idx_in,
    dpll_fw_setup_t *out_setup
);

/**
 * Full-chip firmware configuration, closed-loop lock acquisition, OTW readback,
 * and silicon speed-index calibration function.
 *
 * - On the first call (`speed_idx_in == 0`), starts from the real chip Typical
 *   corner (`speed_idx = 1000`), acquires lock across any PVT corner (automatically
 *   stepping `otw_nominal` if the chip is in an extreme FAST or SLOW corner),
 *   reads back `DPLL_REG_OTW_CUR (0x08)`, and returns the chip's calibrated
 *   `speed_idx`.
 * - On all subsequent calls when the caller passes the returned `speed_idx` as
 *   `speed_idx_in`, immediately programs the exact corner-calibrated `otw_nominal`
 *   and locks maximally fast.
 */
int32_t dpll_fw_configure_and_lock(
    const dpll_fw_hal_t *hal,
    double               f_ref_hz,
    double               f_target_hz,
    double               duty_pct,
    bool                 force_mul2,
    int32_t              speed_idx_in,
    dpll_fw_setup_t     *out_applied_setup,
    uint16_t            *out_otw_locked
);

#ifdef __cplusplus
}
#endif

#endif // DPLL_FIRMWARE_H
