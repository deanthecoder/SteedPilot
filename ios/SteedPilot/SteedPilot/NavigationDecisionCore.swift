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

enum NavigationDecisionManeuver: String {
    case bendLeft
    case bendRight
    case exitLeft
    case slightLeft
    case turnLeft
    case sharpLeft
    case uTurn
    case continueAhead = "continue"
    case exitRight
    case slightRight
    case turnRight
    case sharpRight
    case roundabout
    case arrive

    init(instruction: String) {
        let text = instruction.lowercased()

        if text.contains("roundabout") {
            self = .roundabout
        } else if text.contains("u-turn") || text.contains("u turn") {
            self = .uTurn
        } else if text.contains("arrive") || text.contains("destination") {
            self = .arrive
        } else if text.contains("take the exit") || text.contains("take exit") {
            self = .exitLeft
        } else if text.contains("sharp left") {
            self = .sharpLeft
        } else if text.contains("slight left") {
            self = .slightLeft
        } else if text.contains("bear left") || text.contains("keep left") {
            self = .bendLeft
        } else if text.contains("left") {
            self = .turnLeft
        } else if text.contains("sharp right") {
            self = .sharpRight
        } else if text.contains("slight right") {
            self = .slightRight
        } else if text.contains("bear right") || text.contains("keep right") {
            self = .bendRight
        } else if text.contains("right") {
            self = .turnRight
        } else {
            self = .continueAhead
        }
    }

    var isMeaningfulDirection: Bool {
        self != .continueAhead
    }

    var isBend: Bool {
        self == .bendLeft || self == .bendRight
    }

    var isWaypointSeamCandidate: Bool {
        switch self {
            case .turnLeft, .turnRight, .slightLeft, .slightRight, .bendLeft, .bendRight:
                return true
            default:
                return false
        }
    }

    var debugTitle: String {
        switch self {
            case .bendLeft: return "bend left"
            case .bendRight: return "bend right"
            case .exitLeft: return "exit left"
            case .slightLeft: return "slight left"
            case .turnLeft: return "left"
            case .sharpLeft: return "sharp left"
            case .uTurn: return "u-turn"
            case .continueAhead: return "continue"
            case .exitRight: return "exit right"
            case .slightRight: return "slight right"
            case .turnRight: return "right"
            case .sharpRight: return "sharp right"
            case .roundabout: return "roundabout"
            case .arrive: return "arrive"
        }
    }
}

struct NavigationDecisionInstruction {
    let legID: UUID
    let index: Int
    let distanceFromLegStart: CLLocationDistance
    let targetDistanceFromLegStart: CLLocationDistance
    let distance: CLLocationDistance
    let rawInstruction: String
    let maneuver: NavigationDecisionManeuver
    let roundaboutExit: Int?
}

struct NavigationDecisionLeg {
    let id: UUID
    let distance: CLLocationDistance
    let instructions: [NavigationDecisionInstruction]
}

struct NavigationDecisionRouteProgress {
    let legID: UUID
    let distanceFromLegStart: CLLocationDistance
    let distanceFromRouteStart: CLLocationDistance
    let legDistance: CLLocationDistance
}

struct NavigationDecisionProgressWindow {
    let signature: String
    let startDistanceMeters: CLLocationDistance
}

struct NavigationDecisionSelection {
    let instruction: NavigationDecisionInstruction
    let routeOffset: CLLocationDistance
    let targetOffset: CLLocationDistance
}

struct NavigationDecisionSnapshot {
    let distanceToDestinationMeters: Int
    let distanceToManeuverMeters: Int
    let tripProgressComplete: Int
    let maneuverProgressRemaining: Int
    let maneuver: NavigationDecisionManeuver
    let selectedInstruction: NavigationDecisionInstruction?
    let selectedInstructionOffsetMeters: CLLocationDistance?
    let selectedInstructionEndMeters: CLLocationDistance?
    let selectedInstructionTargetOffsetMeters: CLLocationDistance?
    let routeProgressMeters: CLLocationDistance
    let selectionReason: String
}

struct NavigationRouteMatchCandidate {
    let distanceFromRouteStart: CLLocationDistance
    let distanceToRoute: CLLocationDistance
    let routeBearingDegrees: Double
}

