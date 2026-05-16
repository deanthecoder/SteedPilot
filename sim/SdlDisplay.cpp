// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

#include "SdlDisplay.h"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {

constexpr uint8_t Font[10][7] = {
    {0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E},
    {0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E},
    {0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F},
    {0x1E, 0x01, 0x01, 0x0E, 0x01, 0x01, 0x1E},
    {0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02},
    {0x1F, 0x10, 0x10, 0x1E, 0x01, 0x01, 0x1E},
    {0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E},
    {0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08},
    {0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E},
    {0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C},
};

constexpr uint8_t Letter[][7] = {
    {0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11}, // A
    {0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E}, // B
    {0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E}, // C
    {0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E}, // D
    {0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F}, // E
    {0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10}, // F
    {0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F}, // G
    {0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11}, // H
    {0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E}, // I
    {0x01, 0x01, 0x01, 0x01, 0x11, 0x11, 0x0E}, // J
    {0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11}, // K
    {0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F}, // L
    {0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11}, // M
    {0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11}, // N
    {0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E}, // O
    {0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10}, // P
    {0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D}, // Q
    {0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11}, // R
    {0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E}, // S
    {0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04}, // T
    {0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E}, // U
    {0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04}, // V
    {0x11, 0x11, 0x11, 0x15, 0x15, 0x1B, 0x11}, // W
    {0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11}, // X
    {0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04}, // Y
    {0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F}, // Z
};

const uint8_t* glyphFor(char value) {
    if (value >= '0' && value <= '9') {
        return Font[value - '0'];
    }

    if (value >= 'a' && value <= 'z') {
        value = (char)(value - 'a' + 'A');
    }

    if (value >= 'A' && value <= 'Z') {
        return Letter[value - 'A'];
    }

    if (value == '.') {
        static constexpr uint8_t Dot[7] = {0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C};
        return Dot;
    }

    return nullptr;
}

int textWidth(const char* value, int size) {
    return (int)std::strlen(value) * 6 * size;
}

void writeU32(std::vector<uint8_t>& out, uint32_t value) {
    out.push_back((uint8_t)(value >> 24));
    out.push_back((uint8_t)(value >> 16));
    out.push_back((uint8_t)(value >> 8));
    out.push_back((uint8_t)value);
}

uint32_t crc32(const uint8_t* data, int length) {
    uint32_t crc = 0xFFFFFFFFu;

    for (int i = 0; i < length; ++i) {
        crc ^= data[i];
        for (int bit = 0; bit < 8; ++bit) {
            crc = (crc >> 1) ^ (0xEDB88320u & (uint32_t)(-(int)(crc & 1)));
        }
    }

    return ~crc;
}

uint32_t adler32(const std::vector<uint8_t>& data) {
    uint32_t a = 1;
    uint32_t b = 0;

    for (uint8_t value : data) {
        a = (a + value) % 65521;
        b = (b + a) % 65521;
    }

    return (b << 16) | a;
}

void writeChunk(std::vector<uint8_t>& png, const char* type, const std::vector<uint8_t>& data) {
    writeU32(png, (uint32_t)data.size());

    const size_t typeStart = png.size();
    png.push_back((uint8_t)type[0]);
    png.push_back((uint8_t)type[1]);
    png.push_back((uint8_t)type[2]);
    png.push_back((uint8_t)type[3]);
    png.insert(png.end(), data.begin(), data.end());

    writeU32(png, crc32(png.data() + typeStart, (int)(png.size() - typeStart)));
}

std::vector<uint8_t> makeStoredZlib(const std::vector<uint8_t>& raw) {
    std::vector<uint8_t> zlib;
    zlib.push_back(0x78);
    zlib.push_back(0x01);

    size_t offset = 0;
    while (offset < raw.size()) {
        const uint16_t blockSize = (uint16_t)std::min((size_t)65535, raw.size() - offset);
        const bool finalBlock = offset + blockSize == raw.size();

        zlib.push_back(finalBlock ? 0x01 : 0x00);
        zlib.push_back((uint8_t)(blockSize & 0xFF));
        zlib.push_back((uint8_t)(blockSize >> 8));
        zlib.push_back((uint8_t)(~blockSize & 0xFF));
        zlib.push_back((uint8_t)(~blockSize >> 8));
        zlib.insert(zlib.end(), raw.begin() + offset, raw.begin() + offset + blockSize);

        offset += blockSize;
    }

    writeU32(zlib, adler32(raw));
    return zlib;
}

bool writePng(const char* path, int width, int height, const std::vector<uint8_t>& rgba) {
    std::vector<uint8_t> raw;
    raw.reserve((size_t)(width * 4 + 1) * height);

    for (int y = 0; y < height; ++y) {
        raw.push_back(0);
        const uint8_t* row = rgba.data() + y * width * 4;
        raw.insert(raw.end(), row, row + width * 4);
    }

    std::vector<uint8_t> png;
    const uint8_t signature[] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n'};
    png.insert(png.end(), signature, signature + sizeof(signature));

    std::vector<uint8_t> ihdr;
    writeU32(ihdr, (uint32_t)width);
    writeU32(ihdr, (uint32_t)height);
    ihdr.push_back(8);
    ihdr.push_back(6);
    ihdr.push_back(0);
    ihdr.push_back(0);
    ihdr.push_back(0);
    writeChunk(png, "IHDR", ihdr);
    writeChunk(png, "IDAT", makeStoredZlib(raw));
    writeChunk(png, "IEND", {});

    FILE* file = std::fopen(path, "wb");
    if (!file) {
        return false;
    }

    const bool ok = std::fwrite(png.data(), 1, png.size(), file) == png.size();
    std::fclose(file);
    return ok;
}

} // namespace

