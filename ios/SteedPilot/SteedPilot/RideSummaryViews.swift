// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

import SwiftUI

struct RideSummarySheet: View {
    @Environment(\.dismiss) private var dismiss

    let summary: RideSummary
    let usesMiles: Bool

    var body: some View {
        NavigationStack {
            RideSummaryContent(summary: summary, usesMiles: usesMiles)
                .navigationTitle("Ride complete")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct RideHistorySheet: View {
    @Environment(\.dismiss) private var dismiss

    let summaries: [RideSummary]
    let usesMiles: Bool
    let deleteSummary: (UUID) -> Void

    var body: some View {
        NavigationStack {
            RideHistoryContent(
                summaries: summaries,
                usesMiles: usesMiles,
                deleteSummary: deleteSummary
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct RideHistoryContent: View {
    let summaries: [RideSummary]
    let usesMiles: Bool
    let deleteSummary: (UUID) -> Void

    var body: some View {
        Group {
            if summaries.isEmpty {
                ContentUnavailableView(
                    "No Rides Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Completed rides will appear here automatically.")
                )
            } else {
                List {
                    ForEach(summaries) { summary in
                        NavigationLink {
                            RideSummaryContent(summary: summary, usesMiles: usesMiles)
                                .navigationTitle(summary.name)
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            RideHistoryRow(summary: summary, usesMiles: usesMiles)
                        }
                        .listRowBackground(Color.white.opacity(0.04))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteSummary(summary.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(red: 0.045, green: 0.050, blue: 0.060))
        .navigationTitle("Ride History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RideSummaryContent: View {
    let summary: RideSummary
    let usesMiles: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 5) {
                    Image(systemName: "flag.checkered.2.crossed")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.cyan)

                    Text(summary.name)
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text(summary.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                LazyVGrid(columns: columns, spacing: 10) {
                    RideMetricCard(icon: "point.topleft.down.curvedto.point.bottomright.up", title: "Distance", value: distanceText(summary.distanceMeters))
                    RideMetricCard(icon: "clock", title: "Elapsed", value: durationText(summary.elapsedTime))
                    RideMetricCard(icon: "gauge.with.dots.needle.33percent", title: "Overall avg", value: speedText(summary.overallAverageSpeedMetersPerSecond))
                    RideMetricCard(icon: "speedometer", title: "Maximum", value: speedText(summary.maximumSpeedMetersPerSecond))
                }

                if let weather = summary.weather {
                    weatherCard(weather)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Navigation quality", systemImage: "location.magnifyingglass")
                        .font(.headline)

                    LabeledContent("GPS interruptions", value: "\(summary.gpsInterruptionCount)")
                    LabeledContent("Time without GPS", value: durationText(summary.gpsInterruptionDuration))
                    LabeledContent("Dead reckoning", value: durationText(summary.deadReckonedDuration))
                    LabeledContent("Off-route events", value: "\(summary.offRouteEventCount)")
                }
                .summaryCard()
            }
            .padding(16)
        }
        .background(Color(red: 0.045, green: 0.050, blue: 0.060))
    }

    private func weatherCard(_ weather: RideWeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: weather.symbolName)
                    .font(.title2)
                    .foregroundStyle(.cyan)

                VStack(alignment: .leading, spacing: 2) {
                    Text(weather.condition)
                        .font(.headline)
                    Text("\(Int(weather.temperatureCelsius.rounded()))°C · Feels like \(Int(weather.apparentTemperatureCelsius.rounded()))°C")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Conditions at start")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            LabeledContent("Wind", value: "\(Int(weather.windKilometresPerHour.rounded())) km/h")
            if let gust = weather.windGustKilometresPerHour {
                LabeledContent("Gusts", value: "\(Int(gust.rounded())) km/h")
            }
            if weather.precipitationMillimetresPerHour > 0 {
                LabeledContent("Precipitation", value: String(format: "%.1f mm/h", weather.precipitationMillimetresPerHour))
            }

            Link(destination: weather.attributionLegalURL) {
                AsyncImage(url: weather.attributionMarkURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Text(weather.attributionServiceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel("Weather data attribution")
        }
        .summaryCard()
    }

    private func distanceText(_ meters: Double) -> String {
        if usesMiles {
            return String(format: "%.1f mi", meters / 1609.344)
        }
        return String(format: "%.1f km", meters / 1000)
    }

    private func speedText(_ metersPerSecond: Double) -> String {
        if usesMiles {
            return "\(Int((metersPerSecond * 2.2369362921).rounded())) mph"
        }
        return "\(Int((metersPerSecond * 3.6).rounded())) km/h"
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct RideMetricCard: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(.cyan)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .summaryCard()
    }
}

private struct RideHistoryRow: View {
    let summary: RideSummary
    let usesMiles: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: summary.weather?.symbolName ?? "figure.outdoor.cycle")
                .font(.headline)
                .foregroundStyle(.cyan)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(summary.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(distanceText) · \(durationText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var distanceText: String {
        usesMiles
            ? String(format: "%.1f mi", summary.distanceMeters / 1609.344)
            : String(format: "%.1f km", summary.distanceMeters / 1000)
    }

    private var durationText: String {
        let minutes = max(Int(summary.elapsedTime / 60), 0)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

private extension View {
    func summaryCard() -> some View {
        padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

#Preview("Ride Summary") {
    RideSummarySheet(summary: .preview, usesMiles: true)
}

#Preview("Ride History") {
    RideHistorySheet(
        summaries: [.preview],
        usesMiles: true,
        deleteSummary: { _ in }
    )
}

private extension RideSummary {
    static var preview: RideSummary {
        RideSummary(
            id: UUID(),
            name: "Sunday loop",
            startedAt: Date().addingTimeInterval(-5_400),
            endedAt: Date(),
            distanceMeters: 31_200,
            plannedDistanceMeters: 30_800,
            movingTime: 4_860,
            maximumSpeedMetersPerSecond: 13.8,
            routeCompletionPercent: 100,
            gpsInterruptionCount: 2,
            gpsInterruptionDuration: 13,
            deadReckonedDuration: 10,
            offRouteEventCount: 1,
            weather: RideWeatherSnapshot(
                observedAt: Date(),
                condition: "Partly Cloudy",
                symbolName: "cloud.sun.fill",
                temperatureCelsius: 18,
                apparentTemperatureCelsius: 17,
                windKilometresPerHour: 14,
                windGustKilometresPerHour: 23,
                precipitationMillimetresPerHour: 0,
                attributionServiceName: "Weather",
                attributionMarkURL: URL(string: "https://example.com/weather.svg")!,
                attributionLegalURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
            )
        )
    }
}
