# iOS & WatchOS Native Client Codebase

> **NEW — XcodeGen workflow (recommended).** The project is now generated from
> [`project.yml`](./project.yml). Run `./generate.sh` (or `xcodegen generate`) to
> produce `Aptus.xcodeproj` with both targets, capabilities, embedding, and app
> icons pre-configured — no manual Xcode setup. See [`XCODEGEN.md`](./XCODEGEN.md)
> for the full guide and the new `Shared/ConnectivityManager.swift` WatchConnectivity
> bridge. The manual-setup notes below remain as a fallback reference.

This directory contains the complete, high-fidelity iOS and WatchOS native Swift client files. They are structured precisely for easy integration into an Xcode project.

## Project Structure

```text
ios/
├── README.md                              <- Integrating & building instructions
├── Aptus/
│   ├── AptusApp.swift                     <- SwiftUI Main App entry point (iOS)
│   ├── HealthKit/
│   │   └── HealthKitManager.swift         <- Core HealthKit querying layer (HRV, Sleep, VO2 Max, etc.)
│   └── Views/
│       └── PhoneDashboardView.swift       <- Beautiful iOS iPhone client dashboard UI
└── Aptus Watch App/
    ├── AptusWatchApp.swift                <- SwiftUI Watch App entry point
    └── Views/
        └── WatchWorkoutTelemetryView.swift <- WatchOS workout telemetry live dashboard UI
```

---

## Getting Started in Xcode

Follow these steps to run the iOS & WatchOS clients:

### 1. Create a New Xcode Project
1. Open **Xcode** and select **File > New > Project**.
2. Select **iOS > App** or **Watch App** (with companion iOS app).
3. Name your project `Aptus` (matching the target and class names).
4. Set the Interface to **SwiftUI** and Language to **Swift**.

### 2. Import the Source Files
Simply drag and drop the folders from this directory into your Xcode project navigator:
* Drag the files from `Aptus/` to your iOS App group.
* Drag the files from `Aptus Watch App/` to your Watch App target group.
* Ensure you check **"Copy items if needed"** and select the correct targets.

### 3. Configure HealthKit Capabilities
1. Click on the root `Aptus` project in the left sidebar.
2. Under **Signing & Capabilities**, click `+ Capability` and search for **HealthKit**.
3. Under the newly added HealthKit section, check **Background Delivery** (if background syncing is desired).

### 4. Update the Privacy Info.plist Description Keys
Open your iOS target's `Info.plist` (or select the target, go to **Info** tab, and expand **Custom iOS Target Properties**) and add the following keys with description messages:
* `Privacy - Health Share Usage Description`
  > *"We need to sync your Heart Rate Variability, Sleep, Resting Heart Rate, and VO2 Max data to analyze your training recovery."*

### 5. Point to Your Cloud/Dev Server
In `PhoneDashboardView.swift`, verify or update the `serverURL` variable to point to your live running server endpoint:
```swift
let serverURL = "https://ais-dev-to6bwfg55gkonhk43ukpce-284658191881.us-east5.run.app"
```
---

## Troubleshooting: "Debug Session Ended with Code 9: Killed"

If Xcode displays a message like **"The debug session ended with code 9: killed"** (or *Terminated due to signal 9 / SIGKILL*), it means the iOS or watchOS operating system forcefully terminated your app's process. This is a very common development occurrence and is caused by one of three things:

1. **Re-running from Xcode (Most Common)**: 
   * When you click the **Run** button ($\mathscr{H}$ + R) in Xcode while the app is already open and running on your device, Xcode has to terminate the existing active process to install and launch the new build. 
   * This generates a **Code 9: Killed** message because Xcode sent a SIGKILL to the old process. This is completely harmless and normal!

2. **Watchdog Launch Timeout**:
   * Apple watchOS has an aggressive security watchdog. If your Watch App takes longer than **15–20 seconds** to launch (e.g., if the debugger is attached and paused, or if it is stuck performing slow database/network operations on startup), watchOS assumes the app is frozen and kills it with Signal 9.
   * *How to solve*: Run the app in "Release" mode or run it without the debugger attached (**Product > Perform Action > Run without Building/Debugging**).