enum NavigationRouteMatching {
    static func selectedCandidateIndex(
        candidates: [NavigationRouteMatchCandidate],
        acceptedProgress: CLLocationDistance?,
        elapsed: TimeInterval,
        speed: CLLocationSpeed,
        course: CLLocationDirection?,
        isOffRoute: Bool
    ) -> Int? {
        let eligibleCandidates: [(offset: Int, element: NavigationRouteMatchCandidate)]
        if isOffRoute || acceptedProgress == nil {
            eligibleCandidates = Array(candidates.enumerated())
        } else {
            let maximumForwardProgress = max(250, max(speed, 0) * max(elapsed, 1) * 3 + 100)
            eligibleCandidates = candidates.enumerated().filter {
                guard let acceptedProgress else {
                    return true
                }

                let progressDelta = $0.element.distanceFromRouteStart - acceptedProgress
                return progressDelta >= -80 && progressDelta <= maximumForwardProgress
            }
        }

        return eligibleCandidates.min {
            score($0.element, course: course) < score($1.element, course: course)
        }?.offset
    }

    static func offRouteThreshold(horizontalAccuracy: CLLocationAccuracy) -> CLLocationDistance {
        max(65, horizontalAccuracy * 1.5)
    }

    static func shouldDeclareOffRoute(consecutiveFixes: Int, duration: TimeInterval) -> Bool {
        consecutiveFixes >= 3 && duration >= 8
    }

    private static func score(_ candidate: NavigationRouteMatchCandidate, course: CLLocationDirection?) -> Double {
        guard let course else {
            return candidate.distanceToRoute
        }

        let difference = abs(
            ((candidate.routeBearingDegrees - course + 540).truncatingRemainder(dividingBy: 360)) - 180
        )
        return candidate.distanceToRoute + (difference / 180 * 40)
    }
}

enum NavigationArrivalPolicy {
    static func isArmed(wasArmed: Bool, destinationDistance: CLLocationDistance) -> Bool {
        wasArmed || destinationDistance > 300
    }

    static func shouldArrive(
        remainingRouteDistance: CLLocationDistance,
        destinationDistance: CLLocationDistance,
        isArmed: Bool,
        forceArrival: Bool = false
    ) -> Bool {
        isArmed && (
            forceArrival
                || (remainingRouteDistance <= 120 && destinationDistance <= 150)
        )
    }
}

enum NavigationStationaryArrivalPolicy {
    static func stationarySince(
        current: Date?,
        isArmed: Bool,
        destinationDistance: CLLocationDistance,
        speed: CLLocationSpeed,
        locationTimestamp: Date,
        now: Date
    ) -> Date? {
        let locationAge = max(now.timeIntervalSince(locationTimestamp), 0)
        let appearsStationary = max(speed, 0) <= 0.8 || locationAge >= 5

        guard isArmed,
              destinationDistance <= 80,
              appearsStationary else {
            return nil
        }

        return current ?? (max(speed, 0) <= 0.8 ? now : locationTimestamp)
    }

    static func shouldForceArrival(stationarySince: Date?, now: Date) -> Bool {
        guard let stationarySince else {
            return false
        }

        return now.timeIntervalSince(stationarySince) >= 20
    }
}

enum NavigationOffRouteGuidance {
    static func nextWaypointIndex(
        activeLegDestinationIndex: Int?,
        waypointCount: Int
    ) -> Int? {
        guard waypointCount > 1 else {
            return nil
        }

        guard let activeLegDestinationIndex,
              (1..<waypointCount).contains(activeLegDestinationIndex) else {
            return 1
        }

        return activeLegDestinationIndex
    }
}

enum NavigationDeadReckoning {
    static let maximumDuration: TimeInterval = 8

    static func estimatedProgress(
        from routeProgress: CLLocationDistance,
        speed: CLLocationSpeed,
        locationAge: TimeInterval,
        routeBearing: CLLocationDirection,
        course: CLLocationDirection?,
        nextConstraintProgress: CLLocationDistance?,
        totalRouteDistance: CLLocationDistance
    ) -> CLLocationDistance? {
        guard locationAge >= 1.5,
              locationAge <= maximumDuration,
              speed >= 1.4,
              let course,
              bearingDifference(routeBearing, course) <= 45 else {
            return nil
        }

        let unconstrainedProgress = routeProgress + min(speed * locationAge, 120)
        let constraintLimit = nextConstraintProgress.map { max(routeProgress, $0 - 5) } ?? totalRouteDistance
        return min(unconstrainedProgress, min(constraintLimit, totalRouteDistance))
    }

    private static func bearingDifference(_ first: CLLocationDirection, _ second: CLLocationDirection) -> Double {
        abs(((first - second + 540).truncatingRemainder(dividingBy: 360)) - 180)
    }
}

