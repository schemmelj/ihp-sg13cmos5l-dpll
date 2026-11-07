/**
 * @file dpll_arduino_example.ino
 * @brief Complete Arduino Programming Example for the IHP 130nm SG13CMOS5L DPLL Breakout Board
 *
 * Hardware Connections (3.3V Logic Arduino -> 20x30mm DPLL Breakout Board):
 *   - Arduino 3.3V   ---> Pin J11 (IOV / 3.3V Input: powers IO ring, Blue LED D1, and U2/U3 TLV773 1.2V LDOs)
 *   - Arduino GND    ---> Pin J10 / J6 (GND: solid B.Cu ground plane)
 *   - Arduino Pin 10 ---> Pin J3  (CS_N: Active-Low SPI Chip Select)
 *   - Arduino SCK    ---> Pin J4  (SCK : Asynchronous SPI Clock, up to 20 MHz)
 *   - Arduino MOSI   ---> Pin J1  (MOSI: SPI Master-Out Slave-In)
 *   - Arduino MISO   ---> Pin J5  (MISO: SPI Master-In Slave-Out)
 *   - Arduino Pin 7  ---> Pin J2  (RSTN: Active-Low Chip Reset)
 *   - Arduino Pin 6  <--- Pin J7  (LCK : Hardware Lock Status Output, also drives Red LED D2)
 *   - 1..10 MHz Ref  ---> Pin J2  (RCLK: 1..10 MHz 3.3V CMOS Reference Clock Input, 5.0 MHz nominal)
 *   - RF Output      <--- J1 SMA  (50-Ohm Coaxial Output: 1 Hz .. 500 MHz + 500 MHz .. 1.0 GHz 2x XOR Mode)
 */

#include <SPI.h>
#include "../dpll_spi.h"

/* Pin definitions on the Arduino */
static const uint8_t PIN_DPLL_CS_N   = 10;
static const uint8_t PIN_DPLL_RST_N  = 7;
static const uint8_t PIN_DPLL_LOCKED = 6;

/**
 * @brief Wait for the DPLL hardware lock pin (and Red LED D2) to assert HIGH
 */
static bool wait_for_dpll_lock(uint32_t timeout_us, uint32_t *elapsed_us) {
    uint32_t t0 = micros();
    while (digitalRead(PIN_DPLL_LOCKED) == LOW) {
        if ((micros() - t0) >= timeout_us) {
            if (elapsed_us) *elapsed_us = timeout_us;
            return false;
        }
    }
    if (elapsed_us) *elapsed_us = micros() - t0;
    return true;
}

/**
 * @brief Print all readable DPLL registers over Serial
 */
static void print_dpll_telemetry(const char *label, int32_t speed_idx, uint32_t lock_us) {
    uint16_t otw_nom   = dpll_spi_read_reg24(PIN_DPLL_CS_N, DPLL_REG_OTW_NOM);
    uint16_t otw_cur   = dpll_spi_read_reg24(PIN_DPLL_CS_N, DPLL_REG_OTW_CUR);
    uint16_t div_ctrl  = dpll_spi_read_reg24(PIN_DPLL_CS_N, DPLL_REG_DIV_CTRL);
    uint16_t out_div1  = dpll_spi_read_reg24(PIN_DPLL_CS_N, DPLL_REG_OUT_DIV1);
    uint16_t out_div2  = dpll_spi_read_reg24(PIN_DPLL_CS_N, DPLL_REG_OUT_DIV2);
    uint16_t fb_frac   = dpll_spi_read_reg24(PIN_DPLL_CS_N, DPLL_REG_FB_FRAC);
    bool     spi_locked = false;
    uint16_t div_n      = 0;
    bool     magic_ok   = dpll_read_status(PIN_DPLL_CS_N, &spi_locked, &div_n);
    bool     pin_locked = (digitalRead(PIN_DPLL_LOCKED) == HIGH);

    Serial.println(F("------------------------------------------------------------"));
    Serial.print(F("[DPLL] Stage: "));
    Serial.println(label);
    Serial.print(F("  REG_OTW_NOM (00) : 0x"));
    Serial.print(otw_nom, HEX);
    Serial.print(F(" | REG_OTW_CUR (08): 0x"));
    Serial.print(otw_cur, HEX);
    Serial.print(F(" | speed_idx="));
    Serial.print(speed_idx);
    Serial.print(F(" | t_lock="));
    Serial.print(lock_us);
    Serial.println(F(" us"));
    Serial.print(F("  REG_DIV_CTRL(01) : 0x"));
    Serial.print(div_ctrl, HEX);
    Serial.print(F(" (N="));
    Serial.print(div_n);
    Serial.print(F(", F_fb="));
    Serial.print(fb_frac & 0xFFu);
    Serial.println(F("/256)"));
    Serial.print(F("  REG_OUT_DIV1(05) : 0x"));
    Serial.print(out_div1, HEX);
    Serial.print(F(" | REG_OUT_DIV2(06): 0x"));
    Serial.print(out_div2, HEX);
    Serial.print(F(" | 2x_XOR="));
    Serial.println((div_ctrl & DPLL_DIV_OUT_MUL2_EN_BIT) ? F("ON (500-1000 MHz)") : F("OFF"));
    Serial.print(F("  Lock Status      : PIN_LOCKED="));
    Serial.print(pin_locked ? F("1 (Red LED ON)") : F("0 (OFF)"));
    Serial.print(F(" | SPI_LOCKED="));
    Serial.print(spi_locked ? F("1") : F("0"));
    Serial.print(F(" | Magic(0x15)="));
    Serial.println(magic_ok ? F("OK") : F("ERR"));
}

