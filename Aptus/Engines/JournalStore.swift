//
//  JournalStore.swift
//  Aptus
//
//  Persistence for daily wellness journal entries. Uses a uniform Codable JSON file
//  store in the app's Documents directory. This is deliberately chosen over SwiftData
//  so the feature builds and runs cleanly on the iOS 18 deployment target with no
//  `if #available` fences around the model layer (the spec explicitly permits "the
//  file/UserDefaults store uniformly if simpler"). No third-party dependencies.
//
//  COMPLIANCE (App Store Guideline 1.4): entries are the user's PRIVATE PERSONAL NOTES.
//  Nothing here interprets, diagnoses, or gives medical meaning to what the user writes.
//  The optional metrics snapshot simply records that day's already-computed app scores.
//

import Foundation
import Combine

// MARK: - Models

/// A snapshot of the day's computed scores, optionally attached to an entry so the user
/// can later notice personal correlations ("on tired days my HRV was lower").
public struct JournalMetricsSnapshot: Codable, Hashable {
    public var longevityScore: Int
    public var recoveryScore: Int
    public var fitnessScore: Int
    public var hrv: Double
    public var rhr: Double

    public init(longevityScore: Int, recoveryScore: Int, fitnessScore: Int,
                hrv: Double, rhr: Double) {
        self.longevityScore = longevityScore
        self.recoveryScore = recoveryScore
        self.fitnessScore = fitnessScore
        self.hrv = hrv
        self.rhr = rhr
    }
}

/// One free-text journal entry with optional mood/state tags and score snapshot.
public struct JournalEntry: Identifiable, Codable, Hashable {
    public let id: UUID
    public var date: Date
    public var text: String
    public var tags: [String]
    public var metricsSnapshot: JournalMetricsSnapshot?

    public init(id: UUID = UUID(), date: Date = Date(), text: String,
                tags: [String] = [], metricsSnapshot: JournalMetricsSnapshot? = nil) {
        self.id = id
        self.date = date
        self.text = text
        self.tags = tags
        self.metricsSnapshot = metricsSnapshot
    }
}

// MARK: - Store

/// Observable singleton the views bind to. CRUD over an on-disk JSON array.
public final class JournalStore: ObservableObject {
    public static let shared = JournalStore()

    /// Always kept sorted reverse-chronologically (newest first).
    @Published public private(set) var entries: [JournalEntry] = []

    /// A few suggested wellness tags for the chip picker (users can add their own).
    public static let suggestedTags = ["tired", "sore", "energized", "stressed",
                                       "rested", "motivated", "sick", "great sleep"]

    private let fileURL: URL

    /// `filename` is injectable for tests; defaults to the app Documents directory.
    public init(filename: String = "journal_entries.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = dir.appendingPathComponent(filename)
        load()
    }

    // MARK: CRUD

    public func add(_ entry: JournalEntry) {
        entries.append(entry)
        resort()
        persist()
    }

    /// Replaces the entry with the same id (no-op if not found).
    public func update(_ entry: JournalEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx] = entry
        resort()
        persist()
    }

    public func delete(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    /// Swipe-to-delete support against the current (sorted) ordering.
    public func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        persist()
    }

    // MARK: Persistence

    private func resort() {
        entries.sort { $0.date > $1.date }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.journal.decode([JournalEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded.sorted { $0.date > $1.date }
    }

    private func persist() {
        guard let data = try? JSONEncoder.journal.encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

// MARK: - Coders (ISO-8601 dates for stable, human-readable files)

private extension JSONEncoder {
    static var journal: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

private extension JSONDecoder {
    static var journal: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
