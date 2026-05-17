// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

import Foundation

struct NavFixture: Identifiable {
    let id = UUID()
    let title: String
    let json: String

    var data: Data {
        Data(json.utf8)
    }
}

enum NavFixtures {
    static let all = [
        NavFixture(title: "Roundabout", json: """
        {
          "v": 1,
          "type": "state",
          "mode": "navigation",
          "link": "connected",
          "maneuver": "roundabout",
          "distanceToManeuverMeters": 260,
          "distanceToDestinationMeters": 18400,
          "maneuverProgressRemaining": 58,
          "tripProgressComplete": 44,
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
        """),
        NavFixture(title: "Left", json: """
        {
          "v": 1,
          "type": "state",
          "mode": "navigation",
          "link": "connected",
          "maneuver": "turnLeft",
          "distanceToManeuverMeters": 180,
          "distanceToDestinationMeters": 18400,
          "maneuverProgressRemaining": 22,
          "tripProgressComplete": 32
        }
        """),
        NavFixture(title: "Update", json: """
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
        """),
        NavFixture(title: "Heartbeat", json: """
        {
          "v": 1,
          "type": "heartbeat"
        }
        """),
        NavFixture(title: "Destination", json: """
        {
          "v": 1,
          "type": "state",
          "mode": "destination",
          "link": "connected",
          "distanceToDestinationMeters": 18400,
          "destinationBearingDegrees": 35,
          "tripProgressComplete": 32
        }
        """)
    ]
}
