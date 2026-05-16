// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

#include <Arduino.h>

#include "I2C_Driver.h"
#include "TCA9554PWR.h"
#include "SteedPilot/FontAtlas.h"
#include "SteedPilot/ImageAssets.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_st77916.h"

#include "driver/spi_master.h"
#include "esp_heap_caps.h"

namespace {

constexpr int LCD_WIDTH = 360;
constexpr int LCD_HEIGHT = 360;
constexpr int LCD_COLOR_BITS = 16;

constexpr int LCD_BACKLIGHT_PIN = 5;
constexpr int LCD_TE_PIN = 18;
constexpr int LCD_SCK_PIN = 40;
constexpr int LCD_DATA0_PIN = 46;
constexpr int LCD_DATA1_PIN = 45;
constexpr int LCD_DATA2_PIN = 42;
constexpr int LCD_DATA3_PIN = 41;
constexpr int LCD_CS_PIN = 21;
constexpr int LCD_SPI_MAX_TRANSFER_SIZE = 2048;
constexpr int INSTRUCTION_Y = 240;
constexpr int DISTANCE_Y = 260;
constexpr int UNIT_Y = 318;
constexpr int GRAPHIC_OFFSET_Y = 15;
constexpr float PROGRESS_START_DEGREES = -130.0f;
constexpr float PROGRESS_SWEEP_DEGREES = 260.0f;

constexpr uint64_t LCD_OPCODE_WRITE_CMD = 0x02ULL;
constexpr uint64_t LCD_OPCODE_READ_CMD = 0x0BULL;
constexpr uint64_t LCD_OPCODE_WRITE_COLOR = 0x32ULL;

esp_lcd_panel_handle_t g_panel = nullptr;
uint16_t* g_line = nullptr;
uint16_t* g_frame = nullptr;

uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b) {
    return (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3));
}

void resetDisplayViaExpander() {
    Set_EXIO(EXIO_PIN2, Low);
    delay(10);
    Set_EXIO(EXIO_PIN2, High);
    delay(50);
}

bool initDisplay() {
    I2C_Init();
    TCA9554PWR_Init(0x00);
    resetDisplayViaExpander();

    pinMode(LCD_TE_PIN, OUTPUT);
    pinMode(LCD_BACKLIGHT_PIN, OUTPUT);
    digitalWrite(LCD_BACKLIGHT_PIN, HIGH);

    static const spi_bus_config_t busConfig = {
        .data0_io_num = LCD_DATA0_PIN,
        .data1_io_num = LCD_DATA1_PIN,
        .sclk_io_num = LCD_SCK_PIN,
        .data2_io_num = LCD_DATA2_PIN,
        .data3_io_num = LCD_DATA3_PIN,
        .data4_io_num = -1,
        .data5_io_num = -1,
        .data6_io_num = -1,
        .data7_io_num = -1,
        .max_transfer_sz = LCD_SPI_MAX_TRANSFER_SIZE,
        .flags = SPICOMMON_BUSFLAG_MASTER,
        .intr_flags = 0,
    };

    if (spi_bus_initialize(SPI2_HOST, &busConfig, SPI_DMA_CH_AUTO) != ESP_OK) {
        Serial.println("SPI bus init failed");
        return false;
    }

    esp_lcd_panel_io_spi_config_t ioConfig = {
        .cs_gpio_num = LCD_CS_PIN,
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
        .bits_per_pixel = LCD_COLOR_BITS,
        .flags = {
            .reset_active_high = 0,
        },
        .vendor_config = &vendorConfig,
    };

    if (esp_lcd_new_panel_st77916(io, &panelConfig, &g_panel) != ESP_OK) {
        Serial.println("ST77916 panel init failed");
        return false;
    }

    if (esp_lcd_panel_reset(g_panel) != ESP_OK || esp_lcd_panel_init(g_panel) != ESP_OK) {
        Serial.println("ST77916 reset/init failed");
        return false;
    }

    esp_lcd_panel_disp_on_off(g_panel, true);

    g_line = (uint16_t*)heap_caps_malloc(LCD_WIDTH * sizeof(uint16_t), MALLOC_CAP_DMA);
    if (!g_line) {
        Serial.println("Line buffer allocation failed");
        return false;
    }

    g_frame = (uint16_t*)heap_caps_malloc(LCD_WIDTH * LCD_HEIGHT * sizeof(uint16_t), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!g_frame) {
        g_frame = (uint16_t*)heap_caps_malloc(LCD_WIDTH * LCD_HEIGHT * sizeof(uint16_t), MALLOC_CAP_8BIT);
    }

    if (!g_frame) {
        Serial.println("Frame buffer allocation failed");
        return false;
    }

    return true;
}

