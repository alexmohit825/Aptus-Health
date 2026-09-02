//
//  FitnessEngine.swift
//  Aptus
//
//  On-device Fitness Score engine (pure Swift, no UI, no HealthKit calls).
//
//  Grades how training is loading the user over a 14-day window using a
//  Banister-style impulse-response model (fitness / fatigue / form) and produces
//  a 0–100 Fitness Score plus 5 sub-scores:
//
//      Load · Intensity · Readiness · Variance · Strength
//
//  It also maps time-in-zone to the Seiler 3-zone (80/20 polarized) model and
//  keeps a per-workout contribution list so the UI can explain what drove each
//  sub-score.
//
//  COMPLIANCE (App Store Guideline 1.4): informational training-load estimate,
//  NOT a medical device or diagnosis. Sub-scores are fitness guidance only.
//
//  DATA NOTE: Banister's classic constants use a 42-day fitness / 7-day fatigue
//  time constant. Within a 14-day window we approximate fitness with a 14-day and
//  fatigue with a 7-day exponential decay — documented as an approximation, not a
//  validated clinical model (see PHASE2_INTEGRATION.md).
//

import Foundation

// MARK: - Public data model

public struct PolarizedSplit {
    public let lowPct: Double   // Seiler LIT: zones 1–2
    public let midPct: Double   // threshold: zone 3
    public let highPct: Double  // HIT: zones 4–5
    public let adherence: String // human-readable 80/20 adherence note
    public let onTarget: Bool    // true if roughly ~80% low / ~20% high
}

public struct WorkoutContribution: Identifiable {
    public let id = UUID()
    public let date: Date
    public let type: String
    public let durationMin: Double
    public let load: Double          // session training load (TRIMP-style)
    public let primaryZone: Int      // 1–5, dominant intensity zone
    public let drivesSubScore: String // which sub-score this workout most influenced
}

public struct FitnessReport {
    public let score: Double         // 0–100 overall
    public let load: Double          // sub-score 0–100
    public let intensity: Double     // sub-score 0–100
    public let readiness: Double     // sub-score 0–100
    public let variance: Double      // sub-score 0–100
    public let strength: Double      // sub-score 0–100
    public let fitness: Double       // Banister CTL (chronic load) raw
    public let fatigue: Double       // Banister ATL (acute load) raw
    public let form: Double          // Banister TSB = CTL - ATL raw
    public let polarizedSplit: PolarizedSplit
    public let contributions: [WorkoutContribution]
    public let generatedAt: Date
    public let dataQualityNote: String?
    public let disclaimer: String
}

// MARK: - Engine inputs

/// One workout over the analysis window. `timeInZoneSeconds` holds seconds spent in
/// HR zones 1…5 (index 0 = zone 1). If HR data is unavailable, callers may pass zeros
/// and the engine estimates intensity from active energy / duration.
public struct WorkoutInput {
    public let date: Date
    public let type: String
    public let durationMin: Double
    public let activeEnergyKcal: Double
    public let avgHR: Double?          // nil if unknown
    public let timeInZoneSeconds: [Double] // length 5 expected

    public init(date: Date, type: String, durationMin: Double,
                activeEnergyKcal: Double, avgHR: Double?, timeInZoneSeconds: [Double]) {
        self.date = date
        self.type = type
        self.durationMin = durationMin
        self.activeEnergyKcal = activeEnergyKcal
        self.avgHR = avgHR
        self.timeInZoneSeconds = timeInZoneSeconds
    }
}

public struct FitnessInputs {
    public var windowDays: Int
    public var maxHR: Double            // for reference; zones already bucketed upstream
    public var workouts: [WorkoutInput]
    public var strengthMinutesInWindow: Double // resistance-training minutes (if known)

    public init(windowDays: Int = 14, maxHR: Double, workouts: [WorkoutInput],
                strengthMinutesInWindow: Double = 0) {
        self.windowDays = windowDays
        self.maxHR = maxHR
        self.workouts = workouts
        self.strengthMinutesInWindow = strengthMinutesInWindow
    }
}

// MARK: - Engine

public struct FitnessEngine {

    public init() {}

    // Zone intensity multipliers for a TRIMP-style session load: higher zones cost
    // disproportionately more (Banister/Edwards weighting 1…5).
    private let zoneWeights: [Double] = [1, 2, 3, 4, 5]

