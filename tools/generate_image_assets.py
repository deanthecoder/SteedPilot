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
OUT_HEADER = ROOT / "include" / "SteedPilot" / "ImageAssets.h"
OUT_SOURCE = ROOT / "src" / "generated" / "ImageAssets.c"
IMAGES = [
    {
        "name": "SteedPilotDtcLogo",
        "pixels": "SteedPilotDtcLogoPixels",
        "source": ROOT / "img" / "DTC.png",
        "description": "Startup DTC logo bitmap",
    },
    {
        "name": "SteedPilotFinishFlag",
        "pixels": "SteedPilotFinishFlagPixels",
        "source": ROOT / "img" / "flag.png",
        "description": "Arrival chequered flag bitmap",
    },
]


def byte_lines(values, columns=18):
    lines = []
    for i in range(0, len(values), columns):
        chunk = values[i:i + columns]
        lines.append("    " + ", ".join(f"0x{value:02x}" for value in chunk) + ",")
    return "\n".join(lines)


def load_image(definition):
    image = Image.open(definition["source"]).convert("LA")
    if "max_size" in definition:
        image.thumbnail(definition["max_size"], Image.Resampling.LANCZOS)

    return image


def image_pixels(image):
    pixels = []
    for gray, alpha in image.getdata():
        pixels.append(gray)
        pixels.append(alpha)

    return pixels


def write_outputs(images):
    OUT_HEADER.parent.mkdir(parents=True, exist_ok=True)
    OUT_SOURCE.parent.mkdir(parents=True, exist_ok=True)

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

"""

    for definition, _ in images:
        header += f"/** {definition['description']}. */\n"
        header += f"extern const SteedPilotGrayAlphaImage {definition['name']};\n\n"

    header += """#ifdef __cplusplus
}
#endif
"""


    source = HEADER
    source += '#include "SteedPilot/ImageAssets.h"\n\n'
    for definition, image in images:
        source += f"// Generated from {definition['source']}.\n"
        source += f"/** Interleaved grey and alpha bytes for {definition['description'].lower()}. */\n"
        source += f"const uint8_t {definition['pixels']}[] = {{\n"
        source += byte_lines(image_pixels(image))
        source += "\n};\n\n"
        source += f"/** {definition['description']}. */\n"
        source += f"const SteedPilotGrayAlphaImage {definition['name']} = {{\n"
        source += f"    {image.width},\n"
        source += f"    {image.height},\n"
        source += f"    {definition['pixels']},\n"
        source += "};\n\n"

    OUT_HEADER.write_text(header)
    OUT_SOURCE.write_text(source)


def main():
    images = [(definition, load_image(definition)) for definition in IMAGES]
    write_outputs(images)


if __name__ == "__main__":
    main()
