//
//  AptusWatchApp.swift
//  Aptus Watch App
//

import SwiftUI

@main
struct AptusWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchWorkoutTelemetryView()
                .onAppear {
                    // Activate the WatchConnectivity session so the watch can receive
                    // the phone's WorkoutContext and stream live HR back. Idempotent.
                    ConnectivityManager.shared.activate()
                }
        }
    }
}
