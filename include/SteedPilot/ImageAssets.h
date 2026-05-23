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

/** Arrival chequered flag bitmap. */
extern const SteedPilotGrayAlphaImage SteedPilotFinishFlag;

#ifdef __cplusplus
}
#endif
