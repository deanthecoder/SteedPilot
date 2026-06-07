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

#include <cstdlib>
#include <iostream>

namespace {

int failures = 0;

void expect(bool condition, const char* message) {
    if (condition) {
        std::cout << "PASS " << message << "\n";
        return;
    }

    std::cout << "FAIL " << message << "\n";
    ++failures;
}

void speedPayloadParsesFromNestedObject() {
    const char* json =
        "{"
        "\"v\":1,"
        "\"type\":\"state\","
        "\"mode\":\"navigation\","
        "\"speed\":{\"current\":70,\"limit\":60,\"unit\":\"mph\"}"
        "}";

    SteedPilot::NavPacket packet;
    expect(SteedPilot::parseNavPacketJson(json, packet), "nested speed payload parses");
    expect((packet.fields & SteedPilot::NavFieldCurrentSpeed) != 0, "current speed field is present");
    expect((packet.fields & SteedPilot::NavFieldSpeedLimit) != 0, "speed limit field is present");
    expect((packet.fields & SteedPilot::NavFieldSpeedUnit) != 0, "speed unit field is present");
    expect(packet.state.currentSpeed == 70, "current speed value is 70 mph");
    expect(packet.state.speedLimit == 60, "speed limit value is 60 mph");
    expect(packet.state.speedUnit == SteedPilot::SpeedUnit::Mph, "speed unit is mph");
}

}

int main() {
    speedPayloadParsesFromNestedObject();

    if (failures > 0) {
        std::cout << "\n" << failures << " nav json test" << (failures == 1 ? "" : "s") << " failed.\n";
        return 1;
    }

    std::cout << "\nAll nav json tests passed.\n";
    return 0;
}
