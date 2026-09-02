//
//  ProGateView.swift
//  Aptus
//
//  Reusable Pro gating. `.proLocked("Feature name")` renders its content only when the
//  user is Pro; otherwise it shows a lock placeholder with an "Unlock with Pro" button
//  that presents `PaywallView`. Free surfaces simply don't use the modifier and stay
//  fully usable.
//
//  Usage:
//    someProSection
//        .proLocked("Pattern Detectors")
//

import SwiftUI

extension View {
    /// Gates `self` behind an active Aptus Pro subscription.
    /// - Parameter feature: user-facing name shown on the lock card.
    func proLocked(_ feature: String) -> some View {
        modifier(ProLockModifier(feature: feature))
    }
}

private struct ProLockModifier: ViewModifier {
    let feature: String
    @ObservedObject private var store = SubscriptionManager.shared
    @State private var showPaywall = false

    func body(content: Content) -> some View {
        if store.isPro {
            content
        } else {
            ProLockCard(feature: feature) { showPaywall = true }
                .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }
}

/// The placeholder shown in place of gated content. Standalone so it can also be used
/// directly (e.g. a whole-screen lock) without the modifier.
struct ProLockCard: View {
    let feature: String
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 30))
                .foregroundColor(.green)
            Text("\(feature) is a Pro feature")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Your headline scores stay free. Unlock the full breakdown, patterns, and journal with Aptus Pro.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onUnlock) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.heart.fill")
                    Text("Unlock with Pro")
                }
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(14)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}