3. **watchOS Memory/CPU Limits**:
   * Apple Watches have extremely tight memory limits. If the app allocates too much memory at once, watchOS will instantly kill it with Signal 9.

---

## Troubleshooting: "I Erased the Apps and Now I Can't Find Them" (The Xcode Scheme Trap)

If you deleted the Aptus apps from your phone and watch to clear old caches, and now rebuild but cannot find them, you are likely falling into the **Xcode Scheme Trap**:

### 1. Check your Active Xcode Scheme (Top-Left Dropdown)
Next to the Play/Stop buttons in the very top-left of Xcode, there is a dropdown selector for the active **Scheme** and **Destination**:
* **If you select the "Aptus Watch App" scheme**: Xcode compiles and installs **ONLY** the Watch App directly to your Apple Watch. It completely skips installing the companion iOS app to your iPhone! That is why you cannot find the iOS native app on your iPhone.
* **If you select the "Aptus" scheme**: Xcode compiles **BOTH** the iOS app and the Watch app, installs the iOS app on your iPhone, and then installs the Watch companion app.
* **HOW TO FIX**: 
  1. Change the active Scheme to **`Aptus`** (the main target, not the Watch App target).
  2. Select your device: **"iPhone 17 Pro + Paired Apple Watch Ultra 2"** (or your physical devices).
  3. Click **Run**. This will put the native app back on your iPhone!

### 2. Finding the Native iOS App on your iPhone
Once built under the `Aptus` scheme, if it doesn't appear on your home screen:
* **Check the App Library**: Swipe all the way to the rightmost screen on your iPhone to access the App Library. Search for **"Aptus"** there. Xcode-installed apps sometimes skip the Home Screen by default.
* **Spotlight Search**: Swipe down from the middle of any Home screen and search for **"Aptus"**.
* **VPN & Device Management**: If you are using a personal Apple ID for signing, go to **Settings > General > VPN & Device Management** on your iPhone. Tap your Developer App certificate and select **"Trust"**, otherwise iOS will prevent the app from appearing or launching.

### 3. "Xcode says it's already running, but I can't see it!"
If Xcode states the app is already running, it is actively in memory. If your Watch or Phone screen went blank, it is in the background.
* On Apple Watch: Double-press the **Digital Crown** (or click the side button) to open the **App Switcher (Dock)**. Swipe through the apps to find the active **Aptus** session running right there!

---

## Troubleshooting: Xcode AI Coding Assistant / API Key Issues

