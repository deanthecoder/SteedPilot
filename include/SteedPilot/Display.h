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
    /**
     * Destroys the display abstraction.
     */
    virtual ~Display() = default;

    /**
     * Gets the logical display width in pixels.
     *
     * @return Display width.
     */
    virtual int width() const = 0;

    /**
     * Gets the logical display height in pixels.
     *
     * @return Display height.
     */
    virtual int height() const = 0;

    /**
     * Clears the full display to a single color.
     *
     * @param color Fill color.
     */
    virtual void clear(Color color) = 0;

    /**
     * Presents any queued drawing to the visible display.
     */
    virtual void present() = 0;

    /**
     * Draws a straight line.
     *
     * @param x0 Start x coordinate.
     * @param y0 Start y coordinate.
     * @param x1 End x coordinate.
     * @param y1 End y coordinate.
     * @param color Line color.
     * @param thickness Approximate line thickness in pixels.
     */
    virtual void line(int x0, int y0, int x1, int y1, Color color, int thickness = 1) = 0;

    /**
     * Draws a circle outline.
     *
     * @param cx Center x coordinate.
     * @param cy Center y coordinate.
     * @param radius Circle radius in pixels.
     * @param color Outline color.
     * @param thickness Outline thickness in pixels.
     */
    virtual void circle(int cx, int cy, int radius, Color color, int thickness = 1) = 0;

    /**
     * Draws a filled circle.
     *
     * @param cx Center x coordinate.
     * @param cy Center y coordinate.
     * @param radius Circle radius in pixels.
     * @param color Fill color.
     */
    virtual void fillCircle(int cx, int cy, int radius, Color color) = 0;

    /**
     * Draws text using one of the fixed SteedPilot font sizes.
     *
     * @param x Anchor x coordinate.
     * @param y Top y coordinate.
     * @param value Null-terminated text to draw.
     * @param size Fixed font size identifier.
     * @param color Text color.
     * @param align Horizontal alignment relative to x.
     */
    virtual void text(int x, int y, const char* value, int size, Color color, TextAlign align = TextAlign::Left) = 0;
};

} // namespace SteedPilot
