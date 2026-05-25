// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

#include "FirmwareDisplay.h"

#include "I2C_Driver.h"
#include "SteedPilot/FontAtlas.h"
#include "SteedPilot/ImageAssets.h"
#include "TCA9554PWR.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_st77916.h"

#include "driver/spi_master.h"
#include "esp_heap_caps.h"

#include <Arduino.h>
#include <cmath>

namespace {

constexpr uint64_t LcdOpcodeWriteCommand = 0x02ULL;
constexpr uint64_t LcdOpcodeReadCommand = 0x0BULL;
constexpr uint64_t LcdOpcodeWriteColor = 0x32ULL;

uint8_t red565(uint16_t color) {
    return (uint8_t)(((color >> 11) & 0x1F) * 255 / 31);
}

uint8_t green565(uint16_t color) {
    return (uint8_t)(((color >> 5) & 0x3F) * 255 / 63);
}

uint8_t blue565(uint16_t color) {
    return (uint8_t)((color & 0x1F) * 255 / 31);
}

uint8_t coverageAlpha(int coveredSamples, int totalSamples) {
    if (coveredSamples <= 0) {
        return 0;
    }

    if (coveredSamples >= totalSamples) {
        return 255;
    }

    return (uint8_t)((coveredSamples * 255) / totalSamples);
}

float normalizeDegrees(float degrees) {
    while (degrees < 0.0f) {
        degrees += 360.0f;
    }

    while (degrees >= 360.0f) {
        degrees -= 360.0f;
    }

    return degrees;
}

bool angleInSweep(float degrees, float startDegrees, float sweepDegrees) {
    const float relative = normalizeDegrees(degrees - startDegrees);
    return relative <= sweepDegrees;
}

} // namespace

bool FirmwareDisplay::begin() {
    I2C_Init();
    TCA9554PWR_Init(0x00);
    resetDisplayViaExpander();

    pinMode(LcdTePin, OUTPUT);
    pinMode(LcdBacklightPin, OUTPUT);
    digitalWrite(LcdBacklightPin, HIGH);

    static const spi_bus_config_t busConfig = {
        .data0_io_num = LcdData0Pin,
        .data1_io_num = LcdData1Pin,
        .sclk_io_num = LcdSckPin,
        .data2_io_num = LcdData2Pin,
        .data3_io_num = LcdData3Pin,
        .data4_io_num = -1,
        .data5_io_num = -1,
        .data6_io_num = -1,
        .data7_io_num = -1,
        .max_transfer_sz = LcdSpiMaxTransferSize,
        .flags = SPICOMMON_BUSFLAG_MASTER,
        .intr_flags = 0,
    };

    if (spi_bus_initialize(SPI2_HOST, &busConfig, SPI_DMA_CH_AUTO) != ESP_OK) {
        Serial.println("SPI bus init failed");
        return false;
    }

    esp_lcd_panel_io_spi_config_t ioConfig = {
        .cs_gpio_num = LcdCsPin,
        .dc_gpio_num = -1,
        .spi_mode = 0,
        .pclk_hz = 40 * 1000 * 1000,
        .trans_queue_depth = 10,
        .on_color_trans_done = nullptr,
        .user_ctx = nullptr,
        .lcd_cmd_bits = 32,
        .lcd_param_bits = 8,
        .flags = {
            .quad_mode = true,
        },
    };

    esp_lcd_panel_io_handle_t io = nullptr;
    if (esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)SPI2_HOST, &ioConfig, &io) != ESP_OK) {
        Serial.println("LCD panel IO init failed");
        return false;
    }

    st77916_vendor_config_t vendorConfig = {
        .flags = {
            .use_qspi_interface = 1,
        },
    };

    esp_lcd_panel_dev_config_t panelConfig = {
        .reset_gpio_num = -1,
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB,
        .data_endian = LCD_RGB_DATA_ENDIAN_BIG,
        .bits_per_pixel = LcdColorBits,
        .flags = {
            .reset_active_high = 0,
        },
        .vendor_config = &vendorConfig,
    };

    if (esp_lcd_new_panel_st77916(io, &panelConfig, &_panel) != ESP_OK) {
        Serial.println("ST77916 panel init failed");
        return false;
    }

    if (esp_lcd_panel_reset(_panel) != ESP_OK || esp_lcd_panel_init(_panel) != ESP_OK) {
        Serial.println("ST77916 reset/init failed");
        return false;
    }

    esp_lcd_panel_disp_on_off(_panel, true);

    _frame = (uint16_t*)heap_caps_malloc(LcdWidth * LcdHeight * sizeof(uint16_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!_frame) {
        _frame = (uint16_t*)heap_caps_malloc(LcdWidth * LcdHeight * sizeof(uint16_t), MALLOC_CAP_8BIT);
    }

    if (!_frame) {
        Serial.println("Frame buffer allocation failed");
        return false;
    }

    return true;
}

void FirmwareDisplay::splash(uint8_t opacity) {
    clear(SteedPilot::Palette::Black);
    imageCentered(opacity);
    present();
}

