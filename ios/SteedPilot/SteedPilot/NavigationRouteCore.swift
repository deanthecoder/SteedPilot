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

struct NavigationRoundaboutExitAngle {
    let index: Int
    let angleDegrees: Int
}

struct NavigationRoundaboutApproachBearingProbe {
    let offset: CLLocationDistance
    let bearing: Int
}

struct NavigationRouteStep {
    let distanceFromLegStart: CLLocationDistance
    let distance: CLLocationDistance
    let rawInstruction: String
    let rawNotice: String?
    let sourceManeuver: NavigationDecisionManeuver
    let deviceManeuver: NavigationDecisionManeuver?
    let incomingBearing: Int?
    let outgoingBearing: Int?
    let mapKitRoundaboutExit: Int?
    let mapKitRoundaboutExitAngles: [NavigationRoundaboutExitAngle]
    let deviceRoundaboutExit: Int?
    let deviceRoundaboutExitAngles: [NavigationRoundaboutExitAngle]
    let roundaboutApproachDeviationOffset: CLLocationDistance?
    let roundaboutApproachProbes: [NavigationRoundaboutApproachBearingProbe]
    let skipReason: String?
}

struct NavigationSyntheticBendDiagnostic {
    let startDistance: CLLocationDistance
    let endDistance: CLLocationDistance
    let peakDistance: CLLocationDistance
    let peakBendiness: Int
    let peakDelta: Int
    let maneuver: NavigationDecisionManeuver
    let accepted: Bool
    let reason: String
}

enum NavigationRouteBuilder {
    static func steps(polyline: MKPolyline, routeDistance: CLLocationDistance, mapKitSteps: [MKRoute.Step], isFirstLeg: Bool, isFinalLeg: Bool) -> [NavigationRouteStep] {
        let mapKitDebugSteps = navigationSteps(
            polyline: polyline,
            mapKitSteps: mapKitSteps,
            isFinalLeg: isFinalLeg
        )

        let syntheticBends = syntheticBendSteps(
            legPolyline: polyline,
            legDistance: routeDistance,
            existingSteps: mapKitDebugSteps,
            suppressStartBoundary: !isFirstLeg,
            suppressEndBoundary: !isFinalLeg
        )
        return (mapKitDebugSteps + syntheticBends).sorted { targetDistance(for: $0) < targetDistance(for: $1) }
    }

    private static func targetDistance(for step: NavigationRouteStep) -> CLLocationDistance {
        step.rawInstruction.hasPrefix("Synthetic ") ? step.distanceFromLegStart : step.distanceFromLegStart + step.distance
    }

    static func syntheticBendDiagnostics(polyline: MKPolyline, routeDistance: CLLocationDistance, mapKitSteps: [MKRoute.Step], isFirstLeg: Bool, isFinalLeg: Bool) -> [NavigationSyntheticBendDiagnostic] {
        syntheticBendDiagnostics(
            legPolyline: polyline,
            legDistance: routeDistance,
            existingSteps: navigationSteps(polyline: polyline, mapKitSteps: mapKitSteps, isFinalLeg: isFinalLeg),
            suppressStartBoundary: !isFirstLeg,
            suppressEndBoundary: !isFinalLeg
        )
    }

