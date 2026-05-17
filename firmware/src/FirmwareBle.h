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

#include "SteedPilot/NavJson.h"

#include <cstddef>
#include <cstdint>

/**
 * Receives SteedPilot navigation JSON packets over BLE.
 */
class FirmwareBle {
public:
    /**
     * Callback invoked when a complete navigation packet is received.
     */
    using PacketCallback = void (*)(const SteedPilot::NavPacket& packet);

    /**
     * Starts BLE advertising and exposes the writable navigation-state characteristic.
     *
     * @param callback Function invoked after a valid JSON packet is parsed.
     */
    void begin(PacketCallback callback);

    /**
     * Gets the current link state inferred from BLE server activity.
     *
     * @return Current BLE link state.
     */
    SteedPilot::LinkState linkState() const;

    /**
     * Appends bytes written by the BLE client to the packet buffer.
     *
     * @param data Packet bytes.
     * @param length Number of packet bytes.
     */
    void handleWrite(const char* data, size_t length);

    /**
     * Updates the current BLE link state.
     *
     * @param state New link state.
     */
    void setLinkState(SteedPilot::LinkState state);

private:
    static constexpr size_t MaxPacketBytes = 1024;

    PacketCallback _callback = nullptr;
    SteedPilot::LinkState _linkState = SteedPilot::LinkState::Disconnected;
    char _packet[MaxPacketBytes] = {};
    size_t _packetLength = 0;
    int _jsonDepth = 0;
    bool _packetStarted = false;

    void parseBufferedPacket();
};
