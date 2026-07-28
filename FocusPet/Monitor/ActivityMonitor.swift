import AppKit
import ApplicationServices

@MainActor
final class ActivityMonitor {
    private let usageTracker: UsageTracker
    private var timer: Timer?

    init(usageTracker: UsageTracker) {
        self.usageTracker = usageTracker
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard AccessibilityPermission.isGranted else { return }
        guard let host = frontmostBrowserHost() else { return }
        usageTracker.record(host: host, at: Date())
    }

    private func frontmostBrowserHost() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier,
              let browser = Browser(rawValue: bundleID) else { return nil }
        return BrowserURLParser.extractHost(appPID: frontApp.processIdentifier, browser: browser)
    }
}