    public func computeReport(from inputs: FitnessInputs) -> FitnessReport {
        let now = Date()
        let cal = Calendar.current
        let windowStart = cal.date(byAdding: .day, value: -inputs.windowDays, to: cal.startOfDay(for: now)) ?? now
        let workouts = inputs.workouts.filter { $0.date >= windowStart }

        // Sparse-data handling.
        var dataNote: String? = nil
        if workouts.isEmpty {
            dataNote = "No workouts found in the last \(inputs.windowDays) days — Fitness Score is a low-confidence estimate."
        } else if workouts.count < 3 {
            dataNote = "Only \(workouts.count) workout(s) in the last \(inputs.windowDays) days — score confidence is limited."
        }

        // Per-workout load + dominant zone.
        var contributions: [WorkoutContribution] = []
        var dailyLoad: [Date: Double] = [:]
        var totalZoneSeconds = [Double](repeating: 0, count: 5)

        for w in workouts {
            let zones = normalizedZones(for: w)
            for i in 0..<5 { totalZoneSeconds[i] += zones[i] }

            let load = sessionLoad(for: w, zones: zones)
            let day = cal.startOfDay(for: w.date)
            dailyLoad[day, default: 0] += load

            let primaryZone = (zones.enumerated().max(by: { $0.element < $1.element })?.offset ?? 1) + 1
            contributions.append(WorkoutContribution(
                date: w.date, type: w.type, durationMin: round1(w.durationMin),
                load: round1(load), primaryZone: primaryZone,
                drivesSubScore: primaryZone >= 4 ? "Intensity" : "Load"))
        }

        // Banister fitness/fatigue/form via exponential decay over the window.
        let (fitness, fatigue) = banister(dailyLoad: dailyLoad, windowStart: windowStart, now: now, cal: cal)
        let form = fitness - fatigue

        // --- Sub-scores (0–100) ---
        let totalLoad = dailyLoad.values.reduce(0, +)
        let loadScore = loadSubScore(totalLoad: totalLoad, days: inputs.windowDays)
        let intensityScore = intensitySubScore(zoneSeconds: totalZoneSeconds)
        let readinessScore = readinessSubScore(form: form, fitness: fitness)
        let varianceScore = varianceSubScore(dailyLoad: dailyLoad, windowDays: inputs.windowDays, windowStart: windowStart, cal: cal)
        let strengthScore = strengthSubScore(strengthMinutes: inputs.strengthMinutesInWindow, workouts: workouts)

        // Overall weighted blend. Load and Readiness dominate (they best reflect
        // whether training is productively building fitness without overreaching).
        let overall =
            loadScore * 0.28 +
            readinessScore * 0.24 +
            intensityScore * 0.20 +
            varianceScore * 0.16 +
            strengthScore * 0.12

        let split = polarized(totalZoneSeconds: totalZoneSeconds)

        // Tag which sub-score each workout most influenced (refine after scoring).
        contributions = tagContributions(contributions, intensityScore: intensityScore, loadScore: loadScore)

        return FitnessReport(
            score: clampScore(overall),
            load: clampScore(loadScore),
            intensity: clampScore(intensityScore),
            readiness: clampScore(readinessScore),
            variance: clampScore(varianceScore),
            strength: clampScore(strengthScore),
            fitness: round1(fitness),
            fatigue: round1(fatigue),
            form: round1(form),
            polarizedSplit: split,
            contributions: contributions.sorted { $0.date > $1.date },
            generatedAt: now,
            dataQualityNote: dataNote,
            disclaimer: "Informational training-load estimate — not a diagnosis or medical device. Fitness guidance only."
        )
    }

    // MARK: - Load / zone helpers

    /// Returns seconds-in-zone, estimating from duration + energy when HR zones are absent.
    private func normalizedZones(for w: WorkoutInput) -> [Double] {
        if w.timeInZoneSeconds.count == 5, w.timeInZoneSeconds.reduce(0, +) > 0 {
            return w.timeInZoneSeconds
        }
        // Estimate: distribute duration by intensity proxy from kcal/min.
        let secs = max(0, w.durationMin) * 60.0
        let kcalPerMin = w.durationMin > 0 ? w.activeEnergyKcal / w.durationMin : 0
        // Rough intensity proxy: <8 kcal/min → mostly Z2; 8–12 → Z3; >12 → Z4.
        var zones = [Double](repeating: 0, count: 5)
        switch kcalPerMin {
        case ..<8:  zones[1] = secs
        case 8..<12: zones[2] = secs
        default:     zones[3] = secs
        }
        return zones
    }

    private func sessionLoad(for w: WorkoutInput, zones: [Double]) -> Double {
        // TRIMP-style: sum over zones of (minutes-in-zone * zoneWeight).
        var load = 0.0
        for i in 0..<5 { load += (zones[i] / 60.0) * zoneWeights[i] }
        return load
    }

