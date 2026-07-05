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
        makeInstruction(index: 1, start: 520.7, distance: 1122.1, raw: "Turn left onto Ermine Street North", maneuver: .turnLeft),
        makeInstruction(index: 2, start: 1642.8, distance: 303.5, raw: "Turn left onto Stirling Way", maneuver: .turnLeft),
        makeInstruction(index: 3, start: 1946.3, distance: 87.7, raw: "Turn right into the car park", maneuver: .turnRight),
        makeInstruction(index: 4, start: 2034.0, distance: 0.0, raw: "Arrive at the destination", maneuver: .arrive)
    ]

    private static let tests: [TestCase] = [
        TestCase(name: "MapKit instructions target the start of the step") {
            let routeInstruction = makeInstruction(index: 0, start: 0, distance: 520.7, raw: "Turn left onto Ermine Street North", maneuver: .turnLeft)
            try assertApprox(routeInstruction.targetDistanceFromLegStart, 0, "MapKit instructions must count down to the step start")
        },
        TestCase(name: "Synthetic bends target the detected bend start") {
            let routeInstruction = makeInstruction(index: 0, start: 230, distance: 20, raw: "Synthetic bend left", maneuver: .bendLeft)
            try assertApprox(routeInstruction.targetDistanceFromLegStart, 230, "Synthetic bend instructions must target their start marker")
        },
        TestCase(name: "Roundabout countdown targets the approach entry") {
            let instructions = [
                makeInstruction(index: 0, start: 1027, target: 1000, distance: 80, raw: "At the roundabout, take the second exit", maneuver: .roundabout)
            ]

            let approaching = snapshot(total: 1500, instructions: instructions, progress: 973).snapshot
            try assertEqual(approaching.maneuver, .roundabout, "Roundabout should be selected before the entry point")
            try assertEqual(approaching.distanceToManeuverMeters, 27, "Roundabout countdown should target entry, not exit")

            let inside = snapshot(total: 1500, instructions: instructions, progress: 1001).snapshot
            try assertEqual(inside.maneuver, .roundabout, "Roundabout should remain selected after passing entry")
            try assertEqual(inside.distanceToManeuverMeters, 0, "Roundabout countdown should not keep pointing ahead after passing entry")
        },
        TestCase(name: "Roundabout holds active until the exit zone") {
            let instructions = [
                makeInstruction(index: 0, start: 1027, target: 1000, distance: 80, raw: "At the roundabout, take the first exit", maneuver: .roundabout),
                makeInstruction(index: 1, start: 1200, target: 1200, distance: 90, raw: "At the roundabout, take the second exit", maneuver: .roundabout)
            ]

            let onRoundabout = snapshot(total: 1500, instructions: instructions, progress: 1050).snapshot
            try assertEqual(onRoundabout.selectedInstruction?.index, 0, "Current roundabout should hold while inside its route span")
            try assertEqual(onRoundabout.maneuver, .roundabout, "Current roundabout maneuver should stay active in the hold zone")
            try assertEqual(onRoundabout.distanceToManeuverMeters, 0, "Current roundabout distance should remain at zero in the hold zone")

            let afterExitBuffer = snapshot(total: 1500, instructions: instructions, progress: 1123).snapshot
            try assertEqual(afterExitBuffer.selectedInstruction?.index, 1, "Selection should advance after the roundabout exit buffer")
            try assertEqual(afterExitBuffer.distanceToManeuverMeters, 77, "Next roundabout countdown should resume after leaving the first")
        },
        TestCase(name: "Long MapKit roundabout span releases after exit buffer") {
            let instructions = [
                makeInstruction(index: 0, start: 7113, target: 7113, distance: 180, raw: "At the roundabout, take the first exit", maneuver: .roundabout),
                makeInstruction(index: 1, start: 7293, target: 7293, distance: 134, raw: "Arrive at the destination", maneuver: .arrive)
            ]

            let afterExitBuffer = snapshot(total: 7427, instructions: instructions, progress: 7213).snapshot
            try assertEqual(afterExitBuffer.selectedInstruction?.index, 1, "Selection should not keep a long MapKit roundabout step active 100m after entry")
        },
        TestCase(name: "A G Motors route does not finish after first bend") {
            let first = snapshot(total: 2034, instructions: aGMotorsInstructions, progress: 0).snapshot
            try assertEqual(first.maneuver, .bendLeft, "First instruction should be the bend")
            try assertEqual(first.distanceToManeuverMeters, 230, "Initial bend distance should count down to the bend start")

            let afterBend = snapshot(total: 2034, instructions: aGMotorsInstructions, progress: 250).snapshot
            try assertEqual(afterBend.maneuver, .turnLeft, "After the first bend, the next real turn should be selected")
            try assertEqual(afterBend.distanceToManeuverMeters, 271, "Next real turn should count down to the turn step start")
            try assertTrue(afterBend.maneuver != .arrive, "Route must not arrive after the first bend")
        },
        TestCase(name: "Route start instruction is skipped before next useful target") {
            let instructions = [
                makeInstruction(index: 0, start: 0, distance: 230, raw: "Turn right onto Ermine Street North", maneuver: .turnRight),
                makeInstruction(index: 1, start: 230, distance: 20, raw: "Synthetic bend left", maneuver: .bendLeft),
                makeInstruction(index: 2, start: 520, distance: 400, raw: "Turn left", maneuver: .turnLeft)
            ]

            let first = snapshot(total: 1200, instructions: instructions, progress: 0).snapshot
            try assertEqual(first.maneuver, .bendLeft, "A zero-distance route-start instruction should not hide the first real target")
            try assertEqual(first.distanceToManeuverMeters, 230, "First visible target should be the bend distance")
        },
        TestCase(name: "Shortly before a MapKit turn does not count down through the following road") {
            let instructions = [
                makeInstruction(index: 0, start: 1000, distance: 1600, raw: "Turn left onto Long Road", maneuver: .turnLeft),
                makeInstruction(index: 1, start: 2600, distance: 100, raw: "Turn right", maneuver: .turnRight)
            ]

            let beforeTurn = snapshot(total: 3000, instructions: instructions, progress: 995).snapshot
            try assertEqual(beforeTurn.maneuver, .turnLeft, "Turn should already be selected shortly before the step starts")
            try assertEqual(beforeTurn.distanceToManeuverMeters, 5, "Distance should count down to the turn, not the end of the following road")

            let afterLookbehind = snapshot(total: 3000, instructions: instructions, progress: 1016).snapshot
            try assertEqual(afterLookbehind.maneuver, .turnRight, "Once past the turn lookbehind, selection should move to the next target")
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
        TestCase(name: "Early MapKit arrival instruction remains continue") {
            let instructions = [
                makeInstruction(index: 0, start: 1000, distance: 1609, raw: "Arrive at the destination", maneuver: .arrive)
            ]

            let early = snapshot(total: 2609, instructions: instructions, progress: 1000).snapshot
            try assertEqual(early.maneuver, .continueAhead, "An arrival step beginning a mile early must remain continue")
            try assertEqual(early.distanceToDestinationMeters, 1609, "Early arrival should retain the route distance to destination")
        },
        TestCase(name: "Arrival requires physical proximity to destination") {
            let nearRouteEndButPhysicallyDistant = snapshot(
                total: 2034,
                instructions: aGMotorsInstructions,
                progress: 1950,
                destinationDistance: 1609
            ).snapshot
            try assertTrue(nearRouteEndButPhysicallyDistant.maneuver != .arrive, "A route projection near the end must not finish while physically distant")
        },
        TestCase(name: "Arrival remains blocked until armed") {
            let unarmed = snapshot(
                total: 2034,
                instructions: aGMotorsInstructions,
                progress: 1950,
                destinationDistance: 84,
                arrivalArmed: false
            ).snapshot
            try assertTrue(unarmed.maneuver != .arrive, "Starting inside the destination area must not immediately finish a circular route")
        },
        TestCase(name: "Leaving the destination area permanently arms arrival") {
            let armedAwayFromHome = NavigationArrivalPolicy.isArmed(wasArmed: false, destinationDistance: 301)
            let remainsArmedOnReturn = NavigationArrivalPolicy.isArmed(wasArmed: armedAwayFromHome, destinationDistance: 84)
            try assertTrue(armedAwayFromHome, "Moving beyond the departure radius should arm arrival")
            try assertTrue(remainsArmedOnReturn, "Arrival should remain armed when returning home")
        },
        TestCase(name: "Stationary destination fallback still requires arming") {
            try assertTrue(
                NavigationArrivalPolicy.shouldArrive(
                    remainingRouteDistance: 500,
                    destinationDistance: 70,
                    isArmed: true,
                    forceArrival: true
                ),
                "An armed stationary fallback should finish despite uncertain route progress"
            )
            try assertTrue(
                !NavigationArrivalPolicy.shouldArrive(
                    remainingRouteDistance: 0,
                    destinationDistance: 0,
                    isArmed: false,
                    forceArrival: true
                ),
                "A forced arrival must not finish an unarmed circular route at its start"
            )
        },
        TestCase(name: "Stationary destination fallback waits twenty seconds") {
            let now = Date()
            let started = NavigationStationaryArrivalPolicy.stationarySince(
                current: nil,
                isArmed: true,
                destinationDistance: 70,
                speed: 0,
                locationTimestamp: now,
                now: now
            )
            try assertTrue(
                !NavigationStationaryArrivalPolicy.shouldForceArrival(
                    stationarySince: started,
                    now: now.addingTimeInterval(19)
                ),
                "Nineteen stationary seconds should not finish"
            )
            try assertTrue(
                NavigationStationaryArrivalPolicy.shouldForceArrival(
                    stationarySince: started,
                    now: now.addingTimeInterval(20)
                ),
                "Twenty stationary seconds inside 80m should finish"
            )
        },
        TestCase(name: "Stationary destination fallback rejects fresh movement") {
            let now = Date()
            let stationarySince = NavigationStationaryArrivalPolicy.stationarySince(
                current: nil,
                isArmed: true,
                destinationDistance: 70,
                speed: 5,
                locationTimestamp: now,
                now: now
            )
            try assertTrue(stationarySince == nil, "Fresh moving GPS must not start the stationary arrival timer")
        },
        TestCase(name: "Off-route heading targets the active leg destination") {
            try assertEqual(
                NavigationOffRouteGuidance.nextWaypointIndex(
                    activeLegDestinationIndex: 3,
                    waypointCount: 5
                ),
                3,
                "Heading guidance should target the next unvisited waypoint rather than the final destination"
            )
        },
        TestCase(name: "Off-route heading safely falls back to the first waypoint") {
            try assertEqual(
                NavigationOffRouteGuidance.nextWaypointIndex(
                    activeLegDestinationIndex: nil,
                    waypointCount: 5
                ),
                1,
                "Unknown progress should point toward the first waypoint after the start"
            )
            try assertTrue(
                NavigationOffRouteGuidance.nextWaypointIndex(
                    activeLegDestinationIndex: nil,
                    waypointCount: 1
                ) == nil,
                "A route without a destination has no heading target"
            )
        },
        TestCase(name: "Dead reckoning advances briefly along the route") {
            let estimated = NavigationDeadReckoning.estimatedProgress(
                from: 1_000,
                speed: 8,
                locationAge: 5,
                routeBearing: 90,
                course: 95,
                nextConstraintProgress: 1_200,
                totalRouteDistance: 5_000
            )
            try assertApprox(estimated ?? -1, 1_040, "A short GPS gap should advance by speed times elapsed time")
        },
        TestCase(name: "Dead reckoning stops before the next maneuver") {
            let estimated = NavigationDeadReckoning.estimatedProgress(
                from: 1_000,
                speed: 12,
                locationAge: 8,
                routeBearing: 90,
                course: 90,
                nextConstraintProgress: 1_050,
                totalRouteDistance: 5_000
            )
            try assertApprox(estimated ?? -1, 1_045, "Estimated progress must not pass the next maneuver")
        },
        TestCase(name: "Dead reckoning expires and rejects incompatible heading") {
            let expired = NavigationDeadReckoning.estimatedProgress(
                from: 1_000,
                speed: 8,
                locationAge: 9,
                routeBearing: 90,
                course: 90,
                nextConstraintProgress: nil,
                totalRouteDistance: 5_000
            )
            let wrongDirection = NavigationDeadReckoning.estimatedProgress(
                from: 1_000,
                speed: 8,
                locationAge: 5,
                routeBearing: 90,
                course: 180,
                nextConstraintProgress: nil,
                totalRouteDistance: 5_000
            )
            try assertTrue(expired == nil, "Dead reckoning must expire after eight seconds")
            try assertTrue(wrongDirection == nil, "Dead reckoning must not advance when heading disagrees with the route")
        },
        TestCase(name: "Route crossing preserves plausible progress") {
            let candidates = [
                NavigationRouteMatchCandidate(distanceFromRouteStart: 1_020, distanceToRoute: 5, routeBearingDegrees: 0),
                NavigationRouteMatchCandidate(distanceFromRouteStart: 9_000, distanceToRoute: 1, routeBearingDegrees: 180)
            ]
            let selected = NavigationRouteMatching.selectedCandidateIndex(
                candidates: candidates,
                acceptedProgress: 1_000,
                elapsed: 2,
                speed: 8,
                course: 0,
                isOffRoute: false
            )
            try assertEqual(selected, 0, "A nearby crossing must not jump several miles ahead")
        },
        TestCase(name: "Heading disambiguates overlapping route segments") {
            let candidates = [
                NavigationRouteMatchCandidate(distanceFromRouteStart: 1_000, distanceToRoute: 4, routeBearingDegrees: 0),
                NavigationRouteMatchCandidate(distanceFromRouteStart: 1_000, distanceToRoute: 1, routeBearingDegrees: 180)
            ]
            let selected = NavigationRouteMatching.selectedCandidateIndex(
                candidates: candidates,
                acceptedProgress: nil,
                elapsed: 0,
                speed: 8,
                course: 0,
                isOffRoute: false
            )
            try assertEqual(selected, 0, "Travel direction should beat a marginally closer opposing segment")
        },
        TestCase(name: "Off-route threshold accounts for GPS accuracy") {
            try assertApprox(NavigationRouteMatching.offRouteThreshold(horizontalAccuracy: 10), 65, "Accurate GPS should retain the base threshold")
            try assertApprox(NavigationRouteMatching.offRouteThreshold(horizontalAccuracy: 60), 90, "Uncertain GPS should widen the threshold")
        },
        TestCase(name: "Off-route requires sustained bad fixes") {
            try assertTrue(!NavigationRouteMatching.shouldDeclareOffRoute(consecutiveFixes: 1, duration: 12), "One bad fix must not declare off-route")
            try assertTrue(!NavigationRouteMatching.shouldDeclareOffRoute(consecutiveFixes: 3, duration: 4), "A short GPS wobble must not declare off-route")
            try assertTrue(NavigationRouteMatching.shouldDeclareOffRoute(consecutiveFixes: 3, duration: 8), "Sustained bad fixes should declare off-route")
        },
        TestCase(name: "Continue message leads into the next target instead of hiding it") {
            let instructions = [
                makeInstruction(index: 0, start: 3800, distance: 200, raw: "At the roundabout, take the first exit", maneuver: .roundabout)
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

    private static func snapshot(total: CLLocationDistance, instructions: [NavigationDecisionInstruction], progress: CLLocationDistance, progressWindow: NavigationDecisionProgressWindow? = nil, destinationDistance: CLLocationDistance? = nil, arrivalArmed: Bool = true) -> (snapshot: NavigationDecisionSnapshot, progressWindow: NavigationDecisionProgressWindow?) {
        NavigationDecisionEngine.snapshot(
            totalDistance: total,
            routeProgress: NavigationDecisionRouteProgress(
                legID: legID,
                distanceFromLegStart: progress,
                distanceFromRouteStart: progress,
                legDistance: total
            ),
            legs: [NavigationDecisionLeg(id: legID, distance: total, instructions: instructions)],
            progressWindow: progressWindow,
            destinationDistance: destinationDistance,
            arrivalArmed: arrivalArmed
        )
    }

    private static func makeInstruction(index: Int, start: CLLocationDistance, distance: CLLocationDistance, raw: String, maneuver: NavigationDecisionManeuver) -> NavigationDecisionInstruction {
        NavigationDecisionInstruction(
            legID: legID,
            index: index,
            distanceFromLegStart: start,
            targetDistanceFromLegStart: start,
            distance: distance,
            rawInstruction: raw,
            maneuver: maneuver,
            roundaboutExit: nil
        )
    }

    private static func makeInstruction(index: Int, start: CLLocationDistance, target: CLLocationDistance, distance: CLLocationDistance, raw: String, maneuver: NavigationDecisionManeuver) -> NavigationDecisionInstruction {
        NavigationDecisionInstruction(
            legID: legID,
            index: index,
            distanceFromLegStart: start,
            targetDistanceFromLegStart: target,
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
