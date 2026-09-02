//
//  LongevityEngine.swift
//  Aptus
//
//  On-device Longevity Drift Score engine (pure Swift, no UI, no HealthKit calls).
//
//  Computes an informational "Longevity Drift Score" (0–100) by blending, for each
//  of 8 biomarkers:
//    (a) an AGE/SEX-ADJUSTED population sub-score (0–100) — where being at or above
//        the healthy norm for the user's age/sex scores high, and
//    (b) a PERSONAL DRIFT adjustment — the recent (7-day) value's deviation from the
//        user's own 21-day baseline (a z-score), nudging the sub-score up or down.
//
//  COMPLIANCE (App Store Guideline 1.4): This is an informational wellness estimate,
//  NOT a medical device, diagnosis, or risk prediction. All normative tables below are
//  approximations drawn from published population studies and REQUIRE physician review
//  before being treated as anything more than a general wellness signal.
//
//  The engine is deliberately pure: it takes plain numeric inputs and returns a
//  LongevityReport. Data acquisition (HealthKit) lives in HealthKitManager.
//

import Foundation

// MARK: - Public data model

/// Direction of a biomarker's recent personal drift relative to the user's baseline,
/// interpreted so that `.improving` always means "moving toward better longevity."
public enum BiomarkerTrend: String {
    case improving = "Improving"
    case stable    = "Stable"
    case declining = "Declining"

    var symbolName: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .stable:    return "arrow.right"
        case .declining: return "arrow.down.right"
        }
    }
}

/// Per-biomarker result surfaced to the UI. `subScore` is the final blended 0–100
/// contribution for this biomarker (age-norm score adjusted by personal drift).
public struct BiomarkerResult: Identifiable {
    public let id: String            // stable identifier, e.g. "vo2Max"
    public let name: String          // display name
    public let userValue: Double     // recent value (7-day representative)
    public let unit: String
    public let baselineValue: Double // user's own 21-day baseline mean
    public let ageNorm: Double       // healthy age/sex norm reference value
    public let subScore: Double      // 0–100 blended sub-score for this biomarker
    public let trend: BiomarkerTrend
    public let evidenceCitation: String
    public let evidenceURL: String
}

/// Full longevity report. `overallScore` is the weighted blend of the per-biomarker
/// sub-scores (VO2 max weighted highest — strongest mortality evidence).
public struct LongevityReport {
    public let overallScore: Double          // 0–100
    public let biomarkers: [BiomarkerResult]
    public let generatedAt: Date
    public let disclaimer: String
}

// MARK: - Engine inputs

public enum BiologicalSexInput {
    case male
    case female
    case other // falls back to the average of male/female norms
}

/// One biomarker's raw inputs. `recentValues` = last ~7 days of daily values,
/// `baselineValues` = trailing ~21 days used to establish the personal baseline.
/// When history is unavailable, callers may pass a single-element array; the engine
/// degrades gracefully (drift adjustment → 0, baseline == recent).
public struct BiomarkerInput {
    public let recentValues: [Double]
    public let baselineValues: [Double]

    public init(recentValues: [Double], baselineValues: [Double]) {
        self.recentValues = recentValues
        self.baselineValues = baselineValues
    }

    /// Convenience for when only a single latest value is known.
    public init(latest: Double) {
        self.recentValues = [latest]
        self.baselineValues = [latest]
    }
}

/// The complete set of engine inputs. Any biomarker may be nil (not yet available);
/// nil biomarkers are excluded from the blend and its weight is redistributed.
public struct LongevityInputs {
    public var age: Int
    public var sex: BiologicalSexInput

    public var vo2Max: BiomarkerInput?
    public var hrvSDNN: BiomarkerInput?
    public var restingHR: BiomarkerInput?
    public var sleepHours: BiomarkerInput?
    public var steps: BiomarkerInput?
    public var exerciseMinutes: BiomarkerInput?
    public var heartRateRecovery: BiomarkerInput?
    public var walkingSpeed: BiomarkerInput?

    public init(age: Int, sex: BiologicalSexInput) {
        self.age = age
        self.sex = sex
    }
}

// MARK: - Engine

public struct LongevityEngine {

    public init() {}