    /// Banister impulse-response: fitness (CTL) as 14-day EWMA, fatigue (ATL) as 7-day EWMA.
    private func banister(dailyLoad: [Date: Double], windowStart: Date, now: Date, cal: Calendar) -> (Double, Double) {
        let tauFitness = 14.0
        let tauFatigue = 7.0
        var fitness = 0.0
        var fatigue = 0.0
        // Iterate day-by-day applying decay then adding that day's load.
        var day = cal.startOfDay(for: windowStart)
        let end = cal.startOfDay(for: now)
        while day <= end {
            fitness = fitness * exp(-1.0 / tauFitness)
            fatigue = fatigue * exp(-1.0 / tauFatigue)
            let load = dailyLoad[day] ?? 0
            fitness += load * (1 - exp(-1.0 / tauFitness))
            fatigue += load * (1 - exp(-1.0 / tauFatigue))
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return (fitness, fatigue)
    }

    // MARK: - Sub-score mappings (0–100)

    private func loadSubScore(totalLoad: Double, days: Int) -> Double {
        // Reference: ~50 TRIMP-load/day sustained is a solid recreational-athlete target.
        let perDay = totalLoad / Double(max(1, days))
        return clamp(100 * perDay / 50.0, 0, 100)
    }

    private func intensitySubScore(zoneSeconds: [Double]) -> Double {
        let total = zoneSeconds.reduce(0, +)
        guard total > 0 else { return 50 }
        // Reward the presence of some high-intensity work (Z4–Z5 ~ up to 20%),
        // penalize both zero intensity and excessive grinding in Z3 (the "black hole").
        let highPct = (zoneSeconds[3] + zoneSeconds[4]) / total
        let midPct = zoneSeconds[2] / total
        // Ideal high ~0.15–0.25. Score peaks there, decays away.
        let highScore = 100 - min(100, abs(highPct - 0.20) * 300)
        let blackHolePenalty = midPct > 0.5 ? (midPct - 0.5) * 60 : 0
        return clamp(highScore - blackHolePenalty, 0, 100)
    }

    private func readinessSubScore(form: Double, fitness: Double) -> Double {
        // Form (TSB) positive → fresh/ready; strongly negative → overreached.
        // Normalize by fitness magnitude so it's scale-independent.
        guard fitness > 0.5 else { return 50 }
        let ratio = form / fitness           // typically ~ -0.5 … +0.5
        // ratio 0 → 70 (balanced), +0.3 → ~100, -0.3 → ~40.
        return clamp(70 + ratio * 100, 0, 100)
    }

    private func varianceSubScore(dailyLoad: [Date: Double], windowDays: Int, windowStart: Date, cal: Calendar) -> Double {
        // Consistency: lower coefficient of variation of daily load → higher score.
        var series: [Double] = []
        var day = cal.startOfDay(for: windowStart)
        for _ in 0..<windowDays {
            series.append(dailyLoad[day] ?? 0)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let m = mean(series)
        guard m > 0 else { return 40 }
        let cv = stdDev(series) / m
        // cv 0 → 100, cv 1.5+ → ~0.
        return clamp(100 - cv * 66.0, 0, 100)
    }

    private func strengthSubScore(strengthMinutes: Double, workouts: [WorkoutInput]) -> Double {
        // Guideline: ~2 strength sessions/week (~60+ min/week → ~120 min/14d).
        let inferred = workouts
            .filter { isStrength($0.type) }
            .reduce(0.0) { $0 + $1.durationMin }
        let mins = max(strengthMinutes, inferred)
        return clamp(100 * mins / 120.0, 0, 100)
    }

    private func isStrength(_ type: String) -> Bool {
        let t = type.lowercased()
        return t.contains("strength") || t.contains("functional") || t.contains("traditional")
            || t.contains("resistance") || t.contains("weight") || t.contains("core")
    }

    // MARK: - Seiler polarized split

    private func polarized(totalZoneSeconds: [Double]) -> PolarizedSplit {
        let total = totalZoneSeconds.reduce(0, +)
        guard total > 0 else {
            return PolarizedSplit(lowPct: 0, midPct: 0, highPct: 0,
                                  adherence: "No intensity data yet.", onTarget: false)
        }
        let low = (totalZoneSeconds[0] + totalZoneSeconds[1]) / total * 100
        let mid = totalZoneSeconds[2] / total * 100
        let high = (totalZoneSeconds[3] + totalZoneSeconds[4]) / total * 100

        // Seiler 80/20: ~80% low-intensity, ~20% high-intensity.
        let onTarget = low >= 75 && high <= 25 && high >= 10
        let note: String
        if onTarget {
            note = "On target — close to the Seiler 80/20 polarized model."
        } else if low < 75 {
            note = "Too much moderate/high intensity — aim for ~80% easy (Zone 1–2)."
        } else {
            note = "Very little high-intensity work — add some Zone 4–5 to reach ~20%."
        }
        return PolarizedSplit(lowPct: round1(low), midPct: round1(mid), highPct: round1(high),
                              adherence: note, onTarget: onTarget)
    }

    private func tagContributions(_ contributions: [WorkoutContribution],
                                  intensityScore: Double, loadScore: Double) -> [WorkoutContribution] {
        contributions.map { c in
            let tag: String
            if c.primaryZone >= 4 { tag = "Intensity" }
            else if isStrength(c.type) { tag = "Strength" }
            else if c.durationMin >= 60 { tag = "Load" }
            else { tag = "Variance" }
            return WorkoutContribution(date: c.date, type: c.type, durationMin: c.durationMin,
                                       load: c.load, primaryZone: c.primaryZone, drivesSubScore: tag)
        }
    }

    // MARK: - Math helpers

    private func mean(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        return xs.reduce(0, +) / Double(xs.count)
    }
    private func stdDev(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return 0 }
        let m = mean(xs)
        return (xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)).squareRoot()
    }
    private func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, x)) }
    private func clampScore(_ x: Double) -> Double { (clamp(x, 0, 100) * 10).rounded() / 10 }
    private func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
}
