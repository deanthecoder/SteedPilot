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

`heartbeat` refreshes the no-phone timeout without changing the visible screen.

```json
{
  "v": 1,
  "type": "heartbeat"
}
```

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
