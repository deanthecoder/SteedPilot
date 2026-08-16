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
import WeatherKit

struct RideWeatherSnapshot: Codable, Equatable {
    let observedAt: Date
    let condition: String
    let symbolName: String
    let temperatureCelsius: Double
    let apparentTemperatureCelsius: Double
    let windKilometresPerHour: Double
    let windGustKilometresPerHour: Double?
    let precipitationMillimetresPerHour: Double
    let attributionServiceName: String
    let attributionMarkURL: URL
    let attributionLegalURL: URL
}

struct RideSummary: Codable, Equatable, Identifiable {
    static let storageKey = "SteedPilot.rideHistory"
    static let maximumHistoryCount = 50

    let id: UUID
    let name: String
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: CLLocationDistance
    let plannedDistanceMeters: CLLocationDistance
    let movingTime: TimeInterval
    let maximumSpeedMetersPerSecond: CLLocationSpeed
    let routeCompletionPercent: Int
    let gpsInterruptionCount: Int
    let gpsInterruptionDuration: TimeInterval
    let deadReckonedDuration: TimeInterval
    let offRouteEventCount: Int
    let weather: RideWeatherSnapshot?

    var elapsedTime: TimeInterval {
        max(endedAt.timeIntervalSince(startedAt), 0)
    }

    var overallAverageSpeedMetersPerSecond: CLLocationSpeed {
        elapsedTime > 0 ? distanceMeters / elapsedTime : 0
    }

    var movingAverageSpeedMetersPerSecond: CLLocationSpeed {
        movingTime > 0 ? distanceMeters / movingTime : 0
    }

    func completionNotificationBody(usesMiles: Bool) -> String {
        let distance: String
        if usesMiles {
            distance = String(format: "%.1f miles", distanceMeters / 1_609.344)
        } else {
            distance = String(format: "%.1f km", distanceMeters / 1_000)
        }

        let elapsedMinutes = max(Int((elapsedTime / 60).rounded()), 0)
        let hours = elapsedMinutes / 60
        let minutes = elapsedMinutes % 60
        let duration = hours > 0
            ? (minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h")
            : "\(minutes)m"

        return "\(distance) • \(duration)"
    }

    func with(weather: RideWeatherSnapshot) -> RideSummary {
        RideSummary(
            id: id,
            name: name,
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: distanceMeters,
            plannedDistanceMeters: plannedDistanceMeters,
            movingTime: movingTime,
            maximumSpeedMetersPerSecond: maximumSpeedMetersPerSecond,
            routeCompletionPercent: routeCompletionPercent,
            gpsInterruptionCount: gpsInterruptionCount,
            gpsInterruptionDuration: gpsInterruptionDuration,
            deadReckonedDuration: deadReckonedDuration,
            offRouteEventCount: offRouteEventCount,
            weather: weather
        )
    }
}

@MainActor
final class RideSessionRecorder {
    let id = UUID()
    let name: String
    let startedAt: Date
    let plannedDistanceMeters: CLLocationDistance

    var weather: RideWeatherSnapshot?
    private(set) var hasRequestedWeather = false
    private(set) var isTestRide = false

    private var lastLocation: CLLocation?
    private var distanceMeters: CLLocationDistance = 0
    private var movingTime: TimeInterval = 0
    private var maximumSpeedMetersPerSecond: CLLocationSpeed = 0
    private var routeCompletionPercent = 0
    private var gpsInterruptionCount = 0
    private var gpsInterruptionDuration: TimeInterval = 0
    private var deadReckonedDuration: TimeInterval = 0
    private var offRouteEventCount = 0
    private var wasOffRoute = false

    init(
        name: String,
        plannedDistanceMeters: CLLocationDistance,
        startedAt: Date = Date()
    ) {
        self.name = name
        self.plannedDistanceMeters = plannedDistanceMeters
        self.startedAt = startedAt
    }

    func beginWeatherRequest() -> Bool {
        guard !hasRequestedWeather else {
            return false
        }

        hasRequestedWeather = true
        return true
    }

    func markAsTestRide() {
        isTestRide = true
    }

