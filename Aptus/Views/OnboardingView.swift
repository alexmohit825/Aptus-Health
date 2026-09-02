//
//  OnboardingView.swift
//  Aptus
//
//  First-launch flow, shown once (gated by a UserDefaults flag). Four screens:
//   1. What Aptus does
//   2. Connect Apple Health (triggers the existing HealthKitManager auth flow)
//   3. Apple Intelligence + privacy note
//   4. Done
//
//  COMPLIANCE (App Store Guideline 1.4): sets expectations up front that Aptus provides
//  informational wellness estimates, not medical advice. Privacy is stated plainly.
//

import SwiftUI

struct OnboardingView: View {
    @ObservedObject var hkManager: HealthKitManager
    /// Flipped to dismiss onboarding (persisted by the caller via the same flag).
    @Binding var isPresented: Bool

    static let completedKey = "aptus.onboarding.completed.v1"

    @State private var page = 0

    var body: some View {
        VStack {
            TabView(selection: $page) {
                welcome.tag(0)
                health.tag(1)
                intelligence.tag(2)
                done.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            controls
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .interactiveDismissDisabled(true)
        // Auto-advance from the “Connect Apple Health” page (page 1) to the next page once
        // HealthKitManager reports authorization succeeded. `isAuthorized` is a @Published
        // Bool flipped on the main thread, so this is safe to use from SwiftUI.
        .onChange(of: hkManager.isAuthorized) { newValue in
            if newValue && page == 1 {
                withAnimation { page = 2 }
            }
        }
    }

    // MARK: Pages

    private var welcome: some View {
        page(icon: "bolt.heart.fill", tint: .green,
             title: "Welcome to Aptus",
             body: "Aptus turns your Apple Watch data into on-device longevity, recovery, and fitness insights — plus recovery-informed live coaching.",
             footnote: "Informational wellness estimates — not a diagnosis or medical device.")
    }

    private var health: some View {
        page(icon: "heart.text.square.fill", tint: .red,
             title: "Connect Apple Health",
             body: "Aptus reads heart rate variability (HRV), resting heart rate, sleep, VO₂ max, and workout data from Apple Health to compute your scores. All analysis happens on your device. Your health data is never sold, shared with third parties, or used for tracking.",
             footnote: "You can review or revoke access anytime in Settings ▸ Health ▸ Data Access.")
    }

    private var intelligence: some View {
        page(icon: "sparkles", tint: .purple,
             title: "Private by design",
             body: "On supported devices, Aptus uses Apple Intelligence to write your daily insight entirely on-device. Nothing about your health is sold or used for tracking.",
             footnote: "See our Privacy Policy for the full details.",
             footnoteLinkURL: URL(string: "https://alexmohit825.github.io/aptushealth/privacy.html"))
    }

    private var done: some View {
        page(icon: "checkmark.seal.fill", tint: .green,
             title: "You're all set",
             body: "Your headline scores are free. Aptus Pro unlocks the detailed breakdowns, pattern detectors, and your private journal — with a 7-day free trial.",
             footnote: nil)
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 12) {
            if page == 1 {
                Button(action: connectHealth) {
                    primaryLabel(hkManager.isAuthorized ? "Health Connected ✓" : "Connect Apple Health")
                }
                .disabled(hkManager.isAuthorized)

                if !hkManager.isAuthorized {
                    Text("You can also continue without connecting, or manage access anytime in Settings ▸ Health ▸ Data Access.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            Button(action: advance) {
                primaryLabel(page < 3 ? "Continue" : "Get Started")
            }

            if page < 3 {
                Button("Skip") { finish() }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private func primaryLabel(_ text: String) -> some View {
        Text(text)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(14)
    }

    // MARK: Actions

    private func connectHealth() {
        // Reuse the existing manager flow (covers Phase 1–3 read types incl. hidden signals).
        // Auto-advance to the next onboarding page is handled by .onChange(of: hkManager.isAuthorized)
        // on the root view, so the reviewer is never left stuck on the “Connect Apple Health” screen.
        // If the request fails (rare), the user can retry or tap Continue / Skip.
        hkManager.requestAuthorization()
    }

    private func advance() {
        if page < 3 {
            withAnimation { page += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        withAnimation { isPresented = false }
    }

    // MARK: Reusable page layout

    private func page(icon: String, tint: Color, title: String,
                      body: String, footnote: String?,
                      footnoteLinkURL: URL? = nil) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundColor(tint)
            Text(title)
                .font(.largeTitle)
                .fontWeight(.black)
                .multilineTextAlignment(.center)
            Text(body)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if let footnote {
                VStack(spacing: 6) {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    if let footnoteLinkURL {
                        Link("Privacy Policy", destination: footnoteLinkURL)
                            .font(.footnote)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}