void drawPixelToLine(uint16_t* line, int x, uint16_t color) {
    if (x >= 0 && x < LCD_WIDTH) {
        line[x] = __builtin_bswap16(color);
    }
}

void drawCalibration() {
    const int cx = LCD_WIDTH / 2;
    const int cy = LCD_HEIGHT / 2;
    const uint16_t black = rgb565(0, 0, 0);
    const uint16_t dim = rgb565(55, 68, 72);
    const uint16_t cyan = rgb565(58, 206, 212);
    const uint16_t green = rgb565(118, 220, 130);
    const uint16_t amber = rgb565(255, 184, 77);
    const uint16_t red = rgb565(236, 83, 74);
    const uint16_t magenta = rgb565(210, 84, 230);
    const uint16_t white = rgb565(245, 248, 242);

    for (int y = 0; y < LCD_HEIGHT; ++y) {
        for (int x = 0; x < LCD_WIDTH; ++x) {
            uint16_t color = black;
            const int dx = x - cx;
            const int dy = y - cy;
            const int d2 = dx * dx + dy * dy;

            for (int r = 30; r <= 120; r += 30) {
                const int delta = abs(d2 - r * r);
                if (delta < r * 3) {
                    color = dim;
                }
            }

            const int safeDelta = abs(d2 - 150 * 150);
            if (safeDelta < 150 * 3) {
                color = green;
            }

            const int outerDelta = abs(d2 - 160 * 160);
            if (outerDelta < 160 * 3) {
                color = amber;
            }

            const int warningDelta = abs(d2 - 170 * 170);
            if (warningDelta < 170 * 3) {
                color = red;
            }

            const int cropDelta = abs(d2 - 176 * 176);
            if (cropDelta < 176 * 2) {
                color = magenta;
            }

            if (x == cx || y == cy || x == y || x == LCD_WIDTH - 1 - y) {
                color = cyan;
            }

            const bool cardinalTick =
                ((abs(x - cx) <= 2 && (abs(abs(y - cy) - 150) <= 8 || abs(abs(y - cy) - 160) <= 8 || abs(abs(y - cy) - 170) <= 8)) ||
                 (abs(y - cy) <= 2 && (abs(abs(x - cx) - 150) <= 8 || abs(abs(x - cx) - 160) <= 8 || abs(abs(x - cx) - 170) <= 8)));

            if (cardinalTick) {
                color = white;
            }

            if ((x >= cx - 24 && x <= cx + 24 && y >= cy - 10 && y <= cy + 10) &&
                (x == cx - 24 || x == cx + 24 || y == cy - 10 || y == cy + 10)) {
                color = white;
            }

            g_line[x] = __builtin_bswap16(color);
        }

        esp_lcd_panel_draw_bitmap(g_panel, 0, y, LCD_WIDTH, y + 1, g_line);
    }
}

void clearFrame(uint16_t color) {
    const uint16_t swapped = __builtin_bswap16(color);
    for (int i = 0; i < LCD_WIDTH * LCD_HEIGHT; ++i) {
        g_frame[i] = swapped;
    }
}

void putPixel(int x, int y, uint16_t color) {
    if (x >= 0 && x < LCD_WIDTH && y >= 0 && y < LCD_HEIGHT) {
        g_frame[y * LCD_WIDTH + x] = __builtin_bswap16(color);
    }
}

