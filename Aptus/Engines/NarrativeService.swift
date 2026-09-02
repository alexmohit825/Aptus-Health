//
//  NarrativeService.swift
//  Aptus
//
//  Generates a wellness-framed narrative insight from the computed LongevityReport
//  and RecoveryReport.
//
//  PRIMARY  : Apple Intelligence on-device via the Foundation Models framework
//             (iOS 26+, Apple Intelligence-capable device). FREE, private, no network.
//  FALLBACK : the existing Gemini Cloud Run backend (/api/coaching/daily) for older
//             devices / iOS < 26, or if on-device generation fails.
//  LAST RESORT: a deterministic on-device template so the UI always has content.
//
//  Callers use a single async interface and never know which path ran.
//
//  PRIVACY (documented honestly):
//   - On-device path sends NOTHING anywhere — generation happens on the Neural Engine.
//   - Gemini fallback POSTs COMPUTED METRICS (scores + a few biomarker values), NOT raw
//     HealthKit samples, to the user's own Cloud Run backend.
//
//  COMPLIANCE (App Store Guideline 1.4): informational wellness estimate, not a
//  diagnosis or medical device.
//
//  API VERIFICATION: the Foundation Models API used below (SystemLanguageModel.default,
//  .availability → .available/.unavailable(reason), LanguageModelSession(instructions:),
//  session.respond(to:generating:) → Response<T>.content, @Generable/@Guide) was validated
//  against current Apple developer documentation. All of it is compiled ONLY when the
//  FoundationModels SDK is present AND iOS 26+ at runtime, so the app still builds/runs on
//  iOS 18+. See PHASE2_INTEGRATION.md for the "verify against Apple docs at build" TODO.
//

import Foundation
import Network

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Public model (UI-facing, framework-agnostic)

public struct NarrativeInsight: Identifiable, Equatable {
    public enum Source: String {
        case appleIntelligence = "On-device (Apple Intelligence)"
        case gemini = "Cloud (Gemini)"
        case template = "On-device (template)"
    }

    public let id = UUID()
    public let headline: String
    public let body: String
    public let bullets: [String]
    public let source: Source
    public let disclaimer: String

    public static func == (lhs: NarrativeInsight, rhs: NarrativeInsight) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Insight focus (per-screen differentiation)

/// Which domain a detail screen is showing. The Recovery and Longevity detail views
/// each derive their own insight from a single shared AI narrative so the two screens
/// never display identical text (distinct headline + lead + bullets), while still
/// keeping one AI generation per refresh.
public enum InsightFocus {
    case longevity
    case recovery
}

// MARK: - Typed errors

/// Typed failure reasons for the narrative pipeline. Callers never see these thrown
/// from `narrative(for:recovery:)` (it always degrades to a template), but they are
/// recorded on `lastError` for debugging and drive the retry decision internally.
public enum NarrativeError: Error, Equatable {
    case appleIntelligenceUnavailable
    case network
    case rateLimited
    case decode
    case noModel
}

// MARK: - Cache model (Codable snapshot of a NarrativeInsight)

/// `NarrativeInsight` is intentionally not `Codable` (its `id` is a fresh UUID), so we
/// persist a flat Codable mirror keyed by a metrics hash + calendar day.
private struct CachedNarrative: Codable {
    let headline: String
    let body: String
    let bullets: [String]
    let sourceRaw: String
    let disclaimer: String
    let metricsHash: String
    let dayKey: String

    var insight: NarrativeInsight {
        NarrativeInsight(
            headline: headline,
            body: body,
            bullets: bullets,
            source: NarrativeInsight.Source(rawValue: sourceRaw) ?? .template,
            disclaimer: disclaimer
        )
    }

    init(insight: NarrativeInsight, metricsHash: String, dayKey: String) {
        self.headline = insight.headline
        self.body = insight.body
        self.bullets = insight.bullets
        self.sourceRaw = insight.source.rawValue
        self.disclaimer = insight.disclaimer
        self.metricsHash = metricsHash
        self.dayKey = dayKey
    }
}

// MARK: - Reachability (Network framework — system, not third-party)

/// Lightweight wrapper over `NWPathMonitor`. `isOnline` starts optimistically `true`
/// so a not-yet-settled monitor never wrongly forces the offline path on first launch.
final class NetworkReachability {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.aptus.reachability")
    private let lock = NSLock()
    private var _isOnline = true

