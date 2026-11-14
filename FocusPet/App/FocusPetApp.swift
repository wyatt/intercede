import SwiftUI
import AppKit

@main
struct FocusPetApp: App {
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
    private var petLibrary: PetLibrary?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let usageTracker = UsageTracker()
        let activityMonitor = ActivityMonitor(usageTracker: usageTracker)
        let petdex = PetdexClient()
        let petLibrary = PetLibrary(petdexClient: petdex)
        let nudgeCoordinator = NudgeCoordinator(usageTracker: usageTracker, petLibrary: petLibrary)
        let menuBarController = MenuBarController(usageTracker: usageTracker, activityMonitor: activityMonitor, nudgeCoordinator: nudgeCoordinator, petLibrary: petLibrary)

        self.usageTracker = usageTracker
        self.petLibrary = petLibrary
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
