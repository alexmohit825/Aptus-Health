//
//  RecoveryEngine.swift
//  Aptus
//
//  On-device Recovery Score engine (pure Swift, no UI, no HealthKit calls).
//
//  Computes a WHOOP-style daily "Recovery Score" (0–100) expressing readiness to
//  train. Each metric is compared to the user's own 14-day rolling baseline as a
//  z-score, weighted, and scaled to 0–100:
//
//      HRV 40%  |  Sleep 30%  |  Resting HR 20%  |  Respiratory Rate 10%
//
//  Zones:  Red 0–33  |  Yellow 34–66  |  Green 67–100
//
//  COMPLIANCE (App Store Guideline 1.4): informational wellness/training-readiness
//  estimate, NOT a medical device or diagnosis. "strainTarget" is a general training
//  suggestion, not medical or coaching advice.
//

import Foundation

// MARK: - Public data model

public enum RecoveryZone: String {
    case red    = "Red"
    case yellow = "Yellow"
    case green  = "Green"

    /// Hex-free semantic hint for the UI layer to map to a Color.
    public var uiHint: String {
        switch self {
        case .red: return "red"
        case .yellow: return "yellow"
        case .green: return "green"
        }
    }
}

public struct MetricResult: Identifiable {
    public let id: String
    public let name: String
    public let value: Double        // today's representative value
    public let baseline: Double     // 14-day baseline mean
    public let unit: String
    public let zScore: Double       // signed, oriented so + == better recovery
    public let weight: Double       // 0–1
    public let contribution: Double // points contributed to final score (0–100 space)
}

public struct RecoveryReport {
    public let score: Int           // 0–100
    public let zone: RecoveryZone
    public let strainTarget: String // recommended training intensity guidance
    public let perMetric: [MetricResult]
    public let generatedAt: Date
    public let disclaimer: String
}

// MARK: - Engine inputs

public struct RecoveryMetricInput {
    public let today: Double
    public let baseline: [Double]   // trailing ~14 days

    public init(today: Double, baseline: [Double]) {
        self.today = today
        self.baseline = baseline
    }

    public init(latest: Double) {
        self.today = latest
        self.baseline = [latest]
    }
}

public struct RecoveryInputs {
    public var hrv: RecoveryMetricInput?
    public var sleepHours: RecoveryMetricInput?
    public var restingHR: RecoveryMetricInput?
    public var respiratoryRate: RecoveryMetricInput?

    public init() {}
}

// MARK: - Engine

public struct RecoveryEngine {

    public init() {}

    private enum Direction { case higherIsBetter, lowerIsBetter }

    private struct Spec {
        let id: String
        let name: String
        let unit: String
        let weight: Double
        let direction: Direction
    }

    // WHOOP-style weights. HRV dominates (primary autonomic-readiness signal),
    // then sleep, then resting HR, then respiratory rate. Weights sum to 1.0.
    private let specs: [Spec] = [
        Spec(id: "hrv",        name: "Heart Rate Variability", unit: "ms",  weight: 0.40, direction: .higherIsBetter),
        Spec(id: "sleep",      name: "Sleep Duration",         unit: "hrs", weight: 0.30, direction: .higherIsBetter),
        Spec(id: "rhr",        name: "Resting Heart Rate",     unit: "bpm", weight: 0.20, direction: .lowerIsBetter),
        Spec(id: "rr",         name: "Respiratory Rate",       unit: "br/min", weight: 0.10, direction: .lowerIsBetter)
    ]

    public func computeReport(from inputs: RecoveryInputs) -> RecoveryReport {
        var metrics: [MetricResult] = []

        func handle(_ spec: Spec, _ input: RecoveryMetricInput?) {
            guard let input = input else { return }
            let baseMean = mean(input.baseline)
            let baseSD = stdDev(input.baseline)

            var z = 0.0
            if baseSD > 0.0001 {
                z = (input.today - baseMean) / baseSD
            }
            // Orient so positive z == better recovery.
            let orientedZ = spec.direction == .higherIsBetter ? z : -z

            // Map oriented z into a 0–100 per-metric score. z of 0 (== baseline)
            // maps to 60 (a "normal" day). ±2 SD spans roughly the full range.
            let perMetricScore = clamp(60 + orientedZ * 20.0, 0, 100)
            let contribution = perMetricScore * spec.weight

            metrics.append(MetricResult(
                id: spec.id,
                name: spec.name,
                value: round1(input.today),
                baseline: round1(baseMean),
                unit: spec.unit,
                zScore: round2(orientedZ),
                weight: spec.weight,
                contribution: round1(contribution)
            ))
        }

        handle(specs[0], inputs.hrv)
        handle(specs[1], inputs.sleepHours)
        handle(specs[2], inputs.restingHR)
        handle(specs[3], inputs.respiratoryRate)

        // Weighted blend with redistribution over available metrics.
        let totalWeight = metrics.reduce(0.0) { $0 + $1.weight }
        let rawScore: Double
        if totalWeight > 0 {
            let sum = metrics.reduce(0.0) { $0 + $1.contribution }
            rawScore = sum / totalWeight
        } else {
            rawScore = 0
        }

        let score = Int(rawScore.rounded())
        let zone = zoneFor(score)

        return RecoveryReport(
            score: score,
            zone: zone,
            strainTarget: strainTarget(for: zone),
            perMetric: metrics,
            generatedAt: Date(),
            disclaimer: "Informational training-readiness estimate — not a diagnosis or medical device. Listen to your body and consult a professional as needed."
        )
    }

    private func zoneFor(_ score: Int) -> RecoveryZone {
        switch score {
        case ..<34: return .red
        case 34...66: return .yellow
        default: return .green
        }
    }

    private func strainTarget(for zone: RecoveryZone) -> String {
        switch zone {
        case .green:
            return "High intensity OK — you're primed for a hard session. Zone 4–5 intervals or threshold work are on the table."
        case .yellow:
            return "Moderate day — aerobic base and tempo (Zone 2–3). Keep effort controlled; avoid maximal strain."
        case .red:
            return "Prioritize rest or light active recovery (Zone 1). Mobility, easy walking, hydration and sleep will pay off more than training."
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
    private func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
}
