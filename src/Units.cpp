// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

#include "SteedPilot/Units.h"

namespace SteedPilot {

FormattedDistance formatDistanceMeters(int32_t meters, UnitSettings settings) {
    if (meters < 0) {
        meters = 0;
    }

    switch (settings.distance) {
        case DistanceUnitPreference::KilometersMeters:
            if (meters >= 1000) {
                return {(int32_t)((meters + 50) / 100), 1, "km"};
            }
            return {meters, 0, "m"};

        case DistanceUnitPreference::MilesFeet:
            if (meters >= 1609) {
                return {(int32_t)((meters * 10 + 804) / 1609), 1, "mi"};
            }
            return {(int32_t)((meters * 328 + 50) / 100), 0, "ft"};

        case DistanceUnitPreference::MilesMeters:
        default:
            if (meters >= 200) {
                return {(int32_t)((meters * 10 + 804) / 1609), 1, "mi"};
            }
            return {meters, 0, "m"};
    }
}

} // namespace SteedPilot
