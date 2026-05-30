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
#include "FirmwareMotion.h"
#include "FirmwareTouch.h"

#include "SteedPilot/App.h"

#include <Arduino.h>
#include <BLEDevice.h>
#include <esp_sleep.h>
#include <esp_rtc_time.h>
#include <driver/gpio.h>
#include <driver/rtc_io.h>

namespace {

constexpr uint32_t SplashFadeInMs = 900;
constexpr uint32_t SplashHoldMs = 2000;
constexpr uint32_t SplashFadeOutMs = 900;
constexpr uint32_t SplashTotalMs = SplashFadeInMs + SplashHoldMs + SplashFadeOutMs;
constexpr uint32_t NoPhoneTimeoutMs = 10000;
constexpr uint32_t AnimationFrameMs = 50;
constexpr uint32_t IdleSleepAfterMs = 2 * 60 * 1000;
constexpr uint32_t ActiveLoopDelayMs = 16;
constexpr uint32_t PowerSaveLoopDelayMs = 250;
constexpr uint32_t ActiveCpuMhz = 240;
constexpr uint32_t PowerSaveCpuMhz = 80;
constexpr uint32_t TouchWakeIgnoreMs = 1200;
constexpr uint32_t TouchTapDebounceMs = 80;
constexpr uint32_t TouchSleepQuietMs = 1500;
constexpr uint32_t TouchSleepQuietTimeoutMs = 3000;
constexpr uint32_t UserOffDeepSleepDelayMs = 1000;
constexpr uint32_t ImmediateWakeGuardMs = 1500;

RTC_DATA_ATTR bool userParked = false;
RTC_DATA_ATTR uint64_t userParkedSinceUs = 0;

FirmwareDisplay display;
FirmwareBle ble;
FirmwareMotion motion;
FirmwareTouch touch;
SteedPilot::App app;
bool liveBleMode = false;
bool noPhoneVisible = false;
bool powerSaveMode = false;
volatile bool pendingBleState = false;
volatile uint32_t touchInterruptCount = 0;
volatile uint32_t lastTouchInterruptUs = 0;
uint32_t lastPacketMs = 0;
uint32_t lastWakefulActivityMs = 0;
uint32_t bootMs = 0;
uint32_t lastTouchTapMs = 0;
uint32_t userOffRequestedMs = 0;
bool haveBleState = false;
bool userOffPending = false;
SteedPilot::NavState lastBleState;
SteedPilot::NavPacket nextBlePacket;

void IRAM_ATTR handleTouchInterrupt() {
    const uint32_t nowUs = micros();
    if (nowUs - lastTouchInterruptUs >= TouchTapDebounceMs * 1000UL) {
        lastTouchInterruptUs = nowUs;
        touchInterruptCount = touchInterruptCount + 1;
    }
}

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
    if (packet.type != SteedPilot::NavPacketType::Heartbeat) {
        lastWakefulActivityMs = lastPacketMs;
    }

    nextBlePacket = packet;
    pendingBleState = true;
    Serial.printf("BLE packet queued: type=%d fields=%lu\n", (int)packet.type, (unsigned long)packet.fields);
}

void enterPowerSave(uint32_t now) {
    if (powerSaveMode) {
        return;
    }

    display.setAwake(false);
    setCpuFrequencyMhz(PowerSaveCpuMhz);
    powerSaveMode = true;
    Serial.printf("Power save entered after %lu ms idle\n", (unsigned long)(now - lastWakefulActivityMs));
}

void leavePowerSave(const char* reason) {
    if (!powerSaveMode) {
        return;
    }

    setCpuFrequencyMhz(ActiveCpuMhz);
    display.setAwake(true);
    powerSaveMode = false;
    Serial.printf("Power save exited: %s\n", reason);
}

bool wokeFromTouch() {
    return esp_sleep_get_wakeup_cause() == ESP_SLEEP_WAKEUP_EXT0;
}

gpio_num_t touchWakeGpio() {
    return (gpio_num_t)FirmwareTouch::InterruptPin;
}

void releaseTouchWakePinFromSleep() {
    rtc_gpio_hold_dis(touchWakeGpio());
    rtc_gpio_deinit(touchWakeGpio());
    pinMode(FirmwareTouch::InterruptPin, INPUT_PULLUP);
}

