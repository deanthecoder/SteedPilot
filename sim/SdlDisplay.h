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
    SdlDisplay(int width, int height, int scale);
    ~SdlDisplay() override;

    bool ok() const;
    bool poll();
    bool savePng(const char* path) const;

    int width() const override;
    int height() const override;

    void clear(SteedPilot::Color color) override;
    void present() override;

    void line(int x0, int y0, int x1, int y1, SteedPilot::Color color, int thickness = 1) override;
    void circle(int cx, int cy, int radius, SteedPilot::Color color, int thickness = 1) override;
    void fillCircle(int cx, int cy, int radius, SteedPilot::Color color) override;
    void text(int x, int y, const char* value, int size, SteedPilot::Color color, SteedPilot::TextAlign align) override;

private:
    int _width;
    int _height;
    SDL_Window* _window = nullptr;
    SDL_Renderer* _renderer = nullptr;
    std::vector<uint8_t> _lastFrame;

    void setColor(SteedPilot::Color color);
};
