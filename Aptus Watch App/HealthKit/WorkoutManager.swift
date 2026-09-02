//
//  WorkoutManager.swift
//  Aptus Watch App
//
//  A live workout session that streams real heart-rate samples to the iPhone over
//  ConnectivityManager during an active workout, and exposes the live HR to the watch
//  UI so `LiveCoachingEngine` can be driven by genuine sensor data instead of the
//  +/- simulation.
//
//    HKWorkoutSession     -> keeps the heart-rate sensor active (incl. background).
//    HKLiveWorkoutBuilder -> collects live HR / energy / distance and emits updates.
//
//  Each new heart-rate sample is pushed to ConnectivityManager.shared.pushBiometric(_:)
//  so the Phone's Live Coach receives real telemetry.
//
//  COMPLIANCE (App Store Guideline 1.4): telemetry only — not medical monitoring.
//

import Foundation
import Combine
import HealthKit
import WatchConnectivity

@MainActor
final class WorkoutManager: NSObject, ObservableObject {

    // Published state for the SwiftUI view --------------------------------
    @Published private(set) var isRunning = false
    @Published private(set) var heartRate: Double = 0
    @Published private(set) var activeEnergy: Double = 0   // kcal
    @Published private(set) var distance: Double = 0       // meters
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var lastError: String?

    // HealthKit -----------------------------------------------------------
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    // Timer for the on-screen elapsed clock --------------------------------
    private var timer: Timer?

    // MARK: - Authorization

    /// Request read/write authorization for the workout + quantity types we use.
    /// Called from `start()` (and can be triggered up-front from the view).
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            lastError = "HealthKit unavailable on this device."
            return
        }

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        ]

        let typesToRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        } catch {
            lastError = "HealthKit auth failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Start / Pause / Stop

    private var isStarting = false

    func start() async {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        // End any previous session/builder before starting a new one — watchOS
        // allows only one active workout session at a time.
        if let previous = session {
            try? await previous.end()
        }
        session = nil
        builder = nil

        await requestAuthorization()

        // Explicitly confirm write authorization. If sharing isn't granted, the
        // builder silently enters an opaque Error(7) state instead of a clear
        // permission error — so check it here and bail with an actionable message.
        let workoutStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        guard workoutStatus == .sharingAuthorized else {
            lastError = "HealthKit workout write permission not granted. Watch Settings → Privacy & Security → Health → Aptus → turn all on."
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        do {
            let startDate = Date()
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            session?.delegate = self

            // The live builder comes from the session (the standalone
            // HKLiveWorkoutBuilder(healthStore:configuration:device:) initializer is gone
            // on recent watchOS).
            builder = session?.associatedWorkoutBuilder()
            builder?.delegate = self
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                           workoutConfiguration: configuration)

            // Modern watchOS flow (WWDC "Track workouts with HealthKit"):
            // prepare() → countdown → startActivity → beginCollection.
            try await session?.prepare()
            try? await Task.sleep(nanoseconds: 3_000_000_000)   // 3-second sensor countdown
            try await session?.startActivity(with: startDate)

            // Give the session a moment to actually transition to .running before
            // we begin collection — calling beginCollection before the session has
            // settled wedges the builder into an unrecoverable Error(7) state.
            let settleDeadline = Date().addingTimeInterval(5)
            while session?.state != .running, Date() < settleDeadline {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            try await builder?.beginCollection(at: startDate)

            isRunning = true
            startTimer()
        } catch {
            let ns = error as NSError
            let msg = "Failed [\(ns.domain) #\(ns.code)] state=\(session?.state.rawValue ?? -1): \(error.localizedDescription)"
            lastError = msg
            print("APTUS start(): \(msg)")
            isRunning = false
            if let s = session { try? await s.end() }
            session = nil
            builder = nil
        }
    }

    func pause() async {
        guard isRunning else { return }
        try? await session?.pause()
    }

    func resume() async {
        try? await session?.resume()
    }

    func stop() async {
        guard isRunning else { return }
        timer?.invalidate()
        timer = nil

        // Stop the session first so the builder collects final metrics, then end
        // collection, finalize the workout into a permanent HKWorkout sample, and end.
        try? await session?.stopActivity(with: Date())
        try? await builder?.endCollection(at: Date())
        if let builder = builder {
            try? await builder.finishWorkout()
        }
        try? await session?.end()

        session = nil
        builder = nil
        isRunning = false
        heartRate = 0
    }

    // MARK: - Elapsed clock

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsedSeconds += 1 }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        Task { @MainActor in
            if toState == .ended { self.isRunning = false }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = "Workout session error: \(error.localizedDescription)"
            self.isRunning = false
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate  (where the live HR actually arrives)

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            for type in collectedTypes {
                guard let quantityType = type as? HKQuantityType else { continue }

                switch quantityType {
                case HKQuantityType.quantityType(forIdentifier: .heartRate):
                    // Latest heart-rate sample (count/min).
                    if let stats = workoutBuilder.statistics(for: quantityType) {
                        let unit = HKUnit.count().unitDivided(by: .minute())
                        if let value = stats.mostRecentQuantity()?.doubleValue(for: unit) {
                            self.heartRate = value
                            // Stream the real HR to the iPhone over WatchConnectivity.
                            ConnectivityManager.shared.pushBiometric(
                                BiometricSample(kind: .heartRate, value: value)
                            )
                        }
                    }

                case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                    if let stats = workoutBuilder.statistics(for: quantityType) {
                        let kcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                        self.activeEnergy = kcal
                    }

                case HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning):
                    if let stats = workoutBuilder.statistics(for: quantityType) {
                        let m = stats.sumQuantity()?.doubleValue(for: .meter()) ?? 0
                        self.distance = m
                    }

                default:
                    break
                }
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // No-op: we don't surface workout events (laps, pauses) in the UI yet.
    }
}