If you added your Google Gemini API key inside Xcode to use an AI Coding Assistant (such as Xcode 16's built-in Swift Assist, GitHub Copilot, Cursor, or an Xcode Gemini extension) and it is not working, check the following:

1. **Verify Extension Compatibility**:
   * Xcode's built-in **Swift Assist** and **Predictive Code Completion** run on Apple's local on-device models and Apple's cloud servers—they do not use third-party Google Gemini API keys directly.
   * If you are using a third-party Xcode extension (like *Copilot for Xcode*, *Cursor*, or *XcodeLLM*), check the extension's specific preferences tab to ensure your key is pasted cleanly without any leading/trailing spaces or hidden characters.
2. **Network/Proxy Blocks**:
   * Xcode runtimes and simulators are sandboxed. If you are behind a strict network firewall, Xcode extensions may be blocked from connecting to external APIs (`generativelanguage.googleapis.com`). Ensure Xcode has full internet access.
3. **Key Validity**:
   * Double-check that your Gemini API key is active by running a quick curl test or testing it in the Google AI Studio playground.

Now, you can build and run on your iPhone Simulator or physical iPhone + Apple Watch!

---

## Troubleshooting: Companion Watch App Not Showing in iPhone "Watch" App

If you do not see **Aptus** under the **"Available Apps"** section in the Watch app on your iPhone, or if Xcode throws installation errors, it is always caused by one of three configuration mismatches in Xcode. Here is exactly how to resolve them:

### A. The "Do Not Embed" vs. "Embed & Sign" Issue (The Root Cause)
When you build an iOS app with an Apple Watch companion, **the iPhone app acts as the delivery vehicle**. The watchOS binary must be physically embedded inside the iOS app bundle so that iOS can transfer it to your Watch.
1. If you select **"Do Not Embed"**, the iPhone app compiles without the Watch app inside it. Your phone will have no idea a Watch app exists.
2. If you see **only** *"Do Not Embed"* and *"Embed Without Signing"*, Xcode is blocking the critical **"Embed & Sign"** option. This happens because your **Signing Teams** or **Bundle Identifiers** do not match.
3. **How to fix:**
   * In Xcode, click on the root project folder in the left sidebar to open the settings.
   * Go to **Signing & Capabilities** for **BOTH** targets: the main `Aptus` (iOS) target and the `Aptus Watch App` target.
   * Ensure that **both** targets are using the **exact same Apple Development Team** and that **"Automatically manage signing"** is checked on both.
   * Once they are signed with the same Team, go back to the iOS target's **General** tab, scroll down to **Frameworks, Libraries, and Embedded Content**, and you will now be able to select **"Embed & Sign"** for your Watch App target.

### B. Mismatched Bundle Identifiers (Why Xcode locks the field)
Apple enforces a strict security relationship between a parent iOS app and its companion Watch app.
1. **The Rule**: The Watch app's Bundle ID **must** be prefixed by the iOS app's Bundle ID.
   * If iOS App Bundle ID is: `com.Alex.Aptus`
   * The Watch App Bundle ID must be: `com.Alex.Aptus.watchkitapp` (or `com.Alex.Aptus.watchapp`).
2. **Why Xcode won't let you change it**:
   * If Xcode is showing a red warning or blocking you from changing the identifier, it is because **"Automatically manage signing"** is actively trying to generate a profile for a mismatched ID or a Team that is not configured.
   * **How to fix:**
     * Go to the `Aptus Watch App` target -> **General** tab.
     * Manually change the **Bundle Identifier** to exactly match your iOS App's bundle identifier with `.watchkitapp` appended as a suffix.
     * If Xcode errors out, temporarily **uncheck** "Automatically manage signing" in the *Signing & Capabilities* tab of the Watch App target, update the Bundle Identifier in the *General* tab, and then **re-check** "Automatically manage signing". Xcode will then resolve the correct provisioning certificates matching the prefix of the parent.

### C. Check iPhone & Watch Pairing and Active Run Destination
If your devices are not actively paired or selected, iOS won't transfer the app.
1. **Verify Pairing**: Open the built-in Apple **"Watch"** app on your iPhone. If you can see your Apple Watch Ultra 2 listed, custom watch faces are syncable, and sync data is working, they are paired.
2. **Xcode Run Destination**: In Xcode's top toolbar, click on the active run destination (the dropdown next to the Play/Run button).
   * Do not select just *"iPhone 17 Pro"*.
   * Select **"iPhone 17 Pro + Paired Apple Watch Ultra 2"** (or your physical devices if plugged in).
   * Click **Run** ($ \mathscr{H} $ + R). This forces Xcode to build both architectures and push them onto the respective devices.
3. **Enable Developer Mode on watchOS**:
   * On your Apple Watch, go to **Settings > Privacy & Security > Developer Mode** and switch it **ON**. Restart the Watch and confirm trust. (This is mandatory on watchOS 9+).

---

## Troubleshooting: Watch App Icon Missing & Locating the Active App

If you built the app and Xcode indicates it is running, but you cannot find it on your Apple Watch, or if it has no icon, here is exactly why this happens and how to find/fix it:

### 1. "The app is running, but I can't find it on my Apple Watch!"
When you launch the app directly from Xcode, it runs as an active debug process. If you pressed the Digital Crown, or the watch went to sleep, the app is running in the background. Because it might not have an icon yet, it is extremely easy to miss.

Here are the two fastest ways to open it:
* **The App Switcher (Fastest)**: Double-click the **Digital Crown** (or press the side button depending on your watchOS version) on your Apple Watch to open the **App Switcher (Dock)**. Swipe left or right through your active apps; you will see **Aptus** running right there! Tap it to bring it to the foreground.
* **The App List View**: In the default "Honeycomb" grid view, an app without a custom icon displays as a generic, plain wireframe circle that is hard to spot. To find it, press the Digital Crown to go to the Home screen, scroll to the bottom (or long-press the screen) and tap **List View**. Scroll alphabetically to **"A"** and tap **Aptus**.

### 2. "Why is there no App Icon on my Apple Watch?"
The iPhone app and the Apple Watch app are separate binary targets with their own distinct **Asset Catalogs** in Xcode. The watch does not automatically inherit the phone's launcher icon unless it is explicitly added to the Watch App's asset bundle.

**How to add the App Icon to the Watch App in Xcode:**
1. In Xcode's left sidebar, expand the **Aptus Watch App** folder.
2. Click on **`Assets.xcassets`** (or `Assets`) inside that folder.
3. Click on the **`AppIcon`** asset slot.
4. Drag and drop your icon image files into the designated size placeholders:
   * You can use the high-resolution PNGs generated by our project! Look inside the project's `/public` folder for **`icon-192.png`** or **`icon-512.png`** and drag them into the corresponding asset slots.
   * *Tip:* For watchOS 9+, Xcode prefers a single 1024x1024 px high-resolution App Store icon, which it automatically scales for all watch face and notification sizes. Drag **`icon-512.png`** or a 1024x1024 px PNG into the Mac/App Store asset slot, and Xcode will handle the rest!

---

## Troubleshooting: "Aptus Watch App.app couldn't be opened because there is no such file"

If Xcode throws this error during compilation:
`The file “Aptus Watch App.app” couldn’t be opened because there is no such file.`

This means the main **Aptus** iOS target is attempting to bundle/embed the Watch App, but the Watch App binary does not exist in your build outputs yet because it was either skipped during build or built with mismatched settings.

Here is exactly how to resolve this:

### 1. Force Watch App as a Target Dependency (Highly Recommended)
You must tell Xcode to compile the Watch App *first* before it builds the iPhone app.
1. Select the root **Aptus** project folder in the top left of Xcode's sidebar.
2. In the central pane, select the **Aptus** target (under the "Targets" section, this is the main iOS app).
3. Go to the **Build Phases** tab.
4. Expand the **Dependencies** section (usually near the top).
5. Click the **`+`** button, select **`Aptus Watch App`** from the list, and click **Add**.
   * *Now, Xcode will guarantee that the Watch App compiles successfully before trying to package the iPhone app.*

### 2. Enable Watch App in the Active Build Scheme
Make sure the Watch App is not unchecked in your active run configurations:
1. In Xcode's top toolbar, click on your active Scheme dropdown (labeled **Aptus**) and select **Edit Scheme...**.
2. Click on **Build** in the left sidebar of the scheme popup.
3. Verify that both **Aptus** and **Aptus Watch App** targets are listed.
4. Ensure that the checkbox under the **"Build"** column (and specifically for **Run**) is checked for both targets. If unchecked, check it.

### 3. Clear Stale Build Cache (DerivedData)
Sometimes Xcode caches incomplete compilation states.
1. In Xcode, press **Command + Shift + K** ($\mathscr{H}$ + $\mathscr{Shift}$ + K) or go to **Product > Clean Build Folder**.
2. Close Xcode completely.
3. Open your Mac's Terminal and run this command to delete the temporary build files:
   ```bash
   rm -rf /Users/robertapolk/Library/Developer/Xcode/DerivedData/Aptus-*
   ```
4. Reopen Xcode, make sure you have the **`Aptus`** scheme and your paired phone/watch selected, and press **Run** ($\mathscr{H}$ + R).

---

## Where is the "Choose Your Destination" Dropdown/Menu in Xcode?

In Xcode, there is no separate "Destination tab" inside the settings screens. Instead, the **Destination selector** is a dropdown button in the **main top toolbar** of Xcode. Here is exactly how to find it and select your device:

1. **Look at the Very Top Toolbar of Xcode**:
   At the very top center-left of the Xcode window (just to the right of the `▶` (Run) and `■` (Stop) buttons), you will see two dropdown menus separated by a small arrow or space.

2. **The First Dropdown is the Scheme**:
   * It usually has a project blueprint icon or app icon followed by the name **`Aptus`** or **`Aptus Watch App`**.
   * Make sure this is set to **`Aptus`** (the main app target).

3. **The Second Dropdown is your Destination**:
   * Directly to the right of the Scheme dropdown, you will see a second dropdown.
   * By default, it might say something like **`Any iOS Device (arm64)`**, **`iPhone 17 Pro`**, or the name of a specific simulator/device.
   * **Click this dropdown** to open the list of available devices, simulators, and paired pairs.

4. **Select the Paired Device Pair**:
   * Scroll through the dropdown menu.
   * Under the **iOS Simulators** or **Devices** list, look for a paired device line that matches both your phone and watch. It will look like:
     * **`iPhone 17 Pro + Paired Apple Watch Ultra 3`** (Simulator)
     * OR **`Your iPhone Name + Paired Apple Watch Ultra`** (Physical Devices)
   * Select this pair. Now, when you press the `▶` (Run) button, Xcode will compile and launch the app on both your iPhone and Watch simultaneously!

---

## Troubleshooting: "I Do Not See Paired Devices in the Dropdown"

If your destination dropdown does not show a paired iPhone + Apple Watch option, here is exactly why and how to fix it based on whether you are using **Simulators** or **Physical Devices**:

### Scenario A: You are using Simulators (Mac Virtual Devices)
If you only see individual simulators (like `iPhone 17 Pro` and `Apple Watch Ultra`) but no combined **`iPhone + Paired Apple Watch`** entry, Xcode hasn't created the virtual pair yet. Here is how to create one in 30 seconds:

1. **Open Devices & Simulators**:
   * In the macOS menu bar at the top of your screen, click **Window > Devices and Simulators** (or press **Command + Shift + 2**).
2. **Add a Paired Simulator**:
   * Click on the **Simulators** tab at the top.
   * Click the small **`+` (plus)** button in the bottom-left corner of the window.
3. **Configure the Pair**:
   * **Device Name**: Give it a name (e.g., `iPhone 17 Pro with Watch Ultra`).
   * **Device Type**: Select `iPhone 17 Pro` (or your preferred iPhone).
   * **OS Version**: Select the latest iOS version.
   * **Companion**: Check the box for **"Watch Companion"**.
   * **Watch Type**: Select `Apple Watch Ultra 2` (or your preferred Watch).
   * **OS Version**: Select the latest watchOS version.
4. **Click "Create"**:
   * Close the Devices & Simulators window.
   * Go back to your main Xcode window, click the Destination dropdown again, and your brand-new **`iPhone 17 Pro + Paired Apple Watch Ultra`** simulator will now be right there ready to use!

### Scenario B: You are using Physical Devices (Your Real iPhone & Watch)
For physical hardware, Xcode **does not** list them as a combined "Phone + Watch" text string. Instead:

1. **Select Your Physical iPhone**:
   * In the destination dropdown, select your **physical iPhone's name** under the **"Devices"** section (not Simulators).
2. **Xcode Handles the Rest Behind the Scenes**:
   * When you select your physical iPhone as the build target and press **Run**, Xcode automatically detects the paired Apple Watch connected to it and installs the Watch companion app over Bluetooth/Wi-Fi automatically.
3. **Important Checklists for Physical Hardware**:
   * **Screen Unlocked**: Make sure both your iPhone and Apple Watch are unlocked and on your wrist/desk.
   * **Trust This Computer**: If prompted, tap **"Trust"** on both your iPhone screen and Apple Watch screen.
   * **Developer Mode (Mandatory)**:
     * **iPhone**: Go to *Settings > Privacy & Security > Developer Mode*, turn it **ON**, and restart your phone.
     * **Apple Watch**: Go to *Settings > Privacy & Security > Developer Mode*, turn it **ON**, and restart your watch.
   * **Same Wi-Fi Network**: Make sure your Mac, iPhone, and Apple Watch are all connected to the exact same Wi-Fi network and have Bluetooth turned ON.

---

## Troubleshooting: "Aptus Watch App.app couldn't be opened because there is no such file" + "Embed Without Signing" Locked

If you are seeing **"Embed Without Signing"** (or "Do Not Embed") as the only options in the main iOS target's settings, the minus (`-`) button under *Frameworks, Libraries, and Embedded Content* does nothing, and your build fails with the error:
`The file “Aptus Watch App.app” couldn’t be opened because there is no such file.`

This happens because the watchOS app was added as an **external file reference** (a static file path) instead of a **Target Product**. Because Xcode treats it as a static file, it locks the embedding settings to "Embed Without Signing" (disabling standard signing) and tries to copy it before compiling the watchOS target, which crashes. Furthermore, Xcode locks the item in the list (making the `-` button do nothing) if it is still active as a compiled dependency or linked binary.

Here is the exact, step-by-step solution to break this lock and configure modern watchOS companion embedding in Xcode 15/16:

### Step 1: Remove the Locked Reference from the Left Project Sidebar (Navigator)
If the minus (`-`) button under *Frameworks, Libraries, and Embedded Content* is disabled or does nothing, you must delete the file reference from your project's main file tree:
1. Look at the **Project Navigator** (the file tree on the far-left sidebar of Xcode).
2. Scroll to locate **`Aptus Watch App.app`** (it usually has a yellow folder or white app icon and is located either at the root or under a `Products` group).
3. Right-click **`Aptus Watch App.app`** and click **Delete**.
4. In the pop-up modal, select **"Remove Reference"** (do NOT choose Move to Trash, just select "Remove Reference").
   * *This instantly breaks the file reference lock, clearing it from your General settings page.*

### Step 2: Remove Stale Linking under Build Phases
We must make sure Xcode is not trying to link the Watch App binary as a library:
1. Select the root **Aptus** project folder in Xcode's left sidebar, and select the **Aptus** (iOS App) target.
2. Go to the **Build Phases** tab.
3. Expand the **Link Binary With Libraries** section.
4. If **`Aptus Watch App.app`** or any WatchApp-related binary is listed there, select it and click the **`-` (minus)** button at the bottom of that list to remove it. (A watchOS app is a separate executable, not a library, and should never be linked here).

### Step 3: Link the Watch Target as a "Target" (The Modern Way)
Now, instead of dragging a pre-built file, we will add the watchOS App target itself:
1. Go back to the **General** tab of your **Aptus** (iOS App) target.
2. Scroll down to the **Frameworks, Libraries, and Embedded Content** section.
3. Click the **`+` (plus)** button.
4. In the sheet that pops up, do **not** select any file from your disk. Instead, look at the very top of the list under **Targets** and select the **`Aptus Watch App`** target.
5. Click **Add**.
6. Under the **Embed** column for this newly added item, Xcode will now fully unlock the **"Embed & Sign"** option! Select **"Embed & Sign"**.

### Step 4: Ensure Target Dependencies are Ordered
1. Go back to the **Build Phases** tab of your **Aptus** (iOS App) target.
2. Expand the **Dependencies** section near the top.
3. Click the **`+` (plus)** button, select the **`Aptus Watch App`** target, and click **Add**.
   * *This guarantees that Xcode compiles the Watch App first, ensuring the `.app` binary is ready and waiting when the iOS app packages it.*

### Step 5: Clean and Run
1. Press **Command + Shift + K** ($\mathscr{H}$ + $\mathscr{Shift}$ + K) or go to **Product > Clean Build Folder**.
2. Select your paired device/simulator from the scheme destination menu.
3. Press **Command + R** ($\mathscr{H}$ + R) or click the **Run** (`▶`) button. The project will now compile both targets flawlessly!






