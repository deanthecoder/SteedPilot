#!/usr/bin/env python3

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HEADER = """// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

"""

ROOT = Path(__file__).resolve().parents[1]
OUT_HEADER = ROOT / "include" / "SteedPilot" / "FontAtlas.h"
OUT_SOURCE = ROOT / "src" / "generated" / "FontAtlas.c"

CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz .,:-/+"
SIZES = {
    1: 12,
    2: 20,
    4: 42,
    5: 58,
}

FONT_CANDIDATES = [
    Path("/System/Library/Fonts/SFCompact.ttf"),
    Path("/System/Library/Fonts/SFNS.ttf"),
    Path("/System/Library/Fonts/Avenir.ttc"),
    Path("/System/Library/Fonts/HelveticaNeue.ttc"),
    Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
]


def find_font():
    for path in FONT_CANDIDATES:
        if path.exists():
            return path
    raise FileNotFoundError("No suitable source font found.")


def load_font(path, size):
    return ImageFont.truetype(str(path), size=size)


def render_glyph(font, ch):
    scratch = Image.new("L", (160, 160), 0)
    draw = ImageDraw.Draw(scratch)
    bbox = draw.textbbox((0, 0), ch, font=font)
    advance = int(round(draw.textlength(ch, font=font)))

    width = max(1, bbox[2] - bbox[0])
    height = max(1, bbox[3] - bbox[1])
    image = Image.new("L", (width + 2, height + 2), 0)
    draw = ImageDraw.Draw(image)
    draw.text((1 - bbox[0], 1 - bbox[1]), ch, font=font, fill=255)
    return image, advance, bbox[0] - 1, bbox[1] - 1


def pack_glyphs(font_path):
    glyphs = []
    x = 0
    y = 0
    row_h = 0
    atlas_w = 512
    padding = 2

    rendered = []
    for size_id, pixel_size in SIZES.items():
        font = load_font(font_path, pixel_size)
        ascent, descent = font.getmetrics()
        for ch in CHARS:
            image, advance, offset_x, offset_y = render_glyph(font, ch)
            rendered.append({
                "char": ch,
                "size_id": size_id,
                "pixel_size": pixel_size,
                "ascent": ascent,
                "image": image,
                "advance": advance,
                "offset_x": offset_x,
                "offset_y": offset_y,
            })

    for item in rendered:
        image = item["image"]
        if x + image.width + padding > atlas_w:
            x = 0
            y += row_h + padding
            row_h = 0

        item["x"] = x
        item["y"] = y
        x += image.width + padding
        row_h = max(row_h, image.height)

    atlas_h = y + row_h
    atlas = Image.new("L", (atlas_w, atlas_h), 0)

    for item in rendered:
        image = item["image"]
        atlas.paste(image, (item["x"], item["y"]))

        glyphs.append({
            "ch": item["char"],
            "size_id": item["size_id"],
            "x": item["x"],
            "y": item["y"],
            "w": image.width,
            "h": image.height,
            "advance": item["advance"],
            "offset_x": item["offset_x"],
            "offset_y": item["offset_y"],
            "ascent": item["ascent"],
        })

    return atlas, glyphs, font_path


def c_char(ch):
    if ch == "'":
        return "'\\'''"
    if ch == "\\":
        return "'\\\\'"
    return f"'{ch}'"


def write_outputs(atlas, glyphs, font_path):
    OUT_HEADER.parent.mkdir(parents=True, exist_ok=True)
    OUT_SOURCE.parent.mkdir(parents=True, exist_ok=True)

    pixels = list(atlas.tobytes())

    header = HEADER + f"""#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {{
#endif

/**
 * Describes a single glyph inside the generated font atlas.
 */
typedef struct SteedPilotGlyph {{
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
}} SteedPilotGlyph;

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
}}
#endif
"""

    source = HEADER
    source += '#include "SteedPilot/FontAtlas.h"\n\n'
    source += f"// Generated from {font_path}.\n"
    source += "/** Width of the generated font atlas in pixels. */\n"
    source += f"const uint16_t SteedPilotFontAtlasWidth = {atlas.width};\n"
    source += "/** Height of the generated font atlas in pixels. */\n"
    source += f"const uint16_t SteedPilotFontAtlasHeight = {atlas.height};\n"
    source += "/** Number of pixels in the generated font atlas. */\n"
    source += f"const uint32_t SteedPilotFontAtlasPixelCount = {atlas.width * atlas.height};\n\n"

    source += "/**\n"
    source += " * Single-channel anti-aliased glyph coverage.\n"
    source += " *\n"
    source += " * Runtime renderers tint each glyph by multiplying this coverage by the\n"
    source += " * requested text color.\n"
    source += " */\n"
    source += "const uint8_t SteedPilotFontAtlasAlpha[] = {\n"
    for i in range(0, len(pixels), 18):
        source += "    " + ", ".join(f"0x{v:02x}" for v in pixels[i:i + 18]) + ",\n"
    source += "};\n\n"

    source += "/** Packed glyph metric table for all generated characters and sizes. */\n"
    source += "const SteedPilotGlyph SteedPilotFontGlyphs[] = {\n"
    for g in glyphs:
        source += (
            f"    {{{c_char(g['ch'])}, {g['size_id']}, {g['x']}, {g['y']}, "
            f"{g['w']}, {g['h']}, {g['offset_x']}, {g['offset_y']}, "
            f"{g['advance']}, {g['ascent']}}},\n"
        )
    source += "};\n\n"
    source += "/** Number of entries in SteedPilotFontGlyphs. */\n"
    source += f"const uint16_t SteedPilotFontGlyphCount = {len(glyphs)};\n"

    OUT_HEADER.write_text(header)
    OUT_SOURCE.write_text(source)


def main():
    font_path = find_font()
    atlas, glyphs, font_path = pack_glyphs(font_path)
    write_outputs(atlas, glyphs, font_path)
    print(f"Generated {OUT_HEADER}")
    print(f"Generated {OUT_SOURCE}")
    print(f"Atlas: {atlas.width}x{atlas.height}, glyphs: {len(glyphs)}, source: {font_path}")


if __name__ == "__main__":
    main()
