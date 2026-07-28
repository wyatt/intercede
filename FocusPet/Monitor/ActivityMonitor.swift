import AppKit
import ApplicationServices

@MainActor
final class ActivityMonitor: ObservableObject {
    private let usageTracker: UsageTracker
    private var timer: Timer?

    @Published var debugStatus: String = "starting…"
    @Published var lastAXDump: String = ""
    private(set) var lastBrowserPID: pid_t?
    private(set) var lastBrowser: Browser?
    private var lastTickDate: Date?
    private let maxTickGap: TimeInterval = 10  // cap single tick contribution

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
            lastTickDate = nil
            return
        }
        lastBrowserPID = frontApp.processIdentifier
        lastBrowser = browser
        guard let host = BrowserURLParser.extractHost(appPID: frontApp.processIdentifier, browser: browser) else {
            let dump = BrowserURLParser.dumpAXTree(appPID: frontApp.processIdentifier)
            lastAXDump = dump
            let dest = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop/focuspet-ax-debug.txt")
            try? dump.write(to: dest, atomically: true, encoding: .utf8)
            debugStatus = "extract failed — raw: \(BrowserURLParser.rawAddressBarValue(appPID: frontApp.processIdentifier) ?? "nil")"
            return
        }
        let now = Date()
        let elapsed = lastTickDate.map { min(now.timeIntervalSince($0), maxTickGap) } ?? 2.0
        lastTickDate = now
        debugStatus = "tracking: \(host)"
        usageTracker.record(host: host, elapsed: elapsed)
    }
}
