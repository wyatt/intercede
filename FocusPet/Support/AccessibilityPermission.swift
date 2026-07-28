import AppKit
import ApplicationServices

@MainActor
enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    static func requestIfNeeded() {
        guard !isGranted else { return }
        // Use string literal to avoid concurrency-unsafe global ref
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }
}
