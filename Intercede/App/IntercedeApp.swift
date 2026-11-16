import SwiftUI
import AppKit

@main
struct IntercedeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window opened manually via MenuBarController with shared UsageTracker
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private(set) var activityMonitor: ActivityMonitor?
    private var usageTracker: UsageTracker?
    private var nudgeCoordinator: NudgeCoordinator?
    private var patronLibrary: PatronLibrary?
    private var browserBridge: BrowserBridge?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LegacyMigration.run()  // before anything reads settings or usage data

        let usageTracker = UsageTracker()
        let activityMonitor = ActivityMonitor(usageTracker: usageTracker)
        let patronLibrary = PatronLibrary()
        let browserBridge = BrowserBridge()
        browserBridge.start()
        NativeHostInstaller.install()
        let nudgeCoordinator = NudgeCoordinator(usageTracker: usageTracker, patronLibrary: patronLibrary, browserBridge: browserBridge)
        let menuBarController = MenuBarController(usageTracker: usageTracker, activityMonitor: activityMonitor, nudgeCoordinator: nudgeCoordinator, patronLibrary: patronLibrary)

        self.usageTracker = usageTracker
        self.patronLibrary = patronLibrary
        self.browserBridge = browserBridge
        self.nudgeCoordinator = nudgeCoordinator
        self.activityMonitor = activityMonitor
        self.menuBarController = menuBarController

        AccessibilityPermission.requestIfNeeded()
        activityMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        browserBridge?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
