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

private struct DeviceStage {
    let maneuver: NavigationDecisionManeuver
    let text: String
    let targetMeters: Int
    let mapKitInstruction: String
    let roundaboutExitAngleDegrees: Int?
}

private struct PlannedRouteTest {
    let name: String
    let start: RoutePlanEndpoint
    let destination: RoutePlanEndpoint
    let avoidMotorways: Bool
    let expectedStages: [ExpectedStage]

    init(name: String, start: String, destination: String, expectedStages: [ExpectedStage]) {
        self.name = name
        self.start = .query(start)
        self.destination = .query(destination)
        self.avoidMotorways = false
        self.expectedStages = expectedStages
    }

    init(name: String, startCoordinate: CLLocationCoordinate2D, destinationCoordinate: CLLocationCoordinate2D, avoidMotorways: Bool = false, expectedStages: [ExpectedStage]) {
        self.name = name
        self.start = .coordinate(startCoordinate)
        self.destination = .coordinate(destinationCoordinate)
        self.avoidMotorways = avoidMotorways
        self.expectedStages = expectedStages
    }
}

private enum RoutePlanEndpoint {
    case query(String)
    case coordinate(CLLocationCoordinate2D)
}

private struct PlannedRouteResult {
    let distanceMeters: CLLocationDistance
    let stages: [DeviceStage]
    let bendDiagnostics: [NavigationSyntheticBendDiagnostic]
}

private struct ExpectedStage {
    let maneuver: NavigationDecisionManeuver
    let textContains: String
    let angleRange: ClosedRange<Int>?

    init(_ maneuver: NavigationDecisionManeuver, textContains: String, angleRange: ClosedRange<Int>? = nil) {
        self.maneuver = maneuver
        self.textContains = textContains
        self.angleRange = angleRange
    }
}

private enum RoutePlanFailure: Error, CustomStringConvertible {
    case geocodeFailed(String)
    case routeFailed(String)
    case stageCount(name: String, expected: Int, actual: Int)
    case stageMismatch(name: String, index: Int, expected: ExpectedStage, actual: DeviceStage)
    case staleRoundaboutText(name: String, index: Int, actual: DeviceStage)
    case failed(String)

    var description: String {
        switch self {
            case let .geocodeFailed(query):
                return "Could not geocode '\(query)'"
            case let .routeFailed(name):
                return "Could not calculate route for '\(name)'"
            case let .stageCount(name, expected, actual):
                return "\(name): expected \(expected) stages, got \(actual)"
            case let .stageMismatch(name, index, expected, actual):
                return "\(name) stage \(index + 1): expected \(expected.maneuver.rawValue) containing '\(expected.textContains)', got \(actual.maneuver.rawValue) '\(actual.text)'"
            case let .staleRoundaboutText(name, index, actual):
                return "\(name) stage \(index + 1): non-roundabout instruction still contains roundabout text: '\(actual.mapKitInstruction)'"
            case let .failed(message):
                return message
        }
    }
}

@main
private struct RoutePlanTests {
    private static let tests = [
        PlannedRouteTest(
            name: "CB23 3UG to CB23 3RJ",
            start: "CB23 3UG, UK",
            destination: "CB23 3RJ, UK",
            expectedStages: [
                ExpectedStage(.bendLeft, textContains: "Bend left"),
                ExpectedStage(.arrive, textContains: "Arrive")
            ]
        ),
        PlannedRouteTest(
            name: "CB23 3UG to PE19 6TW",
            start: "CB23 3UG, UK",
            destination: "PE19 6TW, UK",
            expectedStages: [
                ExpectedStage(.bendLeft, textContains: "Bend left"),
                ExpectedStage(.turnRight, textContains: "Right"),
                ExpectedStage(.roundabout, textContains: "exit 1", angleRange: -125 ... -95),
                ExpectedStage(.roundabout, textContains: "exit 2", angleRange: 80 ... 115),
                ExpectedStage(.arrive, textContains: "Arrive")
            ]
        ),
        PlannedRouteTest(
            name: "CB23 3UG to CB23 4EY",
            start: "CB23 3UG, UK",
            destination: "Franks Farm, CB23 4EY, UK",
            expectedStages: [
                ExpectedStage(.bendLeft, textContains: "Bend left"),
                ExpectedStage(.turnRight, textContains: "Right"),
                ExpectedStage(.roundabout, textContains: "exit 3", angleRange: 80 ... 115),
                ExpectedStage(.turnRight, textContains: "Right"),
                ExpectedStage(.turnRight, textContains: "Right"),
                ExpectedStage(.bendLeft, textContains: "Bend left"),
                ExpectedStage(.turnRight, textContains: "Right"),
                ExpectedStage(.bendRight, textContains: "Bend right"),
                ExpectedStage(.turnRight, textContains: "Right"),
                ExpectedStage(.arrive, textContains: "Arrive")
            ]
        ),
        PlannedRouteTest(
            name: "Regression route A",
            startCoordinate: CLLocationCoordinate2D(latitude: 52.2503681, longitude: -0.1147143),
            destinationCoordinate: CLLocationCoordinate2D(latitude: 52.2211188, longitude: -0.0723177),
            avoidMotorways: true,
            expectedStages: [
                ExpectedStage(.bendLeft, textContains: "Bend left"),
                ExpectedStage(.turnLeft, textContains: "Left"),
                ExpectedStage(.roundabout, textContains: "exit 1"),
                ExpectedStage(.roundabout, textContains: "exit 2"),
                ExpectedStage(.roundabout, textContains: "exit 1"),
                ExpectedStage(.roundabout, textContains: "exit 2"),
                ExpectedStage(.roundabout, textContains: "exit 1"),
                ExpectedStage(.turnLeft, textContains: "Left"),
                ExpectedStage(.bendRight, textContains: "Bend right"),
                ExpectedStage(.turnLeft, textContains: "Left"),
                ExpectedStage(.roundabout, textContains: "exit 1", angleRange: -100 ... -60),
                ExpectedStage(.arrive, textContains: "Arrive")
            ]
        )
    ]

