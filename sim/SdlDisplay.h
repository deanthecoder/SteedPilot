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

#include <SDL.h>
#include <cstdint>
#include <vector>

class SdlDisplay final : public SteedPilot::Display {
public:
    /**
     * Creates an SDL-backed display window.
     *
     * @param width Logical display width.
     * @param height Logical display height.
     * @param scale Window scale factor.
     */
    SdlDisplay(int width, int height, int scale);

    /**
     * Releases SDL window and renderer resources.
     */
    ~SdlDisplay() override;

    /**
     * Checks whether SDL initialization completed successfully.
     *
     * @return True when the display can be used.
     */
    bool ok() const;

    /**
     * Processes pending SDL window events.
     *
     * @return False when the window should close.
     */
    bool poll();

    /**
     * Saves the most recently presented frame as a PNG.
     *
     * @param path Destination PNG path.
     * @return True when the file was written.
     */
    bool savePng(const char* path) const;

    int width() const override;
    int height() const override;

    void clear(SteedPilot::Color color) override;
    void present() override;

    void line(int x0, int y0, int x1, int y1, SteedPilot::Color color, int thickness = 1) override;
    void circle(int cx, int cy, int radius, SteedPilot::Color color, int thickness = 1) override;
    void arc(int cx, int cy, int radius, float startDegrees, float sweepDegrees, SteedPilot::Color color, int thickness = 1) override;
    void fillCircle(int cx, int cy, int radius, SteedPilot::Color color) override;
    void text(int x, int y, const char* value, int size, SteedPilot::Color color, SteedPilot::TextAlign align) override;

private:
    int _width;
    int _height;
    int _sampleScale = 3;
    SDL_Window* _window = nullptr;
    SDL_Renderer* _renderer = nullptr;
    SDL_Texture* _target = nullptr;
    SDL_Texture* _presentTexture = nullptr;
    std::vector<uint8_t> _lastFrame;

    int sx(int x) const;
    int sy(int y) const;
    int ss(int value) const;
    void setColor(SteedPilot::Color color);
};
