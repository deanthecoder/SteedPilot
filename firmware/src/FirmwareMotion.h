// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

#pragma once

#include <cstdint>

/**
 * Low-power-ish motion detector backed by the onboard QMI8658 accelerometer.
 */
class FirmwareMotion {
public:
    /**
     * Initialises the QMI8658 accelerometer.
     *
     * @return True when the IMU responds and acceleration can be sampled.
     */
    bool begin();

    /**
     * Polls the accelerometer and updates the motion/stillness state.
     *
     * @param now Current Arduino millis timestamp.
     * @return True when a significant movement was detected by this sample.
     */
    bool update(uint32_t now);

    /**
     * Gets whether the IMU has been still long enough for idle power saving.
     *
     * @param now Current Arduino millis timestamp.
     * @param quietMs Required still duration.
     * @return True when the IMU is available and quiet for at least quietMs.
     */
    bool isStillFor(uint32_t now, uint32_t quietMs) const;

    /**
     * Gets whether the IMU was found during begin().
     *
     * @return True when motion detection is active.
     */
    bool available() const;

private:
    static constexpr uint8_t Qmi8658Address = 0x6B;
    static constexpr uint8_t RegisterWhoAmI = 0x00;
    static constexpr uint8_t RegisterCtrl1 = 0x02;
    static constexpr uint8_t RegisterCtrl2 = 0x03;
    static constexpr uint8_t RegisterCtrl7 = 0x08;
    static constexpr uint8_t RegisterAxL = 0x35;
    static constexpr uint8_t ExpectedWhoAmI = 0x05;

    // The QMI8658 is configured for +/-2g. This threshold is deliberately
    // above normal sensor jitter but below the movement caused by picking up
    // or rolling the bike.
    static constexpr int32_t MotionDeltaThreshold = 1800;
    static constexpr uint32_t SampleIntervalMs = 250;

    bool _available = false;
    bool _haveSample = false;
    uint32_t _lastSampleMs = 0;
    uint32_t _lastMotionMs = 0;
    int16_t _lastX = 0;
    int16_t _lastY = 0;
    int16_t _lastZ = 0;

    bool readAcceleration(int16_t& x, int16_t& y, int16_t& z) const;
    bool writeRegister(uint8_t reg, uint8_t value) const;
    bool readRegisters(uint8_t reg, uint8_t* data, uint32_t length) const;
};
