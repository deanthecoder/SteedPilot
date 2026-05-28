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
    let distance: CLLocationDistance
    let rawInstruction: String
    let maneuver: NavigationDecisionManeuver
    let roundaboutExit: Int?

    var targetDistanceFromLegStart: CLLocationDistance {
        rawInstruction.hasPrefix("Synthetic ") ? distanceFromLegStart : distanceFromLegStart + distance
    }
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

enum NavigationDecisionEngine {
    static func snapshot(totalDistance: CLLocationDistance, routeProgress: NavigationDecisionRouteProgress, legs: [NavigationDecisionLeg], progressWindow: NavigationDecisionProgressWindow?) -> (snapshot: NavigationDecisionSnapshot, progressWindow: NavigationDecisionProgressWindow?) {
        let remainingDistance = max(totalDistance - routeProgress.distanceFromRouteStart, 0)
        let instructionSelection = nextInstructionSelection(after: routeProgress, legs: legs)
        let instruction = instructionSelection?.instruction
        let selectedInstructionTargetOffset = instructionSelection.map(\.targetOffset)
        let remainingManeuver = selectedInstructionTargetOffset.map {
            max($0 - routeProgress.distanceFromRouteStart, 0)
        } ?? max(routeProgress.legDistance - routeProgress.distanceFromLegStart, 0)
        let tripProgress = totalDistance > 0 ? Int(((routeProgress.distanceFromRouteStart / totalDistance) * 100).rounded()) : 0
        let isArriving = remainingDistance <= 120 || instruction?.maneuver == .arrive
        let continueThresholdMeters: CLLocationDistance = instruction?.maneuver.isBend == true ? 400 : 1609.344
        let shouldContinue = !isArriving && remainingManeuver > continueThresholdMeters
        let displayedManeuverDistance = shouldContinue
            ? max(remainingManeuver - continueThresholdMeters, 1)
            : (isArriving ? remainingDistance : remainingManeuver)
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
        let selectionReason = isArriving ? "Arriving" : (shouldContinue ? "Synthetic continue: selected instruction activates in \(Int(displayedManeuverDistance.rounded()))m" : "Selected instruction")

        return (NavigationDecisionSnapshot(
            distanceToDestinationMeters: Int(remainingDistance.rounded()),
            distanceToManeuverMeters: Int(displayedManeuverDistance.rounded()),
            tripProgressComplete: max(0, min(100, tripProgress)),
            maneuverProgressRemaining: progressResult.progressRemaining,
            maneuver: maneuver,
            selectedInstruction: instruction,
            selectedInstructionOffsetMeters: instructionSelection?.routeOffset,
            selectedInstructionEndMeters: instructionSelection.map(\.targetOffset),
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
            let activeInstructionEnd = activeInstruction.targetDistanceFromLegStart
            let isOutgoingWaypointSeamInstruction = !isFirstLeg
                && activeInstruction.targetDistanceFromLegStart <= waypointSeamInstructionDelayMeters
                && routeProgress.distanceFromLegStart < waypointSeamInstructionDelayMeters
            if !isOutgoingWaypointSeamInstruction,
               routeProgress.distanceFromLegStart <= activeInstructionEnd + lookbehindMeters {
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