    static func main() async {
        var failures: [String] = []

        do {
            try validateOverlappingRoundaboutSuppression()
            print("PASS overlapping roundabout suppression")
        } catch {
            failures.append(String(describing: error))
            print("FAIL overlapping roundabout suppression: \(error)")
        }

        do {
            try validateSignedTurnManeuvers()
            print("PASS signed turn maneuvers")
        } catch {
            failures.append(String(describing: error))
            print("FAIL signed turn maneuvers: \(error)")
        }
        print("")

        for test in tests {
            do {
                let result = try await routeResult(for: test)
                let sentStages = stagesSentByDevicePipeline(for: result)
                printStages(result.stages, sentStages: sentStages, bendDiagnostics: result.bendDiagnostics, for: test)
                try validateNoStaleRoundaboutText(stages: result.stages, name: test.name)
                try validate(stages: sentStages, for: test)
                print("PASS \(test.name)")
            } catch {
                failures.append(String(describing: error))
                print("FAIL \(test.name): \(error)")
            }
            print("")
        }

        if !failures.isEmpty {
            print("\(failures.count) route plan test\(failures.count == 1 ? "" : "s") failed.")
            exit(1)
        }

        print("\(tests.count) route plan test\(tests.count == 1 ? "" : "s") passed.")
    }

    private static func routeResult(for test: PlannedRouteTest) async throws -> PlannedRouteResult {
        let request = MKDirections.Request()
        request.source = try await mapItem(for: test.start)
        request.destination = try await mapItem(for: test.destination)
        request.transportType = .automobile
        request.requestsAlternateRoutes = test.avoidMotorways
        request.highwayPreference = test.avoidMotorways ? .avoid : .any

        let routes = try await MKDirections(request: request).calculate().routes
        guard let route = test.avoidMotorways ? routes.first(where: { !$0.hasHighways }) ?? routes.first : routes.first else {
            throw RoutePlanFailure.routeFailed(test.name)
        }

        let stages = NavigationRouteBuilder.steps(
            polyline: route.polyline,
            routeDistance: route.polyline.steedPilotRouteDistance,
            mapKitSteps: route.steps,
            isFirstLeg: true,
            isFinalLeg: true
        )
        .compactMap(DeviceStage.init)
        let bendDiagnostics = NavigationRouteBuilder.syntheticBendDiagnostics(
            polyline: route.polyline,
            routeDistance: route.polyline.steedPilotRouteDistance,
            mapKitSteps: route.steps,
            isFirstLeg: true,
            isFinalLeg: true
        )

        return PlannedRouteResult(distanceMeters: route.distance, stages: stages, bendDiagnostics: bendDiagnostics)
    }

