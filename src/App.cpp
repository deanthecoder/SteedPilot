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
constexpr int InstructionY = 240;
constexpr int DistanceY = 260;
constexpr int UnitY = 318;
constexpr int GraphicOffsetY = 15;
constexpr float ProgressStartDegrees = -130.0f;
constexpr float ProgressSweepDegrees = 260.0f;

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
    display.clear(Palette::Black);
}

int clampProgress(int value) {
    if (value < 0) {
        return -1;
    }

    if (value > 100) {
        return 100;
    }

    return value;
}

void drawArcMarker(Display& display, int cx, int cy, int radius, float degrees, Color color, int markerRadius) {
    const float radians = (degrees - 90.0f) * Pi / 180.0f;
    const int x = cx + (int)(std::cos(radians) * radius);
    const int y = cy + (int)(std::sin(radians) * radius);

    display.fillCircle(x, y, markerRadius, color);
}

void drawTripProgressArc(Display& display, const NavState& state) {
    const int cx = centerX(display);
    const int cy = centerY(display);
    const int radius = faceRadius(display);
    const int trip = clampProgress(state.tripProgressComplete);

    if (trip >= 0) {
        const float sweep = ProgressSweepDegrees * (float)trip / 100.0f;
        const int arcRadius = radius - 18;
        display.arc(cx, cy, arcRadius, ProgressStartDegrees, ProgressSweepDegrees, Color{38, 32, 17}, 3);
        display.arc(cx, cy, arcRadius, ProgressStartDegrees, sweep, Palette::Amber, 3);
        drawArcMarker(display, cx, cy, arcRadius, ProgressStartDegrees, Palette::Amber, 4);
        drawArcMarker(display, cx, cy, arcRadius, ProgressStartDegrees + ProgressSweepDegrees, Palette::Amber, 4);
    }
}

void drawManeuverProgressArc(Display& display, const NavState& state) {
    const int cx = centerX(display);
    const int cy = centerY(display);
    const int radius = faceRadius(display);
    const int maneuver = clampProgress(state.maneuverProgressRemaining);

    if (maneuver >= 0) {
        const float sweep = ProgressSweepDegrees * (float)maneuver / 100.0f;
        const int arcRadius = radius - 30;
        display.arc(cx, cy, arcRadius, ProgressStartDegrees, ProgressSweepDegrees, Color{8, 30, 32}, 7);
        display.arc(cx, cy, arcRadius, ProgressStartDegrees, sweep, Palette::Cyan, 7);
        drawArcMarker(display, cx, cy, arcRadius, ProgressStartDegrees, Palette::Cyan, 5);
        drawArcMarker(display, cx, cy, arcRadius, ProgressStartDegrees + ProgressSweepDegrees, Palette::Cyan, 5);
    }
}

void drawSpeedWarning(Display& display, const NavState& state) {
    if (state.currentSpeed <= 0 || state.speedLimit <= 0 || state.currentSpeed <= state.speedLimit) {
        return;
    }

    const int fadeRange = 5;
    int overLimit = state.currentSpeed - state.speedLimit;
    if (overLimit > fadeRange) {
        overLimit = fadeRange;
    }

    const int red = 80 + (155 * overLimit) / fadeRange;
    const int green = 12 - (12 * overLimit) / fadeRange;
    const int blue = 10 - (10 * overLimit) / fadeRange;

    display.circle(centerX(display), centerY(display), faceRadius(display) - 2, Color{(uint8_t)red, (uint8_t)green, (uint8_t)blue}, 7);
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

    display.line(tailX, tailY, tipX, tipY, color, 9);
    display.line(tipX, tipY, wingAX, wingAY, color, 9);
    display.line(tipX, tipY, wingBX, wingBY, color, 9);
    display.fillCircle(cx, cy, 9, color);
}

void drawArrowHead(Display& display, int tipX, int tipY, float degrees, int length, Color color, int thickness) {
    const float angle = (degrees - 90.0f) * Pi / 180.0f;
    const float sideA = angle + 2.45f;
    const float sideB = angle - 2.45f;
    const int wingAX = tipX + (int)(std::cos(sideA) * length);
    const int wingAY = tipY + (int)(std::sin(sideA) * length);
    const int wingBX = tipX + (int)(std::cos(sideB) * length);
    const int wingBY = tipY + (int)(std::sin(sideB) * length);

    display.line(tipX, tipY, wingAX, wingAY, color, thickness);
    display.line(tipX, tipY, wingBX, wingBY, color, thickness);
}

