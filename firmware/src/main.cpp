// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

#include "FirmwareDisplay.h"
#include "FirmwareBle.h"

#include "SteedPilot/App.h"

#include <Arduino.h>

namespace {

constexpr uint32_t SplashFadeInMs = 900;
constexpr uint32_t SplashHoldMs = 2000;
constexpr uint32_t SplashFadeOutMs = 900;
constexpr uint32_t SplashTotalMs = SplashFadeInMs + SplashHoldMs + SplashFadeOutMs;
constexpr uint32_t NoPhoneTimeoutMs = 10000;
constexpr uint32_t AnimationFrameMs = 16;

FirmwareDisplay display;
FirmwareBle ble;
SteedPilot::App app;
bool liveBleMode = false;
bool noPhoneVisible = false;
volatile bool pendingBleState = false;
uint32_t lastPacketMs = 0;
bool haveBleState = false;
SteedPilot::NavState lastBleState;
SteedPilot::NavPacket nextBlePacket;

uint8_t splashOpacity(uint32_t elapsedMs) {
    if (elapsedMs < SplashFadeInMs) {
        return (uint8_t)((elapsedMs * 255) / SplashFadeInMs);
    }

    if (elapsedMs < SplashFadeInMs + SplashHoldMs) {
        return 255;
    }

    return (uint8_t)(255 - (((elapsedMs - SplashFadeInMs - SplashHoldMs) * 255) / SplashFadeOutMs));
}

SteedPilot::NavState navigationState(SteedPilot::Maneuver maneuver, int32_t distanceMeters) {
    SteedPilot::NavState state;
    state.mode = SteedPilot::DisplayMode::Navigation;
    state.maneuver = maneuver;
    state.distanceToManeuverMeters = distanceMeters;
    state.distanceToDestinationMeters = 18400;
    state.maneuverProgressRemaining = distanceMeters > 300 ? 85 : 22;
    state.tripProgressComplete = 32;
    state.destinationBearingDegrees = 35;
    return state;
}

SteedPilot::NavState roundaboutState() {
    SteedPilot::NavState state = navigationState(SteedPilot::Maneuver::Roundabout, 260);
    state.roundaboutExitCount = 5;
    state.roundaboutExit = 3;
    state.maneuverProgressRemaining = 58;
    state.tripProgressComplete = 44;
    return state;
}

SteedPilot::NavState speedingState() {
    SteedPilot::NavState state = navigationState(SteedPilot::Maneuver::Continue, 420);
    state.currentSpeed = 55;
    state.speedLimit = 50;
    state.speedUnit = SteedPilot::SpeedUnit::Mph;
    return state;
}

SteedPilot::NavState destinationState() {
    SteedPilot::NavState state;
    state.mode = SteedPilot::DisplayMode::Destination;
    state.distanceToDestinationMeters = 18400;
    state.destinationBearingDegrees = 35;
    state.tripProgressComplete = 32;
    return state;
}

SteedPilot::NavState demoState(int screen) {
    switch (screen) {
        case 1:
            return navigationState(SteedPilot::Maneuver::TurnLeft, 180);
        case 2:
            return roundaboutState();
        case 3:
            return speedingState();
        case 4:
            return destinationState();
        case 5:
            return navigationState(SteedPilot::Maneuver::UTurn, 90);
        case 6:
            return navigationState(SteedPilot::Maneuver::BendLeft, 120);
        case 0:
        default:
            return navigationState(SteedPilot::Maneuver::Continue, 420);
    }
}

void renderDemoScreen(int screen) {
    if (liveBleMode) {
        return;
    }

    Serial.printf("Demo screen rendered: %d\n", screen);
    app.setState(demoState(screen));
    app.render(display);
}

void applyUpdate(SteedPilot::NavState& state, const SteedPilot::NavPacket& packet) {
    if (packet.fields & SteedPilot::NavFieldMode) state.mode = packet.state.mode;
    if (packet.fields & SteedPilot::NavFieldManeuver) state.maneuver = packet.state.maneuver;
    if (packet.fields & SteedPilot::NavFieldLink) {
        state.connected = packet.state.connected;
        state.linkState = packet.state.linkState;
    }
    if (packet.fields & SteedPilot::NavFieldDistanceToManeuver) state.distanceToManeuverMeters = packet.state.distanceToManeuverMeters;
    if (packet.fields & SteedPilot::NavFieldDistanceToDestination) state.distanceToDestinationMeters = packet.state.distanceToDestinationMeters;
    if (packet.fields & SteedPilot::NavFieldManeuverProgress) state.maneuverProgressRemaining = packet.state.maneuverProgressRemaining;
    if (packet.fields & SteedPilot::NavFieldTripProgress) state.tripProgressComplete = packet.state.tripProgressComplete;
    if (packet.fields & SteedPilot::NavFieldDestinationBearing) state.destinationBearingDegrees = packet.state.destinationBearingDegrees;
    if (packet.fields & SteedPilot::NavFieldRoundabout) {
        state.roundaboutExitCount = packet.state.roundaboutExitCount;
        state.roundaboutExit = packet.state.roundaboutExit;
        state.roundaboutExitAngleCount = packet.state.roundaboutExitAngleCount;
        for (int i = 0; i < SteedPilot::MaxRoundaboutExits; ++i) {
            state.roundaboutExitAngles[i] = packet.state.roundaboutExitAngles[i];
        }
    }
    if (packet.fields & SteedPilot::NavFieldCurrentSpeed) state.currentSpeed = packet.state.currentSpeed;
    if (packet.fields & SteedPilot::NavFieldSpeedLimit) state.speedLimit = packet.state.speedLimit;
    if (packet.fields & SteedPilot::NavFieldSpeedUnit) state.speedUnit = packet.state.speedUnit;
    if (packet.fields & SteedPilot::NavFieldOffRoute) state.offRoute = packet.state.offRoute;
}

void applyBlePacket(const SteedPilot::NavPacket& packet) {
    liveBleMode = true;
    lastPacketMs = millis();
    nextBlePacket = packet;
    pendingBleState = true;
    Serial.printf("BLE packet queued: type=%d fields=%lu\n", (int)packet.type, (unsigned long)packet.fields);
}

void renderNoPhone() {
    SteedPilot::NavState state;
    state.mode = SteedPilot::DisplayMode::NoPhone;
    state.connected = false;
    state.linkState = SteedPilot::LinkState::Disconnected;
    app.setState(state);
    app.render(display);
    noPhoneVisible = true;
    Serial.println("No-phone screen rendered");
}

void renderWaitingForApp() {
    SteedPilot::NavState state;
    state.mode = SteedPilot::DisplayMode::NoPhone;
    state.connected = false;
    state.linkState = SteedPilot::LinkState::Pairing;
    app.setState(state);
    app.render(display);
    noPhoneVisible = true;
    Serial.println("Waiting-for-app screen rendered");
}

void renderWaitingForRoute() {
    SteedPilot::NavState state;
    state.mode = SteedPilot::DisplayMode::NoPhone;
    state.connected = true;
    state.linkState = SteedPilot::LinkState::Connected;
    app.setState(state);
    app.render(display);
    noPhoneVisible = false;
    Serial.println("Waiting-for-route screen rendered");
}

} // namespace

