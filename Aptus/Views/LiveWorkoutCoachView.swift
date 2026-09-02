//
//  LiveWorkoutCoachView.swift
//  Aptus
//
//  Recovery-informed live coaching on the phone — THE DIFFERENTIATOR. Today's
//  Recovery Score sets the recommended HR-zone band; live heart rate is compared
//  against it in real time to produce a coaching cue (push / hold / ease off /
//  recover). Shared logic lives in `LiveCoachingEngine` (also used by the Watch).
//
//  This screen drives coaching from the REAL live heart rate streamed from the Apple
//  Watch (`HKLiveWorkoutBuilder` → WatchConnectivity → `ConnectivityManager.lastSample`)
//  when a workout is active and the watch is reachable. Otherwise it falls back to a
//  simulated heart rate (slider) so it stays demoable in the Simulator without a paired
//  Watch. The provenance label shows which source is active.
//
//  COMPLIANCE (App Store Guideline 1.4): coaching cues are fitness guidance, not
//  medical advice.
//

import SwiftUI

struct LiveWorkoutCoachView: View {
    @ObservedObject var hkManager: HealthKitManager
    @ObservedObject private var connectivity = ConnectivityManager.shared

    @State private var simHeartRate: Double = 130
    // Ticks every second so live/simulation freshness re-evaluates even when no new
    // sample arrives (a stale watch sample should drop back to the simulation).
    @State private var now: Date = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let engine = LiveCoachingEngine()

    /// A watch sample counts as "live" if it arrived within the last 10 seconds while
    /// the watch is reachable.
    private var isLive: Bool {
        guard connectivity.isReachable, let s = connectivity.lastSample,
              s.kind == .heartRate else { return false }
        return now.timeIntervalSince(s.timestamp) < 10
    }

    private var heartRate: Double {
        if isLive, let s = connectivity.lastSample { return s.value }
        return simHeartRate
    }

    private var band: RecoveryBand {
        if let report = hkManager.recoveryReport {
            return RecoveryBand.from(score: report.score)
        }
        return .yellow
    }

    private var zones: HRZones { HRZones(age: hkManager.userAge) }

    private var cue: CoachingCue {
        engine.cue(recovery: band, heartRate: heartRate, zones: zones)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                planCard
                cueCard
                zonesCard
                if !isLive { simulatorCard }
                disclaimer
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Live Coach")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(clock) { now = $0 }
        .onAppear {
            connectivity.activate()
            // Push today's recovery + age to the watch so it drives coaching with the
            // same inputs (replaces the watch's standalone band picker + hard-coded age).
            let score = hkManager.recoveryReport?.score ?? 50
            connectivity.sendWorkoutContext(
                WorkoutContext(recoveryScore: score, age: hkManager.userAge)
            )
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("RECOVERY-INFORMED")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
                Text("Live Coaching")
                    .font(.largeTitle)
                    .fontWeight(.black)
            }
            Spacer()
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 35))
                .foregroundColor(bandColor)
        }
        .padding(.top)
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(bandColor).frame(width: 12, height: 12)
                Text("Today: \(band.rawValue) recovery")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(bandColor)
            }
            Text(engine.planSummary(for: band))
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bandColor.opacity(0.12))
        .cornerRadius(12)
    }

    private var cueCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: isLive ? "dot.radiowaves.left.and.right" : "hand.tap")
                Text(isLive ? "Live from Watch" : "Simulation")
            }
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(isLive ? .green : .gray)

            Text("\(Int(heartRate)) bpm")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundColor(cueColor)
            Text("Zone \(cue.currentZone)  ·  target Z\(cue.targetZoneLow)–Z\(cue.targetZoneHigh)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(cue.action.rawValue)
                .font(.title)
                .fontWeight(.black)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(cueColor)
                .cornerRadius(14)

            Text(cue.message)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private var zonesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your HR Zones")
                .font(.headline)
            ForEach(1...5, id: \.self) { z in
                let r = zones.range(for: z)
                HStack {
                    Circle()
                        .fill(zoneTint(z))
                        .frame(width: 10, height: 10)
                    Text("Zone \(z)")
                        .font(.subheadline)
                        .fontWeight(z == cue.currentZone ? .bold : .regular)
                    Spacer()
                    Text("\(Int(r.low))–\(Int(r.high)) bpm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if z >= cue.targetZoneLow && z <= cue.targetZoneHigh {
                        Image(systemName: "target")
                            .font(.caption2)
                            .foregroundColor(bandColor)
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private var simulatorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Simulated Heart Rate")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.gray)
            Slider(value: $simHeartRate, in: 80...190, step: 1)
                .tint(cueColor)
            HStack {
                Button { simHeartRate = max(80, simHeartRate - 5) } label: {
                    Image(systemName: "minus.circle.fill").font(.title2)
                }
                Spacer()
                Text("Drag to preview coaching cues at different intensities.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
                Button { simHeartRate = min(190, simHeartRate + 5) } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield")
                .foregroundColor(.secondary)
            Text("Coaching cues are fitness guidance based on your estimated recovery — not medical advice.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: Helpers

    private var bandColor: Color {
        switch band {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
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

    private func zoneTint(_ z: Int) -> Color {
        switch z {
        case 1: return .blue
        case 2: return .green
        case 3: return .yellow
        case 4: return .orange
        default: return .red
        }
    }
}