    private static func stagesSentByDevicePipeline(for result: PlannedRouteResult) -> [DeviceStage] {
        let legID = UUID()
        let leg = NavigationDecisionLeg(
            id: legID,
            distance: result.distanceMeters,
            instructions: result.stages.enumerated().map { index, stage in
                let isSynthetic = stage.mapKitInstruction.hasPrefix("Synthetic ")
                let target = CLLocationDistance(stage.targetMeters)
                return NavigationDecisionInstruction(
                    legID: legID,
                    index: index,
                    distanceFromLegStart: target,
                    targetDistanceFromLegStart: target,
                    distance: 0,
                    rawInstruction: stage.mapKitInstruction,
                    maneuver: stage.maneuver,
                    roundaboutExit: NavigationRouteBuilder.roundaboutExit(from: stage.mapKitInstruction)
                )
            }
        )

        var sentStages: [DeviceStage] = []
        var progressWindow: NavigationDecisionProgressWindow?
        var routeProgress: CLLocationDistance = 0
        var emittedKeys = Set<String>()

        while routeProgress <= result.distanceMeters {
            let decision = NavigationDecisionEngine.snapshot(
                totalDistance: result.distanceMeters,
                routeProgress: NavigationDecisionRouteProgress(
                    legID: legID,
                    distanceFromLegStart: routeProgress,
                    distanceFromRouteStart: routeProgress,
                    legDistance: result.distanceMeters
                ),
                legs: [leg],
                progressWindow: progressWindow
            )
            progressWindow = decision.progressWindow
            let snapshot = decision.snapshot
            let key = "\(snapshot.maneuver.rawValue)|\(Int((snapshot.selectedInstructionTargetOffsetMeters ?? result.distanceMeters).rounded()))"

            if snapshot.maneuver == .arrive {
                let arriveKey = "arrive|\(Int(result.distanceMeters.rounded()))"
                if !emittedKeys.contains(arriveKey),
                   let arrive = result.stages.last(where: { $0.maneuver == .arrive }) {
                    emittedKeys.insert(arriveKey)
                    sentStages.append(arrive)
                }
                break
            }

            if snapshot.maneuver != .continueAhead,
               !emittedKeys.contains(key) {
                emittedKeys.insert(key)
                if let selectedInstruction = snapshot.selectedInstruction,
                   result.stages.indices.contains(selectedInstruction.index) {
                    sentStages.append(result.stages[selectedInstruction.index])
                }
            }

            let nextProgress = min(result.distanceMeters, routeProgress + 10)
            guard nextProgress > routeProgress + 0.5 else {
                break
            }

            routeProgress = nextProgress
        }

        return sentStages
    }

    private static func mapItem(for endpoint: RoutePlanEndpoint) async throws -> MKMapItem {
        switch endpoint {
            case let .query(query):
                let placemark = try await geocode(query)
                return MKMapItem(placemark: MKPlacemark(placemark: placemark))
            case let .coordinate(coordinate):
                return MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        }
    }

    private static func geocode(_ query: String) async throws -> CLPlacemark {
        let placemarks = try await CLGeocoder().geocodeAddressString(query)
        guard let placemark = placemarks.first else {
            throw RoutePlanFailure.geocodeFailed(query)
        }

        return placemark
    }

    private static func validate(stages: [DeviceStage], for test: PlannedRouteTest) throws {
        guard stages.count == test.expectedStages.count else {
            throw RoutePlanFailure.stageCount(name: test.name, expected: test.expectedStages.count, actual: stages.count)
        }

        for (index, expected) in test.expectedStages.enumerated() {
            let actual = stages[index]
            guard actual.maneuver == expected.maneuver,
                  actual.text.localizedCaseInsensitiveContains(expected.textContains) else {
                throw RoutePlanFailure.stageMismatch(name: test.name, index: index, expected: expected, actual: actual)
            }

            if let angleRange = expected.angleRange {
                guard let angle = actual.roundaboutExitAngleDegrees,
                      angleRange.contains(angle) else {
                    throw RoutePlanFailure.stageMismatch(name: test.name, index: index, expected: expected, actual: actual)
                }
            }

            if actual.maneuver != .roundabout,
               actual.mapKitInstruction.localizedCaseInsensitiveContains("roundabout") {
                throw RoutePlanFailure.staleRoundaboutText(name: test.name, index: index, actual: actual)
            }
        }
    }

    private static func validateNoStaleRoundaboutText(stages: [DeviceStage], name: String) throws {
        for (index, stage) in stages.enumerated() {
            if stage.maneuver != .roundabout,
               stage.mapKitInstruction.localizedCaseInsensitiveContains("roundabout") {
                throw RoutePlanFailure.staleRoundaboutText(name: name, index: index, actual: stage)
            }
        }
    }

    private static func validateOverlappingRoundaboutSuppression() throws {
        let weakDuplicate = makeRoundaboutStep(start: 7033, distance: 140, angle: -38)
        let realRoundabout = makeRoundaboutStep(start: 7113, distance: 180, angle: 150)
        let kept = NavigationRouteBuilder.suppressOverlappingRoundaboutSteps([weakDuplicate, realRoundabout])

        try assertEqual(kept.count, 1, "Overlapping duplicate roundabouts should collapse to one instruction")
        try assertEqual(Int(kept[0].distanceFromLegStart.rounded()), 7113, "The later overlapping roundabout should be kept")
        try assertEqual(kept[0].deviceRoundaboutExitAngles.last?.angleDegrees, 150, "The kept roundabout should preserve its exit angle")
    }

