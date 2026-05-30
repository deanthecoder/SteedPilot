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
#include "SteedPilot/ImageAssets.h"

#include <cmath>
#include <cstdio>

#ifdef STEEDPILOT_PROFILE_RENDER
#include <Arduino.h>
#endif

namespace SteedPilot {
namespace {

constexpr float Pi = 3.14159265358979323846f;
constexpr int InstructionY = 240;
constexpr int DistanceY = 260;
constexpr int UnitY = 318;
constexpr int GraphicOffsetY = 15;
constexpr float ProgressStartDegrees = -130.0f;
constexpr float ProgressSweepDegrees = 260.0f;

#ifdef STEEDPILOT_PROFILE_RENDER
struct RenderProfile {
    const char* kind = nullptr;
    uint32_t startedUs = 0;
    uint32_t clearUs = 0;
    uint32_t arcsUs = 0;
    uint32_t statusUs = 0;
    uint32_t graphicUs = 0;
    uint32_t textUs = 0;
    uint32_t presentUs = 0;
};

RenderProfile activeProfile;

void beginRenderProfile(const char* kind) {
    activeProfile = {};
    activeProfile.kind = kind;
    activeProfile.startedUs = micros();
}

void printRenderProfile() {
    const uint32_t totalUs = micros() - activeProfile.startedUs;
    Serial.printf(
        "render-profile kind=%s total=%lu.%03lums clear=%lu.%03lums arcs=%lu.%03lums status=%lu.%03lums graphic=%lu.%03lums text=%lu.%03lums present=%lu.%03lums\n",
        activeProfile.kind ? activeProfile.kind : "unknown",
        (unsigned long)(totalUs / 1000),
        (unsigned long)(totalUs % 1000),
        (unsigned long)(activeProfile.clearUs / 1000),
        (unsigned long)(activeProfile.clearUs % 1000),
        (unsigned long)(activeProfile.arcsUs / 1000),
        (unsigned long)(activeProfile.arcsUs % 1000),
        (unsigned long)(activeProfile.statusUs / 1000),
        (unsigned long)(activeProfile.statusUs % 1000),
        (unsigned long)(activeProfile.graphicUs / 1000),
        (unsigned long)(activeProfile.graphicUs % 1000),
        (unsigned long)(activeProfile.textUs / 1000),
        (unsigned long)(activeProfile.textUs % 1000),
        (unsigned long)(activeProfile.presentUs / 1000),
        (unsigned long)(activeProfile.presentUs % 1000)
    );
}

class ProfileSection {
public:
    explicit ProfileSection(uint32_t& bucket) : _bucket(bucket), _startedUs(micros()) {}

