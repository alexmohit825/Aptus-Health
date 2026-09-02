//
//  ConnectivityManager.swift
//  Aptus  (shared by the iOS `Aptus` target and the watchOS `Aptus Watch App` target)
//
//  A real WatchConnectivity bridge, compiled into BOTH targets so the iPhone and the
//  Apple Watch share one communication contract. Data flows two ways during the
//  live-coaching phase:
//
//    Watch -> Phone : live biometric samples (heart rate, pace) during a workout.
//    Phone -> Watch : the day's WorkoutContext (recovery score + user age) at workout
//                     start, so the watch can drive LiveCoachingEngine with real inputs
//                     instead of a hard-coded band/age.
//
//  This file has NO dependency on LiveCoachingEngine / RecoveryBand — it carries only
//  primitives (recoveryScore: Int, age: Int) so `Shared/` compiles cleanly in both
//  targets without pulling the Engines/ layer into the watch. The watch view converts
//  the score to a `RecoveryBand` via `RecoveryBand.from(score:)`.
//
//  COMPLIANCE (App Store Guideline 1.4): payloads carry fitness telemetry only.
//

import Foundation
import Combine
import WatchConnectivity

// MARK: - Shared payloads (Codable so they survive the WCSession serialization layer)

/// A single live sample streamed from the Watch to the Phone during a workout.
public struct BiometricSample: Codable, Hashable {
    public enum Kind: String, Codable { case heartRate, hrv, activeEnergy, pace }
    public let kind: Kind
    public let value: Double
    public let timestamp: Date

    public init(kind: Kind, value: Double, timestamp: Date = Date()) {
        self.kind = kind
        self.value = value
        self.timestamp = timestamp
    }
}

/// A coaching result the Phone could push down to the Watch (kept for compatibility
/// with existing plumbing; the live-feed phase drives the watch from `WorkoutContext`).
public struct CoachingPayload: Codable, Hashable {
    public let recoveryScore: Int
    public let targetZone: String
    public let instruction: String
    public let adjustedPlan: String

    public init(recoveryScore: Int, targetZone: String, instruction: String, adjustedPlan: String) {
        self.recoveryScore = recoveryScore
        self.targetZone = targetZone
        self.instruction = instruction
        self.adjustedPlan = adjustedPlan
    }
}

/// The day's coaching inputs the Phone pushes to the Watch at workout start. Primitives
/// only (no RecoveryBand import) — the watch maps `recoveryScore` → band locally.
public struct WorkoutContext: Codable, Hashable {
    public let recoveryScore: Int
    public let age: Int

    public init(recoveryScore: Int, age: Int) {
        self.recoveryScore = recoveryScore
        self.age = age
    }
}

// MARK: - ConnectivityManager

/// Singleton `WCSession` bridge. Observed from SwiftUI via `@Published` so views react
/// to reachability and incoming data automatically.
public final class ConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {

    public static let shared = ConnectivityManager()

    // Connection state ----------------------------------------------------
    @Published public private(set) var isActivated = false
    @Published public private(set) var isReachable = false

    // Latest values received from the other side --------------------------
    #if os(iOS)
    /// Biometrics received from the Watch (the phone's Live Coach observes these).
    @Published public private(set) var lastSample: BiometricSample?
    @Published public private(set) var sampleCount: Int = 0
    #else
    /// Coaching received from the Phone (kept for compatibility).
    @Published public private(set) var lastCoaching: CoachingPayload?
    /// The day's workout context pushed from the Phone (recovery score + age).
    @Published public private(set) var lastWorkoutContext: WorkoutContext?
    #endif

    /// Stream of incoming biometric samples for any subscriber that wants every event.
    public let biometricStream = PassthroughSubject<BiometricSample, Never>()

    private let session: WCSession

    /// Idempotency guard so repeated `activate()` calls (phone view onAppear, watch app
    /// onAppear) don't re-assign the delegate / re-activate.
    private var hasActivated = false

    /// Throttle for pushBiometric logging so we don't flood the console.
    private var lastPushLog: Date = .distantPast

    private override init() {
        self.session = WCSession.default
        super.init()
    }

    // MARK: Activation

    /// Activate the session. Safe to call from both `AptusApp` and `AptusWatchApp`.
    public func activate() {
        guard WCSession.isSupported() else {
            // watchOS without a paired phone, or iOS without a paired watch.
            // Not an error — the app still works with local HealthKit data only.
            return
        }
        guard !hasActivated else { return }
        hasActivated = true
        session.delegate = self
        session.activate()
    }

    // MARK: Phone -> Watch

    /// Push the day's workout context (recovery score + age) to the Watch. Uses
    /// `updateApplicationContext` so the Watch always wakes to the latest inputs, then
    /// `sendMessage` for an immediate update when the Watch is reachable.
    public func sendWorkoutContext(_ context: WorkoutContext) {
        guard let data = try? JSONEncoder().encode(context) else { return }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        print("[Aptus WC] sendWorkoutContext reachable=\(session.isReachable) activated=\(session.activationState.rawValue) score=\(context.recoveryScore) age=\(context.age)")

        do {
            try session.updateApplicationContext(dict)
        } catch {
            print("[Aptus WC] updateApplicationContext threw: \(error)")
        }

        if session.isReachable {
            session.sendMessage(dict, replyHandler: nil) { _ in }
        } else {
            print("[Aptus WC] sendWorkoutContext sendMessage SKIPPED — counterpart not reachable. Context queued for next wake.")
        }
    }

