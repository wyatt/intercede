import AppKit
import ApplicationServices

@MainActor
enum AccessibilityPermission {
    static var isGranted: Bool {
        // AXIsProcessTrustedWithOptions returns false for ad-hoc signed dev builds
        // even when permission is granted. Verify by attempting a real AX read on
        // another process — notTrusted (-25242) is the definitive "no permission" error.
        if AXIsProcessTrustedWithOptions(nil) { return true }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return false
        }
        let element = AXUIElementCreateApplication(pid)
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        // kAXErrorNotTrusted = -25242, kAXErrorAPIDisabled = -25211
        return result.rawValue != -25242 && result.rawValue != -25211
    }

    static func requestIfNeeded() {
        guard !isGranted else { return }
        // Use string literal to avoid concurrency-unsafe global ref
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }
}