int FirmwareDisplay::width() const {
    return LcdWidth;
}

int FirmwareDisplay::height() const {
    return LcdHeight;
}

void FirmwareDisplay::clear(SteedPilot::Color color) {
    const uint16_t swapped = __builtin_bswap16(rgb565(color));
    for (int i = 0; i < LcdWidth * LcdHeight; ++i) {
        _frame[i] = swapped;
    }
}

void FirmwareDisplay::present() {
    esp_lcd_panel_draw_bitmap(_panel, 0, 0, LcdWidth, LcdHeight, _frame);
}

void FirmwareDisplay::pixel(int x, int y, SteedPilot::Color color) {
    putPixel(x, y, rgb565(color));
}

void FirmwareDisplay::line(int x0, int y0, int x1, int y1, SteedPilot::Color color, int thickness) {
    const float radius = max(0.5f, (float)(thickness - 1) * 0.5f);
    const int boundsRadius = (int)ceilf(radius + 1.0f);
    const int minX = min(x0, x1) - boundsRadius;
    const int maxX = max(x0, x1) + boundsRadius;
    const int minY = min(y0, y1) - boundsRadius;
    const int maxY = max(y0, y1) + boundsRadius;
    const float dx = (float)(x1 - x0);
    const float dy = (float)(y1 - y0);
    const float len2 = dx * dx + dy * dy;

    if (len2 <= 0.0f) {
        fillCircle(x0, y0, (int)radius, color);
        return;
    }

    const float sampleOffsets[] = {-0.25f, 0.25f};
    constexpr int sampleCount = 2;
    constexpr int totalSamples = sampleCount * sampleCount;

    for (int y = minY; y <= maxY; ++y) {
        for (int x = minX; x <= maxX; ++x) {
            int coveredSamples = 0;
            for (int sampleY = 0; sampleY < sampleCount; ++sampleY) {
                for (int sampleX = 0; sampleX < sampleCount; ++sampleX) {
                    const float px = (float)x + sampleOffsets[sampleX];
                    const float py = (float)y + sampleOffsets[sampleY];
                    float t = ((px - (float)x0) * dx + (py - (float)y0) * dy) / len2;
                    if (t < 0.0f) {
                        t = 0.0f;
                    } else if (t > 1.0f) {
                        t = 1.0f;
                    }

                    const float nearestX = x0 + dx * t;
                    const float nearestY = y0 + dy * t;
                    const float distX = px - nearestX;
                    const float distY = py - nearestY;
                    if (distX * distX + distY * distY <= radius * radius) {
                        ++coveredSamples;
                    }
                }
            }

            if (coveredSamples) {
                maxPixel(x, y, color.r, color.g, color.b, coverageAlpha(coveredSamples, totalSamples));
            }
        }
    }
}

void FirmwareDisplay::circle(int cx, int cy, int radius, SteedPilot::Color color, int thickness) {
    const int brushRadius = max(1, (thickness + 1) / 2);
    const float stepDegrees = max(0.5f, 120.0f / (float)max(radius, 1));
    const int steps = max(1, (int)ceilf(360.0f / stepDegrees));

    for (int step = 0; step < steps; ++step) {
        const float degrees = 360.0f * (float)step / (float)steps;
        const float radians = (degrees - 90.0f) * PI / 180.0f;
        const int x = cx + (int)roundf(cosf(radians) * (float)radius);
        const int y = cy + (int)roundf(sinf(radians) * (float)radius);
        fillCircle(x, y, brushRadius, color);
    }
}

void FirmwareDisplay::arc(int cx, int cy, int radius, float startDegrees, float sweepDegrees, SteedPilot::Color color, int thickness) {
    if (sweepDegrees <= 0.0f) {
        return;
    }

    if (sweepDegrees >= 359.9f) {
        circle(cx, cy, radius, color, thickness);
        return;
    }

    const int brushRadius = max(1, (thickness + 1) / 2);
    const float stepDegrees = max(0.5f, 120.0f / (float)max(radius, 1));
    const int steps = max(0, (int)floorf(sweepDegrees / stepDegrees));

    for (int step = 0; step <= steps; ++step) {
        const float degrees = startDegrees + stepDegrees * (float)step;
        const float radians = (degrees - 90.0f) * PI / 180.0f;
        const int x = cx + (int)roundf(cosf(radians) * (float)radius);
        const int y = cy + (int)roundf(sinf(radians) * (float)radius);
        fillCircle(x, y, brushRadius, color);
    }
}

void FirmwareDisplay::fillCircle(int cx, int cy, int radius, SteedPilot::Color color) {
    const uint16_t packed = rgb565(color);
    for (int y = -radius; y <= radius; ++y) {
        for (int x = -radius; x <= radius; ++x) {
            if (x * x + y * y <= radius * radius) {
                putPixel(cx + x, cy + y, packed);
            }
        }
    }
}

