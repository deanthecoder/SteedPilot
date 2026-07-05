// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

import CoreLocation
import Foundation
import MapKit

private enum TestFailure: Error {
    case failed(String)
}

@main
private struct RouteGeometryTests {
    static func main() throws {
        try testFirstExitUsesPostRoundaboutRoadBearing()
        try testWaypointTransitionCreatesMissingLeftTurn()
        try testWaypointTransitionDoesNotDuplicateMapKitTurn()
        print("3 route geometry tests passed.")
    }

    private static func testFirstExitUsesPostRoundaboutRoadBearing() throws {
        let outgoing = NavigationRouteBuilder.preferredRoundaboutOutgoingBearing(
            coarseOutgoingBearing: 248,
            earlyRoundaboutBearing: 92
        )
        try require(outgoing == 248, "First exit must use the road after the roundabout, not its curved circulating lane")

        let angle = NavigationRouteBuilder.roundaboutDisplayAngle(
            incomingBearing: 165,
            outgoingBearing: outgoing
        )
        try require(angle == 83, "165° to 248° should be displayed as an 83° right exit")
        print("PASS first exit uses post-roundabout road bearing")
    }

    private static func testWaypointTransitionCreatesMissingLeftTurn() throws {
        let waypoint = CLLocationCoordinate2D(latitude: 52.18426, longitude: -0.08286)
        let incoming = polyline([
            waypoint.steedPilotCoordinate(movedMeters: 100, bearingDegrees: 180),
            waypoint
        ])
        let outgoing = polyline([
            waypoint,
            waypoint.steedPilotCoordinate(movedMeters: 100, bearingDegrees: 270)
        ])

        let transition = NavigationRouteBuilder.waypointTransitionStep(
            incomingPolyline: incoming,
            outgoingPolyline: outgoing,
            existingSteps: []
        )
        try require(transition?.deviceManeuver == .turnLeft, "A north-to-west waypoint transition should generate a left turn")
        try require(transition?.targetDistanceFromLegStart == 0, "Waypoint turn should target the start of the outgoing leg")
        print("PASS waypoint transition creates missing left turn")
    }

    private static func testWaypointTransitionDoesNotDuplicateMapKitTurn() throws {
        let waypoint = CLLocationCoordinate2D(latitude: 52.18426, longitude: -0.08286)
        let incoming = polyline([
            waypoint.steedPilotCoordinate(movedMeters: 100, bearingDegrees: 180),
            waypoint
        ])
        let outgoing = polyline([
            waypoint,
            waypoint.steedPilotCoordinate(movedMeters: 100, bearingDegrees: 270)
        ])
        let existing = NavigationRouteStep(
            distanceFromLegStart: 0,
            targetDistanceFromLegStart: 0,
            distance: 100,
            rawInstruction: "Turn left",
            rawNotice: nil,
            sourceManeuver: .turnLeft,
            deviceManeuver: .turnLeft,
            incomingBearing: 0,
            outgoingBearing: 270,
            mapKitRoundaboutExit: nil,
            mapKitRoundaboutExitAngles: [],
            deviceRoundaboutExit: nil,
            deviceRoundaboutExitAngles: [],
            roundaboutApproachDeviationOffset: nil,
            roundaboutApproachProbes: [],
            skipReason: nil
        )

        let transition = NavigationRouteBuilder.waypointTransitionStep(
            incomingPolyline: incoming,
            outgoingPolyline: outgoing,
            existingSteps: [existing]
        )
        try require(transition == nil, "A MapKit maneuver at the leg start must suppress the generated waypoint turn")
        print("PASS waypoint transition does not duplicate MapKit turn")
    }

    private static func polyline(_ coordinates: [CLLocationCoordinate2D]) -> MKPolyline {
        var coordinates = coordinates
        return MKPolyline(coordinates: &coordinates, count: coordinates.count)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw TestFailure.failed(message)
        }
    }
}
