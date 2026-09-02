//
//  EvidenceView.swift
//  Aptus
//
//  Reusable cited-evidence surfaces backed by `EvidenceLibrary` (the single source of
//  truth for evidence-backed thresholds + citations). Three pieces:
//
//   • `EvidenceView`        — full screen, all entries grouped by biomarker (dashboard tile).
//   • `EvidenceSection`     — an expandable "Why this matters" block to embed in the
//                             Longevity / Recovery / Fitness / Pattern score views.
//   • `EvidenceRow`         — one entry with threshold, plain-language detail, tappable link.
//
//  COMPLIANCE (App Store Guideline 1.4): links go to real, peer-reviewed sources only.
//  Nothing here diagnoses — it explains why each estimate matters, in wellness terms.
//

import SwiftUI

// MARK: - Full-screen library (dashboard "Evidence" tile)

struct EvidenceView: View {
    /// Optional subset; nil shows the whole library.
    let entries: [EvidenceEntry]

    init(entries: [EvidenceEntry] = EvidenceLibrary.all) {
        self.entries = entries
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                ForEach(entries) { entry in
                    EvidenceRow(entry: entry)
                }
                footer
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Evidence")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("WHY THIS MATTERS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
                Text("The Science")
                    .font(.largeTitle)
                    .fontWeight(.black)
            }
            Spacer()
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 32))
                .foregroundColor(.teal)
        }
        .padding(.top)
    }

    private var footer: some View {
        Text("Aptus estimates are informational and based on the peer-reviewed sources above. They are not a diagnosis or medical device — review with a professional before acting on them.")
            .font(.footnote)
            .foregroundColor(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
    }
}

// MARK: - Embeddable expandable section

/// Drop into any score view: `EvidenceSection(ids: EvidenceLibrary.recoveryIDs)`.
/// Renders a collapsed "Why this matters" disclosure that expands to the cited entries.
struct EvidenceSection: View {
    let title: String
    let entries: [EvidenceEntry]
    @State private var expanded = false

    init(title: String = "Why this matters", ids: [String]) {
        self.title = title
        self.entries = EvidenceLibrary.entries(ids: ids)
    }

    init(title: String = "Why this matters", entries: [EvidenceEntry]) {
        self.title = title
        self.entries = entries
    }

    var body: some View {
        if entries.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "books.vertical")
                            .foregroundColor(.teal)
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    ForEach(entries) { entry in
                        EvidenceRow(entry: entry, compact: true)
                    }
                }
            }
            .padding()
            .background(Color(uiColor: .systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - Single entry row

struct EvidenceRow: View {
    let entry: EvidenceEntry
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.biomarker)
                .font(.subheadline)
                .fontWeight(.bold)
            Text(entry.thresholdSummary)
                .font(.footnote)
                .foregroundColor(.primary)
            Text(entry.detail)
                .font(.footnote)
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "link")
                Link(entry.title, destination: entry.url)
            }
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 12 : 16)
        .background(compact
                    ? Color(uiColor: .secondarySystemBackground)
                    : Color(uiColor: .systemBackground))
        .cornerRadius(compact ? 10 : 16)
        .shadow(color: compact ? .clear : Color.black.opacity(0.05),
                radius: compact ? 0 : 8, x: 0, y: 4)
    }
}
