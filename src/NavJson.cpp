// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

#include "SteedPilot/NavJson.h"

#include <cctype>
#include <cstdlib>
#include <cstring>
#include <string>

namespace SteedPilot {
namespace {

const char* findKey(const char* json, const char* key) {
    std::string needle = "\"";
    needle += key;
    needle += "\"";
    return std::strstr(json, needle.c_str());
}

const char* valueStart(const char* keyPosition) {
    const char* colon = std::strchr(keyPosition, ':');
    if (!colon) {
        return nullptr;
    }

    ++colon;
    while (*colon && std::isspace((unsigned char)*colon)) {
        ++colon;
    }

    return colon;
}

bool readString(const char* json, const char* key, char* output, size_t outputSize) {
    const char* keyPosition = findKey(json, key);
    if (!keyPosition) {
        return false;
    }

    const char* value = valueStart(keyPosition);
    if (!value || *value != '"' || outputSize == 0) {
        return false;
    }

    ++value;
    size_t index = 0;
    while (*value && *value != '"' && index + 1 < outputSize) {
        output[index++] = *value++;
    }

    output[index] = '\0';
    return *value == '"';
}

bool readInt(const char* json, const char* key, int& output) {
    const char* keyPosition = findKey(json, key);
    if (!keyPosition) {
        return false;
    }

    const char* value = valueStart(keyPosition);
    if (!value) {
        return false;
    }

    char* end = nullptr;
    const long parsed = std::strtol(value, &end, 10);
    if (end == value) {
        return false;
    }

    output = (int)parsed;
    return true;
}

bool readBool(const char* json, const char* key, bool& output) {
    const char* keyPosition = findKey(json, key);
    if (!keyPosition) {
        return false;
    }

    const char* value = valueStart(keyPosition);
    if (!value) {
        return false;
    }

    if (std::strncmp(value, "true", 4) == 0) {
        output = true;
        return true;
    }

    if (std::strncmp(value, "false", 5) == 0) {
        output = false;
        return true;
    }

    return false;
}

bool stringEquals(const char* left, const char* right) {
    return std::strcmp(left, right) == 0;
}

DisplayMode parseMode(const char* value) {
    if (stringEquals(value, "destination")) {
        return DisplayMode::Destination;
    }

    if (stringEquals(value, "rideInfo")) {
        return DisplayMode::RideInfo;
    }

    if (stringEquals(value, "noPhone")) {
        return DisplayMode::NoPhone;
    }

    if (stringEquals(value, "calibration")) {
        return DisplayMode::Calibration;
    }

    return DisplayMode::Navigation;
}

Maneuver parseManeuver(const char* value) {
    if (stringEquals(value, "bendLeft")) return Maneuver::BendLeft;
    if (stringEquals(value, "exitLeft")) return Maneuver::ExitLeft;
    if (stringEquals(value, "slightLeft")) return Maneuver::SlightLeft;
    if (stringEquals(value, "turnLeft")) return Maneuver::TurnLeft;
    if (stringEquals(value, "sharpLeft")) return Maneuver::SharpLeft;
    if (stringEquals(value, "uTurn")) return Maneuver::UTurn;
    if (stringEquals(value, "exitRight")) return Maneuver::ExitRight;
    if (stringEquals(value, "slightRight")) return Maneuver::SlightRight;
    if (stringEquals(value, "turnRight")) return Maneuver::TurnRight;
    if (stringEquals(value, "sharpRight")) return Maneuver::SharpRight;
    if (stringEquals(value, "roundabout")) return Maneuver::Roundabout;
    if (stringEquals(value, "arrive")) return Maneuver::Arrive;
    return Maneuver::Continue;
}

LinkState parseLinkState(const char* value) {
    if (stringEquals(value, "pairing")) {
        return LinkState::Pairing;
    }

    if (stringEquals(value, "disconnected")) {
        return LinkState::Disconnected;
    }

    return LinkState::Connected;
}

SpeedUnit parseSpeedUnit(const char* value) {
    if (stringEquals(value, "kph")) {
        return SpeedUnit::Kph;
    }

    return SpeedUnit::Mph;
}

NavPacketType parsePacketType(const char* value) {
    if (stringEquals(value, "update")) {
        return NavPacketType::Update;
    }

    if (stringEquals(value, "heartbeat")) {
        return NavPacketType::Heartbeat;
    }

    return NavPacketType::State;
}

bool readRoundaboutAngles(const char* json, NavState& state) {
    const char* exits = findKey(json, "exits");
    if (!exits) {
        return false;
    }

    state.roundaboutExitAngleCount = 0;
    const char* cursor = exits;
    while (state.roundaboutExitAngleCount < MaxRoundaboutExits) {
        const char* angle = findKey(cursor, "angleDegrees");
        if (!angle) {
            break;
        }

        int parsed = 0;
        const char* value = valueStart(angle);
        if (!value) {
            break;
        }

        char* end = nullptr;
        parsed = (int)std::strtol(value, &end, 10);
        if (end == value) {
            break;
        }

        state.roundaboutExitAngles[state.roundaboutExitAngleCount++] = (int16_t)parsed;
        cursor = end;
    }

    if (state.roundaboutExitCount <= 0) {
        state.roundaboutExitCount = state.roundaboutExitAngleCount;
    }

    return state.roundaboutExitAngleCount > 0;
}

} // namespace

bool parseNavPacketJson(const char* json, NavPacket& packet) {
    if (!json) {
        return false;
    }

    packet = {};
    char text[32];
    int value = 0;
    bool boolValue = false;

    if (readString(json, "type", text, sizeof(text))) {
        packet.type = parsePacketType(text);
    }

    if (packet.type == NavPacketType::Heartbeat) {
        return true;
    }

    if (readString(json, "mode", text, sizeof(text))) {
        packet.state.mode = parseMode(text);
        packet.fields |= NavFieldMode;
    }

    if (readString(json, "maneuver", text, sizeof(text))) {
        packet.state.maneuver = parseManeuver(text);
        packet.fields |= NavFieldManeuver;
    }

    if (readString(json, "link", text, sizeof(text))) {
        packet.state.linkState = parseLinkState(text);
        packet.state.connected = packet.state.linkState == LinkState::Connected;
        packet.fields |= NavFieldLink;
    }

    if (readBool(json, "connected", boolValue)) {
        packet.state.connected = boolValue;
        packet.state.linkState = boolValue ? LinkState::Connected : LinkState::Disconnected;
        packet.fields |= NavFieldLink;
    }

    if (readBool(json, "offRoute", boolValue)) {
        packet.state.offRoute = boolValue;
        packet.fields |= NavFieldOffRoute;
    }

    if (readInt(json, "distanceToManeuverMeters", value)) { packet.state.distanceToManeuverMeters = value; packet.fields |= NavFieldDistanceToManeuver; }
    if (readInt(json, "distanceToDestinationMeters", value)) { packet.state.distanceToDestinationMeters = value; packet.fields |= NavFieldDistanceToDestination; }
    if (readInt(json, "maneuverProgressRemaining", value)) { packet.state.maneuverProgressRemaining = (int8_t)value; packet.fields |= NavFieldManeuverProgress; }
    if (readInt(json, "tripProgressComplete", value)) { packet.state.tripProgressComplete = (int8_t)value; packet.fields |= NavFieldTripProgress; }
    if (readInt(json, "destinationBearingDegrees", value)) { packet.state.destinationBearingDegrees = (int16_t)value; packet.fields |= NavFieldDestinationBearing; }
    if (readInt(json, "exit", value)) { packet.state.roundaboutExit = (int8_t)value; packet.fields |= NavFieldRoundabout; }
    if (readInt(json, "exitCount", value)) { packet.state.roundaboutExitCount = (int8_t)value; packet.fields |= NavFieldRoundabout; }
    if (readInt(json, "current", value)) { packet.state.currentSpeed = (int16_t)value; packet.fields |= NavFieldCurrentSpeed; }
    if (readInt(json, "limit", value)) { packet.state.speedLimit = (int16_t)value; packet.fields |= NavFieldSpeedLimit; }

    if (readString(json, "unit", text, sizeof(text))) {
        packet.state.speedUnit = parseSpeedUnit(text);
        packet.fields |= NavFieldSpeedUnit;
    }

    if (readRoundaboutAngles(json, packet.state)) {
        packet.fields |= NavFieldRoundabout;
    }

    return packet.fields != NavFieldNone;
}

bool parseNavPacketJson(const char* json, size_t length, NavPacket& packet) {
    if (!json) {
        return false;
    }

    std::string copy(json, length);
    return parseNavPacketJson(copy.c_str(), packet);
}

bool parseNavStateJson(const char* json, NavState& state) {
    NavPacket packet;
    if (!parseNavPacketJson(json, packet) || packet.type == NavPacketType::Heartbeat) {
        return false;
    }

    state = packet.state;
    return true;
}

bool parseNavStateJson(const char* json, size_t length, NavState& state) {
    if (!json) {
        return false;
    }

    std::string copy(json, length);
    return parseNavStateJson(copy.c_str(), state);
}

} // namespace SteedPilot
