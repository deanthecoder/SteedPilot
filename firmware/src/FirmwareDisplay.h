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

#include "SteedPilot/Display.h"
#include "SteedPilot/FontAtlas.h"

#include "esp_lcd_panel_ops.h"

#include <cstdint>

/**
 * SteedPilot display implementation backed by the Waveshare ESP32-S3 LCD.
 */
class FirmwareDisplay final : public SteedPilot::Display {
public:
    /**
     * Initialises the panel, backlight, SPI bus, and framebuffer.
     *
     * @return True when the display is ready to render.
     */
    bool begin();

    /**
     * Draws the startup logo at the given opacity and presents it immediately.
     *
     * @param opacity Logo opacity from 0 to 255.
     */
    void splash(uint8_t opacity);

    /**
     * Enables or disables the LCD panel and backlight for low-power idle periods.
     *
     * @param awake True to show the panel, false to blank it.
     */
    void setAwake(bool awake);

    /**
     * Gets whether the panel/backlight are currently enabled.
     *
     * @return True when the display is awake.
     */
    bool isAwake() const;

    /**
     * Gets the display width in pixels.
     *
     * @return Display width.
     */
    int width() const override;

    /**
     * Gets the display height in pixels.
     *
     * @return Display height.
     */
    int height() const override;

    /**
     * Clears the framebuffer to a single color.
     *
     * @param color Fill color.
     */
    void clear(SteedPilot::Color color) override;

    /**
     * Pushes the framebuffer to the LCD panel.
     */
    void present() override;

    /**
     * Draws one logical pixel into the framebuffer.
     *
     * @param x Pixel x coordinate.
     * @param y Pixel y coordinate.
     * @param color Pixel color.
     */
    void pixel(int x, int y, SteedPilot::Color color) override;

    /**
     * Draws an anti-aliased line into the framebuffer.
     *
     * @param x0 Start x coordinate.
     * @param y0 Start y coordinate.
     * @param x1 End x coordinate.
     * @param y1 End y coordinate.
     * @param color Line color.
     * @param thickness Approximate line thickness in pixels.
     */
    void line(int x0, int y0, int x1, int y1, SteedPilot::Color color, int thickness = 1) override;

    /**
     * Draws an anti-aliased circle outline into the framebuffer.
     *
     * @param cx Center x coordinate.
     * @param cy Center y coordinate.
     * @param radius Circle radius in pixels.
     * @param color Outline color.
     * @param thickness Outline thickness in pixels.
     */
    void circle(int cx, int cy, int radius, SteedPilot::Color color, int thickness = 1) override;

    /**
     * Draws an anti-aliased clockwise arc into the framebuffer.
     *
     * @param cx Center x coordinate.
     * @param cy Center y coordinate.
     * @param radius Arc radius in pixels.
     * @param startDegrees Start angle in degrees, where 0 points up.
     * @param sweepDegrees Clockwise sweep in degrees.
     * @param color Arc color.
     * @param thickness Arc thickness in pixels.
     */
    void arc(int cx, int cy, int radius, float startDegrees, float sweepDegrees, SteedPilot::Color color, int thickness = 1) override;

    /**
     * Draws a filled circle into the framebuffer.
     *
     * @param cx Center x coordinate.
     * @param cy Center y coordinate.
     * @param radius Circle radius in pixels.
     * @param color Fill color.
     */
    void fillCircle(int cx, int cy, int radius, SteedPilot::Color color) override;

    /**
     * Draws a generated grey plus alpha image into the framebuffer.
     *
     * @param x Left edge x coordinate.
     * @param y Top edge y coordinate.
     * @param image Generated image data.
     * @param opacity Image opacity from 0 to 255.
     */
    void image(int x, int y, const SteedPilotGrayAlphaImage& image, uint8_t opacity = 255) override;

    /**
     * Draws atlas-backed text into the framebuffer.
     *
     * @param x Anchor x coordinate.
     * @param y Top y coordinate.
     * @param value Null-terminated text to draw.
     * @param size Fixed font size identifier.
     * @param color Text color.
     * @param align Horizontal alignment relative to x.
     */
    void text(int x, int y, const char* value, int size, SteedPilot::Color color, SteedPilot::TextAlign align = SteedPilot::TextAlign::Left) override;

private:
    static constexpr int LcdWidth = 360;
    static constexpr int LcdHeight = 360;
    static constexpr int LcdColorBits = 16;
    static constexpr int LcdBacklightPin = 5;
    static constexpr int LcdTePin = 18;
    static constexpr int LcdSckPin = 40;
    static constexpr int LcdData0Pin = 46;
    static constexpr int LcdData1Pin = 45;
    static constexpr int LcdData2Pin = 42;
    static constexpr int LcdData3Pin = 41;
    static constexpr int LcdCsPin = 21;
    static constexpr int LcdSpiMaxTransferSize = 2048;

    esp_lcd_panel_handle_t _panel = nullptr;
    uint16_t* _frame = nullptr;
    bool _awake = false;

    uint16_t rgb565(SteedPilot::Color color) const;
    void resetDisplayViaExpander();
    void putPixel(int x, int y, uint16_t color);
    void blendPixel(int x, int y, uint8_t r, uint8_t g, uint8_t b, uint8_t alpha);
    void maxPixel(int x, int y, uint8_t r, uint8_t g, uint8_t b, uint8_t alpha);
    void imageCentered(uint8_t opacity);
    const SteedPilotGlyph* glyphFor(char value, int size) const;
    int textWidth(const char* value, int size) const;
};
