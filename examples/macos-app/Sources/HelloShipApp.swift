// HelloShip: a tiny SwiftUI Mac app showing shipcrate's in-app updates.
// The only shipcrate-specific lines are marked "shipcrate". Build: sh build.sh  ·  Run: open build/HelloShip.app
import SwiftUI

@main
struct HelloShipApp: App {
    init() {   // shipcrate: lets scripts/update-path-test.sh prove that old copies update themselves
        if CommandLine.arguments.contains("--update-now") { Updater.shared.updateNow() }
    }
    var body: some Scene {
        WindowGroup { ContentView().frame(width: 420, height: 300) }
    }
}

/// App settings. The beta toggle just sets the update channel.
final class Settings: ObservableObject {
    @Published var beta = Updater.channel == "beta" { didSet { Updater.channel = beta ? "beta" : "stable" } }  // shipcrate
}

struct ContentView: View {
    @ObservedObject var updater = Updater.shared             // shipcrate: the updater from updater/Updater.swift
    @ObservedObject var settings = Settings()

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("HelloShip").font(.title2.bold())
                Spacer()
                UpdateButton(updater: updater)                // shipcrate: orange "Update" when a new version is out
            }
            AnnouncementBanner(updater: updater)              // shipcrate: messages sent with scripts/announce.sh
            Text("👋 Hello! You're on version \(updater.current).").frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            HStack {
                Toggle("Beta updates", isOn: $settings.beta)  // shipcrate: opt into the beta channel
                Spacer()
                Button("Check for Updates") { updater.check(userInitiated: true) }   // shipcrate
            }
        }
        .padding(20)
        .onAppear { updater.announceLaunch() }               // shipcrate: "What's new" after an update
    }
}
