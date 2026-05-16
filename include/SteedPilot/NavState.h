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

namespace SteedPilot {

enum class DisplayMode {
    Navigation,
    Destination,
    RideInfo,
    Calibration
};

enum class Maneuver {
    Continue,
    SlightLeft,
    TurnLeft,
    SharpLeft,
    UTurn,
    SlightRight,
    TurnRight,
    SharpRight,
    Roundabout,
    Arrive
};

enum class SpeedUnit {
    Mph,
    Kph
};

struct NavState {
    DisplayMode mode = DisplayMode::Navigation;
    Maneuver maneuver = Maneuver::Continue;
    int32_t distanceToManeuverMeters = 240;
    int32_t distanceToDestinationMeters = 18400;
    int8_t maneuverProgressRemaining = -1;
    int8_t tripProgressComplete = -1;
    int16_t destinationBearingDegrees = 35;
    int8_t roundaboutExitCount = 0;
    int8_t roundaboutExit = 0;
    int16_t currentSpeed = 0;
    int16_t speedLimit = 0;
    SpeedUnit speedUnit = SpeedUnit::Mph;
    bool connected = true;
};

} // namespace SteedPilot