void prepareTouchWakePinForSleep() {
    releaseTouchWakePinFromSleep();
    rtc_gpio_pullup_en(touchWakeGpio());
    rtc_gpio_pulldown_dis(touchWakeGpio());
    rtc_gpio_set_direction_in_sleep(touchWakeGpio(), RTC_GPIO_MODE_INPUT_ONLY);
    rtc_gpio_hold_en(touchWakeGpio());
}

const char* wakeCauseName(esp_sleep_wakeup_cause_t cause) {
    switch (cause) {
        case ESP_SLEEP_WAKEUP_UNDEFINED:
            return "power/reset";
        case ESP_SLEEP_WAKEUP_EXT0:
            return "touch";
        case ESP_SLEEP_WAKEUP_EXT1:
            return "ext1";
        case ESP_SLEEP_WAKEUP_TIMER:
            return "timer";
        case ESP_SLEEP_WAKEUP_TOUCHPAD:
            return "touchpad";
        case ESP_SLEEP_WAKEUP_ULP:
            return "ulp";
        default:
            return "other";
    }
}

bool waitForTouchWakeLineIdle() {
    const uint32_t startMs = millis();
    uint32_t highSinceMs = 0;

    while (millis() - startMs < TouchSleepQuietTimeoutMs) {
        if (digitalRead(FirmwareTouch::InterruptPin) == HIGH) {
            if (highSinceMs == 0) {
                highSinceMs = millis();
            } else if (millis() - highSinceMs >= TouchSleepQuietMs) {
                return true;
            }
        } else {
            highSinceMs = 0;
        }

        delay(10);
    }

    return false;
}

void enterDeepSleep(const char* reason);

void enterPreDisplayDeepSleep(const char* reason) {
    userParked = true;
    releaseTouchWakePinFromSleep();

    while (!waitForTouchWakeLineIdle()) {
        Serial.println("Deep sleep delayed before display init: touch interrupt line stayed active");
        Serial.flush();
        delay(250);
    }

    prepareTouchWakePinForSleep();
    userParkedSinceUs = esp_rtc_get_time_us();
    Serial.printf("Deep sleep entered before display init: %s\n", reason);
    Serial.flush();
    esp_sleep_enable_ext0_wakeup(touchWakeGpio(), 0);
    esp_deep_sleep_start();
}

void cancelUserOff(uint32_t now) {
    lastTouchTapMs = now;
    userOffPending = false;
    userOffRequestedMs = 0;
    userParked = false;
    display.setAwake(true);
    setCpuFrequencyMhz(ActiveCpuMhz);
    powerSaveMode = false;
    lastWakefulActivityMs = now;
    Serial.println("Tap: user display on");
}

void requestUserOff(uint32_t now) {
    lastTouchTapMs = now;
    userOffPending = true;
    userOffRequestedMs = now;
    userParked = true;
    display.setAwake(false);
    detachInterrupt(digitalPinToInterrupt(FirmwareTouch::InterruptPin));
    Serial.println("Tap: user display off; deep sleep in 1s");
}

void enterDeepSleep(const char* reason) {
    detachInterrupt(digitalPinToInterrupt(FirmwareTouch::InterruptPin));
    display.setAwake(false);
    userParked = true;

    releaseTouchWakePinFromSleep();
    if (!waitForTouchWakeLineIdle()) {
        userOffRequestedMs = millis();
        Serial.println("Deep sleep delayed: touch interrupt line stayed active");
        return;
    }

    prepareTouchWakePinForSleep();
    userParkedSinceUs = esp_rtc_get_time_us();
    Serial.printf("Deep sleep entered: %s\n", reason);
    Serial.flush();

    esp_sleep_enable_ext0_wakeup(touchWakeGpio(), 0);
    esp_deep_sleep_start();
}

void updateTouchPowerGesture(uint32_t now) {
    if (userOffPending) {
        noInterrupts();
        touchInterruptCount = 0;
        interrupts();
        return;
    }

    if (now - bootMs < TouchWakeIgnoreMs) {
        noInterrupts();
        touchInterruptCount = 0;
        interrupts();
        return;
    }

    noInterrupts();
    const uint32_t pendingTouchCount = touchInterruptCount;
    touchInterruptCount = 0;
    interrupts();

    if (pendingTouchCount == 0) {
        return;
    }

    for (uint32_t i = 0; i < pendingTouchCount; ++i) {
        if (now - lastTouchTapMs < TouchTapDebounceMs) {
            continue;
        }

        Serial.printf("Touch interrupt accepted: count=%lu\n", (unsigned long)pendingTouchCount);
        if (!display.isAwake()) {
            cancelUserOff(now);
        } else {
            requestUserOff(now);
        }

        return;
    }
}