enum NavigationDecisionEngine {
    static func snapshot(totalDistance: CLLocationDistance, routeProgress: NavigationDecisionRouteProgress, legs: [NavigationDecisionLeg], progressWindow: NavigationDecisionProgressWindow?, destinationDistance: CLLocationDistance? = nil, arrivalArmed: Bool = true, forceArrival: Bool = false) -> (snapshot: NavigationDecisionSnapshot, progressWindow: NavigationDecisionProgressWindow?) {
        let remainingDistance = max(totalDistance - routeProgress.distanceFromRouteStart, 0)
        let instructionSelection = nextInstructionSelection(after: routeProgress, legs: legs)
        let instruction = instructionSelection?.instruction
        let selectedInstructionTargetOffset = instructionSelection.map(\.targetOffset)
        let remainingManeuver = selectedInstructionTargetOffset.map {
            max($0 - routeProgress.distanceFromRouteStart, 0)
        } ?? max(routeProgress.legDistance - routeProgress.distanceFromLegStart, 0)
        let tripProgress = totalDistance > 0 ? Int(((routeProgress.distanceFromRouteStart / totalDistance) * 100).rounded()) : 0
        let straightLineDestinationDistance = destinationDistance ?? remainingDistance
        let isArriving = NavigationArrivalPolicy.shouldArrive(
            remainingRouteDistance: remainingDistance,
            destinationDistance: straightLineDestinationDistance,
            isArmed: arrivalArmed,
            forceArrival: forceArrival
        )
        let isEarlyArrivalInstruction = instruction?.maneuver == .arrive && !isArriving
        let continueThresholdMeters: CLLocationDistance = instruction?.maneuver.isBend == true ? 400 : 1609.344
        let shouldContinue = !isArriving && (isEarlyArrivalInstruction || remainingManeuver > continueThresholdMeters)
        let displayedManeuverDistance = isArriving || isEarlyArrivalInstruction
            ? remainingDistance
            : remainingManeuver
        let maneuver = isArriving ? NavigationDecisionManeuver.arrive : (shouldContinue ? .continueAhead : (instruction?.maneuver ?? .continueAhead))
        let progressDistance = isArriving ? remainingDistance : (shouldContinue ? displayedManeuverDistance : remainingManeuver)
        let progressResult = maneuverProgressRemaining(
            signature: maneuverProgressSignature(
                maneuver: maneuver,
                instruction: instruction,
                selectedTargetOffset: selectedInstructionTargetOffset,
                shouldContinue: shouldContinue,
                isArriving: isArriving
            ),
            remainingDistance: progressDistance,
            progressWindow: progressWindow
        )
        let selectionReason = isArriving
            ? "Arriving"
            : (isEarlyArrivalInstruction
                ? "Approaching destination: arrival gate is \(Int(remainingDistance.rounded()))m away"
                : (shouldContinue ? "Synthetic continue: selected instruction activates in \(Int(displayedManeuverDistance.rounded()))m" : "Selected instruction"))

        return (NavigationDecisionSnapshot(
            distanceToDestinationMeters: Int(remainingDistance.rounded()),
            distanceToManeuverMeters: Int(displayedManeuverDistance.rounded()),
            tripProgressComplete: max(0, min(100, tripProgress)),
            maneuverProgressRemaining: progressResult.progressRemaining,
            maneuver: maneuver,
            selectedInstruction: instruction,
            selectedInstructionOffsetMeters: instructionSelection?.routeOffset,
            selectedInstructionEndMeters: instructionSelection.map { $0.routeOffset + $0.instruction.distance },
            selectedInstructionTargetOffsetMeters: selectedInstructionTargetOffset,
            routeProgressMeters: routeProgress.distanceFromRouteStart,
            selectionReason: selectionReason
        ), progressResult.progressWindow)
    }