    private static func navigationSteps(polyline: MKPolyline, mapKitSteps: [MKRoute.Step], isFinalLeg: Bool) -> [NavigationRouteStep] {
        var distanceFromLegStart: CLLocationDistance = 0
        return mapKitSteps.enumerated().map { index, step in
            let roundaboutExit = roundaboutExit(from: step.instructions)
            let maneuverStartDistance = distanceFromLegStart
            let maneuverTargetDistance = distanceFromLegStart + step.distance
            let approach = roundaboutApproachBearingDiagnostic(
                exit: roundaboutExit,
                legPolyline: polyline,
                maneuverDistance: maneuverTargetDistance,
                previousStep: index > 0 ? mapKitSteps[index - 1] : nil
            )
            let incomingBearing = roundaboutExit == nil
                ? (polyline.steedPilotBearing(atDistance: maneuverTargetDistance - 50) ?? (index > 0 ? mapKitSteps[index - 1].polyline.steedPilotLastSegmentBearingDegrees : nil))
                : approach.bearing
            let outgoingBearing = polyline.steedPilotBearing(atDistance: maneuverTargetDistance + 50) ?? step.polyline.steedPilotLastSegmentBearingDegrees
            let sourceManeuver = NavigationDecisionManeuver(instruction: step.instructions)
            let inferredManeuver = inferredManeuver(
                sourceManeuver,
                instruction: step.instructions,
                incomingBearing: incomingBearing,
                outgoingBearing: outgoingBearing
            )
            let roundaboutAngles = roundaboutExitAngles(
                exit: roundaboutExit,
                targetAngle: nil,
                incomingBearing: incomingBearing,
                outgoingBearing: outgoingBearing
            )
            let deviceManeuver = normalizedManeuver(
                inferredManeuver,
                roundaboutExit: roundaboutExit,
                incomingBearing: incomingBearing,
                outgoingBearing: outgoingBearing
            )
            let skipReason: String?
            if step.distance <= 1 {
                skipReason = "distance <= 1m"
            } else if !isFinalLeg && sourceManeuver == .arrive {
                skipReason = "intermediate leg arrival"
            } else if sourceManeuver == .continueAhead && step.instructions.isEmpty {
                skipReason = "empty continue"
            } else {
                skipReason = nil
            }

            let routeStep = NavigationRouteStep(
                distanceFromLegStart: maneuverStartDistance,
                distance: step.distance,
                rawInstruction: step.instructions,
                rawNotice: step.notice,
                sourceManeuver: sourceManeuver,
                deviceManeuver: skipReason == nil ? deviceManeuver : nil,
                incomingBearing: incomingBearing,
                outgoingBearing: outgoingBearing,
                mapKitRoundaboutExit: roundaboutExit,
                mapKitRoundaboutExitAngles: roundaboutAngles,
                deviceRoundaboutExit: skipReason == nil && deviceManeuver == .roundabout ? roundaboutExit : nil,
                deviceRoundaboutExitAngles: skipReason == nil && deviceManeuver == .roundabout ? roundaboutAngles : [],
                roundaboutApproachDeviationOffset: approach.deviationOffset,
                roundaboutApproachProbes: approach.routeApproachProbes,
                skipReason: skipReason
            )

            distanceFromLegStart += step.distance
            return routeStep
        }
    }

    static func roundaboutExit(from instruction: String) -> Int? {
        let words = instruction.lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")

        for word in words {
            if let exit = Int(word) {
                return exit
            }

            switch word {
                case "first", "1st": return 1
                case "second", "2nd": return 2
                case "third", "3rd": return 3
                case "fourth", "4th": return 4
                case "fifth", "5th": return 5
                case "sixth", "6th": return 6
                default: break
            }
        }

        return nil
    }

    static func roundaboutDisplayAngle(incomingBearing: Int?, outgoingBearing: Int?) -> Int? {
        guard let angle = relativeAngle(incomingBearing: incomingBearing, outgoingBearing: outgoingBearing) else {
            return nil
        }

        return normalizedSignedAngle(angle)
    }

    private static func inferredManeuver(_ maneuver: NavigationDecisionManeuver, instruction: String, incomingBearing: Int?, outgoingBearing: Int?) -> NavigationDecisionManeuver {
        guard (maneuver == .continueAhead || maneuver == .exitLeft),
              instruction.lowercased().contains("take the exit") || instruction.lowercased().contains("take exit") else {
            return maneuver
        }

        guard let angle = relativeAngle(incomingBearing: incomingBearing, outgoingBearing: outgoingBearing) else {
            return .exitLeft
        }

        if angle < -25 {
            return .exitLeft
        }
        if angle > 25 {
            return .exitRight
        }

        return .continueAhead
    }

    private static func normalizedManeuver(_ maneuver: NavigationDecisionManeuver, roundaboutExit: Int?, incomingBearing: Int?, outgoingBearing: Int?) -> NavigationDecisionManeuver {
        guard maneuver != .roundabout || roundaboutExit != nil else {
            return fallbackManeuver(incomingBearing: incomingBearing, outgoingBearing: outgoingBearing)
        }

        return maneuver
    }