    ~ProfileSection() {
        _bucket += micros() - _startedUs;
    }

private:
    uint32_t& _bucket;
    uint32_t _startedUs;
};
#endif

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

float easedProgress(float current, int target, uint32_t elapsedMs) {
    if (target < 0) {
        return -1.0f;
    }

    if (current < 0.0f) {
        return (float)target;
    }

    const float alpha = elapsedMs >= 500 ? 1.0f : (float)elapsedMs / 500.0f;
    return current + (((float)target - current) * alpha);
}

float normalizedDegrees(float degrees) {
    while (degrees < 0.0f) {
        degrees += 360.0f;
    }
    while (degrees >= 360.0f) {
        degrees -= 360.0f;
    }

    return degrees;
}

float shortestAngleDelta(float current, float target) {
    float delta = normalizedDegrees(target) - normalizedDegrees(current);
    if (delta > 180.0f) {
        delta -= 360.0f;
    } else if (delta < -180.0f) {
        delta += 360.0f;
    }

    return delta;
}

float easedAngle(float current, int target, uint32_t elapsedMs) {
    if (current < -360.0f) {
        return normalizedDegrees((float)target);
    }

    const float alpha = elapsedMs >= 500 ? 1.0f : (float)elapsedMs / 500.0f;
    return normalizedDegrees(current + shortestAngleDelta(current, (float)target) * alpha);
}

int roundedProgress(float value) {
    if (value < 0.0f) {
        return -1;
    }

    return clampProgress((int)(value + 0.5f));
}

int roundedDegrees(float value) {
    if (value < -360.0f) {
        return -1000;
    }

    return (int)(normalizedDegrees(value) + 0.5f) % 360;
}

void drawTripProgressArc(Display& display, float tripProgress) {
    if (tripProgress < 0.0f) {
        return;
    }

    const int cx = centerX(display);
    const int cy = centerY(display);
    const int radius = faceRadius(display);
    const int trip = clampProgress((int)(tripProgress + 0.5f));

    if (trip >= 0) {
        const float sweep = ProgressSweepDegrees * (float)trip / 100.0f;
        const int arcRadius = radius - 18;
        display.arc(cx, cy, arcRadius, ProgressStartDegrees, ProgressSweepDegrees, Color{38, 32, 17}, 5);
        display.arc(cx, cy, arcRadius, ProgressStartDegrees, sweep, Palette::Amber, 3);
        drawArcMarker(display, cx, cy, arcRadius, ProgressStartDegrees, Palette::Amber, 4);
        drawArcMarker(display, cx, cy, arcRadius, ProgressStartDegrees + ProgressSweepDegrees, Palette::Amber, 4);
    }
}

void drawManeuverProgressArc(Display& display, float maneuverProgress) {
    if (maneuverProgress < 0.0f) {
        return;
    }

    const int cx = centerX(display);
    const int cy = centerY(display);
    const int radius = faceRadius(display);
    const int maneuver = clampProgress((int)(maneuverProgress + 0.5f));

    if (maneuver >= 0) {
        const int complete = 100 - maneuver;
        const float sweep = ProgressSweepDegrees * (float)complete / 100.0f;
        const int arcRadius = radius - 30;
        display.arc(cx, cy, arcRadius, ProgressStartDegrees, ProgressSweepDegrees, Color{8, 30, 32}, 9);
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

void drawLinkStatus(Display& display, const NavState& state) {
    if (state.linkState == LinkState::Connected && state.connected) {
        return;
    }

    const int x = centerX(display) + 86;
    const int y = 76;
    const Color color = state.linkState == LinkState::Pairing ? Palette::Cyan : Palette::Muted;
    display.text(x, y, "BT", 1, color, TextAlign::Center);

    if (state.linkState == LinkState::Disconnected || !state.connected) {
        display.line(x - 10, y + 2, x + 10, y + 18, Palette::Red, 2);
    }
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

uint8_t sampleImageChannel(const SteedPilotGrayAlphaImage& image, float x, float y, int channel) {
    if (x < 0.0f || y < 0.0f || x >= (float)(image.width - 1) || y >= (float)(image.height - 1)) {
        return 0;
    }

    const int x0 = (int)x;
    const int y0 = (int)y;
    const int x1 = x0 + 1;
    const int y1 = y0 + 1;
    const float fx = x - (float)x0;
    const float fy = y - (float)y0;
    const uint8_t* p00 = image.pixels + (y0 * image.width + x0) * 2;
    const uint8_t* p10 = image.pixels + (y0 * image.width + x1) * 2;
    const uint8_t* p01 = image.pixels + (y1 * image.width + x0) * 2;
    const uint8_t* p11 = image.pixels + (y1 * image.width + x1) * 2;
    const float top = (float)p00[channel] + ((float)p10[channel] - (float)p00[channel]) * fx;
    const float bottom = (float)p01[channel] + ((float)p11[channel] - (float)p01[channel]) * fx;
    const float value = top + (bottom - top) * fy;
    return (uint8_t)(value + 0.5f);
}

/**
 * Draws a generated greyscale bitmap around a center point, optionally mirrored
 * and rotated. This keeps desktop screenshots close to the final device output
 * while allowing right-hand maneuvers to reuse the left-hand artwork.
 */
void drawImageTransformed(Display& display, int cx, int cy, const SteedPilotGrayAlphaImage& image, float rotationDegrees = 0.0f, bool mirrorX = false) {
    const float radians = rotationDegrees * Pi / 180.0f;
    const float sinA = std::sin(radians);
    const float cosA = std::cos(radians);
    const float halfW = (float)image.width / 2.0f;
    const float halfH = (float)image.height / 2.0f;
    const int extent = (int)(std::sqrt((float)(image.width * image.width + image.height * image.height)) / 2.0f) + 2;

    for (int dy = -extent; dy <= extent; ++dy) {
        for (int dx = -extent; dx <= extent; ++dx) {
            float sourceX = (float)dx * cosA + (float)dy * sinA;
            const float sourceY = -(float)dx * sinA + (float)dy * cosA;
            if (mirrorX) {
                sourceX = -sourceX;
            }

            sourceX += halfW;
            const float sourcePixelY = sourceY + halfH;
            const uint8_t alpha = sampleImageChannel(image, sourceX, sourcePixelY, 1);
            if (alpha == 0) {
                continue;
            }

            const uint8_t gray = sampleImageChannel(image, sourceX, sourcePixelY, 0);
            const uint8_t value = (uint8_t)(((int)gray * (int)alpha) / 255);
            display.pixel(cx + dx, cy + dy, Color{value, value, value});
        }
    }
}

void drawImageCentered(Display& display, int cx, int cy, const SteedPilotGrayAlphaImage& image) {
    display.image(cx - image.width / 2, cy - image.height / 2, image);
}

void drawContinueLane(Display& display, int cx, int cy, Color color) {
    const int topY = cy - 70;
    const int bottomY = cy + 62;
    const int topHalfWidth = 18;
    const int bottomHalfWidth = 66;
    const int thickness = 8;

    display.line(cx - bottomHalfWidth, bottomY, cx - topHalfWidth, topY, color, thickness);
    display.line(cx + bottomHalfWidth, bottomY, cx + topHalfWidth, topY, color, thickness);
}

void drawTurnLeft(Display& display, int cx, int cy, Color color) {
    const int thickness = 9;

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

void drawExitLeft(Display& display, int cx, int cy, Color color) {
    const Color continuation{18, 38, 40};
    display.line(cx + 30, cy + 52, cx + 30, cy - 62, continuation, 5);
    drawArrowHead(display, cx + 30, cy - 62, 0.0f, 20, continuation, 5);
    drawBendLeft(display, cx, cy + 16, color);
}

void drawExitRight(Display& display, int cx, int cy, Color color) {
    const Color continuation{18, 38, 40};
    display.line(cx - 30, cy + 52, cx - 30, cy - 62, continuation, 5);
    drawArrowHead(display, cx - 30, cy - 62, 0.0f, 20, continuation, 5);
    drawArrow(display, cx, cy - 4, 82, 28.0f, color);
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
    const bool hasAngles = state.roundaboutExitAngleCount > 0;
    const float targetDegrees = hasAngles && targetExit <= state.roundaboutExitAngleCount
        ? (float)state.roundaboutExitAngles[targetExit - 1]
        : startDegrees + stepDegrees * (float)(targetExit - 1);

    display.circle(cx, cy, radius, Palette::Dim, mutedExitThickness);
    for (int i = 0; i < exitCount; ++i) {
        const float degrees = hasAngles && i < state.roundaboutExitAngleCount
            ? (float)state.roundaboutExitAngles[i]
            : startDegrees + stepDegrees * (float)i;
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

void drawRoundaboutBitmap(Display& display, int cx, int cy, const NavState& state) {
    const int exitCount = state.roundaboutExitCount > 0 ? state.roundaboutExitCount : 4;
    const int targetExit = state.roundaboutExit > 0 ? state.roundaboutExit : 1;
    const float startDegrees = -155.0f;
    const float stepDegrees = 250.0f / (float)(exitCount > 1 ? exitCount - 1 : 1);
    const bool hasAngles = state.roundaboutExitAngleCount > 0;
    const float targetDegrees = hasAngles && targetExit <= state.roundaboutExitAngleCount
        ? (float)state.roundaboutExitAngles[targetExit - 1]
        : startDegrees + stepDegrees * (float)(targetExit - 1);

    drawImageTransformed(display, cx, cy, SteedPilotRoundaboutNonExit, 180.0f);

    for (int i = 0; i < exitCount; ++i) {
        const int exitNumber = i + 1;
        if (exitNumber == targetExit) {
            continue;
        }

        const float degrees = hasAngles && i < state.roundaboutExitAngleCount
            ? (float)state.roundaboutExitAngles[i]
            : startDegrees + stepDegrees * (float)i;
        drawImageTransformed(display, cx, cy, SteedPilotRoundaboutNonExit, degrees);
    }

    drawImageTransformed(display, cx, cy, SteedPilotRoundaboutRoute, targetDegrees);
}

void drawDirectionBitmap(Display& display, int cx, int cy, Maneuver maneuver) {
    switch (maneuver) {
        case Maneuver::Continue:
            drawImageCentered(display, cx, cy, SteedPilotDirectionContinue);
            break;
        case Maneuver::BendLeft:
            drawImageCentered(display, cx, cy, SteedPilotDirectionBendLeft);
            break;
        case Maneuver::BendRight:
            drawImageTransformed(display, cx, cy, SteedPilotDirectionBendLeft, 0.0f, true);
            break;
        case Maneuver::ExitLeft:
            drawImageCentered(display, cx, cy, SteedPilotDirectionExitLeft);
            break;
        case Maneuver::SlightLeft:
            drawImageCentered(display, cx, cy, SteedPilotDirectionSlightLeft);
            break;
        case Maneuver::TurnLeft:
            drawImageCentered(display, cx, cy, SteedPilotDirectionTurnLeft);
            break;
        case Maneuver::SharpLeft:
            drawImageCentered(display, cx, cy, SteedPilotDirectionSharpLeft);
            break;
        case Maneuver::UTurn:
            drawImageCentered(display, cx, cy, SteedPilotDirectionUTurnLeft);
            break;
        case Maneuver::ExitRight:
            drawImageTransformed(display, cx, cy, SteedPilotDirectionExitLeft, 0.0f, true);
            break;
        case Maneuver::SlightRight:
            drawImageTransformed(display, cx, cy, SteedPilotDirectionSlightLeft, 0.0f, true);
            break;
        case Maneuver::TurnRight:
            drawImageTransformed(display, cx, cy, SteedPilotDirectionTurnLeft, 0.0f, true);
            break;
        case Maneuver::SharpRight:
            drawImageTransformed(display, cx, cy, SteedPilotDirectionSharpLeft, 0.0f, true);
            break;
        default:
            break;
    }
}

const char* maneuverLabel(Maneuver maneuver) {
    switch (maneuver) {
        case Maneuver::BendLeft: return "BEND IN";
        case Maneuver::BendRight: return "BEND IN";
        case Maneuver::ExitLeft: return "EXIT LEFT IN";
        case Maneuver::SlightLeft: return "SLIGHT LEFT IN";
        case Maneuver::TurnLeft: return "LEFT IN";
        case Maneuver::SharpLeft: return "SHARP LEFT IN";
        case Maneuver::UTurn: return "U TURN IN";
        case Maneuver::ExitRight: return "EXIT RIGHT IN";
        case Maneuver::SlightRight: return "SLIGHT RIGHT IN";
        case Maneuver::TurnRight: return "RIGHT IN";
        case Maneuver::SharpRight: return "SHARP RIGHT IN";
        case Maneuver::Roundabout: return "ROUNDABOUT IN";
        case Maneuver::Arrive: return "ARRIVED";
        case Maneuver::Continue:
        default: return "CONTINUE FOR";
    }
}

const char* immediateManeuverLabel(Maneuver maneuver) {
    switch (maneuver) {
        case Maneuver::BendLeft: return "BEND NOW";
        case Maneuver::BendRight: return "BEND NOW";
        case Maneuver::ExitLeft: return "EXIT LEFT";
        case Maneuver::SlightLeft: return "SLIGHT LEFT";
        case Maneuver::TurnLeft: return "LEFT";
        case Maneuver::SharpLeft: return "SHARP LEFT";
        case Maneuver::UTurn: return "U TURN";
        case Maneuver::ExitRight: return "EXIT RIGHT";
        case Maneuver::SlightRight: return "SLIGHT RIGHT";
        case Maneuver::TurnRight: return "RIGHT";
        case Maneuver::SharpRight: return "SHARP RIGHT";
        case Maneuver::Roundabout: return "ROUNDABOUT";
        case Maneuver::Arrive: return "ARRIVED";
        case Maneuver::Continue:
        default: return "CONTINUE";
    }
}

void maneuverLabelText(const NavState& state, char* buffer, int bufferSize) {
    if (state.distanceToManeuverMeters <= 0) {
        std::snprintf(buffer, bufferSize, "%s", immediateManeuverLabel(state.maneuver));
        return;
    }

    if (state.maneuver == Maneuver::Roundabout && state.roundaboutExit > 0) {
        std::snprintf(buffer, bufferSize, "ROUNDABOUT IN");
        return;
    }

    std::snprintf(buffer, bufferSize, "%s", maneuverLabel(state.maneuver));
}

float maneuverAngle(Maneuver maneuver) {
    switch (maneuver) {
        case Maneuver::BendLeft: return -35.0f;
        case Maneuver::BendRight: return 35.0f;
        case Maneuver::ExitLeft: return -28.0f;
        case Maneuver::SlightLeft: return -28.0f;
        case Maneuver::TurnLeft: return -55.0f;
        case Maneuver::SharpLeft: return -90.0f;
        case Maneuver::UTurn: return 180.0f;
        case Maneuver::ExitRight: return 28.0f;
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

void fillRect(Display& display, int x, int y, int width, int height, Color color) {
    for (int row = 0; row < height; ++row) {
        display.line(x, y + row, x + width - 1, y + row, color, 1);
    }
}

void drawFinishFlag(Display& display, int cx, int cy) {
    display.image(cx - SteedPilotFinishFlag.width / 2, cy - SteedPilotFinishFlag.height / 2, SteedPilotFinishFlag);
}

} // namespace

App::App(UnitSettings units) : _units(units) {}

void App::setState(const NavState& state) {
    _state = state;
    if (_displayTripProgress < 0.0f && state.tripProgressComplete >= 0) {
        _displayTripProgress = (float)state.tripProgressComplete;
    }
    if (_displayManeuverProgress < 0.0f && state.maneuverProgressRemaining >= 0) {
        _displayManeuverProgress = (float)state.maneuverProgressRemaining;
    }
    if (_displayDestinationBearingDegrees < -360.0f) {
        _displayDestinationBearingDegrees = normalizedDegrees((float)state.destinationBearingDegrees);
    }

    _lastRenderedTripProgress = -2;
    _lastRenderedManeuverProgress = -2;
    _lastRenderedDestinationBearingDegrees = -1000;
}

const NavState& App::state() const {
    return _state;
}

void App::tick(uint32_t elapsedMs) {
    _timeMs += elapsedMs;
    _displayTripProgress = easedProgress(_displayTripProgress, _state.tripProgressComplete, elapsedMs);
    _displayManeuverProgress = easedProgress(_displayManeuverProgress, _state.maneuverProgressRemaining, elapsedMs);
    _displayDestinationBearingDegrees = easedAngle(_displayDestinationBearingDegrees, _state.destinationBearingDegrees, elapsedMs);
}

bool App::isAnimating() const {
    return (_state.tripProgressComplete >= 0 && _displayTripProgress >= 0.0f && std::fabs(_displayTripProgress - (float)_state.tripProgressComplete) > 0.5f)
        || (_state.maneuverProgressRemaining >= 0 && _displayManeuverProgress >= 0.0f && std::fabs(_displayManeuverProgress - (float)_state.maneuverProgressRemaining) > 0.5f)
        || (_state.mode == DisplayMode::Destination && _displayDestinationBearingDegrees >= -360.0f && std::fabs(shortestAngleDelta(_displayDestinationBearingDegrees, (float)_state.destinationBearingDegrees)) > 0.5f);
}

bool App::needsProgressAnimationFrame() const {
    const int trip = roundedProgress(_displayTripProgress);
    const int maneuver = roundedProgress(_displayManeuverProgress);
    const int bearing = roundedDegrees(_displayDestinationBearingDegrees);
    return trip != _lastRenderedTripProgress
        || maneuver != _lastRenderedManeuverProgress
        || (_state.mode == DisplayMode::Destination && bearing != _lastRenderedDestinationBearingDegrees);
}

void App::render(Display& display) {
#ifdef STEEDPILOT_PROFILE_RENDER
    beginRenderProfile("full");
#endif

    switch (_state.mode) {
        case DisplayMode::Destination:
            renderDestination(display);
            break;
        case DisplayMode::RideInfo:
            renderRideInfo(display);
            break;
        case DisplayMode::NoPhone:
            renderNoPhone(display);
            break;
        case DisplayMode::Calibration:
            renderCalibration(display);
            break;
        case DisplayMode::Navigation:
        default:
            renderNavigation(display);
            break;
    }

    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.presentUs);
#endif
        display.present();
    }

#ifdef STEEDPILOT_PROFILE_RENDER
    printRenderProfile();
#endif

    _lastRenderedTripProgress = roundedProgress(_displayTripProgress);
    _lastRenderedManeuverProgress = roundedProgress(_displayManeuverProgress);
    _lastRenderedDestinationBearingDegrees = roundedDegrees(_displayDestinationBearingDegrees);
}

void App::renderProgressAnimation(Display& display) {
    if (!needsProgressAnimationFrame()) {
        return;
    }

#ifdef STEEDPILOT_PROFILE_RENDER
    beginRenderProfile("animation");
#endif

    if (_state.mode == DisplayMode::Navigation && _state.maneuver != Maneuver::Arrive) {
        {
#ifdef STEEDPILOT_PROFILE_RENDER
            ProfileSection section(activeProfile.arcsUs);
#endif
            drawTripProgressArc(display, _displayTripProgress);
            drawManeuverProgressArc(display, _displayManeuverProgress);
        }
        {
#ifdef STEEDPILOT_PROFILE_RENDER
            ProfileSection section(activeProfile.presentUs);
#endif
            display.present();
        }
    } else if (_state.mode == DisplayMode::Destination) {
        renderDestination(display);
        {
#ifdef STEEDPILOT_PROFILE_RENDER
            ProfileSection section(activeProfile.presentUs);
#endif
            display.present();
        }
    }

#ifdef STEEDPILOT_PROFILE_RENDER
    printRenderProfile();
#endif

    _lastRenderedTripProgress = roundedProgress(_displayTripProgress);
    _lastRenderedManeuverProgress = roundedProgress(_displayManeuverProgress);
    _lastRenderedDestinationBearingDegrees = roundedDegrees(_displayDestinationBearingDegrees);
}

void App::renderNavigation(Display& display) {
    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.clearUs);
#endif
        drawCircularShell(display);
    }
    if (_state.maneuver != Maneuver::Arrive) {
        {
#ifdef STEEDPILOT_PROFILE_RENDER
            ProfileSection section(activeProfile.arcsUs);
#endif
            drawTripProgressArc(display, _displayTripProgress);
            drawManeuverProgressArc(display, _displayManeuverProgress);
        }
    }
    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.statusUs);
#endif
        drawSpeedWarning(display, _state);
        drawLinkStatus(display, _state);
    }

    const int cx = centerX(display);
    const int cy = centerY(display);
    char label[24];
    maneuverLabelText(_state, label, sizeof(label));

    const int graphicY = cy - 48 + GraphicOffsetY;
    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.graphicUs);
#endif
        if (_state.maneuver == Maneuver::Roundabout) {
            drawRoundaboutBitmap(display, cx, graphicY, _state);
        } else if (_state.maneuver == Maneuver::Arrive) {
            drawFinishFlag(display, cx, cy);
        } else {
            drawDirectionBitmap(display, cx, graphicY, _state.maneuver);
        }
    }
    if (_state.maneuver != Maneuver::Arrive) {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.textUs);
#endif
        if (_state.maneuver == Maneuver::Roundabout) {
            char exitLabel[16];
            std::snprintf(exitLabel, sizeof(exitLabel), "EXIT %d", _state.roundaboutExit);
            display.text(cx, 38, exitLabel, 2, Palette::Muted, TextAlign::Center);
        }
        if (_state.distanceToManeuverMeters > 0) {
            drawDistance(display, formatDistanceMeters(_state.distanceToManeuverMeters, _units), Palette::White);
        }
        display.text(cx, InstructionY, label, 2, Palette::Muted, TextAlign::Center);
    }
}

