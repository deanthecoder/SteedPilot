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

#include "SteedPilot/FontAtlas.h"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {

const SteedPilotGlyph* glyphFor(char value, int size) {
    for (uint16_t i = 0; i < SteedPilotFontGlyphCount; ++i) {
        const SteedPilotGlyph* glyph = &SteedPilotFontGlyphs[i];
        if (glyph->ch == value && glyph->sizeId == size) {
            return glyph;
        }
    }

    return nullptr;
}

int textWidth(const char* value, int size) {
    int width = 0;
    for (const char* ch = value; *ch; ++ch) {
        const SteedPilotGlyph* glyph = glyphFor(*ch, size);
        if (glyph) {
            width += glyph->advance;
        }
    }

    return width;
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
    int drawX = x;
    if (align == SteedPilot::TextAlign::Center) {
        drawX -= textWidth(value, size) / 2;
    } else if (align == SteedPilot::TextAlign::Right) {
        drawX -= textWidth(value, size);
    }

    for (const char* ch = value; *ch; ++ch) {
        const SteedPilotGlyph* glyph = glyphFor(*ch, size);
        if (glyph) {
            const int glyphX = drawX + glyph->offsetX;
            const int glyphY = y + glyph->offsetY;

            for (int row = 0; row < glyph->h; ++row) {
                for (int col = 0; col < glyph->w; ++col) {
                    const int atlasIndex = (glyph->y + row) * SteedPilotFontAtlasWidth + glyph->x + col;
                    const uint8_t coverage = SteedPilotFontAtlasAlpha[atlasIndex];

                    if (coverage) {
                        SDL_SetRenderDrawColor(
                            _renderer,
                            (uint8_t)((color.r * coverage) / 255),
                            (uint8_t)((color.g * coverage) / 255),
                            (uint8_t)((color.b * coverage) / 255),
                            255
                        );
                        SDL_RenderDrawPoint(_renderer, glyphX + col, glyphY + row);
                    }
                }
            }

            drawX += glyph->advance;
        } else {
            drawX += size * 6;
        }
    }
}

void SdlDisplay::setColor(SteedPilot::Color color) {
    SDL_SetRenderDrawColor(_renderer, color.r, color.g, color.b, 255);
}
