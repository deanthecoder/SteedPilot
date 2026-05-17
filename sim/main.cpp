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
#include "SteedPilot/NavJson.h"

#include <SDL.h>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

namespace {

constexpr uint32_t SplashFadeInMs = 900;
constexpr uint32_t SplashHoldMs = 2000;
constexpr uint32_t SplashFadeOutMs = 900;
constexpr uint32_t SplashTotalMs = SplashFadeInMs + SplashHoldMs + SplashFadeOutMs;

float splashOpacity(uint32_t elapsedMs) {
    if (elapsedMs < SplashFadeInMs) {
        return (float)elapsedMs / (float)SplashFadeInMs;
    }

    if (elapsedMs < SplashFadeInMs + SplashHoldMs) {
        return 1.0f;
    }

    if (elapsedMs < SplashTotalMs) {
        return 1.0f - (float)(elapsedMs - SplashFadeInMs - SplashHoldMs) / (float)SplashFadeOutMs;
    }

    return 0.0f;
}

SteedPilot::NavState scenarioFor(uint32_t elapsedMs) {
    SteedPilot::NavState state;
    const uint32_t phase = (elapsedMs / 3500) % 5;

    state.distanceToManeuverMeters = 420 - (int32_t)((elapsedMs / 25) % 390);
    state.distanceToDestinationMeters = 18400 - (int32_t)((elapsedMs / 100) % 2500);
    state.maneuverProgressRemaining = 20 + (int8_t)((elapsedMs / 80) % 80);
    state.tripProgressComplete = 30 + (int8_t)((elapsedMs / 300) % 55);
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
        state.mode = SteedPilot::DisplayMode::Navigation;
        state.maneuver = SteedPilot::Maneuver::BendLeft;
    } else if (phase == 3) {
        state.mode = SteedPilot::DisplayMode::Navigation;
        state.maneuver = SteedPilot::Maneuver::UTurn;
    } else {
        state.mode = SteedPilot::DisplayMode::Destination;
    }

    return state;
}

bool loadFixture(const std::string& path, SteedPilot::NavState& state) {
    std::ifstream file(path);
    if (!file) {
        std::cerr << "Could not open fixture: " << path << "\n";
        return false;
    }

    const std::string json((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    if (!SteedPilot::parseNavStateJson(json.c_str(), json.size(), state)) {
        std::cerr << "Could not parse fixture: " << path << "\n";
        return false;
    }

    return true;
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

bool exportScreenshot(SteedPilot::App& app, SdlDisplay& display, const SteedPilot::NavState& state, const char* path) {
    app.setState(state);
    app.render(display);
    return display.savePng(path);
}

bool exportSplashScreenshot(SdlDisplay& display, const SdlImage& logo, const char* path) {
    display.clear(SteedPilot::Palette::Black);
    display.drawImageCentered(logo, 1.0f);
    display.present();
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
    SdlImage logo;

    const std::vector<std::pair<const char*, const char*>> fixtures = {
        {"fixtures/navigation-ahead.json", "img/navigation-ahead.png"},
        {"fixtures/navigation-left.json", "img/navigation-left.png"},
        {"fixtures/navigation-bend-left.json", "img/navigation-bend-left.png"},
        {"fixtures/navigation-u-turn.json", "img/navigation-u-turn.png"},
        {"fixtures/navigation-roundabout.json", "img/navigation-roundabout.png"},
        {"fixtures/navigation-speed-warning.json", "img/navigation-speed-warning.png"},
        {"fixtures/destination-heading.json", "img/destination-heading.png"},
        {"fixtures/disconnected.json", "img/disconnected.png"},
    };

    bool ok = true;
    ok = display.loadPng("img/DTC.png", logo) && ok;
    ok = exportSplashScreenshot(display, logo, "img/startup-dtc.png") && ok;

    for (const auto& fixture : fixtures) {
        SteedPilot::NavState state;
        ok = loadFixture(fixture.first, state) && exportScreenshot(app, display, state, fixture.second) && ok;
    }

    return ok ? 0 : 1;
}

int renderFixture(const std::string& fixturePath, const std::string& outputPath) {
    SdlDisplay display(360, 360, outputPath.empty() ? 2 : 1);
    if (!display.ok()) {
        return 1;
    }

    SteedPilot::UnitSettings units;
    units.distance = SteedPilot::DistanceUnitPreference::MilesMeters;
    SteedPilot::App app(units);
    SteedPilot::NavState state;
    if (!loadFixture(fixturePath, state)) {
        return 1;
    }

    app.setState(state);
    app.render(display);

    if (!outputPath.empty()) {
        return display.savePng(outputPath.c_str()) ? 0 : 1;
    }

    while (display.poll()) {
        SDL_Delay(16);
    }

    return 0;
}

} // namespace

int main(int argc, char** argv) {
    if (argc > 1 && std::string(argv[1]) == "--export-screenshots") {
        return exportScreenshots();
    }

    if (argc > 2 && std::string(argv[1]) == "--fixture") {
        return renderFixture(argv[2], "");
    }

    if (argc > 4 && std::string(argv[1]) == "--export-fixture") {
        return renderFixture(argv[2], argv[4]);
    }

    SdlDisplay display(360, 360, 2);
    if (!display.ok()) {
        return 1;
    }

    SteedPilot::UnitSettings units;
    units.distance = SteedPilot::DistanceUnitPreference::MilesMeters;
    SteedPilot::App app(units);
    SdlImage logo;
    display.loadPng("img/DTC.png", logo);

    const uint32_t start = SDL_GetTicks();
    uint32_t last = start;

    while (display.poll()) {
        const uint32_t now = SDL_GetTicks();
        app.tick(now - last);
        last = now;

        const uint32_t elapsed = now - start;
        if (elapsed < SplashTotalMs && !logo.rgba.empty()) {
            display.clear(SteedPilot::Palette::Black);
            display.drawImageCentered(logo, splashOpacity(elapsed));
            display.present();
        } else {
            app.setState(scenarioFor(elapsed - SplashTotalMs));
            app.render(display);
        }

        SDL_Delay(16);
    }

    return 0;
}
