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
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
#include <zlib.h>

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

uint8_t paeth(uint8_t a, uint8_t b, uint8_t c) {
    const int p = (int)a + (int)b - (int)c;
    const int pa = std::abs(p - (int)a);
    const int pb = std::abs(p - (int)b);
    const int pc = std::abs(p - (int)c);

    if (pa <= pb && pa <= pc) {
        return a;
    }

    if (pb <= pc) {
        return b;
    }

    return c;
}

bool readFile(const char* path, std::vector<uint8_t>& data) {
    FILE* file = std::fopen(path, "rb");
    if (!file) {
        return false;
    }

    std::fseek(file, 0, SEEK_END);
    const long size = std::ftell(file);
    std::fseek(file, 0, SEEK_SET);

    if (size <= 0) {
        std::fclose(file);
        return false;
    }

    data.resize((size_t)size);
    const bool ok = std::fread(data.data(), 1, data.size(), file) == data.size();
    std::fclose(file);
    return ok;
}

uint32_t readU32(const uint8_t* data) {
    return ((uint32_t)data[0] << 24) | ((uint32_t)data[1] << 16) | ((uint32_t)data[2] << 8) | (uint32_t)data[3];
}

bool decodePng(const char* path, SdlImage& image) {
    std::vector<uint8_t> png;
    if (!readFile(path, png) || png.size() < 33) {
        return false;
    }

    const uint8_t signature[] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n'};
    if (std::memcmp(png.data(), signature, sizeof(signature)) != 0) {
        return false;
    }

    int width = 0;
    int height = 0;
    uint8_t bitDepth = 0;
    uint8_t colorType = 0;
    std::vector<uint8_t> idat;

    size_t offset = 8;
    while (offset + 12 <= png.size()) {
        const uint32_t length = readU32(png.data() + offset);
        offset += 4;
        if (offset + 4 + length + 4 > png.size()) {
            return false;
        }

        const char* type = (const char*)png.data() + offset;
        offset += 4;
        const uint8_t* chunk = png.data() + offset;

        if (std::memcmp(type, "IHDR", 4) == 0) {
            width = (int)readU32(chunk);
            height = (int)readU32(chunk + 4);
            bitDepth = chunk[8];
            colorType = chunk[9];
        } else if (std::memcmp(type, "IDAT", 4) == 0) {
            idat.insert(idat.end(), chunk, chunk + length);
        } else if (std::memcmp(type, "IEND", 4) == 0) {
            break;
        }

        offset += length + 4;
    }

    if (width <= 0 || height <= 0 || bitDepth != 8 || (colorType != 4 && colorType != 6) || idat.empty()) {
        return false;
    }

    const int bytesPerPixel = colorType == 4 ? 2 : 4;
    const int stride = width * bytesPerPixel;
    std::vector<uint8_t> filtered((size_t)(stride + 1) * height);
    uLongf filteredSize = (uLongf)filtered.size();

    if (uncompress(filtered.data(), &filteredSize, idat.data(), (uLong)idat.size()) != Z_OK || filteredSize != filtered.size()) {
        return false;
    }

    std::vector<uint8_t> raw((size_t)stride * height);
    for (int y = 0; y < height; ++y) {
        const uint8_t filter = filtered[(size_t)y * (stride + 1)];
        const uint8_t* src = filtered.data() + (size_t)y * (stride + 1) + 1;
        uint8_t* dst = raw.data() + (size_t)y * stride;
        const uint8_t* prev = y > 0 ? raw.data() + (size_t)(y - 1) * stride : nullptr;

        for (int x = 0; x < stride; ++x) {
            const uint8_t left = x >= bytesPerPixel ? dst[x - bytesPerPixel] : 0;
            const uint8_t up = prev ? prev[x] : 0;
            const uint8_t upLeft = prev && x >= bytesPerPixel ? prev[x - bytesPerPixel] : 0;
            uint8_t predictor = 0;

            if (filter == 1) {
                predictor = left;
            } else if (filter == 2) {
                predictor = up;
            } else if (filter == 3) {
                predictor = (uint8_t)(((int)left + (int)up) / 2);
            } else if (filter == 4) {
                predictor = paeth(left, up, upLeft);
            } else if (filter != 0) {
                return false;
            }

            dst[x] = (uint8_t)(src[x] + predictor);
        }
    }

    image.width = width;
    image.height = height;
    image.rgba.resize((size_t)width * height * 4);

    for (int i = 0; i < width * height; ++i) {
        const uint8_t* src = raw.data() + i * bytesPerPixel;
        uint8_t* dst = image.rgba.data() + i * 4;

        if (colorType == 4) {
            dst[0] = src[0];
            dst[1] = src[0];
            dst[2] = src[0];
            dst[3] = src[1];
        } else {
            dst[0] = src[0];
            dst[1] = src[1];
            dst[2] = src[2];
            dst[3] = src[3];
        }
    }

    return true;
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

    _target = SDL_CreateTexture(
        _renderer,
        SDL_PIXELFORMAT_RGBA32,
        SDL_TEXTUREACCESS_TARGET,
        width * _sampleScale,
        height * _sampleScale
    );

    if (!_target) {
        return;
    }

    _presentTexture = SDL_CreateTexture(
        _renderer,
        SDL_PIXELFORMAT_RGBA32,
        SDL_TEXTUREACCESS_STREAMING,
        width,
        height
    );

    if (!_presentTexture) {
        return;
    }

    SDL_SetRenderTarget(_renderer, _target);
    SDL_ShowWindow(_window);
    SDL_RaiseWindow(_window);
}