    private static func fallbackManeuver(incomingBearing: Int?, outgoingBearing: Int?) -> NavigationDecisionManeuver {
        guard let angle = relativeAngle(incomingBearing: incomingBearing, outgoingBearing: outgoingBearing) else {
            return .continueAhead
        }

        if angle < -60 {
            return .turnLeft
        }
        if angle < -20 {
            return .slightLeft
        }
        if angle > 60 {
            return .turnRight
        }
        if angle > 20 {
            return .slightRight
        }

        return .continueAhead
    }

    private static func syntheticBendSteps(legPolyline: MKPolyline, legDistance: CLLocationDistance, existingSteps: [NavigationRouteStep], suppressStartBoundary: Bool, suppressEndBoundary: Bool) -> [NavigationRouteStep] {
        syntheticBendDiagnostics(
            legPolyline: legPolyline,
            legDistance: legDistance,
            existingSteps: existingSteps,
            suppressStartBoundary: suppressStartBoundary,
            suppressEndBoundary: suppressEndBoundary
        )
        .filter(\.accepted)
        .map { diagnostic in
            NavigationRouteStep(
                distanceFromLegStart: diagnostic.startDistance,
                distance: diagnostic.endDistance - diagnostic.startDistance,
                rawInstruction: "Synthetic \(diagnostic.maneuver.debugTitle)",
                rawNotice: "Generated from route curvature: \(diagnostic.peakBendiness) degrees around \(Int(diagnostic.peakDistance))m",
                sourceManeuver: .continueAhead,
                deviceManeuver: diagnostic.maneuver,
                incomingBearing: nil,
                outgoingBearing: nil,
                mapKitRoundaboutExit: nil,
                mapKitRoundaboutExitAngles: [],
                deviceRoundaboutExit: nil,
                deviceRoundaboutExitAngles: [],
                roundaboutApproachDeviationOffset: nil,
                roundaboutApproachProbes: [],
                skipReason: nil
            )
        }
    }

