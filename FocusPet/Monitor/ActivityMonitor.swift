import AppKit
import ApplicationServices

@MainActor
final class ActivityMonitor: ObservableObject {
    private let usageTracker: UsageTracker
    private var timer: Timer?

    @Published var debugStatus: String = "starting…"
    private(set) var lastBrowserPID: pid_t?
    private(set) var lastBrowser: Browser?

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
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            debugStatus = "no frontmost app"
            return
        }
        guard let bundleID = frontApp.bundleIdentifier else {
            debugStatus = "no bundle ID"
            return
        }
        guard let browser = Browser(rawValue: bundleID) else {
            debugStatus = "not a browser: \(bundleID)"
            return
        }
        lastBrowserPID = frontApp.processIdentifier
        lastBrowser = browser
        guard let host = BrowserURLParser.extractHost(appPID: frontApp.processIdentifier, browser: browser) else {
            debugStatus = "URL extract failed (\(browser.rawValue))"
            return
        }
        debugStatus = "tracking: \(host)"
        usageTracker.record(host: host, at: Date())
    }
}
