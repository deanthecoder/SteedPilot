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
    {
        "name": "SteedPilotDirectionContinue",
        "pixels": "SteedPilotDirectionContinuePixels",
        "source": ROOT / "img" / "directions" / "Continue.png",
        "description": "Continue direction bitmap",
        "canvas_size": (220, 220),
        "fit_size": (170, 190),
        "transparent_black": True,
    },
    {
        "name": "SteedPilotDirectionBendLeft",
        "pixels": "SteedPilotDirectionBendLeftPixels",
        "source": ROOT / "img" / "directions" / "BendLeft.png",
        "description": "Bend left direction bitmap",
        "canvas_size": (220, 220),
        "fit_size": (190, 190),
        "transparent_black": True,
    },
    {
        "name": "SteedPilotDirectionExitLeft",
        "pixels": "SteedPilotDirectionExitLeftPixels",
        "source": ROOT / "img" / "directions" / "ExitLeft.png",
        "description": "Exit left direction bitmap",
        "canvas_size": (220, 220),
        "fit_size": (190, 190),
        "transparent_black": True,
    },
    {
        "name": "SteedPilotDirectionSlightLeft",
        "pixels": "SteedPilotDirectionSlightLeftPixels",
        "source": ROOT / "img" / "directions" / "SlightLeft.png",
        "description": "Slight left direction bitmap",
        "canvas_size": (220, 220),
        "fit_size": (190, 190),
        "transparent_black": True,
    },
    {
        "name": "SteedPilotDirectionTurnLeft",
        "pixels": "SteedPilotDirectionTurnLeftPixels",
        "source": ROOT / "img" / "directions" / "TurnLeft.png",
        "description": "Turn left direction bitmap",
        "canvas_size": (220, 220),
        "fit_size": (190, 190),
        "transparent_black": True,
    },
    {
        "name": "SteedPilotDirectionSharpLeft",
        "pixels": "SteedPilotDirectionSharpLeftPixels",
        "source": ROOT / "img" / "directions" / "SharpLeft.png",
        "description": "Sharp left direction bitmap",
        "canvas_size": (220, 220),
        "fit_size": (190, 190),
        "transparent_black": True,
    },
    {
        "name": "SteedPilotDirectionUTurnLeft",
        "pixels": "SteedPilotDirectionUTurnLeftPixels",
        "source": ROOT / "img" / "directions" / "UTurnLeft.png",
        "description": "U turn left direction bitmap",
        "canvas_size": (220, 220),
        "fit_size": (190, 190),
        "transparent_black": True,
    },
    {
        "name": "SteedPilotDirectionHeading",
        "pixels": "SteedPilotDirectionHeadingPixels",
        "source": ROOT / "img" / "directions" / "Heading.png",
        "description": "Heading direction bitmap",
        "canvas_size": (160, 160),
        "fit_size": (140, 140),
        "transparent_black": True,
    },
    {
        "name": "SteedPilotRoundaboutRoute",
        "pixels": "SteedPilotRoundaboutRoutePixels",
        "source": ROOT / "img" / "directions" / "Roundabout.png",
        "description": "Roundabout selected exit bitmap",
        "canvas_size": (190, 190),
        "fit_size": (180, 180),
    },
    {
        "name": "SteedPilotRoundaboutNonExit",
        "pixels": "SteedPilotRoundaboutNonExitPixels",
        "source": ROOT / "img" / "directions" / "RoundaboutNonExit.png",
        "description": "Roundabout muted exit bitmap",
        "canvas_size": (190, 190),
        "fit_size": (180, 180),
    },
]


def byte_lines(values, columns=18):
    lines = []
    for i in range(0, len(values), columns):
        chunk = values[i:i + columns]
        lines.append("    " + ", ".join(f"0x{value:02x}" for value in chunk) + ",")
    return "\n".join(lines)


def apply_transparent_black(image):
    converted = Image.new("LA", image.size)
    pixels = []
    for gray, alpha in image.getdata():
        if gray <= 4 or alpha == 0:
            pixels.append((255, 0))
        else:
            pixels.append((255, (gray * alpha) // 255))
    converted.putdata(pixels)
    return converted


def fit_to_canvas(image, definition):
    if "fit_size" in definition:
        image.thumbnail(definition["fit_size"], Image.Resampling.LANCZOS)

    if "canvas_size" not in definition:
        return image

    canvas = Image.new("LA", definition["canvas_size"], (0, 0))
    left = (canvas.width - image.width) // 2
    top = (canvas.height - image.height) // 2
    canvas.paste(image, (left, top), image.getchannel("A"))
    return canvas.convert("LA")


def load_image(definition):
    image = Image.open(definition["source"]).convert("LA")
    if "max_size" in definition:
        image.thumbnail(definition["max_size"], Image.Resampling.LANCZOS)

    if definition.get("transparent_black"):
        image = apply_transparent_black(image)

    return fit_to_canvas(image, definition)


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