uint8_t red565(uint16_t color) {
    return (uint8_t)(((color >> 11) & 0x1F) * 255 / 31);
}

uint8_t green565(uint16_t color) {
    return (uint8_t)(((color >> 5) & 0x3F) * 255 / 63);
}

uint8_t blue565(uint16_t color) {
    return (uint8_t)((color & 0x1F) * 255 / 31);
}

void blendPixel(int x, int y, uint8_t r, uint8_t g, uint8_t b, uint8_t alpha) {
    if (x < 0 || x >= LCD_WIDTH || y < 0 || y >= LCD_HEIGHT || alpha == 0) {
        return;
    }

    if (alpha == 255) {
        putPixel(x, y, rgb565(r, g, b));
        return;
    }

    const uint16_t existing = __builtin_bswap16(g_frame[y * LCD_WIDTH + x]);
    const uint8_t existingR = red565(existing);
    const uint8_t existingG = green565(existing);
    const uint8_t existingB = blue565(existing);
    const uint8_t outR = (uint8_t)((r * alpha + existingR * (255 - alpha)) / 255);
    const uint8_t outG = (uint8_t)((g * alpha + existingG * (255 - alpha)) / 255);
    const uint8_t outB = (uint8_t)((b * alpha + existingB * (255 - alpha)) / 255);

    putPixel(x, y, rgb565(outR, outG, outB));
}

void maxPixel(int x, int y, uint8_t r, uint8_t g, uint8_t b, uint8_t alpha) {
    if (x < 0 || x >= LCD_WIDTH || y < 0 || y >= LCD_HEIGHT || alpha == 0) {
        return;
    }

    const uint16_t existing = __builtin_bswap16(g_frame[y * LCD_WIDTH + x]);
    const uint8_t existingR = red565(existing);
    const uint8_t existingG = green565(existing);
    const uint8_t existingB = blue565(existing);
    const uint8_t outR = max(existingR, (uint8_t)((r * alpha) / 255));
    const uint8_t outG = max(existingG, (uint8_t)((g * alpha) / 255));
    const uint8_t outB = max(existingB, (uint8_t)((b * alpha) / 255));

    putPixel(x, y, rgb565(outR, outG, outB));
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

void fillCircleFrame(int cx, int cy, int radius, uint16_t color) {
    for (int y = -radius; y <= radius; ++y) {
        for (int x = -radius; x <= radius; ++x) {
            if (x * x + y * y <= radius * radius) {
                putPixel(cx + x, cy + y, color);
            }
        }
    }
}

void thickLineFrame(int x0, int y0, int x1, int y1, uint16_t color, int thickness) {
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
        fillCircleFrame(x0, y0, (int)radius, color);
        return;
    }

    const uint8_t r = red565(color);
    const uint8_t g = green565(color);
    const uint8_t b = blue565(color);
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
                maxPixel(x, y, r, g, b, coverageAlpha(coveredSamples, totalSamples));
            }
        }
    }
}

