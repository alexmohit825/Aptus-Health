//
//  RecoveryView.swift
//  Aptus
//
//  SwiftUI view for the daily Recovery Score: color-coded zone, today's strain
//  target (recommended intensity), and a per-metric breakdown (HRV / Sleep / RHR / RR).
//
//  COMPLIANCE (App Store Guideline 1.4): informational training-readiness estimate,
//  not a medical device or diagnosis.
//

import SwiftUI

struct RecoveryView: View {
    @ObservedObject var hkManager: HealthKitManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let report = hkManager.recoveryReport {
                    scoreCard(report)
                    if let insight = hkManager.narrativeInsightRecovery {
                        NarrativeInsightCard(insight: insight)
                    }
                    strainCard(report)
                    Group {
                        metricPanel(report)
                        EvidenceSection(ids: EvidenceLibrary.recoveryIDs)
                    }
                    .proLocked("Recovery breakdown")
                    disclaimer(report.disclaimer)
                } else {
                    emptyState
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Recovery")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if hkManager.recoveryReport == nil {
                hkManager.computeEngineReports()
            } else if hkManager.narrativeInsightRecovery == nil {
                hkManager.refreshNarrative()
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("RECOVERY INSIGHT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
                Text("Readiness")
                    .font(.largeTitle)
                    .fontWeight(.black)
            }
            Spacer()
            Image(systemName: "bolt.heart.fill")
                .font(.system(size: 35))
                .foregroundColor(zoneColor(hkManager.recoveryReport?.zone))
        }
        .padding(.top)
    }

    private func scoreCard(_ report: RecoveryReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recovery Score")
                    .font(.headline)
                Spacer()
                Text("\(report.score)")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundColor(zoneColor(report.zone))
                Text("%")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(zoneColor(report.zone))
                    .frame(width: 12, height: 12)
                Text("\(report.zone.rawValue) Zone")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(zoneColor(report.zone))
            }
            ProgressView(value: Double(report.score), total: 100)
                .tint(zoneColor(report.zone))
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private func strainCard(_ report: RecoveryReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's Strain Target")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.gray)
            Text(report.strainTarget)
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(zoneColor(report.zone).opacity(0.12))
        .cornerRadius(12)
    }

    private func metricPanel(_ report: RecoveryReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contributing Metrics")
                .font(.headline)
            ForEach(report.perMetric) { m in
                metricRow(m)
                if m.id != report.perMetric.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private func metricRow(_ m: MetricResult) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("\(fmt(m.value)) \(m.unit)  ·  base \(fmt(m.baseline))  ·  \(Int(m.weight * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(zText(m.zScore))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(m.zScore >= 0 ? .green : .orange)
                Text("z-score")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func disclaimer(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield")
                .foregroundColor(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.heart")
                .font(.title)
                .foregroundColor(.green)
            Text("Authorize Apple Health and sync to generate today's estimated Recovery Score.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    // MARK: Helpers

    private func zoneColor(_ zone: RecoveryZone?) -> Color {
        switch zone {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        case .none: return .gray
        }
    }

    private func zText(_ z: Double) -> String {
        String(format: "%+.1f", z)
    }

    private func fmt(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.0f", v) }
        if v == v.rounded() { return String(format: "%.0f", v) }
        return String(format: "%.1f", v)
    }
}
