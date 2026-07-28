import SwiftUI
import AppKit

@main
struct FocusPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var activityMonitor: ActivityMonitor?
    private var usageTracker: UsageTracker?
    private var nudgeCoordinator: NudgeCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let usageTracker = UsageTracker()
        let nudgeCoordinator = NudgeCoordinator(usageTracker: usageTracker)
        let activityMonitor = ActivityMonitor(usageTracker: usageTracker)
        let menuBarController = MenuBarController(usageTracker: usageTracker)

        self.usageTracker = usageTracker
        self.nudgeCoordinator = nudgeCoordinator
        self.activityMonitor = activityMonitor
        self.menuBarController = menuBarController

        AccessibilityPermission.requestIfNeeded()
        activityMonitor.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