    static func syntheticBendDiagnostics(legPolyline: MKPolyline, legDistance: CLLocationDistance, existingSteps: [NavigationRouteStep], suppressStartBoundary: Bool, suppressEndBoundary: Bool) -> [NavigationSyntheticBendDiagnostic] {
        let sampleSpacing: CLLocationDistance = 10
        let curvatureWindow: CLLocationDistance = 20
        let bendinessEntryThreshold = 40
        let bendinessTriggerThreshold = 50
        let maximumBendDelta = 95
        let minimumBendSpan: CLLocationDistance = 20
        let waypointBoundarySuppressionDistance: CLLocationDistance = 80
        let maneuverSuppressionDistance: CLLocationDistance = 130
        let duplicateSuppressionDistance: CLLocationDistance = 180
        guard legDistance >= curvatureWindow * 2 else {
            return []
        }

        let existingInstructionOffsets = existingSteps
            .filter { $0.deviceManeuver?.isMeaningfulDirection == true }
            .map(\.distanceFromLegStart)
        var diagnostics: [NavigationSyntheticBendDiagnostic] = []
        var lastSyntheticOffset: CLLocationDistance = -duplicateSuppressionDistance
        var lastSyntheticManeuver: NavigationDecisionManeuver?
        var activeCandidate: SyntheticBendCandidate?
        var scanDistance = curvatureWindow

        while scanDistance <= legDistance - curvatureWindow {
            defer { scanDistance += sampleSpacing }
            guard let beforeBearing = legPolyline.steedPilotBearing(atDistance: scanDistance - curvatureWindow),
                  let afterBearing = legPolyline.steedPilotBearing(atDistance: scanDistance + curvatureWindow) else {
                continue
            }

            let delta = normalizedSignedAngle(afterBearing - beforeBearing)
            let bendiness = abs(delta)
            guard bendiness >= bendinessEntryThreshold,
                  bendiness <= maximumBendDelta else {
                appendSyntheticBendDiagnostic(activeCandidate, to: &diagnostics, lastSyntheticOffset: &lastSyntheticOffset, lastSyntheticManeuver: &lastSyntheticManeuver, legDistance: legDistance, existingInstructionOffsets: existingInstructionOffsets, minimumBendSpan: minimumBendSpan, waypointBoundarySuppressionDistance: waypointBoundarySuppressionDistance, suppressStartBoundary: suppressStartBoundary, suppressEndBoundary: suppressEndBoundary, maneuverSuppressionDistance: maneuverSuppressionDistance, duplicateSuppressionDistance: duplicateSuppressionDistance)
                activeCandidate = nil
                continue
            }

            let hasTriggered = bendiness >= bendinessTriggerThreshold
            if var candidate = activeCandidate {
                if bendDirectionChanged(from: candidate.peakDelta, to: delta) {
                    appendSyntheticBendDiagnostic(candidate, to: &diagnostics, lastSyntheticOffset: &lastSyntheticOffset, lastSyntheticManeuver: &lastSyntheticManeuver, legDistance: legDistance, existingInstructionOffsets: existingInstructionOffsets, minimumBendSpan: minimumBendSpan, waypointBoundarySuppressionDistance: waypointBoundarySuppressionDistance, suppressStartBoundary: suppressStartBoundary, suppressEndBoundary: suppressEndBoundary, maneuverSuppressionDistance: maneuverSuppressionDistance, duplicateSuppressionDistance: duplicateSuppressionDistance)
                    activeCandidate = SyntheticBendCandidate(startDistance: scanDistance, endDistance: scanDistance, peakDistance: scanDistance, peakBendiness: bendiness, peakDelta: delta, incomingBearing: beforeBearing, outgoingBearing: afterBearing, hasTriggered: hasTriggered)
                    continue
                }

                candidate.endDistance = scanDistance
                candidate.hasTriggered = candidate.hasTriggered || hasTriggered
                if bendiness > candidate.peakBendiness {
                    candidate.peakDistance = scanDistance
                    candidate.peakBendiness = bendiness
                    candidate.peakDelta = delta
                    candidate.incomingBearing = beforeBearing
                    candidate.outgoingBearing = afterBearing
                }
                activeCandidate = candidate
            } else {
                activeCandidate = SyntheticBendCandidate(startDistance: scanDistance, endDistance: scanDistance, peakDistance: scanDistance, peakBendiness: bendiness, peakDelta: delta, incomingBearing: beforeBearing, outgoingBearing: afterBearing, hasTriggered: hasTriggered)
            }
        }

        appendSyntheticBendDiagnostic(activeCandidate, to: &diagnostics, lastSyntheticOffset: &lastSyntheticOffset, lastSyntheticManeuver: &lastSyntheticManeuver, legDistance: legDistance, existingInstructionOffsets: existingInstructionOffsets, minimumBendSpan: minimumBendSpan, waypointBoundarySuppressionDistance: waypointBoundarySuppressionDistance, suppressStartBoundary: suppressStartBoundary, suppressEndBoundary: suppressEndBoundary, maneuverSuppressionDistance: maneuverSuppressionDistance, duplicateSuppressionDistance: duplicateSuppressionDistance)
        return diagnostics
    }

