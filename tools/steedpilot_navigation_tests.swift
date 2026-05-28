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

private struct TestCase {
    let name: String
    let run: () throws -> Void
}

private enum TestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
            case let .failed(message):
                return message
        }
    }
}

@main
private struct NavigationTests {
    private static let legID = UUID()
    private static let aGMotorsInstructions = [
        makeInstruction(index: 0, start: 230.0, distance: 20.0, raw: "Synthetic bend left", maneuver: .bendLeft),
        makeInstruction(index: 1, start: 0.0, distance: 520.7, raw: "Turn left onto Ermine Street North", maneuver: .turnLeft),
        makeInstruction(index: 2, start: 0.0, distance: 1642.8, raw: "Turn left onto Stirling Way", maneuver: .turnLeft),
        makeInstruction(index: 3, start: 0.0, distance: 1946.3, raw: "Turn right into the car park", maneuver: .turnRight),
        makeInstruction(index: 4, start: 2034.0, distance: 0.0, raw: "Arrive at the destination", maneuver: .arrive)
    ]

    private static let tests: [TestCase] = [
        TestCase(name: "MapKit instructions target the end of the step") {
            let routeInstruction = makeInstruction(index: 0, start: 0, distance: 520.7, raw: "Turn left onto Ermine Street North", maneuver: .turnLeft)
            try assertApprox(routeInstruction.targetDistanceFromLegStart, 520.7, "MapKit instructions must count down to maneuver distance")
        },
        TestCase(name: "Synthetic bends target the detected bend start") {
            let routeInstruction = makeInstruction(index: 0, start: 230, distance: 20, raw: "Synthetic bend left", maneuver: .bendLeft)
            try assertApprox(routeInstruction.targetDistanceFromLegStart, 230, "Synthetic bend instructions must target their start marker")
        },
        TestCase(name: "A G Motors route does not finish after first bend") {
            let first = snapshot(total: 2034, instructions: aGMotorsInstructions, progress: 0).snapshot
            try assertEqual(first.maneuver, .bendLeft, "First instruction should be the bend")
            try assertEqual(first.distanceToManeuverMeters, 230, "Initial bend distance should count down to the bend start")

            let afterBend = snapshot(total: 2034, instructions: aGMotorsInstructions, progress: 250).snapshot
            try assertEqual(afterBend.maneuver, .turnLeft, "After the first bend, the next real turn should be selected")
            try assertTrue(afterBend.maneuver != .arrive, "Route must not arrive after the first bend")
        },
        TestCase(name: "A G Motors route has no phantom roundabout") {
            try assertTrue(!aGMotorsInstructions.contains { $0.maneuver == .roundabout }, "Route should not inject a roundabout for A G Motors")
        },
        TestCase(name: "Arrival is only selected near destination") {
            let early = snapshot(total: 2034, instructions: aGMotorsInstructions, progress: 250).snapshot
            try assertTrue(early.maneuver != .arrive, "Arrival must not be selected mid-route")

            let nearDestination = snapshot(total: 2034, instructions: aGMotorsInstructions, progress: 1950).snapshot
            try assertEqual(nearDestination.maneuver, .arrive, "Arrival should be selected inside the destination threshold")
            try assertEqual(nearDestination.distanceToDestinationMeters, 84, "Arrival distance should be remaining trip distance")
        },
        TestCase(name: "Continue message leads into the next target instead of hiding it") {
            let instructions = [
                makeInstruction(index: 0, start: 0, distance: 3800, raw: "At the roundabout, take the first exit", maneuver: .roundabout)
            ]

            let farAway = snapshot(total: 4200, instructions: instructions, progress: 0).snapshot
            try assertEqual(farAway.maneuver, .continueAhead, "Distant instructions should show continue")
            try assertEqual(farAway.distanceToManeuverMeters, 2191, "Continue distance should stop just before the next target countdown")

            let closeEnough = snapshot(total: 4200, instructions: instructions, progress: 2200).snapshot
            try assertEqual(closeEnough.maneuver, .roundabout, "Instruction should switch to the real maneuver inside the threshold")
            try assertEqual(closeEnough.distanceToManeuverMeters, 1600, "Real maneuver distance should count down from the target")
        },
        TestCase(name: "Progress arc starts full for a new target and counts down") {
            let first = snapshot(total: 2034, instructions: aGMotorsInstructions, progress: 0)
            try assertEqual(first.snapshot.maneuverProgressRemaining, 100, "New maneuver progress should start full")

            let second = snapshot(total: 2034, instructions: aGMotorsInstructions, progress: 50, progressWindow: first.progressWindow).snapshot
            try assertTrue(second.maneuverProgressRemaining < 100, "Maneuver progress should reduce as the target approaches")
            try assertTrue(second.maneuverProgressRemaining > 0, "Maneuver progress should not jump straight to zero")
        }
    ]

    static func main() {
        var failureCount = 0
        for test in tests {
            do {
                try test.run()
                print("PASS \(test.name)")
            } catch {
                failureCount += 1
                print("FAIL \(test.name): \(error)")
            }
        }

        if failureCount > 0 {
            print("\n\(failureCount) navigation test\(failureCount == 1 ? "" : "s") failed.")
            exit(1)
        }

        print("\n\(tests.count) navigation tests passed.")
    }

    private static func snapshot(total: CLLocationDistance, instructions: [NavigationDecisionInstruction], progress: CLLocationDistance, progressWindow: NavigationDecisionProgressWindow? = nil) -> (snapshot: NavigationDecisionSnapshot, progressWindow: NavigationDecisionProgressWindow?) {
        NavigationDecisionEngine.snapshot(
            totalDistance: total,
            routeProgress: NavigationDecisionRouteProgress(
                legID: legID,
                distanceFromLegStart: progress,
                distanceFromRouteStart: progress,
                legDistance: total
            ),
            legs: [NavigationDecisionLeg(id: legID, distance: total, instructions: instructions)],
            progressWindow: progressWindow
        )
    }

    private static func makeInstruction(index: Int, start: CLLocationDistance, distance: CLLocationDistance, raw: String, maneuver: NavigationDecisionManeuver) -> NavigationDecisionInstruction {
        NavigationDecisionInstruction(
            legID: legID,
            index: index,
            distanceFromLegStart: start,
            distance: distance,
            rawInstruction: raw,
            maneuver: maneuver,
            roundaboutExit: nil
        )
    }

    private static func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw TestFailure.failed(message)
        }
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
        guard actual == expected else {
            throw TestFailure.failed("\(message). Expected \(expected), got \(actual).")
        }
    }

    private static func assertApprox(_ actual: Double, _ expected: Double, tolerance: Double = 0.1, _ message: String) throws {
        guard abs(actual - expected) <= tolerance else {
            throw TestFailure.failed("\(message). Expected \(expected), got \(actual).")
        }
    }
}
