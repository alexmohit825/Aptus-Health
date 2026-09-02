//
//  WatchWorkoutTelemetryView.swift
//  Aptus Watch App
//
//  LIVE FEED: recovery-informed live coaching driven by a REAL HKLiveWorkoutBuilder
//  heart-rate feed. When a workout session is active (`WorkoutManager.isRunning`), the
//  HR ring, telemetry, and `LiveCoachingEngine` cue are driven by genuine sensor data
//  and each sample is streamed to the phone over WatchConnectivity. When no session is
//  active, the view falls back to the +/- simulation so it stays demoable in the
//  Simulator without a started workout.
//
//  The day's recovery band + age arrive from the phone via
//  `ConnectivityManager.lastWorkoutContext`; the standalone picker is only used as a
//  fallback when the phone hasn't pushed a context yet.
//
//  NOTE: add `LiveCoachingEngine.swift` to the Watch App target so this compiles.
//
//  COMPLIANCE (App Store Guideline 1.4): coaching cues are fitness guidance, not
//  medical advice.
//

import SwiftUI
import HealthKit

struct WatchWorkoutTelemetryView: View {
    @StateObject private var workoutManager = WorkoutManager()
    @ObservedObject private var connectivity = ConnectivityManager.shared

    // Simulation state — used ONLY when no real workout session is active.
    @State private var simHeartRate: Double = 142.0
    @State private var simPace: String = "5:12 /km"
    @State private var fallbackBand: RecoveryBand = .yellow

    private let engine = LiveCoachingEngine()

    // MARK: Live vs. simulated inputs

    /// True when a real HKLiveWorkoutBuilder session is streaming data.
    private var isLive: Bool { workoutManager.isRunning }

    /// The HR that drives the UI + coaching: real sensor HR when live, else simulated.
    private var heartRate: Double {
        if isLive, workoutManager.heartRate > 0 { return workoutManager.heartRate }
        return simHeartRate
    }

    /// Recovery band: from the phone's pushed context when available, else the picker.
    private var band: RecoveryBand {
        if let ctx = connectivity.lastWorkoutContext {
            return RecoveryBand.from(score: ctx.recoveryScore)
        }
        return fallbackBand
    }

    /// Age: from the phone's pushed context when available, else a safe default of 40.
    private var zones: HRZones {
        HRZones(age: connectivity.lastWorkoutContext?.age ?? 40)
    }

    private var cue: CoachingCue {
        engine.cue(recovery: band, heartRate: heartRate, zones: zones)
    }

    private var pace: String {
        isLive ? livePace : simPace
    }

    private var timeString: String {
        if isLive {
            let s = workoutManager.elapsedSeconds
            return "\(s / 60)m \(String(format: "%02d", s % 60))s"
        }
        return "22m 12s"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                provenanceBadge

                // Heart Rate Ring
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                        .scaleEffect(1.2)
                    Text("\(Int(heartRate))")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.bold)
                    Text("BPM")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                // Pace and Duration
                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("PACE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                        Text(pace)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    }
                    VStack(alignment: .leading) {
                        Text("TIME")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                        Text(timeString)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    }
                }
                .padding(.vertical, 4)

                // Recovery-informed target band + current zone.
                Text("Recovery: \(band.rawValue)  ·  Target Z\(cue.targetZoneLow)–Z\(cue.targetZoneHigh)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
                Text("Now: Zone \(cue.currentZone)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(cueColor)

                // Live recovery-informed coaching cue on Watch.
                VStack(spacing: 2) {
                    Text(cue.action.rawValue)
                        .font(.caption)
                        .fontWeight(.black)
                        .foregroundColor(.black)
                    Text(cue.message)
                        .font(.system(size: 10))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(cueColor)
                .cornerRadius(8)

                // Start / Stop the real workout session.
                workoutControls

                // Offline fallback controls — only when NO real session is active.
                if !isLive {
                    offlineControls
                }

                if let err = workoutManager.lastError {
                    Text(err)
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
    }

    // MARK: Sections

    private var provenanceBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: isLive ? "dot.radiowaves.left.and.right" : "hand.tap")
            Text(isLive ? "Live workout" : "Simulation")
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(isLive ? .green : .gray)
    }

    private var workoutControls: some View {
        Button {
            Task {
                if isLive { await workoutManager.stop() }
                else { await workoutManager.start() }
            }
        } label: {
            Label(isLive ? "End Workout" : "Start Workout",
                  systemImage: isLive ? "stop.fill" : "play.fill")
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .tint(isLive ? .red : .green)
        .padding(.top, 4)
    }

    private var offlineControls: some View {
        VStack(spacing: 8) {
            // +/- HR simulation.
            HStack {
                Button(action: { simHeartRate = min(190, simHeartRate + 5); updateSimPace() }) {
                    Image(systemName: "plus")
                }
                Spacer()
                Text("Simulated HR")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                Spacer()
                Button(action: { simHeartRate = max(90, simHeartRate - 5); updateSimPace() }) {
                    Image(systemName: "minus")
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 12)

            // Standalone recovery-band selector — only used if the phone hasn't pushed one.
            if connectivity.lastWorkoutContext == nil {
                Picker("Recovery", selection: $fallbackBand) {
                    Text("Green").tag(RecoveryBand.green)
                    Text("Yellow").tag(RecoveryBand.yellow)
                    Text("Red").tag(RecoveryBand.red)
                }
                .pickerStyle(.navigationLink)
                .font(.caption2)
            }
        }
    }

    // MARK: Helpers

    /// A coarse live pace estimate from the current zone (the builder gives distance,
    /// but a per-sample instantaneous pace is noisy — zone-based is stable for display).
    private var livePace: String {
        switch cue.currentZone {
        case 5: return "4:20 /km"
        case 4: return "4:40 /km"
        case 3: return "5:15 /km"
        case 2: return "5:55 /km"
        default: return "6:30 /km"
        }
    }

    /// Keeps the simulated pace readout responsive to intensity changes.
    private func updateSimPace() {
        switch cue.currentZone {
        case 5: simPace = "5:45 /km"
        case 4: simPace = "4:40 /km"
        case 3: simPace = "5:15 /km"
        case 2: simPace = "5:55 /km"
        default: simPace = "6:30 /km"
        }
    }

    private var cueColor: Color {
        switch cue.colorHint {
        case "green": return .green
        case "yellow": return .yellow
        case "red": return .red
        case "blue": return .blue
        default: return .gray
        }
    }
}