    private static func validateSignedTurnManeuvers() throws {
        try assertEqual(NavigationRouteBuilder.signedTurnManeuver(forAngle: -75), .turnLeft, "Strong negative angles should map to left turns")
        try assertEqual(NavigationRouteBuilder.signedTurnManeuver(forAngle: -35), .slightLeft, "Moderate negative angles should map to slight left")
        try assertEqual(NavigationRouteBuilder.signedTurnManeuver(forAngle: 35), .slightRight, "Moderate positive angles should map to slight right")
        try assertEqual(NavigationRouteBuilder.signedTurnManeuver(forAngle: 75), .turnRight, "Strong positive angles should map to right turns")
        try assertEqual(NavigationRouteBuilder.signedTurnManeuver(forAngle: 12), .continueAhead, "Small angle changes should remain continue")
    }

    private static func makeRoundaboutStep(start: CLLocationDistance, distance: CLLocationDistance, angle: Int) -> NavigationRouteStep {
        NavigationRouteStep(
            distanceFromLegStart: start,
            targetDistanceFromLegStart: start,
            distance: distance,
            rawInstruction: "At the roundabout, take the first exit",
            rawNotice: nil,
            sourceManeuver: .roundabout,
            deviceManeuver: .roundabout,
            incomingBearing: nil,
            outgoingBearing: nil,
            mapKitRoundaboutExit: 1,
            mapKitRoundaboutExitAngles: [NavigationRoundaboutExitAngle(index: 1, angleDegrees: angle)],
            deviceRoundaboutExit: 1,
            deviceRoundaboutExitAngles: [NavigationRoundaboutExitAngle(index: 1, angleDegrees: angle)],
            roundaboutApproachDeviationOffset: nil,
            roundaboutApproachProbes: [],
            skipReason: nil
        )
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
        guard actual == expected else {
            throw RoutePlanFailure.failed("\(message). Expected \(expected), got \(actual).")
        }
    }

    private static func printStages(_ plannedStages: [DeviceStage], sentStages: [DeviceStage], bendDiagnostics: [NavigationSyntheticBendDiagnostic], for test: PlannedRouteTest) {
        print("Route: \(test.name)")
        print("Planned device stages:")
        for (index, stage) in plannedStages.enumerated() {
            let angle = stage.roundaboutExitAngleDegrees.map { " angle \($0)deg" } ?? ""
            print("\(index + 1). \(stage.text) @ \(stage.targetMeters)m\(angle)")
            print("   MapKit: \(stage.mapKitInstruction)")
        }
        print("Sent stage order:")
        for (index, stage) in sentStages.enumerated() {
            let angle = stage.roundaboutExitAngleDegrees.map { " angle \($0)deg" } ?? ""
            print("\(index + 1). \(stage.text) @ \(stage.targetMeters)m\(angle)")
        }

        if bendDiagnostics.isEmpty {
            print("Bend candidates: none")
        } else {
            print("Bend candidates:")
            for diagnostic in bendDiagnostics {
                let state = diagnostic.accepted ? "accepted" : "suppressed: \(diagnostic.reason)"
                print("   \(diagnostic.maneuver.deviceText) \(Int(diagnostic.startDistance.rounded()))-\(Int(diagnostic.endDistance.rounded()))m peak \(diagnostic.peakBendiness)deg @ \(Int(diagnostic.peakDistance.rounded()))m delta \(diagnostic.peakDelta)deg \(state)")
            }
        }
    }
}

private extension DeviceStage {
    init?(_ step: NavigationRouteStep) {
        guard let maneuver = step.deviceManeuver else {
            return nil
        }

        self.maneuver = maneuver
        self.text = DeviceStage.text(for: step, maneuver: maneuver)
        self.targetMeters = Int(step.targetDistanceFromLegStart.rounded())
        self.mapKitInstruction = step.rawInstruction
        self.roundaboutExitAngleDegrees = step.deviceRoundaboutExitAngles.last?.angleDegrees
    }

    static func text(for step: NavigationRouteStep, maneuver: NavigationDecisionManeuver) -> String {
        if maneuver == .roundabout,
           let exit = step.deviceRoundaboutExit {
            return "Roundabout exit \(exit)"
        }

        return maneuver.deviceText
    }
}

private extension NavigationDecisionManeuver {
    var deviceText: String {
        switch self {
            case .arrive: return "Arrive"
            case .bendLeft: return "Bend left"
            case .bendRight: return "Bend right"
            case .continueAhead: return "Continue"
            case .exitLeft: return "Exit left"
            case .exitRight: return "Exit right"
            case .roundabout: return "Roundabout"
            case .turnLeft: return "Left"
            case .turnRight: return "Right"
            case .sharpLeft: return "Sharp left"
            case .sharpRight: return "Sharp right"
            case .slightLeft: return "Slight left"
            case .slightRight: return "Slight right"
            case .uTurn: return "U-turn"
        }
    }
}
