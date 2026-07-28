import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let usageTracker: UsageTracker
    private var settingsWindow: NSWindow?

    init(usageTracker: UsageTracker) {
        self.usageTracker = usageTracker
        super.init()
        setupStatusItem()
        setupPopover()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = pixelPetIcon()
            button.image?.isTemplate = false
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 320)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(usageTracker: usageTracker, openSettings: { [weak self] in
                self?.openSettings()
            })
        )
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
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
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "FocusPet Settings"
        win.contentViewController = NSHostingController(rootView: SettingsView(usageTracker: usageTracker))
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = win
    }

    private func pixelPetIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.systemGreen.setFill()
        NSRect(x: 3, y: 3, width: 12, height: 12).fill()
        NSColor.black.setFill()
        NSRect(x: 5, y: 9, width: 3, height: 3).fill()
        NSRect(x: 10, y: 9, width: 3, height: 3).fill()
        NSRect(x: 6, y: 5, width: 6, height: 2).fill()
        img.unlockFocus()
        return img
    }
}

struct MenuBarPopoverView: View {
    @ObservedObject var usageTracker: UsageTracker
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("FOCUS PET")
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

            Divider()

            ScrollView {
                StatsView(usageTracker: usageTracker)
            }

            Divider()

            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .font(.system(size: 11, design: .monospaced))
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
