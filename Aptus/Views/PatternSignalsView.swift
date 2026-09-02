//
//  PatternSignalsView.swift
//  Aptus
//
//  Renders the on-device `PatternDetectorEngine` output (`PatternSignal` list) sorted
//  by severity (alert → insight → info). Each card shows the direction icon, a
//  severity-colored badge, a one-line summary, and an expandable detail with an
//  optional tappable evidence link.
//
//  COMPLIANCE (App Store Guideline 1.4): every pattern is an informational wellness
//  estimate — not a diagnosis, risk score, or medical device.
//

import SwiftUI

struct PatternSignalsView: View {
    @ObservedObject var hkManager: HealthKitManager
    @State private var expanded: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                Group {
                    if hkManager.patternSignals.isEmpty {
                        emptyState
                    } else {
                        ForEach(hkManager.patternSignals) { signal in
                            card(signal)
                        }
                    }
                }
                .proLocked("Pattern Detectors")

                disclaimer
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Patterns")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if hkManager.patternSignals.isEmpty {
                hkManager.refreshHiddenSignalsAndPatterns()
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HIDDEN PATTERNS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.gray)
            Text("Trends & Anomalies")
                .font(.largeTitle)
                .fontWeight(.black)
            Text("On-device analysis of your recent history. Sorted by how much they may be worth your attention.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func card(_ signal: PatternSignal) -> some View {
        let isOpen = expanded.contains(signal.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: signal.direction.symbolName)
                    .font(.headline)
                    .foregroundColor(color(for: signal.severity))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(signal.title)
                        .font(.headline)
                    Text(signal.severity.label)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(color(for: signal.severity))
                }
                Spacer()
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(signal.summary)
                .font(.subheadline)
                .foregroundColor(.primary)

            if isOpen {
                Text(signal.detail)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let entry = Self.libraryEntry(for: signal.id) {
                    // Evidence-backed signal → cite the shared EvidenceLibrary entry
                    // (threshold + plain-language "why this matters" + tappable source).
                    EvidenceRow(entry: entry, compact: true)
                } else if let url = signal.evidenceURL {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "book")
                            Text("Evidence")
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color(for: signal.severity).opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isOpen { expanded.remove(signal.id) } else { expanded.insert(signal.id) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.title)
                .foregroundColor(.green)
            Text("No notable patterns right now")
                .font(.headline)
            Text("As more Apple Watch history accumulates, trend and anomaly patterns will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield")
                .foregroundColor(.secondary)
            Text("Informational wellness estimates only — not a diagnosis or medical device. Consult a clinician about any health concern.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    /// Maps a `PatternSignal.id` to its evidence-backed `EvidenceLibrary` entry, so the
    /// pattern card and the score views cite the exact same source. Signals without a
    /// mapped biomarker fall back to their own `evidenceURL` (or none).
    private static func libraryEntry(for signalID: String) -> EvidenceEntry? {
        let map: [String: String] = [
            "hrv_down": "hrvSDNN",
            "rhr_elevated": "restingHR",
            "sleep_debt": "sleepHours",
            "vo2_down": "vo2Max",
            "blunted_hrr": "heartRateRecovery",
            "steps_down": "steps",
            "inactivity_streak": "steps",
            "afib_burden": "appleHeartStudy"
        ]
        guard let id = map[signalID] else { return nil }
        return EvidenceLibrary.entry(for: id)
    }

    // Maps the engine's string color hint to a SwiftUI color (keeps the engine SwiftUI-free).
    private func color(for severity: SignalSeverity) -> Color {
        switch severity.colorHint {
        case "orange": return .orange
        case "blue":   return .blue
        default:        return .gray
        }
    }
}
