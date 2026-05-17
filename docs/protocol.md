# SteedPilot BLE Protocol

SteedPilot uses BLE to send small JSON packets from the phone to the ESP32 display.

The ESP32 advertises as `SteedPilot` and exposes one writable navigation-state characteristic.

## Packet Types

### State

`state` replaces the current device state. Send it when the maneuver, mode, roundabout geometry, speed limit, units, or route changes.

```json
{
  "v": 1,
  "type": "state",
  "mode": "navigation",
  "maneuver": "turnLeft",
  "distanceToManeuverMeters": 180,
  "distanceToDestinationMeters": 18400
}
```

### Update

`update` patches only fields present in the packet. Send it frequently while riding for distance, speed, progress, and bearing changes.

```json
{
  "v": 1,
  "type": "update",
  "distanceToManeuverMeters": 120,
  "distanceToDestinationMeters": 18240,
  "maneuverProgressRemaining": 32,
  "tripProgressComplete": 45,
  "speed": {
    "current": 47
  }
}
```

### Heartbeat

`heartbeat` refreshes the no-phone timeout without changing an active navigation screen.

Before the device has received a route state, a heartbeat means the app is alive but no route is active. The device should move from `LAUNCH APP` to `SET ROUTE`.

```json
{
  "v": 1,
  "type": "heartbeat"
}
```

## Route Lifecycle

The phone owns route planning and decides which lifecycle state the display should show.

Initial device startup:

- The device shows `LAUNCH APP` until it receives any packet from the phone.
- A heartbeat before any route state means the phone app is connected, but no route is active.
- The device then shows `SET ROUTE`.

Route selected:

- The phone sends a `state` packet with `mode: "navigation"` and the first useful instruction.
- The device renders that state immediately.
- The phone keeps sending `update` packets while the rider moves.

Route paused or app still open with no route:

- The phone sends heartbeat packets only.
- The device stays on `SET ROUTE` if no route has ever been received.

Phone lost after a route:

- If no packet is received for 10 seconds after route data has started, the device shows `NO PHONE`.
- A later heartbeat restores the last route state.

Arrived:

- The phone sends a `state` packet using `maneuver: "arrive"`.
- The device can show the arrival state until the phone clears or replaces it.

Future lifecycle packets may add an explicit route status field, for example:

```json
{
  "v": 1,
  "type": "state",
  "route": {
    "status": "planning",
    "destinationName": "Ace Cafe"
  }
}
```

The current firmware does not require this object yet; for now the route lifecycle is inferred from packet timing plus navigation state.

## Modes

- `navigation`
- `destination`
- `rideInfo`
- `noPhone`

## Maneuvers

- `continue`
- `bendLeft`
- `slightLeft`
- `turnLeft`
- `sharpLeft`
- `uTurn`
- `slightRight`
- `turnRight`
- `sharpRight`
- `roundabout`
- `arrive`

## Roundabouts

Roundabout exits can include relative angles so the device can draw a schematic closer to real life.

`0` degrees means straight ahead relative to entry. Negative angles are left-ish. Positive angles are right-ish.

```json
{
  "v": 1,
  "type": "state",
  "mode": "navigation",
  "maneuver": "roundabout",
  "roundabout": {
    "exit": 3,
    "exitCount": 5,
    "exits": [
      { "index": 1, "angleDegrees": -105 },
      { "index": 2, "angleDegrees": -20 },
      { "index": 3, "angleDegrees": 35 },
      { "index": 4, "angleDegrees": 95 },
      { "index": 5, "angleDegrees": 150 }
    ]
  }
}
```

## Timing

The phone should send either an `update` or `heartbeat` at least every few seconds while navigation is active.

If the device receives no packets for 10 seconds after live BLE mode has started, it switches to the `NO PHONE` screen.

## Versioning

Every packet should include `"v": 1`.

The device ignores unknown fields. Missing fields keep their current values for `update` packets.