    private static func appendSyntheticBendDiagnostic(_ candidate: SyntheticBendCandidate?, to diagnostics: inout [NavigationSyntheticBendDiagnostic], lastSyntheticOffset: inout CLLocationDistance, lastSyntheticManeuver: inout NavigationDecisionManeuver?, legDistance: CLLocationDistance, existingInstructionOffsets: [CLLocationDistance], minimumBendSpan: CLLocationDistance, waypointBoundarySuppressionDistance: CLLocationDistance, suppressStartBoundary: Bool, suppressEndBoundary: Bool, maneuverSuppressionDistance: CLLocationDistance, duplicateSuppressionDistance: CLLocationDistance) {
        guard let candidate,
              candidate.hasTriggered else {
            return
        }

        let startDistance = candidate.startDistance
        let endDistance = max(candidate.endDistance, candidate.startDistance + 1)
        let maneuver: NavigationDecisionManeuver = candidate.peakDelta < 0 ? .bendLeft : .bendRight
        let reason: String
        if endDistance - startDistance < minimumBendSpan {
            reason = "short span"
        } else if suppressStartBoundary && startDistance < waypointBoundarySuppressionDistance {
            reason = "waypoint start boundary"
        } else if suppressEndBoundary && legDistance - endDistance < waypointBoundarySuppressionDistance {
            reason = "waypoint end boundary"
        } else if !existingInstructionOffsets.allSatisfy({ abs($0 - startDistance) >= maneuverSuppressionDistance }) {
            reason = "near maneuver"
        } else if startDistance - lastSyntheticOffset < duplicateSuppressionDistance && lastSyntheticManeuver == maneuver {
            reason = "duplicate"
        } else {
            reason = "accepted"
        }
        let accepted = reason == "accepted"
        diagnostics.append(
            NavigationSyntheticBendDiagnostic(
                startDistance: startDistance,
                endDistance: endDistance,
                peakDistance: candidate.peakDistance,
                peakBendiness: candidate.peakBendiness,
                peakDelta: candidate.peakDelta,
                maneuver: maneuver,
                accepted: accepted,
                reason: reason
            )
        )

        guard accepted else {
            return
        }

        let duplicateSuppressed = startDistance - lastSyntheticOffset < duplicateSuppressionDistance && lastSyntheticManeuver == maneuver
        guard !duplicateSuppressed else {
            return
        }
        lastSyntheticOffset = startDistance
        lastSyntheticManeuver = maneuver
    }

    private static func roundaboutApproachBearingDiagnostic(exit: Int?, legPolyline: MKPolyline, maneuverDistance: CLLocationDistance, previousStep: MKRoute.Step?) -> RoundaboutApproachBearingDiagnostic {
        guard exit != nil else {
            return RoundaboutApproachBearingDiagnostic(bearing: nil, deviationOffset: nil, routeApproachProbes: [])
        }

        var probes: [NavigationRoundaboutApproachBearingProbe] = []
        for offset in [-220, -180, -140, -110, -90, -70, -55, -45, -35, -25, -18, -12, -8] as [CLLocationDistance] {
            let sampleDistance = maneuverDistance + offset
            guard sampleDistance >= 0,
                  let bearing = legPolyline.steedPilotBearing(atDistance: sampleDistance) else {
                continue
            }

            probes.append(NavigationRoundaboutApproachBearingProbe(offset: offset, bearing: bearing))
        }

        let analysis = roundaboutApproachAnalysis(in: probes)
        return RoundaboutApproachBearingDiagnostic(bearing: analysis.bearing ?? probes.last?.bearing, deviationOffset: analysis.deviationOffset, routeApproachProbes: probes)
    }

    private static func roundaboutApproachAnalysis(in probes: [NavigationRoundaboutApproachBearingProbe]) -> (bearing: Int?, deviationOffset: CLLocationDistance?) {
        guard let first = probes.first else {
            return (nil, nil)
        }

        var approachProbes = [first]
        for probe in probes.dropFirst() {
            let average = circularAverageBearing(approachProbes) ?? first.bearing
            let delta = abs(normalizedSignedAngle(probe.bearing - average))
            if delta >= 18 {
                return (circularAverageBearing(approachProbes), probe.offset)
            }

            approachProbes.append(probe)
        }

        return (circularAverageBearing(approachProbes), nil)
    }

    private static func circularAverageBearing(_ probes: [NavigationRoundaboutApproachBearingProbe]) -> Int? {
        guard !probes.isEmpty else {
            return nil
        }

        var x = 0.0
        var y = 0.0
        for probe in probes {
            let radians = Double(probe.bearing) * .pi / 180
            x += cos(radians)
            y += sin(radians)
        }

        guard x != 0 || y != 0 else {
            return nil
        }

        return Int(((atan2(y, x) * 180 / .pi) + 360).truncatingRemainder(dividingBy: 360).rounded())
    }

