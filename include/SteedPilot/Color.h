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

struct Color {
    uint8_t r;
    uint8_t g;
    uint8_t b;

    constexpr Color(uint8_t red, uint8_t green, uint8_t blue) : r(red), g(green), b(blue) {}
};

namespace Palette {
    constexpr Color Black{0, 0, 0};
    constexpr Color White{245, 248, 242};
    constexpr Color Dim{70, 78, 82};
    constexpr Color Muted{138, 150, 151};
    constexpr Color Cyan{58, 206, 212};
    constexpr Color Amber{255, 184, 77};
    constexpr Color Red{236, 83, 74};
    constexpr Color Green{118, 220, 130};
}

} // namespace SteedPilot

