// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

#include "SteedPilot/App.h"

#include <cmath>
#include <cstdio>

namespace SteedPilot {
namespace {

constexpr float Pi = 3.14159265358979323846f;

int centerX(Display& display) {
    return display.width() / 2;
}

int centerY(Display& display) {
    return display.height() / 2;
}

int faceRadius(Display& display) {
    const int smallest = display.width() < display.height() ? display.width() : display.height();
    return smallest / 2 - 5;
}

void drawCircularShell(Display& display) {
    const int cx = centerX(display);
    const int cy = centerY(display);
    const int radius = faceRadius(display);

    display.clear(Palette::Black);
    display.circle(cx, cy, radius, Palette::Dim, 2);
    display.circle(cx, cy, radius - 12, Color{18, 26, 28}, 1);
}

void drawArrow(Display& display, int cx, int cy, int length, float degrees, Color color) {
    const float angle = (degrees - 90.0f) * Pi / 180.0f;
    const float sideA = angle + 2.45f;
    const float sideB = angle - 2.45f;

    const int tipX = cx + (int)(std::cos(angle) * length);
    const int tipY = cy + (int)(std::sin(angle) * length);
    const int tailX = cx - (int)(std::cos(angle) * (length / 3));
    const int tailY = cy - (int)(std::sin(angle) * (length / 3));
    const int wingAX = tipX + (int)(std::cos(sideA) * (length / 3));
    const int wingAY = tipY + (int)(std::sin(sideA) * (length / 3));
    const int wingBX = tipX + (int)(std::cos(sideB) * (length / 3));
    const int wingBY = tipY + (int)(std::sin(sideB) * (length / 3));

    display.line(tailX, tailY, tipX, tipY, color, 6);
    display.line(tipX, tipY, wingAX, wingAY, color, 6);
    display.line(tipX, tipY, wingBX, wingBY, color, 6);
    display.fillCircle(cx, cy, 7, color);
}

const char* maneuverLabel(Maneuver maneuver) {
    switch (maneuver) {
        case Maneuver::TurnLeft: return "LEFT";
        case Maneuver::TurnRight: return "RIGHT";
        case Maneuver::Roundabout: return "R-ABT";
        case Maneuver::Arrive: return "ARRIVE";
        case Maneuver::Continue:
        default: return "AHEAD";
    }
}

float maneuverAngle(Maneuver maneuver) {
    switch (maneuver) {
        case Maneuver::TurnLeft: return -55.0f;
        case Maneuver::TurnRight: return 55.0f;
        case Maneuver::Roundabout: return 120.0f;
        case Maneuver::Arrive: return 0.0f;
        case Maneuver::Continue:
        default: return 0.0f;
    }
}

void drawDistance(Display& display, int y, FormattedDistance distance, Color color) {
    char value[16];
    if (distance.decimalPlaces == 1) {
        std::snprintf(value, sizeof(value), "%ld.%ld", (long)(distance.value / 10), (long)(distance.value % 10));
    } else {
        std::snprintf(value, sizeof(value), "%ld", (long)distance.value);
    }

    display.text(centerX(display), y, value, 5, color, TextAlign::Center);
    display.text(centerX(display), y + 52, distance.unit, 2, Palette::Muted, TextAlign::Center);
}

} // namespace

App::App(UnitSettings units) : _units(units) {}

void App::setState(const NavState& state) {
    _state = state;
}

const NavState& App::state() const {
    return _state;
}

void App::tick(uint32_t elapsedMs) {
    _timeMs += elapsedMs;
}

void App::render(Display& display) {
    switch (_state.mode) {
        case DisplayMode::Destination:
            renderDestination(display);
            break;
        case DisplayMode::RideInfo:
            renderRideInfo(display);
            break;
        case DisplayMode::Calibration:
            renderCalibration(display);
            break;
        case DisplayMode::Navigation:
        default:
            renderNavigation(display);
            break;
    }

    display.present();
}

void App::renderNavigation(Display& display) {
    drawCircularShell(display);

    const int cx = centerX(display);
    const int cy = centerY(display);
    drawArrow(display, cx, cy - 34, 82, maneuverAngle(_state.maneuver), Palette::Cyan);
    drawDistance(display, cy + 66, formatDistanceMeters(_state.distanceToManeuverMeters, _units), Palette::White);
    display.text(cx, 50, maneuverLabel(_state.maneuver), 2, Palette::Muted, TextAlign::Center);

    if (_state.speedLimitMph > 0) {
        char limit[24];
        std::snprintf(limit, sizeof(limit), "limit %d", _state.speedLimitMph);
        display.text(cx, display.height() - 56, limit, 2, Palette::Green, TextAlign::Center);
    }
}

void App::renderDestination(Display& display) {
    drawCircularShell(display);

    const int cx = centerX(display);
    const int cy = centerY(display);
    drawArrow(display, cx, cy - 8, 100, (float)_state.destinationBearingDegrees, Palette::Amber);
    drawDistance(display, cy + 78, formatDistanceMeters(_state.distanceToDestinationMeters, _units), Palette::White);
    display.text(cx, 48, "DEST", 2, Palette::Muted, TextAlign::Center);
}

void App::renderRideInfo(Display& display) {
    drawCircularShell(display);

    display.text(centerX(display), centerY(display) - 36, "RIDE", 4, Palette::White, TextAlign::Center);
    drawDistance(display, centerY(display) + 38, formatDistanceMeters(_state.distanceToDestinationMeters, _units), Palette::Amber);
}

void App::renderCalibration(Display& display) {
    display.clear(Palette::Black);

    const int cx = centerX(display);
    const int cy = centerY(display);
    const int maxRadius = faceRadius(display);

    for (int r = 30; r <= maxRadius; r += 30) {
        display.circle(cx, cy, r, r == maxRadius ? Palette::Red : Palette::Dim, r == maxRadius ? 2 : 1);
    }

    display.line(cx, 0, cx, display.height() - 1, Palette::Cyan, 1);
    display.line(0, cy, display.width() - 1, cy, Palette::Cyan, 1);
    display.line(0, 0, display.width() - 1, display.height() - 1, Palette::Muted, 1);
    display.line(display.width() - 1, 0, 0, display.height() - 1, Palette::Muted, 1);
    display.text(cx, cy - 10, "CAL", 2, Palette::White, TextAlign::Center);
    display.text(cx, cy + 18, "360x360", 1, Palette::Muted, TextAlign::Center);
}

} // namespace SteedPilot