    var isOnline: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isOnline
    }

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self._isOnline = (path.status == .satisfied)
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}

// MARK: - Guided-generation schema (Foundation Models, iOS 26+ only)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedInsight {
    @Guide(description: "A short, encouraging wellness headline of at most 8 words. No medical claims.")
    var headline: String

    @Guide(description: "2–3 sentence informational insight about the user's longevity and recovery estimates. Wellness framing only — never a diagnosis, risk prediction, or medical advice.")
    var body: String

    @Guide(description: "2 to 4 short, actionable, non-medical lifestyle suggestions.")
    var bullets: [String]
}
#endif

// MARK: - Service

public final class NarrativeService {

    /// The user's own Gemini Cloud Run backend (fallback path).
    private let backendBaseURL: String
    private let session: URLSession
    private let reachability = NetworkReachability()
    private let defaults: UserDefaults
    private let cacheKey = "aptus.narrative.cache.v1"

    /// Last failure reason encountered on the AI/network paths. Kept for debugging;
    /// never surfaced as a thrown error to callers.
    public private(set) var lastError: NarrativeError?

    public init(backendBaseURL: String = "https://aptus-api-904011161284.us-central1.run.app",
                session: URLSession = .shared,
                defaults: UserDefaults = .standard) {
        self.backendBaseURL = backendBaseURL
        self.session = session
        self.defaults = defaults
    }

    /// Synchronous, no-network read of the last successful insight IF it still matches
    /// today's metrics (same metrics hash and calendar day). Callers show this instantly
    /// on launch/refresh, then kick off `narrative(...)` in the background to refresh.
    public func cachedInsight(for longevity: LongevityReport,
                              recovery: RecoveryReport) -> NarrativeInsight? {
        guard let data = defaults.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(CachedNarrative.self, from: data) else {
            return nil
        }
        // Material-change check: metrics hash must match. Day match is a softer signal
        // (a same-day cache with an identical hash is fresh enough to show immediately).
        guard cached.metricsHash == metricsHash(longevity: longevity, recovery: recovery),
              cached.dayKey == Self.dayKey() else {
            return nil
        }
        return cached.insight
    }

    /// Single entry point. Tries on-device first, then Gemini, then a template.
    /// Declared `throws` for API symmetry; in practice it always resolves to a
    /// NarrativeInsight (template last-resort) rather than throwing. On any AI/Gemini
    /// success the result is persisted to the on-device cache.
    public func narrative(for longevity: LongevityReport,
                          recovery: RecoveryReport) async throws -> NarrativeInsight {
        lastError = nil

        // 1) On-device Apple Intelligence (iOS 26+, capable device).
        if let onDevice = await generateOnDevice(longevity: longevity, recovery: recovery) {
            store(onDevice, longevity: longevity, recovery: recovery)
            return onDevice
        }

        // 2) Gemini backend fallback — only if we appear to be online AND this build is
        //    allowed to call the paid backend (i.e., not a public App Store install).
        //    Offline or public build → skip straight to cache-or-template so we never
        //    burn a doomed network round-trip or a chargeable Gemini call.
        if reachability.isOnline && AptusConfig.geminiEnabled {
            if let gemini = await generateViaGeminiWithRetry(longevity: longevity, recovery: recovery) {
                store(gemini, longevity: longevity, recovery: recovery)
                return gemini
            }
        } else if !reachability.isOnline {
            lastError = .network
        }

        // 4) Deterministic on-device template — the UI ALWAYS has content.
        return templateInsight(longevity: longevity, recovery: recovery)
    }

    // MARK: Per-screen focus

