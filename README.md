# SteedPilot
Motorcycle navigation companion powered by iPhone + ESP32 with a clean circular HUD-style display.

## Vision
SteedPilot is a compact motorcycle navigation companion inspired by minimalist devices such as the Beeline Moto II.

The goal is to create a clean, glanceable circular display mounted on a motorcycle handlebar, with an iPhone acting as the primary navigation and routing device.

Rather than rendering full maps on the device itself, SteedPilot focuses on:

- Clear turn-by-turn directions.
- Ride information.
- Minimal rider distraction.
- Fast interaction and readability.
- Compact, premium-looking hardware.

The project aims to feel more like a purpose-built instrument than a tiny computer.

## Core Architecture
SteedPilot is intentionally split into two parts:

### iPhone App
The iPhone app acts as the "brain" of the system.

Responsibilities include:

- Route planning.
- GPS tracking.
- Navigation state.
- Speed limit lookup.
- Heading and destination information.
- BLE communication with the display device.

### ESP32 Device
The ESP32 device acts as a low-power remote display and sensor platform.

Responsibilities include:

- Rendering the circular UI.
- Receiving navigation and telemetry data over BLE.
- Power management.
- Motion detection and wake/sleep behaviour.
- Optional ride telemetry using the onboard IMU.

The embedded device should remain intentionally lightweight and focused.

## Hardware
The initial prototype hardware is based around:

- Waveshare ESP32-S3 1.85" Touch Display Development Board.
- 360x360 circular IPS display.
- ESP32-S3 dual-core processor.
- BLE + WiFi.
- Integrated accelerometer + gyroscope.
- Battery charging support.
- Capacitive touch input.

The long-term goal is a compact, battery-powered device suitable for motorcycle handlebar mounting.

## Planned Modes
SteedPilot is expected to support multiple display modes:

- Navigation.
- Ride information.
- Destination heading.
- Ride summary.
- Display calibration.

The UI should remain clean and glanceable at all times.

Destination heading mode is not intended to be a traditional NSEW compass. It should show a clear arrow pointing toward the destination, plus a remaining-distance indicator.

Distances should be formatted for the rider's selected preference. The initial default is miles for longer distances and meters for shorter distances, with app settings planned for alternatives such as miles/feet and kilometers/meters.

Speed limit warnings should avoid adding another text readout. When current speed exceeds the limit supplied by the phone, the display can show a red circular edge warning that fades from subtle to fully opaque between the speed limit and speed limit + 5 in the rider's selected speed unit.

Navigation maneuvers should support more nuance than simple left/right turns. Planned maneuver data includes slight left/right, standard left/right, sharp left/right, roundabout, and roundabout exit number such as "exit 3". If the phone can provide roundabout exit count as well as the target exit, the device can draw a schematic roundabout with non-target exits muted and the desired exit highlighted.

Route progress can be shown with edge arcs inside the speed warning ring. The trip arc grows toward 100% as the route is completed, while the next-maneuver arc shrinks from 100% to 0% as the upcoming instruction approaches. Long stretches without a near maneuver may use a "stay on this road" style state rather than presenting an unhelpfully distant turn.

## UI Direction
The interface should favour:

- Large readable typography.
- High contrast.
- Minimal clutter.
- Smooth animations.
- Circular/radial UI elements.
- Touch-friendly interactions.

The design should feel modern and instrument-like rather than retro or novelty themed.

## Simulator Screens
The desktop simulator can export reference screenshots for README updates and visual review:

```sh
./sim/build/steedpilot-sim --export-screenshots
```

![Navigation ahead](img/navigation-ahead.png)
![Navigation left](img/navigation-left.png)
![Navigation U-turn](img/navigation-u-turn.png)
![Navigation roundabout](img/navigation-roundabout.png)
![Navigation speed warning](img/navigation-speed-warning.png)
![Destination heading](img/destination-heading.png)
![Display calibration](img/display-calibration.png)
![Startup DTC logo](img/startup-dtc.png)

## Font Assets
The simulator uses a generated anti-aliased single-channel font atlas that can also be consumed by the ESP32 firmware renderer.

Regenerate the atlas after changing the source font, character set, or fixed text sizes:

```sh
python3 tools/generate_font_atlas.py
```

The generator writes:

- `include/SteedPilot/FontAtlas.h`
- `src/generated/FontAtlas.c`

## Interaction Model
The device is expected to primarily use capacitive touch input.

Interactions should be designed around:

- Large touch regions.
- Long-press gestures.
- Simple mode switching.
- Minimal interaction while riding.

The UI should remain stable and resistant to accidental input caused by vibration.

## Development Approach
A desktop simulator will be used for rapid UI iteration and development.

The simulator should allow:

- Rendering the circular UI on desktop.
- Simulating navigation state.
- Simulating BLE packets.
- Testing touch interactions.
- Iterating quickly without repeatedly flashing hardware.

The ESP32 firmware and desktop simulator should share as much rendering and state-management logic as possible.

## Display Calibration
Circular displays can have practical visible bounds that differ slightly from the nominal square panel resolution.

SteedPilot will include a one-off calibration display mode for real-device bring-up. This mode should draw concentric circles, crosshairs, diagonals, and edge markers so the usable circular area can be checked on the Waveshare 360x360 display.

The calibration mode is intended for development only, but it should remain easy to run on hardware whenever display rotation, offsets, or clipping need to be checked.

## Project Principles
- No full map rendering on the device.
- The iPhone handles the complex logic.
- The device should boot and wake quickly.
- The UI should be readable in bright daylight.
- Minimal rider distraction is a priority.
- Keep the embedded side simple and reliable.

## Status
Early planning and prototyping.
