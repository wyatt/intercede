import AppKit
import ApplicationServices

/// Accessibility is only a fallback, for browsers without AppleScript support (Firefox); the
/// others are read through Automation. So it's requested only when it's actually needed.
///
/// Note for dev builds: ad-hoc signed apps get a new signature on every rebuild, and macOS then
/// treats an earlier grant as stale even though the switch still shows as on in System Settings.
@MainActor
enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt (if not yet decided) and opens the Accessibility settings pane.
    static func request() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary  // literal key: Swift 6-safe
        AXIsProcessTrustedWithOptions(opts)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
