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

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(sender.status)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Fixtures") {
                    ForEach(NavFixtures.all) { fixture in
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
