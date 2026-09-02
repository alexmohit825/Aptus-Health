//
//  AptusConfig.swift
//  Aptus
//
//  Central config for build-type-dependent behavior.
//  Gemini paid backend is disabled in all builds — Aptus uses Apple
//  Intelligence (on-device) or a deterministic on-device template only.
//

import Foundation

enum AptusConfig {
    /// True when this build is a public App Store install.
    /// False for Xcode debug runs and TestFlight (internal + external) builds.
    ///
    /// Detection method:
    /// - Debug builds have DEBUG defined by Xcode → not public.
    /// - TestFlight builds ship with a "sandboxReceipt" file in the app bundle → not public.
    /// - Everything else (production App Store) → public.
    static let isPublicAppStoreBuild: Bool = {
        #if DEBUG
        return false
        #else
        if let url = Bundle.main.appStoreReceiptURL,
           url.lastPathComponent == "sandboxReceipt" {
            return false
        }
        return true
        #endif
    }()

    /// Whether this build is allowed to call the paid Gemini backend.
    /// Disabled everywhere — Aptus uses Apple Intelligence (on-device) or a
    /// deterministic on-device template only. No paid cloud APIs are ever called.
    static var geminiEnabled: Bool {
        false
    }
}
