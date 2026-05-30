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
 * Minimal CST816 touch reader for local power gestures.
 */
class FirmwareTouch {
public:
    struct Sample {
        bool touched = false;
        uint8_t gesture = 0;
        uint16_t x = 0;
        uint16_t y = 0;
    };

    /**
     * Initialises the touch interrupt pin and verifies the CST816 responds.
     *
     * @return True when the touch controller can be read.
     */
    bool begin();

    /**
     * Reads the latest touch state.
     *
     * @param sample Output sample.
     * @return True when the touch controller returned data.
     */
    bool read(Sample& sample) const;

    /**
     * Gets whether the touch controller was found during begin().
     *
     * @return True when touch reads are available.
     */
    bool available() const;

    /**
     * ESP32 GPIO connected to TP_INT. This is RTC-capable and used for deep-sleep wake.
     */
    static constexpr int InterruptPin = 4;

private:
    bool _available = false;
};