    /// Derives a domain-specific insight from a shared base narrative so the Recovery
    /// and Longevity detail screens show distinct text. The shared AI body is kept (with
    /// a domain-specific lead sentence prepended); the headline and bullets are composed
    /// from the relevant report. When `base` is nil a domain template is used instead.
    public func focusedInsight(_ focus: InsightFocus,
                               longevity: LongevityReport,
                               recovery: RecoveryReport,
                               base: NarrativeInsight?) -> NarrativeInsight {
        switch focus {
        case .longevity:
            let score = Int(longevity.overallScore.rounded())
            let headline: String
            if longevity.overallScore >= 80 {
                headline = "Strong Longevity Signal"
            } else if longevity.overallScore < 60 {
                headline = "Room to Strengthen Longevity"
            } else {
                headline = "Longevity Holding Steady"
            }
            let top = longevity.biomarkers
                .sorted { $0.subScore > $1.subScore }
                .prefix(2)
                .map { $0.name }
                .joined(separator: " and ")
            let lead = top.isEmpty
                ? "Your estimated Longevity Score is \(score)/100."
                : "Your estimated Longevity Score is \(score)/100, with \(top) among your strongest markers."
            let opportunities = longevity.biomarkers
                .sorted { $0.subScore < $1.subScore }
                .prefix(2)
                .map { "\($0.name) is your biggest opportunity to move the needle." }
            let body = lead + " " + (base?.body ?? "Consistency across sleep, activity, and recovery is what moves these markers over time. This is an informational estimate, not a diagnosis.")
            let bullets = opportunities + Array((base?.bullets ?? []).prefix(2))
            return NarrativeInsight(
                headline: headline,
                body: body,
                bullets: bullets,
                source: base?.source ?? .template,
                disclaimer: Self.disclaimer
            )

        case .recovery:
            let score = recovery.score
            let headline: String
            if recovery.zone == .green {
                headline = "Primed and Ready"
            } else if recovery.zone == .red {
                headline = "Prioritize Recovery"
            } else {
                headline = "Steady As You Go"
            }
            let lead = "Your Recovery is \(score)% and in the \(recovery.zone.rawValue) zone."
            let body = lead + " " + (base?.body ?? "Match today's effort to your readiness and protect sleep tonight. This is an informational estimate, not a diagnosis.")
            var bullets = [recovery.strainTarget]
            bullets.append(contentsOf: (base?.bullets ?? []).prefix(2))
            return NarrativeInsight(
                headline: headline,
                body: body,
                bullets: Array(bullets),
                source: base?.source ?? .template,
                disclaimer: Self.disclaimer
            )
        }
    }

    // MARK: Cache helpers

    private func store(_ insight: NarrativeInsight,
                       longevity: LongevityReport,
                       recovery: RecoveryReport) {
        // Never cache the template — it's a last-resort fallback, not a "successful" insight.
        guard insight.source != .template else { return }
        let cached = CachedNarrative(
            insight: insight,
            metricsHash: metricsHash(longevity: longevity, recovery: recovery),
            dayKey: Self.dayKey()
        )
        if let data = try? JSONEncoder().encode(cached) {
            defaults.set(data, forKey: cacheKey)
        }
    }

    private static func dayKey() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Stable hash over the computed metrics that actually drive the narrative. Values
    /// are rounded so trivial jitter doesn't invalidate the cache ("materially changed").
    private func metricsHash(longevity: LongevityReport, recovery: RecoveryReport) -> String {
        var parts: [String] = []
        parts.append("L\(Int(longevity.overallScore.rounded()))")
        parts.append("R\(recovery.score)")
        parts.append("Z\(recovery.zone.rawValue)")
        for b in longevity.biomarkers.sorted(by: { $0.id < $1.id }) {
            parts.append("\(b.id):\(Int(b.userValue.rounded()))")
        }
        // Deterministic across launches — Swift's `String.hashValue` is per-process
        // seeded, so it would break a persisted cache. The joined string is stable and
        // small enough to store directly as the key.
        return parts.joined(separator: "|")
    }

    // MARK: Primary — Apple Intelligence