void circleFrame(int cx, int cy, int radius, uint16_t color, int thickness) {
    const float half = max(0.5f, (float)(thickness - 1) * 0.5f);
    const int boundsRadius = radius + (int)ceilf(half + 1.0f);
    const uint8_t r = red565(color);
    const uint8_t g = green565(color);
    const uint8_t b = blue565(color);
    const float sampleOffsets[] = {-0.25f, 0.25f};
    constexpr int sampleCount = 2;
    constexpr int totalSamples = sampleCount * sampleCount;

    for (int y = cy - boundsRadius; y <= cy + boundsRadius; ++y) {
        for (int x = cx - boundsRadius; x <= cx + boundsRadius; ++x) {
            int coveredSamples = 0;
            for (int sampleY = 0; sampleY < sampleCount; ++sampleY) {
                for (int sampleX = 0; sampleX < sampleCount; ++sampleX) {
                    const float dx = (float)x + sampleOffsets[sampleX] - (float)cx;
                    const float dy = (float)y + sampleOffsets[sampleY] - (float)cy;
                    const float edgeDistance = fabsf(sqrtf(dx * dx + dy * dy) - (float)radius);
                    if (edgeDistance <= half) {
                        ++coveredSamples;
                    }
                }
            }

            if (coveredSamples) {
                maxPixel(x, y, r, g, b, coverageAlpha(coveredSamples, totalSamples));
            }
        }
    }
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

void arcFrame(int cx, int cy, int radius, float startDegrees, float sweepDegrees, uint16_t color, int thickness) {
    if (sweepDegrees <= 0.0f) {
        return;
    }

    if (sweepDegrees >= 359.9f) {
        circleFrame(cx, cy, radius, color, thickness);
        return;
    }

    const float half = max(0.5f, (float)(thickness - 1) * 0.5f);
    const int boundsRadius = radius + (int)ceilf(half + 1.0f);
    const float innerRadius = max(0.0f, (float)radius - half);
    const float outerRadius = (float)radius + half;
    const float prefilterInner = max(0.0f, innerRadius - 1.0f);
    const float prefilterOuter = outerRadius + 1.0f;
    const float inner2 = innerRadius * innerRadius;
    const float outer2 = outerRadius * outerRadius;
    const float prefilterInner2 = prefilterInner * prefilterInner;
    const float prefilterOuter2 = prefilterOuter * prefilterOuter;
    const float normalizedStart = normalizeDegrees(startDegrees);
    const uint8_t r = red565(color);
    const uint8_t g = green565(color);
    const uint8_t b = blue565(color);
    const float sampleOffsets[] = {-0.25f, 0.25f};
    constexpr int sampleCount = 2;
    constexpr int totalSamples = sampleCount * sampleCount;

    for (int y = cy - boundsRadius; y <= cy + boundsRadius; ++y) {
        for (int x = cx - boundsRadius; x <= cx + boundsRadius; ++x) {
            const float centerDx = (float)x - (float)cx;
            const float centerDy = (float)y - (float)cy;
            const float centerDistance2 = centerDx * centerDx + centerDy * centerDy;

            if (centerDistance2 < prefilterInner2 || centerDistance2 > prefilterOuter2) {
                continue;
            }

            const float centerDegrees = normalizeDegrees(atan2f(centerDy, centerDx) * 180.0f / PI + 90.0f);
            if (!angleInSweep(centerDegrees, normalizedStart, sweepDegrees)) {
                continue;
            }

            int coveredSamples = 0;
            for (int sampleY = 0; sampleY < sampleCount; ++sampleY) {
                for (int sampleX = 0; sampleX < sampleCount; ++sampleX) {
                    const float dx = (float)x + sampleOffsets[sampleX] - (float)cx;
                    const float dy = (float)y + sampleOffsets[sampleY] - (float)cy;
                    const float distance2 = dx * dx + dy * dy;

                    if (distance2 >= inner2 && distance2 <= outer2) {
                        ++coveredSamples;
                    }
                }
            }

            if (coveredSamples) {
                maxPixel(x, y, r, g, b, coverageAlpha(coveredSamples, totalSamples));
            }
        }
    }

}

void arcMarkerFrame(int cx, int cy, int radius, float degrees, uint16_t color, int markerRadius) {
    const float radians = (degrees - 90.0f) * PI / 180.0f;
    const int x = cx + (int)(cosf(radians) * radius);
    const int y = cy + (int)(sinf(radians) * radius);
    fillCircleFrame(x, y, markerRadius, color);
}

const SteedPilotGlyph* glyphFor(char value, int size) {
    for (uint16_t i = 0; i < SteedPilotFontGlyphCount; ++i) {
        const SteedPilotGlyph* glyph = &SteedPilotFontGlyphs[i];
        if (glyph->ch == value && glyph->sizeId == size) {
            return glyph;
        }
    }

    return nullptr;
}

int textWidth(const char* text, int size) {
    int width = 0;
    for (const char* p = text; *p; ++p) {
        const SteedPilotGlyph* glyph = glyphFor(*p, size);
        if (glyph) {
            width += glyph->advance;
        }
    }

    return width;
}

void textFrame(int x, int y, const char* text, int size, uint16_t color, bool center = true) {
    if (center) {
        x -= textWidth(text, size) / 2;
    }

    for (const char* ch = text; *ch; ++ch) {
        const SteedPilotGlyph* glyph = glyphFor(*ch, size);
        if (glyph) {
            const int glyphX = x + glyph->offsetX;
            const int glyphY = y + glyph->offsetY;

            for (int row = 0; row < glyph->h; ++row) {
                for (int col = 0; col < glyph->w; ++col) {
                    const int atlasIndex = (glyph->y + row) * SteedPilotFontAtlasWidth + glyph->x + col;
                    const uint8_t coverage = SteedPilotFontAtlasAlpha[atlasIndex];
                    blendPixel(glyphX + col, glyphY + row, red565(color), green565(color), blue565(color), coverage);
                }
            }

            x += glyph->advance;
        }
    }
}

void imageFrameCentered(const SteedPilotGrayAlphaImage& image, uint8_t opacity) {
    const int left = (LCD_WIDTH - image.width) / 2;
    const int top = (LCD_HEIGHT - image.height) / 2 + 20;

    for (int y = 0; y < image.height; ++y) {
        for (int x = 0; x < image.width; ++x) {
            const uint8_t* pixel = image.pixels + (y * image.width + x) * 2;
            const uint8_t gray = pixel[0];
            const uint8_t alpha = (uint8_t)((pixel[1] * opacity) / 255);
            blendPixel(left + x, top + y, gray, gray, gray, alpha);
        }
    }
}

void presentFrame();

void splashFrame(uint8_t opacity) {
    clearFrame(rgb565(0, 0, 0));
    imageFrameCentered(SteedPilotDtcLogo, opacity);
    presentFrame();
}

void arrowFrame(int cx, int cy, int length, float degrees, uint16_t color) {
    const float angle = (degrees - 90.0f) * PI / 180.0f;
    const float sideA = angle + 2.45f;
    const float sideB = angle - 2.45f;
    const int tipX = cx + (int)(cosf(angle) * length);
    const int tipY = cy + (int)(sinf(angle) * length);
    const int tailX = cx - (int)(cosf(angle) * (length / 3));
    const int tailY = cy - (int)(sinf(angle) * (length / 3));
    const int wingAX = tipX + (int)(cosf(sideA) * (length / 3));
    const int wingAY = tipY + (int)(sinf(sideA) * (length / 3));
    const int wingBX = tipX + (int)(cosf(sideB) * (length / 3));
    const int wingBY = tipY + (int)(sinf(sideB) * (length / 3));

    thickLineFrame(tailX, tailY, tipX, tipY, color, 9);
    thickLineFrame(tipX, tipY, wingAX, wingAY, color, 9);
    thickLineFrame(tipX, tipY, wingBX, wingBY, color, 9);
    fillCircleFrame(cx, cy, 9, color);
}

void arrowHeadFrame(int tipX, int tipY, float degrees, int length, uint16_t color, int thickness) {
    const float angle = (degrees - 90.0f) * PI / 180.0f;
    const float sideA = angle + 2.45f;
    const float sideB = angle - 2.45f;
    const int wingAX = tipX + (int)(cosf(sideA) * length);
    const int wingAY = tipY + (int)(sinf(sideA) * length);
    const int wingBX = tipX + (int)(cosf(sideB) * length);
    const int wingBY = tipY + (int)(sinf(sideB) * length);

    thickLineFrame(tipX, tipY, wingAX, wingAY, color, thickness);
    thickLineFrame(tipX, tipY, wingBX, wingBY, color, thickness);
}

void uTurnFrame(int cx, int cy, uint16_t color) {
    const int radius = 34;
    const int thickness = 9;
    thickLineFrame(cx - radius, cy + 48, cx - radius, cy, color, thickness);
    arcFrame(cx, cy, radius, 270.0f, 180.0f, color, thickness);
    thickLineFrame(cx + radius, cy, cx + radius, cy + 48, color, thickness);
    arrowHeadFrame(cx + radius, cy + 48, 180.0f, 28, color, thickness);
}

void shellFrame(bool speedWarning) {
    const int cx = LCD_WIDTH / 2;
    const int cy = LCD_HEIGHT / 2;
    if (speedWarning) {
        circleFrame(cx, cy, 174, rgb565(236, 0, 0), 7);
    }
}

void progressFrame(int tripComplete, int maneuverRemaining, bool maneuver) {
    const int cx = LCD_WIDTH / 2;
    const int cy = LCD_HEIGHT / 2;
    const uint16_t amber = rgb565(255, 184, 77);
    const uint16_t amberTrack = rgb565(38, 32, 17);
    const uint16_t cyan = rgb565(58, 206, 212);
    const uint16_t cyanTrack = rgb565(8, 30, 32);

    if (tripComplete >= 0) {
        const float sweep = PROGRESS_SWEEP_DEGREES * (float)tripComplete / 100.0f;
        arcFrame(cx, cy, 162, PROGRESS_START_DEGREES, PROGRESS_SWEEP_DEGREES, amberTrack, 3);
        arcFrame(cx, cy, 162, PROGRESS_START_DEGREES, sweep, amber, 3);
        arcMarkerFrame(cx, cy, 162, PROGRESS_START_DEGREES, amber, 4);
        arcMarkerFrame(cx, cy, 162, PROGRESS_START_DEGREES + PROGRESS_SWEEP_DEGREES, amber, 4);
    }

    if (maneuver && maneuverRemaining >= 0) {
        const float sweep = PROGRESS_SWEEP_DEGREES * (float)maneuverRemaining / 100.0f;
        arcFrame(cx, cy, 150, PROGRESS_START_DEGREES, PROGRESS_SWEEP_DEGREES, cyanTrack, 7);
        arcFrame(cx, cy, 150, PROGRESS_START_DEGREES, sweep, cyan, 7);
        arcMarkerFrame(cx, cy, 150, PROGRESS_START_DEGREES, cyan, 5);
        arcMarkerFrame(cx, cy, 150, PROGRESS_START_DEGREES + PROGRESS_SWEEP_DEGREES, cyan, 5);
    }
}

void roundaboutFrame() {
    const int cx = LCD_WIDTH / 2;
    const int cy = LCD_HEIGHT / 2 - 34 + GRAPHIC_OFFSET_Y;
    const int radius = 42;
    const int exitLength = 32;
    const int exitCount = 5;
    const int targetExit = 3;
    const uint16_t dim = rgb565(55, 68, 72);
    const uint16_t cyan = rgb565(58, 206, 212);
    const float startDegrees = -155.0f;
    const float stepDegrees = 250.0f / (float)(exitCount - 1);
    const float targetDegrees = startDegrees + stepDegrees * (float)(targetExit - 1);
    float routeSweep = targetDegrees - 180.0f;
    if (routeSweep < 0.0f) {
        routeSweep += 360.0f;
    }

    circleFrame(cx, cy, radius, dim, 5);
    for (int i = 0; i < exitCount; ++i) {
        const float degrees = startDegrees + stepDegrees * (float)i;
        const float radians = (degrees - 90.0f) * PI / 180.0f;
        const int innerX = cx + (int)(cosf(radians) * (radius + 2));
        const int innerY = cy + (int)(sinf(radians) * (radius + 2));
        const int outerX = cx + (int)(cosf(radians) * (radius + exitLength));
        const int outerY = cy + (int)(sinf(radians) * (radius + exitLength));
        thickLineFrame(innerX, innerY, outerX, outerY, dim, 5);
    }

    thickLineFrame(cx, cy + radius + exitLength, cx, cy + radius + 4, cyan, 9);
    arcFrame(cx, cy, radius, 180.0f, routeSweep, cyan, 9);

    const float targetRadians = (targetDegrees - 90.0f) * PI / 180.0f;
    const int targetInnerX = cx + (int)(cosf(targetRadians) * (radius + 4));
    const int targetInnerY = cy + (int)(sinf(targetRadians) * (radius + 4));
    const int targetOuterX = cx + (int)(cosf(targetRadians) * (radius + exitLength));
    const int targetOuterY = cy + (int)(sinf(targetRadians) * (radius + exitLength));
    thickLineFrame(targetInnerX, targetInnerY, targetOuterX, targetOuterY, cyan, 9);
    fillCircleFrame(targetOuterX, targetOuterY, 7, cyan);
}

void presentFrame() {
    esp_lcd_panel_draw_bitmap(g_panel, 0, 0, LCD_WIDTH, LCD_HEIGHT, g_frame);
}

void demoScreen(int screen) {
    const uint16_t black = rgb565(0, 0, 0);
    const uint16_t white = rgb565(245, 248, 242);
    const uint16_t muted = rgb565(138, 150, 151);
    const uint16_t cyan = rgb565(58, 206, 212);
    const uint16_t amber = rgb565(255, 184, 77);

    clearFrame(black);

    if (screen == 4) {
        shellFrame(false);
        progressFrame(32, -1, false);
        arrowFrame(180, 146 + GRAPHIC_OFFSET_Y, 88, 35.0f, amber);
        textFrame(180, INSTRUCTION_Y, "DESTINATION", 2, muted);
        textFrame(180, DISTANCE_Y, "11.4", 5, white);
        textFrame(180, UNIT_Y, "mi", 2, muted);
        presentFrame();
        return;
    }

    if (screen == 5) {
        shellFrame(false);
        progressFrame(36, 18, true);
        textFrame(180, INSTRUCTION_Y, "U TURN IN", 2, muted);
        uTurnFrame(180, 128 + GRAPHIC_OFFSET_Y, cyan);
        textFrame(180, DISTANCE_Y, "90", 5, white);
        textFrame(180, UNIT_Y, "m", 2, muted);
        presentFrame();
        return;
    }

    shellFrame(screen == 3);
    progressFrame(screen == 1 ? 32 : 44, screen == 1 ? 22 : 58, true);

    if (screen == 2) {
        roundaboutFrame();
        textFrame(180, 38, "EXIT 3", 2, muted);
        textFrame(180, INSTRUCTION_Y, "ROUNDABOUT IN", 2, muted);
        textFrame(180, DISTANCE_Y, "260", 5, white);
        textFrame(180, UNIT_Y, "m", 2, muted);
    } else {
        const bool left = screen == 1;
        textFrame(180, INSTRUCTION_Y, left ? "LEFT IN" : "CONTINUE FOR", 2, muted);
        arrowFrame(180, 146 + GRAPHIC_OFFSET_Y, 82, left ? -55.0f : 0.0f, cyan);
        textFrame(180, DISTANCE_Y, left ? "180" : "420", 5, white);
        textFrame(180, UNIT_Y, "m", 2, muted);
    }

    presentFrame();
}

} // namespace

void setup() {
    Serial.begin(115200);
    Serial.println("SteedPilot demo firmware");

    if (!initDisplay()) {
        Serial.println("Display init failed");
        return;
    }

    const uint32_t fadeInMs = 900;
    const uint32_t holdMs = 2000;
    const uint32_t fadeOutMs = 900;
    const uint32_t splashStart = millis();

    while (millis() - splashStart < fadeInMs + holdMs + fadeOutMs) {
        const uint32_t elapsed = millis() - splashStart;
        uint8_t opacity = 255;

        if (elapsed < fadeInMs) {
            opacity = (uint8_t)((elapsed * 255) / fadeInMs);
        } else if (elapsed >= fadeInMs + holdMs) {
            opacity = (uint8_t)(255 - (((elapsed - fadeInMs - holdMs) * 255) / fadeOutMs));
        }

        splashFrame(opacity);
        delay(16);
    }

    demoScreen(0);
    Serial.println("Demo screen drawn");
}

void loop() {
    static uint32_t lastSwitch = millis();
    static int screen = 0;
    const uint32_t now = millis();

    if (now - lastSwitch >= 3500) {
        screen = (screen + 1) % 6;
        demoScreen(screen);
        lastSwitch = now;
    }

    delay(16);
}
