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
    /**
     * Creates the shared SteedPilot application state machine.
     *
     * @param units Distance formatting preferences used by rendered screens.
     */
    explicit App(UnitSettings units = {});

    /**
     * Replaces the current navigation state received from the phone or simulator.
     *
     * @param state The latest navigation and device display state.
     */
    void setState(const NavState& state);

    /**
     * Gets the current navigation state.
     *
     * @return The state most recently supplied to setState().
     */
    const NavState& state() const;

    /**
     * Advances time-dependent UI state.
     *
     * @param elapsedMs Milliseconds elapsed since the previous tick.
     */
    void tick(uint32_t elapsedMs);

    /**
     * Renders the active display mode to the supplied display.
     *
     * @param display Rendering target used by either the simulator or firmware.
     */
    void render(Display& display);

private:
    UnitSettings _units;
    NavState _state;
    uint32_t _timeMs = 0;
    float _displayTripProgress = -1.0f;
    float _displayManeuverProgress = -1.0f;

    /**
     * Renders the turn-by-turn navigation screen.
     *
     * @param display Rendering target.
     */
    void renderNavigation(Display& display);

    /**
     * Renders the destination-heading screen.
     *
     * @param display Rendering target.
     */
    void renderDestination(Display& display);

    /**
     * Renders the ride-information screen.
     *
     * @param display Rendering target.
     */
    void renderRideInfo(Display& display);

    /**
     * Renders the no-phone connection warning screen.
     *
     * @param display Rendering target.
     */
    void renderNoPhone(Display& display);

    /**
     * Renders the display calibration screen used during hardware bring-up.
     *
     * @param display Rendering target.
     */
    void renderCalibration(Display& display);
};

} // namespace SteedPilot