    private func generateOnDevice(longevity: LongevityReport,
                                  recovery: RecoveryReport) async -> NarrativeInsight? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            lastError = .appleIntelligenceUnavailable
            return nil
        }

        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        default:
            // Device ineligible / Apple Intelligence off / model still downloading.
            lastError = .appleIntelligenceUnavailable
            return nil
        }

        let instructions = Self.systemPrompt
        let prompt = Self.userPrompt(longevity: longevity, recovery: recovery)

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: GeneratedInsight.self)
            let g = response.content
            let bullets = g.bullets.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return NarrativeInsight(
                headline: g.headline,
                body: g.body,
                bullets: bullets,
                source: .appleIntelligence,
                disclaimer: Self.disclaimer
            )
        } catch {
            // Any on-device failure → let the caller fall through to Gemini.
            lastError = .noModel
            return nil
        }
        #else
        // FoundationModels SDK not present at build time (older Xcode) → skip.
        lastError = .appleIntelligenceUnavailable
        return nil
        #endif
    }

    // MARK: Fallback — Gemini backend

    /// Wraps the single Gemini request in a bounded retry with exponential backoff.
    /// Retries ONLY transient failures (`.network`, `.rateLimited`) up to 2 times at
    /// ~1s then ~2s. Permanent failures (non-429 4xx, unparseable 200) return `nil`
    /// immediately without retrying. Always returns `nil` on ultimate failure so the
    /// caller can fall through to cache-or-template.
    private func generateViaGeminiWithRetry(longevity: LongevityReport,
                                            recovery: RecoveryReport) async -> NarrativeInsight? {
        let maxRetries = 2
        var attempt = 0
        while true {
            do {
                return try await performGeminiRequest(longevity: longevity, recovery: recovery)
            } catch let error as NarrativeError {
                lastError = error
                // Only .network / .rateLimited are transient and worth retrying.
                let retryable = (error == .network || error == .rateLimited)
                guard retryable, attempt < maxRetries else { return nil }
                attempt += 1
                let backoffNanos = UInt64(1 << (attempt - 1)) * 1_000_000_000 // 1s, then 2s
                try? await Task.sleep(nanoseconds: backoffNanos)
            } catch {
                lastError = .network
                return nil
            }
        }
    }

    /// One Gemini round-trip. Throws a typed `NarrativeError` so the retry wrapper can
    /// decide whether to retry; returns `nil` only when the 200 body has no usable text.
    private func performGeminiRequest(longevity: LongevityReport,
                                      recovery: RecoveryReport) async throws -> NarrativeInsight? {
        guard let url = URL(string: "\(backendBaseURL)/api/coaching/daily") else {
            throw NarrativeError.network
        }

        // Only COMPUTED metrics are sent — never raw HealthKit samples.
        let payload = geminiPayload(longevity: longevity, recovery: recovery)
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            throw NarrativeError.decode
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // URLSession transport failures (timeout, connection lost, DNS) are transient.
            throw NarrativeError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw NarrativeError.network
        }

        switch http.statusCode {
        case 200:
            break
        case 429:
            throw NarrativeError.rateLimited          // transient — retry
        case 500...599:
            throw NarrativeError.network              // transient — retry
        default:
            // Other 4xx (and any non-200 <500) are permanent client errors — no retry.
            throw NarrativeError.decode
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NarrativeError.decode               // unparseable 200 — permanent
        }

        let recoveryStatus = json["recoveryStatus"] as? [String: Any]
        let intensity = json["recommendedIntensity"] as? [String: Any]
        let plan = json["planAdjustment"] as? [String: Any]

        let recoveryDesc = recoveryStatus?["description"] as? String
        let intensityDesc = intensity?["description"] as? String
        let targetZone = intensity?["targetHeartRateZone"] as? String
        let adjustedPlan = plan?["adjustedPlan"] as? String

        // Require at least some usable text to count this as a success.
        guard recoveryDesc != nil || intensityDesc != nil else { return nil }

        var bullets: [String] = []
        if let z = targetZone { bullets.append("Today's target: \(z)") }
        if let p = adjustedPlan { bullets.append("Suggested session: \(p)") }

        return NarrativeInsight(
            headline: "Today's Insight",
            body: [recoveryDesc, intensityDesc].compactMap { $0 }.joined(separator: " "),
            bullets: bullets,
            source: .gemini,
            disclaimer: Self.disclaimer
        )
    }

    // MARK: Last resort — deterministic template (on-device, no network)

    private func templateInsight(longevity: LongevityReport,
                                 recovery: RecoveryReport) -> NarrativeInsight {
        let longScore = Int(longevity.overallScore.rounded())
        let recZone = recovery.zone.rawValue
        let topDrivers = longevity.biomarkers
            .sorted { $0.subScore > $1.subScore }
            .prefix(2)
            .map { $0.name }
            .joined(separator: " and ")

        let body = "Your estimated Longevity Score is \(longScore)/100 and today's Recovery is in the \(recZone) zone. "
            + (topDrivers.isEmpty ? "" : "\(topDrivers) are among your strongest markers. ")
            + "This is an informational estimate to help you notice trends, not a diagnosis."

        var bullets = [recovery.strainTarget]
        if longevity.overallScore < 60 {
            bullets.append("Small, consistent habit changes tend to move these markers most.")
        } else {
            bullets.append("Keep doing what's working — consistency compounds.")
        }

        return NarrativeInsight(
            headline: recovery.zone == .green ? "Primed and Ready" : (recovery.zone == .red ? "Prioritize Recovery" : "Steady As You Go"),
            body: body,
            bullets: bullets,
            source: .template,
            disclaimer: Self.disclaimer
        )
    }

    // MARK: Prompt + payload builders

    private static let disclaimer = "Informational wellness estimate — not a diagnosis or medical device. Consult a professional before acting on these insights."

    private static let systemPrompt = """
    You are a supportive wellness guide inside a longevity and fitness app. You explain
    on-device health ESTIMATES in plain, encouraging language. Strict rules:
    - This is informational wellness content, NOT medical advice, diagnosis, or risk prediction.
    - Never claim to detect, diagnose, treat, or predict disease.
    - Use words like "estimated" and "insight". Be concise and positive.
    - Suggestions must be general lifestyle habits (sleep, movement, consistency), not medical.
    """

    private static func userPrompt(longevity: LongevityReport, recovery: RecoveryReport) -> String {
        var lines: [String] = []
        lines.append("Longevity Score (estimate): \(Int(longevity.overallScore.rounded()))/100")
        lines.append("Recovery Score (estimate): \(recovery.score)/100, zone \(recovery.zone.rawValue)")
        lines.append("Recommended training focus today: \(recovery.strainTarget)")
        lines.append("Key longevity biomarkers (value / age-norm / sub-score):")
        for b in longevity.biomarkers.prefix(6) {
            lines.append("  - \(b.name): \(b.userValue) \(b.unit) / norm \(b.ageNorm) / \(Int(b.subScore.rounded()))")
        }
        lines.append("Write a short headline, a 2–3 sentence insight, and 2–4 general suggestions.")
        return lines.joined(separator: "\n")
    }

    /// Maps computed reports into the Gemini `/api/coaching/daily` payload shape.
    private func geminiPayload(longevity: LongevityReport, recovery: RecoveryReport) -> [String: Any] {
        func longevityValue(_ id: String) -> Double? {
            longevity.biomarkers.first { $0.id == id }?.userValue
        }
        func recoveryValue(_ id: String) -> Double? {
            recovery.perMetric.first { $0.id == id }?.value
        }

        return [
            "hrv": recoveryValue("hrv") ?? longevityValue("hrvSDNN") ?? 70.0,
            "rhr": recoveryValue("rhr") ?? longevityValue("restingHR") ?? 55.0,
            "sleepDuration": recoveryValue("sleep") ?? longevityValue("sleepHours") ?? 7.5,
            "sleepEfficiency": 90.0,
            "stressLevel": 35,
            "acuteTrainingLoad": 300,
            "chronicTrainingLoad": 285,
            "fatigueIndex": max(0, 100 - recovery.score),
            "svO2": 74,
            "vo2Max": longevityValue("vo2Max") ?? 48.0,
            "heartRateRecovery": longevityValue("heartRateRecovery") ?? 30.0
        ]
    }
}