void updateUserOffPending(uint32_t now) {
    if (!userOffPending || now - userOffRequestedMs < UserOffDeepSleepDelayMs) {
        return;
    }

    enterDeepSleep("user tap");
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
    bootMs = millis();
    const esp_sleep_wakeup_cause_t wakeCause = esp_sleep_get_wakeup_cause();
    releaseTouchWakePinFromSleep();
    Serial.printf("SteedPilot demo firmware startup: wake=%s userParked=%d\n", wakeCauseName(wakeCause), userParked ? 1 : 0);
    if (wakeCause == ESP_SLEEP_WAKEUP_EXT0 && userParked) {
        const uint64_t nowUs = esp_rtc_get_time_us();
        const uint64_t sleptMs = userParkedSinceUs == 0 || nowUs < userParkedSinceUs ? UINT64_MAX : (nowUs - userParkedSinceUs) / 1000;
        Serial.printf("Startup: touch wake after %llu ms\n", (unsigned long long)sleptMs);
        if (sleptMs < ImmediateWakeGuardMs) {
            Serial.println("Startup: touch wake ignored as release bounce");
            Serial.flush();
            enterPreDisplayDeepSleep("release bounce");
        }

        Serial.println("Startup: user tap wake accepted");
        userParked = false;
        userParkedSinceUs = 0;
    } else {
        userParked = false;
        userParkedSinceUs = 0;
    }

    if (!display.begin()) {
        Serial.println("Display init failed");
        return;
    }

    if (!wokeFromTouch()) {
        const uint32_t splashStart = millis();
        while (millis() - splashStart < SplashTotalMs) {
            display.splash(splashOpacity(millis() - splashStart));
            delay(16);
        }
    }

    motion.begin();
    touch.begin();
    noInterrupts();
    touchInterruptCount = 0;
    lastTouchInterruptUs = micros();
    interrupts();
    attachInterrupt(digitalPinToInterrupt(FirmwareTouch::InterruptPin), handleTouchInterrupt, FALLING);
    ble.begin(applyBlePacket);
    lastWakefulActivityMs = millis();
    renderWaitingForApp();
}

void loop() {
    static uint32_t lastTick = millis();
    static uint32_t lastAnimationFrameMs = 0;
    const uint32_t now = millis();

    updateTouchPowerGesture(now);
    updateUserOffPending(now);

    if (userOffPending) {
        delay(ActiveLoopDelayMs);
        return;
    }

    if (motion.update(now)) {
        lastWakefulActivityMs = now;
        leavePowerSave("motion");
        if (haveBleState) {
            app.setState(lastBleState);
            app.render(display);
            noPhoneVisible = false;
        } else {
            renderWaitingForApp();
        }
    }

    app.tick(now - lastTick);
    lastTick = now;

    if (pendingBleState) {
        pendingBleState = false;
        if (nextBlePacket.type == SteedPilot::NavPacketType::Heartbeat) {
            Serial.println("BLE heartbeat received");
        } else if (nextBlePacket.type == SteedPilot::NavPacketType::State) {
            leavePowerSave("BLE state");
            haveBleState = true;
            lastBleState = nextBlePacket.state;
            app.setState(lastBleState);
            app.render(display);
            noPhoneVisible = false;
            Serial.printf("BLE state rendered: mode=%d maneuver=%d distance=%ld\n", (int)nextBlePacket.state.mode, (int)nextBlePacket.state.maneuver, (long)nextBlePacket.state.distanceToManeuverMeters);
        } else if (haveBleState) {
            leavePowerSave("BLE update");
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

    if (!pendingBleState
        && !noPhoneVisible
        && app.isAnimating()
        && app.needsProgressAnimationFrame()
        && now - lastAnimationFrameMs >= AnimationFrameMs) {
        app.renderProgressAnimation(display);
        lastAnimationFrameMs = now;
    }

    if (liveBleMode && !pendingBleState && !noPhoneVisible && now - lastPacketMs >= NoPhoneTimeoutMs) {
        renderNoPhone();
    }

    if (!pendingBleState
        && !powerSaveMode
        && motion.isStillFor(now, IdleSleepAfterMs)
        && now - lastWakefulActivityMs >= IdleSleepAfterMs) {
        enterPowerSave(now);
    }

    delay(powerSaveMode ? PowerSaveLoopDelayMs : ActiveLoopDelayMs);
}
