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
        try testRoundaboutIgnoresPreviousStepCurvature()
        try testShortRoundaboutStepFallsBackToItsEnd()
        try testStraightRoundaboutApproachFallsBackToItsEnd()
        try testCapturedRoundaboutTargets()
        print("7 route geometry tests passed.")
    }

    private static func testRoundaboutIgnoresPreviousStepCurvature() throws {
        let origin = CLLocationCoordinate2D(latitude: 52, longitude: 0)
        let route = localPolyline([[0, 0], [0, 100], [100, 100], [100, 200]], origin: origin)
        let steps = NavigationRouteBuilder.steps(polyline: route, routeDistance: route.steedPilotRouteDistance,
            mapKitSteps: [
                CapturedMapKitStep(distance: 180, instruction: "Continue straight", polyline: route),
                CapturedMapKitStep(distance: 110, instruction: "At the roundabout, turn right", polyline: route)
            ], isFirstLeg: true, isFinalLeg: true)
        guard let roundabout = steps.first(where: { $0.mapKitRoundaboutExit != nil }) else {
            throw TestFailure.failed("Missing roundabout")
        }
        try require(roundabout.targetDistanceFromLegStart >= 180, "Roundabout target must not select the earlier corner")
        try require(roundabout.targetDistanceFromLegStart < 290, "A real heading change within the step should still adjust the target")
        try require(roundabout.roundaboutApproachProbes.allSatisfy { 290 + $0.offset >= 180 }, "Approach baseline must exclude the preceding step")
        print("PASS roundabout ignores previous step curvature")
    }

    private static func testShortRoundaboutStepFallsBackToItsEnd() throws {
        for distance in [5.0, 10.0] {
            let step = try straightRoundaboutStep(start: 1000 - distance, distance: distance)
            try require(abs(step.targetDistanceFromLegStart - 1000) < 0.01, "Insufficient approach data must retain the MapKit endpoint")
            try require(step.roundaboutApproachDeviationOffset == nil, "Zero or one probe cannot establish an entry deviation")
            try require(step.roundaboutApproachProbes.count <= 1, "A short step must not borrow earlier approach samples")
        }
        print("PASS short roundabout steps fall back to their end")
    }

    private static func testStraightRoundaboutApproachFallsBackToItsEnd() throws {
        let step = try straightRoundaboutStep(start: 500, distance: 500)
        try require(abs(step.targetDistanceFromLegStart - 1000) < 0.01, "A straight approach with no detected entry must retain its endpoint")
        try require(step.roundaboutApproachDeviationOffset == nil, "A straight road must not invent an entry deviation")
        print("PASS straight roundabout approach falls back to its end")
    }

    private static func straightRoundaboutStep(start: Double, distance: Double) throws -> NavigationRouteStep {
        let route = localPolyline([[0, 0], [0, 1100]], origin: CLLocationCoordinate2D(latitude: 52, longitude: 0))
        let steps = NavigationRouteBuilder.steps(polyline: route, routeDistance: route.steedPilotRouteDistance,
            mapKitSteps: [
                CapturedMapKitStep(distance: start, instruction: "Continue straight", polyline: route),
                CapturedMapKitStep(distance: distance, instruction: "At the roundabout, take the second exit", polyline: route)
            ], isFirstLeg: true, isFinalLeg: true)
        guard let step = steps.first(where: { $0.mapKitRoundaboutExit != nil }) else { throw TestFailure.failed("Missing roundabout") }
        return step
    }

    private static func testCapturedRoundaboutTargets() throws {
        guard CommandLine.arguments.count == 2 else { throw TestFailure.failed("Provide the decompressed route fixture directory") }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        try require(files.count == 7, "Expected all seven frozen route captures")
        let changes = ["regression-a-reverse:2": 162.0, "regression-a-reverse:4": 125.0, "regression-a:9": 155.0]
        var roundaboutCount = 0
        var changedCount = 0
        var ordinaryCount = 0
        for file in files {
            let snapshot = try JSONDecoder().decode(CapturedRoute.self, from: Data(contentsOf: file))
            let origin = CLLocationCoordinate2D(latitude: snapshot.origin[0], longitude: snapshot.origin[1])
            let route = localPolyline(snapshot.points, origin: origin)
            let mapKitSteps = snapshot.steps.map { CapturedMapKitStep(distance: $0.reportedDistance, instruction: $0.instruction, polyline: localPolyline($0.points, origin: origin)) }
            let actualSteps = NavigationRouteBuilder.steps(polyline: route, routeDistance: route.steedPilotRouteDistance,
                mapKitSteps: mapKitSteps, isFirstLeg: true, isFinalLeg: true)
            for source in snapshot.steps where source.reportedDistance > 1 {
                let start = source.reportedEnd - source.reportedDistance
                guard let before = snapshot.currentSteps.first(where: { $0.instruction == source.instruction && abs($0.start + $0.distance - source.reportedEnd) < 0.01 }),
                      let after = actualSteps.first(where: { $0.rawInstruction == source.instruction && abs($0.distanceFromLegStart + $0.distance - source.reportedEnd) < 0.01 }) else {
                    throw TestFailure.failed("Lost original instruction \(snapshot.id):\(source.index)")
                }
                let key = "\(snapshot.id):\(source.index)"
                let shift = changes[key] ?? 0
                try require(abs(after.targetDistanceFromLegStart - before.target - shift) < 0.01, "Unexpected target change for \(key)")
                try require(after.deviceManeuver?.rawValue == before.deviceManeuver, "Unexpected maneuver type change for \(key)")
                if before.roundaboutExit != nil {
                    roundaboutCount += 1
                    if shift != 0 { changedCount += 1 }
                    try require(after.targetDistanceFromLegStart >= start, "Roundabout target precedes its step: \(key)")
                    try require(after.roundaboutApproachProbes.allSatisfy { source.reportedEnd + $0.offset >= start }, "Probe crosses step boundary: \(key)")
                } else {
                    ordinaryCount += 1
                }
            }
        }
        try require(roundaboutCount == 17 && changedCount == 3, "Expected three corrected targets and fourteen unchanged roundabouts")
        try require(ordinaryCount == 23, "Expected all sixteen ordinary turns and seven arrivals to remain unchanged")
        print("PASS frozen routes: 3 corrected roundabouts, 14 unchanged roundabouts, 23 unchanged turns/arrivals")
    }

    private static func localPolyline(_ points: [[Double]], origin: CLLocationCoordinate2D) -> MKPolyline {
        let originPoint = MKMapPoint(origin)
        let scale = MKMetersPerMapPointAtLatitude(origin.latitude)
        return polyline(points.map { MKMapPoint(x: originPoint.x + $0[0] / scale, y: originPoint.y - $0[1] / scale).coordinate })
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

private struct CapturedRoute: Decodable {
    let id: String
    let origin: [Double]
    let points: [[Double]]
    let steps: [Step]
    let currentSteps: [CurrentStep]
    struct Step: Decodable {
        let index: Int
        let reportedDistance: Double
        let reportedEnd: Double
        let instruction: String
        let points: [[Double]]
    }
    struct CurrentStep: Decodable {
        let instruction: String
        let start: Double
        let distance: Double
        let target: Double
        let deviceManeuver: String?
        let roundaboutExit: Int?
    }
}

// Supply frozen provider inputs to the production route builder without another
// network request, so route changes cannot hide a regression.
private final class CapturedMapKitStep: MKRoute.Step {
    private let capturedDistance: CLLocationDistance
    private let capturedInstruction: String
    private let capturedPolyline: MKPolyline

    init(distance: CLLocationDistance, instruction: String, polyline: MKPolyline) {
        capturedDistance = distance
        capturedInstruction = instruction
        capturedPolyline = polyline
        super.init()
    }

    override var distance: CLLocationDistance { capturedDistance }
    override var instructions: String { capturedInstruction }
    override var polyline: MKPolyline { capturedPolyline }
}
