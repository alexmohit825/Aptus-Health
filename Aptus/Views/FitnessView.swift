//
//  FitnessView.swift
//  Aptus
//
//  SwiftUI view for the on-device Fitness Score: overall 0–100 score, the five
//  sub-scores (Load · Intensity · Readiness · Variance · Strength), the Seiler
//  80/20 polarized intensity split, and the per-workout contributions that drove
//  each sub-score.
//
//  Also hosts `NarrativeInsightCard`, the shared "Today's insight" card reused by
//  LongevityView and RecoveryView to render a `NarrativeInsight`.
//
//  COMPLIANCE (App Store Guideline 1.4): informational training-load estimate,
//  not a diagnosis or medical device. Fitness guidance only.
//

import SwiftUI

struct FitnessView: View {
    @ObservedObject var hkManager: HealthKitManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let report = hkManager.fitnessReport {
                    scoreCard(report)
                    if let note = report.dataQualityNote {
                        dataQualityBanner(note)
                    }
                    Group {
                        subScorePanel(report)
                        polarizedCard(report.polarizedSplit)
                        contributionsPanel(report)
                        EvidenceSection(ids: EvidenceLibrary.fitnessIDs)
                    }
                    .proLocked("Fitness breakdown")
                    disclaimer(report.disclaimer)
                } else {
                    emptyState
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Fitness")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if hkManager.fitnessReport == nil {
                hkManager.refreshFitnessScore()
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("TRAINING INSIGHT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
                Text("Fitness Score")
                    .font(.largeTitle)
                    .fontWeight(.black)
            }
            Spacer()
            Image(systemName: "figure.run")
                .font(.system(size: 35))
                .foregroundColor(.orange)
        }
        .padding(.top)
    }

    private func scoreCard(_ report: FitnessReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("14-Day Fitness")
                    .font(.headline)
                Spacer()
                Text("\(Int(report.score.rounded()))")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundColor(scoreColor(report.score))
                Text("/100")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            ProgressView(value: report.score, total: 100)
                .tint(scoreColor(report.score))

            HStack {
                banisterStat("Fitness", report.fitness, .blue)
                Spacer()
                banisterStat("Fatigue", report.fatigue, .orange)
                Spacer()
                banisterStat("Form", report.form, report.form >= 0 ? .green : .red)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private func banisterStat(_ label: String, _ value: Double, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.0f", value))
                .font(.headline)
                .foregroundColor(tint)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func subScorePanel(_ report: FitnessReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sub-Scores")
                .font(.headline)
            subScoreRow("Load", report.load, "scalemass")
            Divider()
            subScoreRow("Intensity", report.intensity, "flame")
            Divider()
            subScoreRow("Readiness", report.readiness, "battery.100")
            Divider()
            subScoreRow("Variance", report.variance, "waveform.path.ecg")
            Divider()
            subScoreRow("Strength", report.strength, "dumbbell")
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private func subScoreRow(_ name: String, _ value: Double, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundColor(scoreColor(value))
                .frame(width: 22)
            Text(name)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            Text("\(Int(value.rounded()))")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(scoreColor(value))
            ProgressView(value: value, total: 100)
                .tint(scoreColor(value))
                .frame(width: 90)
        }
    }

    private func polarizedCard(_ split: PolarizedSplit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Intensity Pattern")
                    .font(.headline)
                Spacer()
                Text(split.onTarget ? "On Target" : "Off Target")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(split.onTarget ? .green : .orange)
            }
            Text("Seiler 80/20 polarized model")
                .font(.caption)
                .foregroundColor(.secondary)

            polarizedBar(split)

            HStack {
                legendDot(.green, "Low (Z1–2) \(Int(split.lowPct.rounded()))%")
                Spacer()
                legendDot(.yellow, "Mid (Z3) \(Int(split.midPct.rounded()))%")
                Spacer()
                legendDot(.red, "High (Z4–5) \(Int(split.highPct.rounded()))%")
            }
            .font(.caption2)

            Text(split.adherence)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private func polarizedBar(_ split: PolarizedSplit) -> some View {
        GeometryReader { geo in
            let total = max(1, split.lowPct + split.midPct + split.highPct)
            let w = geo.size.width
            HStack(spacing: 0) {
                Rectangle().fill(Color.green)
                    .frame(width: w * CGFloat(split.lowPct / total))
                Rectangle().fill(Color.yellow)
                    .frame(width: w * CGFloat(split.midPct / total))
                Rectangle().fill(Color.red)
                    .frame(width: w * CGFloat(split.highPct / total))
            }
            .clipShape(Capsule())
        }
        .frame(height: 14)
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundColor(.secondary)
        }
    }

    private func contributionsPanel(_ report: FitnessReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Contributions")
                .font(.headline)
            if report.contributions.isEmpty {
                Text("No workouts logged in the last 14 days.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(report.contributions) { c in
                    contributionRow(c)
                    if c.id != report.contributions.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private func contributionRow(_ c: WorkoutContribution) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.type)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("\(dateText(c.date))  ·  \(Int(c.durationMin.rounded())) min  ·  Zone \(c.primaryZone)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(c.drivesSubScore)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                Text("load \(Int(c.load.rounded()))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func dataQualityBanner(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundColor(.orange)
            Text(note)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(12)
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
            Image(systemName: "figure.run")
                .font(.title)
                .foregroundColor(.orange)
            Text("Sync your workouts to generate your estimated 14-day Fitness Score.")
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

    private func scoreColor(_ s: Double) -> Color {
        switch s {
        case ..<50: return .red
        case 50..<75: return .orange
        default: return .green
        }
    }

    private func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

// MARK: - Shared "Today's insight" card (Narrative)

/// Renders a `NarrativeInsight` (Apple Intelligence / Gemini / template). Reused by
/// LongevityView and RecoveryView. Shows the generation source honestly so the user
/// knows whether it ran fully on-device.
struct NarrativeInsightCard: View {
    let insight: NarrativeInsight
    @State private var showSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)
                Text("Today's Insight")
                    .font(.headline)
                Spacer()
                AISourceBadge(source: insight.source)
            }

            Text(insight.headline)
                .font(.title3)
                .fontWeight(.bold)

            Text(insight.body)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if !insight.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(insight.bullets, id: \.self) { b in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text(b)
                                .font(.footnote)
                        }
                    }
                }
                .padding(.top, 2)
            }

            Text(insight.disclaimer)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 2)

            // Sources & citations (App Store Guideline 1.4.1): the health recommendations
            // in these insights are backed by the reputable sources below — functional links,
            // easy to find, directly inside the insight card.
            DisclosureGroup("Sources & Citations", isExpanded: $showSources) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Self.citations, id: \.self) { citation in
                        Link(citation.title, destination: citation.url)
                            .font(.caption)
                    }
                }
                .padding(.top, 4)
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    // Reputable sources backing the health metrics and recommendations shown above
    // (Guideline 1.4.1). All links reviewed for functionality.
    private struct Citation: Hashable {
        let title: String
        let url: URL
    }
    private static let citations: [Citation] = [
        Citation(title: "Sleep & recovery — CDC",
                 url: URL(string: "https://www.cdc.gov/sleep/about/index.html")!),
        Citation(title: "Resting heart rate — American Heart Association",
                 url: URL(string: "https://www.heart.org/en/health-topics/high-blood-pressure/the-facts-about-high-blood-pressure/all-about-heart-rate-pulse")!),
        Citation(title: "Physical Activity Guidelines — HHS",
                 url: URL(string: "https://odphp.health.gov/our-work/nutrition-physical-activity/physical-activity-guidelines")!),
        Citation(title: "Cardiorespiratory fitness & VO₂ max — CDC",
                 url: URL(string: "https://www.cdc.gov/physical-activity-basics/about/index.html")!),
        Citation(title: "Physical activity & health outcomes — WHO 2020",
                 url: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC7719906/")!),
        Citation(title: "Apple Health — how metrics are measured",
                 url: URL(string: "https://www.apple.com/health/")!)
    ]
}
