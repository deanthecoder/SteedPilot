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

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Describes a single glyph inside the generated font atlas.
 */
typedef struct SteedPilotGlyph {
    /** Character represented by this glyph. */
    char ch;

    /** Fixed font size identifier used by Display::text(). */
    uint8_t sizeId;

    /** Glyph x position in the atlas. */
    uint16_t x;

    /** Glyph y position in the atlas. */
    uint16_t y;

    /** Glyph width in pixels. */
    uint8_t w;

    /** Glyph height in pixels. */
    uint8_t h;

    /** Horizontal offset from the text cursor to the glyph bitmap. */
    int8_t offsetX;

    /** Vertical offset from the supplied text y coordinate to the glyph bitmap. */
    int8_t offsetY;

    /** Horizontal cursor advance after drawing this glyph. */
    uint8_t advance;

    /** Source font ascent for this glyph size. */
    uint8_t ascent;
} SteedPilotGlyph;

/** Width of the generated font atlas in pixels. */
extern const uint16_t SteedPilotFontAtlasWidth;

/** Height of the generated font atlas in pixels. */
extern const uint16_t SteedPilotFontAtlasHeight;

/** Number of pixels in the generated font atlas. */
extern const uint32_t SteedPilotFontAtlasPixelCount;

/**
 * Single-channel anti-aliased glyph coverage.
 *
 * Runtime renderers tint each glyph by multiplying this coverage by the
 * requested text color.
 */
extern const uint8_t SteedPilotFontAtlasAlpha[];

/** Packed glyph metric table for all generated characters and sizes. */
extern const SteedPilotGlyph SteedPilotFontGlyphs[];

/** Number of entries in SteedPilotFontGlyphs. */
extern const uint16_t SteedPilotFontGlyphCount;

#ifdef __cplusplus
}
#endif
