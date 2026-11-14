import AppKit
import SwiftUI

/// A transparent panel in the bottom-left of the screen. It's non-activating, so clicking the pet
/// never pulls focus from the browser, and it ignores the mouse everywhere except directly over the
/// sprite or its bubble, so the rest of the stage is fully click-through.
final class SpriteOverlayWindow: NSPanel {
    private static let stageSize = NSSize(width: 560, height: 380)
    private let scene: NudgeScene
    private let stageFrame: NSRect
    private var hitTimer: Timer?
    private var lastWindowState = ""
    private var appObservers: [NSObjectProtocol] = []

    init(headline: String?, message: String, sheet: SpriteSheet?, screen: NSScreen) {
        scene = NudgeScene(headline: headline, message: message, sheet: sheet)
        let visible = screen.visibleFrame
        let frame = NSRect(
            origin: visible.origin,
            size: NSSize(width: min(Self.stageSize.width, visible.width), height: min(Self.stageSize.height, visible.height))
        )
        stageFrame = frame
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false  // NSPanel defaults to hiding when the app isn't active — it never is
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        // Fixed stage: by default NSHostingView resizes the window to fit its content, and when the
        // bubble appeared the window grew downward off-screen, taking the sprite with it.
        let hosting = FirstMouseHostingView(rootView: NudgeOverlayView(scene: scene)
            .frame(width: frame.width, height: frame.height))
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(onFinished: @escaping () -> Void) {
        orderFrontRegardless()
        Log.overlay.info("shown at \(NSStringFromRect(self.frame), privacy: .public), level \(self.level.rawValue)")
        startHitTracking()
        observeApp()
        scene.enter { [weak self] in
            guard let self else { return }
            self.stopHitTracking()
            self.appObservers.forEach(NotificationCenter.default.removeObserver)
            self.appObservers = []
            self.orderOut(nil)
            Log.overlay.info("finished")
            onFinished()
        }
    }

    func dismiss() {
        scene.exit(reason: "dismiss()")
    }

    /// Tears down immediately, e.g. when a new nudge must replace this one.
    func abort(reason: String) {
        scene.abort(reason: reason)
    }

    private func observeApp() {
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSApplication.didBecomeActiveNotification,
                     NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            appObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                Log.overlay.info("app: \(note.name.rawValue, privacy: .public)")
            })
        }
    }

    // Polls the cursor rather than using tracking areas, which never fire while the window
    // ignores mouse events.
    private func startHitTracking() {
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouseHandling() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hitTimer = timer
    }

    private func stopHitTracking() {
        hitTimer?.invalidate()
        hitTimer = nil
        ignoresMouseEvents = true
    }

    private func updateMouseHandling() {
        logWindowStateChanges()
        if frame != stageFrame {
            Log.overlay.error("window moved to \(NSStringFromRect(self.frame), privacy: .public); restoring stage frame")
            setFrame(stageFrame, display: true)
        }
        // If something ordered the window out from under us, end the nudge so the next one can show.
        guard isVisible else {
            scene.abort(reason: "window no longer visible")
            return
        }

        let mouse = NSEvent.mouseLocation
        let point = NSPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY)
        let overPet = scene.hitRects.contains { $0.contains(point) }
        if ignoresMouseEvents == overPet {
            ignoresMouseEvents = !overPet
        }
    }
}

extension SpriteOverlayWindow {
    fileprivate func logWindowStateChanges() {
        let state = "visible=\(isVisible) occluded=\(!occlusionState.contains(.visible)) activeSpace=\(isOnActiveSpace) onScreen=\(screen != nil) frame=\(NSStringFromRect(frame)) ignoresMouse=\(ignoresMouseEvents)"
        guard state != lastWindowState else { return }
        lastWindowState = state
        Log.overlay.info("window \(state, privacy: .public)")
    }
}

/// The app is never active while a nudge is up, so the first click must reach SwiftUI directly.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
