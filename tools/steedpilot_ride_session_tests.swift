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

private enum TestFailure: Error {
    case failed(String)
}

@main
private struct RideSessionTests {
    @MainActor
    static func main() throws {
        let now = Date()
        let recorder = RideSessionRecorder(
            name: "Test ride",
            plannedDistanceMeters: 1_000,
            startedAt: now.addingTimeInterval(-14)
        )

        recorder.record(location: location(longitude: 0, speed: 10, timestamp: now.addingTimeInterval(-14)))
        recorder.record(location: location(longitude: 0.00018, speed: 10, timestamp: now.addingTimeInterval(-12)))
        recorder.record(location: location(longitude: 0.00108, speed: 12, timestamp: now.addingTimeInterval(-2)))
        recorder.recordNavigation(isOffRoute: false, routeCompletionPercent: 40)
        recorder.recordNavigation(isOffRoute: true, routeCompletionPercent: 60)
        recorder.recordNavigation(isOffRoute: true, routeCompletionPercent: 65)
        recorder.recordNavigation(isOffRoute: false, routeCompletionPercent: 64)

        let summary = recorder.finish(at: now)

        try assert(summary.distanceMeters > 60, "Recorded distance should include plausible GPS segments")
        try assert(summary.movingTime == 12, "Moving time should include valid moving intervals")
        try assert(summary.maximumSpeedMetersPerSecond == 12, "Maximum speed should retain the fastest accurate fix")
        try assert(summary.gpsInterruptionCount == 1, "A ten-second GPS gap should count once")
        try assert(summary.deadReckonedDuration == 8, "Dead reckoning should be capped at eight seconds per gap")
        try assert(summary.offRouteEventCount == 1, "One continuous off-route episode should count once")
        try assert(summary.routeCompletionPercent == 65, "Completion should retain the highest observed progress")
        try assert(
            summary.completionNotificationBody(usesMiles: true) == "0.0 miles • 0m",
            "Mile notifications should contain the recorded distance and elapsed time"
        )
        try assert(
            summary.completionNotificationBody(usesMiles: false) == "0.1 km • 0m",
            "Kilometre notifications should contain the recorded distance and elapsed time"
        )

        let encoded = try JSONEncoder().encode([summary])
        let decoded = try JSONDecoder().decode([RideSummary].self, from: encoded)
        try assert(decoded == [summary], "Ride summaries should round-trip through persistent storage")

        print("10 ride session tests passed.")
    }

    private static func location(longitude: CLLocationDegrees, speed: CLLocationSpeed, timestamp: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 51, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 90,
            speed: speed,
            timestamp: timestamp
        )
    }

    private static func assert(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw TestFailure.failed(message)
        }
    }
}
