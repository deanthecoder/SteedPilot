// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

#include "FirmwareTouch.h"

#include "TCA9554PWR.h"

#include <Arduino.h>

bool FirmwareTouch::begin() {
    pinMode(InterruptPin, INPUT_PULLUP);
    Set_EXIO(EXIO_PIN1, Low);
    delay(10);
    Set_EXIO(EXIO_PIN1, High);
    delay(50);

    // The CST816 interrupt line is reliable for wake/tap pulses, while the
    // register interface varies between board revisions. Keep awake gestures
    // on TP_INT until we add a verified touch-controller driver.
    Serial.println("Touch wake interrupt enabled");
    return false;
}

bool FirmwareTouch::read(Sample& sample) const {
    sample = {};
    return false;
}

bool FirmwareTouch::available() const {
    return _available;
}
