// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

#include "SdlDisplay.h"

#include "SteedPilot/App.h"

#include <SDL.h>
#include <cstdint>
#include <filesystem>
#include <string>

namespace {

SteedPilot::NavState scenarioFor(uint32_t elapsedMs) {
    SteedPilot::NavState state;
    const uint32_t phase = (elapsedMs / 3500) % 4;

    state.distanceToManeuverMeters = 420 - (int32_t)((elapsedMs / 25) % 390);
    state.distanceToDestinationMeters = 18400 - (int32_t)((elapsedMs / 100) % 2500);
    state.destinationBearingDegrees = (int16_t)((elapsedMs / 30) % 360);
    state.speedLimit = 50;
    state.currentSpeed = 47 + (int16_t)((elapsedMs / 450) % 10);
    state.speedUnit = SteedPilot::SpeedUnit::Mph;

    if (phase == 0) {
        state.mode = SteedPilot::DisplayMode::Navigation;
        state.maneuver = SteedPilot::Maneuver::Continue;
    } else if (phase == 1) {
        state.mode = SteedPilot::DisplayMode::Navigation;
        state.maneuver = SteedPilot::Maneuver::TurnLeft;
    } else if (phase == 2) {
        state.mode = SteedPilot::DisplayMode::Destination;
    } else {
        state.mode = SteedPilot::DisplayMode::Calibration;
    }

    return state;
}

SteedPilot::NavState navigationState(SteedPilot::Maneuver maneuver, int32_t distanceMeters) {
    SteedPilot::NavState state;
    state.mode = SteedPilot::DisplayMode::Navigation;
    state.maneuver = maneuver;
    state.distanceToManeuverMeters = distanceMeters;
    state.distanceToDestinationMeters = 18400;
    state.destinationBearingDegrees = 35;
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
    return state;
}

SteedPilot::NavState calibrationState() {
    SteedPilot::NavState state;
    state.mode = SteedPilot::DisplayMode::Calibration;
    return state;
}

bool exportScreenshot(SteedPilot::App& app, SdlDisplay& display, const SteedPilot::NavState& state, const char* path) {
    app.setState(state);
    app.render(display);
    return display.savePng(path);
}

int exportScreenshots() {
    std::filesystem::create_directories("img");

    SdlDisplay display(360, 360, 1);
    if (!display.ok()) {
        return 1;
    }

    SteedPilot::UnitSettings units;
    units.distance = SteedPilot::DistanceUnitPreference::MilesMeters;
    SteedPilot::App app(units);

    bool ok = true;
    ok = exportScreenshot(app, display, navigationState(SteedPilot::Maneuver::Continue, 420), "img/navigation-ahead.png") && ok;
    ok = exportScreenshot(app, display, navigationState(SteedPilot::Maneuver::TurnLeft, 180), "img/navigation-left.png") && ok;
    ok = exportScreenshot(app, display, speedingState(), "img/navigation-speed-warning.png") && ok;
    ok = exportScreenshot(app, display, destinationState(), "img/destination-heading.png") && ok;
    ok = exportScreenshot(app, display, calibrationState(), "img/display-calibration.png") && ok;

    return ok ? 0 : 1;
}

} // namespace

int main(int argc, char** argv) {
    if (argc > 1 && std::string(argv[1]) == "--export-screenshots") {
        return exportScreenshots();
    }

    SdlDisplay display(360, 360, 2);
    if (!display.ok()) {
        return 1;
    }

    SteedPilot::UnitSettings units;
    units.distance = SteedPilot::DistanceUnitPreference::MilesMeters;
    SteedPilot::App app(units);

    const uint32_t start = SDL_GetTicks();
    uint32_t last = start;

    while (display.poll()) {
        const uint32_t now = SDL_GetTicks();
        app.tick(now - last);
        last = now;

        app.setState(scenarioFor(now - start));
        app.render(display);

        SDL_Delay(16);
    }

    return 0;
}