void drawTurnLeft(Display& display, int cx, int cy, Color color) {
    const int thickness = 9;
    const Color continuation{22, 46, 48};

    display.line(cx, cy + 62, cx, cy - 58, continuation, 5);
    drawArrowHead(display, cx, cy - 58, 0.0f, 20, continuation, 5);

    display.line(cx, cy + 62, cx, cy - 8, color, thickness);
    display.line(cx, cy - 8, cx - 66, cy - 8, color, thickness);
    drawArrowHead(display, cx - 66, cy - 8, -90.0f, 28, color, thickness);
    display.fillCircle(cx, cy - 8, 8, color);
}

void drawBendLeft(Display& display, int cx, int cy, Color color) {
    const int radius = 55;
    const int arcCx = cx - 25;
    const int arcCy = cy - 5;
    const int entryX = arcCx + radius;
    const int entryY = arcCy;
    const int tipX = arcCx;
    const int tipY = arcCy - radius;

    display.line(entryX, entryY + 60, entryX, entryY, color, 9);
    display.arc(arcCx, arcCy, radius, 0.0f, 90.0f, color, 9);
    drawArrowHead(display, tipX, tipY, -90.0f, 28, color, 9);
}

void drawUTurn(Display& display, int cx, int cy, Color color) {
    const int radius = 34;
    const int thickness = 9;
    display.line(cx - radius, cy + 48, cx - radius, cy, color, thickness);
    display.arc(cx, cy, radius, 270.0f, 180.0f, color, thickness);
    display.line(cx + radius, cy, cx + radius, cy + 48, color, thickness);
    drawArrowHead(display, cx + radius, cy + 48, 180.0f, 28, color, thickness);
}

void drawRoundabout(Display& display, int cx, int cy, const NavState& state) {
    const int exitCount = state.roundaboutExitCount > 0 ? state.roundaboutExitCount : 4;
    const int targetExit = state.roundaboutExit > 0 ? state.roundaboutExit : 1;
    const int radius = 42;
    const int exitLength = 32;
    const int mutedExitThickness = 5;
    const int routeThickness = 9;
    const float startDegrees = -155.0f;
    const float stepDegrees = 250.0f / (float)(exitCount > 1 ? exitCount - 1 : 1);
    const float targetDegrees = startDegrees + stepDegrees * (float)(targetExit - 1);

    display.circle(cx, cy, radius, Palette::Dim, mutedExitThickness);
    for (int i = 0; i < exitCount; ++i) {
        const float degrees = startDegrees + stepDegrees * (float)i;
        const float radians = (degrees - 90.0f) * Pi / 180.0f;
        const int innerX = cx + (int)(std::cos(radians) * (radius + mutedExitThickness / 2));
        const int innerY = cy + (int)(std::sin(radians) * (radius + mutedExitThickness / 2));
        const int outerX = cx + (int)(std::cos(radians) * (radius + exitLength));
        const int outerY = cy + (int)(std::sin(radians) * (radius + exitLength));

        display.line(innerX, innerY, outerX, outerY, Palette::Dim, mutedExitThickness);
    }

    float routeSweep = targetDegrees - 180.0f;
    if (routeSweep < 0.0f) {
        routeSweep += 360.0f;
    }

    display.line(cx, cy + radius + exitLength, cx, cy + radius + routeThickness / 2, Palette::Cyan, routeThickness);
    display.arc(cx, cy, radius, 180.0f, routeSweep, Palette::Cyan, routeThickness);

    const float targetRadians = (targetDegrees - 90.0f) * Pi / 180.0f;
    const int targetInnerX = cx + (int)(std::cos(targetRadians) * (radius + routeThickness / 2));
    const int targetInnerY = cy + (int)(std::sin(targetRadians) * (radius + routeThickness / 2));
    const int targetOuterX = cx + (int)(std::cos(targetRadians) * (radius + exitLength));
    const int targetOuterY = cy + (int)(std::sin(targetRadians) * (radius + exitLength));

    display.line(targetInnerX, targetInnerY, targetOuterX, targetOuterY, Palette::Cyan, routeThickness);
    display.fillCircle(targetOuterX, targetOuterY, 7, Palette::Cyan);
}