void App::renderDestination(Display& display) {
    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.clearUs);
#endif
        drawCircularShell(display);
    }
    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.arcsUs);
#endif
        drawTripProgressArc(display, _displayTripProgress);
    }
    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.statusUs);
#endif
        drawSpeedWarning(display, _state);
        drawLinkStatus(display, _state);
    }

    const int cx = centerX(display);
    const int cy = centerY(display);
    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.graphicUs);
#endif
        drawImageTransformed(display, cx, cy - 34 + GraphicOffsetY, SteedPilotDirectionHeading, _displayDestinationBearingDegrees);
    }
    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.textUs);
#endif
        drawDistance(display, formatDistanceMeters(_state.distanceToDestinationMeters, _units), Palette::White);
        display.text(cx, InstructionY, _state.offRoute ? "OFF ROUTE" : "DESTINATION", 2, _state.offRoute ? Palette::Amber : Palette::Muted, TextAlign::Center);
    }
}

void App::renderRideInfo(Display& display) {
    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.clearUs);
#endif
        drawCircularShell(display);
    }
    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.statusUs);
#endif
        drawLinkStatus(display, _state);
    }

    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.textUs);
#endif
        display.text(centerX(display), centerY(display) - 36, "RIDE", 4, Palette::White, TextAlign::Center);
        drawDistance(display, formatDistanceMeters(_state.distanceToDestinationMeters, _units), Palette::Amber);
    }
}

