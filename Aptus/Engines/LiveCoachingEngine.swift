//
//  LiveCoachingEngine.swift
//  Aptus  (SHARED — add to BOTH the iOS app target and the Watch App target)
//
//  Pure-Swift live-coaching logic used during a workout on both phone and watch.
//  It combines today's Recovery Score strain target with the live heart rate to
//  produce a real-time coaching cue: whether to push, hold, or ease off.
//
//  This is the recovery-informed coaching layer — the app's differentiator. It has
//  NO UIKit / HealthKit / SwiftUI dependencies so it compiles for watchOS and iOS.
//
//  COMPLIANCE (App Store Guideline 1.4): coaching cues are fitness guidance, NOT
//  medical advice.
//

import Foundation

// MARK: - Recovery band (mirrors RecoveryEngine zones without importing UI types)

public enum RecoveryBand: String {
    case green  = "Green"
    case yellow = "Yellow"
    case red    = "Red"

    /// Maps a 0–100 recovery score to a band (matches RecoveryEngine thresholds).
    public static func from(score: Int) -> RecoveryBand {
        switch score {
        case ..<34: return .red
        case 34...66: return .yellow
        default: return .green
        }
    }
}

// MARK: - HR zones

public struct HRZones {
    public let maxHR: Double
    /// Upper bound (bpm) of each zone 1…5 as a fraction of maxHR.
    public let bounds: [Double] // length 5, ascending

    /// Standard %-of-max zones: Z1 <60, Z2 60–70, Z3 70–80, Z4 80–90, Z5 90–100.
    public init(age: Int) {
        let mhr = Double(max(30, 220 - age))
        self.maxHR = mhr
        self.bounds = [0.60, 0.70, 0.80, 0.90, 1.00].map { $0 * mhr }
    }

    public func zone(for hr: Double) -> Int {
        guard hr > 0 else { return 1 }
        for (i, upper) in bounds.enumerated() where hr <= upper { return i + 1 }
        return 5
    }

    public func range(for zone: Int) -> (low: Double, high: Double) {
        let idx = max(1, min(5, zone)) - 1
        let low = idx == 0 ? bounds[0] * 0.5 : bounds[idx - 1]
        let high = bounds[idx]
        return (low.rounded(), high.rounded())
    }
}

// MARK: - Coaching output

public enum CoachingAction: String {
    case push   = "PUSH"
    case hold   = "HOLD"
    case ease   = "EASE OFF"
    case rest   = "RECOVER"
}

public struct CoachingCue {
    public let action: CoachingAction
    public let message: String        // short, watch-friendly
    public let currentZone: Int       // 1–5
    public let targetZoneLow: Int     // recommended min zone for today
    public let targetZoneHigh: Int    // recommended max zone for today
    public let colorHint: String      // "green" | "yellow" | "red" | "blue"
}

// MARK: - Engine

public struct LiveCoachingEngine {

    public init() {}

    /// Today's recommended HR-zone band derived from the recovery band.
    /// Green → hard work allowed (Z3–Z5); Yellow → moderate (Z2–Z3); Red → easy (Z1–Z2).
    public func targetZoneRange(for band: RecoveryBand) -> (low: Int, high: Int) {
        switch band {
        case .green:  return (3, 5)
        case .yellow: return (2, 3)
        case .red:    return (1, 2)
        }
    }

    /// Produces a live coaching cue from the recovery band, live HR, and the user's zones.
    public func cue(recovery band: RecoveryBand, heartRate: Double, zones: HRZones) -> CoachingCue {
        let currentZone = zones.zone(for: heartRate)
        let target = targetZoneRange(for: band)

        let action: CoachingAction
        let message: String
        let color: String

        if currentZone < target.low {
            action = .push
            message = "Target Zone \(target.low)"
            color = "blue"
        } else if currentZone > target.high {
            if band == .red {
                action = .rest
                message = "Low recovery — ease effort"
                color = "red"
            } else {
                action = .ease
                message = "Ease off to Zone \(target.high)"
                color = "yellow"
            }
        } else {
            action = .hold
            message = "In target zone — hold pace"
            color = "green"
        }

        return CoachingCue(
            action: action,
            message: message,
            currentZone: currentZone,
            targetZoneLow: target.low,
            targetZoneHigh: target.high,
            colorHint: color
        )
    }

    /// One-line summary of today's plan for display before/at the start of a workout.
    public func planSummary(for band: RecoveryBand) -> String {
        let t = targetZoneRange(for: band)
        switch band {
        case .green:  return "Optimal recovery — estimated target effort is Zones \(t.low)–\(t.high)."
        case .yellow: return "Moderate recovery — estimated target effort is aerobic Zones \(t.low)–\(t.high)."
        case .red:    return "Low recovery — suggest light activity in Zones \(t.low)–\(t.high). Rest supports recovery."
        }
    }
}
