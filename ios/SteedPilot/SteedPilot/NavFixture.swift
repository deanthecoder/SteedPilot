// Code authored by Dean Edis (DeanTheCoder).
// Anyone is free to copy, modify, use, compile, or distribute this software,
// either in source code form or as a compiled binary, for any purpose.
//
// If you modify the code, please retain this copyright header,
// and consider contributing back to the repository or letting us know
// about your modifications. Your contributions are valued!
//
// THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.

import Foundation

struct NavFixture: Identifiable {
    let id = UUID()
    let title: String
    let filename: String
    let data: Data
}

struct ReplayStep: Decodable, Identifiable {
    let id = UUID()
    let packet: String?
    let json: String?
    let delayMs: Int

    private enum CodingKeys: String, CodingKey {
        case packet
        case json
        case delayMs
    }
}

struct ReplayRoute: Decodable {
    let steps: [ReplayStep]
}

enum NavFixtures {
    static let heartbeat = Data(#"{ "v": 1, "type": "heartbeat" }"#.utf8)

    /**
     * Loads the fixture buttons from bundled JSON resources.
     *
     * - Returns: Fixture packets available for one-tap sending.
     */
    static func loadFixtures() -> [NavFixture] {
        [
            loadFixture(title: "Ahead", filename: "navigation-ahead.json"),
            loadFixture(title: "Left", filename: "navigation-left.json"),
            loadFixture(title: "Bend Left", filename: "navigation-bend-left.json"),
            loadFixture(title: "U Turn", filename: "navigation-u-turn.json"),
            loadFixture(title: "Roundabout", filename: "navigation-roundabout.json"),
            loadFixture(title: "Speed Warning", filename: "navigation-speed-warning.json"),
            loadFixture(title: "Destination", filename: "destination-heading.json"),
            loadFixture(title: "Update", filename: "update-distance.json"),
            NavFixture(title: "Heartbeat", filename: "heartbeat.json", data: heartbeat)
        ].compactMap { $0 }
    }

    /**
     * Loads the bundled replay route definition.
     *
     * - Returns: Timed replay route, or nil if the resource cannot be decoded.
     */
    static func loadReplayRoute() -> ReplayRoute? {
        guard let data = loadData(filename: "route-demo.json") else {
            return nil
        }

        return try? JSONDecoder().decode(ReplayRoute.self, from: data)
    }

    /**
     * Resolves a replay step to the JSON payload that should be sent.
     *
     * - Parameter step: Replay route step.
     * - Returns: JSON payload bytes, or nil when the step cannot be resolved.
     */
    static func payload(for step: ReplayStep) -> Data? {
        if let json = step.json {
            return Data(json.utf8)
        }

        guard let packet = step.packet else {
            return nil
        }

        return loadData(filename: URL(fileURLWithPath: packet).lastPathComponent)
    }

    /**
     * Loads one named fixture from the bundled resources.
     *
     * - Parameters:
     *   - title: User-facing button title.
     *   - filename: JSON resource filename.
     * - Returns: Fixture packet, or nil when the file is unavailable.
     */
    private static func loadFixture(title: String, filename: String) -> NavFixture? {
        guard let data = loadData(filename: filename) else {
            return nil
        }

        return NavFixture(title: title, filename: filename, data: data)
    }

    /**
     * Loads a JSON file from the bundled fixture folder.
     *
     * - Parameter filename: Resource filename including `.json`.
     * - Returns: File contents as bytes, or nil when unavailable.
     */
    private static func loadData(filename: String) -> Data? {
        let resource = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json", subdirectory: "Fixtures") else {
            return nil
        }

        return try? Data(contentsOf: url)
    }
}