const char* maneuverLabel(Maneuver maneuver) {
    switch (maneuver) {
        case Maneuver::BendLeft: return "BEND IN";
        case Maneuver::SlightLeft: return "SLIGHT LEFT IN";
        case Maneuver::TurnLeft: return "LEFT IN";
        case Maneuver::SharpLeft: return "SHARP LEFT IN";
        case Maneuver::UTurn: return "U TURN IN";
        case Maneuver::SlightRight: return "SLIGHT RIGHT IN";
        case Maneuver::TurnRight: return "RIGHT IN";
        case Maneuver::SharpRight: return "SHARP RIGHT IN";
        case Maneuver::Roundabout: return "ROUNDABOUT IN";
        case Maneuver::Arrive: return "ARRIVE IN";
        case Maneuver::Continue:
        default: return "CONTINUE FOR";
    }
}

void maneuverLabelText(const NavState& state, char* buffer, int bufferSize) {
    if (state.maneuver == Maneuver::Roundabout && state.roundaboutExit > 0) {
        std::snprintf(buffer, bufferSize, "ROUNDABOUT IN");
        return;
    }

    std::snprintf(buffer, bufferSize, "%s", maneuverLabel(state.maneuver));
}

float maneuverAngle(Maneuver maneuver) {
    switch (maneuver) {
        case Maneuver::BendLeft: return -35.0f;
        case Maneuver::SlightLeft: return -28.0f;
        case Maneuver::TurnLeft: return -55.0f;
        case Maneuver::SharpLeft: return -90.0f;
        case Maneuver::UTurn: return 180.0f;
        case Maneuver::SlightRight: return 28.0f;
        case Maneuver::TurnRight: return 55.0f;
        case Maneuver::SharpRight: return 90.0f;
        case Maneuver::Roundabout: return 120.0f;
        case Maneuver::Arrive: return 0.0f;
        case Maneuver::Continue:
        default: return 0.0f;
    }
}

void drawDistance(Display& display, FormattedDistance distance, Color color) {
    char value[16];
    if (distance.decimalPlaces == 1) {
        std::snprintf(value, sizeof(value), "%ld.%ld", (long)(distance.value / 10), (long)(distance.value % 10));
    } else {
        std::snprintf(value, sizeof(value), "%ld", (long)distance.value);
    }

    display.text(centerX(display), DistanceY, value, 5, color, TextAlign::Center);
    display.text(centerX(display), UnitY, distance.unit, 2, Palette::Muted, TextAlign::Center);
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
    drawTripProgressArc(display, _state);
    drawManeuverProgressArc(display, _state);
    drawSpeedWarning(display, _state);

    const int cx = centerX(display);
    const int cy = centerY(display);
    char label[24];
    maneuverLabelText(_state, label, sizeof(label));

    if (_state.maneuver == Maneuver::Roundabout) {
        drawRoundabout(display, cx, cy - 34 + GraphicOffsetY, _state);
        char exitLabel[16];
        std::snprintf(exitLabel, sizeof(exitLabel), "EXIT %d", _state.roundaboutExit);
        display.text(cx, 38, exitLabel, 2, Palette::Muted, TextAlign::Center);
    } else if (_state.maneuver == Maneuver::BendLeft) {
        drawBendLeft(display, cx, cy - 44 + GraphicOffsetY, Palette::Cyan);
    } else if (_state.maneuver == Maneuver::TurnLeft) {
        drawTurnLeft(display, cx, cy - 36 + GraphicOffsetY, Palette::Cyan);
    } else if (_state.maneuver == Maneuver::UTurn) {
        drawUTurn(display, cx, cy - 52 + GraphicOffsetY, Palette::Cyan);
    } else {
        drawArrow(display, cx, cy - 34 + GraphicOffsetY, 82, maneuverAngle(_state.maneuver), Palette::Cyan);
    }
    drawDistance(display, formatDistanceMeters(_state.distanceToManeuverMeters, _units), Palette::White);
    display.text(cx, InstructionY, label, 2, Palette::Muted, TextAlign::Center);
}

void App::renderDestination(Display& display) {
    drawCircularShell(display);
    drawTripProgressArc(display, _state);

    const int cx = centerX(display);
    const int cy = centerY(display);
    drawArrow(display, cx, cy - 34 + GraphicOffsetY, 88, (float)_state.destinationBearingDegrees, Palette::Amber);
    drawDistance(display, formatDistanceMeters(_state.distanceToDestinationMeters, _units), Palette::White);
    display.text(cx, InstructionY, "DESTINATION", 2, Palette::Muted, TextAlign::Center);
}

void App::renderRideInfo(Display& display) {
    drawCircularShell(display);

    display.text(centerX(display), centerY(display) - 36, "RIDE", 4, Palette::White, TextAlign::Center);
    drawDistance(display, formatDistanceMeters(_state.distanceToDestinationMeters, _units), Palette::Amber);
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
