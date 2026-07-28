import AppKit
import SwiftUI

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let usageTracker: UsageTracker

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
            rootView: MenuBarPopoverView(usageTracker: usageTracker)
        )
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // Programmatically drawn pixel-art pet icon (16x16)
    private func pixelPetIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size)
        img.lockFocus()

        // Body
        NSColor.systemGreen.setFill()
        NSRect(x: 3, y: 3, width: 12, height: 12).fill()
        // Eyes
        NSColor.black.setFill()
        NSRect(x: 5, y: 9, width: 3, height: 3).fill()
        NSRect(x: 10, y: 9, width: 3, height: 3).fill()
        // Smile
        NSRect(x: 6, y: 5, width: 6, height: 2).fill()

        img.unlockFocus()
        return img
    }
}

struct MenuBarPopoverView: View {
    @ObservedObject var usageTracker: UsageTracker
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("FOCUS PET")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                Spacer()
                Button(action: { showSettings = true }) {
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

            // Footer: quit
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}