    // Whether a higher raw value is better for longevity.
    private enum Direction { case higherIsBetter, lowerIsBetter, optimalRange }

    // ---------------------------------------------------------------------
    // WEIGHTS — documented with evidence rationale.
    //
    // VO2 max carries the largest weight: it has the strongest and most
    // consistent dose-response association with all-cause mortality of any
    // consumer-measurable biomarker here (Fraser et al., Br J Sports Med 2024,
    // HR 0.47 for highest vs lowest CRF; da Costa et al. ~14% lower mortality
    // per +1 MET). HRV and RHR are next (autonomic/cardiovascular mortality
    // signals). Sleep is U-shaped and moderately weighted. Steps, exercise
    // minutes, HR-recovery and gait speed round out the blend. Weights sum to 1.0.
    //
    // These weights are a defensible starting point, NOT a validated clinical
    // model — flagged for physician review (see PHASE1_INTEGRATION.md).
    // ---------------------------------------------------------------------
    private struct Spec {
        let id: String
        let name: String
        let unit: String
        let weight: Double
        let direction: Direction
        let citation: String
        let url: String
    }

    private let specs: [String: Spec] = [
        "vo2Max": Spec(
            id: "vo2Max", name: "VO₂ Max", unit: "ml/kg/min", weight: 0.24,
            direction: .higherIsBetter,
            citation: "Cardiorespiratory fitness vs all-cause mortality: HR 0.47 (highest vs lowest); ~14% lower risk per +1 MET. Fraser et al., Br J Sports Med 2024.",
            url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC11103301/"),
        "hrvSDNN": Spec(
            id: "hrvSDNN", name: "Heart Rate Variability (SDNN)", unit: "ms", weight: 0.15,
            direction: .higherIsBetter,
            citation: "Lowest vagally-mediated HRV quartile → all-cause mortality HR 1.56 (1.32–1.85). Jarczok et al., Neurosci Biobehav Rev 2022.",
            url: "https://linkinghub.elsevier.com/retrieve/pii/S0149763422003967"),
        "restingHR": Spec(
            id: "restingHR", name: "Resting Heart Rate", unit: "bpm", weight: 0.14,
            direction: .lowerIsBetter,
            citation: "Each +10 bpm resting HR → all-cause mortality RR 1.17 (1.14–1.19). Aune et al., Nutr Metab Cardiovasc Dis 2017.",
            url: "https://linkinghub.elsevier.com/retrieve/pii/S0939475317300856"),
        "sleepHours": Spec(
            id: "sleepHours", name: "Sleep Duration", unit: "hrs", weight: 0.12,
            direction: .optimalRange,
            citation: "U-shaped mortality: <7h HR ~1.14, ≥9h HR ~1.34 vs 7–8h. Ungvari et al., GeroScience 2025.",
            url: "https://link.springer.com/10.1007/s11357-025-01592-y"),
        "heartRateRecovery": Spec(
            id: "heartRateRecovery", name: "Heart-Rate Recovery (1 min)", unit: "bpm", weight: 0.11,
            direction: .higherIsBetter,
            citation: "Attenuated 1-min HR recovery predicts higher all-cause mortality (classic Cole et al. threshold ≤12 bpm; larger drop = better autonomic reactivation).",
            url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC11103301/"),
        "walkingSpeed": Spec(
            id: "walkingSpeed", name: "Walking Speed", unit: "m/s", weight: 0.08,
            direction: .higherIsBetter,
            citation: "Each +0.1 m/s gait speed → ~23–25% lower mortality. Studenski et al., JAMA 2011; Perera et al. 2024.",
            url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC3080184/"),
        "steps": Spec(
            id: "steps", name: "Daily Steps", unit: "steps", weight: 0.08,
            direction: .higherIsBetter,
            citation: "Higher daily step counts associate with progressively lower all-cause mortality. Lee et al., JAMA Intern Med.",
            url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC2951585/"),
        "exerciseMinutes": Spec(
            id: "exerciseMinutes", name: "Exercise Minutes", unit: "min", weight: 0.08,
            direction: .higherIsBetter,
            citation: "Meeting/exceeding activity guidelines (~≥30 min/day moderate) associates with substantially lower mortality. Fraser et al., Br J Sports Med 2024.",
            url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC11103301/")
    ]

    // MARK: Public entry point

    public func computeReport(from inputs: LongevityInputs) -> LongevityReport {
        var results: [BiomarkerResult] = []

        func add(_ id: String, _ input: BiomarkerInput?) {
            guard let input = input, let spec = specs[id] else { return }
            let norm = normReference(for: id, age: inputs.age, sex: inputs.sex)
            results.append(makeResult(spec: spec, input: input, ageNorm: norm))
        }

        add("vo2Max", inputs.vo2Max)
        add("hrvSDNN", inputs.hrvSDNN)
        add("restingHR", inputs.restingHR)
        add("sleepHours", inputs.sleepHours)
        add("heartRateRecovery", inputs.heartRateRecovery)
        add("walkingSpeed", inputs.walkingSpeed)
        add("steps", inputs.steps)
        add("exerciseMinutes", inputs.exerciseMinutes)

        // Weighted blend with weight redistribution over available biomarkers.
        let totalWeight = results.reduce(0.0) { $0 + (specs[$1.id]?.weight ?? 0) }
        let overall: Double
        if totalWeight > 0 {
            let weighted = results.reduce(0.0) { acc, r in
                acc + r.subScore * (specs[r.id]?.weight ?? 0)
            }
            overall = (weighted / totalWeight)
        } else {
            overall = 0
        }

        // Present the highest-evidence biomarkers first.
        let order = ["vo2Max", "hrvSDNN", "restingHR", "sleepHours",
                     "heartRateRecovery", "walkingSpeed", "steps", "exerciseMinutes"]
        results.sort { (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99) }

        return LongevityReport(
            overallScore: (overall * 10).rounded() / 10,
            biomarkers: results,
            generatedAt: Date(),
            disclaimer: "Informational wellness estimate — not a diagnosis or medical device. Consult a physician before acting on these insights."
        )
    }

    // MARK: Per-biomarker scoring

    private func makeResult(spec: Spec, input: BiomarkerInput, ageNorm: Double) -> BiomarkerResult {
        let recentMean = mean(input.recentValues)
        let baselineMean = mean(input.baselineValues)
        let baselineSD = stdDev(input.baselineValues)

        // (a) Age/sex population sub-score (0–100).
        let ageNormScore = populationSubScore(value: recentMean, norm: ageNorm, direction: spec.direction)

        // (b) Personal drift: z-score of recent mean vs 21-day baseline.
        // Positive driftSigned == "better than baseline" in longevity terms.
        var driftZ = 0.0
        if baselineSD > 0.0001 {
            driftZ = (recentMean - baselineMean) / baselineSD
        }
        let driftSigned = signForDirection(spec.direction, value: recentMean, norm: ageNorm) * driftZ

        // Nudge the population score by drift, capped at ±12 points so the
        // age-norm remains the dominant signal.
        let driftAdjustment = max(-12.0, min(12.0, driftSigned * 6.0))
        let blended = max(0.0, min(100.0, ageNormScore + driftAdjustment))

        let trend: BiomarkerTrend
        if driftSigned > 0.5 { trend = .improving }
        else if driftSigned < -0.5 { trend = .declining }
        else { trend = .stable }

        return BiomarkerResult(
            id: spec.id,
            name: spec.name,
            userValue: round1(recentMean),
            unit: spec.unit,
            baselineValue: round1(baselineMean),
            ageNorm: round1(ageNorm),
            subScore: round1(blended),
            trend: trend,
            evidenceCitation: spec.citation,
            evidenceURL: spec.url
        )
    }

    /// Maps a value against a healthy norm to a 0–100 sub-score. At the norm → ~80
    /// (a healthy target, not a perfect ceiling); meaningfully above/below scales
    /// toward 100 / 0. For `optimalRange` (sleep), distance from the ideal window drops it.
    private func populationSubScore(value: Double, norm: Double, direction: Direction) -> Double {
        switch direction {
        case .higherIsBetter:
            guard norm > 0 else { return 50 }
            let ratio = value / norm                 // 1.0 == at norm
            return clamp(80 * ratio, 0, 100)          // 1.25× norm → 100
        case .lowerIsBetter:
            guard value > 0 else { return 50 }
            let ratio = norm / value                 // at norm → 1.0
            return clamp(80 * ratio, 0, 100)
        case .optimalRange:
            // Sleep: ideal window 7.0–8.0h. Score 100 inside, decaying outside.
            let low = 7.0, high = 8.0
            if value >= low && value <= high { return 100 }
            let dist = value < low ? (low - value) : (value - high)
            return clamp(100 - dist * 22.0, 0, 100)   // ~1h off → ~78
        }
    }

    private func signForDirection(_ direction: Direction, value: Double, norm: Double) -> Double {
        switch direction {
        case .higherIsBetter: return 1.0
        case .lowerIsBetter:  return -1.0
        case .optimalRange:
            // Above the 7–8h window, "more" is not better; below, "more" is better.
            return value < 7.5 ? 1.0 : -1.0
        }
    }

    // MARK: - Normative tables (APPROXIMATIONS — require physician review)
    //
    // VO2 max: age/sex "good"-band midpoints (ml/kg/min), adapted from ACSM /
    //   Cooper Institute cardiorespiratory-fitness percentile norms.
    // Resting HR: healthy-adult reference ~60 bpm, drifting slightly with age.
    // HRV (SDNN): population declines with age; values adapted from published
    //   short-term SDNN age norms (e.g. Nunan et al. 2010 review ranges).
    // Walking speed: healthy-adult usual gait speed ~1.2–1.4 m/s, declining with age.
    // Steps / exercise minutes / HRR: guideline-based reference targets.
    // Sleep: handled via optimal-range logic (norm reference kept at 7.5h).

    private func normReference(for id: String, age: Int, sex: BiologicalSexInput) -> Double {
        switch id {
        case "vo2Max":            return vo2MaxNorm(age: age, sex: sex)
        case "hrvSDNN":           return hrvNorm(age: age)
        case "restingHR":         return 60.0
        case "sleepHours":        return 7.5
        case "heartRateRecovery": return 25.0   // healthy 1-min drop reference (≥12 abnormal-threshold; 25 = solid)
        case "walkingSpeed":      return walkingSpeedNorm(age: age)
        case "steps":             return 8000.0 // reference daily target
        case "exerciseMinutes":   return 30.0   // ~min/day meeting guidelines
        default:                  return 0
        }
    }

    private func vo2MaxNorm(age: Int, sex: BiologicalSexInput) -> Double {
        // "Good" band midpoints by age (ml/kg/min).
        func male(_ a: Int) -> Double {
            switch a {
            case ..<30: return 48
            case 30..<40: return 44
            case 40..<50: return 40
            case 50..<60: return 36
            default: return 32
            }
        }
        func female(_ a: Int) -> Double {
            switch a {
            case ..<30: return 42
            case 30..<40: return 38
            case 40..<50: return 34
            case 50..<60: return 30
            default: return 27
            }
        }
        switch sex {
        case .male:   return male(age)
        case .female: return female(age)
        case .other:  return (male(age) + female(age)) / 2.0
        }
    }

    private func hrvNorm(age: Int) -> Double {
        // Approx healthy short-term SDNN midpoints (ms), declining with age.
        switch age {
        case ..<30: return 65
        case 30..<40: return 55
        case 40..<50: return 45
        case 50..<60: return 38
        default: return 32
        }
    }

    private func walkingSpeedNorm(age: Int) -> Double {
        // Usual healthy gait speed (m/s), declining with age.
        switch age {
        case ..<40: return 1.35
        case 40..<60: return 1.30
        case 60..<70: return 1.20
        default: return 1.05
        }
    }

    // MARK: - Math helpers

    private func mean(_ xs: [Double]) -> Double {
        let v = xs.filter { $0.isFinite }
        guard !v.isEmpty else { return 0 }
        return v.reduce(0, +) / Double(v.count)
    }

    private func stdDev(_ xs: [Double]) -> Double {
        let v = xs.filter { $0.isFinite }
        guard v.count > 1 else { return 0 }
        let m = mean(v)
        let variance = v.reduce(0.0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count - 1)
        return variance.squareRoot()
    }

    private func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, x)) }
    private func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
}
