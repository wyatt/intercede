import AppKit
import ApplicationServices

@MainActor
final class ActivityMonitor: ObservableObject {
    private let usageTracker: UsageTracker
    private var timer: Timer?
    private let interval: TimeInterval = 2.0

    /// True only when the frontmost browser can't be read without Accessibility (no AppleScript
    /// support, e.g. Firefox) and that permission isn't granted. Chrome, Safari etc. use Automation.
    @Published private(set) var needsAccessibility = false
    private var status = "" {
        didSet { if status != oldValue { Log.monitor.debug("\(self.status, privacy: .public)") } }
    }
    private var lastTickDate: Date?
    private let maxTickGap: TimeInterval = 10  // cap single tick contribution
    // Time doesn't count while the Mac is asleep, the screen is locked, or the user switched away.
    private var pauseReasons: Set<String> = []

    init(usageTracker: UsageTracker) {
        self.usageTracker = usageTracker
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observeSystemState()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let host = currentHost() else {
            lastTickDate = nil  // don't credit the gap once tracking resumes
            return
        }
        let now = Date()
        let elapsed = lastTickDate.map { min(now.timeIntervalSince($0), maxTickGap) } ?? interval
        lastTickDate = now
        status = "tracking: \(host)"
        usageTracker.record(host: host, elapsed: elapsed, now: now)
    }

    private func currentHost() -> String? {
        if let reason = pauseReasons.sorted().first {
            status = "paused (\(reason))"
            return nil
        }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            status = "no frontmost app"
            return nil
        }
        guard let bundleID = frontApp.bundleIdentifier else {
            status = "no bundle ID"
            return nil
        }
        guard let browser = Browser(rawValue: bundleID) else {
            status = "not a browser: \(bundleID)"
            return nil
        }
        let host = BrowserURLParser.extractHost(appPID: frontApp.processIdentifier, browser: browser)
        needsAccessibility = host == nil && browser.appleScriptName == nil && !AccessibilityPermission.isGranted
        guard let host else {
            status = "no URL from \(browser.displayName) — check \(browser.appleScriptName == nil ? "Accessibility" : "Automation") permission"
            return nil
        }
        return host
    }

    private func observeSystemState() {
        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.willSleepNotification, pause: "sleep")
        observe(ws, NSWorkspace.didWakeNotification, resume: "sleep")
        observe(ws, NSWorkspace.screensDidSleepNotification, pause: "display off")
        observe(ws, NSWorkspace.screensDidWakeNotification, resume: "display off")
        observe(ws, NSWorkspace.sessionDidResignActiveNotification, pause: "user switched")
        observe(ws, NSWorkspace.sessionDidBecomeActiveNotification, resume: "user switched")
        let dist = DistributedNotificationCenter.default()
        observe(dist, Notification.Name("com.apple.screenIsLocked"), pause: "locked")
        observe(dist, Notification.Name("com.apple.screenIsUnlocked"), resume: "locked")
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, pause reason: String) {
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pauseReasons.insert(reason)
                self?.lastTickDate = nil
            }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, resume reason: String) {
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pauseReasons.remove(reason)
                self?.lastTickDate = nil
            }
        }
    }
}
