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

#include "Display.h"
#include "NavState.h"
#include "Units.h"

namespace SteedPilot {

class App {
public:
    explicit App(UnitSettings units = {});

    void setState(const NavState& state);
    const NavState& state() const;

    void tick(uint32_t elapsedMs);
    void render(Display& display);

private:
    UnitSettings _units;
    NavState _state;
    uint32_t _timeMs = 0;

    void renderNavigation(Display& display);
    void renderDestination(Display& display);
    void renderRideInfo(Display& display);
    void renderCalibration(Display& display);
};

} // namespace SteedPilot
