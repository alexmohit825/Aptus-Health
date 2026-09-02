//
//  AptusApp.swift
//  Aptus
//

import SwiftUI

@main
struct AptusApp: App {
    // Single shared HealthKit + engine host. HealthKitManager owns the on-device
    // LongevityEngine and RecoveryEngine and exposes their reports. Authorization
    // continues to flow through this existing manager.
    @StateObject private var healthKitManager = HealthKitManager()

    // First-launch onboarding is shown once, gated by a UserDefaults flag.
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: OnboardingView.completedKey)

    var body: some Scene {
        WindowGroup {
            PhoneDashboardView(hkManager: healthKitManager)
                .onAppear {
                    // Start StoreKit 2: load products, restore entitlement, listen for updates.
                    SubscriptionManager.shared.start()

                    if healthKitManager.narrativeService == nil {
                        healthKitManager.narrativeService = NarrativeService()
                        // Regenerate the narrative if reports already exist.
                        healthKitManager.refreshNarrative()
                    }
                }
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView(hkManager: healthKitManager, isPresented: $showOnboarding)
                }
        }
    }
}
