import AppKit
import SwiftUI

final class SpriteOverlayWindow: NSWindow {
    private var hostingView: NSHostingView<NudgeOverlayView>?

    init(message: String, petImage: NSImage?, screen: NSScreen) {
        let screenFrame = screen.frame
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        let overlayView = NudgeOverlayView(
            message: message,
            petImage: petImage,
            onDismiss: { [weak self] in
                self?.close()
            }
        )
        let hosting = NSHostingView(rootView: overlayView)
        hosting.frame = screenFrame
        contentView = hosting
        self.hostingView = hosting
    }

    func show() {
        makeKeyAndOrderFront(nil)
    }
}
