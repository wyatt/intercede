import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let usageTracker: UsageTracker
    private let activityMonitor: ActivityMonitor
    private let nudgeCoordinator: NudgeCoordinator
    private let patronLibrary: PatronLibrary
    private var settingsWindow: NSWindow?

    init(usageTracker: UsageTracker, activityMonitor: ActivityMonitor, nudgeCoordinator: NudgeCoordinator, patronLibrary: PatronLibrary) {
        self.usageTracker = usageTracker
        self.activityMonitor = activityMonitor
        self.nudgeCoordinator = nudgeCoordinator
        self.patronLibrary = patronLibrary
        super.init()
        setupStatusItem()
        setupPopover()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.toolTip = "Intercede"
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 340)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(
                usageTracker: usageTracker,
                activityMonitor: activityMonitor,
                openSettings: { [weak self] in self?.openSettings() },
                testNudge: { [weak self] in self?.nudgeCoordinator.triggerTest() }
            )
        )
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func openSettings() {
        popover.performClose(nil)
        if let win = settingsWindow, win.isVisible {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Intercede Settings"
        win.contentViewController = NSHostingController(rootView: SettingsView(usageTracker: usageTracker, patronLibrary: patronLibrary))
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = win
    }

    /// Pixel-art saint: halo, head, and shoulders with a cross cut out. A template image, so
    /// macOS tints it for light/dark menu bars and the highlighted state.
    static func menuBarIcon() -> NSImage {
        let rows = [
            "..................",
            "......######......",
            ".....#......#.....",
            "......######......",
            "..................",
            ".......####.......",
            "......######......",
            "......######......",
            "......######......",
            ".......####.......",
            "..................",
            ".....########.....",
            "...############...",
            "..######..######..",
            "..####......####..",
            "..######..######..",
            "..######..######..",
            "..................",
        ]
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" {
                    NSRect(x: x, y: y, width: 1, height: 1).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuBarPopoverView: View {
    @ObservedObject var usageTracker: UsageTracker
    @ObservedObject var activityMonitor: ActivityMonitor
    let openSettings: () -> Void
    let testNudge: () -> Void
    @State private var axGranted = AccessibilityPermission.isGranted

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("INTERCEDE")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.1))

            if !axGranted {
                Button(action: {
                    AccessibilityPermission.requestIfNeeded()
                    axGranted = AccessibilityPermission.isGranted
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text("Accessibility permission needed")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .background(Color.orange.opacity(0.1))
            }

            // Debug status row
            HStack(spacing: 4) {
                Circle()
                    .fill(activityMonitor.debugStatus.hasPrefix("tracking") ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text(activityMonitor.debugStatus)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.05))

            Divider()

            ScrollView {
                StatsView(usageTracker: usageTracker)
            }

            Divider()

            HStack {
                Button("Test Nudge") { testNudge() }
                    .font(.system(size: 10, design: .monospaced))
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .font(.system(size: 11, design: .monospaced))
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear { axGranted = AccessibilityPermission.isGranted }
    }
}