    static func nextInstructionSelection(after routeProgress: NavigationDecisionRouteProgress, legs: [NavigationDecisionLeg]) -> NavigationDecisionSelection? {
        var totalBeforeLeg: CLLocationDistance = 0
        var isFirstLeg = true
        guard let leg = legs.first(where: { candidate in
            if candidate.id == routeProgress.legID {
                return true
            }
            totalBeforeLeg += candidate.distance
            isFirstLeg = false
            return false
        }) else {
            return nil
        }

        let lookbehindMeters: CLLocationDistance = 15
        let roundaboutExitLookbehindMeters: CLLocationDistance = 15
        let routeStartInstructionSkipMeters: CLLocationDistance = 25
        let waypointSeamInstructionDelayMeters: CLLocationDistance = 35
        let shouldSkipRouteStartInstruction = isFirstLeg
            && routeProgress.distanceFromRouteStart < routeStartInstructionSkipMeters

        if let activeInstruction = leg.instructions.last(where: {
            let target = $0.targetDistanceFromLegStart
            return $0.maneuver.isMeaningfulDirection
                && target <= routeProgress.distanceFromLegStart
                && !(shouldSkipRouteStartInstruction && target < routeStartInstructionSkipMeters)
        }) {
            let activeInstructionEnd = activeInstruction.activeSelectionEndDistance
            let activeInstructionLookbehind = activeInstruction.maneuver == .roundabout ? roundaboutExitLookbehindMeters : lookbehindMeters
            let isOutgoingWaypointSeamInstruction = !isFirstLeg
                && activeInstruction.targetDistanceFromLegStart <= waypointSeamInstructionDelayMeters
                && routeProgress.distanceFromLegStart < waypointSeamInstructionDelayMeters
            if !isOutgoingWaypointSeamInstruction,
               routeProgress.distanceFromLegStart <= activeInstructionEnd + activeInstructionLookbehind {
                return NavigationDecisionSelection(
                    instruction: activeInstruction,
                    routeOffset: totalBeforeLeg + activeInstruction.distanceFromLegStart,
                    targetOffset: totalBeforeLeg + activeInstruction.targetDistanceFromLegStart
                )
            }
        }

        if let instruction = leg.instructions.first(where: {
            let target = $0.targetDistanceFromLegStart
            return $0.maneuver.isMeaningfulDirection
                && target > routeProgress.distanceFromLegStart
                && !(shouldSkipRouteStartInstruction && target < routeStartInstructionSkipMeters)
        }) {
            return NavigationDecisionSelection(
                instruction: instruction,
                routeOffset: totalBeforeLeg + instruction.distanceFromLegStart,
                targetOffset: totalBeforeLeg + instruction.targetDistanceFromLegStart
            )
        }

        var foundCurrentLeg = false
        var nextLegTotalBefore: CLLocationDistance = 0
        for candidate in legs {
            if foundCurrentLeg,
               let instruction = candidate.instructions.first(where: {
                   let target = $0.targetDistanceFromLegStart
                   return $0.maneuver.isMeaningfulDirection
                       && (target > waypointSeamInstructionDelayMeters || !$0.maneuver.isWaypointSeamCandidate)
               }) {
                return NavigationDecisionSelection(
                    instruction: instruction,
                    routeOffset: nextLegTotalBefore + instruction.distanceFromLegStart,
                    targetOffset: nextLegTotalBefore + instruction.targetDistanceFromLegStart
                )
            }

            if candidate.id == routeProgress.legID {
                foundCurrentLeg = true
            }
            nextLegTotalBefore += candidate.distance
        }

        return nil
    }

    private static func maneuverProgressSignature(maneuver: NavigationDecisionManeuver, instruction: NavigationDecisionInstruction?, selectedTargetOffset: CLLocationDistance?, shouldContinue: Bool, isArriving: Bool) -> String? {
        guard !isArriving else {
            return nil
        }

        let target = selectedTargetOffset.map { Int(($0 / 5).rounded() * 5) } ?? -1
        let exit = instruction?.roundaboutExit ?? 0
        let phase = shouldContinue ? "continue" : "maneuver"
        return "\(phase)|\(maneuver.rawValue)|\(target)|\(exit)|\(instruction?.rawInstruction ?? "none")"
    }

    private static func maneuverProgressRemaining(signature: String?, remainingDistance: CLLocationDistance, progressWindow: NavigationDecisionProgressWindow?) -> (progressRemaining: Int, progressWindow: NavigationDecisionProgressWindow?) {
        guard let signature else {
            return (100, nil)
        }

        let remaining = max(remainingDistance, 0)
        let window = progressWindow?.signature == signature
            ? progressWindow!
            : NavigationDecisionProgressWindow(signature: signature, startDistanceMeters: max(remaining, 1))
        let range = max(window.startDistanceMeters, 1)
        let progress = Int(((remaining / range) * 100).rounded())
        return (max(0, min(100, progress)), window)
    }
}

private extension NavigationDecisionInstruction {
    var activeSelectionEndDistance: CLLocationDistance {
        guard maneuver == .roundabout else {
            return targetDistanceFromLegStart
        }

        let roundaboutHoldSpanMeters: CLLocationDistance = 75
        return targetDistanceFromLegStart + min(max(distance, 0), roundaboutHoldSpanMeters)
    }
}