    func record(location: CLLocation) {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 50,
              abs(location.timestamp.timeIntervalSinceNow) <= 15 else {
            return
        }

        let speed = max(location.speed, 0)
        if location.horizontalAccuracy <= 30, speed <= 50 {
            maximumSpeedMetersPerSecond = max(maximumSpeedMetersPerSecond, speed)
        }

        if let previous = lastLocation {
            let elapsed = location.timestamp.timeIntervalSince(previous.timestamp)
            if elapsed > NavigationDeadReckoning.maximumDuration {
                gpsInterruptionCount += 1
                gpsInterruptionDuration += elapsed
                deadReckonedDuration += min(max(elapsed - 1.5, 0), NavigationDeadReckoning.maximumDuration)
            }

            if elapsed > 0, elapsed <= 15 {
                let segmentDistance = location.distance(from: previous)
                let previousSpeed = max(previous.speed, 0)
                let plausibleDistance = max(50, max(max(speed, previousSpeed), 5) * elapsed * 2 + 20)

                if segmentDistance <= plausibleDistance {
                    distanceMeters += segmentDistance
                    if max(speed, previousSpeed) >= 1 {
                        movingTime += elapsed
                    }
                }
            }
        }

        lastLocation = location
    }

    func recordNavigation(isOffRoute: Bool, routeCompletionPercent: Int) {
        if isOffRoute, !wasOffRoute {
            offRouteEventCount += 1
        }

        wasOffRoute = isOffRoute
        self.routeCompletionPercent = max(
            self.routeCompletionPercent,
            max(0, min(100, routeCompletionPercent))
        )
    }

    func finish(at endedAt: Date = Date()) -> RideSummary {
        if let lastLocation {
            let unfinishedGap = endedAt.timeIntervalSince(lastLocation.timestamp)
            if unfinishedGap > NavigationDeadReckoning.maximumDuration {
                gpsInterruptionCount += 1
                gpsInterruptionDuration += unfinishedGap
                deadReckonedDuration += min(max(unfinishedGap - 1.5, 0), NavigationDeadReckoning.maximumDuration)
            }
        }

        return RideSummary(
            id: id,
            name: name,
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: distanceMeters,
            plannedDistanceMeters: plannedDistanceMeters,
            movingTime: movingTime,
            maximumSpeedMetersPerSecond: maximumSpeedMetersPerSecond,
            routeCompletionPercent: routeCompletionPercent,
            gpsInterruptionCount: gpsInterruptionCount,
            gpsInterruptionDuration: gpsInterruptionDuration,
            deadReckonedDuration: deadReckonedDuration,
            offRouteEventCount: offRouteEventCount,
            weather: weather
        )
    }
}

enum RideWeatherClient {
    enum Result {
        case success(RideWeatherSnapshot, attempts: Int)
        case failure(message: String, attempts: Int)
    }

    static func currentWeather(
        at location: CLLocation,
        maximumAttempts: Int = 3
    ) async -> Result {
        let attemptLimit = max(maximumAttempts, 1)
        var lastFailure = "Unknown WeatherKit error"

        for attempt in 1...attemptLimit {
            do {
                let weather = try await WeatherService.shared.weather(for: location, including: .current)

                do {
                    let attribution = try await WeatherService.shared.attribution
                    return .success(
                        RideWeatherSnapshot(
                            observedAt: weather.date,
                            condition: weather.condition.description,
                            symbolName: weather.symbolName,
                            temperatureCelsius: weather.temperature.converted(to: .celsius).value,
                            apparentTemperatureCelsius: weather.apparentTemperature.converted(to: .celsius).value,
                            windKilometresPerHour: weather.wind.speed.converted(to: .kilometersPerHour).value,
                            windGustKilometresPerHour: weather.wind.gust?.converted(to: .kilometersPerHour).value,
                            precipitationMillimetresPerHour: weather.precipitationIntensity.converted(to: .kilometersPerHour).value * 1_000_000,
                            attributionServiceName: attribution.serviceName,
                            attributionMarkURL: attribution.combinedMarkDarkURL,
                            attributionLegalURL: attribution.legalPageURL
                        ),
                        attempts: attempt
                    )
                } catch {
                    lastFailure = "attribution: \(String(reflecting: error))"
                }
            } catch {
                lastFailure = "current weather: \(String(reflecting: error))"
            }

            guard attempt < attemptLimit else {
                break
            }

            let retryDelay = attempt == 1 ? 2 : 8
            try? await Task.sleep(for: .seconds(retryDelay))
        }

        return .failure(message: lastFailure, attempts: attemptLimit)
    }
}
