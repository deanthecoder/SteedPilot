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
    /** Numeric distance value, with decimalPlaces indicating the fixed-point scale. */
    int32_t value;

    /** Number of decimal places represented by value. */
    int8_t decimalPlaces;

    /** Unit suffix to display with the value. */
    const char* unit;
};

/**
 * Formats a distance for display using the rider's preferred unit system.
 *
 * @param meters Distance in meters.
 * @param settings Unit preference settings.
 * @return Display-ready distance value and suffix.
 */
FormattedDistance formatDistanceMeters(int32_t meters, UnitSettings settings);

} // namespace SteedPilot
