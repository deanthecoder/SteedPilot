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

struct ContentView: View {
    @StateObject private var sender = BluetoothNavSender()
    @State private var destination = "Ace Cafe"
    @State private var routeActive = false
    private let fixtures = NavFixtures.loadFixtures()
    private let replayRoute = NavFixtures.loadReplayRoute()

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    HStack {
                        Spacer()
                        Image("DTC")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 132, height: 78)
                            .accessibilityLabel("Dean The Coder")
                        Spacer()
                    }
                    .listRowBackground(Color.black)

                    HStack {
                        Text("Status")
                        Spacer()
                        Text(sender.status)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Route") {
                    TextField("Destination", text: $destination)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)

                    Button(routeActive ? "Route Active" : "Start Route") {
                        if let payload = NavFixtures.loadStubRouteStart() {
                            sender.send(payload)
                            routeActive = true
                        }
                    }
                    .disabled(routeActive || destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if routeActive {
                        Button("End Route", role: .destructive) {
                            sender.send(NavFixtures.clearRoute)
                            routeActive = false
                        }
                    }
                }

                if let replayRoute {
                    Section("Replay") {
                        Button(sender.isReplaying ? "Stop Replay" : "Replay Demo Route") {
                            if sender.isReplaying {
                                sender.cancelReplay()
                            } else {
                                sender.replay(replayRoute)
                            }
                        }

                        if sender.isReplaying {
                            HStack {
                                Text("Progress")
                                Spacer()
                                Text(sender.replayProgress)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Fixtures") {
                    ForEach(fixtures) { fixture in
                        Button(fixture.title) {
                            sender.send(fixture.data)
                        }
                    }
                }
            }
            .navigationTitle("SteedPilot")
        }
    }
}

struct ContentViewPreviews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