void setup() {
    Serial.begin(115200);
    Serial.println("SteedPilot demo firmware");

    if (!display.begin()) {
        Serial.println("Display init failed");
        return;
    }

    const uint32_t splashStart = millis();
    while (millis() - splashStart < SplashTotalMs) {
        display.splash(splashOpacity(millis() - splashStart));
        delay(16);
    }

    ble.begin(applyBlePacket);
    renderWaitingForApp();
}

void loop() {
    static uint32_t lastTick = millis();
    static uint32_t lastAnimationFrameMs = 0;
    const uint32_t now = millis();

    app.tick(now - lastTick);
    lastTick = now;

    if (pendingBleState) {
        pendingBleState = false;
        if (nextBlePacket.type == SteedPilot::NavPacketType::Heartbeat) {
            Serial.println("BLE heartbeat received");
            if (haveBleState && noPhoneVisible) {
                lastBleState.connected = nextBlePacket.state.connected;
                lastBleState.linkState = nextBlePacket.state.linkState;
                app.setState(lastBleState);
                app.render(display);
                noPhoneVisible = false;
                Serial.println("BLE heartbeat restored last state");
            } else if (!haveBleState) {
                renderWaitingForRoute();
            }
        } else if (nextBlePacket.type == SteedPilot::NavPacketType::State) {
            haveBleState = true;
            lastBleState = nextBlePacket.state;
            app.setState(lastBleState);
            app.render(display);
            noPhoneVisible = false;
            Serial.printf("BLE state rendered: mode=%d maneuver=%d distance=%ld\n", (int)nextBlePacket.state.mode, (int)nextBlePacket.state.maneuver, (long)nextBlePacket.state.distanceToManeuverMeters);
        } else if (haveBleState) {
            SteedPilot::NavState state = lastBleState;
            applyUpdate(state, nextBlePacket);
            lastBleState = state;
            app.setState(lastBleState);
            app.render(display);
            noPhoneVisible = false;
            Serial.printf("BLE update rendered: fields=%lu distance=%ld\n", (unsigned long)nextBlePacket.fields, (long)state.distanceToManeuverMeters);
        } else {
            Serial.println("BLE update ignored before full state");
        }
    }

    if (!pendingBleState && !noPhoneVisible && app.isAnimating() && now - lastAnimationFrameMs >= AnimationFrameMs) {
        app.renderProgressAnimation(display);
        lastAnimationFrameMs = now;
    }

    if (liveBleMode && !pendingBleState && !noPhoneVisible && now - lastPacketMs >= NoPhoneTimeoutMs) {
        renderNoPhone();
    }

    delay(16);
}
