import AppKit
import ApplicationServices
import Combine

final class ActivityMonitor {
    private let usageTracker: UsageTracker
    private var timer: Timer?
    private var lastHost: String?

    init(usageTracker: UsageTracker) {
        self.usageTracker = usageTracker
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard AccessibilityPermission.isGranted else { return }
        guard let host = frontmostBrowserHost() else {
            lastHost = nil
            return
        }
        lastHost = host
        usageTracker.record(host: host, at: Date())
    }

    private func frontmostBrowserHost() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier,
              let browser = Browser(rawValue: bundleID) else { return nil }

        // Get window title via AX API as fallback input for title parser
        let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)
        var windowValue: AnyObject?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue)
        var titleValue: AnyObject?
        if let window = windowValue {
            AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleValue)
        }
        let title = (titleValue as? String) ?? ""

        return BrowserURLParser.extractHost(from: title, browser: browser)
    }
}