void setup() {
    Serial.begin(115200);
    while (!Serial && millis() < 3000UL) {
        /* Wait up to 3s for USB Serial Monitor */
    }

    pinMode(PIN_DPLL_CS_N, OUTPUT);
    digitalWrite(PIN_DPLL_CS_N, HIGH);
    pinMode(PIN_DPLL_RST_N, OUTPUT);
    digitalWrite(PIN_DPLL_RST_N, LOW);
    pinMode(PIN_DPLL_LOCKED, INPUT);

    SPI.begin();

    Serial.println(F("\n============================================================"));
    Serial.println(F("  IHP 130nm SG13CMOS5L All-Digital PLL Breakout Controller"));
    Serial.println(F("============================================================"));

    /* 1. Release active-low reset (RST_N) after power rails settle */
    delay(2);
    digitalWrite(PIN_DPLL_RST_N, HIGH);

    uint16_t otw_locked = 0;
    uint32_t lock_us    = 0;

    /* 2. First Call: Pass speed_idx = DPLL_SPEED_UNCALIBRATED (0) to start from
     *    the real chip Typical corner (0xEE89), lock to 50.0 MHz from a 5.0 MHz
     *    reference clock, read back REG_OTW_CUR (0x08), and obtain chip_speed_idx! */
    int32_t chip_speed_idx = dpll_configure_and_lock(
        PIN_DPLL_CS_N, PIN_DPLL_LOCKED,
        5.0e6, 50.0e6, DPLL_SPEED_UNCALIBRATED, 50.0, false,
        &otw_locked, &lock_us
    );
    print_dpll_telemetry("Initial Lock & Speed Calibration: 50.0 MHz Output (Ref=5 MHz)", chip_speed_idx, lock_us);

    /* 3. Subsequent Call #1: Pass calibrated chip_speed_idx for maximal fast lock
     *    at 500.0 MHz direct DCO output */
    chip_speed_idx = dpll_configure_and_lock(
        PIN_DPLL_CS_N, PIN_DPLL_LOCKED,
        5.0e6, 500.0e6, chip_speed_idx, 50.0, false,
        &otw_locked, &lock_us
    );
    print_dpll_telemetry("Fast Calibrated Lock: 500.0 MHz Direct DCO Output", chip_speed_idx, lock_us);

    /* 4. Subsequent Call #2: Pass calibrated chip_speed_idx for 1.000 GHz (1000 MHz)
     *    2x XOR output multiplier mode */
    chip_speed_idx = dpll_configure_and_lock(
        PIN_DPLL_CS_N, PIN_DPLL_LOCKED,
        5.0e6, 1000.0e6, chip_speed_idx, 50.0, true,
        &otw_locked, &lock_us
    );
    print_dpll_telemetry("Fast Calibrated Lock: 1.000 GHz (2x XOR Multiplier)", chip_speed_idx, lock_us);

    /* 5. Subsequent Call #3: Pass calibrated chip_speed_idx for 375.0 MHz Fractional-N
     *    DCO synthesis (N = 75.0 at 5 MHz ref, or N = 37.5 at 10 MHz ref) */
    chip_speed_idx = dpll_configure_and_lock(
        PIN_DPLL_CS_N, PIN_DPLL_LOCKED,
        5.0e6, 375.0e6, chip_speed_idx, 50.0, false,
        &otw_locked, &lock_us
    );
    print_dpll_telemetry("Fast Calibrated Lock: 375.0 MHz DCO Output", chip_speed_idx, lock_us);
}

void loop() {
    delay(1000);
}