SdlDisplay::~SdlDisplay() {
    if (_presentTexture) {
        SDL_DestroyTexture(_presentTexture);
    }
    if (_target) {
        SDL_DestroyTexture(_target);
    }
    if (_renderer) {
        SDL_DestroyRenderer(_renderer);
    }
    if (_window) {
        SDL_DestroyWindow(_window);
    }
    SDL_Quit();
}

bool SdlDisplay::ok() const {
    return _window && _renderer && _target && _presentTexture;
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

bool SdlDisplay::loadPng(const char* path, SdlImage& image) const {
    return decodePng(path, image);
}

void SdlDisplay::drawImageCentered(const SdlImage& image, float opacity) {
    if (image.rgba.empty() || opacity <= 0.0f) {
        return;
    }

    if (opacity > 1.0f) {
        opacity = 1.0f;
    }

    const int left = (_width - image.width) / 2;
    const int top = (_height - image.height) / 2 + 20;

    SDL_SetRenderTarget(_renderer, _target);
    for (int y = 0; y < image.height; ++y) {
        for (int x = 0; x < image.width; ++x) {
            const uint8_t* pixel = image.rgba.data() + (y * image.width + x) * 4;
            const int alpha = (int)((float)pixel[3] * opacity);
            if (alpha <= 0) {
                continue;
            }

            SDL_SetRenderDrawColor(
                _renderer,
                (uint8_t)((pixel[0] * alpha) / 255),
                (uint8_t)((pixel[1] * alpha) / 255),
                (uint8_t)((pixel[2] * alpha) / 255),
                255
            );
            const SDL_Rect rect{sx(left + x), sy(top + y), ss(1), ss(1)};
            SDL_RenderFillRect(_renderer, &rect);
        }
    }
}

void SdlDisplay::image(int x, int y, const SteedPilotGrayAlphaImage& image, uint8_t opacity) {
    SDL_SetRenderTarget(_renderer, _target);
    for (int row = 0; row < image.height; ++row) {
        for (int column = 0; column < image.width; ++column) {
            const uint8_t* pixel = image.pixels + (row * image.width + column) * 2;
            const uint8_t gray = pixel[0];
            const int alpha = (int)((pixel[1] * opacity) / 255);
            if (alpha <= 0) {
                continue;
            }

            SDL_SetRenderDrawColor(
                _renderer,
                (uint8_t)((gray * alpha) / 255),
                (uint8_t)((gray * alpha) / 255),
                (uint8_t)((gray * alpha) / 255),
                255
            );
            const SDL_Rect rect{sx(x + column), sy(y + row), ss(1), ss(1)};
            SDL_RenderFillRect(_renderer, &rect);
        }
    }
}

int SdlDisplay::width() const {
    return _width;
}

int SdlDisplay::height() const {
    return _height;
}

void SdlDisplay::clear(SteedPilot::Color color) {
    SDL_SetRenderTarget(_renderer, _target);
    setColor(color);
    SDL_RenderClear(_renderer);
}

void SdlDisplay::present() {
    std::vector<uint8_t> supersampled((size_t)_width * _height * _sampleScale * _sampleScale * 4);
    SDL_SetRenderTarget(_renderer, _target);
    SDL_RenderReadPixels(_renderer, nullptr, SDL_PIXELFORMAT_RGBA32, supersampled.data(), _width * _sampleScale * 4);

    _lastFrame.resize((size_t)_width * _height * 4);
    for (int y = 0; y < _height; ++y) {
        for (int x = 0; x < _width; ++x) {
            int r = 0;
            int g = 0;
            int b = 0;
            int a = 0;

            for (int yy = 0; yy < _sampleScale; ++yy) {
                for (int xx = 0; xx < _sampleScale; ++xx) {
                    const int srcX = x * _sampleScale + xx;
                    const int srcY = y * _sampleScale + yy;
                    const int src = (srcY * _width * _sampleScale + srcX) * 4;
                    r += supersampled[src + 0];
                    g += supersampled[src + 1];
                    b += supersampled[src + 2];
                    a += supersampled[src + 3];
                }
            }

            const int count = _sampleScale * _sampleScale;
            const int dst = (y * _width + x) * 4;
            _lastFrame[dst + 0] = (uint8_t)(r / count);
            _lastFrame[dst + 1] = (uint8_t)(g / count);
            _lastFrame[dst + 2] = (uint8_t)(b / count);
            _lastFrame[dst + 3] = (uint8_t)(a / count);
        }
    }

    SDL_UpdateTexture(_presentTexture, nullptr, _lastFrame.data(), _width * 4);
    SDL_SetRenderTarget(_renderer, nullptr);
    SDL_RenderClear(_renderer);
    SDL_RenderCopy(_renderer, _presentTexture, nullptr, nullptr);
    SDL_RenderPresent(_renderer);
    SDL_SetRenderTarget(_renderer, _target);
}

void SdlDisplay::line(int x0, int y0, int x1, int y1, SteedPilot::Color color, int thickness) {
    setColor(color);
    const int radius = ss(std::max(1, thickness)) / 2;
    const int startX = sx(x0);
    const int startY = sy(y0);
    const int endX = sx(x1);
    const int endY = sy(y1);
    const int minX = std::min(startX, endX) - radius - 1;
    const int maxX = std::max(startX, endX) + radius + 1;
    const int minY = std::min(startY, endY) - radius - 1;
    const int maxY = std::max(startY, endY) + radius + 1;
    const float dx = (float)(endX - startX);
    const float dy = (float)(endY - startY);
    const float len2 = dx * dx + dy * dy;

    if (len2 <= 0.0f) {
        fillCircle(x0, y0, thickness / 2, color);
        return;
    }

    for (int y = minY; y <= maxY; ++y) {
        for (int x = minX; x <= maxX; ++x) {
            float t = ((x - startX) * dx + (y - startY) * dy) / len2;
            if (t < 0.0f) {
                t = 0.0f;
            } else if (t > 1.0f) {
                t = 1.0f;
            }

            const float nearestX = startX + dx * t;
            const float nearestY = startY + dy * t;
            const float distX = x - nearestX;
            const float distY = y - nearestY;

            if (distX * distX + distY * distY <= radius * radius) {
                SDL_RenderDrawPoint(_renderer, x, y);
            }
        }
    }
}

void SdlDisplay::circle(int cx, int cy, int radius, SteedPilot::Color color, int thickness) {
    setColor(color);
    thickness = std::max(1, thickness);

    for (int t = 0; t < thickness; ++t) {
        const int r = ss(radius) - t;
        int x = r - 1;
        int y = 0;
        int dx = 1;
        int dy = 1;
        int err = dx - (r << 1);

        while (x >= y) {
            SDL_RenderDrawPoint(_renderer, sx(cx) + x, sy(cy) + y);
            SDL_RenderDrawPoint(_renderer, sx(cx) + y, sy(cy) + x);
            SDL_RenderDrawPoint(_renderer, sx(cx) - y, sy(cy) + x);
            SDL_RenderDrawPoint(_renderer, sx(cx) - x, sy(cy) + y);
            SDL_RenderDrawPoint(_renderer, sx(cx) - x, sy(cy) - y);
            SDL_RenderDrawPoint(_renderer, sx(cx) - y, sy(cy) - x);
            SDL_RenderDrawPoint(_renderer, sx(cx) + y, sy(cy) - x);
            SDL_RenderDrawPoint(_renderer, sx(cx) + x, sy(cy) - y);

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

void SdlDisplay::arc(int cx, int cy, int radius, float startDegrees, float sweepDegrees, SteedPilot::Color color, int thickness) {
    if (sweepDegrees <= 0.0f) {
        return;
    }

    if (sweepDegrees > 360.0f) {
        sweepDegrees = 360.0f;
    }

    const int steps = std::max(8, (int)(std::abs(sweepDegrees) * radius / 90.0f));
    int previousX = 0;
    int previousY = 0;

    for (int i = 0; i <= steps; ++i) {
        const float p = (float)i / (float)steps;
        const float degrees = startDegrees + sweepDegrees * p;
        const float radians = (degrees - 90.0f) * 3.14159265358979323846f / 180.0f;
        const int x = cx + (int)(std::cos(radians) * radius);
        const int y = cy + (int)(std::sin(radians) * radius);

        if (i > 0) {
            line(previousX, previousY, x, y, color, thickness);
        }

        previousX = x;
        previousY = y;
    }
}

void SdlDisplay::fillCircle(int cx, int cy, int radius, SteedPilot::Color color) {
    setColor(color);
    const int scaledRadius = ss(radius);
    for (int y = -scaledRadius; y <= scaledRadius; ++y) {
        for (int x = -scaledRadius; x <= scaledRadius; ++x) {
            if (x * x + y * y <= scaledRadius * scaledRadius) {
                SDL_RenderDrawPoint(_renderer, sx(cx) + x, sy(cy) + y);
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
                        const SDL_Rect pixel{sx(glyphX + col), sy(glyphY + row), ss(1), ss(1)};
                        SDL_RenderFillRect(_renderer, &pixel);
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

int SdlDisplay::sx(int x) const {
    return x * _sampleScale;
}

int SdlDisplay::sy(int y) const {
    return y * _sampleScale;
}

int SdlDisplay::ss(int value) const {
    return value * _sampleScale;
}