void App::renderNoPhone(Display& display) {
    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.clearUs);
#endif
        drawCircularShell(display);
    }

    const int cx = centerX(display);
    const int cy = centerY(display);
    const char* title = "NO PHONE";
    if (_state.linkState == LinkState::Pairing) {
        title = "LAUNCH APP";
    } else if (_state.linkState == LinkState::Connected) {
        title = "SET ROUTE";
    }

    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.textUs);
#endif
        display.text(cx, cy - 20, title, 2, Palette::White, TextAlign::Center);
        display.text(cx, cy + 18, "WAITING", 2, Palette::Muted, TextAlign::Center);
    }
}

void App::renderCalibration(Display& display) {
    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.clearUs);
#endif
        display.clear(Palette::Black);
    }

    const int cx = centerX(display);
    const int cy = centerY(display);
    const int maxRadius = faceRadius(display);

    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.graphicUs);
#endif
        for (int r = 30; r <= maxRadius; r += 30) {
            display.circle(cx, cy, r, r == maxRadius ? Palette::Red : Palette::Dim, r == maxRadius ? 2 : 1);
        }

        display.line(cx, 0, cx, display.height() - 1, Palette::Cyan, 1);
        display.line(0, cy, display.width() - 1, cy, Palette::Cyan, 1);
        display.line(0, 0, display.width() - 1, display.height() - 1, Palette::Muted, 1);
        display.line(display.width() - 1, 0, 0, display.height() - 1, Palette::Muted, 1);
    }
    {
#ifdef STEEDPILOT_PROFILE_RENDER
        ProfileSection section(activeProfile.textUs);
#endif
        display.text(cx, cy - 10, "CAL", 2, Palette::White, TextAlign::Center);
        display.text(cx, cy + 18, "360x360", 1, Palette::Muted, TextAlign::Center);
    }
}

} // namespace SteedPilot