    private static func roundaboutExitAngleDiagnostic(exit: Int?, legPolyline: MKPolyline, maneuverDistance: CLLocationDistance, incomingBearing: Int?) -> RoundaboutExitAngleDiagnostic {
        guard exit != nil,
              let incomingBearing,
              let entry = legPolyline.steedPilotCoordinate(atDistance: maneuverDistance) else {
            return RoundaboutExitAngleDiagnostic(targetAngle: nil)
        }

        let estimatedCenter = entry.steedPilotCoordinate(movedMeters: 18, bearingDegrees: incomingBearing)
        for probeDistance in [25, 35, 50, 70, 90, 120] as [CLLocationDistance] {
            guard let exitSample = legPolyline.steedPilotCoordinate(atDistance: maneuverDistance + probeDistance) else {
                continue
            }

            let sampleDistance = MKMapPoint(estimatedCenter).distance(to: MKMapPoint(exitSample))
            let exitBearing = estimatedCenter.steedPilotBearingDegrees(to: exitSample)
            let angle = roundaboutDisplayAngle(incomingBearing: incomingBearing, outgoingBearing: exitBearing)
            if sampleDistance >= 18 {
                return RoundaboutExitAngleDiagnostic(targetAngle: angle)
            }
        }

        return RoundaboutExitAngleDiagnostic(targetAngle: nil)
    }

    private static func roundaboutExitAngles(exit: Int?, targetAngle: Int?, incomingBearing: Int?, outgoingBearing: Int?) -> [NavigationRoundaboutExitAngle] {
        guard let exit else {
            return []
        }

        let targetAngle = targetAngle ?? roundaboutDisplayAngle(incomingBearing: incomingBearing, outgoingBearing: outgoingBearing)
        let target = clamp(targetAngle ?? fallbackExitAngle(for: exit), min: -150, max: 150)
        guard exit > 1 else {
            return [NavigationRoundaboutExitAngle(index: 1, angleDegrees: target)]
        }

        return (0..<exit).map { index in
            let ratio = Double(index + 1) / Double(exit)
            let angle = normalizedSignedAngle(Int((180.0 + ((Double(target) + 180.0) * ratio)).rounded()))
            return NavigationRoundaboutExitAngle(index: index + 1, angleDegrees: angle)
        }
    }

    private static func relativeAngle(incomingBearing: Int?, outgoingBearing: Int?) -> Int? {
        guard let incomingBearing,
              let outgoingBearing else {
            return nil
        }

        return normalizedSignedAngle(outgoingBearing - incomingBearing)
    }

    private static func normalizedSignedAngle(_ degrees: Int) -> Int {
        var angle = degrees
        while angle > 180 { angle -= 360 }
        while angle < -180 { angle += 360 }
        return angle
    }

    private static func fallbackExitAngle(for exit: Int) -> Int {
        min(150, max(-150, -70 + ((exit - 1) * 55)))
    }

    private static func clamp(_ value: Int, min minimum: Int, max maximum: Int) -> Int {
        Swift.max(minimum, Swift.min(maximum, value))
    }

    private static func bendDirectionChanged(from previousDelta: Int, to nextDelta: Int) -> Bool {
        (previousDelta < 0 && nextDelta > 0) || (previousDelta > 0 && nextDelta < 0)
    }
}

private struct RoundaboutApproachBearingDiagnostic {
    let bearing: Int?
    let deviationOffset: CLLocationDistance?
    let routeApproachProbes: [NavigationRoundaboutApproachBearingProbe]
}

private struct RoundaboutExitAngleDiagnostic {
    let targetAngle: Int?
}

private struct SyntheticBendCandidate {
    let startDistance: CLLocationDistance
    var endDistance: CLLocationDistance
    var peakDistance: CLLocationDistance
    var peakBendiness: Int
    var peakDelta: Int
    var incomingBearing: Int
    var outgoingBearing: Int
    var hasTriggered: Bool
}

extension CLLocationCoordinate2D {
    func steedPilotBearingDegrees(to destination: CLLocationCoordinate2D) -> Int {
        let startLatitude = latitude * .pi / 180
        let startLongitude = longitude * .pi / 180
        let destinationLatitude = destination.latitude * .pi / 180
        let destinationLongitude = destination.longitude * .pi / 180
        let longitudeDelta = destinationLongitude - startLongitude
        let y = sin(longitudeDelta) * cos(destinationLatitude)
        let x = cos(startLatitude) * sin(destinationLatitude) - sin(startLatitude) * cos(destinationLatitude) * cos(longitudeDelta)
        return Int(((atan2(y, x) * 180 / .pi) + 360).truncatingRemainder(dividingBy: 360).rounded())
    }

