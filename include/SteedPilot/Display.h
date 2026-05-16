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

#include "Color.h"

namespace SteedPilot {

enum class TextAlign {
    Left,
    Center,
    Right
};

class Display {
public:
    virtual ~Display() = default;

    virtual int width() const = 0;
    virtual int height() const = 0;

    virtual void clear(Color color) = 0;
    virtual void present() = 0;

    virtual void line(int x0, int y0, int x1, int y1, Color color, int thickness = 1) = 0;
    virtual void circle(int cx, int cy, int radius, Color color, int thickness = 1) = 0;
    virtual void fillCircle(int cx, int cy, int radius, Color color) = 0;
    virtual void text(int x, int y, const char* value, int size, Color color, TextAlign align = TextAlign::Left) = 0;
};

} // namespace SteedPilot

