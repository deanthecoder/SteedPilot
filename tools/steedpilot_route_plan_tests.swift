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
    let start: String
    let destination: String
    let expectedStages: [ExpectedStage]
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
                ExpectedStage(.turnRight, textContains: "Right"),
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
                ExpectedStage(.bendLeft, textContains: "Bend left"),
                ExpectedStage(.turnRight, textContains: "Right"),
                ExpectedStage(.bendRight, textContains: "Bend right"),
                ExpectedStage(.turnRight, textContains: "Right"),
                ExpectedStage(.turnRight, textContains: "Right"),
                ExpectedStage(.arrive, textContains: "Arrive")
            ]
        )
    ]

    static func main() async {
        var failures: [String] = []

        for test in tests {
            do {
                let result = try await routeResult(for: test)
                let sentStages = stagesSentByDevicePipeline(for: result)
                printStages(result.stages, sentStages: sentStages, bendDiagnostics: result.bendDiagnostics, for: test)
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
        let startPlacemark = try await geocode(test.start)
        let destinationPlacemark = try await geocode(test.destination)
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(placemark: startPlacemark))
        request.destination = MKMapItem(placemark: MKPlacemark(placemark: destinationPlacemark))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        let routes = try await MKDirections(request: request).calculate().routes
        guard let route = routes.first else {
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
                    distanceFromLegStart: stage.maneuver == .arrive || isSynthetic ? target : 0,
                    distance: stage.maneuver == .arrive || isSynthetic ? 0 : target,
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

private extension NavigationRouteStep {
    var targetDistanceFromLegStart: CLLocationDistance {
        rawInstruction.hasPrefix("Synthetic ") ? distanceFromLegStart : distanceFromLegStart + distance
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
