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

enum class DistanceUnitPreference {
    MilesMeters,
    MilesFeet,
    KilometersMeters
};

struct UnitSettings {
    DistanceUnitPreference distance = DistanceUnitPreference::MilesMeters;
};

struct FormattedDistance {
    int32_t value;
    int8_t decimalPlaces;
    const char* unit;
};

FormattedDistance formatDistanceMeters(int32_t meters, UnitSettings settings);

} // namespace SteedPilot
