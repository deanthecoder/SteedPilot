// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

#include "FirmwareMotion.h"

#include "I2C_Driver.h"

#include <Arduino.h>
#include <cstdlib>

namespace {

int16_t readInt16Le(const uint8_t* data) {
    return (int16_t)((uint16_t)data[0] | ((uint16_t)data[1] << 8));
}

} // namespace

bool FirmwareMotion::begin() {
    uint8_t whoAmI = 0;
    if (!readRegisters(RegisterWhoAmI, &whoAmI, 1)) {
        Serial.println("QMI8658 not found");
        return false;
    }

    if (whoAmI != ExpectedWhoAmI) {
        Serial.printf("Unexpected QMI8658 WhoAmI: 0x%02x\n", whoAmI);
        return false;
    }

    // CTRL1 enables address auto-increment. CTRL2 uses +/-2g at 125Hz.
    // CTRL7 enables the accelerometer only; the gyro stays off to save power.
    if (!writeRegister(RegisterCtrl1, 0x40)
        || !writeRegister(RegisterCtrl2, 0x06)
        || !writeRegister(RegisterCtrl7, 0x01)) {
        Serial.println("QMI8658 init failed");
        return false;
    }

    _available = true;
    _lastMotionMs = millis();
    Serial.println("QMI8658 motion detection enabled");
    return true;
}

bool FirmwareMotion::update(uint32_t now) {
    if (!_available || now - _lastSampleMs < SampleIntervalMs) {
        return false;
    }

    _lastSampleMs = now;

    int16_t x = 0;
    int16_t y = 0;
    int16_t z = 0;
    if (!readAcceleration(x, y, z)) {
        return false;
    }

    bool moving = false;
    if (_haveSample) {
        const int32_t delta = abs((int32_t)x - _lastX)
            + abs((int32_t)y - _lastY)
            + abs((int32_t)z - _lastZ);
        moving = delta >= MotionDeltaThreshold;
        if (moving) {
            _lastMotionMs = now;
        }
    } else {
        _lastMotionMs = now;
        _haveSample = true;
    }

    _lastX = x;
    _lastY = y;
    _lastZ = z;
    return moving;
}

bool FirmwareMotion::isStillFor(uint32_t now, uint32_t quietMs) const {
    return _available && _haveSample && now - _lastMotionMs >= quietMs;
}

bool FirmwareMotion::available() const {
    return _available;
}

bool FirmwareMotion::readAcceleration(int16_t& x, int16_t& y, int16_t& z) const {
    uint8_t data[6] = {};
    if (!readRegisters(RegisterAxL, data, sizeof(data))) {
        return false;
    }

    x = readInt16Le(&data[0]);
    y = readInt16Le(&data[2]);
    z = readInt16Le(&data[4]);
    return true;
}

bool FirmwareMotion::writeRegister(uint8_t reg, uint8_t value) const {
    return I2C_Write(Qmi8658Address, reg, &value, 1) == 0;
}

bool FirmwareMotion::readRegisters(uint8_t reg, uint8_t* data, uint32_t length) const {
    return I2C_Read(Qmi8658Address, reg, data, length) == 0;
}