    func steedPilotCoordinate(movedMeters distance: CLLocationDistance, bearingDegrees: Int) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let angularDistance = distance / earthRadius
        let bearing = Double(bearingDegrees) * .pi / 180
        let startLatitude = latitude * .pi / 180
        let startLongitude = longitude * .pi / 180
        let destinationLatitude = asin(sin(startLatitude) * cos(angularDistance) + cos(startLatitude) * sin(angularDistance) * cos(bearing))
        let destinationLongitude = startLongitude + atan2(sin(bearing) * sin(angularDistance) * cos(startLatitude), cos(angularDistance) - sin(startLatitude) * sin(destinationLatitude))
        return CLLocationCoordinate2D(latitude: destinationLatitude * 180 / .pi, longitude: destinationLongitude * 180 / .pi)
    }
}

extension MKPolyline {
    var steedPilotRouteCoordinates: [CLLocationCoordinate2D] {
        var coordinates = Array(repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }

    var steedPilotRouteDistance: CLLocationDistance {
        let coordinates = steedPilotRouteCoordinates
        guard coordinates.count > 1 else {
            return 0
        }

        return zip(coordinates, coordinates.dropFirst()).reduce(0) { $0 + MKMapPoint($1.0).distance(to: MKMapPoint($1.1)) }
    }

    var steedPilotLastSegmentBearingDegrees: Int? {
        let coordinates = steedPilotRouteCoordinates
        guard coordinates.count > 1 else {
            return nil
        }

        for index in stride(from: coordinates.count - 1, through: 1, by: -1) {
            let start = coordinates[index - 1]
            let end = coordinates[index]
            if start.latitude != end.latitude || start.longitude != end.longitude {
                return start.steedPilotBearingDegrees(to: end)
            }
        }

        return nil
    }

    func steedPilotBearing(atDistance targetDistance: CLLocationDistance) -> Int? {
        let coordinates = steedPilotRouteCoordinates
        guard coordinates.count > 1 else {
            return nil
        }

        let segments = zip(coordinates, coordinates.dropFirst()).map { start, end in
            (start: start, end: end, distance: MKMapPoint(start).distance(to: MKMapPoint(end)))
        }
        let clampedDistance = max(0, min(segments.reduce(0) { $0 + $1.distance }, targetDistance))
        var distanceSoFar: CLLocationDistance = 0
        for segment in segments {
            if distanceSoFar + segment.distance >= clampedDistance && segment.distance > 0 {
                return segment.start.steedPilotBearingDegrees(to: segment.end)
            }

            distanceSoFar += segment.distance
        }

        return segments.last.map { $0.start.steedPilotBearingDegrees(to: $0.end) }
    }

    func steedPilotCoordinate(atDistance targetDistance: CLLocationDistance) -> CLLocationCoordinate2D? {
        let coordinates = steedPilotRouteCoordinates
        guard coordinates.count > 1 else {
            return coordinates.first
        }

        let segments = zip(coordinates, coordinates.dropFirst()).map { start, end in
            (start: start, end: end, distance: MKMapPoint(start).distance(to: MKMapPoint(end)))
        }
        let clampedDistance = max(0, min(segments.reduce(0) { $0 + $1.distance }, targetDistance))
        var distanceSoFar: CLLocationDistance = 0
        for segment in segments {
            if distanceSoFar + segment.distance >= clampedDistance && segment.distance > 0 {
                let fraction = (clampedDistance - distanceSoFar) / segment.distance
                let startPoint = MKMapPoint(segment.start)
                let endPoint = MKMapPoint(segment.end)
                return MKMapPoint(x: startPoint.x + ((endPoint.x - startPoint.x) * fraction), y: startPoint.y + ((endPoint.y - startPoint.y) * fraction)).coordinate
            }

            distanceSoFar += segment.distance
        }

        return coordinates.last
    }
}