void FirmwareDisplay::text(int x, int y, const char* value, int size, SteedPilot::Color color, SteedPilot::TextAlign align) {
    if (align == SteedPilot::TextAlign::Center) {
        x -= textWidth(value, size) / 2;
    } else if (align == SteedPilot::TextAlign::Right) {
        x -= textWidth(value, size);
    }

    for (const char* ch = value; *ch; ++ch) {
        const SteedPilotGlyph* glyph = glyphFor(*ch, size);
        if (glyph) {
            const int glyphX = x + glyph->offsetX;
            const int glyphY = y + glyph->offsetY;

            for (int row = 0; row < glyph->h; ++row) {
                for (int col = 0; col < glyph->w; ++col) {
                    const int atlasIndex = (glyph->y + row) * SteedPilotFontAtlasWidth + glyph->x + col;
                    const uint8_t coverage = SteedPilotFontAtlasAlpha[atlasIndex];
                    blendPixel(glyphX + col, glyphY + row, color.r, color.g, color.b, coverage);
                }
            }

            x += glyph->advance;
        }
    }
}

uint16_t FirmwareDisplay::rgb565(SteedPilot::Color color) const {
    return (uint16_t)(((color.r & 0xF8) << 8) | ((color.g & 0xFC) << 3) | (color.b >> 3));
}

void FirmwareDisplay::resetDisplayViaExpander() {
    Set_EXIO(EXIO_PIN2, Low);
    delay(10);
    Set_EXIO(EXIO_PIN2, High);
    delay(50);
}

void FirmwareDisplay::putPixel(int x, int y, uint16_t color) {
    if (x >= 0 && x < LcdWidth && y >= 0 && y < LcdHeight) {
        _frame[y * LcdWidth + x] = __builtin_bswap16(color);
    }
}

void FirmwareDisplay::image(int x, int y, const SteedPilotGrayAlphaImage& image, uint8_t opacity) {
    for (int row = 0; row < image.height; ++row) {
        for (int column = 0; column < image.width; ++column) {
            const uint8_t* pixel = image.pixels + (row * image.width + column) * 2;
            const uint8_t gray = pixel[0];
            const uint8_t alpha = (uint8_t)((pixel[1] * opacity) / 255);
            blendPixel(x + column, y + row, gray, gray, gray, alpha);
        }
    }
}

void FirmwareDisplay::blendPixel(int x, int y, uint8_t r, uint8_t g, uint8_t b, uint8_t alpha) {
    if (x < 0 || x >= LcdWidth || y < 0 || y >= LcdHeight || alpha == 0) {
        return;
    }

    if (alpha == 255) {
        putPixel(x, y, rgb565(SteedPilot::Color{r, g, b}));
        return;
    }

    const uint16_t existing = __builtin_bswap16(_frame[y * LcdWidth + x]);
    const uint8_t existingR = red565(existing);
    const uint8_t existingG = green565(existing);
    const uint8_t existingB = blue565(existing);
    const uint8_t outR = (uint8_t)((r * alpha + existingR * (255 - alpha)) / 255);
    const uint8_t outG = (uint8_t)((g * alpha + existingG * (255 - alpha)) / 255);
    const uint8_t outB = (uint8_t)((b * alpha + existingB * (255 - alpha)) / 255);

    putPixel(x, y, rgb565(SteedPilot::Color{outR, outG, outB}));
}

void FirmwareDisplay::maxPixel(int x, int y, uint8_t r, uint8_t g, uint8_t b, uint8_t alpha) {
    if (x < 0 || x >= LcdWidth || y < 0 || y >= LcdHeight || alpha == 0) {
        return;
    }

    const uint16_t existing = __builtin_bswap16(_frame[y * LcdWidth + x]);
    const uint8_t existingR = red565(existing);
    const uint8_t existingG = green565(existing);
    const uint8_t existingB = blue565(existing);
    const uint8_t outR = max(existingR, (uint8_t)((r * alpha) / 255));
    const uint8_t outG = max(existingG, (uint8_t)((g * alpha) / 255));
    const uint8_t outB = max(existingB, (uint8_t)((b * alpha) / 255));

    putPixel(x, y, rgb565(SteedPilot::Color{outR, outG, outB}));
}

void FirmwareDisplay::imageCentered(uint8_t opacity) {
    const SteedPilotGrayAlphaImage& image = SteedPilotDtcLogo;
    const int left = (LcdWidth - image.width) / 2;
    const int top = (LcdHeight - image.height) / 2 + 20;

    this->image(left, top, image, opacity);
}

const SteedPilotGlyph* FirmwareDisplay::glyphFor(char value, int size) const {
    for (uint16_t i = 0; i < SteedPilotFontGlyphCount; ++i) {
        const SteedPilotGlyph* glyph = &SteedPilotFontGlyphs[i];
        if (glyph->ch == value && glyph->sizeId == size) {
            return glyph;
        }
    }

    return nullptr;
}

int FirmwareDisplay::textWidth(const char* value, int size) const {
    int result = 0;
    for (const char* p = value; *p; ++p) {
        const SteedPilotGlyph* glyph = glyphFor(*p, size);
        if (glyph) {
            result += glyph->advance;
        }
    }

    return result;
}