SdlDisplay::SdlDisplay(int width, int height, int scale) : _width(width), _height(height) {
    SDL_SetHint(SDL_HINT_MAC_BACKGROUND_APP, "0");
    SDL_SetHint(SDL_HINT_VIDEO_HIGHDPI_DISABLED, "1");

    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        return;
    }

    _window = SDL_CreateWindow(
        "SteedPilot Sim",
        SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED,
        width * scale,
        height * scale,
        SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE
    );

    if (!_window) {
        return;
    }

    _renderer = SDL_CreateRenderer(_window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!_renderer) {
        return;
    }

    SDL_RenderSetLogicalSize(_renderer, width, height);
    SDL_RenderSetIntegerScale(_renderer, SDL_TRUE);
    SDL_ShowWindow(_window);
    SDL_RaiseWindow(_window);
}

SdlDisplay::~SdlDisplay() {
    if (_renderer) {
        SDL_DestroyRenderer(_renderer);
    }
    if (_window) {
        SDL_DestroyWindow(_window);
    }
    SDL_Quit();
}

bool SdlDisplay::ok() const {
    return _window && _renderer;
}

bool SdlDisplay::poll() {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
        if (event.type == SDL_QUIT) {
            return false;
        }

        if (event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE) {
            return false;
        }
    }

    return true;
}

bool SdlDisplay::savePng(const char* path) const {
    if (_lastFrame.empty()) {
        return false;
    }

    return writePng(path, _width, _height, _lastFrame);
}

int SdlDisplay::width() const {
    return _width;
}

int SdlDisplay::height() const {
    return _height;
}

void SdlDisplay::clear(SteedPilot::Color color) {
    setColor(color);
    SDL_RenderClear(_renderer);
}

void SdlDisplay::present() {
    _lastFrame.resize((size_t)_width * _height * 4);
    SDL_RenderReadPixels(_renderer, nullptr, SDL_PIXELFORMAT_RGBA32, _lastFrame.data(), _width * 4);
    SDL_RenderPresent(_renderer);
}

void SdlDisplay::line(int x0, int y0, int x1, int y1, SteedPilot::Color color, int thickness) {
    setColor(color);
    thickness = std::max(1, thickness);
    const int offset = thickness / 2;

    for (int i = -offset; i <= offset; ++i) {
        SDL_RenderDrawLine(_renderer, x0 + i, y0, x1 + i, y1);
        SDL_RenderDrawLine(_renderer, x0, y0 + i, x1, y1 + i);
    }
}

void SdlDisplay::circle(int cx, int cy, int radius, SteedPilot::Color color, int thickness) {
    setColor(color);
    thickness = std::max(1, thickness);

    for (int t = 0; t < thickness; ++t) {
        const int r = radius - t;
        int x = r - 1;
        int y = 0;
        int dx = 1;
        int dy = 1;
        int err = dx - (r << 1);

        while (x >= y) {
            SDL_RenderDrawPoint(_renderer, cx + x, cy + y);
            SDL_RenderDrawPoint(_renderer, cx + y, cy + x);
            SDL_RenderDrawPoint(_renderer, cx - y, cy + x);
            SDL_RenderDrawPoint(_renderer, cx - x, cy + y);
            SDL_RenderDrawPoint(_renderer, cx - x, cy - y);
            SDL_RenderDrawPoint(_renderer, cx - y, cy - x);
            SDL_RenderDrawPoint(_renderer, cx + y, cy - x);
            SDL_RenderDrawPoint(_renderer, cx + x, cy - y);

            if (err <= 0) {
                ++y;
                err += dy;
                dy += 2;
            }

            if (err > 0) {
                --x;
                dx += 2;
                err += dx - (r << 1);
            }
        }
    }
}

void SdlDisplay::fillCircle(int cx, int cy, int radius, SteedPilot::Color color) {
    setColor(color);
    for (int y = -radius; y <= radius; ++y) {
        for (int x = -radius; x <= radius; ++x) {
            if (x * x + y * y <= radius * radius) {
                SDL_RenderDrawPoint(_renderer, cx + x, cy + y);
            }
        }
    }
}

void SdlDisplay::text(int x, int y, const char* value, int size, SteedPilot::Color color, SteedPilot::TextAlign align) {
    setColor(color);

    int drawX = x;
    if (align == SteedPilot::TextAlign::Center) {
        drawX -= textWidth(value, size) / 2;
    } else if (align == SteedPilot::TextAlign::Right) {
        drawX -= textWidth(value, size);
    }

    for (const char* ch = value; *ch; ++ch) {
        const uint8_t* glyph = glyphFor(*ch);
        if (glyph) {
            for (int row = 0; row < 7; ++row) {
                for (int col = 0; col < 5; ++col) {
                    if (glyph[row] & (1 << (4 - col))) {
                        SDL_Rect rect{drawX + col * size, y + row * size, size, size};
                        SDL_RenderFillRect(_renderer, &rect);
                    }
                }
            }
        }

        drawX += 6 * size;
    }
}

void SdlDisplay::setColor(SteedPilot::Color color) {
    SDL_SetRenderDrawColor(_renderer, color.r, color.g, color.b, 255);
}
