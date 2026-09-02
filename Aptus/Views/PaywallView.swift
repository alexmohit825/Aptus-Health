//
//  PaywallView.swift
//  Aptus
//
//  Aptus Pro paywall. Custom SwiftUI (not SubscriptionStoreView) so it renders
//  identically on the iOS 18 deployment target and gives us full control over the
//  value list + "best value" highlight. Prices, durations and the intro (trial) offer
//  are read straight from the StoreKit `Product`, so they stay authoritative and
//  localized (Guideline 3.1.2).
//
//  COMPLIANCE: single StoreKit purchase path + explicit Restore (3.1.1); clear pricing,
//  trial terms, and a cancel pointer to Settings (3.1.2).
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject private var store = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    /// Preselect yearly (best value) when available.
    @State private var selectedID: String = SubscriptionManager.ProductID.yearly

    private let valueProps: [(String, String)] = [
        ("chart.xyaxis.line", "Full Pattern Detectors & Hidden Signals"),
        ("infinity", "Longevity, Recovery & Fitness breakdowns"),
        ("book.closed.fill", "Private wellness Journal"),
        ("books.vertical.fill", "Cited evidence behind every score")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    valueList
                    planPicker
                    subscribeButton
                    footer
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Aptus Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Restore") { Task { await store.restore() } }
                }
            }
            .onChange(of: store.isPro) { _, isPro in
                if isPro { dismiss() }
            }
        }
    }

    // MARK: Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "bolt.heart.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)
            Text("Unlock your full picture")
                .font(.largeTitle)
                .fontWeight(.black)
            Text("Your headline scores stay free. Go Pro for the detailed breakdowns, on-device pattern analysis, and your private journal.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top)
    }

    private var valueList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(valueProps, id: \.1) { icon, text in
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .foregroundColor(.green)
                        .frame(width: 24)
                    Text(text)
                        .font(.subheadline)
                    Spacer()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
    }

    @ViewBuilder
    private var planPicker: some View {
        if store.products.isEmpty {
            ProgressView("Loading plans…")
                .frame(maxWidth: .infinity)
                .padding()
        } else {
            VStack(spacing: 12) {
                ForEach(store.products, id: \.id) { product in
                    planRow(product)
                }
            }
        }
    }

    private func planRow(_ product: Product) -> some View {
        let isSelected = product.id == selectedID
        let isYearly = product.id == SubscriptionManager.ProductID.yearly
        return Button {
            selectedID = product.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(isYearly ? "Yearly" : "Monthly")
                            .font(.headline)
                        if isYearly {
                            Text("BEST VALUE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }
                    Text(priceCaption(product))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.headline)
            }
            .padding()
            .background(Color(uiColor: .systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
            )
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    private var subscribeButton: some View {
        Button {
            guard let product = store.products.first(where: { $0.id == selectedID }) else { return }
            Task { await store.purchase(product) }
        } label: {
            HStack {
                if store.purchaseInFlight { ProgressView().tint(.white) }
                Text(subscribeTitle)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        .disabled(store.products.isEmpty || store.purchaseInFlight)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let msg = store.lastErrorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Text("Subscriptions auto-renew until cancelled. Manage or cancel anytime in Settings ▸ Apple ID ▸ Subscriptions. Any unused portion of a free trial is forfeited when you subscribe.")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("Aptus provides informational wellness estimates — not a diagnosis or medical device.")
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 16) {
                Link("Terms of Use",
                     destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    .font(.footnote)
                Link("Privacy Policy",
                     destination: URL(string: "https://alexmohit825.github.io/aptushealth/privacy.html")!)
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: Helpers

    private var subscribeTitle: String {
        guard let product = store.products.first(where: { $0.id == selectedID }) else {
            return "Continue"
        }
        if hasIntroTrial(product) { return "Start 7-Day Free Trial" }
        return "Subscribe"
    }

    /// Human caption per plan, including the intro trial when the product offers one.
    private func priceCaption(_ product: Product) -> String {
        let per = product.id == SubscriptionManager.ProductID.yearly ? "per year" : "per month"
        if hasIntroTrial(product) {
            return "7-day free trial, then \(product.displayPrice) \(per)"
        }
        return "\(product.displayPrice) \(per)"
    }

    private func hasIntroTrial(_ product: Product) -> Bool {
        guard let intro = product.subscription?.introductoryOffer else { return false }
        return intro.paymentMode == .freeTrial
    }
}
