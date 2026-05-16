// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

#include <Arduino.h>

#include "SteedPilot/App.h"

SteedPilot::App app;

void setup() {
    Serial.begin(115200);
    Serial.println("SteedPilot firmware scaffold");
    Serial.println("Display bring-up is the next hardware step.");
}

void loop() {
    static uint32_t last = millis();
    const uint32_t now = millis();

    app.tick(now - last);
    last = now;

    delay(16);
}