    /// Push a coaching result to the Watch (compatibility path; not used by the live feed).
    public func sendCoaching(_ payload: CoachingPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        do {
            try session.updateApplicationContext(dict)
        } catch {
            print("[Aptus WC] updateApplicationContext threw: \(error)")
        }

        if session.isReachable {
            session.sendMessage(dict, replyHandler: nil) { _ in }
        }
    }

    // MARK: Watch -> Phone

    /// Stream a live biometric sample to the Phone. `transferUserInfo` is queued and
    /// battery-friendly (survives the phone being unreachable); when the phone IS
    /// reachable we additionally `sendMessage` for true real-time delivery.
    public func pushBiometric(_ sample: BiometricSample) {
        guard let data = try? JSONEncoder().encode(sample) else { return }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Throttle so a fast heart-rate stream doesn't flood the console (one per 5s).
        if Date().timeIntervalSince(lastPushLog) > 5 {
            lastPushLog = Date()
            print("[Aptus WC] pushBiometric kind=\(sample.kind.rawValue) reachable=\(session.isReachable) activated=\(session.activationState.rawValue)")
        }

        session.transferUserInfo(dict)

        if session.isReachable {
            session.sendMessage(dict, replyHandler: nil) { _ in }
        }
    }
}

// MARK: - WCSessionDelegate
//
// WCSessionDelegate is an @objc protocol. Under Swift 6 (Xcode 26) the conforming
// methods must be explicitly marked @objc so the Objective-C runtime can dispatch them.

extension ConnectivityManager {

    // Shared by both platforms.
    @objc(session:activationDidCompleteWithState:error:) public func session(_ session: WCSession,
                        activationDidCompleteWith activationState: WCSessionActivationState,
                        error: Error?) {
        DispatchQueue.main.async {
            self.isActivated = (activationState == .activated)
            self.isReachable = session.isReachable
        }
        let errDesc = error?.localizedDescription ?? "none"
        #if os(iOS)
        print("[Aptus WC] iPhone activated=\(activationState.rawValue) reachable=\(session.isReachable) paired=\(session.isPaired) watchAppInstalled=\(session.isWatchAppInstalled) err=\(errDesc)")
        #else
        print("[Aptus WC] Watch activated=\(activationState.rawValue) reachable=\(session.isReachable) companionInstalled=\(session.isCompanionAppInstalled) err=\(errDesc)")
        #endif
        if let error = error {
            print("[Aptus] WCSession activation failed: \(error.localizedDescription)")
        }
    }

    @objc public func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isReachable = session.isReachable }
    }
}

// MARK: - Incoming messages (decoded back into typed payloads)

extension ConnectivityManager {

    private func decodeSample(_ dict: [String: Any]) -> BiometricSample? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(BiometricSample.self, from: data)
    }

    private func decodeCoaching(_ dict: [String: Any]) -> CoachingPayload? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(CoachingPayload.self, from: data)
    }

    private func decodeWorkoutContext(_ dict: [String: Any]) -> WorkoutContext? {
        // Guard against a CoachingPayload (which also has recoveryScore) decoding as a
        // WorkoutContext: require the `age` key to be present and the coaching-only keys
        // to be absent.
        guard dict["age"] != nil, dict["targetZone"] == nil else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(WorkoutContext.self, from: data)
    }

    // Reachable, synchronous messages ------------------------------------
    @objc public func session(_ session: WCSession,
                        didReceiveMessage message: [String: Any]) {
        handleIncoming(message)
    }

    @objc public func session(_ session: WCSession,
                        didReceiveMessage message: [String: Any],
                        replyHandler: @escaping ([String: Any]) -> Void) {
        handleIncoming(message)
        replyHandler([:])
    }

    // Queued, guaranteed delivery ----------------------------------------
    @objc public func session(_ session: WCSession,
                        didReceiveUserInfo userInfo: [String: Any]) {
        handleIncoming(userInfo)
    }

    // Application context (latest snapshot) ------------------------------
    @objc public func session(_ session: WCSession,
                        didReceiveApplicationContext applicationContext: [String: Any]) {
        handleIncoming(applicationContext)
    }

    private func handleIncoming(_ dict: [String: Any]) {
        print("[Aptus WC] handleIncoming keys=\(dict.keys.sorted())")
        if let sample = decodeSample(dict) {
            DispatchQueue.main.async {
                self.biometricStream.send(sample)
                #if os(iOS)
                self.lastSample = sample
                self.sampleCount += 1
                #endif
            }
        } else if let context = decodeWorkoutContext(dict) {
            DispatchQueue.main.async {
                #if os(watchOS)
                self.lastWorkoutContext = context
                #endif
            }
        } else if let coaching = decodeCoaching(dict) {
            DispatchQueue.main.async {
                #if os(watchOS)
                self.lastCoaching = coaching
                #endif
            }
        }
    }
}

// MARK: - iOS-only delegate methods

#if os(iOS)
extension ConnectivityManager {
    // Required on iOS to hand the session off when a new watch is paired.
    @objc public func sessionDidBecomeInactive(_ session: WCSession) {}
    @objc public func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate for the newly paired watch.
        session.activate()
    }
}
#endif
