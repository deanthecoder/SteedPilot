#!/usr/bin/env python3

from pathlib import Path
from PIL import Image

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
SOURCE_IMAGE = ROOT / "img" / "DTC.png"
OUT_HEADER = ROOT / "include" / "SteedPilot" / "ImageAssets.h"
OUT_SOURCE = ROOT / "src" / "generated" / "ImageAssets.c"


def byte_lines(values, columns=18):
    lines = []
    for i in range(0, len(values), columns):
        chunk = values[i:i + columns]
        lines.append("    " + ", ".join(f"0x{value:02x}" for value in chunk) + ",")
    return "\n".join(lines)


def write_outputs(image):
    OUT_HEADER.parent.mkdir(parents=True, exist_ok=True)
    OUT_SOURCE.parent.mkdir(parents=True, exist_ok=True)

    pixels = []
    for gray, alpha in image.getdata():
        pixels.append(gray)
        pixels.append(alpha)

    header = HEADER + """#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Describes a generated grey plus alpha bitmap.
 */
typedef struct SteedPilotGrayAlphaImage {
    /** Image width in pixels. */
    uint16_t width;

    /** Image height in pixels. */
    uint16_t height;

    /** Interleaved grey and alpha bytes, one pair per pixel. */
    const uint8_t* pixels;
} SteedPilotGrayAlphaImage;

/** Startup DTC logo bitmap. */
extern const SteedPilotGrayAlphaImage SteedPilotDtcLogo;

#ifdef __cplusplus
}
#endif
"""

    source = HEADER
    source += '#include "SteedPilot/ImageAssets.h"\n\n'
    source += f"// Generated from {SOURCE_IMAGE}.\n"
    source += "/** Interleaved grey and alpha bytes for the startup DTC logo. */\n"
    source += "const uint8_t SteedPilotDtcLogoPixels[] = {\n"
    source += byte_lines(pixels)
    source += "\n};\n\n"
    source += "/** Startup DTC logo bitmap. */\n"
    source += "const SteedPilotGrayAlphaImage SteedPilotDtcLogo = {\n"
    source += f"    {image.width},\n"
    source += f"    {image.height},\n"
    source += "    SteedPilotDtcLogoPixels,\n"
    source += "};\n"

    OUT_HEADER.write_text(header)
    OUT_SOURCE.write_text(source)


def main():
    image = Image.open(SOURCE_IMAGE).convert("LA")
    write_outputs(image)


if __name__ == "__main__":
    main()
