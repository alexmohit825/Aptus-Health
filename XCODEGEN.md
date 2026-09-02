# Aptus — XcodeGen Workflow (NEW)

The `Aptus.xcodeproj` is now **generated** from [`project.yml`](./project.yml) with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). This replaces all the manual
Xcode setup that used to fill the troubleshooting README — bundle IDs, "Embed & Sign",
target dependencies, capabilities, and app icons are all declared in the manifest.

## Why

Previously the "Xcode export" was just a folder of loose `.swift` files with no
`.xcodeproj`, `Info.plist`, entitlements, or asset catalog, so every capability and
embedding setting had to be wired up by hand in Xcode. `project.yml` is now the single
source of truth; the generated project is a build artifact you regenerate, not edit.

## Generate the project

```bash
cd ios
./generate.sh          # installs xcodegen if needed, then: xcodegen generate
```

Open `Aptus.xcodeproj`, set your Apple Developer Team (in `project.yml` under
`DEVELOPMENT_TEAM` or in Xcode's Signing & Capabilities), select the **Aptus** scheme
with a paired **iPhone + Apple Watch Ultra** destination, and Run.

## What the manifest defines

| Concern | Where in `project.yml` |
|---|---|
| iOS app target (`com.aptus.Aptus`) | `targets.Aptus` |
| watchOS app target (`com.aptus.Aptus.watchkitapp`) | `targets.Aptus Watch App` |
| Watch app embedded & signed in iOS app | `Aptus.dependencies` → `embed: true` |
| HealthKit + background delivery | `Aptus.entitlements.properties` |
| WatchConnectivity framework | `dependencies: - sdk: WatchConnectivity.framework` |
| HealthKit privacy strings | `Aptus.info.properties.NSHealthShareUsageDescription` |
| Local dev server over HTTP (ATS) | `NSAppTransportSecurity.NSAllowsLocalNetworking` |
| watchOS workout background mode | `WKBackgroundModes: [workout-processing]` |
| App icons | `Aptus/Resources/Assets.xcassets`, `Aptus Watch App/Resources/Assets.xcassets` |

> The 1024×1024 app-icon slot currently points at `icon-512.png` (the highest-res asset
> in `/public`). Xcode will warn but build. Drop a true 1024×1024 PNG into each
> `AppIcon.appiconset` to silence the warning.

## The WatchConnectivity bridge

[`Shared/ConnectivityManager.swift`](./Shared/ConnectivityManager.swift) is compiled
into **both** targets, so the iPhone and the Watch share one communication contract:

- **Watch → Phone**: live `BiometricSample` (heart rate, HRV) via `pushBiometric(_:)`
  (queued `transferUserInfo` + real-time `sendMessage` when reachable).
- **Phone → Watch**: `CoachingPayload` (recovery score, zone, instruction) via
  `sendCoaching(_:)` (`updateApplicationContext` + `sendMessage`).

`AptusApp` and `AptusWatchApp` both call `ConnectivityManager.shared.activate()` on
launch. `PhoneDashboardView` forwards incoming samples to `/api/coaching/realtime-step`
and pushes coaching back to the Watch after the Gemini call. `WatchWorkoutTelemetryView`
displays received coaching and streams its heart-rate value to the Phone.

## Next phase (live biometrics)

The Watch now streams **real** heart rate. [`Aptus Watch App/HealthKit/WorkoutManager.swift`](./Aptus%20Watch%20App/HealthKit/WorkoutManager.swift) runs an `HKWorkoutSession` + `HKLiveWorkoutBuilder`; each new heart-rate sample from `liveWorkoutBuilder(_:didCollectDataOf:)` is pushed to the iPhone via `ConnectivityManager.shared.pushBiometric(_:)`. `WatchWorkoutTelemetryView` exposes Start / Pause / Stop controls that drive the session. The `workout-processing` background mode is declared in `project.yml` so the sensor keeps running when the app backgrounds.
