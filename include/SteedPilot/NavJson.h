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

#include "NavState.h"

#include <cstddef>

namespace SteedPilot {

/**
 * Parses a SteedPilot navigation JSON packet into a NavState.
 *
 * @param json Null-terminated JSON text.
 * @param state Destination state object.
 * @return True when the packet contained enough valid data to apply.
 */
bool parseNavStateJson(const char* json, NavState& state);

/**
 * Parses a SteedPilot navigation JSON packet into a NavState.
 *
 * @param json JSON text buffer.
 * @param length Number of bytes in the JSON text buffer.
 * @param state Destination state object.
 * @return True when the packet contained enough valid data to apply.
 */
bool parseNavStateJson(const char* json, size_t length, NavState& state);

} // namespace SteedPilot
